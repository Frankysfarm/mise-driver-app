# Mise Driver — Native iOS-App für TestFlight

**Multi-Tenant Fahrer-App** mit Smart-Delivery-System — eine App für alle Restaurants. Fahrer loggt sich mit eigenem Account ein, sieht zugewiesene Touren mit GPS-Tracking, Multi-Stop-Navigation und Live-ETA.

## Offer-Notification-Vertrag

Normale Lieferangebote sollen als Standard-APNs-Alerts eintreffen. PushKit und
CallKit bleiben nur als feature-gesteuerter Kompatibilitätspfad erhalten,
solange das Backend auf APNs-First migriert. Sie sind für Angebote ohne echten
Telefonanruf nicht der kanonische Zustellkanal.

Jede neue Payload soll `offer_id`, `batch_id` und die positive ganzzahlige
`assignment_version` enthalten. Alte Payloads mit ausschließlich `batch_id`
bleiben lesbar und erhalten deterministisch `legacy-batch:<batch_id>` als
Offer-ID.

Die native Schicht nimmt keine Tour an. Sie sendet das DOM-Event
`mise-driver-offer` mit den kanonischen Top-Level-Feldern `event_id`, `stage`,
`offer_id`, `batch_id`, `assignment_version` und `ack_url`. `stage` ist
`received`, `displayed`, `opened`, `answered` oder `ended`. Die Web-App bleibt
die einzige Accept-/Decline-Quelle.

Ein erfolgreiches `evaluateJavaScript` ist noch kein App-ACK. Das Event enthält
deshalb zusätzlich `event_id` und `ack_url`. Erst nachdem die Web-App das Event
idempotent in ihren Zustand übernommen hat, quittiert sie explizit:

```js
window.MiseDriverNativeBridge.ack(event.detail)
```

Bis dahin bleibt das Event über Prozessstarts erhalten und wird beim nächsten
Foreground erneut gesendet; nach 24 Stunden läuft es aus. Nach einem Login oder
Tokenwechsel stößt die Web-App die native Token-Reconciliation über
`mise-driver://auth-changed` an.

Sobald der Live-Webclient seinen Offer-Listener installiert hat, kann er mit
`mise-driver://bridge-ready` sofort eine neue Replay-Runde anfordern. Ohne
Handshake versucht die native Hülle begrenzt nach 1, 3, 10 und 30 Sekunden und
pausiert dann bis zum nächsten Foreground/Handshake; es gibt keine Busy-Loop.

`MiseLegacyVoipOffersEnabled` steht aus Kompatibilitätsgründen zunächst auf
`true`. Der APNs-First-Release setzt es erst dann auf `false`, wenn der Server
keine Lieferangebote mehr als VoIP-Anrufe sendet.

## Was die App tut

- **WebView lädt** `mise-gastro.de/fahrer/app` — Smart-Delivery-Code bleibt im Backoffice
- **GPS-Background-Tracking** für Live-Kundenposition
- **Push-Notifications** für neue Touren-Zuweisungen
- **Multi-Tenant** über Supabase Auth + RLS: Fahrer sieht nur eigene Touren
- **Updates** ohne neuen App-Store-Build (Live-URL pattern)
- **Apple-Review-fähig**: GPS-Hintergrund + Push als nativer Mehrwert dokumentiert

## Voraussetzungen auf deinem Mac

| Was | Wie kriegen |
|---|---|
| **macOS 13+** mit Xcode 15+ | Mac App Store (gratis) |
| **Node.js 20+** | `brew install node` |
| **CocoaPods** | `sudo gem install cocoapods` |
| **Apple Developer Account** | $99/Jahr, Team-ID zur Hand |
| **iPhone** mit iOS 16+ zum Testen | optional |

---

## 🚀 Komplett-Anleitung: TestFlight in ~15 Min

### Schritt 1 — Repo runterziehen

```bash
git clone https://github.com/Frankysfarm/mise-driver-app.git
cd mise-driver-app
```

