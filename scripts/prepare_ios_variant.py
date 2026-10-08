#!/usr/bin/env python3
"""Resolve public build identity and validate CI-supplied signing configuration.

Never prints profile contents, certificates, keys, or secret environment values.
"""
import argparse
import base64
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


def backend_origin(target):
    backends = json.loads((ROOT / 'config/driver-backends.json').read_text())
    if target not in backends:
        raise ValueError('Unknown DRIVER_BACKEND_TARGET; expected production or protected_preview.')
    origin = backends[target]
    url = urlsplit(origin)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password or url.port
            or url.path or url.query or url.fragment or origin != 'https://' + url.hostname):
        raise ValueError('Driver backend must be an exact compiled HTTPS origin.')
    return origin


def resolve_variant(environ):
    variants = json.loads((ROOT / 'config/driver-variants.json').read_text())
    name = environ.get('DRIVER_APP_VARIANT', 'mise')
    if name not in variants:
        raise ValueError('Unknown DRIVER_APP_VARIANT; expected mise or frankys.')
    target = environ.get('DRIVER_BACKEND_TARGET', 'production')
    variant = {'name': name, **variants[name], 'backend_target': target, 'server_origin': backend_origin(target)}
    validate_variant(variant)
    return variant


def validate_variant(variant):
    mise = variant.get('name') == 'mise' and variant.get('bundle_id') == 'app.mise.driver'
    frankys = variant.get('name') == 'frankys' and variant.get('bundle_id') == 'de.frankysfarm.driver'
    if (not (mise or frankys)
            or variant.get('url_scheme') != ('mise-driver' if mise else 'frankys-driver')
            or variant.get('web_dir') != ('web' if mise else 'web-canary')
            or variant.get('server_origin') != backend_origin(variant.get('backend_target', 'production'))
            or frankys and variant.get('backend_target', 'production') != 'production'
            or variant.get('team_id') != 'T82KC2CU9V'
            or variant.get('installation_canary') is not frankys
            or variant.get('operations_enabled') is not mise):
        raise ValueError('Variant identity, navigation and capability metadata must match exactly.')


def apple_app_id(variant, environ):
    if variant['name'] == 'mise':
        return '6766271119'
    value = environ.get('FRANKYS_APP_STORE_APP_ID', '')
    if not re.fullmatch(r'[1-9][0-9]{5,19}', value) or value == '6766271119':
        raise ValueError('Set repository variable FRANKYS_APP_STORE_APP_ID to the separate Frankys Apple app ID.')
    return value


def validate_profile(profile, variant):
    team = variant['team_id']
    entitlements = profile.get('Entitlements', {})
    valid = (team in profile.get('TeamIdentifier', [])
             and entitlements.get('com.apple.developer.team-identifier') == team
             and entitlements.get('application-identifier') == team + '.' + variant['bundle_id']
             and entitlements.get('aps-environment') == ('production' if variant['operations_enabled'] else None)
             and entitlements.get('get-task-allow') is False
             and not profile.get('ProvisionedDevices')
             and not profile.get('ProvisionsAllDevices'))
    expires = profile.get('ExpirationDate')
    if not valid or not isinstance(expires, datetime) or expires.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError('Provisioning profile must be an unexpired App Store profile for the selected bundle/team with the selected APNs capability.')
    name, uuid = profile.get('Name', ''), profile.get('UUID', '')
    if not all(isinstance(value, str) and value.strip() and '\n' not in value and '\r' not in value for value in (name, uuid)):
        raise ValueError('Provisioning profile Name/UUID is missing or malformed.')
    if not re.fullmatch(r'[A-Za-z0-9-]{1,80}', uuid):
        raise ValueError('Provisioning profile UUID is malformed.')
    return name, uuid


def configure_plist(plist, variant):
    validate_variant(variant)
    plist['CFBundleDisplayName'] = variant['display_name']
    purposes = {
        'NSPhotoLibraryUsageDescription': 'braucht Zugriff auf deine Fotos, um Liefer-Beweis-Fotos auszuwaehlen und hochzuladen.',
        'NSPhotoLibraryAddUsageDescription': 'speichert Liefer-Beweis-Fotos in deiner Mediathek.',
        'NSCameraUsageDescription': 'braucht die Kamera fuer QR-Login und Liefer-Beweis-Fotos.',
        'NSLocationWhenInUseUsageDescription': 'braucht deinen Standort, um Lieferzentrale und Kunden deine Position zu zeigen.',
        'NSLocationAlwaysAndWhenInUseUsageDescription': 'braucht Hintergrund-Standort fuer Live-Tracking waehrend der Lieferung.',
    }
    for key, text in purposes.items():
        plist[key] = variant['display_name'] + ' ' + text
    plist['DriverExpectedBundleIdentifier'] = variant['bundle_id']
    plist['DriverURLScheme'] = variant['url_scheme']
    plist['DriverServerOrigin'] = variant['server_origin']
    plist['DriverOperationsEnabled'] = variant['operations_enabled']
    plist['DriverInstallationCanary'] = variant['installation_canary']
    own_type = {'CFBundleURLName': variant['bundle_id'] + '.offer-contract',
                'CFBundleURLSchemes': [variant['url_scheme']]}
    if variant['installation_canary']:
        # A parallel app must never retain the Mise scheme from another setup.
        plist['CFBundleURLTypes'] = [own_type]
    else:
        # Match the previous Mise behavior: keep unrelated URL registrations.
        url_types = list(plist.get('CFBundleURLTypes', []))
        if not any(variant['url_scheme'] in row.get('CFBundleURLSchemes', []) for row in url_types):
            url_types.append(own_type)
        plist['CFBundleURLTypes'] = url_types
    plist['UIBackgroundModes'] = ['remote-notification', 'location'] if variant['operations_enabled'] else []


