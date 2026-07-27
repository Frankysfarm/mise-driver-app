# T06 — GPS native lifecycle

Problem: the versioned shell declares location permission but has no native
location manager, Android service, bounded replay queue, or truthful lifecycle
contract. GPS becomes stale under lock/background and can continue outside an
approved shift.

Scope: versioned iOS/Android location modules and configuration, bounded
session/sequence queue, canonical v2 upload, operational-state start/stop,
permission/network warnings, and source-level lifecycle tests. Non-goals:
production enablement, deployment, web-driver UI changes, or claims of
force-quit/reboot guarantees.

Acceptance: foreground/background/locked configuration is present; tracking
starts only for approved states and stops at shift end; queue is bounded to
100 and replay is ordered/idempotent; platform limitations are documented.
Real-device tests remain a release blocker.

Build evidence on the current host is limited: disposable Android generation,
manifest and Gradle integration succeeded but compilation is blocked by a
missing Java runtime. Disposable iOS generation reached native dependency
installation but compilation is blocked because full Xcode is not selected
and CocoaPods cannot normalize the host locale. These are not reported as
device or compiled-native evidence.

Privacy/rollback: tracking is visibly tied to an active operational state.
Backend policy remains default-off. Roll back by disabling backend tracking
and removing the native bridge activation, without deleting stored history.
Bearer credentials are migrated to iOS Keychain and Android
Keystore-backed encrypted preferences. Android encrypts its GPS queue. iOS
encrypts the bounded queue as an AES-GCM file using a device-only Keychain key
and `completeUntilFirstUserAuthentication` file protection. A legacy
UserDefaults queue is migrated once and deleted only after a successful
encrypted round-trip; corrupt ciphertext is deleted fail-closed with
reason-only quarantine metadata.
