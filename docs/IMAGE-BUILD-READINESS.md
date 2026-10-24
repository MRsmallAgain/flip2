# Image build readiness (Flip2 launcher customization)

Use this checklist before baking Flip2 launcher work into a **device image** (AOSP/TCL tree, preinstall APK, or Magisk in factory flash).

## Customization options — status

| Option | Ready? | Notes |
|--------|--------|-------|
| Menu slots 1–9 from JSON | **Yes** | `slots.json` → overlay sync or launcher4 merge |
| Swap / slot CLI | **Yes** | Stock: `flip2 swap`; L4: edit JSON + rebuild |
| Slot 5 crash guard | **Yes** | Policy on stock; smali on L4 |
| Tools list / bools / strings | **Yes** | Overlay res; merged on L4 build |
| Calculator (and map) menu icons | **Partial** | Add packages to `patch-menu-icons.sh` as needed |
| Workspace bar labels | **Yes** | `strings.xml` + locale sync on L4 |
| Shortcuts soft key (right) | **Yes** | `home-keys.json` + `flip2 home-keys`; L4 uses `keyshortcut_rightkey` |
| Left Notifications | **Partial** | TCL intent; optional `keyshortcut_leftkey` |
| Full Quick Settings panel | **No** on L4 | Priv-only; disabled in user APK |
| Notification listener / badges | **No** on L4 | Disabled for installability |
| Live menu without rebuild (L4) | **No** | Future: runtime JSON in fork |
| RRO on Launcher4 | **N/A** | Target is `com.android.launcher3` only |

## Pre-image decisions

1. **Default HOME app** — Stock + RRO (A), preinstalled Launcher4 (B), or platform-signed priv fork (C).
2. **Signing** — debug for dev; platform/release for image priv-app or preinstall.
3. **Config source of truth** — ship `slots.json` + `home-keys.json` on device; L4 bakes menu at `flip2 launcher4 build`.
4. **Soft keys** — `flip2 home-keys` or first-boot equivalent for `Settings.Global`. `flip2 launcher4 install` runs home-keys when `home-keys.json` exists.

## Verification gate

- [ ] Menu grid; slot 5; icons for custom packages
- [ ] Bar labels (en-US + locales if shipped)
- [ ] **Shortcuts** opens `home-keys.json` **right** — no reload
- [ ] Stock Launcher3 remains fallback HOME

## Porting Launcher4 into an image tree

1. Vendor `launcher4/` scripts; CI runs `flip2 launcher4 build` with pinned stock APK.
2. Install `dist/launcher4.apk` to product partition; set default HOME if desired.
3. Do **not** replace priv-app Launcher3 with debug-signed APK without platform sign.

See **[CUSTOMIZATION.md](CUSTOMIZATION.md)** and **[launcher4/README.md](../launcher4/README.md)**.
