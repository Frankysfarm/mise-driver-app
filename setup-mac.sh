#!/usr/bin/env bash
# Mise Driver — One-Command-Setup für deinen Mac
#
# Voraussetzung:
#   - Xcode installiert + einmal geöffnet (Lizenz akzeptiert)
#   - Node.js >= 18
#   - Apple Developer Account in Xcode hinterlegt
#
# Nach Erfolg: Xcode öffnet sich → Team auswählen → Archive → TestFlight

set -e

cd "$(dirname "$0")"

echo "▸ 1/5 — Dependencies installieren..."
npm install

echo "▸ 2/5 — iOS-Projekt erzeugen (einmalig)..."
if [ ! -d "ios" ]; then
  npx cap add ios
fi

echo "▸ 3/5 — Permissions in Info.plist ergänzen..."
INFO_PLIST="ios/App/App/Info.plist"
if [ -f "$INFO_PLIST" ] && ! grep -q "NSLocationWhenInUseUsageDescription" "$INFO_PLIST"; then
  # Permissions vor </dict></plist> einfügen
  /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string 'Mise Driver braucht deinen Standort um deine Position der Lieferzentrale und dem Kunden anzuzeigen.'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :NSLocationAlwaysAndWhenInUseUsageDescription string 'Mise Driver braucht Hintergrund-Standort um deine Live-Position auch dann zu aktualisieren, wenn der Bildschirm aus ist.'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'Mise Driver braucht die Kamera für QR-Code-Login und Liefer-Foto-Beweise.'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string 'Mise Driver speichert Liefer-Fotos als Beleg.'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$INFO_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string location" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:1 string remote-notification" "$INFO_PLIST"
  echo "  ✓ Permissions hinzugefügt"
else
  echo "  → Permissions schon vorhanden, überspringe"
fi

echo "▸ 4/5 — App-Icons + Splash generieren..."
if ! npm list @capacitor/assets >/dev/null 2>&1; then
  npm install -D @capacitor/assets
fi
npx @capacitor/assets generate \
  --iconBackgroundColor '#09090b' \
  --iconBackgroundColorDark '#09090b' \
  --splashBackgroundColor '#09090b' \
  --splashBackgroundColorDark '#09090b' || echo "  (Assets-Plugin braucht resources/icon.png + splash.png — SVG-Variante bitte vorher zu PNG konvertieren)"

echo "▸ 5/5 — Sync + Xcode öffnen..."
npx cap sync ios
npx cap open ios

echo ""
echo "✅ Fertig!"
echo ""
echo "In Xcode:"
echo "  1. Klick auf 'App' → 'Signing & Capabilities' → Team auswählen"
echo "  2. Product → Archive (oben in der Menüleiste)"
echo "  3. Window → Organizer → Distribute App → App Store Connect → Upload"
echo "  4. TestFlight-Bereich in App Store Connect → Tester hinzufügen"
