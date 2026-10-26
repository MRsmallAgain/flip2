# FlipMouse — vendored + patched

**Upstream:** [TylerBoni/FlipMouse](https://github.com/TylerBoni/FlipMouse)
**Vendored at upstream commit:** `f5a4dcc74a80465c6235bccccdf3e66a596716cc` (2025-03-18)
**License:** MIT per upstream README (upstream has no standalone LICENSE file; credit carried in the root README Credits section).

## Why patched

Upstream grabs the keypads at startup and toggles mouse mode on a **Star tap**.
On this device the star key belongs to the null-keyboard IME: tap-`*` cycles T9
candidates, hold-`*` runs Vosk dictation. An always-grabbing mouse would break
both.

## Local patch (`main.c`, this directory)

- **Passive observer at startup** — keypads are NOT grabbed; the system sees
  every key natively and FlipMouse only watches.
- **Toggle:** hold the **upper-left soft key** (139/KEY_MENU) for 2 s, then
  release — enables mouse mode when passive, releases the cursor when active.
  Toggling on release means the grab never happens while a key is physically
  down (that would strand Android's synthetic-repeat timer). In mouse mode a
  short soft-key tap still scrolls up one step. Star tap also exits (backup).
  Volume keys are never used as a gesture, so they always work.
- **While active:** keypads grabbed. D-pad moves (auto-repeat on hold),
  OK = left click, soft-key tap = scroll up / soft-key 2 s hold = exit,
  pound (523) scrolls down, top-right soft key (48/KEY_B) toggles drag,
  Volume-Up/Down adjusts speed.
- **Exit:** star tap (522) releases the grabs, back to passive.
- v1.3: held-key auto-repeat synthesized in-daemon (400 ms delay, 10 steps/s,
  wheel on slowed cadence) — the keypads have no kernel EV_REP and Android's
  repeater never sees grabbed keys; releases are swallowed, which also fixed
  the double-step-per-tap quirk.
- Upstream laptop-keymap path removed (not needed here); scancodes verified
  against this unit's `/system/usr/keylayout/matrix-keypad.kl` and `mtk-kpd.kl`.

## Build & use

```bash
flip2 flipmouse build      # NDK armv7a + static libevdev -> Magisk zip
flip2 flipmouse install    # push + magisk --install-module + start now
flip2 flipmouse status
flip2 flipmouse rollback   # remove module
```

The module's `service.sh` (1.4.1-flip2) supervises the daemon: it waits for
the matrix keypad, detaches stdio, logs to `/cache/FlipMouse.log`, and
restarts the process if it exits. `flip2 flipmouse install` runs the same
script immediately, so the mouse survives both an adb-shell teardown and a
reboot instead of silently disappearing.

Upstream source stays in `pipeline/flipmouse/upstream/` (git-ignored, refresh
with `git -C pipeline/flipmouse/upstream pull`). This directory (`main.c`,
`build.sh`, `install.sh`, `status.sh`, `rollback.sh`, `properties/`) is what
the repo tracks.
