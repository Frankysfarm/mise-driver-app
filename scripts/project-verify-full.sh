#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

echo "== Driver native project verification =="
npm run test:location

node -e '
const fs = require("node:fs");
for (const path of ["app.json", "package.json"]) JSON.parse(fs.readFileSync(path, "utf8"));
console.log("native JSON configuration: PASS");
'

ruby -c scripts/integrate-android-location.rb >/dev/null
ruby -c scripts/integrate-android-gradle.rb >/dev/null
echo "Android manifest integration script syntax: PASS"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint ios-template/Info.plist >/dev/null
  echo "iOS Info.plist syntax: PASS"
fi

if [[ -d ios && -x "$(command -v xcodebuild 2>/dev/null || true)" ]]; then
  xcodebuild -project ios/App/App.xcodeproj -scheme App \
    -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
else
  echo "[project-verify] iOS project/Xcode unavailable; compiled iOS evidence remains external."
fi

BREW_JDK="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
if [[ -d "${BREW_JDK}" ]]; then
  export JAVA_HOME="${BREW_JDK}"
  export PATH="/opt/homebrew/opt/openjdk@17/bin:${PATH}"
fi
ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
if [[ -x android/gradlew ]] && command -v java >/dev/null 2>&1 && [[ -d "${ANDROID_SDK}" ]]; then
  ANDROID_HOME="${ANDROID_SDK}" android/gradlew -p android assembleDebug
elif [[ ! -x android/gradlew ]]; then
  echo "[project-verify] Android project unavailable; generate it with setup-android-location.sh."
elif ! command -v java >/dev/null 2>&1; then
  echo "[project-verify] Java unavailable; compiled Android evidence remains external."
else
  echo "[project-verify] Android SDK unavailable; compiled Android evidence remains external."
fi

echo "== Driver native project verification complete =="
