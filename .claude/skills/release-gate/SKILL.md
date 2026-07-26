---
name: release-gate
description: "Fällt eine unabhängige GO-, LIMITED_GO- oder NO_GO-Entscheidung für einen Release-Kandidaten anhand nachprüfbarer Qualitäts-, Sicherheits-, Betriebs- und Rollback-Evidenz."
argument-hint: "<Release-Kandidat, Commit/PR, Feature Flag oder Slice>"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Release Gate

Prüfe `$ARGUMENTS` unabhängig. Implementiere in diesem Workflow keine fehlenden Features und repariere keine Fehler stillschweigend.

## Gatekeeper

Delegiere die finale Entscheidung an `release-gatekeeper`. Ziehe je nach Scope mindestens hinzu:

- `code-reviewer`,
- `test-architect`,
- `security-privacy-reviewer`,
- `performance-reliability-engineer`,
- `observability-sre`,
- bei Dispatch `dispatch-simulation-tester`,
- bei Mobile `e2e-mobile-tester`.

## Erforderliche Evidenz

- Scope und Commit/Artefakt eindeutig identifiziert.
- Akzeptanzkriterien mit ausgeführten Tests verknüpft.
- Keine offenen P0/P1; P2-Risiken explizit akzeptiert und terminiert.
- Migration vorwärts/rückwärts sicher oder klare Kompatibilitätsphase.
- Feature Flag/Canary-Scope und Kill Switch vorhanden.
- Telemetrie, Alarm, Dashboard und menschlicher Owner vorhanden.
- Rollback getestet oder mit realistischem Drill belegt.
- Externe Provider- und Offline-Fallbacks getestet.
- Support-/Dispatcher-Runbook aktualisiert.
- Datenschutz-/Security-Prüfung im Scope bestanden.

Nutze `evals/release-gates.yaml` und `templates/release-checklist.md`.

## Verdict-Regeln

- `GO`: alle harten Gates erfüllt; kontrollierter Rollout zulässig.
- `LIMITED_GO`: nur eng begrenzter Pilot/Canary mit expliziten Stop-Schwellen.
- `NO_GO`: fehlende Evidenz, harter Defekt oder unkontrollierbares Risiko.

„Tests wirken gut“ oder „sollte funktionieren“ ist keine Freigabeevidenz.
