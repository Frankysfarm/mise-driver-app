# Franky's Fahrer — Apple-Einrichtung, 4. Oktober 2026

## Nachgewiesener Stand

- Apple-App-ID: `6818794309`
- Bundle-ID: `de.frankysfarm.driver`
- SKU: `frankys-fahrer-ios-20261003`
- Interne Testgruppe: `Frankys Installationstest`
- Gruppe: `0ba6f2e5-fc45-4b05-97a1-476ae2de70e9`
- Ein bestehender interner Tester zugeordnet, automatische Verteilung aus.
- Apple zeigt **0 Builds / No Builds Available**.
- Die Meldung „Unable to Add for Review“ betrifft die öffentliche App-Store-
  Einreichung von Version 1.0, nicht den internen TestFlight-Installationstest.

## Nächster Installationstest

1. Bestehenden GitHub-Zugang erneuern; keine Tokens in Dateien oder Chat ablegen.
2. Passendes Distributionsprofil für die neue explizite Bundle-ID einrichten.
   Keine Push-Berechtigung für diese bewusst isolierte Installationsprobe.
3. `FRANKYS_APP_STORE_APP_ID=6818794309` und das eigene Profil über die
   vorgesehenen geschützten CI-Einstellungen bereitstellen.
4. Geprüften Feature-Branch übertragen und Variante `frankys` bauen. Native
   Tests, Signierung, Apple-Verarbeitung und Testerzuordnung nachweisen.
5. Auf dem tatsächlichen iPhone installieren und starten. Das Ergebnis grenzt
   die Ursache ein; ein erfolgreicher Upload allein belegt keine Installation.

## TestFlight-Text für die Installationsprobe

### Beschreibung

Franky's Fahrer – Installationstest. Diese Testversion prüft, ob sich die App
auf deinem Gerät installieren und öffnen lässt. Nach dem Start werden Version
und Build-Nummer angezeigt. Lieferaufträge, Anmeldung, Standortübertragung und
Benachrichtigungen sind in dieser Version deaktiviert.

### Was getestet werden soll

Installiere die App über TestFlight und öffne sie. Prüfe, ob „App gestartet“
sowie Version und Build-Nummer erscheinen. Bei Problemen bitte den genauen
Fehlertext, das iPhone-Modell und die iOS-Version an die Testbetreuung melden.

## Öffentliche App-Store-Einreichung der vollständigen Fahrer-App

Noch nicht einreichen: Die vorbereitete neue Variante ist eine reine
Installationsprobe. Die spätere vollständige Fahrer-App braucht eigene,
zum tatsächlichen Build passende Metadaten und Nachweise.

| Apple-Anforderung | Aktuelle Lücke / benötigter Nachweis |
| --- | --- |
| Build | Für diese App noch keiner hochgeladen. |
| Deutsche Beschreibung / Keywords | Erst anhand des vollständigen, getesteten Funktionsumfangs veröffentlichen. |
| Support-URL | Öffentliche, erreichbare Supportseite für Fahrer prüfen bzw. bereitstellen. Eine Anmeldeseite ersetzt sie nicht. |
| Datenschutz-URL | Öffentliche Erklärung muss die tatsächlichen Fahrer-Datenflüsse abdecken. Interne Architekturunterlagen genügen nicht. |
| App-Privacy-Fragebogen | Datenflüsse einschließlich eingebundener Dienste vollständig prüfen. Angaben der Offline-Probe nicht unverändert übernehmen. |
| Alterseinstufung | Fragebogen anhand aller tatsächlich zugänglichen Inhalte und Funktionen beantworten. |
| Inhaltsrechte | Tatsächliche Rechte an verwendeten Marken, Bildern und Inhalten bestätigen; nicht aus dem Vorhandensein von Dateien ableiten. |
| Screenshots / Review-Zugang | Screenshots und gegebenenfalls einen nutzbaren, begrenzten Review-Zugang für die finale Version bereitstellen. |

Für die vollständige App sind insbesondere Fahrerkennung, genaue Standortdaten,
Hintergrundbetrieb, Schicht-/Lieferaktivität, Geräte-/Push-Kennung, Kundenadresse
und Telefonnummer sowie gegebenenfalls Fotos und Diagnosedaten zu prüfen.
Nicht jede theoretische Kategorie ist automatisch als erhoben anzukreuzen;
maßgeblich ist die tatsächliche Implementierung einschließlich Dienstleister.

### Vorhandene öffentliche Seiten geprüft

- `https://mise-gastro.de/driver/privacy`: HTTP 200, Titel „Datenschutz · Mise
  Driver“, keine Weiterleitung. Quellseite beschreibt die operative Mise-App
  mit Fahrerprofil, Standortdaten und Lieferhistorie (Stand Mai 2026). Vor einer
  Übernahme für Franky's Fahrer müssen Betreiberbezug und tatsächliche
  Datenverarbeitung übereinstimmen; diese Prüfung ist noch offen.
- `https://mise-gastro.de/impressum`: HTTP 200, Titel „Impressum · Mise“.
  Allgemeine Kontaktdaten ersetzen keine auf die Fahrer-App abgestimmte Hilfe.
- Eine gesonderte öffentliche Fahrer-Supportseite wurde bei der gezielten
  Quellprüfung nicht gefunden. Keine ungeprüfte URL bei Apple eingetragen.

## Offizielle Apple-Quellen

- [Interne TestFlight-Tester hinzufügen](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
- [App-Datenschutz verwalten](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

Keine öffentliche Review-Einreichung durchgeführt. Kein neuer TestFlight-Build
und keine erfolgreiche iPhone-Installation nachgewiesen.
