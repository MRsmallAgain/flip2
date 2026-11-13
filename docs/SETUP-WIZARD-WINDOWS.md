# TCL Flip2 Manager on Windows

Windows checklist for **TCL Flip2 Manager** (Flip 2 Companion). Full step-by-step: [SETUP-WIZARD-DETAILED.md](SETUP-WIZARD-DETAILED.md). Read [SAFETY.md](SAFETY.md) first.

## Primary install — Windows `.exe` (recommended)

On Windows, use the **release installer** — not the browser wizard or a from-source `npm start` unless you are developing.

1. Build **`flip2-companion-<version>-win-x64.exe`** (NSIS installer or portable) — see the build step below. No prebuilt Windows `.exe` is published at the moment.
2. Run the installer (or the portable `.exe`). Window title: **TCL Flip2 Manager**.
3. **No separate adb install** — the app bundles Google **Platform Tools** under `resources\platform-tools\` (`adb.exe` + USB DLLs). Override only if needed with env var **`FLIP2_ADB`** pointing at another `adb.exe`.
4. Install [Google USB Driver](https://developer.android.com/studio/run/oem-usb#Drivers) (or OEM driver) so Device Manager shows the phone without a warning triangle when USB debugging is on.
5. Open **Set up** → follow **Prepare** (host adb for downloads, connect, install, verify). **Do not** run Linux udev steps on Windows.

Build the same `.exe` yourself on a Windows PC:

```powershell
cd companion
npm install
npm run pack:win
# dist\flip2-companion-<version>-win-x64.exe (NSIS + portable)
```

`prepack:win` fetches platform-tools into `companion\platform-tools-win\` automatically.

## Run from source (optional)

Only if you are hacking on Companion or no release `.exe` is published yet:

```powershell
cd companion
npm install
npm run fetch:platform-tools:win
npm start
```

Launchers set `FLIP2_ADB` to `companion\platform-tools-win\adb.exe` when present. **Node.js** required.

## Prepare differences on Windows

| Step | Windows |
|------|---------|
| **USB rules** | Not used. Companion shows driver instructions; press **Continue**. |
| **Connect** | Use **Check host adb**. Expect exactly one line ending in `device` in `adb devices`. |
| **Install / verify** | Same as Linux — host adb via Companion (not WebUSB in Edge/Firefox). |

**Do not** run Linux udev steps on Windows.

## Verify adb before Prepare

```powershell
adb kill-server
adb start-server
adb devices
```

You should see one serial and `device`. If you see `unauthorized`, unlock the phone and accept the debugging prompt.

## Known limits

- **Linux sysfs phone strip** — Companion’s USB mode panel is sysfs-based on Linux; on Windows use adb status on Connect instead.
- **Rooting slice (Web Serial)** — preloader handshake is best tested on Linux; Windows may work in Companion with correct driver for `0e8d:2000`.
- **Managed device owner** — still requires zero accounts on the phone; factory reset stays on-device.

## Conservative install without wizard

Download **flip2-installer-full-magisk.zip** from the [package mirror](https://flip2burn.online/packages/flip2-installer-full-magisk.zip), verify its SHA-256 against `wizard/catalog.json`, flash in Magisk — no PC adb required for that path.
