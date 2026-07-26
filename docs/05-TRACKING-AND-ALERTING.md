# 05 – Fahrer-Tracking und Benachrichtigungs-/Alarmkette

## Ziel

Die Zentrale muss erkennen können, ob ein Fahrer wirklich aktiv, erreichbar und an einer plausiblen Position ist. Kunden sehen nur einen sicheren, geglätteten und für ihren Auftrag relevanten Ausschnitt. Eine Bestellzuweisung gilt erst dann als zugestellt, wenn die App sie aktiv bestätigt hat.

## Tracking-Payload

Jeder Punkt oder Batch enthält mindestens:

```text
driver_id
device_id
shift_id
timestamp_device
timestamp_monotonic/sequence
lat/lng
horizontal_accuracy
speed
heading
motion state
battery level
network state
app version
route_version
```

Der Server ergänzt `received_at` und prüft:

- Sequenzsprünge/Duplikate,
- Zeitabweichung,
- unmögliche Sprünge/Geschwindigkeit,
- Genauigkeit,
- Schicht-/Route-Zugehörigkeit,
- Geräte-/Token-Gültigkeit.

## Adaptive Frequenz

Startwerte, später mit realen Geräten kalibrieren:

| Zustand | Zielintervall |
|---|---:|
| aktive Navigation/Delivery, bewegt | 5–10 Sekunden |
| am Pickup/Stop, geringe Bewegung | 15–30 Sekunden |
| verfügbar, keine aktive Route | 30–60 Sekunden |
| Pause/Schicht beendet | keine präzise Dauerübertragung |

Die App batcht bei Offline-Verbindung und sendet nach Wiederkehr in Reihenfolge. Historische Punkte dürfen den aktuellen Standort nicht rückwärts überschreiben.

## Presence und Stale Detection

Separate Signale:

- GPS-Punkt,
- App-Heartbeat,
- Push-Token-Gültigkeit,
- WebSocket/Realtime-Status,
- letzte User-Interaktion.

Ein Fahrer ist nicht allein deshalb „online“, weil vor zehn Minuten ein GPS-Punkt kam.

Empfohlene UI:

```text
LIVE       7s alt, ±12m
DEGRADED  22s alt, ±85m
STALE      48s alt
OFFLINE    letzter Kontakt 6m
```

Stale-Fahrer werden für zeitkritische automatische Zuweisungen ausgeschlossen oder stark bestraft.

## Realtime-Auslieferung

- Tracking-Ingestion schreibt aktuelle Position und optional Historie.
- Realtime Gateway verteilt Delta-Updates per WebSocket/SSE.
- Bei Gateway-Ausfall fällt die UI auf Polling zurück.
- Karten-UI glättet Darstellung, behält aber Originalpunkte für Audit.
- Dispatcher sieht Alter, Genauigkeit, Route-Version und Connectivity.
- Kunde sieht Fahrer erst ab geschäftlich definiertem Zeitpunkt und nur bis Abschluss/kurzer Nachlauf.

## Push-/Alarmprinzip

Ein Provider-ACK bedeutet nur, dass der Provider die Nachricht angenommen hat. Die App sendet deshalb eigene Zustände:

```text
SENT_TO_PROVIDER
RECEIVED_BY_APP
DISPLAYED
ACKNOWLEDGED / DECLINED
```

### Empfohlene Eskalationskette

Konfigurierbares Beispiel:

```text
T+0s   High-priority Push mit kurzer TTL und assignment_id
T+5s   erneuter Push, falls kein RECEIVED_BY_APP
T+10s  In-App/OS-Benachrichtigung erneut; Ops-Warnung
T+15s  Lease ablaufen lassen und nächsten Fahrer prüfen
T+20s  echter automatisierter VoIP-/Telefonanruf als Fallback
T+30s  Dispatcher-Alarm und MANUAL_REVIEW, falls weiterhin ungeklärt
```

Die exakten Zeiten werden anhand realer Empfangs- und Annahmedaten kalibriert.

## Plattformstrategie

