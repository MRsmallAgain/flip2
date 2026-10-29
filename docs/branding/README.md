# Flip2 branding assets

Simple flip-phone iconography aligned with the wizard UI (`#0b62c4` accent, `#f7f6f2` background, `#1b1f24` ink).

## Regenerate

```bash
python3 docs/branding/gen-assets.py
```

Requires **Pillow** (`python3-pil`).

## Files

| File | Use |
|------|-----|
| `logo.svg` | Scalable logo (GitHub, docs, print) |
| `logo-512.png` | High-res square (stores, PWA) |
| `github-social-preview.png` | **1280×640** — GitHub repo **Settings → Social preview → Upload an image** |
| `readme-banner.png` | Optional wide banner for README or release notes |
| `../wizard/assets/favicon-32.png` | Browser tab icon (wizard served from `wizard/`) |
| `../wizard/assets/apple-touch-icon.png` | iOS home-screen bookmark |
| `../wizard/assets/og-wizard.png` | **1200×630** — Open Graph when linking the wizard page |
| `../wizard/assets/logo.svg` | Copy of vector logo for static hosts |

## GitHub social preview

1. Open **github.com/MRsmallAgain/flip2** → **Settings** → **General** → **Social preview**.
2. Upload `docs/branding/github-social-preview.png`.
3. Save. Links to the repo on Slack/Discord/X will show the card.

## Wizard / Chrome

When serving `wizard/` over HTTP, `pages/index.html` references `../assets/` for favicon and OG image. For a public host, use an absolute OG URL if needed:

```html
<meta property="og:image" content="https://your.host/wizard/assets/og-wizard.png">
```

## Colors

| Token | Hex | Role |
|-------|-----|------|
| Ink | `#1b1f24` | Text |
| Background | `#f7f6f2` | Page |
| Accent | `#0b62c4` | Buttons, active step |
| OK | `#157a3c` | Pass / safety hints |
| Line | `#d8d4ca` | Borders |
