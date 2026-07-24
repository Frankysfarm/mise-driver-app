#!/usr/bin/env bash
# ============================================================
# Mise Driver — Ein-Klick Setup für Mac
# ============================================================
# Führe dieses Script einmal aus, dann öffnet sich Xcode.
# Du musst nur noch:
#  1. Team auswählen (Signing & Capabilities)
#  2. Product → Archive
#  3. Distribute App → App Store Connect → Upload
# ============================================================

set -e
cd "$(dirname "$0")"

echo ""
echo "🚀 Mise Driver — TestFlight Setup"
echo "=================================="
echo ""

# Check Voraussetzungen
command -v node >/dev/null 2>&1 || { echo "❌ Node.js fehlt. Install: brew install node"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "❌ npm fehlt"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "❌ Xcode fehlt. Install: App Store"; exit 1; }

echo "✓ Voraussetzungen OK"
echo ""

# Step 1: Dependencies
echo "▸ 1/6 — Installiere Dependencies..."
npm install --silent

# Step 2: iOS-Projekt
echo "▸ 2/6 — iOS-Projekt vorbereiten..."
if [ ! -d "ios" ]; then
  npx cap add ios
  echo "  ✓ iOS-Projekt erstellt"
else
  echo "  → iOS-Projekt existiert"
fi

# Step 3: Permissions
echo "▸ 3/6 — Permissions in Info.plist..."
INFO="ios/App/App/Info.plist"
if [ -f "$INFO" ]; then
  /usr/libexec/PlistBuddy -c "Delete :NSLocationWhenInUseUsageDescription" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string 'Mise Driver braucht deinen Standort um Lieferzentrale und Kunden deine Position zu zeigen.'" "$INFO"

  /usr/libexec/PlistBuddy -c "Delete :NSLocationAlwaysAndWhenInUseUsageDescription" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSLocationAlwaysAndWhenInUseUsageDescription string 'Mise Driver braucht Hintergrund-Standort fuer Live-Tracking waehrend der Lieferung.'" "$INFO"

  /usr/libexec/PlistBuddy -c "Delete :NSCameraUsageDescription" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'Mise Driver braucht die Kamera fuer QR-Login und Liefer-Beweis-Fotos.'" "$INFO"

  /usr/libexec/PlistBuddy -c "Delete :NSPhotoLibraryAddUsageDescription" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string 'Mise Driver speichert Liefer-Beweis-Fotos.'" "$INFO"

  /usr/libexec/PlistBuddy -c "Delete :UIBackgroundModes" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$INFO"
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string location" "$INFO"
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:1 string remote-notification" "$INFO"

  echo "  ✓ Permissions gesetzt"
fi

# Step 4: Icons + Splash
echo "▸ 4/6 — Icons + Splash generieren..."
if ! npm list @capacitor/assets >/dev/null 2>&1; then
  npm install -D @capacitor/assets --silent
fi
npx @capacitor/assets generate --ios \
  --iconBackgroundColor '#09090b' \
  --iconBackgroundColorDark '#09090b' \
  --splashBackgroundColor '#09090b' \
  --splashBackgroundColorDark '#09090b' 2>&1 | tail -3 || echo "  ⚠ Icons brauchen icon.png + splash.png in resources/"

# Step 5: Sync
echo "▸ 5/7 — Capacitor sync..."
npx cap sync ios

# Step 5b: alarm.caf + AppDelegate ins iOS-Projekt kopieren und in Xcode-Projekt eintragen
echo "▸ 5b — Sound-Datei (alarm.caf) + AppDelegate einrichten..."
APP_DIR="ios/App/App"
PBX_FILE="ios/App/App.xcodeproj/project.pbxproj"

# alarm.caf kopieren
if [ -f "ios-resources/alarm.caf" ] && [ -d "$APP_DIR" ]; then
  cp "ios-resources/alarm.caf" "$APP_DIR/alarm.caf"
  echo "  ✓ alarm.caf nach $APP_DIR kopiert"
else
  echo "  ⚠ alarm.caf oder App-Ordner nicht gefunden"
fi

# AppDelegate.swift kopieren (enthält ringtoneSound = "alarm.caf")
if [ -f "ios-resources/AppDelegate.swift" ] && [ -d "$APP_DIR" ]; then
  cp "ios-resources/AppDelegate.swift" "$APP_DIR/AppDelegate.swift"
  echo "  ✓ AppDelegate.swift (mit VoIP-Ringtone-Config) kopiert"
fi

