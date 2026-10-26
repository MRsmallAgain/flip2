---
name: flip2-ime-stt
description: Build, install, and provision the Flip2 Null Keyboard and its on-device dictation (Whisper first, Vosk fallback). Use whenever the user mentions the Flip2 IME, T9, hold-star dictation, Whisper, Vosk, ggml models, stt_lang, the mic, or "voice to text" on the TCL Flip 2.
---

# Flip2 Null Keyboard and dictation

Repo: `~/.local/share/flip2`. Always go through the CLI:

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
```

Package `com.tim.flip2.nullkeyboard`, service `.NullKeyboardService`. Shipped IME for toolkit `1.1.0-flip2` is versionName `2.6.0` (versionCode 34). Build with `flip2 ime build` so `JAVA_HOME` is `~/.local/opt/jdk17`. Bare `javac` is not on PATH.

## What to run

```bash
flip2 ime build       # nullkeyboard.apk
flip2 ime hide-bar    # install, default IME, disable Kika, grant mic, push Vosk if missing
flip2 ime whisper     # push ggml bins from models/whisper/{en,uk}
flip2 ime models      # push EN+UK Vosk (fallback only)
flip2 ime lang        # print stt_lang
flip2 ime lang uk     # user's daily language; restore this after any EN test
flip2 ime status
flip2 ime restore     # stock Kika: com.iqqijni.dvt912key
```

`hide-bar` also sets `show_ime_with_hard_keyboard` (secure and global) to 1. That is what lets matrix BACK and the keypad reach the IME. Do not turn it off.

## Engine choice

The service picks the engine once, at `onCreate`:

- Whisper when `libwhisperjni` loads and a ggml `.bin` larger than 1 MB exists for the current `stt_lang`.
- Otherwise Vosk.

Both engines share `shared_prefs/flip2_null_ime.xml` key `stt_lang`, so `#` while listening cycles EN/UK without rebuilding the engine. A new engine choice needs a process restart (reinstall, or force-stop the IME and reopen the text field).

Hold `*` (about 380 ms) starts dictation. While listening, `#` switches language and `*` stops. Hold `#` outside dictation opens the symbols picker.

## Whisper will silently stay on Vosk if either of these is wrong

1. `libwhisper.so` needs `libc++_shared.so`. The APK must contain `lib/armeabi-v7a/libc++_shared.so`, and `WhisperSttHelper` must `System.loadLibrary("c++_shared")` before `whisperjni`. A missing library used to fail the load with no log line; failures now go to logcat tag `Flip2STT`. Confirm with the process maps: `libwhisper.so`, `libwhisperjni.so`, and `libc++_shared.so`.
2. The capture loop exits while `mListening` is false. `beginCapture` has to set `mListening = true` before the loop, including the 600 ms mic-retry path. If the mic opens and closes in about 140 ms, this flag was not set.

Whisper is batch: record up to 30 s, one `whisper_full` on stop, silence short-circuit when peak is under 300, 12 s timeout. There are no Vosk-style partials. `harvest final=` in `Flip2STT` means the listen took the Vosk path.

## Models are not in git or in the APK

Host Whisper trees:

`pipeline/ime/null-keyboard/models/whisper/{en,uk}`

One multilingual bin (the phone has been using `ggml-tiny-q5_1.bin`, about 31 MB) may be copied into both language dirs. `adb push` does not follow symlinks (`remote symlink failed`). The language dirs must be real copies (`cp -L`), not links.

Device path (app uid, then `restorecon`):

`/data/data/com.tim.flip2.nullkeyboard/files/whisper/{en,uk}`

Vosk fallback:

`/data/data/com.tim.flip2.nullkeyboard/files/vosk/{en,uk}`

`flip2 ime whisper` stages via `/sdcard/Download/flip2-whisper`, copies in with `su`, `chown`s to the package uid, and runs `restorecon`. Do not leave models on `/data/local` and expect the IME to read them; that label is not readable by the app.

## Judging a listen

A successful Whisper path is: toast `Listening (EN)` or `Listening (UK)`, then `Flip2STT` `commitSttText:` with the raw text. Garbage digits from the tiny model mean the capture was quiet or was an 8 kHz clip played from laptop speakers. That is not a formatter bug (`commitSttText` logs the raw string before smart-commit formatting) and it is not proof the engine failed to run.

After any test that ran `flip2 ime lang en`, set the daily language back:

```bash
flip2 ime lang uk
```

Key injection for the hold is in the `flip2-ondevice-keys` skill. Reinstalling the APK kills the IME process; tap the compose field again before the next listen.