def check_plist(plist, variant):
    validate_variant(variant)
    expected = dict(plist)
    configure_plist(expected, variant)
    if expected != plist or plist.get('CFBundleIdentifier') != variant['bundle_id']:
        raise ValueError('Archived app identity/capabilities do not match the selected variant.')


def check_capacitor_config(config, variant):
    validate_variant(variant)
    server = config.get('server', {})
    expected_url = None if variant['installation_canary'] else variant['server_origin'] + '/fahrer/app'
    navigation = [] if variant['installation_canary'] else [urlsplit(variant['server_origin']).hostname]
    if (config.get('appId') != variant['bundle_id'] or config.get('appName') != variant['display_name']
            or server.get('url') != expected_url
            or server.get('allowNavigation') != navigation):
        raise ValueError('Bundled Capacitor identity/navigation does not match the selected variant.')


def signing_entitlements(variant):
    validate_variant(variant)
    return {'aps-environment': 'production'} if variant['operations_enabled'] else {}


def export_options(variant, profile_name):
    validate_variant(variant)
    if not profile_name:
        raise ValueError('Validated provisioning profile name is required for export.')
    return {'method': 'app-store-connect', 'teamID': variant['team_id'], 'signingStyle': 'manual',
            'signingCertificate': 'Apple Distribution',
            'provisioningProfiles': {variant['bundle_id']: profile_name},
            'destination': 'export', 'uploadSymbols': True}


def preflight(variant, environ, profile_output, github_env):
    app_id = apple_app_id(variant, environ)
    secret_name = 'FRANKYS_BUILD_PROFILE_BASE64' if variant['installation_canary'] else 'BUILD_PROFILE_BASE64'
    encoded = environ.get(secret_name, '')
    if not encoded:
        raise ValueError('Missing required CI secret ' + secret_name + '; no profile fallback is allowed.')
    try:
        profile_data = base64.b64decode(''.join(encoded.split()), validate=True)
    except ValueError:
        raise ValueError('Selected CI provisioning profile is not valid base64.') from None
    profile_output.parent.mkdir(parents=True, exist_ok=True)
    profile_output.write_bytes(profile_data)
    profile_output.chmod(0o600)
    decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile_output)], capture_output=True)
    if decoded.returncode:
        raise ValueError('Selected provisioning profile could not be decoded.')
    try:
        profile = plistlib.loads(decoded.stdout)
    except Exception:
        raise ValueError('Selected provisioning profile does not contain a valid plist.') from None
    profile_name, profile_uuid = validate_profile(profile, variant)
    values = {'DRIVER_APP_VARIANT': variant['name'], 'BUNDLE_ID': variant['bundle_id'],
              'APP_ID': app_id, 'APP_DISPLAY_NAME': variant['display_name'],
              'DRIVER_URL_SCHEME': variant['url_scheme'], 'TEAM_ID': variant['team_id'],
              'PROFILE_NAME': profile_name, 'PROFILE_UUID': profile_uuid,
              'BUILD_NO': datetime.now().strftime('%Y%m%d%H%M')}
    with github_env.open('a') as handle:
        for key, value in values.items():
            handle.write(key + '=' + value + '\n')
    print('Validated build identity and distribution profile for ' + variant['name'] + '.')


def prepare_canary_web(variant, build_number):
    if not variant['installation_canary']:
        return
    if not re.fullmatch(r'[0-9]+', build_number or ''):
        raise ValueError('BUILD_NO must be resolved before preparing the installation page.')
    icon = ROOT / 'resources/variants/frankys/icon.png'
    if not icon.is_file():
        raise ValueError('Missing resources/variants/frankys/icon.png; canary asset generation cannot continue.')
    page = ROOT / variant['web_dir'] / 'index.html'
    source = page.read_text()
    if '__BUILD_NUMBER__' not in source:
        raise ValueError('Canary template requires a fresh checkout before preparing another build.')
    page.write_text(source.replace('__BUILD_NUMBER__', build_number))
    shutil.copyfile(icon, page.parent / 'icon.png')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['preflight', 'configure-plist', 'check-plist', 'export-options', 'prepare-web', 'configure-entitlements', 'check-capacitor-config'])
    parser.add_argument('--path', type=Path)
    parser.add_argument('--github-env', type=Path)
    parser.add_argument('--profile-output', type=Path)
    args = parser.parse_args()
    variant = resolve_variant(os.environ)
    if args.command == 'preflight':
        if not args.profile_output or not args.github_env:
            parser.error('preflight requires --profile-output and --github-env')
        preflight(variant, os.environ, args.profile_output, args.github_env)
    elif args.command == 'prepare-web':
        prepare_canary_web(variant, os.environ.get('BUILD_NO'))
    else:
        if not args.path:
            parser.error('--path is required')
        if args.command == 'check-capacitor-config':
            check_capacitor_config(json.loads(args.path.read_text()), variant)
        elif args.command == 'configure-entitlements':
            args.path.write_bytes(plistlib.dumps(signing_entitlements(variant)))
        elif args.command == 'export-options':
            args.path.write_bytes(plistlib.dumps(export_options(variant, os.environ.get('PROFILE_NAME'))))
        else:
            data = plistlib.loads(args.path.read_bytes())
            if args.command == 'check-plist':
                check_plist(data, variant)
            else:
                configure_plist(data, variant)
                args.path.write_bytes(plistlib.dumps(data, sort_keys=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError) as error:
        print('Variant configuration failed: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
