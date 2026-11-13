# Flip2 toolkit v1.3.0-alpha.3 — public alpha, feedback welcome

> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [MOVED.md](../../MOVED.md).
> The text below is unchanged from publication.

We just tagged **v1.3.0-alpha.3-flip2** as the latest release on [MRsmallAgain/flip2](https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2): tooling to turn a **TCL Flip 2** into a serious dumbphone setup while staying honest about alpha status and safety.

## Who this is for

- You own a **TCL Flip 2** and want **real keypad T9**, **offline STT**, a **tag-based app drawer**, **null-keyboard** full-screen apps, and a **Flip2-patched Forkgram** — without pretending the phone is a 2024 flagship.
- You're comfortable with **Magisk/root** for the full tier, or you plan to use the **clean** installer and accept what survives after de-root.
- **Linux + Chrome** users who want **TCL Flip2 Manager** (browser wizard) with **SHA-256–verified** catalog downloads over USB.

## Who this is not for (yet)

- **Firefox** users (no WebUSB).
- Anyone who wants **verified boot** or a fully stock, warrantied device — read [SAFETY.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md) before anything destructive.
- **Managed / MDM / Headwind** as a first-day story — Base profile is the default launch narrative; Managed is documented but not the headline.

## What's new in this alpha

- **TCL Flip2 Manager** UX refresh (profiles, Get files with license/source expanders, Prepare flow).
- **Arcade** profile marked **experimental** with an explicit gate.
- Installer **full / slim / clean / image-post** tiers; wizard pins target this tag.
- Tag Drawer verify + **FlipMouse Arcade** in the bundle.

## We want feedback on

1. Manager **Prepare** flow — where did you stall (udev, connect, install, verify)?
2. **Conservative zip** vs wizard — which path did you pick and why?
3. **Arcade** — interest vs noise for public docs.

**Conservative install:** [flip2-installer-full-magisk.zip](https://github.com/MRsmallAgain/flip2/releases/download/v1.3.0-alpha.3-flip2/flip2-installer-full-magisk.zip) + `sha256sum -c SHA256SUMS`.

Thanks — issues and screenshots welcome.
