# Flip2 marketing FAQ (v1.3.0-alpha.3)

> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [MOVED.md](../../MOVED.md).
> The text below is unchanged from publication.

## Which phone?

**TCL Flip 2** (Gflip6). USB vendor **1bbb:0c01**. Requires USB debugging; full tier needs **Magisk/root**.

## What's the safest first install?

Download **`flip2-installer-full-magisk.zip`** from the [release](https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2), verify with `sha256sum -c SHA256SUMS`, flash once in the Magisk app, reboot.

The browser wizard **Put on phone** step is **experimental** — same payload in spirit, but more moving parts (WebUSB, host-free install path).

## Browser wizard requirements?

- **Chrome** on **Linux** (WebUSB). **Firefox does not work.**
- Serve `wizard/` over HTTP (not `file://`).
- Read [SETUP-WIZARD.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SETUP-WIZARD.md) and [SAFETY.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md) first.

## Forkgram: Classic or Client?

**Forkgram Classic only** — not Client. See Manager/wizard copy.

## What survives de-root?

Per README: Launcher4, Null Keyboard, Forkgram, home-keys, default HOME/IME tend to survive; FlipMouse, keypad remap, nav overlay, TagDrawer system placement need root and are expected to drop. Final step: Magisk → Uninstall → Restore Images.

## Managed / Headwind / device owner?

Documented for **Managed** profile; not the default launch story. Don't promise MDM in general marketing unless you're ready to support console access issues.

## Arcade profile?

**Experimental** in v1.3.0-alpha.3 — explicit checkbox gate before setup.

## Companion vs browser?

**Flip 2 Companion** is the same pages with host `adb`, one-click udev, and clearer install errors. Browser path is self-contained without host adb for install.

## Credits and third-party pins?

Sherpa-ONNX (k2-fsa), Forkgram (MRsmallAgain/TelegramAndroid), optional neutron.img (neutronscott/flip2) — each listed in `wizard/catalog.json` with upstream URLs.

## Is this stable?

**No** — public alpha tag **v1.3.0-alpha.3-flip2**. Expect breakage; file issues with logs and verify summaries.
