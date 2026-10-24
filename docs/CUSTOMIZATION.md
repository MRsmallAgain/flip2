# Flip2 customization matrix

What you can change today, how, and which launcher path it applies to.

## Deploy paths

| Path | Package | Menu changes | Soft keys | Priv features |
|------|---------|--------------|-----------|---------------|
| **Stock + RRO** | `com.android.launcher3` | `flip2 apply` (live) | `flip2 home-keys` | Full (notifications, Quick Settings) |
| **Launcher4** | `com.tim.flip2.launcher4` | Rebuild + install | `flip2 home-keys` + baked defaults | Reduced (see launcher4/README.md) |

## Menu grid (slots 1–9)

| Item | Config | Stock + RRO | Launcher4 |
|------|--------|-------------|-----------|
| App per slot | `launcher-overlay/slots.json` | `flip2 apply`, `flip2 slot`, `flip2 swap` | `flip2 launcher4 build` (merge + inject) |
| Tools folder entry | `@tools` / `@string/tools_key` | same | same (baked) |
| Slot 5 safety | `lib/slot5-policy.sh` | Enforced on stock overlay sync/swap | Baked list + no slot-5 overwrite in smali |
| **Intertune (not on grid)** | `home-keys.json` **`left`** | N/A — do not put `dev.skye.intertune` in menu if you want left-key launch | Slot 5 uses **`com.android.music`** (stock-safe); Intertune via **`flip2 home-keys`** |
| Tools list arrays | `launcher-overlay/res/values/arrays.xml` | RRO | Merged at launcher4 build |
| Per-slot icons | Stock `mAllAppIconMap` + `patch-menu-icons.sh` | RRO cannot add map entries | Extend `launcher4/scripts/patch-menu-icons.sh` |

## Workspace soft keys (bottom bar)

| Key | Label strings | Action (stock) | Launcher4 |
|-----|---------------|----------------|-----------|
| Left | `notice` (+ locales) | TCL notification intent **or** `keyshortcut_leftkey` on some keys | Same strings; left key uses `keyshortcut_leftkey` where wired |
| Center | `menu` | Opens app grid | Same |
| Right (**Shortcuts**) | `shortcuts` | **Quick Settings** (priv) on keycode 2 | **Uses** `keyshortcut_rightkey` → `startShortcutsApp` (see `home-keys.json`) |

Configure right/left/up/down launches:

```json
// launcher-overlay/home-keys.json
{
  "right": "Messages-com.android.mms-com.android.mms.ui.ConversationList",
  "left": null
}
```

```bash
flip2 home-keys   # Settings.Global keyshortcut_* — works on stock and Launcher4
```

Format: `Label-package-componentActivity` (hyphens separate fields).

## Other overlay resources

| Resource | File | Purpose |
|----------|------|---------|
| Bar / menu strings | `launcher-overlay/res/values/strings.xml` | Labels, `def_appmenu_position_five` |
| TCL toggles | `bools.xml` | STK, dialogs, etc. |
| Misc | `config.xml` | Small flags |

Launcher4: merged at build via `merge_overlay_res.py` (patch keys only, not whole stock `strings.xml`).

## Launcher4-only smali patches

Applied in `launcher4/scripts/build.sh`:

| Patch | Script | Effect |
|-------|--------|--------|
| Null icons | `apply-patches-to.sh` | FastBitmapDrawable / DrawableFactory |
| Slot 5 | same | No `def_appmenu_position_five` overwrite; keep `v4=4` |
| Package / provider | `retarget-manifest.sh`, `retarget-smali.sh` | Own ContentProvider authority |
| Priv skip | `skip-priv-features.sh` | No NotificationListener bind; Quick Settings disabled; Shortcuts → home-keys |
| Menu icons | `patch-menu-icons.sh` | e.g. `com.android.calculator2` → `tool_calculator` |
| Tools folder icons | `patch-tools-icons.sh` | `com.android.settings` in `mToolsIconMap`; string-key rows (e.g. Media center) get map lookup |

## Not customizable without more work

| Feature | Blocker | Possible direction |
|---------|---------|-------------------|
| Live menu edits on Launcher4 | No RRO target for launcher4 | Runtime `/data/local/flip2/slots.json` in fork |
| Full Quick Settings on Launcher4 | Priv permissions / listener | Keep disabled or stub UI |
| Notification badges on workspace | NotificationListener | Accept gap or platform-signed build |
| In-grid long-press edit | RRO cannot patch smali | Fork only |
| Platform-signed system launcher | No OEM keys | Magisk fork (risky) or **image build** with your keys |

## Recommended workflow before image build

1. **Freeze menu** in `slots.json`; verify on Launcher4 (`build` + `install`).
2. **Set soft keys** in `home-keys.json`; run `flip2 home-keys`; test Shortcuts (no crash, opens chosen app).
3. **Document icon map** for any non-stock menu packages in `patch-menu-icons.sh`.
4. **Choose default HOME** for production image: stock + overlay vs baked Launcher4 vs priv-app fork.
5. See **[IMAGE-BUILD-READINESS.md](IMAGE-BUILD-READINESS.md)** checklist.
