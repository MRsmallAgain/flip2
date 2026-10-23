# Flip2 Launcher3 — null menu icon fix

Stock Launcher3 crashes when a menu slot uses an app whose launcher icon bitmap is null (e.g. **Bouncy** `com.dozingcatsoftware.bouncy`).

## Patch

- `FastBitmapDrawable`: 1×1 placeholder if bitmap is null; `draw()` skips null/recycled bitmaps.
- `DrawableFactory.newIcon`: same placeholder before creating the drawable.

## Build

```bash
~/.local/share/flip2/launcher-patch/scripts/pack-magisk-module.sh
```

Output: `dist/flip2_launcher3_icon_fix-magisk.zip`

## Install (Magisk) — **do not use on Flip2**

Replacing platform-signed Launcher3 with this debug-signed APK caused **homescreen crash loops** on device. See **[RECOVERY.md](RECOVERY.md)** to disable the module.

Safer path for Bouncy in the menu: keep a stock app in that slot, or wait for a fix that does not replace the whole launcher APK.

<details>
<summary>Original Magisk steps (withdrawn)</summary>

1. Copy the zip to the phone (or `adb push … /sdcard/Download/`).
2. Magisk → **Modules** → **Install from storage** → select the zip → **Reboot**.
3. After reboot, set menu slot (example slot 5 = Bouncy):

```bash
~/.local/share/flip2/launcher-overlay/scripts/edit-slot.sh 5 com.dozingcatsoftware.bouncy
```

4. Open **Menu** on the homescreen — launcher should not crash. Missing icons may show as a tiny blank tile until a better fallback is added.

</details>

## Uninstall

Disable or remove the Magisk module and reboot; stock `/system/priv-app/Launcher3/Launcher3.apk` is restored.

## Note

The patched APK is signed with the **debug** keystore. Magisk **system** overlay replaces the file on disk; the priv-app still runs as the system launcher. If the device refuses to start the launcher after install, capture `logcat` and we can adjust (e.g. SELinux or signature expectations).
