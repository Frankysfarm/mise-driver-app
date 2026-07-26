# Dispatch Decision Review

## Identität

- decision_id:
- algorithm_version:
- configuration_version:
- snapshot_id:
- feature_flag_variant:
- Zeitpunkt UTC:

## Input

- Order(s):
- Kandidatenfahrer:
- GPS-Freshness/Genauigkeit:
- Route-/Traffic-Matrix:
- Zeitfenster/Quality:
- Latest Safe Departure:
- Prep-Unsicherheit:

## Kandidaten

| Driver | Feasible | Reason Codes | Delta Time | Late Risk | Churn | Score |
|---|---|---|---:|---:|---:|---:|

## Entscheidung

- gewählt:
- Hold/Offer/Manual:
- Score-Aufschlüsselung:
- Fallback benutzt:
- erwartete Auswirkung:

## Tatsächliches Ergebnis

- ACK/Decline/Expire:
- Pickup:
- Delivery:
- tatsächliche ETA-Abweichung:
- Kilometer/Kosten:
- Incident/Override:

## Bewertung

`GOOD | ACCEPTABLE | BAD | UNKNOWN`

- Begründung:
- neues Eval-Szenario nötig:
- Gewicht/Constraint/Forecast ändern:
