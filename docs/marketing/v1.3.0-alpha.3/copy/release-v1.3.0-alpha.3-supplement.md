> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [moved](../../MOVED.md).
> The text below is unchanged from publication.

## Flip2 toolkit — public alpha

Turn a **TCL Flip 2** into a pocket dumbphone powerhouse: **T9 + offline voice** on the real keypad, a **virtual mouse** on the D-pad, **Tag Drawer** app launcher, a clean **custom launcher**, and a hardened **Forkgram** client — installed **one Magisk zip, one boot**, or stepped through **TCL Flip2 Manager** on Chrome/Linux, with a **de-root path that actually works**.

> **Alpha disclaimer:** This is **v1.3.0-alpha.3-flip2**. Full features need **root/Magisk**. The browser wizard **Put on phone** step is **experimental**; for a conservative first install use the **Tier B full installer zip** below. Read [SAFETY.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md) first. **Chrome on Linux** for the WebUSB wizard path.

### What's in this release

- **TCL Flip2 Manager** — Base/Managed profiles, six-step Prepare, pinned SHA-256 catalog downloads
- **Installers:** full, slim, clean, image-post Magisk zips + system-tree and packages bundle
- **Arcade profile** (experimental) — checkbox gate before setup
- Tag Drawer verify fixes; FlipMouse Arcade in Tier D bundle

### Screenshots

Homescreen · menu grid · Tag Drawer · null-keyboard IME — see `docs/screenshots/` and marketing press kit.

### Quick start

**Conservative (recommended first):**

1. Download [`flip2-installer-full-magisk.zip`](https://github.com/MRsmallAgain/flip2/releases/download/v1.3.0-alpha.3-flip2/flip2-installer-full-magisk.zip) from this release.
2. Flash once in the **Magisk** app; reboot.
3. Verify with docs in the repo README.

**Explorer (Linux + Chrome):**

```bash
cd flip2/wizard && python3 -m http.server 8000
# http://127.0.0.1:8000/pages/ — follow Prepare; type yes on Ready
```

**Verify release artifacts:**

```bash
sha256sum -c SHA256SUMS
```

### Links

- [README](https://github.com/MRsmallAgain/flip2#readme) · [Setup wizard](https://github.com/MRsmallAgain/flip2/blob/master/docs/SETUP-WIZARD.md) · [Manager profiles](https://github.com/MRsmallAgain/flip2/blob/master/docs/MANAGER.md) · [SAFETY](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md)
- Release: https://github.com/MRsmallAgain/flip2/releases/tag/v1.3.0-alpha.3-flip2

### Third-party credits

Sherpa-ONNX ASR models (k2-fsa), Forkgram patch (MRsmallAgain/TelegramAndroid), optional neutron boot image (neutronscott/flip2) — see `wizard/catalog.json` upstream fields for each pin.
