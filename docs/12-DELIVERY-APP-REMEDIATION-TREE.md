# Delivery App Remediation Tree

Stand: 2026-07-24

## Ziel

Eine produktionsfähige Liefer-App, in der jede Bestellung genau einmal zugewiesen,
zuverlässig signalisiert, nachvollziehbar gefahren und genau einmal abgeschlossen
wird. Der intelligente Dispatch optimiert erst, nachdem diese Invarianten
automatisiert abgesichert sind.

## Arbeitsbaum

```text
Funktionierende Lieferplattform
├── Gate 0: Belegbarer Build- und Systemstand
│   ├── G0.1 GitHub HEAD und TestFlight-Build-SHA sichtbar machen
│   ├── G0.2 reproduzierbaren Staging-Stack herstellen
│   ├── G0.3 Server-Erreichbarkeit, Backup und Rollback belegen
│   └── G0.4 Flow-/Release-Matrix mit PASS/FAIL/UNKNOWN führen
│
├── Gate 1: Korrektheitsfundament (P0)
│   ├── P0.1 atomarer Dispatch-Tick oder atomare Work-Lease
│   ├── P0.2 atomarer Order-Claim mit Batch und Stops in einer DB-Transaktion
│   ├── P0.3 eindeutige aktive Zuweisung und monotone Version
│   ├── P0.4 idempotente Accept/Pick/Deliver-Requests
│   ├── P0.5 Recovery mit State-, Batch- und Versions-Guards
│   └── P0.6 manuelle Rettung plus vollständiger Audit-Trail
│
├── Gate 2: Fahrer-App und Benachrichtigung (P0/P1)
│   ├── I2.1 APNs Alert + VoIP/CallKit mit Push-Ledger und App-ACK
│   ├── I2.2 batch_id/assignment_version sicher an WebView übergeben
│   ├── I2.3 Token-Registrierung, Retry und Invalidierung beobachten
│   ├── I2.4 Background-GPS auf realen Geräten testen
│   ├── I2.5 Offline-Outbox mit Idempotency-Key und sicherer FIFO-Politik
│   └── I2.6 alte und neue App-Version parallel kompatibel halten
│
├── Gate 3: Deterministischer Dispatch-Baseline (P1)
│   ├── A3.1 harte Constraints vor Score prüfen
│   ├── A3.2 Fahrzeugkapazität, Pickup-vor-Dropoff und Zeitfenster
│   ├── A3.3 ETA-/Quality-Deadline und latest_safe_departure_at
│   ├── A3.4 deterministischer Fallback ohne Kartenanbieter
│   ├── A3.5 Score-Komponenten, Reason Codes und Algorithmusversion auditieren
│   └── A3.6 Replay-Harness mit synthetischen Störfällen
│
├── Gate 4: Intelligenter Rolling-Horizon-Algorithmus (P1/P2)
│   ├── A4.1 Best-Insertion über zulässige Fahrer und Stoppositionen
│   ├── A4.2 Korridor-/Umwegprüfung statt reiner Luftlinie
│   ├── A4.3 dynamisches Warten nur bis zur sicheren Deadline
│   ├── A4.4 Churn-Penalty nach ACK und harte Stabilität nach Pickup
│   ├── A4.5 p90-Risiko, Fairness und Kosten getrennt ausweisen
│   └── A4.6 keine Live-Gewichtsänderung; nur Replay, Review und Freigabe
│
├── Gate 5: Observability und Betrieb
│   ├── O5.1 Dispatch-Latenz, Queue-Tiefe und Duplicate-Assignment-Alarm
│   ├── O5.2 Push accepted/received/acknowledged/expired Ledger
│   ├── O5.3 GPS-Freshness und Zombie-Fahrer
│   ├── O5.4 Recovery-Erfolg, Fehler und manuelle Eingriffe
│   └── O5.5 Runbooks, Feature Flags und One-Click-Fallback
│
└── Gate 6: Freigabe
    ├── R6.1 unabhängiges Code-Review
    ├── R6.2 Unit, Contract, Integration, Replay und Device-E2E
    ├── R6.3 Shadow Mode ohne Produktionsassignment
    ├── R6.4 Canary mit vorab definierten Stop-Kriterien
    └── R6.5 manuelle TestFlight- und Produktionsfreigabe
```

## Abhängigkeiten

- Gate 1 blockiert Gates 3 und 4. Ein intelligenter Score darf keine
  nicht-atomare Zuweisung kaschieren.
- Gate 2 kann parallel zu Gate 1 entwickelt werden, die Ende-zu-Ende-Freigabe
  benötigt aber beide.
- Gate 4 läuft zuerst im Replay und anschließend im Shadow Mode.
- Kein Gate gilt aufgrund eines Agentenberichts als bestanden. PASS benötigt
  reproduzierbare Evidenz im Repository oder CI-Artefakt.

## Aktueller belegter Zustand

| Knoten | Status | Evidenz |
|---|---|---|
| G0.1 GitHub HEAD | PASS | `origin/main` = `afc25f8` |
| G0.1 TestFlight auf HEAD | FAIL | letzter erfolgreicher Upload basiert auf `e5b042a` |
| I2.1 CallKit/Alarm im Repository | PASS | PushKit, CallKit und `alarm.caf` vorhanden |
| I2.1 Alarm in letztem erfolgreichen Build | PASS | CI-Schritt bundelte `alarm.caf`; Upload ohne Fehler |
| P0.1 echter Tick-Lock | FAIL | Decision-Log ist TOCTOU; vorbereiteter xact-lock-RPC schützt den Tick nicht |
| P0.2 atomarer Claim | FAIL | Order-Update und Stop-Inserts bilden keine gemeinsame Transaktion |
| P0.4 Offline-Idempotenz | UNKNOWN/FAIL | kein vollständiger Client+Server-Nachweis |
| G0.2 Staging | UNKNOWN | kein reproduzierbarer lokaler Backoffice-/DB-Stack belegt |
| G0.3 Produktionsserver | BLOCKED | `178.104.106.72:22` nicht erreichbar |

## Definition von „funktioniert“

Die App ist erst freigabefähig, wenn der Single-Order-Slice und seine
Failure-Varianten auf echten Geräten bestanden sind:

```text
Order durable
-> atomare Reservation
-> Push accepted
-> App receipt/ACK
-> Fahrer accept
-> Pickup
-> GPS aktuell oder sichtbar stale
-> idempotente Delivery
-> terminaler Audit-Trail
```

Pflichtvarianten: doppelter Tick, verlorene HTTP-Antwort, App gekillt,
Push ohne Receipt, GPS stale, Accept am Timeout-Rand, DB-Fehler zwischen
Schritten, Kartenanbieter down und manueller Override.
