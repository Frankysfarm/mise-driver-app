Datei erstellt: `/Users/eule/frankys-steuer/docs/accounting-agent-pack/reports/CURRENT-SYSTEM-INVENTORY.md`

# CURRENT-SYSTEM-INVENTORY — mise-gastro Liefersystem

Stand: 2026-07-23 · Quelle: 5 Analyseberichte (Frank Dispatch Engine, Fahrer-Web-App, Capacitor iOS App, Server-Infrastruktur, mise-os Lieferzentrale)

---

# 1. Systemarchitektur

## 1.1 Komponenten und Verantwortlichkeiten

| Komponente | Technologie | Ort | Verantwortlichkeit |
|---|---|---|---|
| **Frank Dispatch Engine** (`frank.ts`) | TypeScript im Next.js-Backoffice | `/opt/mise/backoffice` (Container `mise_backoffice_3300/3310`) | Zentraler Dispatch-Kern: `dispatchTick()` per Cron jede Minute, Order→Fahrer-Zuweisung, Multi-Stop-Batching, Google-Directions-Routenoptimierung (TSP), Sibling-Hold, Stale-Tour-Rescue, Fahrer-Eskalation, Betreiber-Alerts |
| **Backoffice / Web-Plattform** | Next.js 15, Docker Blue-Green (Ports 3300/3310) | `/opt/mise/backoffice` | Hostet alle Web-Oberflächen: `(admin)`, `(neo)`, `fahrer`, `kuche`, `pos`, `delivery-progress` + alle `/api/*`-Routen inkl. Cron-Endpoints |
| **Fahrer-Web-App** | Next.js PWA unter `/fahrer/app` | Teil des Backoffice | Online/Offline-Toggle, Tour-Empfang mit Alarm, Pick-Phase (Item-Bestätigung via RPC), Liefer-Phase (Stop-Navigation, Proof-of-Delivery), GPS-Tracking (3-Modus), Offline-Queues (`outbox`, `gps_queue`), Broadcasts, Shift-Ende |
| **Capacitor iOS Driver App** | Native Swift-Shell (`app.mise.driver`), lädt `https://mise-gastro.de/fahrer/app` | Repo `mise-driver-app`, CI via GitHub Actions `ios-testflight.yml` | Native Features: PushKit/VoIP, CallKit-Anrufmaske, Hintergrund-GPS, Token-Handling via `CapacitorStorage`. Kein eigenes Frontend — reine WebView-Hülle |
| **Storefront** | Docker `franky_storefront`, Port 3500 | `/opt/franky-storefront` | Kundenseitiger Shop (`/bilder/`, `/biss-app`), erzeugt Bestellungen |
| **POS-Module** | Ports 3100 (API), 3102 (Terminal), 3103 (Admin) | Server | Kassen-Stack, via nginx-Pfade eingebunden |
| **Supabase (self-hosted)** | Kong-Gateway Port 3301, erreichbar als `mise-gastro.de/(auth\|rest\|realtime\|storage\|...)/v1/` und `api.mise-gastro.de` | Server | Zentrale Datenbank: `mise_*`-Tabellen (Batches, Stops, Drivers, Decisions, Alerts), `customer_orders`, `locations`, `tenants`, Push-Subscriptions, Realtime-Channels für Fahrer-App |
| **mise_cron** | Alpine-Container | Server | Feuert `GET /api/cron/smart-dispatch` jede Minute (Trigger für `dispatchTick`) |
| **nginx** | Vhosts `mise-gastro.de`, `api.mise-gastro.de`, Ports 80/443/87/8090 | `/etc/nginx` | Routing + Blue-Green-Schalter via `/etc/nginx/conf.d/mise-upstream.conf` |
| **mise-os Lieferzentrale** | React+Vite Frontend, Fastify+Prisma Backend (lokal, mandantenfähig) | separates Projekt | Backoffice-Modul für Online-Lieferdienst: Speisekarte, Shop-Config (Liefergebiet, Gebühren, Optionsgruppen), Bestell-Workflow mit 30s-Polling. **Kein Webhook, kein Push, kein Realtime** |

## 1.2 Datenflüsse

