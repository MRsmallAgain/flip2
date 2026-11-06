# Forkgram patch — BACK-to-delete + IME visibility

Forkgram (`org.forkgram.classic`) is the Telegram client used on this device.
Two Telegram behaviours break the Flip 2 null-keyboard setup:

1. Telegram gives its windows `ALT_FOCUSABLE_IM`, so the input dispatcher keeps
   hardware keys in the app. The IME never sees BACK, its own delete-on-back
   handler cannot run, and BACK closes the app instead.
2. Telegram forces `setShowSoftInputOnFocus(false)` and sets
   `usingHardwareInput = true`, so the IME is not shown and `onKeyPreIme` never
   runs at all.

The IME-side workarounds live in `pipeline/ime` (1px window, `requestShowSelf`),
but they cannot override `ALT_FOCUSABLE_IM`. This pipeline patches the app.

**Do not install `org.forkgram.messenger` (Forkgram Client)** for Flip2 — the wizard
and verify step only target **`org.forkgram.classic`**. Client is a different package
and is not patched by this pipeline.

## Patches

`forkgram-13.0.2.0-back.patch` changes five smali files:

| File | Change |
| --- | --- |
| `ui/LaunchActivity.smali` | `windowSoftInputMode` 0x10 → 0x14; `onBackPressed()` delete in focused `EditText` + chat composer fallback via `ActionBarLayout`; **`flip2HwDelete()`** + early **`dispatchKeyEvent`** for BACK/DEL; |
| `ui/n20.smali` | **`onBackPressed()`** (chat screen): if message composer has text, delete one char and consume BACK — **required for hardware ⌫ in chat** (BACK does not go through `LaunchActivity` first). |
| `ui/jj0.smali` | forces `setShowSoftInputOnFocusCompat(true)`. |
| `ui/at1$z.smali` | forces both `setShowSoftInputOnFocus(true)` calls. |
| `messenger/AndroidUtilities.smali` | forces `usingHardwareInput = false`. |

On the Flip 2, the physical delete key is **BACK (keycode 4, scan 158)** — there is
no separate DEL key. Chat delete is handled in **`n20.onBackPressed()`** first.

Both the physical BACK key and the on-screen nav-bar BACK deliver
`KEYCODE_BACK`, so the same handlers cover both.

## Hosted build

The patched APK is published from our Forkgram fork:

- Fork: <https://github.com/MRsmallAgain/TelegramAndroid>
- Release: <https://github.com/MRsmallAgain/TelegramAndroid/releases/download/flip2-13.0.2.0-r1/forkgram-13.0.2.0-flip2-patched.apk>
- Source-level upstream PR: <https://github.com/Forkgram/TelegramAndroid/pull/539>

After updating `forkgram-13.0.2.0-back.patch`, cut a **new release** (e.g. `flip2-13.0.2.0-r2`),
update `SHA256SUMS`, and bump **`wizard/catalog.json`** + regenerate **`pins.json`**
so the wizard downloads the build that includes the chat ⌫ fix.

```sh
flip2 forkgram release              # download, verify SHA-256, install
flip2 forkgram release --no-install # download and verify only
flip2 forkgram release --uninstall  # uninstall first (wipes app data)
```

Or run the script directly:

```sh
bash pipeline/forkgram/install-release.sh
```

## Usage (build patch locally)

```sh
bash pipeline/forkgram/patch-forkgram.sh
```

The source APK is backed up to `~/forkgram-original-13.0.2.0.apk`. The signed
result is written to `/tmp/forkgram-patch/` by default (`--work DIR` to change).

Requires JDK 17 (`~/.local/opt/jdk17`), apktool (`~/.local/bin/apktool.jar`),
and Android build-tools for `zipalign` / `apksigner`
(`~/.local/share/android-sdk/build-tools`).

## Updating the patched app (keep chats)

Same package: `org.forkgram.classic`. **Keep data** by installing over the top
(same debug signature as a previous patched or wizard install):

```sh
adb install -r /path/to/forkgram-13.0.2.0-flip2-patched-signed.apk
```

Sources for the APK:

1. **Hosted** — `install-release.sh` (after release tag is updated).
2. **Wizard** — Prepare → download `forkgram` from catalog → Install (pushes pinned APK).
3. **Local patch** — `patch-forkgram.sh` (output under `/tmp/forkgram-patch/`).

Use **`--uninstall`** / `adb uninstall org.forkgram.classic` only when switching
from **F-Droid-signed** Classic to **debug-signed** patched (wipes app data).

## Caveats

- The patched APK is signed with the local debug keystore, so it cannot update
  over an F-Droid install. Uninstall once (`--uninstall`, which wipes app data)
  or install over a previous patched build.
- Every Forkgram update replaces the patched APK; re-run the script on the new
  base APK. The patch only applies to version **13.0.2.0** — the script refuses
  other installed versions unless `--force` is passed.
- BACK deletes only while the message composer (or another focused text field)
  contains text. With an empty field, normal Telegram navigation still runs.
- Restore the stock app with `adb install -r ~/forkgram-original-13.0.2.0.apk`
  after uninstalling the patched build.
- Not affiliated with Telegram or Forkgram; no APK is redistributed here.
