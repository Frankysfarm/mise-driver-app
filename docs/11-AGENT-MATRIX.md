# 11 – Agentenmatrix und Verantwortungsgrenzen

## Führungsprinzip

`chief-finish-architect` zerlegt Arbeit in Task Packets und delegiert. Kein Implementierungsagent genehmigt seine eigene Änderung. `release-gatekeeper` fällt die unabhängige Freigabeentscheidung.

| Ebene | Agent | Hauptauftrag | Darf ändern? | Muss unabhängig geprüft werden durch |
|---|---|---|---:|---|
| Führung | chief-finish-architect | Priorisierung, Delegation, Traceability, Evidenz | nur Plan-/Dokuartefakte | release-gatekeeper |
| Führung | release-gatekeeper | GO/LIMITED_GO/NO_GO | nein | – |
| Discovery | repository-cartographer | Ist-Architektur und Befehle belegen | nein | chief |
| Product | product-requirements-auditor | Flows und Akzeptanzkriterien | Spezifikationen | test-architect |
| Architektur | system-architect | Zustände, Grenzen, ADRs, Migration | Architekturartefakte | code/security/reliability |
| Domain | dispatch-optimizer | Routing, Fernorder-Hold, Score/Fallback | Dispatch-Scope | simulation + reviewer |
| Domain | tracking-realtime-engineer | GPS, Presence, Realtime, Stale/Offline | Tracking-Scope | mobile + reliability |
| Domain | notification-reliability-engineer | Push, ACK, Eskalation, VoIP-Fallback | Notification-Scope | mobile + integration |
| Engineering | backend-engineer | APIs, Services, Jobs | Backend | reviewer + tests |
| Engineering | driver-app-engineer | Fahrer-App, Background/Offline | Mobile | E2E + reviewer |
| Engineering | dispatcher-console-engineer | Operations-UI und Override | Web/Console | UX + E2E |
| Engineering | customer-ordering-engineer | Bestellung, Payment, Status | Customer Flow | E2E + data consistency |
| Engineering | data-consistency-engineer | State, Idempotenz, Outbox/Inbox | Daten-/State-Scope | reviewer + tests |
| Engineering | integration-engineer | Karten, Push, Telefonie, Payment | Adapter | contract + reliability |
| Design | ux-accessibility-designer | UI-Zustände, sichere Bedienung | Design/UI-Spec | Product + E2E |
| Quality | bug-reproducer | reproduzierbarer Red-Test | Tests/Fixtures | root-cause-debugger |
| Quality | root-cause-debugger | technische Kausalität | Diagnose/kleine Instrumentierung | reviewer |
| Quality | code-reviewer | Korrektheit, Wartbarkeit, Invarianten | nein | – |
| Quality | test-architect | Testpyramide, Traceability | Tests/Plan | gatekeeper |
| Quality | e2e-mobile-tester | reale Mobile-/Netz-/Lifecycle-Flows | Tests | gatekeeper |
| Quality | dispatch-simulation-tester | Szenarien, Replay, KPI-Vergleich | Evals | gatekeeper |
| Quality | performance-reliability-engineer | Last, Tail-Latenz, Failover | Tests/Configs im Scope | gatekeeper |
| Quality | security-privacy-reviewer | Auth, Secrets, GPS/PII, Retention | Security-Artefakte | gatekeeper |
| Operations | observability-sre | SLOs, Traces, Alerts, Runbooks | Observability | gatekeeper |
| Operations | incident-learning-agent | Postmortem und dauerhafte Schutzschichten | Lernartefakte | chief |

## Empfohlene Modellverteilung

- **Fable 5:** Chief, System Architect, Dispatch Optimizer, Root Cause bei komplexen verteilten Fehlern, Release Gatekeeper und Security für besonders kritische Änderungen.
- **Sonnet:** fokussierte Implementierungen, Reviews, Integration, E2E und Testarchitektur.
- **Haiku:** schnelle Inventar-, Format-, Dokumentations- und wiederholbare Prüfaufgaben, sofern das Risiko niedrig ist.

Die Modellwahl ersetzt keine unabhängige Evidenz und kein Release-Gate.
