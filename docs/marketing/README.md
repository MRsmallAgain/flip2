# Flip2 press kit & launch copy

> **The project moved off GitHub on 2026-11-13** — the account behind it was suspended, so every `github.com/MRsmallAgain` link 404s. Start at <https://flip2burn.online/>; files live under `https://flip2burn.online/packages/` with pins in <https://flip2burn.online/catalog.json>. Full details, including paste-ready notices for existing threads: [moved](MOVED.md).
>
> The published copy in this directory keeps its original text — an announcement is a record of what was said — with a banner at the top of each file. This index is navigation, so its own links are corrected below.

Curated assets and channel-ready markdown for public releases. Raw phone/wizard photos stay on your PC (`~/flip2-marketing-2026-11/`); only redacted or UI-safe files belong here.

## v1.4.0-alpha.3

| Asset | Use |
|-------|-----|
| Reuse `v1.3.0-alpha.3/phone-tour-publish/*` until refreshed | Phone tour / mosaic |

**Release notes:** [`docs/RELEASE-NOTES-v1.4.0-alpha.3-flip2.md`](../RELEASE-NOTES-v1.4.0-alpha.3-flip2.md) — the body of the published release, and the file `flip2 release --notes` consumed.

**Release:** v1.4.0-alpha.3-flip2 — files under [packages/](https://flip2burn.online/packages/), pins in [catalog.json](https://flip2burn.online/catalog.json)

No prebuilt Windows `.exe` is published; build it with `npm run pack:win`. Draft copy for the unreleased alpha.1 cycle sits outside version control and is not linked here.

## v1.3.0-alpha.3

| Asset | Use |
|-------|-----|
| `v1.3.0-alpha.3/flip2-ui-quad.png` | README-style four-panel device UI |
| `v1.3.0-alpha.3/github-social-preview-2026-11.png` | Project **settings → social preview** (1280×640) — phone hero + wizard panel |
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

**Release:** v1.3.0-alpha.3-flip2 — files under [packages/](https://flip2burn.online/packages/), pins in [catalog.json](https://flip2burn.online/catalog.json)

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
