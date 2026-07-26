# 04 – Dispatch Engine Spezifikation

## Ziel

Der Dispatch soll die Gesamtkosten und Leer-/Umwegkilometer reduzieren, ohne Kundenzusagen, Lebensmittelqualität, Fahrerfähigkeit oder Systemstabilität zu verletzen. Er arbeitet als **dynamisches Vehicle-Routing-System mit Rolling Horizon**: Jede relevante Zustandsänderung kann eine neue Berechnung auslösen, aber bereits zugesagte Routen werden durch Stabilitätsregeln geschützt.

## Nicht-Ziele

- keine autonome Live-Anpassung von Gewichten,
- keine unbegründete Wartezeit nur in Hoffnung auf spätere Orders,
- keine Maximierung von Bündelquote auf Kosten verspäteter Kunden,
- keine mathematische „Optimalität“ ohne harte Laufzeitgrenze,
- kein Ersatz für Preis-/Gebietsregeln bei strukturell unprofitablen Fernbestellungen.

## Eingangsdaten

### Order

```text
order_id
pickup_location
dropoff_location
created_at
ready_at_estimate
ready_at_confidence
promised_window
service_times
size/weight/temperature class
priority
customer constraints
latest_safe_departure_at
zone
revenue/contribution estimate (optional, getrennt geschützt)
```

### Driver

```text
driver_id
current_position + accuracy + age
availability state
vehicle type/capacity
active route + route version
shift end
current load
skills/zone permissions
battery/connectivity health
recent acceptance/decline state
```

### Environment

```text
travel-time matrix + timestamp
traffic profile
store/depot queue
weather/incident flags if vorhanden
feature flags
algorithm version
zone configuration
historical demand forecast (optional)
```

## Harte Constraints

Eine Kandidatenroute ist unzulässig, wenn mindestens eine Bedingung verletzt ist:

- Pickup vor Drop-off
- Kapazität/Fahrzeugtyp
- Kunden-Zeitfenster
- maximaler Transport-/Warmhaltezeitraum
- Schichtende und gesetzte Betriebsregeln
- maximale Zahl aktiver Stops
- Fahrerstatus/Presence nicht geeignet
- Order nicht rechtzeitig abholbar
- maximale Umweggrenze für bereits abgeholte Orders
- Zone oder Berechtigung nicht zulässig
- Route basiert auf veralteter Route-Version
- kein ausreichender Zeitpuffer bei unsicherer ETA

Harte Constraints werden nicht durch Score-Gewichte „wegoptimiert“.

## Rolling-Horizon-Ablauf

Auslöser:

- neue/aktualisierte Bestellung,
- Order wird bereit,
- Fahrer wird verfügbar/stale/offline,
- GPS-/Traffic-Änderung oberhalb eines Schwellwerts,
- Offer abgelehnt/abgelaufen,
- Pickup/Delivery bestätigt,
- Prep-Delay,
- Dispatcher-Override,
- periodischer Sicherheitslauf.

Ablauf:

```text
1. konsistenten Snapshot lesen
2. unzulässige Fahrer/Orders filtern
3. machbare Einfügungen in bestehende Routen erzeugen
4. Kosten und Risiko jeder Einfügung berechnen
5. Remote-Hold-Entscheidung prüfen
6. Entscheidung mit Versionsprüfung atomar reservieren
7. Offer/Assignment mit TTL erzeugen
8. Benachrichtigung senden
9. App-ACK oder Ablauf verarbeiten
10. Entscheidung und Score auditieren
```

## Kandidatengenerierung

Nicht nur „nächster Fahrer“. Für jeden zulässigen Fahrer werden Pickup und Drop-off an allen sinnvollen Positionen der Route eingefügt. Kandidaten mit offensichtlicher Verletzung werden früh verworfen.

Zur Begrenzung der Laufzeit:

- räumliche/zeitliche Vorfilterung,
- Top-K Fahrer nach grober Lower-Bound-Kosten,
- maximale Rechenzeit,
- Wiederverwendung frischer Distanzmatrizen,
- deterministischer Fallback.

