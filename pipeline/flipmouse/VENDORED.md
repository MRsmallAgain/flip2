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
- **Activate:** hold OK + Volume-Down together for ~1 s, then release both.
  Mode engages on the release so every press AND release has already been
  delivered natively before the grab (grabbing while a key is down would
  strand Android's synthetic-repeat timer on it). Can't misfire on normal
  volume/OK use, and touches no IME key.
- **While active:** keypads grabbed. D-pad moves, OK = left click, top-left
  soft key (139/KEY_MENU) scrolls up, pound (523) scrolls down, top-right soft
  key (48/KEY_B) toggles drag, Volume-Up/Down adjusts speed.
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

Upstream source stays in `pipeline/flipmouse/upstream/` (git-ignored, refresh
with `git -C pipeline/flipmouse/upstream pull`). This directory (`main.c`,
`build.sh`, `install.sh`, `status.sh`, `rollback.sh`, `properties/`) is what
the repo tracks.
