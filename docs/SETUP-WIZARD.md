# Setup wizard (browser, WebUSB)

**Safety first:** read [SAFETY.md](SAFETY.md) before install or any footer link (rooting / factory).

`wizard/` is the **TCL Flip2 Manager**: **Start** (profile + **Start setup**), **Apps**, and **Set up** (Prepare). The sticky strip shows phone status and Prepare progress in plain language. From **Chrome on Linux** the browser path talks to the phone over USB (WebUSB for install, Web Serial for the optional rooting slice) and does not use host adb. **Flip 2 Companion** is the same pages on your PC with host adb for install, verify, udev, and Managed `profile.list`. Profiles, Headwind/Where pins, and device owner are in [MANAGER.md](MANAGER.md).

Firefox does not work: it has no WebUSB. Windows and macOS get the same site later; Linux is proven first.

## Run it

The page fetches `catalog.json`, the device scripts and the udev rules with
`fetch()`, so it must be served over HTTP (not opened as a `file://`):

```bash
cd ~/.local/share/flip2/wizard
python3 -m http.server 8000
# then open http://127.0.0.1:8000/pages/ in Chrome
```

For a public page, serve the `wizard/` directory from any static host
(GitHub Pages works). Everything the page needs is in that directory:

| Path | Role |
|------|------|
| `pages/` | the manager: one HTML page. Pills: Start, Apps, Set up; phone strip in chrome |
| `catalog.json` | pinned downloads: exact byte size + SHA-256 of every third-party file |
| `device/install.sh`, `device/verify.sh` | pushed to the phone and run there |
| `51-android-flip2-adb.rules` | udev rules the user installs once |
| `fflate.js` | vendored unzip (UMD build of fflate 0.8.2) |

## Front door

1. **Start.** Pick **Base** or **Managed**, then **Start setup** (Prepare). Phone status lives in the sticky strip (Companion: Refresh, USB rules). **Forkgram Classic** only — not Client. Operate/recover links are under **More: operate & recover**.
2. **Apps.** Install or remove one catalog package, remove one Magisk module, **Apply** the selected profile, or **Run check** (verify). Device owner is separate on Managed after you type `manage`. Apply writes `profile.list` and installs missing components; it does not wipe.
3. **Set up (Prepare).** Six sub-steps below. Nothing downloads until you type `yes` on **Ready**.

## Prepare sections (UI labels)

1. **Ready** — Credits and safety paths folded under Advanced; type **`yes`** to continue.
2. **Get files** — Every catalog file needs verified bytes (`size` + SHA-256 in `catalog.json`, including **`sherpa-en`** and **`sherpa-uk`**). Pick downloads or use Companion to fetch. Headwind/Where are local pins for Managed only.
3. **USB rules** — One-time Linux udev; Companion can install rules for you.
4. **Connect** — USB debugging, pick phone (WebUSB or Companion host adb).
5. **Put on phone** — Experimental push + `install.sh` as root. Companion surfaces **`FAIL:`** lines and **Install stopped**; **`pm install -r -d`** on device for downgrades. Fully quit Companion after updating the app so host fixes load.
6. **Check phone** — On-device `verify.sh`; UI shows pass/fail summary (`SUMMARY: N passed, M failed`) and **Restart phone** when done.

Checks include Sherpa **`tokens.txt`** under `files/sherpa/en` and `files/sherpa/uk`, IME, home, apps, `stt_lang`, home keys, display size, wallpaper when present.

The wizard never clears the home-key shortcuts, never downloads a browser
(menu slot 7 stays `org.chromium.chrome` — Chrome is already on the phone),
and the phone downloads nothing: `install.sh` has no `wget` and no `jq`.

## Rooting slice (erase-gated, separate)

A footer link leads to a rooting slice for a **different phone** — one the
user is willing to wipe. Unlocking the bootloader erases the device. The
slice is gated behind typing `erase` (a different word from the author's
`yes`, because unlock wipes the phone), and it only ever flashes `boot` with
neutronscott's `neutron.img`, after unlock. It never touches `super`,
`vbmeta`, system, product, or the preloader, and never writes the EMMC_BOOT
header.

The handshake is a Web Serial port of `autobooter-linux.py`: watch for the
MTK preloader (`0e8d:2000`) at 115200 baud, write `FASTBOOT`, and accept only
an 8-byte `READYTOO`, a `READYTOOB` prefix, or the 18-byte
`READYREADYTOOBTSAF`. Any other non-empty answer stops everything (nothing
flashes, and that reply is not retried); a missed one-second window just
means remove/reinsert the battery again. The fastboot
steps follow in the page (`pages/js/fastboot.js`): unlock with the on-screen
keypad confirm, `download` + `flash:boot` of the hash-verified `neutron.img`,
reboot. By construction those are the only destructive commands the module
can send — there is no path to `flash:` any other partition, and no DATA
phase runs unless the device's declared size matches the image exactly.

