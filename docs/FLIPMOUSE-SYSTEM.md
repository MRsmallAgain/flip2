# System-domain FlipMouse (Tier A)

Goal: run the FlipMouse daemon as an **`init` service** with a dedicated SELinux domain so pointer mode survives **Magisk → Restore Images** (no root).

Magisk FlipMouse opens `/dev/input/event*` as root from `service.sh`. A system bake requires:

| Piece | Path in merge tree |
|-------|-------------------|
| Binary | `system/bin/flip2-mouse` (same NDK build as Magisk `mouse`) |
| Init rc | `system/etc/init/flip2-mouse.rc` (`late_start`, `seclabel`) |
| Policy | Vendor/system sepolicy fragments + `file_contexts` (device-specific) |

## Donor spike (required before trusting the tree)

1. Build: `flip2 flipmouse build` then `flip2 flipmouse build-system` (when implemented).
2. Merge tree; flash `super`; boot without Magisk FlipMouse module.
3. Collect AVC denials while starting the service:
   ```bash
   adb shell su -c 'dmesg | grep avc'   # or logcat -b events
   ```
4. Minimal `audit2allow` rules for domain `flip2_mouse` (name TBD on device).
5. After **Restore Images**, confirm `flip2-mouse` still runs and toggle works.

## Fallback

If monolithic SELinux on 4058G blocks uinput/input access:

- Keep **Magisk FlipMouse** on lab units only.
- Hardened image tier: D-pad only; omit system FlipMouse from `build-tree` until policy is proven.

## Related

- [IMAGE-BUILD.md](IMAGE-BUILD.md) — `image-post` installer after `first-boot.sh`
- `pipeline/flipmouse/` — vendored source + Magisk bundle
- Manifest: `flipmouse` lists tier `"image"` for tree inclusion; tier `"full"` for Magisk zip only