```
Kunde (Storefront :3500 / Shop)
        │  Bestellung → customer_orders (Supabase)
        ▼
mise_cron (jede Minute) ──GET /api/cron/smart-dispatch──▶ Frank dispatchTick()
        │
        ├─ Geocoding (Google) → Sibling-Hold-Check → Fahrer-Selektion (pickBest)
        ├─ createBundle()/addOrderToBundle() → mise_delivery_batches + _stops
        ├─ rerouteBundle() → Google Directions TSP (Fallback Haversine)
        ├─ mise_frank_decisions (Audit + "Advisory-Lock")
        └─ Kein Fahrer >5 min → mise_alerts + web-push an owner_push_subscriptions
        │
        ▼
Fahrer-Benachrichtigung
        ├─ iOS nativ: VoIP-Push (PushKit) → CallKit-Anrufmaske → Accept → WebView vorgeholt
        └─ Web/PWA: Supabase Realtime auf delivery_batches/customer_orders → AlarmRinger
        │
        ▼
Fahrer-Web-App (/fahrer/app)
        ├─ Accept: POST /api/driver/v1/batches/[id]/accept
        ├─ Pick: confirm_pick_item RPC + Küchenstatus via Realtime
        ├─ GPS: POST /api/driver/v1/me/position (10s-Rate-Limit, Offline-Queue)
        ├─ Heartbeat: POST /me/heartbeat alle 15s (unterdrückt VoIP wenn App aktiv)
        └─ Zustellung: Proof-Types, Fehlzustellungs-Flow, Offline-Outbox (localStorage)
        │
        ▼
Status zurück → customer_orders / batch_stops → Backoffice, Küche, delivery-progress

Parallel-System: mise-os Lieferzentrale (Fastify/Prisma, eigene lieferKategorie/
lieferArtikel/Order-Tabellen, 30s-Polling) — Integrationspfad zu Frank/Supabase UNKLAR.
```

## 1.3 Externe Abhängigkeiten

- **Google Maps Platform**: Geocoding (Adresse→Koordinaten) und Directions API (TSP-Routenoptimierung, ETAs). Fallback: Haversine.
- **Apple**: APNs (Remote-Push) + PushKit/VoIP + CallKit; App Store Connect (TestFlight-Upload via CI, Provisioning-Profil hardcoded).
- **web-push (VAPID)**: Betreiber-Alerts an `owner_push_subscriptions`.
- **Stripe**: Webhook `/api/stripe/webhook` → mise_app.
- **GitHub Actions** (`macos-26`-Runner): iOS-Build-Pipeline.
- **Supabase-Stack** (self-hosted via docker-compose): Kong, Auth, Rest, Realtime, Storage, Postgres; tägliches DB-Backup 03:30.

---

# 2. Kritische Nutzerflüsse (Ist-Stand)

## Bestellung → Dispatch → Fahrer → Lieferung