## Zielfunktion

Niedriger ist besser:

```text
J =
  w_drive       * zusätzliche Fahrzeit
+ w_distance    * zusätzliche Distanz
+ w_late        * erwartete Verspätungsminuten
+ w_late_risk   * P(verspätet) bzw. p90-Risiko
+ w_pickup_wait * erwartete Fahrerwartezeit am Pickup
+ w_food        * Transport-/Qualitätsrisiko
+ w_detour      * Umweg für bereits zugesagte Orders
+ w_overtime    * Schichtüberschreitung
+ w_churn       * Änderung einer bereits kommunizierten Route
+ w_stale       * GPS-/Datenunsicherheit
+ w_imbalance   * Belastungsungleichgewicht
- w_age         * Orderalter/Priorität
- w_shared      * gemeinsam genutzte Kilometer
- w_corridor    * robuste Bündelsynergie
```

Jede Entscheidung speichert die Score-Komponenten. So wird sichtbar, warum ein Fahrer gewählt wurde.

### Reihenfolge der Ziele

1. harte Machbarkeit,
2. keine kritische Verspätung/Qualitätsverletzung,
3. Stabilität bereits zugesagter Routen,
4. Gesamtkosten und Kilometer,
5. Auslastung/Fairness.

Fairness ist wichtig, darf aber keinen unpünktlichen oder unzulässigen Plan erzwingen.

## Fernbestellungen und intelligentes Warten

Ein fester Wert wie „immer fünf Minuten warten“ ist nicht robust. Jede Order erhält ein dynamisches spätestes sicheres Abfahrtsdatum:

```text
latest_safe_departure_at =
  promised_latest
  - p90(travel_time_to_customer)
  - pickup_and_handover_time
  - operational_safety_buffer
```

Die Order darf höchstens bis

```text
hold_deadline =
  min(
    latest_safe_departure_at,
    created_at + zone_max_hold,
    quality_deadline
  )
```

gehalten werden.

### Entscheidung: warten oder senden

Alle paar Sekunden/Event neu bewerten:

```text
expected_bundle_value =
  P(passende Order vor hold_deadline)
  * erwartete gemeinsam genutzte Kilometer/Kosten

delay_cost =
  zusätzliche Kundewartezeit
  + höheres Verspätungs-/Qualitätsrisiko
  + geringere zukünftige Fahreroptionen
```

Nur warten, wenn:

```text
expected_bundle_value > delay_cost + safety_margin
```

Sofort senden, wenn:

- `latest_safe_departure_at` näherrückt,
- keine robuste Fahreroption später verbleibt,
- ETA-/Prep-Unsicherheit steigt,
- Quality Deadline gefährdet ist,
- Fahrerangebot/Verfügbarkeit voraussichtlich schlechter wird,
- Dispatcher es erzwingt.

### Korridor-Matching

„Auf dem Weg“ wird über reale Routenteilung bewertet, nicht nur Luftlinie:

- Anteil gemeinsam genutzter Strecke,
- Winkel/Korridor vom Pickup,
- zusätzliche Minuten je Stop,
- Zeitfensterüberlappung,
- Reihenfolge und Quality-Limit,
- Rückweg/Zone,
- aktuelle Verkehrslage.

### Geplante Außenrouten

Bei regelmäßigem Ferngebiet kann eine separate Betriebsstrategie günstiger sein:

- breitere zugesagte Zeitfenster,
- feste Dispatch-Wellen,
- Mindestbestellwert oder zonenspezifische Gebühr,
- definierte Übergabe-/Hub-Punkte,
- dedizierte Fahrerrotation,
- Vorbestellung/Slots.

Der Optimierer soll keine dauerhaft negative Unit Economics verstecken.

## Offer, Reserve und ACK

Empfohlener Mechanismus:

1. Gewinner atomar als kurze Reservation markieren.
2. Assignment-Offer mit 15–20 Sekunden TTL senden; Wert konfigurierbar.
3. App meldet `RECEIVED_BY_APP`.
4. Fahrer akzeptiert/Hard-Assignment wird quittiert.
5. Bei Decline/Timeout Lease auslaufen lassen.
6. Nächsten Kandidaten mit aktuellem Snapshot wählen.
7. Nach wiederholtem Scheitern Dispatcher und VoIP eskalieren.

