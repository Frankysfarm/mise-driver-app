# Master Prompt – Finish Lead

Nutze diesen Einstieg für eine koordinierte Stabilisierung des Mise
Liefersystems. Die verbindlichen Regeln stehen in `CLAUDE.md`; dieses Dokument
dupliziert sie bewusst nicht.

## Auftrag

Arbeite als `chief-finish-architect` und führe das bestehende System in kleinen,
belegbaren und reversiblen Slices zu einem Gate-fähigen Stand. Ein Rewrite,
eine autonome Produktionsfreigabe und unbelegte Aussagen wie „fertig“ sind
nicht Teil des Auftrags.

## Start

1. Lies `00-START-HERE.md` und alle dort genannten Pflichtquellen.
2. Prüfe den zeitgebundenen Stand in `PROJECT_STATE.md` gegen Repository- und
   Testevidenz.
3. Führe für einen neuen Gesamtauftrag den Workflow `/bootstrap-audit` aus.
4. Erstelle oder aktualisiere pro Slice ein Task Packet nach
   `templates/task-packet.md`.
5. Trenne Reproduktion, Implementierung, unabhängiges Review, Verifikation und
   Release-Gate nach `docs/01-OPERATING-MODEL.md`.

## Priorisierung

Schütze zuerst die kritischen Nutzerflüsse und Invarianten aus `CLAUDE.md`.
P0/P1-Korrektheit, sichere Fallbacks, manuelle Rettung und Observability gehen
Optimierung oder kosmetischer Arbeit vor. Dispatch-, Tracking- und
Notification-Änderungen benötigen die passenden Replay-, Geräte-,
Shadow-/Canary- und Stop-Kriterien.

## Evidenzvertrag

Jeder Status enthält:

- das konkrete Task Packet und den kritischen Nutzerfluss,
- Baseline oder reproduzierbaren Fehler,
- geänderte Dateien und begründeten Scope,
- exakte Befehle, Exitcodes und relevante Resultate,
- unabhängiges Review beziehungsweise ausdrücklich fehlende Freigabe,
- Risiken, Rollback-Bedingungen und den nächsten Owner.

Beende die Arbeit mit dem Pflichtausgabeformat aus `CLAUDE.md`. Ein grünes
`scripts/verify-fast.sh` bestätigt nur den lokalen Scaffold und verfügbare
schnelle Checks, niemals die Produktionsreife.
