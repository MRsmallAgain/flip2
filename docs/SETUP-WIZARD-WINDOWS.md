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

`prepack:win` fetches platform-tools into `companion\platform-tools-win\` and **UsbDk** (+ README) into `companion\preloader-drivers-win\` automatically.

## Run from source (optional)

Only if you are hacking on Companion or no release `.exe` is published yet:

```powershell
cd companion
npm install
npm run fetch:platform-tools:win
npm run fetch:preloader-drivers:win
npm start
```

Launchers set `FLIP2_ADB` to `companion\platform-tools-win\adb.exe` when present. **Node.js** required.

## Bundled drivers (Windows package)

| Resource | Location | In-app |
|----------|----------|--------|
| Google Platform Tools | `resources\platform-tools\` | Prepare (host adb) |
| UsbDk 1.0.22 | `resources\preloader-drivers\` | Rooting → **Install UsbDk** (opens MSI; admin) |
| Driver notes + VCOM steps | `resources\preloader-drivers\README.txt` | Rooting → **Open bundled drivers** |

**MediaTek USB VCOM** (preloader `0e8d:2000` COM port) is **not** redistributed — install from MediaTek / vendor packages. Google USB Driver covers adb only, not VCOM.

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
- **Rooting slice (Web Serial)** — in **Companion** there is **no port chooser**: Electron auto-picks when exactly one MTK preloader (`0e8d:2000`) serial port appears after you remove/reinsert the battery. On Windows you often need the **MediaTek USB VCOM** driver so that port is visible; if nothing connects after two minutes, install the driver and retry. A plain browser still shows Chrome’s serial picker.
- **Managed device owner** — still requires zero accounts on the phone; factory reset stays on-device.

## Conservative install without wizard

Download **flip2-installer-full-magisk.zip** from the [package mirror](https://flip2burn.online/packages/flip2-installer-full-magisk.zip), verify its SHA-256 against `wizard/catalog.json`, flash in Magisk — no PC adb required for that path.
