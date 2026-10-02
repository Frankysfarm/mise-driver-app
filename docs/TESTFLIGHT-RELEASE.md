# Mise Driver TestFlight release

Existing app: `app.mise.driver`, Apple ID `6766271119`.
Production origin remains `https://mise-gastro.de/fahrer/app`.
The user confirmed the app is for working drivers on 2026-10-02.
The separate public preview is not silently substituted.

## Encryption declaration (2026-10-02)

The wrapper uses OS-provided HTTPS in WKWebView/URLSession, Keychain in Security,
and AES-GCM supplied by Apple's CryptoKit for locally queued GPS data. The native
package dependencies are Capacitor and its official device plugins. No custom
cryptographic algorithm or bundled crypto SDK was found in the native source.
The build therefore declares `ITSAppUsesNonExemptEncryption = false`; encryption
is still used, but through Apple operating-system facilities. This is not a
claim that the app uses no encryption.

Apple guidance:
https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption

Review this classification if native dependencies or encryption change. The
preparation script refuses to overwrite an existing non-exempt declaration or
Apple export-compliance code. The archive is checked before upload.

## Release evidence and acceptance

Use the existing `iOS → TestFlight` workflow. It runs native contract tests,
builds/signs on GitHub's macOS runner, uploads, then checks the exact build's
Apple processing, encryption status and internal test group. A processing state
of VALID alone does not prove that testers can install it.

After upload verify the exact build in App Store Connect. Real-device acceptance:
login; receive an assigned order while foreground/background/locked; scan pickup;
route and complete; reconnect after lost network; logout; sign in as a different
test driver and confirm no prior driver's queued coordinates or offers appear.
The backend APNs credentials, push-flush worker and deployed order API must also
be current. TestFlight availability does not alone certify operational readiness.

Rollback: retain the prior binary and release SHA; do not change production
backend, database or live orders as part of this native upload.

## Server observations, 2026-10-02

Production `mise-gastro.de`: unauthenticated `/api/driver/v2/snapshot` returns
401/UNAUTHORIZED; `/api/delivery/health` returns 200 with database reachable.
Production revision is not exposed at `/vorschau` (redirects to login). The
existing, repository-configured SSH target timed out; therefore native APNs
credentials and worker execution on production are **not verified**.

Separate Factory preview: release 66dd2a99240a6d590e59c127f5efebb0d1c17bf9.
Boolean-only runtime inspection found no APNs key/path/team configuration or
internal worker token. Browser VAPID configuration and its timer are present.
Do not switch the production driver wrapper to that preview and claim native
push works. No provider notifications or customer orders were sent during audit.
