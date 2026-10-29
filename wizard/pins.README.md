# Wizard download pins (`pins.json`)

`pins.json` is a sha256/size gate list derived from `catalog.json` for tooling and CI. The browser still loads **`catalog.json`** for the setup wizard (URLs, license text, purpose).

Regenerate after catalog changes:

```bash
jq '{version, pinned, catalog: "wizard/catalog.json", files: [.files[] | {id, file, sha256, size, url}]}' wizard/catalog.json > wizard/pins.json
```

Every `sha256` must match a real upstream file (`sha256sum` on the downloaded bytes), not a guess.
