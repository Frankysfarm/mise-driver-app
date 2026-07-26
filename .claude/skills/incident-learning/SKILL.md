---
name: incident-learning
description: "Verwandelt einen Incident oder eine Regression in belegte Ursachen, Schutzmechanismen, Regressionstests, Telemetrie und priorisierte Systemverbesserungen."
argument-hint: "<Incident-ID, Zeitfenster, Regression oder Fehlerbericht>"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Incident Learning

Analysiere `$ARGUMENTS` blameless und evidenzbasiert. Keine personenbezogene Schuldzuweisung; untersuche Systembedingungen und fehlende Schutzschichten.

## Ablauf

1. Zeitlinie aus Audit-Events, Traces, Deployments, Konfigurationsänderungen und Dispatcher-Aktionen rekonstruieren.
2. Kundenauswirkung, Fahrer-/Operations-Auswirkung, Dauer und betroffene Orders bestimmen; Daten minimieren/pseudonymisieren.
3. `incident-learning-agent` koordiniert die Analyse; `root-cause-debugger` prüft technische Kausalität.
4. Unterscheide Trigger, Root Cause, beitragende Faktoren, fehlende Detection und fehlende Containment-Schicht.
5. Prüfe, warum bestehende Tests, Reviews, Gates, Monitore oder Fallbacks den Fehler nicht verhindert/verkürzt haben.
6. Erzeuge priorisierte Corrective Actions mit Owner, Termin, Akzeptanztest und Erfolgssignal.
7. Ergänze zwingend mindestens einen dauerhaften Schutz: Regressionstest, Simulationsfall, Monitor, Runbook, ADR oder Gate.

## Pflichtartefakt

Erzeuge einen Bericht nach `templates/incident-review.md` und verlinke:

- reproduzierbares Szenario,
- Fix-/Mitigation-Task Packet,
- neue Test-/Monitoring-Artefakte,
- Rollout-/Rollback-Lektion,
- überprüfbaren Abschluss der Corrective Actions.
