# Flip2 pipeline architecture

Repeatable, modular workflows for TCL Flip2 / Gflip6 menu overlay and recovery. Repo root: **`~/.local/share/flip2`** (or **`FLIP2_ROOT`**).

## Doctrine

Stages should implement **gates** (preconditions), **logged steps**, and **validity checks** after each stage. New behavior proven in ops (`~/flip2-backups/...`) is **promoted** here rather than left as chat-only recipes. See [LESSONS-LEARNED.md](LESSONS-LEARNED.md) and [AGENT-OPERATING-DOCTRINE.md](AGENT-OPERATING-DOCTRINE.md).

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
| `flip2 display size [reset\|WxH]` | Logical size override, default `321x428` (see [DISPLAY-DPI.md](DISPLAY-DPI.md)) |
| `flip2 display status` | `wm size`, `display_size_forced`, density, font scale |
| `flip2 wallpaper apply` | Copy the default PNG to `/data/system/users/0/wallpaper` (root; reboot to show - see [WALLPAPER.md](WALLPAPER.md)) |
| `flip2 wallpaper status` | Compare the device wallpaper with `pipeline/wallpaper/assets/` |
| `flip2 wallpaper gen` | Regenerate the asset from `gen-wallpaper.py` |
| `flip2 tagdrawer pack` | F-Droid APK → Magisk zip |
| `flip2 tagdrawer install` | System app module + remove AppShelf; reboot |
| `flip2 tagdrawer rollback` | Remove `flip2_pixel_tag_drawer` module |
| `flip2 tagdrawer status` | Zip, `pm path`, Up key |
| `flip2 ci` | Run the device-free gates (same script CI runs) |

### Pixel Tag Drawer (system)

See [pixel-tag-drawer/README.md](../pixel-tag-drawer/README.md). D-pad Up is set in `launcher-overlay/home-keys.json` (`flip2 home-keys`).

## Gates

Everything that can be checked without a phone lives in `pipeline/ci/gates.sh`:
shell syntax across every tracked script (`bin/flip2` and the Magisk
`update-binary` files included, since they are bash without a `.sh` suffix), ES
module syntax across the wizard and Companion `.js`, JSON validity, and the two
generator drift checks (`wizard check`, `wizard pins --check`).

```bash
flip2 ci                                  # ~3s
bash pipeline/ci/install-hooks.sh         # run the same gates before every commit
```

`pipeline/ci/gates.sh` is the **check** stage: device-free only (fresh clone, no
adb, no AWS, no packed `dist/`). A gate that fails for environmental reasons
teaches people to ignore the whole pipeline.

The **build** stage packs the Electron Companion via `pipeline/ci/companion-pack.sh`
(smoke, Linux AppImage + unpacked dir, Windows NSIS/portable). Artifacts live under
`companion/dist/` for 14 days; they are not uploaded to the release mirror. Windows
pack uses Wine on the Linux image and is marked `allow_failure` until a Windows
runner is available.

```bash
bash pipeline/ci/companion-pack.sh smoke   # headless pill-bar smoke
bash pipeline/ci/companion-pack.sh linux   # AppImage + linux-unpacked
bash pipeline/ci/companion-pack.sh win     # .exe targets (needs Windows or Wine)
```

Both gate and pack commands print how many files they covered where relevant, so
read the count from the run rather than from this page.

## Extending

1. Add `pipeline/<name>/<stage>.sh`, source `lib/bootstrap.sh`.
2. Wire in `bin/flip2`.
3. Document stages here.
