# TCL Flip2 Manager on Windows

Windows checklist for **TCL Flip2 Manager** (Flip 2 Companion). Full step-by-step: [SETUP-WIZARD-DETAILED.md](SETUP-WIZARD-DETAILED.md). Read [SAFETY.md](SAFETY.md) first.

## One-time PC setup

1. **Clone or download** [flip2](https://github.com/MRsmallAgain/flip2) (you need `companion/` and `wizard/` — the installer bundles both).
2. **adb** — the **Windows installer** (NSIS/portable from `npm run pack:win`) bundles Google **Platform Tools** under the app’s `resources\platform-tools\` (`adb.exe` + USB DLLs). No separate adb install needed for Companion install/verify. Override with `FLIP2_ADB` if you use another copy.
3. **From source on Windows** — run `npm run fetch:platform-tools:win` once in `companion/` (or let `npm run pack:win` do it via `prepack:win`); launchers set `FLIP2_ADB` to `companion\platform-tools-win\adb.exe` when present.
4. **USB driver** — install [Google USB Driver](https://developer.android.com/studio/run/oem-usb#Drivers) (or OEM driver) so Device Manager shows the phone without a warning triangle when USB debugging is on.
5. **Node.js** — only if you run from source instead of a release `.exe`.

## Run Companion

**Release installer** (after `npm run pack:win` on Windows or a published artifact):

- Run `flip2-companion-*-win-x64.exe` (NSIS) or the portable build from `companion/dist/`.
- Window title: **TCL Flip2 Manager**.

**From source:**

```powershell
cd companion
npm install
npm start
```

Build installers:

```powershell
cd companion
npm install
npm run pack:win
```

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

Download **flip2-installer-full-magisk.zip** from [Releases](https://github.com/MRsmallAgain/flip2/releases), verify `SHA256SUMS`, flash in Magisk — no PC adb required for that path.
