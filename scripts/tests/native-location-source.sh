#!/usr/bin/env bash
set -euo pipefail
grep -q 'refreshServerAuthorization' ios-resources/LocationTracking.swift
grep -q '/api/driver/v2/snapshot' ios-resources/LocationTracking.swift
grep -q 'uploadInFlight' ios-resources/LocationTracking.swift
grep -q 'kSecClassGenericPassword' ios-resources/LocationTracking.swift
grep -q 'status == 409' ios-resources/LocationTracking.swift
grep -q 'AES.GCM.seal' ios-resources/SecureGpsQueue.swift
grep -q 'completeFileProtectionUntilFirstUserAuthentication' ios-resources/SecureGpsQueue.swift
grep -q 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' ios-resources/SecureGpsQueue.swift
grep -q 'defaults.removeObject(forKey: legacyKey)' ios-resources/SecureGpsQueue.swift
grep -q 'expectedData == roundTripData' ios-resources/SecureGpsQueue.swift
grep -Fq 'options: [.sortedKeys]' ios-resources/SecureGpsQueue.swift
grep -q 'secure_queue_corrupt' ios-resources/SecureGpsQueue.swift
if grep -E 'defaults\.(set|array).*queueKey' ios-resources/LocationTracking.swift; then
  echo "plaintext iOS GPS queue access remains in LocationTracking.swift" >&2
  exit 1
fi
grep -q 'SecureGpsQueue.swift' setup-mac.sh
grep -q 'SecureGpsQueue.swift' .github/workflows/ios-testflight.yml
alarm_end_line=$(awk '/unless grp.files.any.*alarm.caf/{inside=1} inside && /^[[:space:]]+end$/{print NR; exit}' .github/workflows/ios-testflight.yml)
project_save_line=$(awk '/^[[:space:]]+proj.save$/{print NR; exit}' .github/workflows/ios-testflight.yml)
if [ -z "$alarm_end_line" ] || [ -z "$project_save_line" ] || [ "$project_save_line" -le "$alarm_end_line" ]; then
  echo "Xcode project save must remain outside alarm.caf conditional" >&2
  exit 1
fi
grep -q 'LocationTracking.swift.*App-Target' setup-mac.sh
grep -q 'LocationTracking.swift' .github/workflows/ios-testflight.yml
grep -q 'startForeground' android-template/MiseLocationService.kt
grep -q 'authorizeFromCanonicalSnapshot' android-template/MiseLocationService.kt
grep -q '/api/driver/v2/snapshot' android-template/MiseLocationService.kt
grep -q 'LocationServices.getFusedLocationProviderClient' android-template/MiseLocationService.kt
grep -q 'QUEUE_LIMIT = 100' android-template/MiseLocationService.kt
grep -q 'play-services-location' scripts/setup-android-location.sh
grep -q 'security-crypto' scripts/setup-android-location.sh
grep -q 'EncryptedSharedPreferences' android-template/SecureGpsStore.kt
grep -q 'startForegroundService' android-template/MiseLocationBridge.kt
grep -q 'locationBridge.reconcile' android-template/MainActivity.kt
grep -q 'ACCESS_BACKGROUND_LOCATION' android-template/AndroidManifest.xml
echo "native location source integration: PASS"
