# TCL Flip2 Manager

The Companion window is the manager. Everything is one scrolling page. **Getting started** is at the top: five workflow cards (Base setup, Check phone, Managed MDM, Reboot/power-cycle, Advanced erase/root) with buttons that scroll to Phone, Profile, Apps, Prepare, or the rooting slice. The pill bar is five anchors on that same page: Getting started, Phone, Profile, Apps, and Prepare. After Apps, Prepare continues in order: the credit gate, the file table, udev, connect, install, and verify.

## Profiles

Canonical list: `pipeline/deploy/profiles.json`. The page fetches `wizard/profiles.json`, which must stay a byte-for-byte copy (`cmp -s`).

- **base** is today's install: nav overlay, keypad backspace, FlipMouse, Tag Drawer, launcher overlay, Launcher4, Null Keyboard, Forkgram, Material Files, Intertune, Bouncy, home keys, 321×428, wallpaper, Whisper, and Vosk.
- **managed** is base plus the pinned Headwind launcher and Where. Device owner is not part of Apply. In the Profile section, Managed also has flags: **Disable camera** (`com.tcl.camera`) and **Disable browsers** (`org.chromium.chrome`, `com.mediatek.op07.browser`). Both default on. A checked flag writes `block_camera` or `block_browser` into `profile.list` and Apply runs `pm disable-user`. An unchecked flag writes `enable_camera` or `enable_browser` and Apply runs `pm enable`. The APKs stay installed.
- **secure** is visible and not selectable. The GrapheneLite/GraphineLite branch is not in this repo. Do not invent that OS image, and do not flash a system image for it.

Apply writes `/data/local/flip2/profile.list` (one component id per line, then any managed flag lines, trailing newline) and installs what that list names. It does not uninstall extras and it does not wipe the phone.

A missing `profile.list` means full base, and Headwind is skipped. A listed component whose incoming file is missing is still a failure. Wallpaper image absence stays a note. An unlisted component is a note, not a failure.

Host adb Apply writes the list after prepare and before the incoming push. WebUSB is unchanged and does not write `profile.list`. Managed Apply from a plain browser stops and asks for Flip 2 Companion. A base Apply from the browser still pushes the base set.

## Adding a profile or a component

1. Add the component to `pipeline/deploy/manifest.json` when it is a real install artifact. Give it tier `managed` (or a new tier name). Do not add tier `full` or `wizard` unless it should ship inside the base installer.
2. Add a catalog pin in `wizard/catalog.json` when the component needs a file. Leave the URL off unless the bytes are a pinned upstream you intend to fetch.
3. Map the component in `wizard/pages/js/profiles.js` (`COMPONENT_META` and `CATALOG_FOR`). `catalogIds()` is the only list Apply and the download gate should use. Neutron is never an Apply id.
4. Name it from `profiles.json`: `components` on a profile like base, or `extends` plus `adds` like managed.
5. Copy `pipeline/deploy/profiles.json` onto `wizard/profiles.json` and check `cmp -s`.
6. If the component is base (tier `full` or `wizard`), update the generators and run `bash pipeline/wizard/render.sh all`.

Headwind is tier `managed` only. Its install and verify blocks stay **after** `# END GENERATED` in `wizard/device/install.sh` and `wizard/device/verify.sh`. Do not move them inside the markers, and do not add tier `full`. The next render rewrites everything between the markers and would delete a hand-written guard placed there. `render.sh` and `gen-pipeline-js.sh` emit only tiers `full` and `wizard`, so regenerating them does not pull Headwind into `requiredIncoming`.

Neither script calls `dpm`. Neither script wipes the phone.

## Headwind pin

Local file only. It is not stored in git.

`~/Downloads/com.hmdm.launcher_15400.apk`

- size 6281971
- sha256 `f674eeec9180b88af7be6fa8a696351d1931071da5bb1da0bbb4d410255c0b6e`
- catalog id `headwind-launcher`, incoming name `headwind.apk`, package `com.hmdm.launcher`

There is no download URL. Companion matches a file already on this PC by that SHA-256. Do not pin `hmdm-6.40-os.apk`. Do not download the pager, restarter, or helper until new hashes exist.

Installing the APK does not set device owner.

## Where pin

Local file only (managed profile).

`~/Downloads/net.af0.where_1471.apk`

- size 11443012
- sha256 `1cd385c35b23248a0f439c9cd1efe4d2027c0b4f6f77050cb456d2ffe25f410c`
- abi `armeabi-v7a`, versionName `2026.10.14.2`, versionCode `1471`
- catalog id `where-app`, incoming name `where.apk`, package `net.af0.where`

