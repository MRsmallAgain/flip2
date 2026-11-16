# flip2 toolkit v1.4.0-alpha.7-flip2

## Highlights

- **Wizard profile-scoped push** — `buildPushSet` filters `requiredIncoming` and installer extractions by profile component ids so **Arcade** no longer fails with `push set incomplete: scummvm.apk` (and other omitted apps stay off the push set).
- **FlipMouse Arcade `0.3.3-flip2`** — Launcher4 hover via **ABS_X/ABS_Y** with REL; portrait gamepad long soft-left re-enables manual mouse after toggle-off.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Same asset set as v1.4.0-alpha.6-flip2 with versioned bundle names `1.4.0-alpha.7-flip2`. Pack installers after merge, then `flip2 release --notes docs/RELEASE-NOTES-v1.4.0-alpha.7-flip2.md`.
