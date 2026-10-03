# TestFlight update 2026-10-02

Status: RELEASED_TO_INTERNAL_TESTFLIGHT — user reports installation failure; device/APNs checks open

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

## Confirmed release
- Binary source: 75fd58101960b2caabcc7e0281be170a585c44cd.
- GitHub run: https://github.com/Frankysfarm/mise-driver-app/actions/runs/37068380171.
- All mandatory tests, archive, signing, upload, exact-build compliance/testing
  and group checks succeeded. Build 1.0.0 (202610022143).
- App Store Connect visibly lists that exact build as Ready to Submit, expires
  in 90 days, group Team (Expo), one invitation. This confirms internal testing;
  it is not a public App Store release or an end-to-end operational acceptance.
- Production host remains mise-gastro.de. Real-device push/driver-switch and
  production native APNs/worker checks remain open.
- Source is pushed on codex/testflight-update-20261002. Direct main update was
  rejected by automatic approval review: TestFlight authorization was deemed
  insufficient for direct default-branch mutation. No workaround attempted.
  PR creation was unavailable (connector 403, CLI GraphQL authentication 401).

## Installation failure diagnosis — 2026-10-03
User reports that TestFlight says the app is unavailable or does not exist.
The exact new-build installation attempt versus invitation-link failure is
not yet distinguished; no speculative replacement build was uploaded.

Verified read-only in App Store Connect:
- Team (Expo) group explicitly lists 202610022143 as Testing, 90 days remaining.
- Existing internal tester is accepted, with a previous August build installed.
- New binary is Validated, iOS 13.0 minimum, arm64, iPhone and iPad.
- Free Apps Agreement is Active (effective October 2, 2026).

Independent inspection of the exact CI IPA found no package blocker:
- App and all 11 frameworks target iOS 13.0; the recorded iPhone 15 Pro on
  iOS 18.7.8 meets these requirements.
- codesign --verify --deep --strict passed; profile, identifier and signing
  entitlements match; distribution certificate/profile expire June 8, 2027.
- IPA SHA256: 7d2849b505c164c2be6022ae1e9c36a3c43b5537996e1c04e11a4012a6c34180.
- No binary was executed and no tester, signing or account settings changed.

Apple DTS acknowledged this same error class in August 2026 and requested a
latest-build retry, then a Feedback Assistant report if it persists:
https://developer.apple.com/forums/thread/813703
This is a possible Apple delivery issue, not an established cause for this app.
Next evidence: visible build number and failure point from the user's TestFlight.
Successful device installation is still unverified.

## Explicitly requested re-upload — 2026-10-03
After the user reported another failed installation attempt, they explicitly
requested a complete new TestFlight upload. Dispatched the existing reviewed
workflow at remote source 75fd58101960b2caabcc7e0281be170a585c44cd, without changing
app identity, signing, production origin, testers or main. Independent reviewer
confirmed no functional source/configuration changes since the verified IPA.
- New run: https://github.com/Frankysfarm/mise-driver-app/actions/runs/37070952020
- Dispatched October 2, 2026 at 22:09:32 UTC (October 3 local).
- Completed successfully October 2, 2026 at 22:16:43 UTC (October 3 local).
- New build 1.0.0 (202610022210); all mandatory tests, archive, signing, upload
  and exact-build internal testing gates succeeded.
- Independently verified in App Store Connect: Team (Expo), Builds (3), exact
  build 202610022210 is Testing with 90 days remaining.
- Apple build ID: 5008ba94-e958-445c-b1f1-d8446a1a9e79.
- Installation on the user's iPhone remains unverified; no claim that the
  underlying availability failure is repaired.
- Previous build remains available. A new build alone does not prove that the
  reported TestFlight availability failure is resolved.

## Second failure confirmed — October 3, 2026
User explicitly confirms the same "requested app unavailable or does not exist"
message for build 202610022210. Do not repeat an unchanged upload or remove the
tester/profile/app as a speculative fix. Prepared an unsent Apple support report
in docs/TESTFLIGHT-INSTALLATION-REPORT-20261003.md. Sending it requires explicit
authorization. Production /fahrer/login returned HTTP 200 and delivery health
reported database OK at 07:21 UTC; this is login availability, not proof of the
authenticated driver workflow, web push or background GPS.

## Deeper diagnosis after reauthentication — October 3, 2026
User requested further direct investigation and reauthenticated Chrome.
- Users and Access: the existing tester is Account Holder + Admin, All Apps.
- Free Apps Agreement remains Active, October 2, 2026–May 3, 2027.
- Latest exact Apple build metadata: Validated, iOS 13+, iPhone/iPad ARM64,
  non-exempt encryption No, expected production/TestFlight entitlements.
- Apple public status page rendered TestFlight, app processing and uploads as
  available. Its displayed App Store Connect incident ended October 1, 2026
  at 01:12 (before these uploads); no current general outage established.
- Independent exact second-IPA check passed deep/strict signing verification.
  Same archive file inventory, same native code sections and embedded profile;
  only Info.plist build number changed. SHA256:
  4d5359ac91c803871638a7a5c2e9c1dd750e113f821145669958f0d258055d13.
- Uploaded IPA inspection does not inspect Apple's re-signed/thinned download.
- No new release, account changes or support submission performed.

Remaining hypotheses: device/TestFlight Apple ID or local download state,
per-account/per-app Apple TestFlight delivery/beta-contract state. Apple DTS
has acknowledged similar cases (forums/thread/814565); no BETA_CONTRACT_MISSING
error has been observed for this account, so that cause remains unconfirmed.
Awaiting user's confirmation of the Apple ID actually used by iPhone TestFlight.
Apple's latest-build File Sizes dialog also lists the iPhone 15 Pro variant
(estimated 1.06 MB download / 6.41 MB installed). This is processing metadata,
not a successful download/installation or proof of delivery authorization.
