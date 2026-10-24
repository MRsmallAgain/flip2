# Flip2 pipeline architecture

Repeatable, modular workflows for TCL Flip2 / Gflip6 menu overlay and recovery. Repo root: **`~/.local/share/flip2`** (or **`FLIP2_ROOT`**).

## Layout

```
flip2/
├── bin/flip2                 # CLI entry point
├── lib/                      # Shared shell modules
│   ├── bootstrap.sh          # source all libs
│   ├── paths.sh              # FLIP2_ROOT, FLIP2_OVERLAY, FLIP2_PATCH
│   ├── constants.sh          # package names, Magisk ids, APK sizes
│   ├── env.sh                # JAVA_HOME, ANDROID_SDK, apktool tools
│   └── adb.sh                # wait boot, require device, restart launcher
├── pipeline/
│   ├── overlay/
│   │   ├── sync-slots.sh     # Stage: slots.json → XML
│   │   └── apply.sh          # Full: sync → build → sign → install → enable
│   └── recovery/
│       └── resolve.sh        # Remove bad Magisk mod → stock Launcher3 → overlay apply
├── launcher-overlay/         # RRO package + build scripts
├── launcher-patch/           # Withdrawn launcher patch + recovery helpers
└── docs/
```

## Pipelines

### Menu overlay

| Stage | Script | Input | Output |
|-------|--------|-------|--------|
| Sync | `pipeline/overlay/sync-slots.sh` | `slots.json` | `arrays.xml`, slot 5 string |
| Build/install | `launcher-overlay/scripts/sign-and-install.sh` | res | APK on device |
| Enable | `launcher-overlay/scripts/after-root-enable.sh` | root | idmap, STATE_ENABLED |

```bash
flip2 apply
flip2 slot 5 com.android.music
```

### Recovery

Do **not** install `flip2_launcher3_icon_fix` Magisk module on Flip2.

```bash
flip2 recovery
```

Stages: remove `flip2_launcher3_null_icon_fix` → restore stock Launcher3 if patched size (5029914) → reboot if needed → `flip2 apply`.

## CLI

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
```

| Command | Action |
|---------|--------|
| `flip2 apply` | Full overlay pipeline |
| `flip2 slot N PKG` | One slot + apply |
| `flip2 editor` | Web UI + adb reverse |
| `flip2 recovery` | Post-crash recovery |
| `flip2 pack-overlay` | Magisk zip for RRO only |
| `flip2 home-keys` | Settings.Global shortcuts |
| `flip2 tagdrawer pack` | F-Droid APK → Magisk zip |
| `flip2 tagdrawer install` | System app module + remove AppShelf; reboot |
| `flip2 tagdrawer rollback` | Remove `flip2_pixel_tag_drawer` module |
| `flip2 tagdrawer status` | Zip, `pm path`, Up key |

### Pixel Tag Drawer (system)

See [pixel-tag-drawer/README.md](../pixel-tag-drawer/README.md). D-pad Up is set in `launcher-overlay/home-keys.json` (`flip2 home-keys`).

## Prerequisites

adb (authorized), root (idmap), JDK, SDK build-tools 34, apktool.

## Extending

1. Add `pipeline/<name>/<stage>.sh`, source `lib/bootstrap.sh`.
2. Wire in `bin/flip2`.
3. Document stages here.
