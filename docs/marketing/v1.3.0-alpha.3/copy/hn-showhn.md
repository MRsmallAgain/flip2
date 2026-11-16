> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [moved](../../MOVED.md).
> The text below is unchanged from publication.

**Title:** Show HN: Flip2 toolkit – TCL Flip 2 dumbphone stack with pinned WebUSB wizard

**URL:** https://github.com/MRsmallAgain/flip2

**First comment (paste after submit):**

Flip2 is pipeline-driven tooling for the **TCL Flip 2** (MediaTek flip phone). One `manifest.json` drives four deployment tiers:

- **A** — merge system tree into your firmware image
- **B** — one Magisk installer zip (full/clean/slim)
- **C** — live `adb` setup on an already-rooted phone
- **D** — release package bundle + SHA256SUMS

The interesting bit for HN: **TCL Flip2 Manager** is a static site + **WebUSB** push of hash-verified artifacts (`catalog.json` pins exact byte size + SHA-256; browser verifies with WebCrypto before flash). Optional **erase-gated** rooting slice talks **Web Serial** to `autobooter-linux.py` and only ever flashes hash-verified `boot` — no path to other partitions by construction.

**De-root** is a first-class story: installer drops `/data/local/flip2/deroot.sh` so cleanup works even after Magisk is gone; README table lists what survives vs what legitimately dies.

**v1.3.0-alpha.3-flip2** (Latest on GitHub): Manager UX refresh, Arcade profile (experimental), Tag Drawer verify fixes.

- Releases: https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2
- Wizard: `wizard/` — must be HTTP-served; Linux Chrome proven
- Safety: `docs/SAFETY.md` before unlock/flash

Alpha software; full tier needs root. Conservative path = Tier B **full** zip, not experimental wizard install.

Happy to answer questions on pins, pipeline layout, or MTK fastboot ergonomics on Linux.
