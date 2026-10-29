# Flip2 recovery program router

Repo: `/home/tim/.local/share/flip2`. Branch: `feature/rooting-slice`. Master stays `0fc09f7`.

## Class rules

- **RUN** — Executed when the recovery plan is approved, one module per session, in RUN order below. Session opens only this file and `docs/recovery/<id>.md` plus that module's READ list. Ends with `MODULE <id> PASS` or `MODULE <id> FAIL`. Does not open the next module.
- **LATER** — Only when the user message is exactly `run <id>`.
- **STOP** — Prints standing decision and exits. Not triggered by plan approval.

## RUN order

| id | summary |
| --- | --- |
| A1 | emitter: `emit.sh`, packer calls it |
| A2 | wizard tier APKs out of installer zips |
| A3 | device install/verify scripts from manifest |
| A4 | pipeline.js push payload |
| A5 | image first-boot from emitter |
| A6 | `flip2 wizard check` drift |
| A7 | `flip2 release` |
| A8 | docs |
| B1 | pins.json |
| B2 | `flip2 source fetch` |
| A9 | proof |
| C1 | wallpaper md5 verify |

## LATER (exact `run <id>`)

C1 regen, C2 version bump, C3 release, C4 catalog pin, B3 build, C5 WebUSB, C6 factory remainder.

## STOP

C7 super/vbmeta — print 2026-10-28 donor bootloop note, exit 0, flash nothing.  
C8 merge — print `master stays 0fc09f7`, exit 0.

## Constants (all RUN modules)

- Donor `MRV8IJJVPRYTS4UG`. Never target guinea pig `ONTKKB9L7PEUX4Z5`.
- During RUN: manifest version `1.2.0-flip2`; catalog full-installer pin size `16424801`, sha256 `be8b5fc7d2fe4b56ae0aa3d91d72a3de12e5be0cf36a09a8687cc6eeaf1e26bb`.
- `global display_size_forced` = `321,428`. Wallpaper md5 `d0eb46bc33e2751940150abf72b93c5f`.
- Manifest `versionCode` = `20261029`. Packers must not call `date`.
- Home keys in `launcher-overlay/home-keys.json` per recovery plan Constants block.
- Markers: `# BEGIN GENERATED` / `# END GENERATED`.
- Phone verifier: `/data/local/tmp/verify-new.sh`.
