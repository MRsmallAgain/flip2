# Managed profile — Headwind MDM + Where (out of the gate)

Use this after a **factory reset** when you want Flip2 **Managed Apply** plus Headwind cloud policy without manual APK sideloads.

## Local pins (Companion)

Place these on the PC before **Managed → Apply** (Companion matches SHA-256):

| Catalog id | File | Package |
|------------|------|---------|
| `headwind-launcher` | `~/Downloads/com.hmdm.launcher_15400.apk` | `com.hmdm.launcher` |
| `where-app` | `~/Downloads/net.af0.where_1471.apk` | `net.af0.where` |

Do **not** use `hmdm-6.40-os.apk` or cloud `hmdm-6.40-master.apk` over the pinned **15400** launcher.

## Recommended order (fresh phone, no accounts)

1. **Factory reset** on the phone (Settings or recovery). Skip Google account if you plan device owner.
2. Enable **USB debugging**, authorize this PC.
3. **Flip 2 Companion** → Profile **Managed** → Files: **Use files already on this PC** (or pick pins) → **Apply** → **Verify**.
4. Reboot once if modules were placed.
5. Apps → type **`manage`** → device owner (`com.hmdm.launcher/.AdminReceiver`). Only when **no accounts** on the device.
6. Enroll in Headwind (QR / device id). Publish configuration from cloud.
7. Optional, last: **Apps** → type **`unroot`**. This marks the six Flip2 Magisk modules for removal, stops FlipMouse, and turns off USB debugging. It does not uninstall apps, does not wipe the phone, and does not restore the Magisk boot image. Do this only when you are done managing the phone. After USB debugging is off, Headwind recovery over adb is gone. The same stage applies to Base. See [MANAGER.md](MANAGER.md).

## Headwind cloud — required for MDM installs

These settings prevent the failures seen on Evie01:

| Setting | Recommended | Why |
|---------|-------------|-----|
| **`no_install_apps`** in Restrictions | **Remove** | Blocks Headwind silent install (`User restriction prevents installing`) |
| **`appPermissions`** | **`grantall`** | Avoids hung prompts on kiosk phones (`askall` waits for UI) |
| Where app | APK uploaded + **URL** in config | `"url":null` never installs |
| Launcher app on server | **15400** build only | Signature mismatch if 6.40 master is pushed |
| MDM password | Match what users can type on flip keypad | Long/complex passwords lock the device out |

### Restrictions you can keep

`no_uninstall_apps`, `no_control_apps`, kiosk/allowlist, hide Chrome/camera via **Applications** — without `no_install_apps`.

### Optional cloud apps

After Flip2 Apply installs Where, you may **omit** duplicate Where push from cloud, or keep cloud copy for updates only (with URL + no `no_install_apps`).

## Browser / camera

On the Profile tab, with **Managed** selected, two flags default on:

- **Disable camera** — `pm disable-user --user 0 com.tcl.camera`
- **Disable browsers** — the same for `org.chromium.chrome` and `com.mediatek.op07.browser`

Apply writes `block_camera` / `block_browser` into `/data/local/flip2/profile.list`. Unchecking a flag writes `enable_camera` or `enable_browser` and the next Apply runs `pm enable`. The packages stay installed. Headwind cloud can still hide the same apps later; these flags are the local Apply path and do not set device owner.

## Lockout recovery

MDM password lockout with **adb unauthorized**: factory reset from recovery (**Volume up + Power** → Wipe data). See [RESTORE-CONTACTS-SMS.md](RESTORE-CONTACTS-SMS.md) after reset.

Break-glass without wipe (root): [HEADWIND-MDM-RECOVERY.md](HEADWIND-MDM-RECOVERY.md).

After **Apps → unroot**, USB debugging is off and that adb path is gone. Lockout recovery is then a factory reset on the phone.