| # | Schritt | Status | Anmerkung |
|---|---|---|---|
| 1 | Bestellung geht ein (`customer_orders`) | ✅ funktioniert | Storefront/Shop schreibt Order; mise-os-Orders laufen in einem separaten System (Integrationslücke) |
| 2 | Cron triggert `dispatchTick` (1/min) | ⚠️ lückenhaft | "Advisory-Lock" ist TOCTOU-anfällig (SELECT-dann-INSERT, kein echter Lock); Tick kann >1 min dauern → äußerer Cron und innerer Lock nicht synchronisiert |
| 3 | Geocoding + Sibling-Hold | ⚠️ lückenhaft | Kein Fehlzähler bei Geocoding-Dauerfehlern (Order kann ewig hängen); Hold kann auf bereits abgeschlossene Sibling-Order zeigen → unnötige Wartezeit bis `dispatch_after` |
| 4 | Fahrer-Selektion + Batch-Erstellung | ❌ kritisch lückenhaft | `createBundle()` = 3 nicht-transaktionale Writes → Order kann in ZWEI Batches landen (Doppelzuweisung, Küche kocht doppelt). Merge-Pfad ignoriert `VEHICLE_SLOTS` (Bike kann überladen werden). Multi-Pickup-Batches werden nach Merge nie mehr routenoptimiert |
| 5 | Fahrer-Benachrichtigung (VoIP/Realtime) | ⚠️ lückenhaft | CallKit-Accept übergibt `batch_id` NICHT an den WebView (Race bei mehreren Pushes); VoIP-Token-Registrierung kann still scheitern (18s-Polling-Limit, Upload ohne Fehlerhandling); eingefrorener iOS-Heartbeat → Doppelklingeln |
| 6 | Accept/Decline in der App | ✅ weitgehend | AlarmRinger ohne Max-Klingeldauer bei hängender Realtime-Verbindung |
| 7 | Pick-Phase im Restaurant | ⚠️ lückenhaft | Realtime-Update kann lokal bestätigte Items optisch zurücksetzen (`setLocal(items)`-Overwrite) |
| 8 | GPS-Tracking während Lieferung | ⚠️ lückenhaft | 30s-Hintergrund-Keepalive wird von iOS auf ≥60s gedrosselt (ETAs ungenau); GPS-Queue und Outbox haben getrennte, nicht synchron geflushte Pfade |
| 9 | Zustellbestätigung | ⚠️ lückenhaft | Offline-Outbox ohne Idempotenz → "Geliefert" kann doppelt gesendet werden; FIFO-Overflow verwirft bei >50 Einträgen die ÄLTESTEN (kritischsten) Aktionen |
| 10 | Fahrer antwortet nicht (Rescue) | ⚠️ lückenhaft | `rescueStaleTours()` greift, setzt aber `hold_reason`/`dispatch_after` freigegebener Orders nicht zurück und heilt inkonsistente Order-Records (batch_id ohne driver_id) nicht |
| 11 | Kein Fahrer verfügbar (Eskalation) | ⚠️ lückenhaft | Alert-Throttle ist In-Memory und pro Worker-Prozess → möglicher Alert-Spam bei mehreren Prozessen |
| 12 | Backoffice-Sicht (mise-os Lieferzentrale) | ❌ kritisch lückenhaft | Deaktivierte Artikel verschwinden dauerhaft aus der UI; Kategorien-Delete löscht alle Artikel hart ohne Warnung; Detail-Panel veraltet; kein Bestellton |

**Fazit:** Der Happy Path funktioniert Ende-zu-Ende. Die Lücken liegen fast alle in Nebenläufigkeit (Doppelzuweisung), Offline-/Hintergrund-Verhalten (iOS) und stillen Fehlern (VoIP-Token, Config-Overwrite, Phantom-Deploys).

---

# 3. Prioritätenliste P0–P3

## P0 – Kritisch (Datenverlust / Systemausfall / doppelte Zuweisung)

### P0-1: Doppelzuweisung von Orders durch nicht-atomaren Dispatch
- **Problem:** Der "Advisory-Lock" in `dispatchTick` ist ein SELECT-dann-INSERT auf `mise_frank_decisions` (TOCTOU); `createBundle()` macht 3 sequenzielle, nicht-transaktionale Writes (Batch → Stops → Order-Update); `addOrderToBundle()` setzt `mise_batch_id` und `mise_driver_id` in getrennten Updates.
- **Ursache:** Supabase-JS-Client kann keine Multi-Statement-Transaktionen; Locking und Claim wurden nicht als Postgres-RPC implementiert.
- **Betroffener Flow:** Dispatch (Schritt 2–4). Verschärft durch: Cron feuert jede Minute auch wenn der vorherige Tick noch läuft, und Blue-Green-Deploys, bei denen kurzzeitig zwei Backoffice-Container leben.
- **Risiko:** Dieselbe Order landet in zwei Batches → zwei Fahrer fahren los, Küche kocht doppelt, direkte Kosten und Kundenverwirrung. Crash zwischen den Writes hinterlässt inkonsistente Records (batch_id ohne driver_id), die von keiner Rescue-Logik bereinigt werden.

### P0-2: Offline-Outbox der Fahrer-App ohne Idempotenz
- **Problem:** `flushOutbox` sendet Aktionen erneut, wenn die Response nicht sauber verarbeitet wurde — ohne Idempotency-Key und ohne serverseitige Deduplizierung.
- **Ursache:** Einfache localStorage-Queue ohne Request-IDs; Retry-Logik unterscheidet nicht zwischen "nicht gesendet" und "gesendet, aber Antwort verloren".
- **Betroffener Flow:** Zustellbestätigung, Pick-Bestätigungen, Statuswechsel (Schritt 9).
- **Risiko:** Doppelte "Geliefert"-Events verfälschen Statuskette, Abrechnungen und Shift-Statistiken; kombiniert mit P0-1 potenziell widersprüchliche Order-Zustände.

