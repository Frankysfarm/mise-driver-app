# 10 – Definition of Done und Release Gates

## Grundsatz

„Keine Bugs mehr“ ist kein überprüfbares Freigabekriterium. Produktionsreife bedeutet:

- bekannte kritische Risiken sind geschlossen,
- zentrale Invarianten sind automatisiert geprüft,
- verbleibende Fehler werden schnell erkannt,
- sichere Fallbacks und manuelle Rettung existieren,
- Rollback ist vorbereitet,
- tatsächliches Verhalten wurde beobachtet.

## Gate A – Spezifikation

PASS nur wenn:

- Scope und Non-Goals klar,
- kritischer Nutzerfluss referenziert,
- Akzeptanzkriterien messbar,
- Daten-/Security-/Privacy-Auswirkung bewertet,
- Rollout und Rollback beschrieben.

## Gate B – Reproduktion/Baseline

PASS nur wenn:

- Bug oder Ist-Verhalten reproduzierbar,
- Test/Replay/Schritte gespeichert,
- Baseline-Metrik vorhanden,
- Ursache nicht nur geraten.

## Gate C – Implementierung

PASS nur wenn:

- kleiner, fokussierter Diff,
- kein unverbundener Refactor,
- Migration kompatibel,
- Idempotenz/Concurrency berücksichtigt,
- Telemetrie und Feature Flag vorhanden, falls riskant.

## Gate D – Unabhängiges Review

PASS nur wenn:

- Reviewer nicht Implementierer,
- Daten-/State-Invarianten geprüft,
- Fehlerpfade/Timeouts/Retries geprüft,
- Security-/Privacy-Fragen bewertet,
- keine Blocker offen.

## Gate E – Verifikation

PASS nur wenn relevante Ebenen tatsächlich grün:

- Unit
- Contract
- Integration
- E2E
- Dispatch Replay/Simulation
- Mobile Device/Background
- Performance/Failure Injection

Nicht jede Änderung benötigt jede Ebene, aber Auslassungen müssen begründet sein.

## Gate F – Betriebsfähigkeit

PASS nur wenn:

- Logs/Metriken/Trace/Audit vorhanden,
- Alert und Runbook existieren,
- Dashboard zeigt Fehlzustand,
- manueller Override möglich,
- Rollback getestet oder nachvollziehbar geprobt.

## Gate G – Shadow/Canary

Für Dispatch, Tracking, Notification und State-Migration:

- Shadow-/Canary-Daten vorhanden,
- Guardrails nicht verletzt,
- Diskrepanzen klassifiziert,
- Stop-/Rollback-Bedingungen definiert.

## Harte Release-Blocker

- offenes P0/P1,
- Duplicate aktive Assignment,
- Order kann verloren/unsichtbar hängen,
- fehlender sicherer Timeout-/Fallbackpfad,
- stale GPS wird als live dargestellt,
- Push ohne ACK kann Order unbegrenzt blockieren,
- keine manuelle Rettung,
- Secrets/PII-Leak,
- ungeprüfte destruktive Migration,
- kritischer Flow nur manuell „einmal ausprobiert“,
- Agent behauptet Tests ohne Artefakt.

## Release Scorecard

| Bereich | Gewicht |
|---|---:|
| Order-/Payment-Korrektheit | 20 |
| Assignment-/Dispatch-Korrektheit | 20 |
| Fahrer-App/Tracking | 15 |
| Notification/Eskalation | 10 |
| Kunden-/Dispatcher-UX | 10 |
| Testabdeckung kritischer Flows | 10 |
| Observability/Runbooks/Rollback | 10 |
| Security/Privacy | 5 |

Ein Score ersetzt keine harten Blocker. Bei Blocker ist das Ergebnis unabhängig vom Score `NO-GO`.

## Abschlussbericht

Der Gatekeeper liefert:

```text
Verdict: GO | LIMITED_GO | NO_GO
Release/Commit:
Scope:
Evidenz:
SLO/Guardrail-Vergleich:
offene Risiken:
Canary-Größe:
Stop-Kriterien:
Rollback:
verantwortliche menschliche Freigabe:
```
