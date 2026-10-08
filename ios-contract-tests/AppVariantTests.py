#!/usr/bin/env python3
"""Synthetic identity/profile checks; never reads configured credentials."""
import copy
import importlib.util
import json
import os
import plistlib
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('prepare_ios_variant', ROOT / 'scripts/prepare_ios_variant.py')
VARIANT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VARIANT)


def profile(bundle='de.frankysfarm.driver'):
    value = {'Name': 'Synthetic Canary Profile', 'UUID': 'synthetic-profile-uuid',
            'TeamIdentifier': ['T82KC2CU9V'], 'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=30),
            'Entitlements': {'application-identifier': 'T82KC2CU9V.' + bundle,
                             'com.apple.developer.team-identifier': 'T82KC2CU9V',
                             'get-task-allow': False}}
    if bundle == 'app.mise.driver': value['Entitlements']['aps-environment'] = 'production'
    return value


class AppVariantTests(unittest.TestCase):
    def test_preview_ci_environment_preserves_selected_build_and_explicit_fixtures(self):
        environ = {**os.environ, 'DRIVER_APP_VARIANT': 'mise', 'DRIVER_BACKEND_TARGET': 'protected_preview'}
        script = "const v=require('./scripts/app-variant.cjs');const r=v.resolveVariant(...process.argv.slice(1));process.stdout.write(JSON.stringify({variant:r,config:v.capacitorIdentity(r)}));"
        selected = json.loads(subprocess.check_output(['node', '-e', script], cwd=ROOT, env=environ))
        preview = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'mise', 'DRIVER_BACKEND_TARGET': 'protected_preview'})
        self.assertEqual(selected['variant'], preview)
        VARIANT.check_capacitor_config(selected['config'], preview)
        with self.assertRaises(ValueError):
            VARIANT.check_capacitor_config(selected['config'], VARIANT.resolve_variant({}))
        for name in ('mise', 'frankys'):
            fixture = json.loads(subprocess.check_output(['node', '-e', script, name, 'production'], cwd=ROOT, env=environ))
            expected = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': name, 'DRIVER_BACKEND_TARGET': 'production'})
            self.assertEqual(fixture['variant'], expected)
            VARIANT.check_capacitor_config(fixture['config'], expected)

    def test_both_build_targets_allow_only_the_exact_selected_host(self):
        for target, host in [('production', 'mise-gastro.de'), ('protected_preview', 'mais-vorschau-178-104-106-72.sslip.io')]:
            with self.subTest(target=target):
                variant = VARIANT.resolve_variant({'DRIVER_BACKEND_TARGET': target})
                script = "const v=require('./scripts/app-variant.cjs');process.stdout.write(JSON.stringify(v.capacitorIdentity(v.resolveVariant('mise',process.argv[1]))));"
                config = json.loads(subprocess.check_output(['node', '-e', script, target], cwd=ROOT))
                self.assertEqual(config['server']['allowNavigation'], [host])
                self.assertTrue(all('*' not in entry for entry in config['server']['allowNavigation']))
                VARIANT.check_capacitor_config(config, variant)
                for navigation in [[host, 'mise.app'], ['*.' + host], ['other.example'], [host, '*.mise-gastro.de']]:
                    wrong = copy.deepcopy(config); wrong['server']['allowNavigation'] = navigation
                    with self.subTest(navigation=navigation), self.assertRaises(ValueError):
                        VARIANT.check_capacitor_config(wrong, variant)

    def test_foreign_webview_host_is_rejected_before_native_credentials_or_gps(self):
        delegate = (ROOT / 'ios-resources/AppDelegate.swift').read_text()
        handoff = delegate.split('private func refreshNativeGPSAuthorization()', 1)[1].split('@discardableResult', 1)[0]
        self.assertIn('guard runtime.contains(url) else {\n            LocationTracking.shared.logout()\n            return\n        }', handoff)
        self.assertLess(handoff.index('guard runtime.contains(url)'), handoff.index('LocationTracking.shared.refreshServerAuthorization()'))
        self.assertIn('if !self.runtime.contains(url) || GpsWebSessionNavigation.isSignedOut', delegate)
        runtime = (ROOT / 'ios-resources/SecureGpsQueue.swift').read_text().split('func contains(_ url: URL)', 1)[1].split('func queueFileURL', 1)[0]
        self.assertIn('url.host == serverURL.host', runtime)
        self.assertIn('url.port == nil', runtime)
        self.assertIn('url.user == nil && url.password == nil', runtime)

    def test_explicit_preview_is_one_origin_for_web_and_signed_plist(self):
        origin = 'https://mais-vorschau-178-104-106-72.sslip.io'
        environ = {'DRIVER_APP_VARIANT': 'mise', 'DRIVER_BACKEND_TARGET': 'protected_preview'}
        variant = VARIANT.resolve_variant(environ)
        node = "const v=require('./scripts/app-variant.cjs');const r=v.resolveVariant('mise','protected_preview');process.stdout.write(JSON.stringify({variant:r,config:v.capacitorIdentity(r)}));"
        resolved = json.loads(subprocess.check_output(['node', '-e', node], cwd=ROOT))
        self.assertEqual(resolved['variant'], variant)
        self.assertEqual(variant['bundle_id'], 'app.mise.driver')
        self.assertEqual(resolved['config']['server']['url'], origin + '/fahrer/app')
        self.assertEqual(resolved['config']['server']['allowNavigation'], [url_host := origin.removeprefix('https://')])
        self.assertNotIn('*', url_host)
        plist = {'CFBundleIdentifier': variant['bundle_id']}
        VARIANT.configure_plist(plist, variant)
        self.assertEqual(plist['DriverServerOrigin'], origin)
        self.assertTrue(plist['DriverOperationsEnabled'])
        VARIANT.check_plist(plist, variant)
        VARIANT.check_capacitor_config(resolved['config'], variant)

    def test_canary_cannot_select_operational_preview(self):
        with self.assertRaises(ValueError):
            VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys', 'DRIVER_BACKEND_TARGET': 'protected_preview'})
        result = subprocess.run(['node', '-e', "require('./scripts/app-variant.cjs').resolveVariant('frankys','protected_preview')"], cwd=ROOT, capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_backend_target_is_a_compiled_name_not_a_url(self):
        for target in ('unknown', 'https://other.example', 'http://mise-gastro.de', 'production\nprotected_preview'):
            with self.subTest(target=target), self.assertRaises(ValueError):
                VARIANT.resolve_variant({'DRIVER_BACKEND_TARGET': target})
            result = subprocess.run(['node', '-e', "require('./scripts/app-variant.cjs').resolveVariant('mise',process.argv[1])", target], cwd=ROOT, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_preview_archive_rejects_mixed_url_and_navigation(self):
        variant = VARIANT.resolve_variant({'DRIVER_BACKEND_TARGET': 'protected_preview'})
        script = "const v=require('./scripts/app-variant.cjs');process.stdout.write(JSON.stringify(v.capacitorIdentity(v.resolveVariant('mise','protected_preview'))));"
        config = json.loads(subprocess.check_output(['node', '-e', script], cwd=ROOT))
        for key, value in [('url', 'https://mise-gastro.de/fahrer/app'), ('allowNavigation', ['*.sslip.io']), ('allowNavigation', ['mise-gastro.de'])]:
            wrong = copy.deepcopy(config); wrong['server'][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                VARIANT.check_capacitor_config(wrong, variant)

    def test_origin_tampering_rejected_by_both_resolvers(self):
        variant = VARIANT.resolve_variant({'DRIVER_BACKEND_TARGET': 'protected_preview'})
        for origin in ('https://other.example', 'http://mise-gastro.de', 'https://mise-gastro.de:8443',
                       'https://user@mise-gastro.de', 'https://mise-gastro.de/path', 'https://mise-gastro.de?x=1',
                       'https://mise-gastro.de#fragment'):
            candidate = {**variant, 'server_origin': origin}
            with self.subTest(origin=origin), self.assertRaises(ValueError): VARIANT.validate_variant(candidate)
            result = subprocess.run(['node', '-e', "require('./scripts/app-variant.cjs').capacitorIdentity(JSON.parse(process.argv[1]))", json.dumps(candidate)], cwd=ROOT, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_native_endpoint_calls_use_the_signed_runtime(self):
        source = (ROOT / 'ios-resources/LocationTracking.swift').read_text()
        self.assertIn('runtime.endpoint(path: "/api/driver/v2/snapshot")', source)
        self.assertIn('runtime.endpoint(path: "/api/driver/v2/gps/events")', source)
        self.assertNotIn('URL(string: "https://mise-gastro.de/api/driver/', source)
        delegate = (ROOT / 'ios-resources/AppDelegate.swift').read_text()
        self.assertIn('let serverURL = runtime.serverURL', delegate)
        self.assertIn('runtime.contains(url)', delegate)

    def test_default_preserves_mise(self):
        v = VARIANT.resolve_variant({})
        self.assertEqual((v['name'], v['bundle_id'], v['display_name'], v['url_scheme']),
                         ('mise', 'app.mise.driver', 'Mise Driver', 'mise-driver'))
        self.assertEqual(v['server_origin'], 'https://mise-gastro.de')
        self.assertTrue(v['operations_enabled'])
        self.assertFalse(v['installation_canary'])

    def test_unknown_variant_fails_closed(self):
        for name in ('', 'Frankys', 'other', '../mise'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                VARIANT.resolve_variant({'DRIVER_APP_VARIANT': name})

    def test_frankys_is_offline_and_non_operational(self):
        v = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        self.assertEqual(v['bundle_id'], 'de.frankysfarm.driver')
        self.assertEqual(v['display_name'], "Franky's Fahrer")
        self.assertEqual(v['url_scheme'], 'frankys-driver')
        self.assertTrue(v['installation_canary'])
        self.assertFalse(v['operations_enabled'])
        self.assertEqual(v['web_dir'], 'web-canary')

    def test_node_capacitor_resolver_matches_python(self):
        for name in ('mise', 'frankys'):
            output = subprocess.check_output(['node', '-e',
                f"process.stdout.write(JSON.stringify(require('./scripts/app-variant.cjs').resolveVariant('{name}','production')))"], cwd=ROOT)
            self.assertEqual(json.loads(output), VARIANT.resolve_variant({'DRIVER_APP_VARIANT': name}))

    def test_node_rejects_unknown_variant(self):
        completed = subprocess.run(['node', '-e', "require('./scripts/app-variant.cjs').resolveVariant('unknown')"],
                                   cwd=ROOT, capture_output=True)
        self.assertNotEqual(completed.returncode, 0)

    def test_new_apple_app_id_required_and_cannot_be_old_app(self):
        v = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        for value in ('', '6766271119', 'abc', '12\n34'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                VARIANT.apple_app_id(v, {'FRANKYS_APP_STORE_APP_ID': value})
        self.assertEqual(VARIANT.apple_app_id(v, {'FRANKYS_APP_STORE_APP_ID': '1234567890'}), '1234567890')

    def test_mise_apple_app_id_preserved(self):
        self.assertEqual(VARIANT.apple_app_id(VARIANT.resolve_variant({}), {}), '6766271119')

    def test_matching_distribution_profile_accepted(self):
        self.assertEqual(VARIANT.validate_profile(profile(), VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})),
                         ('Synthetic Canary Profile', 'synthetic-profile-uuid'))

    def test_wrong_bundle_profile_rejected(self):
        with self.assertRaises(ValueError):
            VARIANT.validate_profile(profile('app.mise.driver'), VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'}))

    def test_wrong_team_or_entitlement_rejected(self):
        v = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        for key, value in [('application-identifier', 'WRONG.de.frankysfarm.driver'),
                           ('com.apple.developer.team-identifier', 'WRONG'),
                           ('aps-environment', 'development'), ('get-task-allow', True)]:
            candidate = profile(); candidate['Entitlements'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): VARIANT.validate_profile(candidate, v)
        candidate = profile(); candidate['TeamIdentifier'] = ['WRONG']
        with self.assertRaises(ValueError): VARIANT.validate_profile(candidate, v)

    def test_expired_and_non_appstore_profiles_rejected(self):
        v = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        for key, value in [('ExpirationDate', datetime.now(timezone.utc) - timedelta(days=1)),
                           ('ProvisionedDevices', ['fake-device']), ('ProvisionsAllDevices', True)]:
            candidate = profile(); candidate[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): VARIANT.validate_profile(candidate, v)

    def test_profile_metadata_cannot_inject_environment_lines(self):
        candidate = profile(); candidate['Name'] = 'Profile\nBUNDLE_ID=other'
        with self.assertRaises(ValueError):
            VARIANT.validate_profile(candidate, VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'}))

    def test_canary_runtime_plist_has_only_own_scheme_and_no_background_modes(self):
        plist = {'CFBundleURLTypes': [{'CFBundleURLSchemes': ['mise-driver', 'old']}],
                 'UIBackgroundModes': ['location', 'remote-notification']}
        VARIANT.configure_plist(plist, VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'}))
        self.assertEqual(plist['CFBundleURLTypes'], [{'CFBundleURLName': 'de.frankysfarm.driver.offer-contract',
                                                   'CFBundleURLSchemes': ['frankys-driver']}])
        self.assertEqual(plist['UIBackgroundModes'], [])
        self.assertFalse(plist['DriverOperationsEnabled'])
        self.assertTrue(plist['DriverInstallationCanary'])
        self.assertEqual(plist['DriverServerOrigin'], 'https://mise-gastro.de')
        self.assertTrue(plist['NSCameraUsageDescription'].startswith("Franky's Fahrer braucht"))

    def test_mise_runtime_keeps_operations(self):
        plist = {'CFBundleURLTypes': [{'CFBundleURLSchemes': ['existing-unrelated-scheme']}]}
        VARIANT.configure_plist(plist, VARIANT.resolve_variant({}))
        self.assertTrue(plist['DriverOperationsEnabled'])
        self.assertEqual(plist['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['existing-unrelated-scheme'])
        self.assertEqual(plist['DriverURLScheme'], 'mise-driver')
        self.assertEqual(plist['UIBackgroundModes'], ['remote-notification', 'location'])

    def test_runtime_configuration_is_idempotent(self):
        plist = {}; variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        VARIANT.configure_plist(plist, variant); expected = copy.deepcopy(plist)
        VARIANT.configure_plist(plist, variant)
        self.assertEqual(plist, expected)

    def test_export_profiles_map_only_selected_identity(self):
        for name in ('mise', 'frankys'):
            variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': name})
            value = VARIANT.export_options(variant, 'actual-profile-name')
            self.assertEqual(value['provisioningProfiles'], {variant['bundle_id']: 'actual-profile-name'})
            self.assertEqual(value['teamID'], 'T82KC2CU9V')

    def test_apple_record_must_match_both_identifiers(self):
        record = {'data': {'id': '1234567890', 'attributes': {'bundleId': 'de.frankysfarm.driver'}}}
        script = "const c=require('./scripts/check_app_store_identity.cjs');c.validateRecord(JSON.parse(process.argv[1]),process.argv[2],process.argv[3]);"
        for apple_id, bundle_id, success in [('1234567890', 'de.frankysfarm.driver', True),
                                             ('6766271119', 'de.frankysfarm.driver', False),
                                             ('1234567890', 'app.mise.driver', False)]:
            result = subprocess.run(['node', '-e', script, json.dumps(record), apple_id, bundle_id], cwd=ROOT, capture_output=True)
            self.assertEqual(result.returncode == 0, success)

    def test_tampered_variant_flags_or_identity_cannot_load_remote_app(self):
        variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        for key, value in [('installation_canary', None), ('installation_canary', False), ('operations_enabled', True),
                           ('bundle_id', 'app.mise.driver'), ('url_scheme', 'mise-driver'), ('web_dir', 'web'),
                           ('server_origin', 'https://other.example'), ('team_id', 'OTHERTEAM')]:
            candidate = dict(variant)
            if value is None: candidate.pop(key)
            else: candidate[key] = value
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError): VARIANT.validate_variant(candidate)
                command = "require('./scripts/app-variant.cjs').capacitorIdentity(JSON.parse(process.argv[1]));"
                result = subprocess.run(['node', '-e', command, json.dumps(candidate)], cwd=ROOT, capture_output=True)
                self.assertNotEqual(result.returncode, 0)

    def test_effective_capacitor_config_is_local_for_canary_and_exact_host_for_mise(self):
        for name in ('mise', 'frankys'):
            script = "const v=require('./scripts/app-variant.cjs');process.stdout.write(JSON.stringify(v.capacitorIdentity(v.resolveVariant(process.argv[1],'production'))));"
            config = json.loads(subprocess.check_output(['node', '-e', script, name], cwd=ROOT))
            variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': name})
            VARIANT.check_capacitor_config(config, variant)
            if name == 'frankys':
                self.assertNotIn('url', config['server'])
                self.assertEqual(config['server']['allowNavigation'], [])
            else:
                self.assertEqual(config['server'], {'url': 'https://mise-gastro.de/fahrer/app', 'cleartext': False,
                                 'androidScheme': 'https', 'allowNavigation': ['mise-gastro.de']})

    def test_archive_gate_rejects_remote_canary_or_incorrect_identity(self):
        variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        config = {'appId': variant['bundle_id'], 'appName': variant['display_name'], 'server': {'allowNavigation': []}}
        VARIANT.check_capacitor_config(config, variant)
        for key, value in [('url', 'https://mise-gastro.de/fahrer/app'), ('allowNavigation', ['mise-gastro.de'])]:
            wrong = copy.deepcopy(config); wrong['server'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): VARIANT.check_capacitor_config(wrong, variant)
        config['appId'] = 'app.mise.driver'
        with self.assertRaises(ValueError): VARIANT.check_capacitor_config(config, variant)

    def test_archived_plist_rejects_wrong_bundle_scheme_and_capabilities(self):
        variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        plist = {'CFBundleIdentifier': variant['bundle_id']}; VARIANT.configure_plist(plist, variant)
        VARIANT.check_plist(plist, variant)
        for key, value in [('CFBundleIdentifier', 'app.mise.driver'), ('DriverURLScheme', 'mise-driver'),
                           ('DriverOperationsEnabled', True), ('UIBackgroundModes', ['location'])]:
            wrong = copy.deepcopy(plist); wrong[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): VARIANT.check_plist(wrong, variant)

    def test_canary_has_no_apns_entitlement_while_mise_is_unchanged(self):
        self.assertEqual(VARIANT.signing_entitlements(VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})), {})
        self.assertEqual(VARIANT.signing_entitlements(VARIANT.resolve_variant({})), {'aps-environment': 'production'})
        candidate = profile(); candidate['Entitlements']['aps-environment'] = 'production'
        with self.assertRaises(ValueError):
            VARIANT.validate_profile(candidate, VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'}))

    def test_missing_canary_profile_never_falls_back_to_mise(self):
        variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / 'profile.mobileprovision'
            with self.assertRaisesRegex(ValueError, 'FRANKYS_BUILD_PROFILE_BASE64'):
                VARIANT.preflight(variant, {'FRANKYS_APP_STORE_APP_ID': '1234567890', 'BUILD_PROFILE_BASE64': 'not-a-secret'},
                                  destination, Path(tmp) / 'env')
            self.assertFalse(destination.exists())

    def test_malformed_profile_secret_fails_without_printing_value(self):
        variant = VARIANT.resolve_variant({'DRIVER_APP_VARIANT': 'frankys'})
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError) as failure:
                VARIANT.preflight(variant, {'FRANKYS_APP_STORE_APP_ID': '1234567890', 'FRANKYS_BUILD_PROFILE_BASE64': 'synthetic invalid value!!'},
                                  Path(tmp) / 'profile.mobileprovision', Path(tmp) / 'env')
            self.assertNotIn('synthetic invalid value', str(failure.exception))

    def test_canary_page_has_no_remote_or_operational_dependencies(self):
        source = (ROOT / 'web-canary/index.html').read_text()
        self.assertIn("connect-src 'none'", source)
        self.assertNotRegex(source, r'(?:src|href)=[\"\']https?://')
        self.assertNotIn('<script', source)
        self.assertIn('__BUILD_NUMBER__', source)
        self.assertIn('Installationstest', source)


if __name__ == '__main__': unittest.main()
