# Franky's Fahrer — design direction

Scope: separate installation canary and future driver app identity. No claim that
the operational driver UI has been replaced or visually approved.

The driver needs to understand the next task under time pressure. Preserve the
existing stop, pickup scan and delivery flows; refine their hierarchy rather than
introduce an unrelated new dashboard.

- Forest green #194B35: primary action and identity.
- Warm cream #F6EDDA: calm background; near-black #172C22 for content.
- System typography with strong route numbers; legible 14–16px instructions and
  44–48px touch targets. Never depend on a status color alone.
- Signature: a compact stop-progress line and a reachable bottom action area.
- App icon: recognizable Franky's face/hat with a small route cue, opaque and
  square; generated from the user's existing brand logo, not an unrelated mark.
- Installation screen must say "Installationstest" and "Noch nicht für
  Lieferfahrten". No simulated completed deliveries or live-connection claims.

## Findings to carry into the operational app
Source review found delivery actions below the route/map, 36px secondary buttons,
11px delivery notes, a color-only connection dot, and pointer-only swipe confirm.
Refine these in a separate verified UI change with an accessible confirmation
alternative. Native GPS/push and real deliveries need real-device verification.

## Asset provenance
Icon generated October 3, 2026 with built-in image generation, using the existing
public/shop-brand/frankys/logo.png as reference. No customer or credential data was
used. Original source is resources/variants/frankys/icon.png; the asset pipeline
must create Apple's required icon dimensions. Splash source is editable SVG.
