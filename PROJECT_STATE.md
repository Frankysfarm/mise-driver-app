# Mise Liefersystem — PROJECT_STATE.md
> Zuletzt aktualisiert: 2026-07-23 (Sprint 2 abgeschlossen)

## Architektur (kompakt)
- **Server:** 178.104.106.72, Docker
- **Backoffice:** `/opt/mise/backoffice/` (Next.js 15, Port **3310** — Blue-Green Switch vollzogen)
- **Deploy:** `auto-deploy.sh` — KEIN git pull, baut lokalen Stand → Änderungen auf Server bleiben erhalten
- **DB:** Supabase self-hosted (Kong :3301, Postgres 5433)
- **Frank Engine:** `/opt/mise/backoffice/lib/frank.ts` — 15s-Tick via mise_cron
- **Fahrer-App:** `/opt/mise/backoffice/app/fahrer/app/` (page.tsx + client.tsx)
- **Cron-Endpunkte:**
  - `/api/cron/smart-dispatch` — 1x/min (BISS_INTERNAL_TOKEN)
  - `/api/driver/v1/internal/repush-loop` — 1x/min

## Abgeschlossene Fixes (dieser Sprint)

| ID | Problem | Status |
|----|---------|--------|
| MISE-003 | Dual-Dispatch: smartDispatchTick + frank.ts liefen parallel | ✅ GEFIXT — smartDispatchTick deaktiviert in smart-dispatch/route.ts |
| MISE-001 | Hold-Spalten fehlen in Migration | ✅ FALSE POSITIVE — Spalten existieren in DB |
| MISE-002 | fn_recover_abandoned_tours fehlte | ✅ GEFIXT — SQL-Funktion erstellt |

### MISE-003 Details
- Datei: `/opt/mise/backoffice/app/api/cron/smart-dispatch/route.ts`
- Zeile 11: Import auskommentiert
- Zeile 77: `smartDispatchTick()` durch `Promise.resolve(...)` ersetzt
- **Deploy noch ausstehend** (nächster 30-min auto-deploy Cycle)

### MISE-002 Details
- `fn_recover_abandoned_tours()` findet Batches in aktivem State (assigned/at_restaurant/picked_up/in_progress) wo Driver seit >10min kein Heartbeat
- Canceliert Batch, gibt Orders frei (mise_batch_id=NULL), setzt Driver auf idle
- Returniert integer (kompatibel mit repush-loop caller)

## Abgeschlossene Fixes (dieser Sprint) — KOMPLETT

| ID | Problem | Status |
|----|---------|--------|
| MISE-002 | fn_recover_abandoned_tours fehlte | ✅ Live in DB |
| MISE-003 | Dual-Dispatch deaktiviert | ✅ Deploy ausstehend |
| MISE-004 | acceptDuringTour RPC-Logik invertiert | ✅ Server |
| MISE-005 | claimBatch kein optimistic state | ✅ Server |
| MISE-006 | angekommen_am nicht gemappt | ✅ Server |
| MISE-007 | openStops stale closure | ✅ False positive |
| MISE-008 | VoIP-Token: falscher Endpoint + Field | ✅ AppDelegate.swift lokal |

### MISE-008 Details — KOMPLETT IMPLEMENTIERT
- `ios-resources/AppDelegate.swift`: URL + Body-Field korrigiert (Quelle der Wahrheit)
- `ios/App/App/AppDelegate.swift`: Vollständige VoIP/CallKit-Version hineinkopiert (war Stub!)
- `ios/App/App/Info.plist`: `voip` zu UIBackgroundModes hinzugefügt
- `ios/App/App.xcodeproj/project.pbxproj`: PushKit.framework + CallKit.framework verlinkt
- **Benötigt neuen EAS-Build für Produktion**

### MISE-009 Details
- `Dockerfile`: HEALTHCHECK Instruktion eingefügt (30s interval, 5s timeout, 60s start)
- Wirkt beim nächsten Deploy

## P0/P1-Bug-Status (Sprint 2)

| ID | Problem | Status |
|----|---------|--------|
| P0-1 | TOCTOU Race im Dispatch | ✅ fn_create_delivery_batch (FOR UPDATE NOWAIT) |
| P0-2 | Doppelte "Geliefert"-Events | ✅ FALSE POSITIVE — Endpoint bereits idempotent (completed_at IS NULL) |
| P0-3 | Kategorie-Löschung cascade | ✅ FALSE POSITIVE — FK ist SET NULL |
| MISE-001 | Hold-Spalten fehlen | ✅ FALSE POSITIVE — existieren in DB |
| MISE-002 | fn_recover_abandoned_tours | ✅ Live in DB |
| MISE-003 | Dual-Dispatch | ✅ smartDispatchTick deaktiviert |
| MISE-004 | acceptDuringTour invertiert | ✅ Korrigiert in client.tsx |
| MISE-005 | claimBatch kein optimistic state | ✅ Korrigiert |
| MISE-006 | angekommen_am nicht gemappt | ✅ arrived_at mapping |
| MISE-007 | markDelivered stale closure | ✅ FALSE POSITIVE |
| MISE-008 | VoIP-Token falsch gespeichert | ✅ AppDelegate lokal — **EAS Build ausstehend** |
| MISE-009 | Kein Docker healthcheck | ✅ Dockerfile HEALTHCHECK |
| Deploy Bug | --output pipe | ✅ Auf --load gewechselt |

## Verifizierte Annahmen
- Hold-Spalten (dispatch_after, hold_reason, hold_for_order_id) EXISTIEREN in customer_orders
- fn_repush_pending_batches + fn_auto_cancel_unaccepted_batches EXISTIEREN
- auto-deploy baut von lokalem Stand — Server-Änderungen persistieren
- Produktion: nur 'completed' und 'cancelled' Batches (keine aktiven gerade)

## Nächstes Arbeitspaket: MISE-006
**Problem:** `angekommen_am` im normalizedMiseBatch ist hardcoded `null` statt `s.arrived_at`
**Datei:** `/opt/mise/backoffice/app/fahrer/app/page.tsx` Zeile ~66
**Fix:** 1 Zeile ändern, kein Risiko
