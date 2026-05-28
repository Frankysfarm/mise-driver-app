# Mise Driver — Native App

iOS/Android Wrapper für die Fahrer-Web-App unter `https://mise-gastro.de/driver`.

## Architektur

Capacitor-WebView lädt `https://mise-gastro.de/driver` direkt → Live-Updates ohne neuen App-Store-Build.

## Build

```bash
cd /opt/mise/driver-native
npm install
npm run add:ios       # einmalig: erzeugt ios/ Folder
npm run ios           # öffnet Xcode
```

In Xcode:
1. Team auswählen (Signing & Capabilities)
2. Bundle-ID prüfen: `app.mise.driver`
3. „Archive" → „Distribute App" → TestFlight

## Permissions (Info.plist)

Die wichtigen Keys werden in `ios/App/App/Info.plist` gepflegt:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Mise Driver braucht deinen Standort für Live-Tracking während der Lieferung.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Mise Driver braucht Hintergrund-Standort um deine Position auch dann zu aktualisieren, wenn der Bildschirm aus ist.</string>

<key>NSCameraUsageDescription</key>
<string>Mise Driver braucht die Kamera für QR-Code-Scan und Liefer-Foto-Beweise.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Mise Driver speichert Liefer-Fotos in deiner Fotomediathek.</string>

<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>remote-notification</string>
</array>
```

## App-Icon & Splash

`resources/icon.svg` und `resources/splash.svg` mit dem Capacitor Assets Plugin generieren:

```bash
npm install -D @capacitor/assets
npx @capacitor/assets generate --iconBackgroundColor "#09090b" --splashBackgroundColor "#09090b"
```

## Pilot-Workflow

1. Fahrer installiert App via TestFlight-Invite
2. Beim Start: Auto-Redirect auf `mise-gastro.de/driver`
3. Driver-App-Login erfolgt über die Web-Page (Code/Magic-Link)
4. Live-Bestellungen via Polling/Realtime aus dem Mise-Backend
