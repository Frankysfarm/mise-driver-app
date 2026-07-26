# Task Packet: T00 – Verifikations-Scaffold auf Source-Tree begrenzen

## Status

`VERIFIED`

## Severity und Flow

- Severity: `P2`
- Critical Flow ID: sichere lokale Verifikation vor jeder Änderung
- Owner/Implementierungsagent: T00 Native Verification
- Pflichtreviewer: unabhängiger Scaffold-/Code-Reviewer
- Pflichtprüfer: Hauptagent

## Problem

`scripts/validate-agent-system.py` durchsucht JSON, YAML und Python unter dem
gesamten Repository rekursiv. Dadurch können Abhängigkeiten, verschachtelte
Claude-Worktrees und generierte Build-Ausgaben das Ergebnis des eigentlichen
Source-Trees verfälschen. Außerdem verlangt der Validator zwei nicht vorhandene
Einstiegsdokumente.

## Evidence/Baseline

- Reproduktion: `./scripts/verify-fast.sh`
- Baseline: Exitcode `1`
- Fehler: `00-START-HERE.md` und `MASTER-PROMPT-FABLE-5.md` fehlen.
- Strukturelle Ursache: unbeschränkte `ROOT.rglob(...)`-Scans für Daten- und
  Python-Dateien.
- Annahmen: Abhängigkeiten, Nested Worktrees, Build- und Cache-Ausgaben sind
  keine projektverwalteten Scaffold-Daten.

## Scope

### In Scope

- zentrale, explizite Verzeichnisausschlüsse im Validator,
- echte Einstiegsdokumente mit Verweisen auf kanonische Quellen,
- lokale Fast-Verifikation und gezielte Ausschluss-Regression.

### Non-Goals

- App- oder Produktlogik,
- Dependencies oder Netzwerkzugriff,
- Build, Deploy oder Release-Freigabe,
- Änderungen an fachlichen Spezifikationen.

### Erlaubte/erwartete Module

- `scripts/validate-agent-system.py`
- `00-START-HERE.md`
- `MASTER-PROMPT-FABLE-5.md`
- dieses Task Packet

## Akzeptanzkriterien

1. `verify-fast` läuft auf dem beabsichtigten Source-Tree mit Exitcode `0`.
2. Ungültige JSON-/Python-Dateien in ausgeschlossenen Abhängigkeits-,
   Worktree- oder Build-Verzeichnissen verändern das Ergebnis nicht.
3. Ungültige projektverwaltete Daten werden weiterhin erkannt.
4. Beide Einstiegspunkte verweisen sachlich auf die kanonischen Regeln und
   behaupten keine Produktfreigabe.
5. Der Diff enthält keine App-/Produktlogik.

## Implementierungsplan

Einen deterministischen Source-Tree-Walker ergänzen, ausgeschlossene
Verzeichnisse vor dem Abstieg entfernen, Daten- und Python-Scans darauf
umstellen und zwei schlanke Einstiegspunkte anlegen.

## Testplan

- Validator-Python kompilieren.
- Bash-Syntax der Verifikationsskripte prüfen.
- `verify-fast` ausführen.
- Temporäre ungültige Dateien in ausgeschlossenen Verzeichnissen anlegen und
  einen erfolgreichen Validator-Lauf erwarten.
- Temporäre ungültige Source-Datei anlegen und einen fehlschlagenden
  Validator-Lauf erwarten; Testartefakte anschließend vollständig entfernen.

## Observability

Keine Laufzeittelemetrie erforderlich. Befehle, Exitcodes und relevante
Validator-Ausgabe bilden die lokale Evidenz.

## Rollout

Nur lokaler Repository-Diff; keine Produktion, kein Feature Flag und kein
Canary erforderlich.

## Rollback

Die vier T00-Dateiänderungen verwerfen. Es entstehen keine Datenmigrationen
oder In-Flight-Auswirkungen.

## Handoff-Evidenz

- Branch/Worktree: `codex/t00-native-verify` /
  `/Users/eule/mise-driver-native-t00`
- Commit: keiner
- Baseline: `./scripts/verify-fast.sh`, Exitcode `1`; beide Pflicht-Einstiege
  fehlten.
- Python-Compile und Bash-Syntax: Exitcode jeweils `0`.
- Ausschluss-Regression mit absichtlich ungültigen Dateien unter
  `.claude/worktrees/`, `node_modules/` und `build/`: Validator Exitcode `0`.
- Negative Source-Tree-Kontrolle mit ungültigem `evals/*.json`: erwarteter
  Validator-Exitcode `1`.
- Final: `./scripts/verify-fast.sh`, Exitcode `0`; `git diff --check`,
  Exitcode `0`.
- Temporäre Testfixtures wurden vollständig entfernt.
- offene Risiken: Validator prüft Format und Scaffold, nicht Produktverhalten
