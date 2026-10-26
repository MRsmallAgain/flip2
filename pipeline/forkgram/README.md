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

## Patches

`forkgram-13.0.2.0-back.patch` changes four smali files:

| File | Change |
| --- | --- |
| `ui/LaunchActivity.smali` | `onBackPressed()` deletes one character when a focused `EditText` is non-empty and returns; otherwise the original navigation runs. `windowSoftInputMode` 0x10 → 0x14 (adjustResize + stateVisible). |
| `ui/jj0.smali` | forces `setShowSoftInputOnFocusCompat(true)`. |
| `ui/at1$z.smali` | forces both `setShowSoftInputOnFocus(true)` calls. |
| `messenger/AndroidUtilities.smali` | forces `usingHardwareInput = false`. |

Both the physical BACK key and the on-screen nav-bar BACK deliver
`KEYCODE_BACK`, so the same `onBackPressed()` handler covers both.

## Hosted build

The patched APK is published from our Forkgram fork:

- Fork: <https://github.com/MRsmallAgain/TelegramAndroid>
- Release: <https://github.com/MRsmallAgain/TelegramAndroid/releases/tag/flip2-13.0.2.0-r1>
- Source-level upstream PR: <https://github.com/Forkgram/TelegramAndroid/pull/539>

```sh
flip2 forkgram release              # download, verify SHA-256, install
flip2 forkgram release --no-install # download and verify only
flip2 forkgram release --uninstall  # uninstall first (wipes app data)
```

## Usage

```sh
flip2 forkgram patch                 # pull installed APK, patch, sign, install
flip2 forkgram patch --apk FILE      # patch a specific APK
flip2 forkgram patch --no-install    # build only
flip2 forkgram patch --uninstall     # uninstall first (wipes app data)
```

The source APK is backed up to `~/forkgram-original-13.0.2.0.apk`. The signed
result is written to `/tmp/forkgram-patch/` by default (`--work DIR` to change).

Requires JDK 17 (`~/.local/opt/jdk17`), apktool (`~/.local/bin/apktool.jar`),
and Android build-tools for `zipalign` / `apksigner`
(`~/.local/share/android-sdk/build-tools`).

## Caveats

- The patched APK is signed with the local debug keystore, so it cannot update
  over an F-Droid install. Uninstall once (`--uninstall`, which wipes app data)
  or install over a previous patched build.
- Every Forkgram update replaces the patched APK; re-run the script on the new
  base APK. The patch only applies to version 13.0.2.0 — the script refuses
  other installed versions unless `--force` is passed.
- BACK deletes only while a focused text field contains text. With an empty
  field, normal Telegram navigation (chat → list → exit) still works.
- Restore the stock app with `adb install -r ~/forkgram-original-13.0.2.0.apk`
  after uninstalling the patched build.
- Not affiliated with Telegram or Forkgram; no APK is redistributed here.
