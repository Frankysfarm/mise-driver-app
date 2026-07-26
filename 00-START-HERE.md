# Mise Liefersystem – Start Here

Dieser Einstieg gilt für Agenten und Menschen, die das Repository analysieren,
ändern oder verifizieren. Er ersetzt keine Spezifikation, sondern verweist auf
die jeweils kanonische Quelle.

## Pflichtlektüre

1. `CLAUDE.md` – Arbeitsvertrag, Sicherheitsgrenzen und Qualitätsablauf.
2. `PROJECT_STATE.md` – aktueller, zeitgebundener Arbeitsstand; Aussagen gegen
   Code und Inventar prüfen.
3. `docs/CURRENT-SYSTEM-INVENTORY.md` – belegter Ist-Zustand, soweit vorhanden.
4. `docs/01-OPERATING-MODEL.md` – Rollen, Task-Lifecycle und Vier-Augen-Prinzip.
5. `docs/02-TARGET-ARCHITECTURE.md` – Zielbild und Zustandsverantwortung.
6. Die für das Task Packet relevanten Spezifikationen, Tests, Evals, ADRs und
   Runbooks.

Bei Widersprüchen gelten Code, ausführbare Tests und beobachtete Evidenz nicht
automatisch als fachlich richtig. Den Konflikt dokumentieren und zur
verantwortlichen Spezifikation beziehungsweise zum Owner zurückgeben.

## Vor einer Änderung

- Ein passendes Task Packet unter `docs/task-packets/` anlegen oder ergänzen.
- Baseline beziehungsweise Reproduktion mit Befehl und Exitcode festhalten.
- Scope, Non-Goals, erwartete Dateien, Tests, Rollback und Risiken benennen.
- Produktlogik und Freigabe durch voneinander unabhängige Rollen bearbeiten.

Für eine koordinierte Stabilisierungssession ist
`MASTER-PROMPT-FABLE-5.md` der Lead-Einstieg. Für einen bereits abgegrenzten
Task gilt dessen Task Packet.

## Lokale Verifikation

```bash
./scripts/verify-fast.sh
```

Die schnelle Prüfung validiert den projektverwalteten Scaffold und verfügbare
lokale Checks. Sie ist kein Release-Gate. Die vollständige Adapterprüfung läuft
über `./scripts/verify-full.sh`; Mobile-, Replay-, Staging- und Canary-Evidenz
muss weiterhin separat belegt werden.

## Abschluss

Jede Übergabe folgt dem Ausgabeformat aus `CLAUDE.md` und nennt exakte
Prüfbefehle, Exitcodes, nicht ausgeführte Prüfungen und verbleibende Risiken.
