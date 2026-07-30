# Task Packet: IOS-P0-OFFER-CONTRACT – Exakter iOS-Offer-Vertrag

## Status

`IMPLEMENTED`

## Severity und Flow

- Severity: `P0`
- Critical Flow ID: Fahrer erhält Angebot/Zuweisung und quittiert
- Owner/Implementierungsagent: Codex iOS implementation agent
- Pflichtreviewer: unabhängiger iOS-/Backend-Reviewer
- Pflichtprüfer: unabhängiger Release-/Device-Test-Agent

## Problem

Die native Hülle hält nur eine globale `currentBatchId`. Zwei Pushes können diese
überschreiben; CallKit-Antworten sind dadurch nicht unveränderlich an den
ursprünglichen Offer gebunden. Der VoIP-Token-Upload meldet Erfolg, ohne HTTP-
Status oder Netzwerkfehler zu prüfen, und verliert Retries nach Prozessende.

Die Zielarchitektur verlangt APNs-First. Bestehendes simuliertes VoIP darf in
diesem kompatiblen Slice nicht erweitert werden.

## Evidence/Baseline

- Reproduktionsschritte:
  1. Zwei Payloads mit verschiedenen `batch_id` kurz nacheinander zustellen.
  2. Ersten Call beantworten.
  3. Der bestehende globale Wert zeigt auf den zweiten Batch.
- fehlschlagender Test/Replay: Im Ausgangscode existiert keine UUID→Offer-
  Abbildung und kein testbares Parsing-/Retry-Modul.
- unabhängiges Review: NO_GO, weil die erste Implementierung Call→Offer nur im
  Speicher hielt, Bridge-Events bereits nach JavaScript-Transport löschte und
  Tokenrotation während eines laufenden Uploads nicht vollständig versöhnte.
- Logs/Trace/Metric: Token-Upload ruft `resume()` ohne Completion-Auswertung auf.
- betroffene Version/Umgebung: `origin/main`/`afc25f8`, TestFlight zuletzt
  `e5b042a`.
- Häufigkeit und Reichweite: Jede überlappende Notification und jeder
  Token-Upload bei Netzwerk-/Authstörung.
- Annahmen: Der bestehende Web-Client ignoriert unbekannte DOM-Custom-Events
  sicher. Backend-Endpunkte bleiben unverändert.

## Root-Cause-Hypothese

Offer-Identität und Call-Lifecycle wurden in globalen optionalen Variablen
modelliert. Token-Synchronisation ist ein Fire-and-forget Request statt eines
persistierten Zustandsautomaten.

## Scope

### In Scope

- unveränderliches Offer-Envelope mit `offer_id`, `batch_id` und
  `assignment_version`
- Mapping pro Call-UUID
- prozessfeste Call→Offer- und Bridge-Queue-Persistenz
- expliziter Web→Native-ACK mit Ablaufzeit statt Transport-ACK
- exakter WebView-Bridge-Event bei Receive/Open/Answer
- persistierter, statusgeprüfter VoIP-Token-Retry
- Feature-Flag für Legacy-VoIP-Offer-UI
- idempotente Registrierung und Archive-Prüfung des `mise-driver` URL-Schemes
- begrenztes Replay-Backoff und expliziter `bridge-ready`-Handshake
- pure Swift-Vertragstests
- Cross-Contract-Test: tatsächlich von Swift emittiertes JSON gegen die
  Top-Level-Validierung des Web-Bridge-Vertrags
- CI-Prüfungen für Entitlement, Payload-Helper und Bundle-Ressourcen

### Non-Goals

- Backend-Schema/RPC
- automatisches Accept im nativen Client
- neue oder stärkere VoIP-Nutzung
- Hintergrund-GPS
- GitHub-Push, TestFlight oder Produktion

### Erlaubte/erwartete Module

- `ios-resources/AppDelegate.swift`
- `ios-resources/OfferContract.swift`
- `ios-contract-tests/`
- `.github/workflows/ios-testflight.yml`
- `setup-mac.sh`
- `scripts/ensure_url_scheme.py`
- Dokumentation dieses Task Packets

## Akzeptanzkriterien

1. Given zwei Offers, when der erste UUID beantwortet wird, then enthält das
   Bridge-Event ausschließlich die IDs des ersten Offers.
2. Invarianten: Kein „newest pending“-Fallback im nativen Vertrag; derselbe
   Envelope wird für Receive/Open/Answer verwendet.
3. Performance-/Latenzbudget: Parsing und Bridge-Aufbereitung synchron <10 ms.
4. Fehler-/Fallbackpfad: Fehlende neue Felder werden kompatibel und
   deterministisch aus `batch_id` abgeleitet; Token-Retry bleibt persistiert.