### P0-3: mise-os Lieferzentrale — harter Datenverlust über die UI
- **Problem:** (a) Kategorien-Delete löscht via Prisma-Cascade alle zugehörigen Artikel sofort, ohne Bestätigungsdialog. (b) `GET /lieferzentrale` filtert `where: { active: true }` — deaktivierte Artikel sind nach Reload unsichtbar und über die UI nicht mehr reaktivierbar.
- **Ursache:** Fehlender Confirm-Guard im Frontend + fehlender Soft-Delete; Backend-Query filtert für das Backoffice fälschlich wie für den Shop.
- **Betroffener Flow:** Speisekarten-Pflege durch Restaurant-Personal.
- **Risiko:** Ein Fehlklick vernichtet eine komplette Kategorie mit z.B. 20 Artikeln unwiederbringlich; "Artikel aus"-Toggle wirkt wie Löschen. Datenverlust durch normale Bedienung.

### P0-4: Deploy-Pipeline: Phantom-Deploys + Container ohne Healthcheck
- **Problem:** (a) `auto-deploy.sh` läuft alle 30 min, aber `git pull` ist deaktiviert — es wird immer der lokale Serverstand neu gebaut; Repo-Änderungen erreichen die Produktion nie automatisch. (b) `mise_backoffice_3300` hat keinen Docker-Healthcheck und nginx keinen aktiven Upstream-Check.
- **Ursache:** Bewusst deaktivierter Pull ohne dokumentierten Ersatzprozess; Healthcheck nur einmalig beim Blue-Green-Schwenk (90s-Fenster).
- **Betroffener Flow:** Gesamtes System — jede Codeänderung und jeder Laufzeitausfall.
- **Risiko:** Fixes (inkl. aller hier gelisteten Bugs) werden gebaut, aber nie deployed — oder es wird versehentlich ein manuell veränderter Serverstand zementiert. Ein abgestürzter Next.js-Prozess bleibt bis zu einem manuellen Eingriff unbemerkt → Dispatch steht komplett.

### P0-5: iOS-Build-Kette bricht: `altool` deprecated + `voip` fehlt im Repo
- **Problem:** (a) TestFlight-Upload nutzt `xcrun altool`, das auf `macos-26`/aktuellem Xcode entfernt ist → CI-Upload schlägt voraussichtlich fehl. (b) Repo-`Info.plist` enthält kein `voip`-Background-Mode und kein `NSPhotoLibraryUsageDescription` — nur der CI-Workflow patcht beides nachträglich.
- **Ursache:** Veralteter Upload-Befehl; "zwei Wahrheiten"-Muster (Repo-Stand ≠ CI-Build-Stand).
- **Betroffener Flow:** Auslieferung der Fahrer-App; lokale Builds sind ohne VoIP funktionsunfähig bzw. Store-rejection-gefährdet (ITMS-90683).
- **Risiko:** Keine neuen App-Versionen mehr auslieferbar; lokal gebaute Test-Versionen erhalten keine VoIP-Pushes → Fahrer verpassen Touren.

## P1 – Major (Zuverlässigkeitsprobleme)

