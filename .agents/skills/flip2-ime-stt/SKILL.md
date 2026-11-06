---
name: flip2-ime-stt
description: Build, install, and provision the Flip2 Null Keyboard and Sherpa-ONNX streaming dictation (EN/UK). Use for Flip2 IME, T9, hold-star dictation, Sherpa, ONNX, stt_lang, mic, or voice-to-text on the TCL Flip 2.
---

# Flip2 Null Keyboard and dictation

Repo: `~/.local/share/flip2`. Always go through the CLI:

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
```

Package `com.tim.flip2.nullkeyboard`, service `.NullKeyboardService`. Build with `flip2 ime build` (`JAVA_HOME` → `~/.local/opt/jdk17`). Run `pipeline/ime/null-keyboard/vendor/fetch-sherpa.sh` before the first build.

## What to run

```bash
flip2 ime build       # nullkeyboard.apk
flip2 ime hide-bar    # install, default IME, disable Kika, grant mic, push Sherpa if missing
flip2 ime sherpa      # fetch host models (if needed) + push EN+UK to device
flip2 ime lang        # print stt_lang
flip2 ime lang uk     # daily language; restore after EN tests
flip2 ime status
flip2 ime restore     # stock Kika: com.iqqijni.dvt912key
```

`whisper` and `models` (Vosk) subcommands are removed — they print an error pointing to `sherpa`.

`hide-bar` sets `show_ime_with_hard_keyboard` (secure and global) to 1 so matrix BACK and the keypad reach the IME.

## Engine

**Sherpa-ONNX only** (`SherpaSttHelper`): loads `libonnxruntime.so` and `libsherpa-onnx-jni.so` (armeabi-v7a). Shared pref `stt_lang` (`en`|`uk`); `#` while listening cycles language.

- **EN:** `OnlineRecognizer` (streaming zipformer) — live partials; **tail flush on stop** so mid-sentence release is not dropped.
- **UK:** `OfflineRecognizer` (NeMo int8) — no streaming UK upstream; text appears on stop (~10 s first load).

**Mic (Android 11):** start **`SttForegroundService`** (microphone FGS) before `AudioRecord`; IME uid is `IMPORTANT_BACKGROUND` otherwise.

Hold `*` (~380 ms) starts dictation. While listening: `#` = EN↔UK, `*` = stop. Hold `#` outside dictation opens symbols. Holding `*` mutes **`FX_KEYCLICK`** via `muteSoundEffects()` (not just DTMF).

Logcat: `Flip2STT` (`fg service up`, load errors, `commitSttText:`).

## Models (not in git or APK)

Host: `pipeline/ime/null-keyboard/models/{en,uk}` via `models/fetch-sherpa-models.sh`.

Device: `/data/data/com.tim.flip2.nullkeyboard/files/sherpa/{en,uk}` — each dir must contain `tokens.txt` and ONNX transducer files.

`flip2 ime sherpa` stages via `/sdcard/Download/flip2-sherpa`, copies with `su`, `chown`, `restorecon`. Do not use `/data/local/flip2` for models; the app cannot read that label.

Installer / wizard: catalog ids `sherpa-en`, `sherpa-uk`; pack with `--sherpa-url en=... --sherpa-url uk=...`.

## Judging a listen

Expect toast `Listening (EN|UK)`, streaming partials, then `Flip2STT` `commitSttText:` on stop. After `flip2 ime lang en` tests, restore `flip2 ime lang uk`.

Reinstall kills the IME process — refocus the text field before the next listen.

See `docs/SHERPA-STT.md` for model URLs and tradeoffs.
