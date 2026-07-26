# 07 – Observability, SLI und anfängliche SLOs

## Prinzip

Logs ohne Korrelation und Dashboards ohne Handlungsregel sind keine Betriebsfähigkeit. Jeder kritische Geschäftsvorgang erhält:

- eine durchgehende Correlation/Trace ID,
- strukturierte Events,
- technische und geschäftliche Metriken,
- definierte Alert-Schwellen,
- ein Runbook,
- einen Owner.

## Identifikatoren

Durch alle Services propagieren:

```text
trace_id
order_id
assignment_id
decision_id
driver_id (intern/pseudonymisiert in Logs)
route_version
event_id
causation_id
idempotency_key
algorithm_version
feature_flag_variant
app_version
```

Keine vollständigen Adressen, Telefonnummern oder Namen in Standardlogs.

## Anfängliche technische Ziele

Diese Werte sind Start-Guardrails und werden nach einer belastbaren Baseline angepasst; sie sind keine vertragliche Zusage.

| SLI | Startziel |
|---|---:|
| Order API erfolgreiche dauerhafte Annahme | >= 99,95 % |
| Order angenommen -> durable Event, p95 | < 1 s |
| Dispatch-Berechnung, p95 | < 2 s |
| Dispatch-Berechnung, p99 | < 5 s |
| Order unzugewiesen ohne bewussten Hold, p95 | < 30 s |
| aktive GPS-Freshness, p95 | < 15 s |
| Stale-Erkennung nach Schwelle | < 5 s zusätzlich |
| Push -> App-Receipt, p95 bei gesunder Verbindung | < 5 s |
| Assignment ACK/Decline innerhalb TTL | messbar >= 99 % der Offers |
| Customer Tracking API Verfügbarkeit | >= 99,9 % |
| doppelte aktive Assignment pro Order | 0 |
| verlorene durable Order Events | 0 |
| Crash-free Driver-App Sessions | baseline + festgelegtes Releaseziel |

Business-Ziele:

- On-time Delivery
- p50/p90 tatsächliche Verspätung
- Kilometer/Order
- Kosten/Order
- Pickup-Wartezeit
- Order-Storno
- Fahrerannahmerate
- Assignment-Churn
- Dispatch-Fallbackrate
- Remote-Hold-Dauer
- ETA-Fehler p50/p90

## Dashboards

### Control Tower

- offene Orders nach Zustand und Alter,
- unzugewiesene/held Orders und Deadline,
- aktive/stale/offline Fahrer,
- Offers nach Status,
- P95 Dispatch-Latenz,
- Provider-Status,
- manuelle Overrides.

### Dispatch Quality

- Baseline vs aktuelle Algorithmusversion,
- On-time/Distance/Cost,
- Score-Komponenten,
- Shadow-Diskrepanzen,
- Fallback/Timeout,
- Churn,
- Fernorder-Holding und Bundle-Erfolg.

### Mobile/Tracking

- App-Versionen,
- Crash/ANR,
- Background Location Success,
- GPS-Freshness/Accuracy,
- Offline Queue/Backfill,
- Push Receipt/ACK,
- Token Invalid Rate,
- Battery-/Connectivity-Segmente.

### Data Integrity

- Order ohne Event/Outbox,
- aktive Duplicate Assignments,
- verwaiste Route Stops,
- Versionskonflikte,
- Inbox-Duplikate,
- negative/unerlaubte State-Transitions,
- Payment-/Order-Abweichungen.

## Alerts

Ein Alert enthält:

- Symptom und Schweregrad,
- betroffene Zone/Version/Provider,
- erste sichere Handlung,
- Link/Referenz zum Runbook,
- Rollback-/Feature-Flag-Pfad,
- Correlation IDs/Beispielorders ohne PII.

Beispiele:

- P0: Duplicate active assignment > 0
- P0: confirmed orders fehlen in kanonischer DB/Audit
- P1: unassigned age p95 über Schwelle
- P1: GPS stale rate über Schwelle
- P1: Push Receipt Rate bricht ein
- P1: Dispatch Fallback/Timeout stark erhöht
- P1: Payment-/Order-Konsistenzabweichung
- P2: ETA-Fehler oder Kilometer/Order verschlechtert
- P2: neue App-Version erhöhte Crashrate

## Synthetic Journeys

Regelmäßig in Test-/Staging-Umgebung:

1. Bestellung anlegen,
2. vorbereiten,
3. Testfahrer verfügbar,
4. Offer empfangen/quittieren,
5. simulierte GPS-Punkte,
6. Pickup/Delivery,
7. Kundenstatus prüfen,
8. Audit/Telemetry prüfen.

Keine künstliche Produktivbestellung ohne klaren separaten Mechanismus.

## Runbooks

Mindestens:

- Dispatch Engine down/timeout
- Routing Provider down
- Push Provider/Token-Probleme
- GPS stale/Tracking-Ingestion down
- Event Bus/Outbox Backlog
- Payment Callback-Probleme
- Datenbank-Failover
- fehlerhafte App-Version
- falsche/doppelte Assignment
- Datenschutz-/Zugriffsincident
