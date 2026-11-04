# Sherpa-ONNX dictation (Null Keyboard)

The Flip2 Null Keyboard uses **Sherpa-ONNX** streaming ASR only (Whisper.cpp and Vosk were removed). Models live under `files/sherpa/{en,uk}/` on the app uid; the APK ships ONNX Runtime + sherpa JNI for **armeabi-v7a** (4058G).

## Models (pinned)

| Catalog id | File | Role |
|------------|------|------|
| **sherpa-en** | `sherpa-onnx-streaming-zipformer-en-20M-2023-02-17-mobile.tar.bz2` | English zipformer transducer (mobile) |
| **sherpa-uk** | `sherpa-onnx-nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2` | Multilingual NeMo int8 pack (Ukrainian via `stt_lang=uk`) |

Upstream: [k2-fsa/sherpa-onnx asr-models releases](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models).

## Host fetch

```bash
pipeline/ime/null-keyboard/vendor/fetch-sherpa.sh      # AAR 2.0.1 for build
pipeline/ime/null-keyboard/models/fetch-sherpa-models.sh  # EN + UK tarballs → models/{en,uk}
```

## Device provisioning

```bash
flip2 ime build
flip2 ime hide-bar    # installs APK; pushes Sherpa if tokens.txt missing
flip2 ime sherpa      # explicit push
flip2 ime lang uk     # default daily language on wizard install
```

Magisk installer (never bundled):

```bash
flip2 installer pack --flavor full \
  --sherpa-url en=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17-mobile.tar.bz2 \
  --sherpa-url uk=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2
```

Wizard / manager: base profile includes components `sherpa-en` and `sherpa-uk`; `install.sh` extracts tarballs to `files/sherpa/{en,uk}` and checks `tokens.txt`.

## UX

Hold `*` to listen (streaming partials). While listening: `#` switches EN↔UK, `*` stops. Preference key: `stt_lang` in `flip2_null_ime.xml`.

## Why Sherpa over Whisper on Flip2

Streaming transducers update text while you speak; batch Whisper (`whisper_full` on stop) felt slower on v7a CPU. `faster-whisper` is not an Android v7a drop-in. Sherpa ships official **armeabi-v7a** libs in the AAR.

## Manifest

`pipeline/deploy/manifest.json` → `ime.optional.sherpa_models`.

Legacy doc `WHISPER-STT.md` is obsolete for current builds.
