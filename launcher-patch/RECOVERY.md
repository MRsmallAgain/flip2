# Recover from homescreen crash loop (launcher Magisk module)

**Phone frozen / touch dead?** → [EMERGENCY-unresponsive.md](EMERGENCY-unresponsive.md) (hard reboot, Magisk safe mode, adb loop).

If the phone **flashes / crashes on the homescreen** after installing `flip2_launcher3_icon_fix`, disable that module and reboot. Stock Launcher3 will load again.

## Fastest: Magisk app on the phone

1. When the UI is up long enough, open **Magisk**.
2. **Modules** → **Flip2 Launcher3 null icon fix** → turn **off** or **Remove**.
3. **Reboot**.

If Magisk is hard to open, try from **Quick Settings** or right after unlock.

## ADB (when USB works on your PC)

```bash
adb shell su -c 'touch /data/adb/modules/flip2_launcher3_null_icon_fix/disable'
adb reboot
```

Or remove entirely:

```bash
adb shell su -c 'rm -rf /data/adb/modules/flip2_launcher3_null_icon_fix'
adb reboot
```

## No Magisk / no ADB

- Boot and open **Magisk** from the app drawer if another launcher or Settings is reachable.
- Some builds: hold **power** → **Reboot to safe mode** (modules often disabled) → disable module in Magisk → normal reboot.

## After recovery

- Menu slots from the **overlay** (`com.tim.flip2.launcheroverlay`) are unchanged.
- Keep slot 5 on a **stock app** (e.g. Music) until we ship a fix that does **not** replace the whole platform-signed `Launcher3.apk`.
- Do **not** re-flash `flip2_launcher3_icon_fix-magisk.zip` without reading [README.md](README.md) — that approach is **withdrawn** for Flip2.

## Why it happened

The module overlays `/system/priv-app/Launcher3/Launcher3.apk` with an **apktool rebuild signed by the debug key**. The stock launcher is **platform-signed** and a priv-app; replacing the file with a different signature often makes Launcher3 fail to start or crash in a loop, even under Magisk.
