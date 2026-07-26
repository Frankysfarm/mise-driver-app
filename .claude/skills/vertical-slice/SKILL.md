---
name: vertical-slice
description: "Stabilisiert einen konkreten Nutzerfluss end-to-end über Kundenoberfläche, Backend, Dispatch, Fahrer-App, Dispatcher-Konsole, Persistenz und Telemetrie."
argument-hint: "<konkreter Nutzerfluss, z. B. Bestellung -> Fahrerannahme -> Abholung -> Zustellung>"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Vertical Slice

Stabilisiere `$ARGUMENTS` als kleinsten end-to-end freigabefähigen Slice. Kein horizontaler Großumbau.

## Slice-Vertrag

Definiere vor Änderungen:

- Nutzer und gewünschtes Ergebnis,
- Start-, Zwischen-, Fehler- und Terminalzustände,
- Invarianten und Idempotenzgrenzen,
- API-/Event-Verträge und Versionsregeln,
- UI-Zustände einschließlich Loading, Offline, Retry und Stale,
- Telemetrie und Support-/Dispatcher-Sicht,
- Akzeptanztests und Rollback.

## Delegationsmuster

1. `product-requirements-auditor`: eindeutige Akzeptanzkriterien.
2. `system-architect` und Domain-Agent: Zustände, Datenfluss, Migrations-/Kompatibilitätsplan.
3. `ux-accessibility-designer`: Fahrer-/Dispatcher-/Kundenerlebnis, Fehlermeldungen und sichere Aktionen.
4. Passender Implementierungsagent je Teil; parallele Arbeit nur bei klar getrennten Dateien/Verträgen.
5. `data-consistency-engineer`: bei Order-, Assignment-, Payment- oder Route-State.
6. `integration-engineer`: bei Push, Karten, Payment, Telefonie oder sonstigen Providern.
7. `code-reviewer`, `test-architect` und passende E2E-/Performance-/Security-Agenten.
8. `observability-sre`: Metrik, Trace, Alarm und Runbook vor Freigabe.

## Ende-zu-Ende-Matrix

Führe mindestens diese Varianten aus oder begründe jede Lücke:

- Happy Path,
- Retry/Duplicate Event,
- Offline und Wiederverbindung,
- veraltete Route-/Order-Version,
- Provider Timeout/Fehler,
- Storno oder fachliche Änderung während des Flows,
- unberechtigte oder ungültige Aktion,
- manueller Dispatcher-Override,
- Rollback-/Fallback-Verhalten.

## Definition des Slice-Abschlusses

Der Slice ist erst `READY`, wenn Anforderung, Test, Telemetrie, Runbook und Rollback miteinander verknüpft sind und kein offener P0/P1 im Scope verbleibt.
