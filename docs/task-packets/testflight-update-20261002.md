# TestFlight update 2026-10-02

Status: REVIEWED — mandatory CI/native build and Apple verification pending

## Problem and baseline
Existing app: app.mise.driver, Apple app 6766271119, GitHub Frankysfarm/mise-driver-app.
Remote main acad3c91; last CI upload 31963497280 succeeded, but Apple displays
Missing Compliance for build 202608161805. Production and preview driver login
pages have different deployed assets. WebView and native GPS URLs are hardcoded.
Native GPS retains credentials/queued coordinates across account switches.

## Scope and invariants
Update this existing iOS app for internal TestFlight only. Preserve dirty files
in other checkouts, app identity, standard APNs offer contract, and rollback build.
No production backend deployment, customer payments or store publication here.
User clarified that the app must stay online for working drivers. Retain the
existing production origin mise-gastro.de for WebView and native GPS; no implicit
preview switch. Backend differences remain a separate launch gate.
Clear or quarantine GPS from a different authenticated identity, reject stale
asynchronous callbacks, and fail closed on logout/invalid credentials. Do not log
tokens or coordinates. Keep OS-backed encryption and permissions.

## Ownership
Root: release configuration, CI, documentation and upload.
Native worker: iOS session/GPS lifecycle and focused tests only.
Independent reviewer: native/release diff and evidence before upload.

## Verification and release
Reproduce defects before patch. Run focused contract tests, native build on the
existing GitHub macOS runner, archive/entitlement checks, upload and confirm exact
build status at Apple. Encryption declaration must match actual OS APIs used.
Verify login, foreground/background notification, logout and driver switch on a
real iPhone before declaring driver operations ready.

## Rollback and limits
Keep previous TestFlight build and release SHA. No schema changes. A new binary
cannot make an old backend current; APNs provider configuration/worker and full
order-to-driver flow need separate server and device evidence. No readiness
claim from a successful upload alone.

## Review and local evidence
Independent reviewer source-GO for release and native changes (2026-10-02).
Encryption plist tests: 3 passed; existing URL scheme plist tests: 3 passed.
Native source integration and whitespace checks passed. Native worker reproduced
the unscoped queue, captured-queue overwrite and persisted-token issues before
patching; 48 behavior assertions are now wired into mandatory CI. Local Swift
compilation was stopped after prolonged no output to respect Mac resource policy;
it is not reported as passed. CI must execute Swift assertions and iOS archive
before upload. Server observations and device acceptance are in TESTFLIGHT-RELEASE.md.
