# Sherpa-ONNX dictation (Null Keyboard)

The Flip2 Null Keyboard uses **Sherpa-ONNX** ASR only (Whisper.cpp and Vosk were removed). Models live under `files/sherpa/{en,uk}/` on the app uid; the APK ships ONNX Runtime + sherpa JNI for **armeabi-v7a** (4058G).

Two engine paths, picked by `stt_lang`:

| Lang | Engine | Behaviour |
|------|--------|-----------|
| `en` | `OnlineRecognizer` (streaming zipformer) | Live partials, endpoint commit |
| `uk` | `OfflineRecognizer` (`model_type=nemo_transducer`) | Buffers the utterance, decodes once on stop |

There is **no streaming Ukrainian model upstream** — Ukrainian ships only inside offline multilingual packs, so `uk` must go through the batch recognizer. Feeding the NeMo pack to `OnlineRecognizer` kills the process (`'window_size' does not exist in the metadata`).

## Models (pinned)

| Catalog id | File | Role |
|------------|------|------|
| **sherpa-en** | `sherpa-onnx-streaming-zipformer-en-20M-2023-02-17-mobile.tar.bz2` | English zipformer transducer (mobile) |
| **sherpa-uk** | `sherpa-onnx-nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2` | Offline multilingual NeMo int8 pack; `stt_lang=uk` selects the offline path |

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

Hold `*` to listen. While listening: `#` switches EN↔UK, `*` stops. Preference key: `stt_lang` in `flip2_null_ime.xml`.

EN shows streaming partials in the status chip. UK has no partials — the text appears when you stop (or after the 12 s listen timeout).

Cold-start cost: the EN zipformer loads in well under a second, but the 131 MB UK encoder takes roughly 10 s to load on first use. It is preloaded on the IME background executor, so holding `*` immediately after a language switch may start capturing before the key release — the decode then runs on stop as usual.

## The click storm while holding `*`

Holding `*` to dictate played a click on every auto-repeat, machine-gunning into the mic. Two framework sounds are involved and they are separate settings:

| Setting | Player | Muted by |
|---------|--------|----------|
| `dtmf_tone` (= `DTMF_TONE_WHEN_DIALING`) | `ToneGenerator` in the IME | `muteDtmfTone()` (pre-existing) |
| `sound_effects_enabled` (= `SOUND_EFFECTS_ENABLED`, `FX_KEYCLICK`) | `AudioService` inside `system_server` | **`muteSoundEffects()`** |

Muting DTMF never covered the second: `AudioTrack(<system_server pid>)` started a fresh 160 ms click track (stream 1, gain `0.501187`) for each repeat. Proof was an A/B synthetic hold — with `sound_effects_enabled=0` the identical hold produced zero `AudioTrack(system_server)` starts, with it at `1` one per repeat.

The mute is scoped to the `*`/`#` press: `muteSoundEffects()` on `ACTION_DOWN`+`repeatCount==0` in `forwardKey`, `restoreSoundEffects()` on `ACTION_UP`, and on `onCreate`, `onDestroy`, `onFinishInput` and `onWindowHidden` so a dead IME process or a focus loss that swallows the KEY_UP can never leave the device silent. The original value is persisted in `SharedPreferences("flip2_ime")` under `se_orig`, the same pattern as `dtmf_orig`.

Verified on device with synthetic holds:

- 18 repeats → **one** `AudioTrack(system_server)` start, and it fires ~7 ms *before* the settings write lands (it is the initial press click, played by `PhoneWindowManager`, not reachable from the IME). The repeat clicks are what the mute removes.
- Ordinary digits still click, and `sound_effects_enabled` stays `1` throughout.
- Hold interrupted by focus loss (HOME, no release event) → restored to `1` by the lifecycle restore, before any KEY_UP arrives.

## Why Sherpa over Whisper on Flip2

Streaming transducers update text while you speak; batch Whisper (`whisper_full` on stop) felt slower on v7a CPU. `faster-whisper` is not an Android v7a drop-in. Sherpa ships official **armeabi-v7a** libs in the AAR.

## Microphone on Android 11 (foreground service)

An IME process stays `IMPORTANT_BACKGROUND` even while its window has focus, so AudioPolicyService refuses the input stream:

```
getInputForAttr permission denied: recording not allowed for uid 10111 pid ...
createRecord_l: status -1  →  Mic init failed
```

This is **not** a missing grant — `dumpsys package` shows `RECORD_AUDIO: granted=true` and appops reads `allow`; the denial is the while-in-use rule applied to a background uid. The stock `com.android.soundrecorder` records fine at the same moment, which isolates it to process state rather than the HAL.

The fix is `SttForegroundService` (`android:foregroundServiceType="microphone""), started before the `AudioRecord` is constructed and stopped when capture ends. Successful capture logs:

```
getInputForAttr() returns input 78 ... session 745
Flip2STT: fg service up
```

Legacy doc `WHISPER-STT.md` is obsolete for current builds.
