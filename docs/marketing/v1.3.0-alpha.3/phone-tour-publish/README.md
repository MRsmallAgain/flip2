# Phone tour — GitHub publication set (v1.3.0-alpha.3)

Hardware hero, companion Getting started, verify (27 passed), nine phone UI shots, and mosaic banner — cleared for release attachments and README/Discussion embeds. **Calculator is not in the mosaic** (`flip2-tour-04.png` optional single attach only).

## Files

| File | Scene |
|------|--------|
| `flip2-tour-hardware-hero.png` | **Hardware** — `wizard/assets/flip2-hero-phone.png` (companion / Getting started hero) |
| `mosaic-companion-start.png` | **Companion** top — Getting started / profiles (source: Pictures 2026-10-30) |
| `mosaic-verify-27-passed.png` | **Prepare → Check** — 27 passed / 0 failed (Pictures 2026-11-07) |
| `flip2-tour-01.png` | Launcher4 homescreen |
| `flip2-tour-02.png` | Menu grid (slots 1–9) |
| `flip2-tour-03.png` | Pixel Tag Drawer |
| `flip2-tour-04.png` | Calculator *(not in mosaic)* |
| `flip2-tour-11.png` | Bouncy / Vector Pinball |
| `flip2-tour-12.png` | Forkgram Classic |
| `flip2-tour-14.png` | Intertune |
| `flip2-tour-15.png` | NewPipe |
| `flip2-tour-16.png` | F-Droid Basic |
| `flip2-tour-17.png` | VLC |
| `flip2-phone-tour-mosaic-banner.png` | Shareable mosaic — **row1:** hardware · companion · 27 passed · **row2:** 4 UI · **row3:** 5 apps |
| `flip2-phone-tour-mosaic-og-1200x630.png` | Open Graph / social (1200×630) |

**Before public post:** Forkgram may show account UI — redact if needed.

## After commit — embed in release or README

```markdown
![Flip2 phone tour mosaic](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-phone-tour-mosaic-banner.png)

![Hardware](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-hardware-hero.png)

| Homescreen | Menu | Tag Drawer |
|:---:|:---:|:---:|
| ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-01.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-02.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-03.png) |

| Bouncy | Forkgram | Intertune | NewPipe | F-Droid | VLC |
|:---:|:---:|:---:|:---:|:---:|:---:|
| ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-11.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-12.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-14.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-15.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-16.png) | ![](docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-tour-17.png) |
```

## Regenerate mosaic

```bash
python3 -I ~/flip2-marketing-2026-11/scripts/stitch_phone_tour_mosaic.py
```

Ensure `assets/phone-tour-publish/` has `flip2-tour-hardware-hero.png`, `mosaic-companion-start.png`, `mosaic-verify-27-passed.png`, and renamed `flip2-tour-*.png` (or originals under `phone-tour-2026-11-08/`). Companion/verify copies: `pictures-curated/Screenshot from 2026-10-30 23-31-29.png` and `Pictures/Screenshots/Screenshot from 2026-11-07 01-17-36.png`.
