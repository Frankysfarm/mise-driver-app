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
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:2 string voip" "$INFO"

  /usr/libexec/PlistBuddy -c "Delete :MiseLegacyVoipOffersEnabled" "$INFO" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :MiseLegacyVoipOffersEnabled bool true" "$INFO"
  python3 scripts/ensure_url_scheme.py "$INFO"

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
  cp "ios-resources/OfferContract.swift" "$APP_DIR/OfferContract.swift"
  echo "  ✓ AppDelegate.swift (mit VoIP-Ringtone-Config) kopiert"
fi
if [ -f "ios-resources/LocationTracking.swift" ] && [ -d "$APP_DIR" ]; then
  cp "ios-resources/LocationTracking.swift" "$APP_DIR/LocationTracking.swift"
  cp "ios-resources/SecureGpsQueue.swift" "$APP_DIR/SecureGpsQueue.swift"
  ruby -e 'require "xcodeproj"; p=Xcodeproj::Project.open(ARGV[0]); t=p.targets.find{|x|x.name=="App"}; g=p.main_group.find_subpath("App",true); ARGV.drop(1).each{|name| r=g.files.find{|x|x.path==name}||g.new_reference(name); t.add_file_references([r]) unless t.source_build_phase.files_references.include?(r)}; p.save' "$PBX_FILE" LocationTracking.swift SecureGpsQueue.swift
  echo "  ✓ LocationTracking.swift + SecureGpsQueue.swift kopiert und dem App-Target hinzugefügt"
fi

# alarm.caf und OfferContract robust/idempotent ins Xcode-Projekt eintragen
if [ -f "$PBX_FILE" ]; then
  USER_GEM_HOME="$(ruby -e 'puts Gem.user_dir')"
  gem install --user-install xcodeproj --no-document --silent
  GEM_HOME="$USER_GEM_HOME" ruby -e '
    require "xcodeproj"
    proj = Xcodeproj::Project.open("ios/App/App.xcodeproj")
    target = proj.targets.find { |t| t.name == "App" }
    grp = proj.main_group.find_subpath("App", true)
    alarm_ref = grp.files.find { |f| f.path == "alarm.caf" } || grp.new_reference("alarm.caf")
    unless target.resources_build_phase.files_references.include?(alarm_ref)
      target.resources_build_phase.add_file_reference(alarm_ref)
    end
    offer_ref = grp.files.find { |f| f.path == "OfferContract.swift" } || grp.new_reference("OfferContract.swift")
    unless target.source_build_phase.files_references.include?(offer_ref)
      target.source_build_phase.add_file_reference(offer_ref)
    end
    abort "alarm.caf missing from Resources" unless target.resources_build_phase.files_references.include?(alarm_ref)
    abort "OfferContract.swift missing from Sources" unless target.source_build_phase.files_references.include?(offer_ref)
    proj.save
  '
  echo "  ✓ alarm.caf + OfferContract.swift im Xcode-Projekt"
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