1. **`batch_id` wird bei CallKit-Accept nicht an den WebView übergeben** — Web-UI verlässt sich auf `visibilitychange` + eigenen Claim; Race Condition bei mehreren VoIP-Pushes in kurzer Folge. Fix: `evaluateJavaScript` oder Deep-Link mit `currentBatchId`.
2. **VoIP-Token-Kette fragil** — Web-seitiges Polling bricht nach 18s ab (kein Retry beim nächsten Start); nativer Token-Upload hat keinen Completion-/Fehler-Handler (stiller Verlust); kein Token-Verify beim App-Start. Folge: Fahrer erhält dauerhaft keine CallKit-Anrufe, ohne dass es jemand merkt.
3. **Doppelklingeln durch eingefrorenen Heartbeat** — iOS friert JS im Hintergrund ein → 15s-Heartbeat pausiert → Server hält Fahrer für inaktiv → VoIP-Push zusätzlich zum AlarmRinger.
4. **AlarmRinger ohne Max-Klingeldauer** — `setInterval(beep, 700)` läuft bei hängender Realtime-Verbindung endlos weiter, auch nach faktischer Annahme.
5. **In-Memory-Throttles nicht prozessübergreifend** — `tenantNoDriverThrottle`/`tenantAlertThrottle` sind Worker-lokal; bei mehreren Prozessen (Blue-Green-Überlappung, Cluster) doppelte Betreiber-Alerts trotz Throttle.
6. **Merge-Pfad ignoriert Fahrzeug-Slots** — `canBundle()` ist toter Code; `findActiveBatchForMerge` prüft nur `capBase`, nicht `VEHICLE_SLOTS` (bike=2, car=4) und `slotBonus` → Bike-Fahrer kann überladen werden.
7. **Multi-Pickup-Batches werden nie re-optimiert** — Merge erlaubt zweiten Pickup, aber TSP läuft nur bei genau einem Pickup; Route bleibt danach dauerhaft unoptimiert; ohne Schutz könnte ein Dropoff vor seinem Pickup einsortiert werden.
8. **Sibling-Hold-Deadlock** — `hold_for_order_id` auf eine bereits zugestellte/stornierte Order hält die wartende Order bis zum Ablauf von `dispatch_after` fest → vermeidbare Lieferverzögerung.
9. **Lieferzentrale-Config kann sich still selbst überschreiben** — `fetchLieferConfig()` ohne Loading-/Error-State: Bei kurzem Serverausfall fällt das Formular auf Defaults zurück und der nächste Save überschreibt die echte Konfiguration; Optionsgruppen als Rohtext-JSON sind für Personal nicht bedienbar (Tippfehler blockiert Speichern).
10. **Sicherheit auf dem Server** — Cron-Secret (`6e8c…`) im Klartext in ~20 crontab-Einträgen; `/opt/mise/.env`/`.env.local` mit `-rw-r--r--` weltlesbar; nginx Port 87 → :3212 routet ins Leere (stille Fehlschläge).

## P2 – Minor (Verbesserungen)

1. **Frank-Query-Verschwendung pro Tick** — `driverActiveDropoffs` doppelt pro Fahrer/Order, `checkSiblingHold` lädt Location jedes Mal neu, `tenantStrategy` 1 Query pro Order → langsame Ticks verlängern das Lock-Risiko-Fenster. Caches pro Tick einführen.
2. **GPS-Rate-Limit nur clientseitig (Ref)** — nach Reload feuern GPS-Pushes ungebremst; serverseitiges Limit fehlt.
3. **GPS-Queue und Outbox haben getrennte Flush-Trigger** — `flushGpsQueue` läuft nur bei `startBgLocation`, nicht beim `online`-Event → Positionen können dauerhaft liegen bleiben.
4. **Outbox-FIFO-Overflow** — bei >50 Einträgen werden die ältesten (oft kritischsten) Aktionen verworfen; kein Backoff, kein Alters-Verwerfen.
5. **iOS drosselt 30s-Keepalive auf ≥60s** — dokumentierte vs. reale GPS-Frequenz divergiert; Kunden-ETAs ungenau.
6. **Restaurant-Fallback über zwei Schemata** — `delivery_batches`→`locations` (lat/lng) vs. `mise_delivery_batches`→`mise_locations` (latitude/longitude); wenn beide leer sind, fehlt die Rück-Navigation.
7. **PickDialog-State-Overwrite** — Realtime-Update setzt lokal bestätigte Items optisch zurück; braucht Merge- statt Replace-Logik.
8. **`mise_frank_decisions` wächst unbegrenzt** — kein TTL/Archiv; Lock-Check macht unindexierten `created_at`-Scan, wird mit der Zeit langsamer.
9. **Inkonsistente ETA-Modelle + Vehicle-Type-Drift** — Haversine-Fallback (40 km/h) vs. `pickBest` (35 km/h); `scooter` existiert zur Laufzeit, aber nicht im TS-Typ und nicht in `VEHICLE_SLOTS`.
10. **CI-Fragilität iOS** — Repo-AppDelegate ≠ CI-AppDelegate (zwei Wahrheiten), `perl`-Rewrite des pbxproj kann Pods-Targets treffen, Provisioning-Profil-UUID hardcoded, kein npm/Pods-Cache.
11. **Storefront-Deploy ohne Blue-Green** — `docker compose up -d` mit kurzem Ausfall, kein Rollback.
12. **nginx-`.bak`/`.broken`-Dateien in `sites-enabled/`** — potenzielle Config-Konflikte, da nginx alle Dateien lädt.
13. **Lieferzentrale: kein Artikel-/Kategorien-Edit in der UI** — `updateArtikel`/`updateKategorie` existieren in der API, werden aber nicht angebunden; Workaround ist Löschen+Neuanlegen (gefährlich, siehe P0-3).
14. **Lieferzentrale: Bestell-Sicht unvollständig** — Detail-Panel synct nicht mit 30s-Refresh, `doneOrders.slice(0, 10)` ohne Paging, PLZ-Liefergebiet ohne Format-Validierung.
15. **Zombie-Zustände im Dispatch-Umfeld** — Fahrer "adib" seit 21.07. `stale` (produziert Logs/CPU); `rescueStaleTours` setzt `hold_reason`/`dispatch_after` freigegebener Orders nicht zurück; `dispatch_after` bleibt bei manueller Zuweisung gesetzt.

