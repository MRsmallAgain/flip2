# Whisper and Vosk on Flip2 (Null Keyboard STT)

> **Obsolete (2026-11):** Null Keyboard STT is **Sherpa-ONNX only**. See [SHERPA-STT.md](SHERPA-STT.md). This page is kept for historical reference.

The Null Keyboard IME uses **Whisper** (ggml `.bin` via whisper.cpp) when models exist under `files/whisper/{en,uk}/model.bin`, otherwise **Vosk** (~40 MB EN + ~75 MB UK). On the 4058G (armeabi-v7a, modest CPU), latency and size trade off directly.

## Current kit default

| Pin | File | ~Size | Notes |
|-----|------|-------|--------|
| **whisper-tiny** (catalog) | `ggml-tiny-q5_1.bin` | ~32 MB | Multilingual tiny, q5_1 — **default** wizard/install push |

One multilingual bin can be copied to both `en` and `uk` paths; the IME treats it as shared.

## Faster options (same tiny tier)

| Model | ~Size | Speed vs tiny-q5_1 | Quality |
|-------|-------|---------------------|---------|
| `ggml-tiny.en-q5_1.bin` | ~32 MB | Similar; **English-only** — slightly less work if you only use EN | EN only |
| `ggml-tiny-q8_0.bin` | ~41 MB | **Slower** (heavier quant) | Slightly better |
| Stay on **Vosk-only** | ~115 MB total | Often **faster first partial** on weak CPUs; no Whisper load | Good for EN/UK without ggml |

**Recommendation for Flip2:** keep **`ggml-tiny-q5_1`** unless you are English-only and want to try **`ggml-tiny.en-q5_1`**. Avoid q8_0 if speed is the goal. For minimum CPU at dictation start, skip Whisper and use Vosk only (`--vosk-url` on pack, no whisper push).

## Slower / heavier (better accuracy)

| Model | ~Size | Use when |
|-------|-------|----------|
| `ggml-base-q5_1.bin` | ~56 MB | Willing to wait longer per utterance on Flip2 |

Not recommended as default on 4058G.

## Install-time fetch

```bash
flip2 installer pack --flavor full \
  --whisper-url en=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin \
  --whisper-url uk=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin
```

Image v2 does **not** bundle STT models (userdata size); image-post still pushes models like `full`.

## References

- Catalog: `wizard/catalog.json` → `whisper-tiny`
- Manifest: `ime.optional.whisper_models` in `pipeline/deploy/manifest.json`
- Upstream weights: [ggerganov/whisper.cpp on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp)
