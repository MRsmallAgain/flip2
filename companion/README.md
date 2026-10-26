# Flip 2 Companion

Desktop shell around the [setup wizard](../docs/SETUP-WIZARD.md). Same six steps, same pages — Electron just removes the two browser-hosted frictions:

- **Step 3 (udev)** becomes one click. The app stages the rules file in `/tmp` and runs the copy + `udevadm` reload through `pkexec`, so the password prompt you see is the system's own approval dialog. A dismissed prompt installs nothing.
- **Steps 4 and the rooting slice** skip Chrome's device chooser. The app auto-picks the phone when it sees TCL adb (`1bbb:0167` / `1bbb:0c01`) or the MediaTek preloader (`0e8d:2000`); anything else still falls back to the normal picker.

Everything else — credit gate, SHA-256 verification, install with stop-on-first-FAIL, erase-gated rooting slice — is the unmodified `wizard/pages` code, served over a private `flip2://` protocol. The pages feature-check `window.FLIP2_NATIVE`, so they keep working in a plain browser with no changes needed for that.

## Run

```bash
cd companion
npm install
npm start
```

No packaging step is provided; this runs from the repo tree like `flip2 editor` does.
