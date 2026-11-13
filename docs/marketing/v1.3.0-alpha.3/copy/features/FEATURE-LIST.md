# Flip2 toolkit — feature list (v1.3.0-alpha.3)

> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [MOVED.md](../../../MOVED.md).
> The text below is unchanged from publication.

Copy-paste friendly for Reddit, Discussions, and release posts. Alpha disclaimers at bottom.

**Release:** https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2  
**Repo:** https://github.com/MRsmallAgain/flip2

---

## One-liner

TCL Flip 2 mod stack: **real T9 + offline voice** on the keypad, **D-pad virtual mouse**, **Tag Drawer**, **Launcher4** menu grid, **null keyboard** (no IME bar), **Forkgram Classic** patch — **one Magisk zip** or **TCL Flip2 Manager** on Chrome/Linux, with a **de-root path** that keeps the user-facing bits.

---

## Headline bullets (paste into a post)

- **Physical T9 + multi-tap** — null keyboard IME; `#` cycles T9 / ABC / 123; hold `*` for **offline Sherpa-ONNX** dictation (EN + UK packs)
- **Null Keyboard** — zero-height IME; full-screen apps without a keyboard bar eating the flip screen (*survives de-root*)
- **Launcher4 + menu grid** — slots 1–9 (+ Tools folder); customizable via `slots.json` / wizard Base profile (*launcher survives de-root*)
- **Tag Drawer** — Pixel-style tagged app launcher (system placement; needs root/Magisk)
- **FlipMouse** — D-pad drives a virtual mouse when apps expect touch (*needs root*)
- **Forkgram Classic** — patched Telegram: BACK deletes in text fields on hardware keys (*Classic only*, not Client; survives de-root)
- **Home soft keys** — map left/right/up/down (e.g. Intertune, Messages, Tag Drawer, Recents) via `home-keys.json`
- **Display profile** — optional 321×428 logical size, wallpaper, nav overlay tuning on full install
- **Tier B installer** — single **`flip2-installer-full-magisk.zip`**: flash in Magisk once, reboot; verify `SHA256SUMS`
- **TCL Flip2 Manager** — browser or **Companion** desktop wizard: pinned downloads, Prepare → connect → install → **27-check verify** (experimental push path vs conservative zip)
- **De-root script** — `deroot.sh` + Magisk restore images; keeps launcher, null keyboard, Forkgram, home keys; drops FlipMouse, keypad remap, Tag Drawer system slot, nav overlay
- **Curated apps (Base)** — F-Droid Basic, Material Files, NewPipe, VLC, AppShelf, Bouncy (pinball), Intertune, Chrome slot, stock utilities via menu/Tools
- **Arcade profile (experimental)** — FlipMouse Arcade / landscape gamepad path; explicit gate in wizard
- **Managed profile (optional)** — Headwind MDM + Where; separate docs; not the default story
- **Linux-first** — WebUSB wizard needs **Chrome on Linux**; companion adds host adb + one-click udev
- **Pipeline CLI** — `flip2 apply`, `flip2 setup full`, `flip2 recovery`, image tree / installer pack / bundle tiers (manifest-driven)

---

## Short paragraphs (if the sub wants prose)

**Typing & voice**  
The null keyboard sits under stock apps so the **real keypad** is your input. Predictive T9, multi-tap ABC, digit mode, and **on-device Sherpa STT** (no cloud) while you hold the star key — built for a phone you flip open, not a 6" slab.

**Launcher & apps**  
Replace the icon swamp with a **9-slot menu**, **Tag Drawer** search/tags, and a **Tools** folder. Launcher4 is built for the inner panel; soft keys jump to music, messages, tags, or shortcuts you configure.

**Pointer & games**  
FlipMouse turns the D-pad into a cursor for stubborn touch UIs. Optional Arcade profile adds gamepad + landscape cursor experiments.

**Install & honesty**  
Public **alpha**. Full stack wants **Magisk root**. Safest first path: **full installer zip** from Releases, not the experimental wizard USB push unless you are comfortable debugging. Read **SAFETY.md** before you flash anything.

---

## Reddit title ideas

1. `TCL Flip 2 toolkit — T9, offline voice, Tag Drawer, one Magisk zip (alpha, open source)`
2. `I modded a TCL Flip 2 into a real dumbphone stack (Launcher4, Sherpa STT, Forkgram) — v1.3.0-alpha.3`
3. `Open source Flip 2 mods: null keyboard, D-pad mouse, de-root path that actually keeps your launcher`

---

## Mandatory disclaimers (every public post)

- **v1.3.0-alpha.3-flip2** — public alpha; expect breakage
- **Root / Magisk** for full tier; **Tier B zip** is the conservative first install
- Wizard **Put on phone** is **experimental** vs one-shot Magisk zip
- **Chrome on Linux** for WebUSB Manager; Firefox does not work
- **Forkgram Classic only** (not Client)
- [SAFETY.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md) · [Releases + SHA256SUMS](https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2)

---

## Image URLs (after clone)

Mosaic: `docs/marketing/v1.3.0-alpha.3/phone-tour-publish/flip2-phone-tour-mosaic-banner.png`  
Quad: `docs/marketing/v1.3.0-alpha.3/flip2-ui-quad.png`

Longer narrative: [PHONE-FEATURES.md](./PHONE-FEATURES.md) · Draft post: [reddit-dumbphones.md](../reddit-dumbphones.md)
