# Headwind MDM (HMDM) recovery on Flip2

When **Headwind MDM** (`com.hmdm.launcher`) was enrolled as **device admin**, Android blocks uninstall with `DELETE_FAILED_DEVICE_POLICY_MANAGER` and `dpm remove-active-admin` fails unless the app is `android:testOnly` (Headwind is not).

## What we saw on donor (2026-10-29)

| Check | Result |
|-------|--------|
| `dumpsys device_policy` | **Active admin** `com.hmdm.launcher/.AdminReceiver`, **no device owner** in dump |
| `/data/system/device_owner_2.xml` | Missing |
| `/data/system/device_policies.xml` | Had `<admin name="com.hmdm.launcher/...">` |
| `userRestrictions` in dump | **null** — Wi‑Fi / uninstall not blocked at OS level |

Packages: `com.hmdm.launcher`, `com.hmdm.emuilauncherrestarter`, `com.hmdm.pager`.

## Fix (requires Magisk/root `su`)

1. Backup and remove the `<admin>` block from `/data/system/device_policies.xml` (keep `setup-complete="true"`).
2. **Reboot** so DPM reloads the file.
3. `adb shell pm uninstall` the three `com.hmdm.*` packages.

## Safer alternatives

- Headwind server retire/remove device if it still checks in.
- Factory reset clears admin (wipes userdata).