## P3 – Nice-to-have

1. **Frank-Health-Endpunkt** (`/api/frank/health`: letzter Tick, Dispatch-Rate, Queue-Tiefe) — aktuell nur über DB-Abfragen monitorbar.
2. **Geocoding-Fehlzähler + Eskalation** — Order mit dauerhaft kaputter Adresse blockiert heute still.
3. **`canBundle()` löschen oder reaktivieren** — toter Code verwirrt Wartung (Fix gehört zu P1-6).
4. **AudioContext-Leak in der Fahrer-App** — pro Tour-Event neuer Context ohne close(); Chrome-Limit 6 → verstummte Töne.
5. **`exhaustive-deps`-Disables aufräumen** (≥8x) — Quelle unerwarteter Re-Subscriptions.
6. **Broadcast-Latenz** — Betriebsnachrichten erst nach nächstem 60s-Poll sichtbar; Unreachable-Timer (120s) überlebt keinen Reload.
7. **Server-Hygiene** — Dutzende `diag-*/fix-*`-Skripte und `.bak`-Deploy-Skripte ohne Archivkonzept; `MIGRATION_ALL.sql` (377 KB) im Repo-Root statt `supabase/migrations/`; Legacy-SPA auf Port 8090.
8. **iOS: `armv7` in `UIRequiredDeviceCapabilities`** → auf `arm64` ändern; Debug-Beacons fire-and-forget ohne Retry; README-Hinweis, dass `web/` bewusst leer ist.
9. **`web-push` beim Modulstart importieren** statt Lazy-Import im Hot-Path; `oldestOrderMin`-Benennung korrigieren.
10. **Lieferzentrale-UX** — Bestellton/Notification API, Drag-and-Drop-Sortierung (`order`-Feld ungenutzt), Badge zählt nur `neu`, `extraDip` wird nie angezeigt, Tab-Wechsel verwirft ungespeicherte Einstellungen, Refresh-Intervall fix 30s.

---

# 4. Offene Fragen / Unbekannte

