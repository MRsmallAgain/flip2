# Flip 2 Companion

Desktop shell around the [TCL Flip2 Manager](../docs/MANAGER.md). The window title is **TCL Flip2 Manager**. The app opens on **Start**. The pill bar is **Start · Apps · Device · Set up**. Device works on WebUSB in Chrome and falls back to host adb in Companion when WebUSB is not connected. Prepare still holds the credit gate, files, udev, connect, install, and verify. Electron removes the two browser-hosted frictions:

- **Prepare → udev** is one click. The app stages the rules file in `/tmp` and runs the copy + `udevadm` reload through `pkexec`, so the password prompt you see is the system's own approval dialog. A dismissed prompt installs nothing.
- **Prepare → Connect**, and the rooting slice, skip Chrome's device chooser. The app auto-picks the phone when it sees TCL adb (`1bbb:0167` / `1bbb:0c01`) or the MediaTek preloader (`0e8d:2000`); anything else still falls back to the normal picker.

Install and verify in Companion use host adb. Managed Apply requires Companion, because a plain browser does not write `/data/local/flip2/profile.list`. The pages are served over a private `flip2://` protocol and feature-check `window.FLIP2_NATIVE`, so they still open in a browser. Stuck on Connect or Install: [WIZARD-FAILURES.md](../docs/WIZARD-FAILURES.md).

## Run (bundled launchers — recommended)

Scripts check **Node/npm**, run **`npm install`** in `companion/` when Electron is missing, warn about **adb** and Linux **udev**, then start Electron.

| OS | Command |
|----|--------|
| **Linux / macOS** | `./companion/run-companion.sh` or `flip2 companion` |
| **Windows** | Double-click `run-companion.bat` or `.\companion\run-companion.ps1` |

```bash
# Linux examples
./companion/run-companion.sh
./companion/run-companion.sh --smoke
FLIP2_ADB=/path/to/adb ./companion/run-companion.sh
FLIP2_COMPANION_SAFE=1 ./companion/run-companion.sh
FLIP2_SKIP_NPM_INSTALL=1 ./companion/run-companion.sh
```

```powershell
.\companion\run-companion.ps1
.\companion\run-companion.ps1 -Smoke
```

**Requirements:** Node.js **18+**, npm. **adb** on PATH (or `FLIP2_ADB`) for Prepare install/verify.

Manual: `cd companion && npm install && npm start`.

## Windows / Linux installers

On the target OS with Node.js installed:

```bash
cd companion
npm install
npm run pack:win    # Windows: NSIS + portable under dist/
npm run pack:linux  # Linux: AppImage + unpacked dir
```

Packaged builds embed `wizard/` via `extraResources`. Put **adb** on `PATH` (or set `FLIP2_ADB` to `adb.exe` on Windows) before install/verify.

**Windows checklist:** [docs/SETUP-WIZARD-WINDOWS.md](../docs/SETUP-WIZARD-WINDOWS.md)  
**Full Prepare walkthrough:** [docs/SETUP-WIZARD-DETAILED.md](../docs/SETUP-WIZARD-DETAILED.md)
