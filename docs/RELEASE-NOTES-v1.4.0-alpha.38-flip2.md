# flip2 toolkit v1.4.0-alpha.38-flip2

## Highlights

- **Wizard Put on phone** — Fix Sherpa UK push: `pipeline.js` `INCOMING_FOR_COMPONENT` and fallback `need.push` now match NeMo EN + Moonshine UK basenames (install.sh / pins). UK Moonshine was renamed then stripped by profile filter before adb push.
- **TCL Flip2 Manager 1.4.0-alpha.38** — Bundled wizard includes the Sherpa push fix.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

Companion pins: `https://flip2burn.online/catalog.json`.

## Start here

- Wizard: [https://flip2burn.online/](https://flip2burn.online/)
- Safest first install: [`flip2-installer-full-magisk.zip`](https://flip2burn.online/packages/flip2-installer-full-magisk.zip)