1. **Verhältnis mise-os Lieferzentrale ↔ Supabase-Stack:** Die Lieferzentrale (Fastify/Prisma, eigene Order-Tabellen) und Franks `customer_orders` sehen wie zwei parallele Bestellsysteme aus. Fließen Lieferzentrale-Orders in den Frank-Dispatch? Über welchen Pfad? Kein Webhook/Push gefunden.
2. **Welches Deploy-Skript ist kanonisch?** `auto-deploy.sh` (Cron, 22.07.) vs. `auto-deploy-new.sh` (20.07., ungenutzt). Und: Warum ist `git pull` deaktiviert — was ist der beabsichtigte Deploy-Trigger?
3. **Port 87 → 127.0.0.1:3212:** Welcher Dienst sollte dort laufen? Kein Container, kein PM2-Prozess belegt den Port.
4. **`/opt/mise/app/` neben `backoffice/`:** Zweck unklar — Altlast oder aktiver Code?
5. **`driver-native/`, `mobile/`, `pos-mobile/`, `pos-native/`:** Verhältnis zur Capacitor-App `mise-driver-app` (Doppelentwicklung?).
6. **Prozessmodell des Backoffice-Containers:** Läuft Next.js als ein Prozess oder mehrere Worker? Davon hängt die reale Schwere der In-Memory-Throttle-Probleme (P1-5) ab. Sicher ist: Während des Blue-Green-Schwenks existieren kurzzeitig zwei Container.
7. **Supabase-RPC-Fähigkeit:** Existieren bereits Postgres-Funktionen/RPCs (z.B. `confirm_pick_item`), auf denen ein atomarer `claim_order`-RPC aufgebaut werden kann? (Vermutlich ja — `confirm_pick_item` ist ein RPC.)
8. **Serverseitige Idempotenz:** Prüft das Backend bereits doppelte Zustell-/Statuscalls (relevant für P0-2), oder ist es vollständig clientvertrauend?
9. **`tenants.dispatch_strategy` in Produktion:** Welche Strategie ist real gesetzt (Fallback `balance` laut Code)? Gibt es überhaupt mehrere aktive Tenants?
10. **Fahrer "adib":** Testartefakt oder echter, falsch abgemeldeter Fahrer? Aufräumprozess für dauerhaft stale Fahrer fehlt.

---

# 5. Empfehlung: Erster Bug-Fix

## → P0-1: Atomarer Dispatch (Lock + Order-Claim als Postgres-RPC)

**Warum zuerst:**

1. **Höchster realer Schaden pro Vorfall:** Eine doppelt zugewiesene Order bedeutet doppelte Küchenproduktion, zwei ausgesandte Fahrer, verwirrte Kunden und falsche Abrechnung — der teuerste Einzelfehler im gesamten System, und er trifft den Kern-Geschäftsprozess.
2. **Die Eintrittswahrscheinlichkeit ist strukturell gegeben, nicht theoretisch:** Der Cron feuert jede Minute, auch wenn der vorherige Tick noch läuft (Logs zeigen bereits "Tick bereits aktiv, überspringe" — der Lock wird also real beansprucht und ist genau dann TOCTOU-gefährdet). Zusätzlich laufen bei jedem Blue-Green-Deploy bis zu 90 Sekunden zwei Backoffice-Container. Die Race-Fenster existieren im Normalbetrieb.
3. **Fundament für alles Weitere:** Rescue-Logik, Sibling-Hold-Fixes, Slot-Checks und Outbox-Idempotenz (P0-2) bauen alle auf der Annahme auf, dass eine Order genau einem Batch gehört. Solange das nicht garantiert ist, kaschieren andere Fixes nur Symptome.
4. **Klar umrissener, testbarer Fix:** Eine Postgres-RPC-Funktion in Supabase, die (a) `pg_try_advisory_lock` für den Tick nutzt und (b) Batch-INSERT + Stop-INSERTs + `customer_orders`-UPDATE in einer Transaktion mit Bedingung `WHERE mise_batch_id IS NULL` ausführt (Conditional Claim). Rückgabewert signalisiert Frank, ob der Claim gelang. Der bestehende `mise_frank_decisions`-Pseudo-Lock bleibt als Audit-Log erhalten, verliert aber seine Lock-Funktion. Testbar durch parallele Tick-Simulation gegen eine Staging-DB.

**Wichtige Randbedingung:** Direkt danach (oder parallel, da unabhängig) muss **P0-4a (auto-deploy ohne git pull)** geklärt werden — sonst wird der Dispatch-Fix zwar gebaut, erreicht die Produktion aber nie. P0-4 ist bewusst nicht der erste Fix, weil zuerst die offene Frage 2 (beabsichtigter Deploy-Prozess) beantwortet werden muss, bevor man den Cron-Deploy scharf schaltet.

**Reihenfolge-Empfehlung gesamt:** P0-1 → P0-4 (nach Klärung) → P0-3 (kleiner Fix, großer Schutz: Confirm-Dialog + `active`-Filter entfernen) → P0-2 (Idempotency-Keys Client+Server) → P0-5 (CI-Upload modernisieren, Repo-Plist angleichen).
