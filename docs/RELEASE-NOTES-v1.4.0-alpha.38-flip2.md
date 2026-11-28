# flip2 toolkit v1.4.0-alpha.38-flip2

## Highlights

- **Wizard Put on phone** — Fix Sherpa UK push: `pipeline.js` `INCOMING_FOR_COMPONENT` and fallback `need.push` now match NeMo EN + Moonshine UK basenames (install.sh / pins). UK Moonshine was renamed then stripped by profile filter before adb push.
- **TCL Flip2 Manager 1.4.0-alpha.38** — Bundled wizard includes the Sherpa push fix and `clearBadLines` on Files retry.

## Upgrading from an older Manager (multi-machine SHA fix)

If **Files** shows `flip2-installer-full-magisk.zip: SHA-256 does not match the catalog pin` on more than one PC:

1. Install **this release’s** Linux AppImage or Windows `.exe` from [flip2burn.online/packages/](https://flip2burn.online/packages/) (footer must show **Catalog 1.4.0-alpha.38** and matching Companion version).
2. Delete any old **`flip2-installer-full-magisk.zip`** (~395 MB) in `~/Downloads` and **`~/Downloads/flip2-wizard/`** (same filename; repacked full installer is ~201 MB).
3. On **Files**, use **Download all here** or **Get** again.

See `docs/WIZARD-FAILURES.md` (#13).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

Companion pins: `https://flip2burn.online/catalog.json`.

## Start here

- Wizard: [https://flip2burn.online/](https://flip2burn.online/)
- Safest first install: [`flip2-installer-full-magisk.zip`](https://flip2burn.online/packages/flip2-installer-full-magisk.zip)
