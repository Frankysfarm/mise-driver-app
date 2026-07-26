# Task Packet: P0-DISPATCH-CORRECTNESS – Atomare Zuweisung und Recovery

## Status

`REPRODUCED`

## Severity und Flow

- Severity: `P0`
- Critical Flow ID: Order bereit -> Dispatch -> Offer/ACK -> Pickup
- Owner/Implementierungsagent: offen
- Pflichtreviewer: unabhängiger Backend-/Postgres-Reviewer
- Pflichtprüfer: Integration-/Replay-Prüfer

## Problem

Der bestehende Tick-Lock ist ein zeitbasiertes Decision-Log und damit
TOCTOU-anfällig. Der vorbereitete `pg_try_advisory_xact_lock`-RPC hält den Lock
nur für die RPC-Transaktion, nicht für den anschließenden Dispatch. Beim Merge
werden Order-Claim und Stop-Inserts getrennt geschrieben. Fehler dazwischen
können Doppelzuweisungen oder verwaiste Orders erzeugen.

## Evidence/Baseline

- Reproduktionsschritte: zwei parallele Ticks lesen denselben freien Auftrag,
  bevor einer sein Decision-Log beziehungsweise seinen Claim dauerhaft
  abgeschlossen hat.
- fehlschlagender Test/Replay: noch als ausführbarer Integrationstest zu bauen;
  die getrennten DB-Schritte belegen das Race strukturell.
- Logs/Trace/Metric: keine belastbare Duplicate-Assignment-Metrik vorhanden.
- betroffene Version/Umgebung: wiederhergestellte Produktionsartefakte vom
  2026-07-24; Produktion derzeit nicht erreichbar.
- Häufigkeit und Reichweite: bei Tick-Überlappung, Blue-Green-Überlappung oder
  Retry; jede fertige Lieferorder ist potenziell betroffen.
- Annahmen: Postgres/Supabase RPCs stehen zur Verfügung.

## Root-Cause-Hypothese

Kritische Zustandsübergänge wurden als mehrere Supabase-HTTP-Requests statt als
eine versionierte DB-Transaktion modelliert. Der Anwendungscode besitzt keine
DB-Session, über die ein session-level Advisory Lock den gesamten Tick schützen
könnte.

## Scope

### In Scope

- atomare Work-Lease oder DB-seitiger Claim pro Order,
- Batch-, Stop- und Assignment-Erstellung in einer Transaktion,
- State-/Version-Guards für Accept, Timeout und Recovery,
- eindeutige Constraints,
- Race-, Failure- und Recovery-Integrationstests,
- Audit- und Duplicate-Assignment-Telemetrie.

### Non-Goals

- neue Score-Gewichte,
- selbstlernender Optimierer,
- vollständiger Dispatch-Rewrite,
- Produktionsfreigabe ohne Staging/Canary.

### Erlaubte/erwartete Module

- Backoffice `frank.ts` und `recovery.ts`,
- additive Postgres-Migration/RPC,
- Dispatch-Integrationstests,
- Observability-/Runbook-Dateien.

## Akzeptanzkriterien

1. Given zwei parallele Ticks, When beide dieselbe Order sehen, Then genau einer
   erzeugt eine aktive Zuweisung.
2. Batch, Stops, Order-Claim, Lease und Audit werden gemeinsam committed oder
   gemeinsam zurückgerollt.
3. Accept am Timeout-Rand kann nicht anschließend gecancelt werden.
4. Recovery verändert nur Rows mit erwarteter Batch-ID, State und Version.
5. Wiederholung derselben Operation ist idempotent.
6. Ein DB-Fehler erzeugt sichtbare Telemetrie und blockiert keine Order still.

## Implementierungsplan

1. Synthetischen parallelen Integrationstest erstellen.
2. Additive RPC für Claim/Batch/Stops/Audit mit Conditional Update und
   versionierter Lease implementieren.
3. Eindeutige aktive Assignment-Constraints nach Duplikat-Preflight ergänzen.
4. Frank auf RPC-Rückgabevertrag umstellen; alter Pfad bleibt per Flag als
   Fallback verfügbar.
5. Accept/Timeout/Recovery auf State+Version-Guards umstellen.
6. Replay und Failure Injection ausführen.

## Testplan

- Unit: State Guards, Lease-Ablauf, Idempotency-Key.
- Contract: RPC-Ergebnis und Fehlercodes.
- Integration: 25–100 parallele Claims derselben Order.
- E2E: Single Order, Accept/Timeout-Race, DB-Fehler nach jedem logischen Schritt.
- Dispatch Replay: deterministischer gleicher Input/Seed.
- Failure Injection: Timeout, Connection Reset, Deadlock und Retry.
- Load: 50 fertige Orders, überlappende Ticks, begrenztes Latenzbudget.

## Observability

- Metrik `dispatch_claim_conflict_total`.
- Metrik `active_assignment_invariant_violation_total`.
- strukturierter Audit mit `decision_id`, `order_version`, `route_version`.
- Alarm bei mehr als einer aktiven Zuweisung pro Order.

## Rollout

- Flag: neuer atomarer Claim zunächst aus.
- Shadow: alter Algorithmus entscheidet, neuer Claim simuliert auf Testdaten.
- Canary: ein Test-Tenant/ein Fahrer mit Supervisor.
- Stop-Kriterien: Duplicate Assignment, verlorene Order, falscher Cancel,
  Dispatch-Latenz über Budget.

## Rollback

- Code: Feature Flag zurück auf alten Pfad.
- Daten: additive Migration nicht sofort entfernen.
- In-Flight Orders: niemals automatisch reassignen; manueller Resolver.
- alte/neue Clients: API-Vertrag abwärtskompatibel halten.
- Owner: menschlicher Release-Verantwortlicher.

## Handoff-Evidenz

- Branch/Worktree: noch nicht angelegt.
- Commit: keiner.
- geänderte Dateien: nur Planung/Dokumentation.
- ausgeführte Befehle: Read-only Code-/Workflow-/Git-Audit.
- Resultate: P0 strukturell reproduziert; Produktion blockiert.
- offene Risiken: realer DB-Schema-/Serverstand muss nach Wiederherstellung
  gegen den Entwurf geprüft werden.
