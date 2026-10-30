# Flip 2 Companion

Desktop shell around the [TCL Flip2 Manager](../docs/MANAGER.md). The window title is **TCL Flip2 Manager**. Phone, Profile, Apps, and Prepare replace the old six-step bar. Prepare still holds the credit gate, files, udev, connect, install, and verify. Electron removes the two browser-hosted frictions:

- **Prepare → udev** is one click. The app stages the rules file in `/tmp` and runs the copy + `udevadm` reload through `pkexec`, so the password prompt you see is the system's own approval dialog. A dismissed prompt installs nothing.
- **Prepare → Connect**, and the rooting slice, skip Chrome's device chooser. The app auto-picks the phone when it sees TCL adb (`1bbb:0167` / `1bbb:0c01`) or the MediaTek preloader (`0e8d:2000`); anything else still falls back to the normal picker.

Install and verify in Companion use host adb. Managed Apply requires Companion, because a plain browser does not write `/data/local/flip2/profile.list`. The pages are served over a private `flip2://` protocol and feature-check `window.FLIP2_NATIVE`, so they still open in a browser. Stuck on Connect or Install: [WIZARD-FAILURES.md](../docs/WIZARD-FAILURES.md).

## Run

```bash
cd companion
npm install
npm start
```

No packaging step is provided; this runs from the repo tree like `flip2 editor` does.