### Android

Während einer aktiv gestarteten Schicht:

- Location-Foreground-Service mit sichtbarer laufender Benachrichtigung,
- High-Priority-FCM nur für zeitkritische, sichtbare Offers,
- Notification Channel mit hoher Wichtigkeit, Sound/Vibration,
- kurzer TTL und eindeutiger Assignment-ID,
- App-Level-Receipt,
- WorkManager für Nacharbeiten, nicht für die sofortige Offer-Anzeige.

Eine Full-Screen-Intent-Lösung nicht als Standard einplanen. Moderne Android-Versionen beschränken sie stark auf echte Anruf-/Alarm-Use-Cases.

### iOS

- APNs/FCM mit normalen oder Time-Sensitive User Notifications,
- Background Location nur für den klar sichtbaren aktiven Schicht-/Liefer-Use-Case,
- In-App-Alarm, sobald die App aktiv ist,
- App-Level-Receipt und serverseitige Eskalation.

Critical Alerts benötigen eine besondere Apple-Berechtigung und dürfen nicht als sichere Grundannahme geplant werden. PushKit/VoIP Push ist für echte eingehende VoIP-Anrufe; normale Order-Offers darüber zu simulieren ist kein belastbares Design.

## UX des Offers

Der Offer-Screen zeigt sofort:

- Abholort,
- grobe Zielzone, nicht unnötig vollständige Kundendaten vor Annahme,
- Zusatzstrecke/-zeit,
- Anzahl Stops,
- Zeitfenster,
- Vergütung/Regel falls relevant,
- Countdown,
- Accept/Decline,
- Connectivity-/GPS-Warnung.

Akzeptieren muss idempotent sein. Doppeltippen oder verspätete Antwort darf keine doppelte Route erzeugen.

## Lokale Alarmierung

Ein tatsächlich „unendlich“ klingelnder Alarm ist betriebssystemübergreifend nicht garantiert. Daher:

- wiederholbare, kurze Benachrichtigungen,
- starke Vibration/Sound nach Nutzerfreigabe,
- In-App-Alarm bis Quittierung, solange die App aktiv ist,
- serverseitige Retry-/Lease-Logik,
- zweiter Kanal,
- automatische Neuvergabe.

Das System darf nie davon abhängen, dass ein einzelner Ton garantiert abgespielt wird.

## Token- und Gerätepflege

- Push-Token pro Installation und Nutzerbindung,
- Token-Rotation aktualisieren,
- Invalid-Token sofort markieren,
- Logout/Schichtende entkoppeln,
- mehrere Geräte klar regeln,
- Offer nur an das aktive, autorisierte Gerät,
- App-Version/Minimum-Version prüfen.

## Datenschutz und Sicherheit

- Tracking nur während klar definierter Schicht-/Lieferaktivität.
- Fahrer sieht deutlich, wann Tracking aktiv ist.
- Kundenlink ist signiert, auf einen Auftrag begrenzt und läuft ab.
- Lock-Screen-Push enthält keine unnötigen Adress-/Personendaten.
- Historische GPS-Aufbewahrung wird fachlich und rechtlich begründet.
- Rollenbasierter Zugriff und Audit für Dispatcher.
- Roh-Produktionsdaten nicht in Agenten-/LLM-Kontexte kopieren.

## Akzeptanztests

1. App im Vordergrund/Hintergrund/gesperrt.
2. Android Battery Saver/Doze.
3. iOS Focus/Muted und normale Berechtigungen.
4. Push-Token invalid.
5. Netzwerkwechsel WLAN/Mobil/Offline.
6. App gekillt oder Prozess neu gestartet.
7. verspäteter ACK nach Lease-Ablauf.
8. doppelte Push-Nachricht.
9. GPS springt/unpräzise.
10. Schicht endet während aktiver Delivery.
11. Realtime Gateway fällt aus.
12. VoIP-Fallback schlägt fehl.
13. Kunde öffnet abgelaufenen Tracking-Link.
14. Fahrer nutzt alte App-Version.
