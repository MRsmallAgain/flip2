---
name: flip2-deploy
description: Deploy or remove the Flip2 toolkit on a TCL Flip 2 (4058G) using the four tiers in pipeline/deploy/manifest.json. Use whenever the user mentions flip2 setup, the Magisk installer zip, pack-all, the system tree, de-root, deroot, a base image, or flashing system/product.
---

# Flip2 deploy tiers

`pipeline/deploy/manifest.json` is the source of truth (toolkit `1.1.0-flip2`). Components in install order: navoverlay, keypad, flipmouse, tagdrawer, launcher_overlay, launcher4, ime, forkgram, home_keys.

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
```

| Tier | Command | Result |
|------|---------|--------|
| A image | `flip2 image build-tree` | `pipeline/deploy/dist/flip2-system-tree/` merged into the user's own stock firmware |
| B installer | `flip2 installer pack --flavor full\|clean` | `flip2-installer-<flavor>-magisk.zip`, flash once in Magisk, self-removes after first boot |
| C live | `flip2 setup full` | eight adb steps, each PASS/FAIL, failures do not stop the rest |
| D bundle | `flip2 pack-all` | `flip2-packages-<version>/` plus inner `SHA256SUMS` |

`clean` is the de-root-friendly set only: Launcher4, Null Keyboard, Forkgram, home-keys. `full` adds the root modules.

## Tier C order

`flip2 setup full` runs, in this order: navoverlay install, keypad pack+push, flipmouse install, tagdrawer pack+install, launcher4 install+set-home, `ime hide-bar`, home-keys, forkgram release. Navoverlay, keypad, and tagdrawer need a reboot. After reboot: `flip2 flipmouse status` and `flip2 ime status`. Steps are idempotent.

Forkgram is downloaded from `MRsmallAgain/TelegramAndroid` tag `flip2-13.0.2.0-r1` and checksum-verified. It is never stored in this repo.

## De-root

`flip2 deroot` pushes `pipeline/deploy/installer/deroot.sh` and runs it. It flags flip2 modules for removal, stops FlipMouse, restores the stock Kika IME, and clears `keyshortcut_*`. Add `--uninstall-apks` only when the user APKs should go too. The last step is always manual: Magisk app, Uninstall, Restore Images.

What survives: Launcher4, Null Keyboard, Forkgram, home-keys, default HOME/IME. What stops working: FlipMouse, the keypad backspace remap, the nav overlay, TagDrawer's system placement.

## Image flash (do not improvise)

Read `docs/IMAGE-BUILD.md` before any partition write. The 4058G is A-only. `adb reboot bootloader` does not stay in fastboot: USB shows `0e8d:0003` then `0e8d:2000` and Android comes back. Fastbootd entry is the bootrom sequence (`~/flip2-enter-fastboot.sh`), not an adb reboot.

Never overwrite the 2048-byte EMMC_BOOT preloader header. Back up `vbmeta`, `vbmeta_system`, and `vbmeta_vendor` before flashing. Do not put a debug-signed APK in `/system/priv-app/Launcher3` (bootloop). Launcher4, the null keyboard, and TagDrawer belong in `system/app`. FlipMouse is not baked into the image. Neutron firmware and Forkgram are not redistributed from this repo.

Packaging the zips for GitHub is the `flip2-release` skill, not this one.
