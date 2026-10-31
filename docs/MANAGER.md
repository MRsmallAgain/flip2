# TCL Flip2 Manager

The Companion window is the manager. **Getting started** is the default landing tab: five workflow cards (Base setup, Check phone, Managed MDM, Reboot/power-cycle, Advanced erase/root) with jump buttons into Phone, Profile, Apps, Prepare, and the rooting slice. The pill bar is Getting started, Phone, Profile, Apps, and Prepare. Prepare is the credit gate, the file table, udev, connect, install, and verify.

## Profiles

Canonical list: `pipeline/deploy/profiles.json`. The page fetches `wizard/profiles.json`, which must stay a byte-for-byte copy (`cmp -s`).

- **base** is today's install: nav overlay, keypad backspace, FlipMouse, Tag Drawer, launcher overlay, Launcher4, Null Keyboard, Forkgram, Material Files, Intertune, Bouncy, home keys, 321×428, wallpaper, Whisper, and Vosk.
- **managed** is base plus the pinned Headwind launcher. Device owner is not part of Apply.
- **secure** is visible and not selectable. The GrapheneLite/GraphineLite branch is not in this repo. Do not invent that OS image, and do not flash a system image for it.

Apply writes `/data/local/flip2/profile.list` (one component id per line, trailing newline) and installs what that list names. It does not uninstall extras and it does not wipe the phone.

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

`~/Downloads/net.af0.where_1404.apk`

- size 14791436
- sha256 `cfc1a50142d338f5f9199783943f844f184950e34ba6635f5cb89e5b9f4d9cd6`
- catalog id `where-app`, incoming name `where.apk`, package `net.af0.where`

Installed by Managed Apply with Headwind. Post-reset MDM policy: [MANAGED-MDM-SETUP.md](MANAGED-MDM-SETUP.md). Contacts/SMS after wipe: [RESTORE-CONTACTS-SMS.md](RESTORE-CONTACTS-SMS.md).

## Device owner

Separate from Apply. The button is on the Apps step when Managed is selected. The user types `manage`. Companion then runs:

`dpm set-device-owner com.hmdm.launcher/.AdminReceiver`

That receiver is the one in the 15400 APK. The main process ignores any other component string from the page.

Prechecks live in the main process: the package is installed, no device owner is already set, and `dumpsys account` shows no accounts. If accounts exist, factory reset stays on the phone. Back up to `~/flip2-pre-wipe-backup` and reset on the phone. This app never wipes userdata over USB and does not edit `/data/system/device_policies.xml`.

If uninstall returns `DELETE_FAILED_DEVICE_POLICY_MANAGER`, the Apps step shows that and stops. Break-glass steps stay in `docs/HEADWIND-MDM-RECOVERY.md`.

## What v1 will add or remove

Catalog packages and the five Magisk module ids only. There is no arbitrary APK sideload. Module install is part of Apply. There is no single-module place action, and module install is not sent through a shell command. Module remove deletes `/data/adb/modules/<id>` for an allowlisted id and asks for a reboot. It does not reboot by itself.

Launcher4 and Null Keyboard ask for an extra confirm, because Home or the keyboard falls back. Settings rows (home keys, display, wallpaper, Whisper, Vosk) are part of Apply and have no Remove button.

Neutron is the rooting slice only. Apply does not require it. Rooting stays behind typing `erase`. Return to factory stays behind typing `factory`. Neither slice flashes `super`, `vbmeta`, system, product, or the preloader.

## Companion smoke

From `companion/`:

`npm run start:safe -- --smoke`

Expect the page title `TCL Flip2 Manager`, four front-door steps, catalog length 11, no missing factory ids, the factory gate locked, and `factoryReadBackup("/etc/passwd")` refused. No phone is required.
