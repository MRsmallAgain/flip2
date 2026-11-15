> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [MOVED.md](../../MOVED.md).
> The text below is unchanged from publication.

## Flip2 toolkit — public alpha

Turn a **TCL Flip 2** into a pocket dumbphone powerhouse: **T9 + offline voice** on the real keypad, a **virtual mouse** on the D-pad, **Tag Drawer** app launcher, a clean **custom launcher**, and a hardened **Forkgram** client — installed **one Magisk zip, one boot**, or stepped through **TCL Flip2 Manager**, with a **de-root path that actually works**.

> **Alpha disclaimer:** This is **v1.4.0-alpha.1-flip2**. Full features need **root/Magisk**. For a conservative first install use the **Tier B full installer zip** below. Read [SAFETY.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md) first.

### What's new in 1.4.0-alpha.1

- **Windows-first TCL Flip2 Manager** — release **`flip2-companion-1.4.0-alpha.1-win-x64.exe`** (NSIS + portable when built on Windows) bundles `wizard/`, host adb, and Google Platform Tools; no separate adb install for Prepare.
- **Docs:** [SETUP-WIZARD-WINDOWS.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SETUP-WIZARD-WINDOWS.md) and [SETUP-WIZARD-DETAILED.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SETUP-WIZARD-DETAILED.md) list the **`.exe` as the primary Windows path**.
- **Linux:** `flip2 companion` or AppImage unchanged.
- **Installers:** full, slim, clean, image-post Magisk zips + packages + system-tree bundle (repacked at this version).

### Quick start

**Conservative (recommended first):**

1. Download [`flip2-installer-full-magisk.zip`](https://github.com/MRsmallAgain/flip2/releases/download/v1.4.0-alpha.1-flip2/flip2-installer-full-magisk.zip) from this release.
2. Flash once in the **Magisk** app; reboot.
3. Verify with docs in the repo README.

**Windows wizard (recommended on PC):**

1. Download **`flip2-companion-*-win-x64.exe`** from this release (when published) or build with `cd companion && npm run pack:win` on Windows.
2. Run the installer → **TCL Flip2 Manager** → Base/Managed → **Start setup** → follow Prepare.

**Linux Companion:**

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
flip2 companion
```

**Verify release artifacts:**

```bash
sha256sum -c SHA256SUMS
```

### Deployment tiers

| Tier | Artifact | Notes |
|------|----------|-------|
| B full | `flip2-installer-full-magisk.zip` | Root; Sherpa voices bundled in full flavor |
| B slim | `flip2-installer-slim-magisk.zip` | Root; fetch Sherpa from catalog |
| B clean | `flip2-installer-clean-magisk.zip` | APKs + settings; de-root friendly |
| B image-post | `flip2-installer-image-post-magisk.zip` | After Tier A image flash |
| D bundle | `flip2-packages-<version>.zip` | Per-component zips + APKs |
| A tree | `flip2-system-tree-<version>.zip` | System tree for image builds |

### Not bundled in Magisk zip

- **Forkgram** GPL APK — downloaded at install from pinned release.
- **Sherpa-ONNX** models — bundled in **full** installer; slim uses catalog `sherpa-en` / `sherpa-uk`.
- **Windows Companion `.exe`** — build on Windows (`npm run pack:win`) or attach to GitHub release manually until CI ships it.

### Links

- [README](https://github.com/MRsmallAgain/flip2#readme) · [Windows setup](https://github.com/MRsmallAgain/flip2/blob/master/docs/SETUP-WIZARD-WINDOWS.md) · [Setup wizard](https://github.com/MRsmallAgain/flip2/blob/master/docs/SETUP-WIZARD.md) · [SAFETY](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md)
- Release: https://github.com/MRsmallAgain/flip2/releases/tag/v1.4.0-alpha.1-flip2
