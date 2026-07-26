---
name: bug-fix-loop
description: "Führt einen Produktionsbug von reproduzierbarer Evidenz über Root Cause, minimale Korrektur und unabhängige Verifikation bis zum dauerhaften Regressionstest."
argument-hint: "<Ticket, Fehlerbeschreibung, Log-/Trace-Referenz oder Reproduktionsschritte>"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Bug-Fix-Loop

Bearbeite `$ARGUMENTS` als Defekt-Hypothese. Ein Symptom ist noch keine Ursache.

## Unverhandelbarer Ablauf

1. **Triage:** Severity, betroffene Nutzerflüsse, Blast Radius, Datenrisiko und sichere Sofortmaßnahme bestimmen.
2. **Reproduktion:** `bug-reproducer` erzeugt den kleinsten deterministischen Test oder ein Simulationsszenario, das vor dem Fix fehlschlägt.
3. **Root Cause:** `root-cause-debugger` verfolgt den Fehler über Zustandsübergänge, Logs/Traces, Idempotenzschlüssel, Versionen und Providergrenzen.
4. **Task Packet:** Akzeptanzkriterien, Nicht-Ziele, Dateien, Invarianten, Telemetrie, Rollout und Rollback festhalten.
5. **Implementierung:** Genau ein zuständiger Engineering-Agent arbeitet in einem isolierten Worktree. Keine Nebenrefactorings.
6. **Unabhängiges Review:** `code-reviewer` plus passende Domain-/Security-Prüfung; der Implementierer darf nicht freigeben.
7. **Verifikation:** Der ursprüngliche Red-Test muss grün werden; passende Unit-, Integrations-, E2E-, Last- oder Dispatch-Simulationen ausführen.
8. **Release-Gate:** Bei P0/P1 oder verteilten Zustandsänderungen `/release-gate` ausführen.
9. **Lernen:** Mindestens Regressionstest; bei Erkennbarkeitslücke zusätzlich Monitor/Alert; bei Designentscheidung ADR.

## Stop-Bedingungen

Stoppe mit `BLOCKED`, statt zu raten, wenn:

- der Fehler nicht reproduziert oder durch Telemetrie belegt werden kann,
- Roh-Produktions-PII/Secrets erforderlich wären,
- die vorgeschlagene Änderung Zustandsinvarianten bricht,
- notwendige Rollback-/Fallback-Pfade fehlen,
- Tests wegen unbekannter Projektbefehle nur behauptet werden könnten.

## Pflichtausgabe

```markdown
## Bug verdict
FIXED_AND_VERIFIED | MITIGATED | NOT_REPRODUCED | BLOCKED

## Reproduction
Vorheriger Fehler, Test/Szenario und Evidenz

## Root cause
Technische Ursache, nicht nur Symptom

## Patch
Minimaler Scope und geänderte Invarianten

## Verification
Exakte Befehle, Ergebnisse und nicht ausführbare Prüfungen

## Release safety
Feature Flag, Canary, Monitoring, Rollback, manueller Fallback

## Permanent learning
Regressionstest / Szenario / Alert / ADR / Runbook
```
