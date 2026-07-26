# 03 – Zustandsmaschinen und Invarianten

## Order State Machine

```text
RECEIVED
  -> VALIDATING
  -> CONFIRMED
  -> PREPARING
  -> READY
  -> HELD_FOR_BUNDLE
  -> OFFERING
  -> ASSIGNED
  -> TO_PICKUP
  -> PICKED_UP
  -> EN_ROUTE
  -> DELIVERED
```

Ausnahme-/Terminalzustände:

```text
PAYMENT_FAILED
CANCELED
REJECTED
DELIVERY_FAILED
MANUAL_REVIEW
```

### Regeln

- `HELD_FOR_BUNDLE` ist nur erlaubt, wenn ein `latest_safe_departure_at` existiert.
- `OFFERING` benötigt mindestens eine aktive Assignment-Lease.
- `ASSIGNED` benötigt eine bestätigte oder geschäftlich definierte Hard-Assignment-Quittierung.
- `PICKED_UP` ist nicht rückwärts in `READY` zu setzen. Korrekturen erfolgen über auditierte Kompensationsereignisse.
- `DELIVERED` ist terminal.
- Zahlung und Order-State dürfen nicht unabhängig widersprüchlich fortgeschrieben werden.

## Driver State Machine

```text
OFFLINE
  -> STARTING_SHIFT
  -> AVAILABLE
  -> RESERVED
  -> OFFERED
  -> ASSIGNED
  -> TO_PICKUP
  -> AT_PICKUP
  -> DELIVERING
  -> AVAILABLE
  -> ENDING_SHIFT
  -> OFFLINE
```

Neben-/Ausnahmezustände:

```text
PAUSED
STALE
NO_CONNECTIVITY
EMERGENCY
SUSPENDED
```

### Regeln

- `AVAILABLE` erfordert gültige Schicht, aktuelle Berechtigung und ausreichend frisches Presence-Signal.
- `STALE` ist kein rein visueller Marker; der Fahrer wird aus risikoreichen automatischen Entscheidungen entfernt.
- `PAUSED` und `OFFLINE` dürfen keine neuen Offers erhalten.
- Ein Fahrer kann mehrere Orders in einer Route führen, aber nur eine kanonische aktive Route-Version besitzen.
- Schichtende darf keine bereits abgeholte Bestellung verwaisen lassen.

## Assignment State Machine

```text
PROPOSED
  -> OFFERED
  -> RECEIVED_BY_DEVICE
  -> ACKNOWLEDGED
  -> ACTIVE
  -> COMPLETED
```

Alternative Übergänge:

```text
OFFERED -> EXPIRED
OFFERED -> DECLINED
OFFERED -> DELIVERY_FAILED
ACKNOWLEDGED -> REVOKED_BEFORE_PICKUP
ACTIVE -> EXCEPTION
```

### Regeln

- Jede Offer hat kurze TTL und eine eindeutige `assignment_id`.
- App-ACKs sind idempotent und enthalten die Assignment-Version.
- Ein später ACK für eine abgelaufene Lease darf die aktuelle Assignment nicht überschreiben.
- Revoke nach Pickup ist nur als Exception mit Dispatcherentscheidung möglich.
- Neue Offers dürfen nicht auf einer veralteten Fahrerroute berechnet werden.

## Tracking State

```text
UNKNOWN -> FRESH -> DEGRADED -> STALE -> OFFLINE
```

Beispielhafte Einstufung, später anhand realer Geräte kalibrieren:

- `FRESH`: letzte valide Position <= 15 Sekunden
- `DEGRADED`: 15–30 Sekunden oder geringe Genauigkeit
- `STALE`: > 30 Sekunden während aktiver Zustellung
- `OFFLINE`: kein Heartbeat/Netz oder Schicht beendet

Die UI zeigt Alter und Genauigkeit. Sie darf eine stale Position nicht animiert als live darstellen.

## Notification Attempt State

```text
CREATED -> SENT_TO_PROVIDER -> RECEIVED_BY_APP -> DISPLAYED -> ACKNOWLEDGED
```

Fehlerpfade:

```text
PROVIDER_REJECTED
TOKEN_INVALID
TTL_EXPIRED
NO_APP_RECEIPT
USER_DECLINED
ESCALATED_TO_VOIP
```

`SENT_TO_PROVIDER` ist nicht gleich `RECEIVED_BY_APP`.

## Globale Invarianten

1. Pro Order maximal eine aktive Assignment-Lease.
2. Pro Fahrer genau eine aktive Route-Version.
3. Kein State-Transition ohne Actor, Zeit, Kausalität und Idempotency-Key.
4. Keine Kunden-ETA aus stale GPS ohne sichtbaren Unsicherheitsaufschlag.
5. Kein Dispatch-Holding über `latest_safe_departure_at`.
6. Kein Offer an Fahrer mit abgelaufener Schicht oder stale Presence.
7. Keine automatische Route-Änderung nach Pickup, die Lieferzeit-/Qualitätsgrenzen verletzt.
8. Keine stille Löschung von Ereignissen; Korrekturen sind neue auditierte Ereignisse.
