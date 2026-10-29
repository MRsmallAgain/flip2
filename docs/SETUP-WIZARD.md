# Setup wizard (browser, WebUSB)

**Safety first:** read [SAFETY.md](SAFETY.md) before install or any footer link (rooting / factory).

`wizard/` is a click-through web page that sets the Flip 2 up from **Chrome on
Linux** — no `flip2` CLI, no adb on the host. The page talks to the phone
directly over USB with ADB over WebUSB.

Firefox does not work: it has no WebUSB. Windows and macOS get the same site
later; Linux is proven first.

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
| `pages/` | the wizard itself: one HTML page, six steps |
| `catalog.json` | pinned downloads: exact byte size + SHA-256 of every third-party file |
| `device/install.sh`, `device/verify.sh` | pushed to the phone and run there |
| `51-android-flip2-adb.rules` | udev rules the user installs once |
| `fflate.js` | vendored unzip (UMD build of fflate 0.8.2) |

## The six steps

1. **Credits and gate.** Who made what, with links: the Flip2 installer,
   Forkgram, whisper.cpp, Vosk, and the F-Droid apps. Nothing downloads
   until the user types `yes`.
2. **Files.** The page links each pinned file; the user downloads it normally
   (GitHub releases, F-Droid and alphacephei.com send no cross-origin
   headers, so the page cannot fetch them itself) and picks the files in the
   page. Every file is hashed with WebCrypto SHA-256 against
   `catalog.json`; a mismatch stops that file.
3. **udev.** One-time `sudo cp` of the rules file so the user's account can
   reach the phone in both adb modes. The rules file also lists the MediaTek
   preloader so that device is permissioned if it appears; this wizard does
   not open it.
4. **Connect.** USB debugging on, pick the phone, ADB handshake in the page.
   The page generates its own RSA key once, stores it in localStorage, and
   offers the public key to adbd — the phone prompts once, "always allow"
   remembers it.
5. **Install.** ⚠ **Experimental** — this step pushes files and runs a root
   install script over adb and has only been exercised on one device. For a
   first-time setup you can trust, flash the Tier B installer zip from the
   release page instead; the page automates the same steps and inherits
   their risks.

   The page unpacks the installer zip, rebuilds the Tag Drawer
   module around the fresh F-Droid APK, pushes everything into
   `/data/local/flip2/incoming/`, and runs `install.sh` as root. It **stops
   at the first failed line**, shows it, and offers Retry — it does not
   continue through failures the way `flip2 setup full` does. `incoming/`
   is kept for Retry; the page cleans it up on success.
6. **Verify.** `verify.sh` runs on the phone and prints one PASS/FAIL line
   per check (daemon, IME, home, six apps, speech models, stt_lang, the five
   home-key shortcuts, IME settings, `display_size_forced=321,428`, and the
   default wallpaper when the installer zip carried one).

The wizard never clears the home-key shortcuts, never downloads a browser
(menu slot 7 stays `org.chromium.chrome` — Chrome is already on the phone),
and the phone downloads nothing: `install.sh` has no `wget` and no `jq`.

## Rooting slice

The erase-gated unlock and boot-flash path is not on this branch. It lives
on `feature/rooting-slice`. Do not run it against this Flip 2 if the phone
is already rooted — unlocking it would erase it. This branch's wizard stops
at install and verify.

On 2026-10-29 the flash button on that slice was pressed for the first time:
donor `MRV8IJJVPRYTS4UG` went from a `boot` hash of `40ef8d56…` to the
`neutron.img` pin, rebooted, and came up rooted on Magisk 27.0 — with the full
app and module set installed and verifying 28/28 on the other side (the
  display-size check was added the same day, after the run itself).
[FLASH-2026-10-29.md](FLASH-2026-10-29.md) records the run, including the one
place it fell back to host adb and why.

## Return to factory (restore path proven)

On **`feature/rooting-slice` only**, a footer slice goes the other way: put back a copy of this phone's own `boot`
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

The third-party binaries and models (Forkgram APK, whisper and
Vosk models, F-Droid APKs) are **not** in this repo and are not attached to
the flip2 release. `catalog.json` only pins their upstream URLs and hashes;
the browser fetches them from upstream and verifies them. Chrome is not
downloaded either.

## Companion app (Electron)

`companion/` wraps the same wizard pages in a desktop app, so step 3 is one
click and the connect step skips Chrome's device chooser:

```bash
cd ~/.local/share/flip2
flip2 companion        # or: cd companion && npm install && npm start
```

- The pages are served from a private `flip2://` protocol — no HTTP server,
  and the wizard code is otherwise unchanged. The pages feature-check
  `window.FLIP2_NATIVE`, so they keep working in a plain browser.
- **One-click udev.** Step 3 gains an "Install the rules for me" button:
  the rules file is staged in a temp dir and copied to `/etc/udev/rules.d/`
  via `pkexec` (the system password prompt), then the rules are reloaded and
  triggered. Dismissing the prompt installs nothing.
- **Auto-picked devices.** When the page asks for a USB device, the app
  selects the matching one automatically (TCL adb `1bbb:0167` and
  `1bbb:0c01`) instead of showing the chooser.

No packaging step is provided; the app runs from the repo tree like
`flip2 editor` does.

## Test status

The wizard has been run once end-to-end against a real Flip 2 from Chrome on
Linux: all six steps passed on the phone, including install and verify. The
2026-10-29 re-run of steps 5 and 6 got the same result but drove the install
over host adb instead of WebUSB, because the host `adb` server held the
interface — so the payload path is re-proven and the WebUSB ADB transport
step 5 uses is still not. All three slices have now had their buttons pressed
on hardware: the factory slice through all six stages, the rooting slice's
flash, and the wipe stage walked to its continue button. The
Electron companion has a self-check mode (`npm start -- --smoke`) that boots
the app, loads the wizard over `flip2://`, and prints the page state as JSON:
all nine catalog rows render, fflate loads, the native bridge answers, the
udev button is visible, and WebUSB + Web Serial are exposed. The one-click
udev install and the device auto-pick still need a real phone plugged in to
exercise; the first such run happens from the user's local terminal, not
from this sandbox.
