# 06 – Teststrategie

## Ziel

Die Teststrategie muss nicht nur Funktionen, sondern verteilte Zustände, Zeit, Offline-Verhalten, Duplikate und Ausfälle prüfen. Die zentrale Frage lautet nicht „funktioniert der Happy Path?“, sondern „bleibt der Geschäftsvorgang unter realen Störungen korrekt und rettbar?“.

## Ebenen

### 1. Unit Tests

- Score-Komponenten und Constraints
- Latest Safe Departure/Hold Deadline
- State-Transition-Guards
- Idempotency-Key-Handling
- GPS-Stale-Klassifikation
- Retry-/Backoff-Berechnung
- ETA-/Zeitfensterlogik
- Datenschutz-/Redaction-Helfer

Unit Tests sind deterministisch; Zeit und Zufall werden injiziert.

### 2. Contract Tests

Für jedes externe/Client-Verhältnis:

- Kunden-Web <-> Order API
- Driver App <-> Realtime/Assignment API
- Dispatcher UI <-> Ops API
- Payment Webhooks
- Map/Route Provider
- FCM/APNs Adapter
- VoIP Provider
- Event Producer/Consumer

Versionierte Schemas und rückwärtskompatible Änderungen prüfen.

### 3. Integration Tests

- DB-Transaktion + Outbox
- Event-Duplikate/Reordering
- optimistic concurrency
- Assignment-Lease-Ablauf
- Push-Ledger + ACK
- Offline-GPS-Backfill
- Route-Version-Konflikt
- Payment-/Order-Konsistenz
- Feature-Flag-Varianten

### 4. Dispatch Replay und Simulation

Gleiche Eingabe, gleicher Seed, reproduzierbares Resultat. Der Harness nimmt historische, anonymisierte Event-Streams oder synthetische Szenarien und vergleicht:

- aktuelle Baseline,
- Kandidatenalgorithmus,
- Fallback.

Pflichtmetriken stehen in `docs/04-DISPATCH-ENGINE-SPEC.md`.

### 5. End-to-End

Mindestens:

```text
Kunde bestellt
-> Order durable
-> Store/Prep
-> Dispatch
-> Offer/ACK
-> Pickup
-> Live Tracking
-> Delivery
-> Abschluss/Audit
```

Varianten:

- Fernorder mit Bundle
- Fernorder ohne Bundle
- Decline/Timeout/Neuvergabe
- Offline-Fahrer
- verspätete Prep-Zeit
- Kunde storniert
- Payment Callback doppelt
- Map-/Push-/Realtime-Ausfall
- manueller Override

### 6. Mobile Device Matrix

Nicht nur Emulatoren. Reale Geräteklassen:

- aktuelles und älteres Android,
- mindestens ein Hersteller mit aggressivem Battery Management,
- aktuelle und unterstützte ältere iOS-Version,
- schwache Verbindung,
- Low Battery/Battery Saver,
- Hintergrund, Lock Screen, Prozessrestart,
- Berechtigung entzogen/ungefährer Standort,
- alte und neue App-Version während Backend-Rollout.

### 7. Performance und Last

- Order-Burst
- GPS-Ingestion pro Sekunde
- WebSocket-Fanout
- Dispatch-Rechenzeit bei Peak
- Notification-Queue
- Outbox-Backlog und Recovery
- DB-Locks/Hot Rows
- Replay nach Ausfall

Lasttests prüfen auch Korrektheit, nicht nur Durchsatz.

### 8. Failure Injection

Gezielt:

- Timeout
- HTTP 429/5xx
- verzögerte/duplizierte Events
- DB-Deadlock
- Redis leer
- Routing Provider down
- Push Provider angenommen, aber keine App-Receipt
- Clock Skew
- GPS stale/spoof-like jump
- App reconnect mit altem Route-State
- Consumer-Neustart mitten in Verarbeitung

## Bug-Fix-Schleife

```text
1. Symptom und Auswirkung erfassen
2. Reproduktion minimieren
3. Test muss rot sein
4. Root Cause belegen
5. kleinsten sicheren Fix implementieren
6. Regressionstest grün
7. angrenzende Invarianten prüfen
8. unabhängiges Review
9. Feature Flag/Canary
10. Incident Learning
```

Kein „probieren, bis es geht“ ohne Hypothese und Messung.

## Testdaten

- synthetisch oder sauber anonymisiert,
- keine vollständigen Kundenadressen in Git,
- reproduzierbare Seeds,
- explizite Zeitzonen,
- realistische Prep-/Traffic-/Netzvariabilität,
- dokumentierte Quelle und zulässige Nutzung.

## Flaky Tests

Ein flaky kritischer Test ist ein Defekt. Nicht einfach mehrfach laufen lassen und ignorieren.

Vorgehen:

1. Seed, Zeit und Abhängigkeiten kontrollieren.
2. Race/Timeout sichtbar machen.
3. Quarantäne nur mit Owner, Ticket und Ablaufdatum.
4. Release Gate blockiert bei flaky kritischen Pfaden.

## Traceability

`docs/CURRENT-SYSTEM-INVENTORY.md` führt für jeden kritischen Flow:

```text
Flow-ID
Anforderung
Codepfad
Unit/Contract/Integration/E2E
Monitoring
Runbook
Owner
Status
```

## Mindestnachweis pro PR

- zugehörige Task-/Flow-ID,
- neuer oder geänderter Test,
- ausgeführte Befehle,
- Resultate,
- Risiko und Rollback,
- Telemetrieänderung,
- Screenshot/Video nur ergänzend, nie als einziger Nachweis.
