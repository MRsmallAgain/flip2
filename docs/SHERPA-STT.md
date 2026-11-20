# Sherpa-ONNX dictation (Null Keyboard)

The Flip2 Null Keyboard uses **Sherpa-ONNX** ASR only (Whisper.cpp and Vosk were removed). Models live under `files/sherpa/{en,uk}/` on the app uid; the APK ships ONNX Runtime + sherpa JNI for **armeabi-v7a** (4058G).

Both languages use **offline** batch decode on `*` release (no zipformer streaming). Engine type is chosen from the model files in each lang directory:

| Lang | Model pack | Sherpa `model_type` | Notes |
|------|------------|---------------------|--------|
| `en` | NeMo multilingual int8 | `nemo_transducer` | English-oriented use of the multilingual pack; still Cyrillic-capable |
| `uk` | Moonshine base UK quantized | `moonshine` | Ukrainian-only tokenizer — avoids NeMo ru/uk confusion |

Default `stt_lang` is **`uk`** (wizard install also seeds `uk` in prefs).

## Models (pinned)

| Catalog id | File | Role |
|------------|------|------|
| **sherpa-en** | `sherpa-onnx-nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2` | Offline NeMo int8 → `files/sherpa/en/` |
| **sherpa-uk** | `sherpa-onnx-moonshine-base-uk-quantized-2026-02-27.tar.bz2` | Moonshine UK → `files/sherpa/uk/` (`encoder_model.ort`, `decoder_model_merged.ort`) |

Upstream: [k2-fsa/sherpa-onnx asr-models releases](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models).

## Host fetch

```bash
pipeline/ime/null-keyboard/vendor/fetch-sherpa.sh      # AAR 2.0.1 for build
pipeline/ime/null-keyboard/models/fetch-sherpa-models.sh  # separate en (NeMo) + uk (Moonshine)
```

Do **not** copy `uk` → `en` anymore; each lang directory is a different pack.

## Device provisioning

```bash
flip2 ime build
flip2 ime hide-bar    # installs APK; pushes Sherpa if models missing
flip2 ime sherpa      # explicit push
flip2 ime lang uk     # pin STT to Ukrainian
```

Magisk installer (never bundled): use catalog `sherpa-en` / `sherpa-uk` tarballs or URLs from `pipeline/deploy/sherpa-models.json`.

Wizard / manager: base profile includes `sherpa-en` and `sherpa-uk`; `install.sh` extracts to `files/sherpa/{en,uk}`. Verify checks Moonshine via `uk/encoder_model.ort` and `stt_lang=uk` when IME is in the profile.

## UX

Hold `*` to listen; release `*` to commit. While listening: `#` cycles EN↔UK. Preference: `stt_lang` in `flip2_null_ime.xml`.

Neither path shows streaming partials today — text appears on release (or 30 s timeout). Models are preloaded on a background executor; first hold after a cold start or language switch may show “Preparing mic…” while the recognizer loads.

## The click storm while holding `*`

Holding `*` to dictate played a click on every auto-repeat, machine-gunning into the mic. Two framework sounds are involved and they are separate settings:

| Setting | Player | Muted by |
|---------|--------|----------|
| `dtmf_tone` (= `DTMF_TONE_WHEN_DIALING`) | `ToneGenerator` in the IME | `muteDtmfTone()` (pre-existing) |
| `sound_effects_enabled` (= `SOUND_EFFECTS_ENABLED`, `FX_KEYCLICK`) | `AudioService` inside `system_server` | **`muteSoundEffects()`** |

The mute is scoped to the `*`/`#` press and restored on lifecycle events so the device is not left silent.

## Microphone on Android 11 (foreground service)

`SttForegroundService` (`android:foregroundServiceType="microphone"`) must run during capture while the IME process is `IMPORTANT_BACKGROUND`.

## Why Sherpa over Whisper on Flip2

Sherpa ships official **armeabi-v7a** libs in the AAR. Batch offline decode on release is the stable path on this CPU for both langs.

Legacy doc `WHISPER-STT.md` is obsolete for current builds.