Do not run the rooting slice against your current Flip 2 if it is already
rooted — unlocking it would erase it.

On 2026-10-29 the flash button on that slice was pressed for the first time:
donor `MRV8IJJVPRYTS4UG` went from a `boot` hash of `40ef8d56…` to the
`neutron.img` pin, rebooted, and came up rooted on Magisk 27.0 — with the full
app and module set installed and verifying 28/28 on the other side (the
  display-size check was added the same day, after the run itself).
[FLASH-2026-10-29.md](FLASH-2026-10-29.md) records the run, including the one
place it fell back to host adb and why.

## Return to factory (restore path proven)

A third slice goes the other way: put back a copy of this phone's own `boot`
image that the wizard saved earlier — this visit, or one before it — then wipe
userdata on the phone. Nothing is downloaded; there is no stock image for this
build to download. It is gated by typing `factory`, linked from the footer, and
it shows one stage at a time like the rooting slice.

Two things to know before using it. A copy saved on a rooted phone puts root
back with it, because root lives in that image's ramdisk — so this restores the
phone to the state the copy was taken in, not to virgin firmware. And it is the
only way back for a phone that will not start, since such a phone cannot be
dumped now.

On 2026-10-28 a donor's `boot` partition was destroyed and restored from a saved
copy, byte-identical, with root coming back with it, and then the whole slice —
all six stages, write included — was driven through the page itself and ended on
"The phone came back as the copy that was saved" —
[FACTORY-TEST.md](FACTORY-TEST.md). Two things are still unexercised: the wipe
stage (no userdata was erased) and choosing a copy on a phone that was already
dead before the copy was picked. See
[RETURN-TO-FACTORY.md](RETURN-TO-FACTORY.md) for the gates, the stages, and why
the boot copy is read and written on the host rather than in the page.

## What is not committed here

The third-party binaries and models (neutron.img, Forkgram APK, Sherpa-ONNX
tarballs, F-Droid APKs) are **not** in this repo and are not attached to
the flip2 release. `catalog.json` only pins their upstream URLs and hashes;
the browser fetches them from upstream and verifies them. Chrome is not
downloaded either. The Headwind launcher pin has no download URL. The file is `~/Downloads/com.hmdm.launcher_15400.apk` (see [MANAGER.md](MANAGER.md)). Do not substitute `hmdm-6.40-os.apk`.

## Companion app (Electron)

`companion/` is the desktop shell for these pages. The window title is **TCL Flip2 Manager**. Prepare → udev is one click, and Prepare → Connect plus the rooting slice skip Chrome's device chooser:

```bash
cd ~/.local/share/flip2
flip2 companion        # or: cd companion && npm install && npm start
```

- The pages are served from a private `flip2://` protocol — no HTTP server.
  Install and verify inside Companion use host adb. The pages feature-check
  `window.FLIP2_NATIVE`, so they keep working in a plain browser.
- **One-click udev.** Prepare → udev has an "Install the rules for me" button:
  the rules file is staged in a temp dir and copied to `/etc/udev/rules.d/`
  via `pkexec` (the system password prompt), then the rules are reloaded and
  triggered. Dismissing the prompt installs nothing.
- **Auto-picked devices.** When the page asks for a USB or serial device,
  the app selects the matching one automatically (TCL adb `1bbb:0167` and
  `1bbb:0c01`, MediaTek preloader `0e8d:2000`) instead of showing the
  chooser.

No packaging step is provided; the app runs from the repo tree like
`flip2 editor` does.

## Test status

Prepare (Ready → Get files → … → Check phone) has been run end-to-end on donor hardware with **Flip 2 Companion** host adb: install completes with **`SUMMARY: N passed, 0 failed`** when Sherpa tarballs and profile ids match catalog pins. Install failures must surface **`FAIL:`** from `install.sh` stdout (Companion uses shell capture, not exit-only adb).

Chrome WebUSB install is secondary; Linux Companion is the supported path for Managed Apply and reliable push. Rooting and factory slices remain separately gated (`erase` / `factory`).

Companion smoke (`companion/` → `npm run start:safe -- --smoke`): page title **TCL Flip2 Manager**, pills **Start · Apps · Set up**, catalog includes **`sherpa-en`** / **`sherpa-uk`** with size and sha256. See [MANAGER.md](MANAGER.md) for smoke expectations.
