# Current System Inventory

> Diese Datei nach `CURRENT-SYSTEM-INVENTORY.md` kopieren und durch Repository-Analyse befüllen. Annahmen deutlich markieren.

## 1. Repository/Stack

- Monorepo oder mehrere Repositories:
- Backend-Sprache/Framework:
- Driver App:
- Customer Web/App:
- Dispatcher Console:
- Datenbanken:
- Queue/Event Bus:
- Realtime:
- Maps/Route/ETA:
- Push:
- VoIP:
- Payment:
- Hosting/CI/CD:
- Feature Flags:
- Monitoring:

## 2. Lokale Befehle

```text
Install:
Build:
Lint:
Typecheck:
Unit:
Integration:
E2E:
Mobile Android:
Mobile iOS:
Dispatch Replay:
Load:
Security:
```

## 3. Umgebungen

| Umgebung | Zweck | Datenart | Deploy | Owner |
|---|---|---|---|---|
| local | | | | |
| test | | | | |
| staging | | | | |
| production | | | | |

## 4. Kritische Nutzerflüsse

| Flow-ID | Beschreibung | Entry | Services/Module | Test | Telemetrie | Status |
|---|---|---|---|---|---|---|
| F-001 | Kunde bestellt | | | | | |
| F-002 | Order durable | | | | | |
| F-003 | Fahrer verfügbar | | | | | |
| F-004 | Dispatch/Offer | | | | | |
| F-005 | ACK/Neuvergabe | | | | | |
| F-006 | Pickup/Delivery | | | | | |
| F-007 | GPS/Customer Tracking | | | | | |
| F-008 | manueller Override | | | | | |

## 5. Ist-Zustandsmaschinen

### Order

```text
TODO
```

### Driver

```text
TODO
```

### Assignment

```text
TODO
```

## 6. Datenmodelle und Invarianten

- Order primary key/version:
- Assignment uniqueness:
- Idempotency:
- Outbox/Inbox:
- Route version:
- GPS current/history:
- Audit:

## 7. Integrationen und Fehlerverhalten

| Integration | Timeout | Retry | Idempotenz | Fallback | Monitoring |
|---|---:|---|---|---|---|
| Payment | | | | | |
| Maps/ETA | | | | | |
| FCM/APNs | | | | | |
| VoIP | | | | | |

## 8. Bekannte Fehler P0–P3

| ID | Severity | Symptom | Reproduktion | Auswirkung | Owner | Status |
|---|---|---|---|---|---|---|

## 9. Baseline-Metriken

| Metrik | Wert | Zeitraum | Quelle | Unsicherheit |
|---|---:|---|---|---|
| on-time | | | | |
| km/order | | | | |
| dispatch p95 | | | | |
| unassigned age p95 | | | | |
| GPS freshness p95 | | | | |
| push receipt p95 | | | | |
| crash-free | | | | |

## 10. Datenschutz/Sicherheit

- Rollen:
- GPS-Zweck/Zeitraum:
- Retention:
- Logging/Redaction:
- Secrets:
- Tracking-Link:
- offene Prüfungen:

## 11. Release/Rollback

- aktueller Releaseprozess:
- Feature Flags:
- Canary:
- DB Rollback:
- App-Kompatibilität:
- Runbooks:
