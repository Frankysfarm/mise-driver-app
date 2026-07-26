---
name: dispatch-evaluation
description: "Vergleicht eine Dispatch-Änderung reproduzierbar mit der aktuellen Baseline über feste Szenarien, Replay/Simulation, Sicherheitsinvarianten und Shadow-Kriterien."
argument-hint: "<Branch, Algorithmusversion, Konfigurationsänderung oder Hypothese>"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Dispatch Evaluation

Bewerte `$ARGUMENTS` niemals nur anhand einzelner Beispielrouten. Die Änderung bleibt offline, bis die Gates erfüllt sind.

## Ablauf

1. `dispatch-optimizer` dokumentiert Hypothese, harte Constraints, Score-Komponenten, Laufzeitbudget und Fallback.
2. `dispatch-simulation-tester` führt die deterministischen Fälle aus `evals/scenarios.yaml` aus.
3. Vergleiche Kandidat und Baseline auf identischem Snapshot/Seed/Datenfenster.
4. Führe Stresstests für Burst, Matrix-/Provider-Latenz, stale GPS, Offer-Timeouts, Prep-Delay und Recompute-Sturm aus.
5. Prüfe mit `data-consistency-engineer`, dass Reservation, Lease, ACK, Reassignment und Route-Version atomar/idempotent bleiben.
6. Prüfe mit `performance-reliability-engineer` p50/p95/p99 Laufzeit, Timeoutquote und Fallback-Verhalten.
7. Prüfe mit `security-privacy-reviewer`, dass Replay-Daten minimiert, pseudonymisiert und zugriffsgeschützt sind.
8. Erzeuge eine Shadow-Readiness-Entscheidung; keine Live-Gewichtsänderung durch den Agenten.

## Harte Regressionen

Sofort `FAIL`, wenn mindestens eines eintritt:

- verschwundene oder doppelt zugewiesene Order,
- verletztes Zeitfenster/Quality-Limit trotz machbarer Alternative,
- ungültige Pickup-vor-Drop-off-Reihenfolge,
- veraltete Route-Version wird übernommen,
- Optimizer-Timeout ohne deterministischen Fallback,
- schlechtere kritische Tail-Latenz außerhalb des vereinbarten Budgets,
- nicht erklärbare Entscheidung ohne Score-/Reason-Audit.

## Bericht

```markdown
## Evaluation verdict
PASS_TO_SHADOW | NEEDS_TUNING | FAIL

## Candidate
Version, Konfiguration, Commit, Daten-/Seed-Fingerprint

## Safety invariants
Bestanden/fehlgeschlagen mit Szenario-ID

## KPI comparison
Baseline vs Kandidat, absolute und relative Änderung, Konfidenz/Unsicherheit

## Segment analysis
Nah/Fern, Peak/Off-Peak, Zone, Fahrzeugtyp, Einzelorder/Bündel, GPS-Qualität

## Runtime and fallback
p50/p95/p99, Timeout, Fallbackquote, Recompute-Churn

## Shadow plan
Scope, Dauer/Kriterien, Abbruchschwellen, Dashboard und Owner
```
