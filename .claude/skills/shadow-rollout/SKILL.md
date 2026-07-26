---
name: shadow-rollout
description: "Plant und bewertet einen sicheren Shadow-, Pilot- und Canary-Rollout für Dispatch-, Tracking-, Notification- oder Zustandsänderungen ohne unkontrollierte Vollfreigabe."
argument-hint: "<Feature/Algorithmus und freizugebender Scope>"
allowed-tools: "Read, Grep, Glob, Bash, Agent, TaskCreate, TaskGet, TaskUpdate, TaskList, TodoWrite"
---

# Shadow Rollout

Erstelle für `$ARGUMENTS` eine stufenweise Freigabe. Ein Shadow-System darf Entscheidungen berechnen und vergleichen, aber keine Fahrer-/Kundenaktion auslösen.

## Stufen

1. **Replay:** historische/pseudonymisierte Snapshots, identische Seeds, Baseline-Vergleich.
2. **Shadow:** Live-Eingänge lesen, nur Audit-Ergebnis schreiben, keine produktive Zuweisung.
3. **Internal/Pilot:** Testfahrer oder kleine kontrollierte Zone/Schicht.
4. **Canary:** beispielhaft 5 % -> 10 % -> 25 % -> 50 % -> 100 %, nur bei erfüllten Gates; tatsächliche Stufen projektspezifisch festlegen.
5. **Soak:** ausreichende Peak-/Off-Peak- und Provider-/Netzwerkvarianten beobachten.

## Vor jeder Stufe

- Hypothese und Erfolgs-/Abbruchmetriken,
- Segmentierung und Ausschlüsse,
- Feature Flag und Kill Switch,
- deterministischer Fallback,
- Dashboard/Alert und menschlicher Owner,
- Daten- und Konfigurationsversion,
- Rollback-Drill,
- Maximaldauer bis automatischer Stopp oder erneuter Freigabe.

Bei Überschreitung einer harten Schwelle automatisch auf sichere Baseline zurückfallen und Incident-Learning auslösen.
