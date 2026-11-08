# TCL Flip 2 — phone feature overviews (marketing)

Short blurbs for posts, release notes, and captions. Pair with screenshots from `assets/pictures-curated/`, `assets/device-ui/`, or repo `docs/screenshots/`.

**Baseline stack:** v1.3.0-alpha.3 Base profile unless noted. Full tier needs Magisk/root unless labeled *de-root friendly*.

---

## Launcher & homescreen

**Launcher4** — Custom HOME app built for the Flip 2’s small inner display: slot-based app grid, soft keys, and behavior tuned for a flip form factor. *De-root friendly.*

**Menu grid (slots 1–9)** — Stock-style number shortcuts on the homescreen; map each key to an app or a Tools folder. Edit `slots.json` and `flip2 apply`, or use the wizard profile.

**Launcher3 RRO overlay** — Resource overlay on stock Launcher3 when you keep it as HOME; same slot semantics without replacing the whole launcher. Meaningful only when Launcher3 stays default; with Launcher4 the menu lives in the APK instead.

**Home soft keys** — Notifications / Menu / Shortcuts under the main grid (`home-keys.json` + `flip2 home-keys`).

**Screenshots:** `docs/screenshots/home.png`, `menu-grid.png`; Pictures `Screenshot from 2026-11-06 00-45-25.png` (BuddyList2 PDP — shows tight third-party UI on the panel).

---

## Apps & input

**Null Keyboard** — IME that stays out of the way: full-screen apps without a fat keyboard bar eating the flip screen. *De-root friendly.*

**Tag Drawer** — Pixel-style tag launcher for apps (system placement via Magisk module). Quick scan by tags instead of an endless grid.

**Forkgram (Classic)** — Patched Telegram for Flip 2 ergonomics and security posture; **Classic only**, not Client.

**F-Droid Basic, Material Files, NewPipe, VLC, AppShelf, Bouncy, Intertune** — Curated utilities in Base profile (see Manager profile copy).

**Screenshots:** `tag-drawer.png`, `null-keyboard.png`; device photos from Downloads hero set.

---

## Voice & typing

**T9 + physical keypad** — Real dumbphone typing on hardware keys, not an on-screen faux keypad.

**Sherpa-ONNX STT (offline)** — On-device speech-to-text while models load; English + Ukrainian voice packs in full installer. No cloud STT required for dictation flows.

**stt_lang / tokens** — Wizard verify checks Sherpa assets under `files/sherpa/en` and `uk`.

---

## Pointer & games

**FlipMouse** — Virtual mouse driven by the D-pad — useful when apps expect touch. *Needs root.*

**FlipMouse Arcade (experimental)** — Gamepad + landscape cursor + portrait mouse; Arcade profile only; mutually exclusive with standard FlipMouse at runtime.

**Keypad ⌫ remap** — Magisk module for backspace on the keypad layout. *Needs root.*

---

## System chrome

**Nav overlay** — Framework nav overlay for Flip 2 layout. *Dies on de-root.*

**Display 321×428 + wallpaper** — Profile can set density/size and ship default wallpaper (first-boot paths where merge tree cannot).

**Flip 2 Companion** — Desktop shell for the same Manager pages: host adb, udev, clearer install errors than pure browser-only for some steps.

**TCL Flip2 Manager** — Browser wizard: pin-verified downloads, Prepare flow, optional erase-gated boot flash slice (separate from install).

**Screenshots:** Pictures `Screenshot from 2026-10-30 23-31-29.png` (Companion Start — phone ready, profiles); `Screenshot from 2026-11-07 19-40-40.png` (Prepare / experimental install + profile Base).

---

## Managed profile (not Default CTA)

**Headwind MDM + Where** — Managed profile adds MDM launcher and Where; device owner is a *phone* wipe story, not USB userdata wipe. See `docs/MANAGED-MDM-SETUP.md`.

---

## Deployment one-liners

| Path | What the user does |
|------|---------------------|
| **Tier B full zip** | Magisk → flash `flip2-installer-full-magisk.zip` → reboot |
| **Wizard** | Chrome/Linux → Prepare → experimental root push |
| **De-root** | Run `deroot.sh` / Magisk uninstall — launcher, null keyboard, Forkgram remain |

---

## Video library

21 clips copied in order to `assets/video/for-editor/` (`01-…` through `21-…`). Concat list: `assets/video/concat-all.ffconcat`. After `ffmpeg` install: `scripts/stitch_all_videos.sh` → `assets/video/export/flip2-all-clips-concat.mp4` (re-encode). Faster on your machine: import `for-editor/` folder into your editor in numeric order.
