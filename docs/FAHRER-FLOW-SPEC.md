# Mise Fahrer-App — Flow-Spec (Liefer-Fahrer)

**Stand:** 2026-06-09 · Basis: Experten-Konsens (mise-researcher, mise-customer-experience, mise-pos-ux) + Founder-Entscheidung Tahar

## Leitprinzip
Ein müder Fahrer um 23 Uhr (laut, hektisch, fettige Finger) darf nie mehr als **eine Frage** im Kopf haben: „Was ist mein nächster Tap?" → 3 Phasen, je EINE dominante Aktion:

```
SAMMELN  →  ABHOLEN  →  LIEFERN
(annehmen)   (picken)    (Route + fahren)
```
Phasen-Leiste oben immer sichtbar, aktive Phase leuchtet (Moutarde).

---

## Der Flow im Detail

### Phase 0 — Online/Offline
- **Online, keine Order:** ruhiges Puls-Icon, „Du bist online — sobald eine Bestellung reinkommt, klingelt dein Handy." Ganzer oberer Rand färbt sich (Online = farbig, Offline = grau). Footer: „Heute: 4 Touren · 38 €".
- **Offline:** „Feierabend-Modus", dicker „Online gehen"-Button.

### Phase 1 — SAMMELN (annehmen)
- Neue Order → **CallKit-Anruf** (klingelt durch, auch App zu). CallKit-Caller-Name: `„Frankys Pasta · 1 Bestellung · 4,20 €"`.
- **Anruf annehmen → App öffnet direkt auf der Order-Karte (Vollbild) → Fahrer tippt 1× „Annehmen".** (Founder-Entscheidung: KEIN native Auto-Claim — die Web-UI nimmt an, eine Quelle der Wahrheit.)
- Angenommene Order wandert **sichtbar** in die Sammel-Liste mit Chip „✓ Angenommen" + Haptik-Bump + kurzes Aufblitzen. **Verschwindet NIE.**
- **Jede weitere Order klingelt EINZELN** → annehmen → Liste wächst live (Realtime).
- Sticky-Footer: großer Button **„Alle abholen (3)"** → Phase ABHOLEN.

### Phase 2 — ABHOLEN (picken)
- Ankunft-Slider „Am Restaurant angekommen" (Status pusht ans Restaurant).
- Jede Order **einzeln** im Vollbild, Fortschritt „1 von 3", Item-Liste groß. Button **„Abgeholt"** → nächste Order.
- Verifikation: Order-Nr. abhaken (QR-Scan = Phase 2). Sekundär klein: „Stimmt was nicht?".
- Wenn alle Pickups completed → automatisch Phase Route.

### Phase 3 — Route → LIEFERN
- **Route wird schon WÄHREND des Pickens im Hintergrund vorberechnet** (`rerouteBundle`).
- Popup (Bottom-Sheet): „Alles abgeholt. Beste Route ist fertig · 3 Stopps · 5,4 km · 22 Min" → **„Losfahren"**. Nie Spinner-Blockade.
- LIEFERN: Stop-Liste + Map (blau=Pickup, grün=Dropoff). Pro Stop: **„Navigieren"** (Apple-Maps-Deep-Link, kein Eigenbau) + **„Geliefert"** (Slider, bewusste Geste).
- **Bar-Betrag prominent** bei Barzahlung. Anruf-Button zum Kunden. Kontaktlos → Foto-Pflicht.
- Letzter Stop geliefert → „Tour fertig! 12,60 € verdient 🎉" → zurück zu Phase 0.

---

## Die 2 Bugs — Ursache + Fix (aus Code-Analyse)

