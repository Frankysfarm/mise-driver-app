---
name: bootstrap-audit
description: "Kartiert ein bestehendes Lieferplattform-Repository, belegt kritische Nutzerflüsse und erstellt vor jeder größeren Änderung eine risikobasierte Fertigstellungs-Baseline. Nutze diesen Workflow zu Projektbeginn oder nach größerem Architekturwechsel."
argument-hint: "[optionaler Scope, bekannte Blocker oder Repository-Hinweise]"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Bootstrap Audit

Führe einen **belegten Read-first-Audit** aus. Ändere in diesem Workflow keinen Produktivcode. `$ARGUMENTS` sind zusätzliche Hinweise, keine ungeprüften Wahrheiten.

## Pflichtschritte

1. Lies `CLAUDE.md`, vorhandene Architektur-/Runbook-Dateien und `docs/CURRENT-SYSTEM-INVENTORY.md`, falls vorhanden.
2. Delegiere die Repository-Kartierung an `repository-cartographer`.
3. Lasse `product-requirements-auditor` die kritischen Nutzerflüsse und fehlenden Akzeptanzkriterien erfassen.
4. Lasse `system-architect` Zustände, Integrationen, Single Points of Failure und Migrationsrisiken prüfen.
5. Lasse `test-architect` vorhandene Testebenen, Lücken und tatsächlich ausführbare Befehle belegen.
6. Lasse `security-privacy-reviewer` Datenflüsse, Secrets, GPS-/PII-Risiken und Agentenkontext-Grenzen prüfen.
7. Führe nur sichere, nicht destruktive Inventar-, Build- oder Testbefehle aus. Erfinde keine Ergebnisse.
8. Lege die Baseline für die in `evals/release-gates.yaml` genannten Metriken an oder markiere sie ausdrücklich als `UNKNOWN`.

## Kritische Nutzerflüsse

Mindestens abdecken:

- Kunde erstellt und bezahlt eine Bestellung genau einmal.
- Bestellung wird in der Lieferzentrale sichtbar und bleibt bis zum Terminalzustand auffindbar.
- Fahrer erhält, quittiert und akzeptiert/übernimmt einen Auftrag genau einmal.
- Route und Status bleiben bei Retry, Offline-Phasen und veralteten Events konsistent.
- Dispatcher erkennt Stale/Offline, kann eingreifen und sieht einen Audit-Trail.
- Kunde erhält belastbare Status-/ETA-Informationen.
- Storno, Prep-Delay, Provider-Ausfall und Schichtende haben deterministische Pfade.

## Pflichtausgabe

Erzeuge oder aktualisiere ohne Spekulation:

- `docs/CURRENT-SYSTEM-INVENTORY.md`
- `docs/TRACEABILITY-MATRIX.md`
- `docs/BASELINE-REPORT.md`
- `docs/RISK-REGISTER.md`
- `docs/FINISH-BACKLOG.md`

Der Bericht enthält:

```markdown
## Verdict
AUDITED | PARTIAL | BLOCKED

## Executed evidence
Befehl, Exit-Code, relevante Ausgabe oder Dateiverweis

## Critical flows
Flow -> Implementierung -> Test -> Telemetrie -> Owner -> Status

## P0/P1 blockers
Severity, reproduzierbare Evidenz, Auswirkung, nächster sicherer Schritt

## Unknowns
Nicht verifizierbare Annahmen und benötigte Evidenz

## First vertical slice
Kleinster Slice, der das größte Produktionsrisiko messbar reduziert
```

Eine große Rewrite-Empfehlung ist nur zulässig, wenn eine inkrementelle Reparatur mit konkreter Evidenz unvertretbar ist.