Installed by Managed Apply with Headwind. Post-reset MDM policy: [MANAGED-MDM-SETUP.md](MANAGED-MDM-SETUP.md). Contacts/SMS after wipe: [RESTORE-CONTACTS-SMS.md](RESTORE-CONTACTS-SMS.md).

## Device owner

Separate from Apply. The button is on the Apps step when Managed is selected. The user types `manage`. Companion then runs:

`dpm set-device-owner com.hmdm.launcher/.AdminReceiver`

That receiver is the one in the 15400 APK. The main process ignores any other component string from the page.

Prechecks live in the main process: the package is installed, no device owner is already set, and `dumpsys account` shows no accounts. If accounts exist, factory reset stays on the phone. Back up to `~/flip2-pre-wipe-backup` and reset on the phone. This app never wipes userdata over USB and does not edit `/data/system/device_policies.xml`.

If uninstall returns `DELETE_FAILED_DEVICE_POLICY_MANAGER`, the Apps step shows that and stops. Break-glass steps stay in `docs/HEADWIND-MDM-RECOVERY.md`.

## Remove root and USB debugging

Separate from Apply, and not a `profile.list` id. The block stays on the Apps step for Base and Managed. The user types `unroot`. Companion requires `su` to return uid 0, then marks these module directories with `touch remove` when they exist:

- `flip2_nav_overlay`
- `flip2_keypad_backspace`
- `FlipMouse`
- `flip2_pixel_tag_drawer`
- `flip2_launcher_overlay`
- `flip2_launcher3_null_icon_fix`

A missing directory is skipped. If a touch fails, USB debugging stays on. FlipMouse is stopped. Companion then sets `development_settings_enabled` to 0 and, last, `adb_enabled` to 0. Turning USB debugging off ends the management channel. Companion cannot turn it back on.

This stage does not run `pipeline/deploy/installer/deroot.sh`. That script also restores the stock IME and clears home-key settings. Apps stay installed. The IME and home keys stay as they are. The phone is not rebooted, not wiped, and `/data/system/device_policies.xml` is not edited. The Magisk boot image is not restored. On the phone afterward: Magisk, Uninstall, Restore Images, then reboot. Unchecking a profile flag cannot restore Magisk or USB debugging.

After USB debugging is off, Headwind recovery over adb is gone. Lockout recovery remains a factory reset on the phone.

## Personal backup

The Apps step saves and restores catalog apps, contacts, and messages through Flip 2 Companion. Files live in `~/flip2-personal-backup`. `factoryReadBackup` cannot read that directory. Backup and restore need USB debugging and root. Do this before removing root. It does not wipe the phone, set device owner, or remove root.

- `apps/<package>.apk` — catalog packages that were installed
- `contacts2.db` — version-checked byte copy, `user_version` 1401. Names live on `raw_contacts.display_name` and the mime name rows.
- `mmssms.db` — rebuilt by `build-messages`, `user_version` 670020, no attachments
- `manifest.json` — integer counts only

`~/flip2-pre-wipe-backup/readable/` remains a restore source for `contacts2.db` and `mmssms.db`. The call log is not included. The Apps step shows counts only (named, blank, data; sms, threads, inbox, sent; app count). It does not print names, numbers, or message bodies. Details: [RESTORE-CONTACTS-SMS.md](RESTORE-CONTACTS-SMS.md).

## What v1 will add or remove

Catalog packages and the five Magisk module ids only. There is no arbitrary APK sideload. Module install is part of Apply. There is no single-module place action, and module install is not sent through a shell command. Module remove deletes `/data/adb/modules/<id>` for an allowlisted id and asks for a reboot. It does not reboot by itself.

Launcher4 and Null Keyboard ask for an extra confirm, because Home or the keyboard falls back. Settings rows (home keys, display, wallpaper, Whisper, Vosk) are part of Apply and have no Remove button.

Neutron is the rooting slice only. Apply does not require it. Rooting stays behind typing `erase`. Return to factory stays behind typing `factory`. Neither slice flashes `super`, `vbmeta`, system, product, or the preloader.

## Companion smoke

From `companion/`:

`npm run start:safe -- --smoke`

Expect the page title `TCL Flip2 Manager`, one scrolling page with five anchors (Getting started, Phone, Profile, Apps, Prepare), catalog length 12, no missing factory ids, the factory gate locked, and `factoryReadBackup("/etc/passwd")` refused. No phone is required.
