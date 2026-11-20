# FluffyChat — Matrix client for Flip2 (bridged inbox)

[FluffyChat](https://fluffychat.im/) (`chat.fluffy.fluffychat`) is the recommended Matrix front-end on Flip2 for **bridged** networks (WhatsApp, Signal, Google Voice). **Telegram stays on patched Forkgram** — do not duplicate Telegram in this client for v1.

## Status

**Phase 0 / Phase 1 landing:** catalog pin, download/install with SHA-256 verify, and CLI mirror Forkgram. **Hardware BACK-delete and D-pad list focus patches are not shipped yet** — Flutter builds need a device spike before `*-back.patch` / `*-dpad.patch` exist. Until then, use **Flip2 Focus Bridge** (planned `pipeline/focus-bridge/`) where list focus is broken.

## Device constraints

- Android 11 (API 30), **armeabi-v7a** only
- Logical panel **321×428** (`display_size_forced`)
- Null Keyboard IME; physical **BACK** is keycode 4 (no separate DEL)
- Patch pattern when ready: `pipeline/forkgram/README.md`

## Package

| Package | Use on Flip2 |
|---------|----------------|
| `chat.fluffy.fluffychat` | **This pipeline** |
| `im.vector.app` (Element) | Fallback only |
| `com.beeper.android` | Deprioritized (D-pad/IME fit) |

## CLI

```sh
flip2 fluffychat release              # catalog pin when live
flip2 fluffychat release --fdroid     # stock F-Droid v7a (Phase 0)
flip2 fluffychat release --no-install
flip2 fluffychat patch --apk PATH     # stub until patches land
flip2 bridges doc                     # runbook paths
```

## Bridge + account setup

See **`docs/BRIDGES-FLIP2.md`** and **`docs/BRIDGE-HOSTING.md`**.

## Homescreen

Default proposal: **launcher menu slot** for FluffyChat; keep **`home-keys.json` Messages** for carrier SMS unless GV replaces SMS UX.

## Licensing

FluffyChat is **AGPL-3.0**; see `docs/BRIDGES-FLIP2.md` and repo GPL notes.
