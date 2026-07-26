# Mission

Wir stabilisieren und vervollständigen eine bestehende Lieferplattform mit Kundenbestellung, Lieferzentrale, Fahrer-App, Echtzeit-Tracking, Benachrichtigungen und dynamischer Auftragsverteilung. Das Ziel ist ein sicher betreibbares Produktionssystem, nicht ein Rewrite und nicht eine bloße Demo.

## Quellen der Wahrheit

Vor jeder Arbeit lesen:

1. `docs/CURRENT-SYSTEM-INVENTORY.md`, falls vorhanden
2. `docs/01-OPERATING-MODEL.md`
3. `docs/02-TARGET-ARCHITECTURE.md`
4. die für den Task relevanten Spezifikationen
5. bestehende ADRs, Tests, Runbooks und Incident-Berichte

Wenn Dokumentation und Code widersprechen, den Widerspruch belegen. Nicht stillschweigend eine Seite als richtig annehmen.

## Nicht verhandelbare Regeln

1. **Erst reproduzieren, dann ändern.** Für Bugs vor dem Fix einen fehlschlagenden Test, ein Replay-Szenario oder exakt dokumentierte Reproduktionsschritte erzeugen.
2. **Kleine vertikale Slices.** Ein Task muss einen konkreten Nutzerfluss oder eine klar abgegrenzte Zuverlässigkeitseigenschaft verbessern.
3. **Kein Selbst-Approval.** Der Implementierer ist nicht Reviewer oder Release-Gatekeeper derselben Änderung.
4. **Keine erfundenen Ergebnisse.** Nur Tests als ausgeführt melden, die tatsächlich ausgeführt wurden. Exakte Befehle und Resultate nennen.
5. **Kein blinder Rewrite.** Bestehende Verträge, Datenmigrationen, APIs und Clients berücksichtigen. Größere Architekturänderungen benötigen ein ADR und einen Migrationsplan.
6. **Abwärtskompatible Migrationen.** Expand -> migrate/backfill -> switch -> contract.
7. **Idempotenz und Versionierung.** Ereignisse, Order-Transitions, Assignments und externe Callbacks müssen Duplikate sicher verkraften.
8. **Feature Flags und Rollback.** Riskante Pfade müssen deaktivierbar sein, ohne eine Notfall-Codeänderung auszurollen.
9. **Kein Live-Selbstlernen.** Optimierer oder Gewichte werden nicht autonom in Produktion angepasst. Änderungen gehen durch Replay, Shadow Mode, Canary und Freigabe.
10. **Datenschutz.** Keine `.env`, Secrets, private Schlüssel, Roh-Produktionsdaten, vollständige Kundenadressen oder historische Fahrertracks in Modellkontexte.
11. **Keine Produktion durch Agenten.** Agenten dürfen Release-Artefakte und Runbooks vorbereiten, aber keine Live-Freigabe eigenständig ausführen.
12. **Fail-safe statt Wunschdenken.** Jeder kritische Dienst braucht Timeouts, Retries mit Jitter, Circuit Breaker/Fallback, Stale-Erkennung und manuellen Override.

## Kritische Nutzerflüsse

Jede Änderung muss mindestens einen dieser Flüsse referenzieren:

- Kunde erstellt, bezahlt und bestätigt eine Bestellung
- Bestellung wird genau einmal dauerhaft gespeichert und sichtbar
- Bestellung wird vorbereitet/abholbereit
- aktiver Fahrer wird korrekt als verfügbar erkannt
- Dispatch entscheidet oder eskaliert innerhalb des Budgets
- Fahrer erhält Angebot/Zuweisung und quittiert
- ausbleibende Quittierung führt sicher zur Neuvergabe/Eskalation
- Fahrer fährt zur Abholung, holt ab und liefert
- GPS wird aktuell, nachvollziehbar und datenschutzkonform angezeigt
- Kunde sieht korrekten Status und eine belastbare ETA
- Störung eines Drittanbieters führt zu einem definierten Fallback
- Dispatcher kann jederzeit manuell eingreifen
- Abschluss, Abrechnung und Audit-Trail sind konsistent

## Task-Packet-Pflicht

Vor Implementierung muss ein Task Packet nach `templates/task-packet.md` existieren. Es enthält:

- Problem und geschäftliche Auswirkung
- belegte Reproduktion/Baseline
- Scope und Non-Goals
- Akzeptanzkriterien
- erlaubte/erwartete Module
- Tests und Telemetrie
- Rollout und Rollback
- Datenschutz-/Sicherheitsauswirkung

Fehlt etwas, eine explizite Annahme dokumentieren und mit dem sichersten reversiblen Weg fortfahren.

## Qualitätsablauf

```text
REPRODUCE -> DIAGNOSE -> PATCH -> REVIEW -> VERIFY -> SHADOW/CANARY -> OBSERVE -> LEARN
```

Ein Gate darf nur PASS melden, wenn die Evidenz im Repository oder CI-Artefakt vorhanden ist.

## Standard-Ausgabe jedes Agenten

```markdown
## Verdict
PASS | READY_WITH_RISKS | BLOCKED

## Scope
Was wurde geprüft oder geändert?

## Evidence
Dateien, Logs, Traces, Testfälle, Metriken, Reproduktionsschritte.

## Changes
Geänderte Dateien und Begründung; bei Read-only-Agenten: keine.

## Verification
Exakte Befehle, Resultate und nicht ausführbare Prüfungen.

## Risks
Restunsicherheit, Rollback-Bedingungen, offene Abhängigkeiten.

## Handoff
Nächster zuständiger Agent und ein konkretes Task Packet.
```

## Verifikationsbefehle

Schnelle lokale Prüfung:

```bash
./scripts/verify-fast.sh
```

Vollständige Prüfung:

```bash
./scripts/verify-full.sh
```

Die Skripte sind Adapter und müssen an den realen Stack angepasst werden. Ein grünes Placeholder-Skript ist keine Produktfreigabe.

## Zustandsinvarianten

- Eine Bestellung hat zu jedem Zeitpunkt genau einen kanonischen Zustand und eine monotone Version.
- Eine aktive Zuweisung besitzt eine Lease, ein Ablaufdatum und eine eindeutige Entscheidungs-ID.
- Eine Bestellung kann nicht gleichzeitig zwei aktive Fahrerzuweisungen haben.
- `picked_up` darf nie vor bestätigter Zuweisung liegen.
- `delivered` ist terminal, außer über einen ausdrücklich auditierten Korrekturprozess.
- Veraltete GPS-Daten werden sichtbar als veraltet markiert, niemals als live dargestellt.
- Eine fehlgeschlagene Push-Zustellung darf keine Bestellung unsichtbar blockieren.
- Jede automatische Entscheidung ist mit Input-Snapshot, Score-Aufschlüsselung, Algorithmusversion und Reason Codes auditierbar.
