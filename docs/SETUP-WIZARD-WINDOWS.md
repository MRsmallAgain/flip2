# TCL Flip2 Manager on Windows

Windows checklist for **TCL Flip2 Manager** (Flip 2 Companion). Full step-by-step: [SETUP-WIZARD-DETAILED.md](SETUP-WIZARD-DETAILED.md). Read [SAFETY.md](SAFETY.md) first.

## Primary install — Windows `.exe` (recommended)

On Windows, use the **release installer** — not the browser wizard or a from-source `npm start` unless you are developing.

1. Build **`flip2-companion-<version>-win-x64.exe`** (NSIS installer or portable) — see the build step below. No prebuilt Windows `.exe` is published at the moment.
2. Run the installer (or the portable `.exe`). Window title: **TCL Flip2 Manager**.
3. **No separate adb install** — the app bundles Google **Platform Tools** under `resources\platform-tools\` (`adb.exe` + USB DLLs). Override only if needed with env var **`FLIP2_ADB`** pointing at another `adb.exe`.
4. For **adb** (Prepare) and **fastboot** (`0e8d:201c` after rooting), install Google’s USB driver from the **direct ZIP** (no Google account): [usb_driver_r13-windows.zip](https://dl.google.com/android/repository/usb_driver_r13-windows.zip) → unpack → Device Manager → Update driver → Browse → `usb_driver` folder. **Rooting VCOM** is separate — already bundled in the app (see below); do not hunt for MediaTek on developer.android.com.
5. Open **Set up** → follow **Prepare** (host adb for downloads, connect, install, verify). **Do not** run Linux udev steps on Windows.

Build the same `.exe` yourself on a Windows PC:

```powershell
cd companion
npm install
npm run pack:win
# dist\flip2-companion-<version>-win-x64.exe (NSIS + portable)
```

`prepack:win` fetches platform-tools into `companion\platform-tools-win\` and the MediaTek USB VCOM driver pack into `companion\vcom-driver-win\` automatically.

## Run from source (optional)

Only if you are hacking on Companion or no release `.exe` is published yet:

```powershell
cd companion
npm install
npm run fetch:platform-tools:win
npm run fetch:vcom-driver:win
npm start
```

Launchers set `FLIP2_ADB` to `companion\platform-tools-win\adb.exe` when present. **Node.js** required.

## Bundled with the Windows package

| Resource | Location | In-app |
|----------|----------|--------|
| Google Platform Tools | `resources\platform-tools\` | Prepare (host adb) + bundled **fastboot** after root |
| MediaTek USB VCOM (INF + `usbser.sys`) | bundled → copied to `%UserProfile%\Downloads\flip2-wizard\vcom-driver\` | Rooting → **VCOM driver steps** (opens that folder), **Open Device Manager** |

**Rooting in Companion needs no Python, mtkclient, or UsbDk** — Web Serial in the wizard talks to the preloader once VCOM is installed.

**MediaTek USB VCOM** (preloader `0e8d:2000` COM port) is bundled at pack time (third-party mirror + self-contained `flip2_preloader_vcom.inf`; see `THIRD_PARTY_NOTICE.txt` in the opened folder). On first use the companion copies files to **`Downloads\flip2-wizard\vcom-driver\`** so Device Manager can browse a normal path (not the app’s `resources\vcom-driver\` under Temp/asar). Install via Device Manager → Update driver → Browse my computer → **Let me pick from a list** → **Have Disk** → Browse → **`flip2_preloader_vcom.inf`** in that folder — not folder-only browse on MTK `usb2ser_Win764.inf` (needs `mdmcpq.inf`). Google USB Driver covers adb/fastboot (`0e8d:201c`) only, not preloader VCOM.

## VCOM then Start watching (straight path to fastboot)

The rooting step needs a **serial COM port** for preloader `0e8d:2000`. If **Start watching** never connects after battery pull:

1. **Open Device Manager** (in-app on Rooting) and look for **Ports (COM & LPT)** or an unknown device with a **yellow warning** — that is usually missing VCOM, not adb.
2. **VCOM driver steps** opens **`Downloads\flip2-wizard\vcom-driver\`** (staged from the bundle on first use). In Device Manager: update driver → Browse my computer → Let me pick from a list → Have Disk → Browse → `flip2_preloader_vcom.inf` in that folder.
3. After VCOM: unplug USB, remove/reinsert battery, replug, press **Start watching** again — the app runs the bootROM handshake and continues to **fastboot** with bundled tools.
4. If the port still does not appear, repeat Device Manager driver update with the folder that contains the MTK VCOM `.inf`.

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
