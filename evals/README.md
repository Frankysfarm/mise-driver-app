# Dispatch- und Reliability-Evaluations

`scenarios.yaml` ist der minimale Golden-Szenariensatz. Der vorhandene Stack soll einen Runner bereitstellen, der jeden Fall deterministisch ausführt und maschinenlesbare Resultate erzeugt.

## Anforderungen an den Runner

- fester Seed und kontrollierte Uhr,
- identischer Input für Baseline und Kandidat,
- algorithmus- und konfigurationsversionierte Ausgabe,
- harte Invarianten zuerst,
- Metriken nach `dispatch-scorecard.schema.json`,
- reproduzierbare Failure Injection,
- keine Roh-PII.

## Empfohlene CLI

```text
dispatch-eval replay --dataset <id> --algorithm <version> --output scorecard.json
dispatch-eval scenarios --file evals/scenarios.yaml --algorithm <version>
dispatch-eval compare --baseline <scorecard> --candidate <scorecard>
```

## Promotion

- harte Invariante verletzt: `REJECT`
- Guardrail unbekannt: höchstens `KEEP_IN_SHADOW`
- Guardrails bestanden, ausreichende Stichprobe: `PROMOTE_TO_CANARY`
- Kostenverbesserung allein reicht nicht.
