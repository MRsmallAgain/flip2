# Default wallpaper

The flip2 build ships one wallpaper: an original anime-style dusk rooftop, drawn
procedurally so the asset is reproducible from this repo alone (no model
checkpoint, no borrowed image).

| File | Size | Purpose |
|------|------|---------|
| `pipeline/wallpaper/gen-wallpaper.py` | 14 KB | generator (PIL + numpy) |
| `pipeline/wallpaper/assets/flip2-wallpaper.png` | 321,115 B | what all tiers install |
| `pipeline/wallpaper/assets/flip2-wallpaper.jpg` | 57,191 B | lighter copy for previews |

Render size is **642×428** — the wallpaper surface this ROM reports for the
240×320 panel under the **321×428** logical size override (`dumpsys wallpaper`:
`mWidth=642 mHeight=428`). Regenerate at any size:

```bash
flip2 wallpaper gen                 # 642x428 into assets/
flip2 wallpaper gen --size 240x320  # native panel, if you drop the override
```

The generator is deterministic: it seeds its RNGs from a constant, so the same
script always produces the same PNG. Changing the picture means editing
`gen-wallpaper.py`, not touching the assets by hand.

## How it gets onto the phone

**There is no `cmd wallpaper` on this ROM.** `cmd wallpaper` returns
`No shell command implementation.`, and there is no settings key that takes a
file path. The `wallpaper` system service exists (`IWallpaperManager`, binder
slot 188) but has no shell entry point.

What the framework actually does is read a raw file at boot:

```
/data/system/users/0/wallpaper
  owner system:system   mode 600   label u:object_r:wallpaper_file:s0
```

So the install is a file copy plus an owner/mode/SELinux fixup:

```bash
flip2 wallpaper apply     # needs root (writes under /data/system)
flip2 wallpaper status    # compares the device file with the repo asset
```

There is no boot script and no first-boot hook on the live path. Verified on
donor `MRV8IJJVPRYTS4UG` on 2026-10-29: the PNG was copied into place, the
phone was rebooted, and the file came back **byte-identical** (md5
`d0eb46bc33e2751940150abf72b93c5f`); the framework also wrote a
`wallpaper_orig` sibling, which is what it does when it parses the file at
load. A screencap after the reboot matched the source image in the flat sky and
ledge regions.

**Undo:** delete `/data/system/users/0/wallpaper` (or `wallpaper_orig`) as root
and pick a wallpaper in Settings, or copy your own PNG over it the same way.

## Where each tier hooks in

| Tier | Mechanism |
|------|-----------|
| **A (image)** | Asset lands at `system/media/flip2-wallpaper.png`; the generated `first-boot.sh` copies it into `/data` once (stamp-guarded) |
| **B (installer zip)** | Asset rides in `payload/wallpaper/`; `service.sh` copies it at first boot (stamp-guarded) |
| **B (wizard)** | Page pulls `payload/wallpaper/` out of the installer zip if present; `install.sh` copies it, `verify.sh` compares it |
| **C (`flip2 setup full`)** | `step_wallpaper` calls `flip2 wallpaper apply` |
| **D (`flip2 pack-all`)** | Ships `flip2-wallpaper.png` + `apply-wallpaper.sh` |

Every path except the image tier needs root at install time, because
`/data/system/users/0` is not writable by a system file merge.

## Why it is stamp-guarded

A wallpaper is a user preference, not a build artifact. Every automatic path
writes `/data/local/flip2/.wallpaper-applied` after a successful copy and checks
for it first, so re-running an installer never replaces a background the user
has since chosen. `flip2 wallpaper apply` is deliberately **not** guarded — it
is the explicit "put the flip2 default back" command.