# alarm.caf in project.pbxproj eintragen (idempotent: nur wenn noch nicht vorhanden)
if [ -f "$PBX_FILE" ] && ! grep -q "alarm.caf" "$PBX_FILE"; then
  # PBXBuildFile
  sed -i '' 's/MISE008BB0002CALLKIT0004 \/\* CallKit.framework in Frameworks \*\/ = {isa = PBXBuildFile;/MISE00CC0001ALARM0CAF002 \/* alarm.caf in Resources *\/ = {isa = PBXBuildFile; fileRef = MISE00CC0001ALARM0CAF001 \/* alarm.caf *\/; };\n\t\tMISE008BB0002CALLKIT0004 \/* CallKit.framework in Frameworks *\/ = {isa = PBXBuildFile;/' "$PBX_FILE"
  # PBXFileReference
  sed -i '' 's/MISE008AA0002CALLKIT0003 \/\* CallKit.framework \*\/ = {isa = PBXFileReference;/MISE00CC0001ALARM0CAF001 \/* alarm.caf *\/ = {isa = PBXFileReference; lastKnownFileType = audio.aiff-c; path = alarm.caf; sourceTree = "<group>"; };\n\t\tMISE008AA0002CALLKIT0003 \/* CallKit.framework *\/ = {isa = PBXFileReference;/' "$PBX_FILE"
  # PBXGroup (App)
  sed -i '' 's/2FAD9762203C412B000D30F8 \/\* config.xml \*\/,/2FAD9762203C412B000D30F8 \/* config.xml *\/,\n\t\t\t\tMISE00CC0001ALARM0CAF001 \/* alarm.caf *\/,/' "$PBX_FILE"
  # PBXResourcesBuildPhase
  sed -i '' 's/2FAD9763203C412B000D30F8 \/\* config.xml in Resources \*\/,/2FAD9763203C412B000D30F8 \/* config.xml in Resources *\/,\n\t\t\t\tMISE00CC0001ALARM0CAF002 \/* alarm.caf in Resources *\/,/' "$PBX_FILE"
  echo "  ✓ alarm.caf in project.pbxproj eingetragen"
else
  echo "  → alarm.caf bereits in project.pbxproj"
fi

# Step 6: Build-Nummer + Version setzen
# WICHTIG: 'cap add ios' erzeugt IMMER Build-Nummer 1. Auf der App-Store-Connect-App
# (app.mise.driver) existierten aber schon Builds bis 14 — ein Upload mit Build 1 (oder
# einer schon benutzten Nummer) wird von Apple ABGELEHNT ("build number must be higher").
# Lösung: datums-basierte Build-Nummer (JJJJMMTTHHMM) — bei jedem Build automatisch höher,
# nie wieder eine Ablehnung, kein manuelles Hochzählen nötig.
echo "▸ 6/7 — Build-Nummer + Version setzen..."
PBX="ios/App/App.xcodeproj/project.pbxproj"
BUILD_NO="$(date +%Y%m%d%H%M)"
if [ -f "$PBX" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9.]*;/CURRENT_PROJECT_VERSION = ${BUILD_NO};/g" "$PBX"
  sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = 1.0.0;/g" "$PBX"
  echo "  ✓ Build-Nummer ${BUILD_NO}, Version 1.0.0"
else
  echo "  ⚠ project.pbxproj nicht gefunden — Build-Nummer manuell in Xcode setzen (> 14)!"
fi

# Step 7: Xcode öffnen
echo "▸ 7/7 — Xcode öffnen..."
npx cap open ios

echo ""
echo "============================================"
echo "✅ FERTIG! Xcode öffnet sich jetzt"
echo "============================================"
echo ""
echo "Nächste Schritte in Xcode:"
echo ""
echo "  1️⃣  Links: Klick auf 'App' (Projekt-Root)"
echo "  2️⃣  'Signing & Capabilities' Tab"
echo "  3️⃣  Team auswählen (Apple Developer Account)"
echo "  4️⃣  Bundle Identifier: app.mise.driver"
echo ""
echo "  5️⃣  Oben: 'Any iOS Device (arm64)' wählen"
echo "  6️⃣  Menü: Product → Archive"
echo "  7️⃣  Im Organizer-Fenster: 'Distribute App'"
echo "  8️⃣  → 'App Store Connect' → 'Upload'"
echo ""
echo "  9️⃣  Auf appstoreconnect.apple.com:"
echo "      → TestFlight Tab (Build erscheint nach ~10 Min)"
echo "      → Tester einladen → Fertig!"
echo ""
