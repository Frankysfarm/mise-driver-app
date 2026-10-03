# Franky's Fahrer — separate installation canary

Status: IN PROGRESS. Not a production driver release.

## User request and baseline
User authorizes checking the repeated TestFlight installation failure and, if the
existing app remains blocked, preparing a separate app outside Mise with a new
icon. Both fresh existing builds failed on the user's phone with the same
unavailable/nonexistent-app message. Existing package signing, group assignment,
minimum OS and roles have passed documented checks. On October 3, Apple Developer
account shows renewal May 4, 2027, annual fee EUR99, and program agreement accepted
October 2, 2026. No overdue payment notice is shown. Root cause remains unproven.

## Scope and allowed modules
Prepare an opt-in Franky's Fahrer build identity and icon, preserving the existing
Mise default. Configure a distinct App Store Connect record, bundle identifier and
URL scheme, tied to the same existing developer team. Initial purpose is an
installation/start comparison, not a claim of completed push or delivery testing.
Allowed: Capacitor/configuration, CI signing/export identity handling, native
identity/scheme lookup, build preparation scripts/tests and release documentation.
Root owns icon assets and this packet. Native worker owns build-variant code.

## Critical invariants
- Existing Mise branch behavior, identity, production origin and rollback build
  remain unchanged by default.
- No secret material in files/logs/model context; do not read .env files.
- Never upload under mismatched App ID, profile or bundle identifier.
- New variant cannot silently register a second-app push token into an existing
  single-topic production endpoint, replacing a working driver token.
- Both apps must not share a custom URL scheme.
- No production backend migration, tester removal or new user privileges.
- Apple record/profile actions require applicable action-time confirmation.

## Acceptance and evidence
1. Variant identity validation fails closed for unknown variants/missing Apple
   configuration and preserves the default identity.
2. Focused tests prove scheme/profile/app-ID consistency, not mere string mirrors.
3. Independent review precedes any upload. iOS compilation/signing run on existing
   GitHub macOS CI, not a heavy local Mac build.
4. Record exact Apple app/build IDs, immutable revision, CI result and group status.
5. Real iPhone installation/start is the decisive comparison. If both records
   fail, do not repeat unchanged uploads; pursue account/device evidence.
6. Native notifications, background GPS, session/account switching and complete
   order delivery remain separate gates before actual driver operations.

## Rollback / privacy
New variant is opt-in and separately named. Keep old app and profiles available.
No customer, order, private GPS or credential data is needed for this comparison.
Do not send Apple support communications without explicit authorization.

## Evidence — October 4, 2026
- User confirms TestFlight on the iPhone uses the same Apple ID as the existing
  internal tester. A mismatched Apple ID is no longer the leading hypothesis.
- Apple Developer visibly confirmed registration of de.frankysfarm.driver,
  description Frankys Fahrer, with no optional capabilities enabled.
- App Store Connect creation was initiated but completion was not confirmed.
  After the interruption the session expired; reauthentication is pending.
  Do not assume a new Apple numeric app ID or retry creating a duplicate blindly.
- Root ran `python3 -m unittest discover -s ios-contract-tests -p '*Tests.py'`:
  31 tests passed. `bash scripts/tests/native-location-source.sh`: PASS.
  `git diff --check`: PASS. Swift assertions have not run locally; mandatory CI
  execution remains open.
- Independent full-diff reviewer GO for the installation canary implementation,
  including fail-closed identity, APNs/GPS isolation and existing Mise behavior.
- New icon has independent visual GO for this installation probe. Static page
  checked in browser at 1280px and 393x852; mobile document width exactly 393px,
  no horizontal overflow. Impeccable detector returned no findings.
- This is a local preview, not an installed iOS app. Native startup, Apple's
  processed download and actual iPhone installation remain unverified.
- Success of the new app would narrow the fault but not prove the old app record
  alone is defective: both identity and enabled capabilities differ.
- Operational UI source review found five targeted refinements, documented in
  FRANKYS-DRIVER-DESIGN.md. No backend UI change or live deployment performed.
