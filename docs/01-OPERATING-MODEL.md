# 01 – Operating Model: Von „fast fertig“ zu produktionsreif

## Leitgedanke

Ein starkes Modell allein macht ein System nicht fertig. Produktionsreife entsteht durch eine kontrollierte Schleife aus Spezifikation, Reproduktion, Implementierung, unabhängiger Kritik, automatisierter Prüfung, beobachteter Ausrollung und dauerhaftem Lernen.

Die Agenten „trainieren“ daher nicht autonom den Live-Dispatch. Sie verbessern:

- die explizite Systemspezifikation,
- den Test- und Simulationsdatensatz,
- die Codebasis,
- die Review-Checklisten,
- die Telemetrie,
- die Fehlerbibliothek und
- die Entscheidungen in ADRs.

Das ist überprüfbar und reversibel.

## Agenten-Hierarchie

```text
Chief Finish Architect (Fable)
├── Discovery & Product
│   ├── Repository Cartographer
│   ├── Product Requirements Auditor
│   └── System Architect
├── Domain Specialists
│   ├── Dispatch Optimizer
│   ├── Tracking & Realtime Engineer
│   └── Notification Reliability Engineer
├── Implementation
│   ├── Backend Engineer
│   ├── Driver App Engineer
│   ├── Dispatcher Console Engineer
│   ├── Customer Ordering Engineer
│   ├── Data Consistency Engineer
│   └── Integration Engineer
├── Design
│   └── UX & Accessibility Designer
├── Independent Verification
│   ├── Bug Reproducer
│   ├── Root Cause Debugger
│   ├── Code Reviewer
│   ├── Test Architect
│   ├── E2E Mobile Tester
│   ├── Dispatch Simulation Tester
│   ├── Performance & Reliability Engineer
│   └── Security & Privacy Reviewer
└── Operations & Release
    ├── Observability SRE
    ├── Release Gatekeeper
    └── Incident Learning Agent
```

## Verantwortungsgrenzen

### Lead

Der Lead priorisiert, zerlegt, delegiert und entscheidet über Gates. Er soll nicht selbst quer durch alle Module implementieren. Seine wichtigste Aufgabe ist, Widersprüche und unbelegte Behauptungen zu erkennen.

### Implementierer

Implementierer besitzen einen eng definierten Scope, arbeiten in isolierten Worktrees und liefern Tests sowie Telemetrie mit. Sie geben ihre Arbeit nicht selbst frei.

### Reviewer und Tester

Reviewer sind standardmäßig read-only. Testagenten dürfen Test- und Eval-Artefakte ändern, aber keine Produktionslogik „nebenbei reparieren“. Ein gefundener Defekt geht zurück an den passenden Implementierer.

### Release-Gatekeeper

Der Gatekeeper bewertet nur vorhandene Evidenz. „Code sieht gut aus“ ist kein Release-Beleg.

## Task-Lifecycle

```text
DRAFT
  -> READY_FOR_REPRODUCTION
  -> REPRODUCED
  -> READY_FOR_IMPLEMENTATION
  -> IMPLEMENTED
  -> REVIEWED
  -> VERIFIED
  -> READY_FOR_SHADOW_OR_CANARY
  -> OBSERVED
  -> RELEASED
  -> LEARNING_CAPTURED
```

Ein Task darf keinen Zustand überspringen, wenn dadurch eine kritische Prüfung entfällt.

## Pflichtartefakte pro Task

| Phase | Pflichtartefakt |
|---|---|
| Problem | Task Packet |
| Reproduktion | Test, Replay oder exakte Schritte |
| Diagnose | Root-Cause-Hypothese mit Evidenz |
| Umsetzung | kleiner Diff, Migration/Fallback falls nötig |
| Review | unabhängiges Review-Protokoll |
| Verifikation | Befehle, Resultate, Artefakte |
| Rollout | Flag, Canary/Shadow, Rollback |
| Beobachtung | relevante Metriken/Logs |
| Lernen | Regressionstest, Szenario, ADR oder Incident-Eintrag |

## P0–P3

- **P0:** Datenverlust, Doppelbelastung, falsche Zustellung, Sicherheitsvorfall, Systemausfall ohne Fallback.
- **P1:** Kritischer Nutzerfluss regelmäßig blockiert; Bestellungen bleiben hängen; Tracking/Assignment ist unzuverlässig; keine sichere manuelle Rettung.
- **P2:** Deutliche Kosten-, ETA-, UX- oder Performanceverschlechterung mit Workaround.
- **P3:** Kosmetik, interne Ergonomie, kleinere Optimierung ohne unmittelbares Betriebsrisiko.

P0 und P1 haben Vorrang vor Dispatch-„Intelligenz“.

## Vier-Augen-Matrix

| Änderung | Implementierung | Pflichtreview | Pflichtprüfung |
|---|---|---|---|
| Order-State/DB | Data/Backend | Code + Security | Integration + Idempotenz |
| Dispatch | Dispatch Optimizer | Code + System Architect | Replay + Shadow |
| Fahrer-GPS | Tracking/Driver App | Code + Privacy | Device + Stale/Offline |
| Push/Alarm | Notification/Driver App | Code + Security | Geräte-/Eskalationstest |
| Kundencheckout | Customer Engineer | Code + Product | E2E + Payment-Sandbox |
| Infrastruktur | Observability/Backend | Code + Security | Load/Failure/Runbook |

## Modell-Routing

- **Fable:** Lead, Systemarchitektur, schwierige Root Cause, Dispatch-Entscheidungen, Security und Release-Gates.
- **Sonnet:** klar abgegrenzte Implementierung, Testautomatisierung, Mobile/Web/Backend-Arbeit.
- **Haiku:** schnelle Repository-Kartierung und repetitive Log-/Dateiinventur, sofern die Aufgabe nicht sicherheitskritisch ist.

Höhere Modellleistung ersetzt keine unabhängigen Tests.

## Lernschleife

Nach jeder Regression:

1. Minimal reproduzierbares Szenario speichern.
2. Ursache kategorisieren, zum Beispiel Race, Retry, Zeitbasis, Offline, Berechtigung, Migration, Drittanbieter.
3. Regressionstest hinzufügen.
4. Monitoring-Lücke schließen.
5. Agentenregel oder Checkliste nur dann ergänzen, wenn sie generalisierbar ist.
6. Keine personenbezogenen Rohdaten in Agenten-Memory speichern.

## Parallelität

Parallel arbeiten nur bei unabhängigen Datei- und Datenbereichen. Beispiele:

- Fahrer-App UI und Dispatch-Replay-Harness: parallel möglich.
- Zwei Agenten ändern dieselbe Assignment-State-Machine: nicht parallel.
- Schemaänderung und Backendverbraucher: nur mit explizitem Expand/Migrate/Contract-Plan.

## Definition eines guten Handoffs

Ein Handoff enthält keinen vagen Satz wie „bitte prüfen“. Es enthält:

- konkrete Branch-/Worktree-Referenz,
- Task Packet,
- geänderte Dateien,
- bekannte Risiken,
- genaue Prüfkommandos,
- erwartete Resultate,
- offene Fragen als Annahmen,
- Rollback-/Feature-Flag-Information.