### Schritt 2 — Setup-Script ausführen (macht alles)

```bash
./setup-mac.sh
```

Das Script macht automatisch:
- npm install
- iOS-Projekt erstellen
- Permissions in Info.plist (GPS Background, Kamera, Push)
- Icons + Splash generieren
- Capacitor sync
- Xcode öffnen

### Schritt 3 — Apple Developer Team setzen (Xcode)

1. Im Project Navigator links: **App** klicken
2. Tab **Signing & Capabilities**
3. **Team:** dein Apple-Developer-Team auswählen
4. **Bundle Identifier:** `app.mise.driver`

### Schritt 4 — App auf iPhone testen (Xcode)

1. iPhone per Kabel mit Mac verbinden
2. Oben in Xcode: iPhone als **Run-Target** auswählen
3. **Cmd-R** → App startet auf iPhone
4. GPS/Kamera/Push erlauben
5. Login mit Fahrer-Account testen

### Schritt 5 — Production-Archive für TestFlight

1. Oben Run-Target auf **„Any iOS Device (arm64)"** umstellen
2. **Product → Archive** (dauert 2-3 Min)
3. **Organizer**-Fenster öffnet sich
4. **Distribute App** → **App Store Connect** → **Upload**

### Schritt 6 — TestFlight aktivieren (App Store Connect Web)

1. https://appstoreconnect.apple.com → **Meine Apps**
2. **+ → Neue App**
3. Plattform: **iOS** · Name: **Mise Driver** · Bundle-ID: `app.mise.driver`
4. Sprache: **Deutsch** · Kategorie: **Wirtschaft**
5. Tab **TestFlight** → dein Build erscheint nach 5-15 Min
6. **Test-Informationen** ausfüllen:
   - Beschreibung: „Fahrer-App für Restaurant-Lieferdienste. Smart-Touren-Bündelung, Live-GPS-Tracking, Multi-Stop-Navigation."
   - Login: Fahrer-Account einfügen
7. **Internes Testing** → Tester einladen

---

## 🎯 Apple-Review-Notes (wichtig!)

**Beim TestFlight-Submit** im Feld „Notes for Reviewer":

```
Mise Driver is a multi-tenant delivery driver app. The webview is
the main UI (shared web/native architecture), but native features
are essential and cannot be done in a browser PWA:

1. Background GPS location tracking — drivers need their position
   shared with customers and dispatch even when the screen is off
   or another app is in foreground
2. Push notifications for incoming order assignments — drivers must
   be alerted instantly when a new tour is assigned
3. Camera for QR-code login and delivery proof photos
4. Haptic feedback for order confirmation

Test login:
  Email: [Fahrer-Account]
  Password: [Passwort]

After login, drivers see their assigned tours with optimized stop
order, live ETAs per stop, and one-tap navigation to Apple/Google
Maps.
```

---

## 🔄 Updates ohne neuen App-Store-Build

Da der WebView die Live-URL lädt, sind Updates am Smart-Delivery-Code **sofort live** — kein neuer App-Store-Build nötig. Native-App-Updates braucht es nur wenn:

- Neue Permissions (z.B. NFC, Apple Pay)
- Neue Capacitor-Plugins
- iOS-System-Updates erzwingen Rebuild

---

## 📦 Was im Repo ist

```
mise-driver-app/
├── capacitor.config.ts       # GPS-Background + Push + Multi-Tenant
├── package.json              # Capacitor 6 + Geolocation + Push + Camera
├── ios-template/Info.plist   # GPS/Kamera/Background-Permissions
├── resources/
│   ├── icon.svg              # 1024×1024 Mise-Logo
│   ├── icon.png              # 1024×1024 PNG (für Capacitor Assets)
│   ├── splash.svg            # 2732×2732
│   └── splash.png            # 2732×2732 PNG
├── setup-mac.sh              # One-Click Setup
└── README.md                 # Diese Datei
```