5. UX/Accessibility: Dieser Slice verändert keine sichtbare UI.
6. Security/Privacy: Keine Tokenwerte oder Kundendaten in Logs/Beacons.

## Implementierungsplan

1. Pure `OfferEnvelope`-, Registry-, Bridge-Queue- und Retry-Helfer mit Tests.
2. AppDelegate auf persistentes UUID-Mapping und DOM-Custom-Event umstellen.
3. Bridge erst nach explizitem Web-ACK löschen; ohne ACK bis TTL erneut senden.
4. Persistierten Token-Uploader mit HTTP-Auswertung, Rotation und Backoff
   integrieren.
5. Legacy-VoIP über Info.plist-Flag kapseln; Default bleibt kompatibel.
6. CI prüft Helper, Source-Phase, Entitlement und Archive-Ressourcen hart.

## Testplan

- Unit: Payload-Normalisierung inklusive numerischer Assignment-Version,
  UUID-Isolation und Wiederherstellung,
  Bridge-Dedupe/ACK/TTL/Replay-Backoff, Token-Rotations-/Retry-Policy,
  JS-Serialisierung und idempotente Plist-Scheme-Konfiguration.
- Contract: Eventname und Detailfelder stabil.
- Integration: Swift-Helper kompilieren/testen; App-Archive in CI.
- E2E: durch separaten TestFlight-/Device-Test-Agenten.
- Mobile: zwei überlappende Offers, Tap, Answer, Prozessneustart.
- Dispatch Replay: nicht in diesem Slice.
- Failure Injection: 401, 500, Timeout, Prozessende vor Retry.
- Load: nicht erforderlich; Mapping ist auf aktive Calls begrenzt.

## Observability

- neue/geänderte Metrik: keine serverseitige Metrik in diesem Slice.
- strukturierter Log/Audit: Beacon enthält nur Stage und nicht-sensitive IDs.
- Trace: Offer-Event enthält `offer_id` und `assignment_version`.
- Alert: keiner.
- Dashboard/Runbook: Device-Matrix im Handoff.

## Rollout

- Flag/Segment: `MiseLegacyVoipOffersEnabled`.
- Shadow/Canary: APNs-First TestFlight-Canary durch Release-Agent.
- Guardrails: Kein Upload ohne grüne Contract- und Archive-Prüfung.
- Stop-Kriterien: falsche Offer-ID, fehlender Alarm, Token nicht registriert.
- Beobachtungsfenster: mindestens eine reale Schicht im internen Test.

## Rollback

- Code: AppDelegate/Helper auf vorherigen Build zurücksetzen.
- Daten: keine Migration.
- In-Flight Orders: Web-Flow bleibt kanonisch.
- alte/neue Clients: Payload-Fallback unterstützt alte `batch_id`-Payloads.
- Owner: Release-Verantwortlicher.

## Handoff-Evidenz

- Branch/Worktree: `codex/apns-offer-contract`,
  `/Users/eule/mise-driver-app-push`
- Commit: keiner
- geänderte Dateien: `ios-resources/AppDelegate.swift`,
  `ios-resources/OfferContract.swift`, `ios-contract-tests/`,
  `.github/workflows/ios-testflight.yml`, `setup-mac.sh`, `README.md`,
  `scripts/ensure_url_scheme.py`, dieses Task Packet
- ausgeführte Befehle:
  - `bash ios-contract-tests/run.sh`
  - `swiftc -frontend -parse ios-resources/AppDelegate.swift ios-resources/OfferContract.swift`
  - Ruby-YAML-Parse des Workflows
  - `bash -n setup-mac.sh`
  - `git diff --check`
- Resultate: Contract-Tests PASS einschließlich Prozesswiederherstellung,
  Bridge-Dedupe/ACK/TTL/gebundenem Replay, Plist-Scheme und Tokenrotation;
  Swift-emittiertes Fixture erfüllt den Web-Top-Level-Vertrag; Swift-Parse PASS,
  Workflow-YAML PASS, Shell-Syntax PASS, Diff-Check PASS.
- nicht ausführbar: Voller Xcode-/CocoaPods-Build, weil auf dem Host nur
  Command Line Tools und keine Xcode-App installiert ist. `npx cap add ios`
  erzeugte das Projekt, CocoaPods brach an der fehlenden Xcode-Toolchain ab.
- offene Risiken: Backend-App-ACK und atomarer Accept bleiben Folgeslice.
  Ein unabhängiger Reviewer muss den nativen Build und die WebView-Bridge auf
  einem Xcode-/TestFlight-Gerät prüfen.
