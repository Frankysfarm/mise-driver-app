#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d android || npx cap add android
mkdir -p android/app/src/main/java/app/mise/driver/location
cp android-template/MiseLocationService.kt android-template/MiseLocationBridge.kt android-template/SecureGpsStore.kt android/app/src/main/java/app/mise/driver/location/
cp android-template/MainActivity.kt android-template/SecureTokenAccess.kt android/app/src/main/java/app/mise/driver/
MANIFEST=android/app/src/main/AndroidManifest.xml
ruby scripts/integrate-android-location.rb "$MANIFEST"
GRADLE=android/app/build.gradle
ruby scripts/integrate-android-gradle.rb "$GRADLE"
npx cap sync android
echo "Android location service integrated; run android/gradlew -p android assembleDebug."
