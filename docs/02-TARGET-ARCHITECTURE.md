# 02 – Zielarchitektur

## Ziel

Die Plattform soll Bestellungen genau einmal als Geschäftsvorgang behandeln, Fahrerzustände und GPS nachvollziehbar führen, Entscheidungen auditierbar treffen und bei Ausfällen kontrolliert degradieren. Die bestehende Architektur wird schrittweise in diese Richtung gebracht; ein Big-Bang-Rewrite ist ausdrücklich nicht vorgesehen.

## Logische Komponenten

```text
[Kunden-Web/App]
       |
       v
[Order API / Checkout] ---- [Payment Provider]
       |
       v
[Order Orchestrator + State Machine]
       |             \
       |              \ transactional outbox
       v               v
[Primary DB]       [Event Bus / Queue]
                         |
          +--------------+-------------------+
          |              |                   |
          v              v                   v
 [Prep/Store]     [Dispatch Engine]   [Notification Service]
                        |                       |
                        v                       v
               [Route/ETA Service]      [FCM/APNs/VoIP]
                        |
                        v
               [Assignment Service]
                        |
          +-------------+--------------+
          |                            |
          v                            v
 [Driver Realtime API]          [Ops/Dispatcher Console]
          |
          v
 [Driver App + GPS]
          |
          v
 [Tracking Ingestion -> Current Position Store -> History/Audit]
          |
          +------------------> [Customer Tracking Gateway]

Alle kritischen Pfade:
[Metrics + Logs + Traces + Audit Events + Alerts]
```

## Datenverantwortung

| Domäne | Kanonische Quelle |
|---|---|
| Bestellung und Zahlung | Order/Payment-Datenbank |
| Fahreridentität und Berechtigungen | Identity/Driver-Service |
| Verfügbarkeit | Driver Presence/Availability |
| aktive Route und Zuweisung | Assignment/Dispatch-Domäne |
| aktuelle GPS-Position | Tracking Current Position Store |
| historische Zustandsänderungen | append-only Audit/Event Store |
| Benachrichtigungsstatus | Notification Delivery Ledger |
| ETA | versionierte ETA-Berechnung mit Input-Snapshot |

Redis oder ähnliche In-Memory-Systeme dürfen beschleunigen, aber nicht die einzige Quelle für geschäftskritische Zustände sein.

## Kernmuster

### 1. Transactional Outbox/Inbox

Order-Transition und zugehöriges Ereignis werden atomar gespeichert. Verbraucher verarbeiten Ereignisse idempotent anhand einer `event_id`. Das verhindert verlorene Events und macht Duplikate beherrschbar.

### 2. Optimistic Concurrency

Order, Driver Route und Assignment besitzen monotone Versionsnummern. Änderungen mit veralteter Version werden abgelehnt und neu berechnet.

### 3. Assignment Lease

Eine Zuweisung ist kein unbefristeter Boolean. Sie enthält mindestens:

```text
assignment_id
order_ids
driver_id
decision_id
route_version
status
offered_at
expires_at
acknowledged_at
lease_version
algorithm_version
reason_codes
```

Bei Ablauf wird sie atomar ungültig und die Bestellung neu disponiert.

### 4. Event Time und Processing Time

Jedes relevante Event führt:

- `occurred_at` vom Erzeuger,
- `received_at` vom Server,
- monotone Sequenz pro Gerät/Stream,
- Zeitzone/UTC-normalisierte Speicherung.

Damit lassen sich verspätete Offline-Events von echten aktuellen Zuständen unterscheiden.

### 5. Feature Flags

Mindestens getrennte Flags für:

- neue Dispatch-Engine,
- Remote-Order-Holding,
- Multi-Stop-Batching,
- neue Push-Eskalation,
- neue GPS-Pipeline,
- Kunden-Livekarte,
- automatische Neuvergabe.

Flags müssen zonen-, fahrergruppen- oder prozentbasiert schaltbar sein.

## Kritische Fallbacks

| Ausfall | Automatischer Fallback | Sichtbarer Ops-Schritt |
|---|---|---|
| Optimizer Timeout | deterministische Best-Insertion-Heuristik | Badge „Fallback Dispatch“ |
| Routing Provider | Cache, grobe Distanz/ETA + Sicherheitsaufschlag | manuelle Route prüfen |
| GPS stale | Fahrer nicht für enge ETA-Zusagen verwenden | Fahrer kontaktieren |
| Push ohne App-ACK | Retry, zweiter Kanal, Lease-Ablauf | Neuvergabe/VoIP |
| Event Bus gestört | Outbox bleibt pending, Poller/Replay | Alarm + Backlog |
| Realtime Gateway | Polling-Fallback | Status „verzögert“ |
| Payment Callback doppelt | idempotente Inbox | Audit-Eintrag |
| App offline | lokale Queue + serverseitiger Stale-Status | kein stilles „online“ |
| Datenbank-Failover | Retry mit Idempotency-Key | Schreibschutz/Degraded Mode |

## Manueller Override

Die Dispatcher-Konsole muss mindestens können:

- Bestellung einem Fahrer zuweisen oder entziehen,
- Holding beenden,
- Optimizer für Zone/Order pausieren,
- stale/ungeklärte Fahrer aus dem Kandidatenpool nehmen,
- Gründe erfassen,
- Kunden-ETA korrigieren,
- VoIP-Anruf auslösen,
- Auftrag in sichere manuelle Bearbeitung setzen.

Jeder Override wird mit Nutzer, Zeitpunkt, Grund, vorherigem und neuem Zustand auditiert.

## Kein „unsichtbarer Erfolg“

Ein API-`200` allein ist kein Geschäftserfolg. Kritische Aktionen benötigen einen serverseitigen, abfragbaren Status:

- Order durable
- Assignment offered
- Push sent
- App received
- Driver acknowledged
- Pickup confirmed
- Delivery confirmed

## Datenbank-Minimum

Empfohlene logische Tabellen/Collections:

- `orders`
- `order_events`
- `drivers`
- `driver_shifts`
- `driver_presence`
- `driver_locations_current`
- `driver_location_history`
- `routes`
- `route_stops`
- `assignments`
- `dispatch_decisions`
- `notification_attempts`
- `idempotency_keys`
- `outbox_events`
- `inbox_events`
- `feature_flag_evaluations`
- `audit_log`

Die konkrete Speicherung richtet sich nach dem bestehenden Stack.
