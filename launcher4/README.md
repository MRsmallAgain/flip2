# Flip2 Launcher4 (user APK)

Patched stock Launcher3 as **`com.tim.flip2.launcher4`**: null-safe icons, slot 5 from `allapp_list` (no Chrome crash), menu baked from `launcher-overlay/slots.json`.

**Does not** replace `/system/priv-app/Launcher3`. Install with `adb install -r`, then pick this app as **Home**. Stock Launcher3 stays on the system partition as fallback.

## Why not Magisk fork?

Debug-signed APK swapped into `system/priv-app` caused boot loops / "System is starting" on this device. Launcher4 avoids that by being a normal user-installed launcher competing on the HOME intent.

## Commands

```bash
flip2 launcher4 build        # extract stock → patches → retarget manifest → sign
flip2 launcher4 install      # adb install -r (USB authorized)
flip2 launcher4 set-home     # default home picker / cmd package set-home-activity
flip2 launcher4 uninstall    # remove package; set Home back to stock in Settings
flip2 launcher4 status       # local APK + pm path on device
```

Stock APK source: `launcher-fork/stock/Launcher3.apk` (5027417 bytes reference).

## Rollback

1. `flip2 launcher4 uninstall`
2. Settings → Default apps → Home → **Launcher3** (stock)
3. Menu tiles on stock: `flip2 apply` (RRO overlay) still works

## Why it can look like stock Launcher3

- **`flip2 apply` / RRO** only targets **`com.android.launcher3`**. With Launcher4 as HOME, the Magisk overlay does **nothing** to what you see.
- Your **`slots.json`** may match TCL’s default grid (Dialer, Messages, …), so the **Menu** looks identical even when baked correctly.
- What **is** different in Launcher4: separate package, **Flip2 Launcher4** label, null-safe icons, slot 5 from `allapp_list` (no forced Music overwrite), no priv notification listener.

## Rebuild after menu / overlay changes

1. Edit **`launcher-overlay/slots.json`** (and overlay `strings.xml` / `bools.xml` if you use them).
2. **`flip2 launcher4 build`** — runs `sync-slots.sh` and **merges overlay values** into the APK.
3. **`flip2 launcher4 install`**

To **see** a menu change quickly: e.g. `flip2 slot 1 com.android.calculator2` then rebuild/install (or edit `slots.json` and rebuild).

## Limits

- Some priv-only permissions were stripped for installability; notification listener is disabled (workspace notification badges may differ).
- Menu/tools strings and bools come from **build-time merge**, not live RRO.
