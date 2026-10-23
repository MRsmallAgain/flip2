# Flip2 toolkit (TCL Gflip6 / Flip 2)

Modular, pipeline-driven tooling for **built-in menu grid (slots 1–9)**, **Launcher3 RRO overlay**, and **recovery** after bad Magisk launcher experiments.

**Quick start**

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
flip2 apply                    # push menu slots from slots.json
flip2 slot 5 com.android.music
flip2 editor                   # http://127.0.0.1:8765
```

Requires: USB debugging, **root** (overlay idmap), JDK + Android SDK build-tools, **apktool**.

## Architecture

| Area | Path | Role |
|------|------|------|
| CLI | `bin/flip2` | Single entry for all pipelines |
| Libraries | `lib/*.sh` | Paths, env, adb, constants |
| Overlay pipeline | `pipeline/overlay/` | `sync-slots` → build/install/enable |
| Recovery pipeline | `pipeline/recovery/` | Stock launcher + overlay after crash |
| RRO project | `launcher-overlay/` | `slots.json`, APK resources, Magisk pack |
| Launcher patch | `launcher-patch/` | **Withdrawn** whole-APK Magisk fix — see RECOVERY.md |

Full design: **[docs/PIPELINE.md](docs/PIPELINE.md)** · shared libs: **[docs/MODULES.md](docs/MODULES.md)**

## Menu grid (MVP)

Edit **`launcher-overlay/slots.json`** (keys `1`–`9`, `@tools` for Tools folder). Then:

```bash
flip2 apply
```

Or one slot:

```bash
flip2 slot 7 org.chromium.chrome
```

**Homescreen** soft keys (Notifications / Menu / Shortcuts) are separate; use `home-keys.json` + `flip2 home-keys`.

## Do not use

- **`launcher-patch/dist/flip2_launcher3_icon_fix-magisk.zip`** — debug-signed Launcher3 replace caused homescreen crash loops. Use **`flip2 recovery`** if it was installed.

## Boot / fastboot (Linux)

- `autobooter-linux.py`, `mtk-bootseq.py`, `~/flip2-enter-fastboot.sh` — see [flip2 wiki](https://github.com/neutronscott/flip2/wiki).

## Legacy scripts

These delegate to the pipeline where noted:

| Script | Prefer |
|--------|--------|
| `launcher-overlay/scripts/apply-slots.sh` | `flip2 apply` |
| `launcher-overlay/scripts/edit-slot.sh` | `flip2 slot` |
| `launcher-patch/scripts/resolve-after-recovery.sh` | `flip2 recovery` |
| `~/flip2-launcher-editor.sh` | `flip2 editor` |
| `~/flip2-resolve.sh` | `flip2 recovery` |

## udev (adb on Linux)

```bash
sudo cp launcher-patch/scripts/51-android-flip2-adb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Vendor **1bbb:0c01** (T & A Mobile).