### Bug A: „Order verschwindet beim Annehmen"
**Ursache:** `client.tsx` `claimBatch` macht `window.location.reload()`, kollidiert mit Realtime-`router.refresh()` + `visibilitychange`-Reload (Race). Order fällt aus `pending_acceptance`-View, ist aber noch nicht als `activeBatch` da → kurz „weg".
**Fix:**
- `claimBatch`: **optimistisches lokales State-Update** statt `window.location.reload()` — Batch sofort aus `openBatches` raus + lokal als `activeBatch` setzen, dann EIN `router.refresh()`. Bei Fail: Rollback + Toast (kein `alert()` — blockiert WebView).
- `visibilitychange`-Handler: `router.refresh()` statt hartem `window.location.reload()`.
- Realtime-Channel 300ms debouncen.

### Bug B: „Anruf-Annehmen claimt die Tour nicht"
**Ursache:** native `acceptTour()` (AppDelegate.swift Z.121–141) postet an Server, aber die WebView synct nicht — zwei parallele Accept-Pfade.
**Fix (Founder-Entscheidung „App öffnet + 1 Tap"):**
- **Native `acceptTour()` ENTFERNEN.** CXAnswerCallAction holt nur die App in den Vordergrund (+ optional `batch_id` an die WebView geben).
- Web zeigt nach Foreground die Order-Karte prominent (Vollbild „INCOMING") → 1 Tap „Annehmen" → `claimBatch` (optimistisch, s.o.).

---

## Architektur-Änderung: einzeln annehmen statt Pre-Bundle
**Ursache der Spannung:** `lib/frank.ts:190-211` hängt neue Orders an einen `pending_acceptance`-Batch → 1 Sammel-Karte statt einzelner Anrufe.
**Fix:**
- Frank legt **pro Order einen eigenen `pending_acceptance`-Batch** an (1 Pickup + 1 Dropoff) → jede Order klingelt einzeln. (Pre-Bundle-Zweig für `pending_acceptance` raus.)
- Annehmen einer weiteren Order während aktiver Tour → neues RPC `merge_mise_order_into_active_batch` hängt die Stops in den aktiven `assigned`-Batch (Pickup-Dedup via Haversine <0.1km, Logik existiert in `addOrderToBundle`) → am Ende EINE optimierte Route.
- UI: bei aktiver Tour zeigt die Inbox neue Einzel-Order als Karte „+ Diese Order dazunehmen".

---

## Prioritäten
**Blocker (Kern-Loop):**
1. Bug A — `claimBatch` optimistisch, `alert()` raus, `visibilitychange` weich.
2. Bug B — native `acceptTour()` raus, Web zeigt Order-Karte nach Anruf.
3. Frank: Einzel-Order-Batches + `merge`-RPC.
4. „Route berechnen"-Popup nach komplettem Pickup.

**Should-Fix:** Annehmen-Button 56pt, Nav-Chip vergrößern, Bestätigungs-Klang/Haptik bei Annahme + „alle bereit", Phasen-Leiste.

**Nice:** Realtime debounce, Übergabe-Foto-Retention (DSGVO).

## Touch/Speed-Regeln
- Eine primäre Aktion pro Screen, ≥56pt, daumenerreichbar unten.
- Slider für irreversibles (Ankunft, Geliefert). Kein „Bist du sicher?".
- Externe Navigation. Haptik bei jedem State-Wechsel. Großer Kontrast.

## Relevante Dateien
- `/opt/mise/backoffice/app/fahrer/app/client.tsx` (State, claimBatch, visibilitychange, OpenBatchSection)
- `/opt/mise/backoffice/app/fahrer/app/page.tsx` (Server-Load aktiver Batch, misePending)
- `/opt/mise/backoffice/lib/frank.ts` (dispatchOrder, Pre-Bundle-Zweig:190, addOrderToBundle:352, rerouteBundle:440)
- `/opt/mise/backoffice/app/api/driver/v1/orders/[id]/picked-up/route.ts` (Reroute-Trigger)
- `/Users/eule/mise-driver-app/ios-resources/AppDelegate.swift` (CallKit, acceptTour:121–141 → entfernen)
