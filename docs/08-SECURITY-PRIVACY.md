# 08 – Sicherheit und Datenschutz

## Schutzobjekte

- Kundenidentität, Adresse, Telefon und Bestellinhalt
- Fahreridentität, GPS und Arbeits-/Schichtdaten
- Zahlungsstatus und Provider-Referenzen
- Authentifizierungs- und Push-Token
- Dispatch-Regeln und interne Betriebsdaten
- Produktionszugänge, Secrets und Backups

## Grundregeln

- Least Privilege und rollenbasierter Zugriff.
- Kurzlebige Access Tokens und rotierbare Refresh-/Device Tokens.
- Jede sensible Ops-Aktion auditiert.
- Verschlüsselung in Transit und at Rest.
- Geheimnisse nur im Secret Manager, nicht in Repo/Logs/Prompts.
- Datenminimierung, Zweckbindung und definierte Aufbewahrungsfristen.
- Tracking nur für klaren betrieblichen Zweck und sichtbaren aktiven Zeitraum.
- Kunden-Tracking-Link ist signiert, scoped und zeitlich begrenzt.
- Push-Lockscreen enthält keine unnötigen personenbezogenen Daten.
- Export-/Supportfunktionen werden besonders berechtigt und protokolliert.

## Authentifizierung und Autorisierung

### Driver App

- Gerät/Installation registrieren,
- Nutzer und aktives Gerät binden,
- Token-Rotation und Remote-Revoke,
- Schichtstart serverseitig prüfen,
- Assignment-ACK gegen `assignment_id`, Version und Fahrer validieren,
- keine vertraulichen Kundendetails vor berechtigtem Zeitpunkt.

### Dispatcher

Rollen trennen:

- Viewer
- Dispatcher
- Supervisor
- Support
- Admin
- Security/Audit

Manuelle Reassignments, Holding-Override, Kundendatenexport und Rollenänderungen benötigen stärkere Rechte.

### Customer Tracking

- keine erratbaren IDs,
- Token an genau eine Order gebunden,
- Ablauf und Revoke,
- Rate Limit,
- nach Abschluss nur minimaler Status, keine dauerhafte Liveposition.

## API-Sicherheit

- Schema-Validierung,
- Größen-/Rate-Limits,
- Idempotency Keys,
- Replay-Schutz wo nötig,
- sichere Fehler ohne interne Details,
- SSRF-/Injection-Schutz für externe URLs/Provider,
- Webhook-Signatur und Zeitfenster,
- Allowlist für Redirects/Callbacks,
- keine vertraulichen Daten in Query Strings.

## Standortdaten

- nur notwendige Genauigkeit/Frequenz,
- aktive Tracking-Anzeige für Fahrer,
- klare Trennung Current Position vs History,
- History-Retention und Zugriff begründen,
- Supportzugriff minimieren,
- Audit und Export-/Löschprozesse,
- keine private Nachverfolgung außerhalb Schicht/Delivery.

Rechtliche Details müssen für Einsatzland, Beschäftigungsmodell und Betriebsvereinbarungen geprüft werden.

## Agenten-/LLM-Schutz

In Modellkontexte dürfen nicht:

- `.env` und Secrets,
- private Schlüssel,
- produktive Datenbank-Dumps,
- vollständige Roh-Produktionslogs,
- Kundenlisten/Adressen/Telefonnummern,
- langfristige GPS-Tracks,
- Zahlungsdaten.

Stattdessen:

- synthetische Testdaten,
- redigierte Logausschnitte,
- pseudonymisierte IDs,
- minimale Reproduktion,
- lokale Tools für geheimhaltungsbedürftige Analysen.

Projekt-Memory speichert nur technische Muster, Entscheidungen und Testwissen, keine personenbezogenen Rohdaten.

### Fable-5-Aufbewahrungshinweis (Stand 23. Juli 2026)

Für Fable 5 gelten zum Erstellungszeitpunkt besondere Aufbewahrungsbedingungen: Modellverkehr erfordert eine 30-tägige Retention und ist daher nicht als Zero-Data-Retention-Pfad zu behandeln. Vor Aktivierung im Unternehmens-Workspace die dann aktuellen Vertrags-, Workspace- und Provider-Einstellungen prüfen. Bis dahin ausschließlich synthetische, redigierte oder pseudonymisierte Daten verwenden; diese Regel gilt auch dann, wenn ein anderer Provider die Daten in seiner eigenen Cloud hält.

## Threat-Szenarien

- Fahrer manipuliert ACK/Route/GPS.
- Angreifer errät Kunden-Tracking-Link.
- gestohlener Dispatcher-Account.
- doppelte/replayed Payment Webhooks.
- Push-Token an falschen Nutzer gebunden.
- alter Client überschreibt neue Route.
- Insider exportiert GPS-Historie.
- Dependency-/Supply-Chain-Angriff.
- Agent liest oder committed Secret.
- Log/Trace enthält PII.

Jedes Szenario braucht Prävention, Detektion und Response.

## Release-Blocker

- bekannte kritische Auth-Bypass-Lücke,
- unverschlüsselte sensible Daten,
- öffentliche/erratbare Tracking-Links,
- Secrets im Repo/Build-Artefakt,
- nicht autorisierte GPS-Ansicht,
- keine Auditspur für Dispatcher-Overrides,
- ungeprüfte Migration mit Datenverlustpotenzial,
- kritische Dependency-Lücke ohne Mitigation.
