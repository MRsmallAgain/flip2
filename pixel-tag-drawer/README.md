# Pixel Tag Drawer (system app)

[F-Droid](https://f-droid.org/packages/com.iwadjp.pixeltagdrawer/) tag-based app drawer, shipped as a Magisk overlay at `/system/app/PixelTagDrawer/PixelTagDrawer.apk`.

**Package:** `com.iwadjp.pixeltagdrawer`  
**Main activity:** `com.iwadjp.pixeltagdrawer.MainActivity`

## D-pad Up

Configured in `launcher-overlay/home-keys.json` and applied with `flip2 home-keys`:

```text
Tags-com.iwadjp.pixeltagdrawer-com.iwadjp.pixeltagdrawer.MainActivity
```

## Commands

| Command | Action |
|---------|--------|
| `flip2 tagdrawer pack` | Download F-Droid APK (if missing), copy into Magisk module tree, zip `dist/flip2_pixel_tag_drawer-magisk.zip` |
| `flip2 tagdrawer install` | Uninstall AppShelf packages, push zip, `magisk --install-module`, reboot required |
| `flip2 tagdrawer rollback` | Remove `/data/adb/modules/flip2_pixel_tag_drawer` |
| `flip2 tagdrawer status` | Pack path, `pm path`, module dir, `keyshortcut_upkey` |

## Rollback

After rollback, reboot. Re-install user APK from F-Droid if you want the drawer without the system module.
