> **2026-11-13 — the GitHub account behind these links was suspended.** Every
> `github.com/MRsmallAgain` URL below now returns 404. The toolkit itself is
> unaffected: start at <https://flip2burn.online/>, downloads under
> `https://flip2burn.online/packages/`, pins in
> <https://flip2burn.online/catalog.json>, source on
> <https://gitlab.com/mrsmallagain-group/flip2>. Details: [moved](../../MOVED.md).
> The text below is unchanged from publication.

## Flip2 toolkit — public alpha

**v1.4.0-alpha.2-flip2** — Vector Pinball (Bouncy) Flip2 controls, manifest-driven cursor block in FlipMouse, installer ships patched Bouncy.

> **Alpha disclaimer:** Full features need **root/Magisk**. Use the **Tier B full installer** below for a conservative first install. Read [SAFETY.md](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md) first.

### What's new in 1.4.0-alpha.2

- **Bouncy (Vector Pinball)** — Flip2 patch: D-pad + `SOFT_LEFT`/`SOFT_RIGHT` flippers (never swapped), optional **reset score each ball** in unlimited mode. Shipped in full/slim/clean installers as `bouncy.apk` (debug-signed; F-Droid base `*_43-fdroid.apk` kept for rebuilds).
- **`flip2 bouncy`** — `patch | release | install | install --fdroid`
- **Input policy (manifest)** — `image_policy.block_cursor_hold: true` on components emits `block_cursor_toggle_packages=` into `/data/local/flip2/gamepad.conf` on install/first-boot. **FlipMouseArcade** skips ~1s soft-key cursor toggle while those packages are foreground (ResumedActivity / mCurrentFocus detection).
- **FlipMouseArcade** — Rebuild includes config-based blocklist (no hardcoded package names in C).

### Quick start

1. Download [`flip2-installer-full-magisk.zip`](https://github.com/MRsmallAgain/flip2/releases/download/v1.4.0-alpha.2-flip2/flip2-installer-full-magisk.zip) from this release.
2. Flash in **Magisk** → reboot.
3. Menu slot **9** / catalog: **Bouncy Ball** with hardware flippers.

**Rebuild Bouncy only (dev):**

```bash
flip2 bouncy patch --no-install && flip2 bouncy release
```

### Artifacts

| File | Tier |
|------|------|
| `flip2-installer-full-magisk.zip` | B full |
| `flip2-installer-slim-magisk.zip` | B slim |
| `flip2-installer-clean-magisk.zip` | B clean |
| `flip2-installer-image-post-magisk.zip` | B image-post |
| `flip2-packages-1.4.0-alpha.2-flip2.zip` | D bundle |
| `SHA256SUMS` | checksums |

### Links

- [README](https://github.com/MRsmallAgain/flip2#readme) · [pipeline/bouncy](https://github.com/MRsmallAgain/flip2/tree/master/pipeline/bouncy) · [SAFETY](https://github.com/MRsmallAgain/flip2/blob/master/docs/SAFETY.md)
