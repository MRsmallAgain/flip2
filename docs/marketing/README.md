# Flip2 press kit & launch copy

Curated assets and channel-ready markdown for public releases. Raw phone/wizard photos stay on your PC (`~/flip2-marketing-2026-11/`); only redacted or UI-safe files belong here.

## v1.3.0-alpha.3

| Asset | Use |
|-------|-----|
| `v1.3.0-alpha.3/flip2-ui-quad.png` | README-style four-panel device UI |
| `v1.3.0-alpha.3/github-social-preview-2026-11.png` | GitHub **Settings → Social preview** (1280×640) — phone hero + wizard panel |
| `v1.3.0-alpha.3/og-1200x630-2026-11.png` | Discussions / blog Open Graph |
| `v1.3.0-alpha.3/20261107_005636.jpg` | Hardware hero (alternate JPG) |
| `v1.3.0-alpha.3/phone-tour-publish/flip2-tour-hardware-hero.png` | **Hardware hero** — same PNG as `wizard/assets/flip2-hero-phone.png` (Manager / Getting started top) |
| `v1.3.0-alpha.3/01-credit-initial.png`, `04-downloads-verified.png` | Wizard flow (from compat test captures — refresh with current Manager UI when available) |
| `v1.3.0-alpha.3/phone-tour-publish/flip2-tour-01.png` … `flip2-tour-17.png` | **Phone tour** — 10 screens (01–04, 11–17); attach to release or embed per `phone-tour-publish/README.md` |
| `v1.3.0-alpha.3/phone-tour-publish/flip2-phone-tour-mosaic-banner.png` | Mosaic share banner (4+4+3 grid + footer) |
| `v1.3.0-alpha.3/phone-tour-publish/flip2-phone-tour-mosaic-og-1200x630.png` | OG / Discussions for the mosaic |

**Copy:** `v1.3.0-alpha.3/copy/` — release supplement, GitHub Discussion, Reddit, HN, X thread, FAQ.

**Feature list (Reddit):** [`v1.3.0-alpha.3/copy/features/FEATURE-LIST.md`](v1.3.0-alpha.3/copy/features/FEATURE-LIST.md)

**Live device tour (adb):** `v1.3.0-alpha.3/phone-tour/` — extra heroes (Tools, FlipMouse); full set in `~/flip2-marketing-2026-11/assets/phone-tour-2026-11-08/`. **GitHub-ready:** `phone-tour-publish/`. Re-run tour: `bash ~/flip2-marketing-2026-11/scripts/phone-tour-screenshots.sh`; mosaic: `python3 -I ~/flip2-marketing-2026-11/scripts/stitch_phone_tour_mosaic.py`.

**Release:** https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2

## Regenerate (working tree)

```bash
python3 -I ~/flip2-marketing-2026-11/scripts/inventory_media.py
bash ~/flip2-marketing-2026-11/scripts/curate_assets.sh
python3 -I ~/flip2-marketing-2026-11/scripts/stitch_ui_quad.py
python3 -I ~/flip2-marketing-2026-11/scripts/social_preview.py
```

Then copy winners into `docs/marketing/v<tag>/` and update this index.

**Branding baseline:** [docs/branding/README.md](../branding/README.md) (`gen-assets.py` for vector/icon cards).

**Launch checklist:** `~/flip2-marketing-2026-11/launch-checklist.md`
