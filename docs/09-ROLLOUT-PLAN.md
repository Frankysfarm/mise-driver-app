# 09 – Rollout-Plan

## Phase 0 – Freeze und Inventar

Ziel: Verstehen, bevor geändert wird.

- Architektur, State Machines, Integrationen und Datenflüsse kartieren.
- Produktionsfehler P0–P3 erfassen.
- Baseline-Metriken und kritische Flows festlegen.
- Test-/Staging-Umgebung reproduzierbar machen.
- Feature-Flag- und Rollback-Fähigkeit prüfen.

Exit: `CURRENT-SYSTEM-INVENTORY.md` vollständig genug; erste P0/P1 Task Packets freigegeben.

## Phase 1 – Korrektheitsfundament

- Order State Machine
- Idempotenz/Outbox/Inbox
- Assignment Lease und Versionen
- Duplicate-/Race-Schutz
- manuelle Rettung
- Audit Trail

Exit: keine bekannten P0-Datenintegritätsfehler; kritische State-Invarianten automatisiert.

## Phase 2 – Fahrer-App, Tracking und Alarmierung

- Schicht-/Presence-State
- Background Tracking
- Stale-Erkennung
- Push Receipt/ACK
- Retry/VoIP/Neuvergabe
- App-Version/Token-Pflege
- Ops-Anzeige

Exit: Geräte-Matrix und Failure-Szenarien bestanden; keine stille Zuweisungsblockade.

## Phase 3 – Dispatch Baseline und Optimierer

- deterministischer Replay-Harness
- aktuelle Baseline messen
- Best-Insertion/Fallback
- Remote-Hold/Latest Safe Departure
- Multi-Stop/Korridor
- Audit/Reason Codes

Exit: Kandidat erfüllt Guardrails im Replay und bleibt innerhalb des Latenzbudgets.

## Phase 4 – Shadow Mode

Neue Engine entscheidet parallel, aber Produktionsassignment bleibt unverändert.

Messen:

- gleiche/abweichende Fahrerwahl,
- erwartete und tatsächliche ETA,
- Kosten/Kilometer,
- Deadline-/Quality-Verletzungen,
- Rechenzeit/Fallback,
- Gründe der Abweichung.

Jede gefährliche Abweichung wird als Szenario gespeichert.

Exit: ausreichende Stichprobe; keine ungeklärten kritischen Guardrail-Verletzungen.

## Phase 5 – Pilot/Canary

- begrenzte Zone oder Fahrergruppe,
- niedriger Traffic-Anteil,
- Supervisor besetzt,
- Feature Flag und One-Click-Fallback,
- enges Dashboard/Alerting,
- vorab definierte Stop-Kriterien.

Stop-Kriterien, beispielhaft:

- Duplicate Assignment,
- On-time deutlich schlechter,
- GPS-/ACK-Ausfall,
- Fallbackrate/Dispatch-Latenz über Schwelle,
- manuelle Eingriffe stark erhöht,
- Incident ohne klares Runbook.

## Phase 6 – Stufenweise Ausweitung

```text
5 % -> 10 % -> 25 % -> 50 % -> 100 %
```

Nur erhöhen, wenn das vorherige Fenster ausreichend beobachtet wurde. Nicht gleichzeitig Algorithmus, Push-System und GPS-Pipeline vollständig umstellen; sonst ist die Ursache nicht isolierbar.

## Phase 7 – Nachbeobachtung

- Guardrails und Kosten prüfen,
- Support-/Dispatcher-Feedback erfassen,
- regressionsfähige Fälle speichern,
- Runbooks und ADRs aktualisieren,
- alte Pfade erst nach Stabilitätsfenster entfernen.

## Rollback

Jede riskante Änderung dokumentiert:

- welches Flag,
- welche Version,
- welche Datenmigration,
- ob alter Client kompatibel bleibt,
- wie In-Flight Orders behandelt werden,
- wer entscheidet,
- welche Metrik den Rollback auslöst.

Ein Rollback darf keine bereits abgeholte Order verwaisen lassen.

## Kein Big-Bang

Die Plattform wird entlang kompletter Nutzerflüsse stabilisiert. Beispiel:

```text
Single Order -> Single Driver -> Push ACK -> GPS -> Delivery
```

Erst wenn dieser Slice stabil ist, folgen Batching, Remote Holding und komplexe Reoptimierung.
