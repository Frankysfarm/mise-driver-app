# Apple-Supportentwurf: Mise Driver App lässt sich aus TestFlight nicht installieren

Status: vorbereitet, **noch nicht an Apple gesendet**.

## Betreff
TestFlight: Zwei verarbeitete interne Builds nicht installierbar – App nicht verfügbar

## Nachricht
Guten Tag,

unsere vorhandene iOS-App „Mise Driver App“ lässt sich auf dem iPhone eines
bestehenden internen Testers nicht aus TestFlight installieren. Die angezeigte
Meldung lautet sinngemäß: „Die angeforderte App ist nicht verfügbar oder
existiert nicht.“ Der Nutzer bestätigt dieselbe Meldung auch nach einem
vollständigen erneuten Build und Upload.

Betroffene App:
- Apple App ID: 6766271119
- Bundle ID: app.mise.driver
- Developer Team ID: T82KC2CU9V
- App-Version: 1.0.0
- Betroffene Builds: 202610022143 und 202610022210
- Neuester Apple Build ID: 5008ba94-e958-445c-b1f1-d8446a1a9e79

Beide Builds sind der internen Gruppe „Team (Expo)“ mit einem bestehenden,
angenommenen Tester zugeordnet. App Store Connect zeigt beide als „Testing“
und nicht abgelaufen. Der zweite Upload und seine Verarbeitung wurden am
2. Oktober 2026 um 22:16 UTC erfolgreich abgeschlossen. Der Nutzer bestätigte
am 3. Oktober 2026 erneut denselben Installationsfehler.

Bereits geprüft:
- Beide neuen Builds sind bei Apple als „Validated“ registriert.
- App und eingebettete Frameworks unterstützen iOS 13.0 oder neuer und ARM64.
- Die vollständige Signaturprüfung beider neuen IPAs war erfolgreich. Native
  Codeabschnitte und eingebettetes Profil sind identisch; die Buildnummer wurde
  beim zweiten Upload erhöht.
- Distribution-Zertifikat und Profil sind bis 8. Juni 2027 gültig;
  App-Kennung, Team und TestFlight-Entitlements stimmen überein.
- Das Free Apps Agreement wurde am 2. Oktober 2026 als „Active“ angezeigt.
- Nach erneuter Anmeldung am 3. Oktober ist das Free Apps Agreement weiterhin
  „Active“. Der interne Tester hat die Rollen Account Holder und Admin mit
  Zugriff auf alle Apps.
- Apple zeigt für den neuesten Build auch eine iPhone-15-Pro-Variante mit
  geschätzt 1,06 MB Download und 6,41 MB Installationsgröße an. Das herunterladbare,
  von Apple aufbereitete Paket selbst konnte noch nicht geprüft werden.
- Apples öffentliche Statusseite zeigt TestFlight, Upload und Verarbeitung als
  verfügbar. Die dort aufgeführte allgemeine App-Store-Connect-Störung endete
  am 1. Oktober vor den beiden Uploads.
- Ein erneutes Öffnen von TestFlight und ein vollständig neuer Upload haben
  den gemeldeten Fehler nicht behoben.

App Store Connect zeigt für diesen Tester zuletzt ein iPhone 15 Pro mit
iOS 18.7.8 und eine früher installierte App-Version vom August. Die aktuell
auf dem Gerät installierte iOS-Version ist noch nicht unabhängig bestätigt.
Ein Test auf einem zweiten Gerät liegt noch nicht vor.
Am 4. Oktober bestätigte der Nutzer, dass auf dem iPhone dieselbe Apple-ID wie
beim hinterlegten internen Tester verwendet wird.
Im Apple-Developer-Konto war die Mitgliedschaft mit Verlängerungsdatum
4. Mai 2027 und Jahresgebühr 99 EUR sichtbar. Es wurde keine fällige Zahlung
angezeigt. Der Developer-Program-Vertrag ist seit 2. Oktober 2026 akzeptiert.

Bitte prüfen Sie die TestFlight-Bereitstellung und Installationsberechtigung
dieser App und unseres Developer Teams. Die Fehlermeldung entspricht dem von
Apple DTS diskutierten Fall:
https://developer.apple.com/forums/thread/813703

Falls Geräteprotokolle oder weitere Diagnosedaten benötigt werden, teilen Sie
uns bitte die konkreten Schritte zur sicheren Erfassung mit.

Vielen Dank.

## Vor dem Absenden
Die Nachricht enthält App-/Build-/Teamkennungen und den beschriebenen Fehler,
keine Schlüssel, Passwörter, Bestell-, Kunden- oder Standortdaten. Empfänger:
Apple Developer Support. Absenden erst nach ausdrücklicher Freigabe des Nutzers.