Kein Broadcast ohne serverseitige Winner-Reservation; sonst entstehen Race Conditions und doppelte Annahmen.

## Route-Stabilität

Neuberechnung ist nicht gleich ständiges Umsortieren.

- Nach Fahrer-ACK hohe Churn-Penalty.
- Nach Pickup Route nur bei Ausnahme oder deutlichem, sicherem Gewinn ändern.
- Bereits kommunizierte ETA nur bei relevanter Abweichung aktualisieren.
- Fahrer-App erhält monotone `route_version`; veraltete Updates werden verworfen.
- Jede Reassignment-Entscheidung enthält einen Reason Code.

## Fallback-Kaskade

```text
Primary: begrenzter Optimierer / OR-basierte Suche
  -> Fallback A: beste machbare Insertion
  -> Fallback B: nächster zulässiger Fahrer mit konservativer ETA
  -> Fallback C: MANUAL_REVIEW
```

Timeout oder Drittanbieterausfall darf keine Order aus dem System verschwinden lassen.

## Pseudocode

```python
def dispatch(snapshot, now):
    orders = eligible_unassigned_orders(snapshot, now)
    drivers = eligible_drivers(snapshot, now)

    for order in priority_order(orders):
        candidates = feasible_insertions(order, drivers, snapshot)

        if not candidates:
            route_to_manual_or_scheduled(order, reason="NO_FEASIBLE_CANDIDATE")
            continue

        best = min(candidates, key=lambda c: score(c, snapshot))

        if should_hold_for_bundle(order, best, snapshot, now):
            persist_hold(
                order_id=order.id,
                until=compute_hold_deadline(order, snapshot),
                reason_codes=["EXPECTED_CORRIDOR_BUNDLE"]
            )
            continue

        decision = reserve_atomically(
            order=order,
            driver=best.driver,
            expected_route_version=best.route_version,
            score_breakdown=best.score_breakdown,
            algorithm_version=ALGORITHM_VERSION
        )

        if decision.conflict:
            enqueue_recompute(order.id)
        else:
            create_offer(decision, ttl_seconds=CONFIG.offer_ttl)
```

## Audit-Record

Jede Entscheidung speichert:

- Input-Snapshot-ID,
- Kandidatenanzahl,
- verworfene Kandidaten und Reason Codes,
- Gewinner und Score-Aufschlüsselung,
- relevante ETA-/Matrixversion,
- Algorithmus-/Konfigurationsversion,
- Laufzeit,
- Feature-Flag-Variante,
- späteres Ergebnis: accepted, expired, late, delivered.

## Dispatch-Evaluation

Vor Live-Nutzung:

1. historische Events deterministisch replayen,
2. Ist-Algorithmus und Kandidat mit identischem Input vergleichen,
3. synthetische Randfälle aus `evals/scenarios.yaml` ausführen,
4. Rechenzeit und Fallbackrate messen,
5. Shadow Mode ohne Einfluss auf echte Assignments,
6. Diskrepanzen durch Menschen/Agenten klassifizieren,
7. Canary auf begrenzte Zone/Fahrergruppe,
8. nur bei bestandenen Guardrails ausweiten.

## Guardrail-Metriken

Eine Optimierung darf nicht freigegeben werden, wenn sie eine harte Guardrail verschlechtert:

- On-time-Quote und p90 Verspätung
- Quality-/maximale Transportzeit
- unzugewiesene Orderzeit
- Assignment-Churn
- Rechenzeit/Fallbackrate
- doppelte/inkonsistente Zuweisungen
- Fahrerwartezeit am Pickup
- Kundenstorno nach Bestätigung

Sekundäre Optimierungsmetriken:

- Kilometer/Order
- Kosten/Order
- Bündelquote
- Fahrer-Auslastung
- Leerfahrt
- Fairness/Belastungsverteilung
