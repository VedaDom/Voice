# Voice

**Private, on-device dictation for macOS.** Hold a key, speak, release — your words land in whatever app you're typing in. No account, no cloud, nothing ever leaves your Mac.

[![CI](https://github.com/Wistfare/voice/actions/workflows/ci.yml/badge.svg)](https://github.com/Wistfare/voice/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Wistfare/voice?include_prereleases)](https://github.com/Wistfare/voice/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20·%20Apple%20Silicon-black)

## Why Voice

- **Truly real-time.** Built on NVIDIA's cache-aware *streaming* FastConformer (Nemotron 3.5 ASR) — words appear as you speak, not after chunked re-processing. The streamed transcript is token-identical to the offline pass.
- **Truly private.** Speech recognition, history, audio, even the optional AI text cleanup all run locally on Apple Silicon via [MLX](https://github.com/ml-explore/mlx).
- **Lives in the menu bar.** Hold **right ⌘** anywhere to dictate; double-tap to record hands-free for minutes; tap to finish. Text pastes into the field you started in — even if you clicked away.
- **A real library.** Every dictation is saved (searchable, with audio playback) and can be **re-transcribed** later at maximum accuracy. Audio auto-deletes after a configurable retention window; transcripts are yours forever.
- **19 languages**, automatic language detection, custom vocabulary, spoken→written replacements, and an optional 350M-parameter local LLM that fixes typos after you finish.

## Install

1. Download **Voice.dmg** from the [latest release](https://github.com/Wistfare/voice/releases).
2. Drag **Voice** into **Applications** and open it.
   *If macOS warns about an unverified developer: right-click → Open, or System Settings ▸ Privacy & Security ▸ "Open Anyway".*
3. First launch downloads the speech model (~1.2 GB, one time) and walks you through Microphone + Accessibility permissions.
4. Hold **right ⌘** and talk.

**Requirements:** Apple Silicon (M1 or newer), macOS 14+, ~2 GB disk for the model.

## How it works

```
┌─ Voice.app (Swift / SwiftUI) ────────────────────────────────┐
│  menu bar · hold-to-talk hotkeys · glow overlay · library    │
│  settings · focus capture → paste · history (JSON + WAV)     │
│            │ JSON-lines over stdio                           │
│  ┌─ engine worker (Python, bundled runtime) ───────────────┐ │
│  │ mic capture → AGC → incremental mel → cache-aware       │ │
│  │ streaming FastConformer-RNNT (MLX) → append-only tokens │ │
│  │ optional: LFM2.5-350M cleanup pass · re-transcription   │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

The interesting engineering bits:

- **Append-only streaming.** The RNN-T greedy decode never revises an emitted token, so live text can be shown (or typed) the moment it appears — no backspacing, no flicker. Verified token-identical to offline decoding in tests.
- **Incremental mel front-end.** The mel spectrogram is computed only for *stable* frames as audio arrives (O(new) per push instead of O(total)), matching the offline preprocessing bit-for-bit within float tolerance — see `engine/tests/test_incremental_mel.py`.
- **One MLX thread.** MLX state is not shareable across threads; the worker owns all model work on a single engine thread fed by queues.
- **Latency dial.** The model's `att_context_size` look-ahead maps chunk sizes 80 ms→1.12 s. Voice uses 560 ms live (snappy + thermal headroom) and 1.12 s for deferred/re-transcription (max accuracy).
- **Guarded LLM cleanup.** The optional Liquid LFM2.5-350M pass fixes spelling/grammar per sentence and is only accepted when the output stays character-similar to the input — a small model can never rewrite your words wholesale.

Measured on an M5 (24 GB): streaming at ~0.2× real-time (5× headroom) in the 320 ms mode, ~2 GB unified memory, model loads in ~2 s.

## Build from source

```bash
git clone https://github.com/Wistfare/voice.git && cd voice

# 1. engine environment (Python 3.12 via uv)
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python \
    "git+https://github.com/Blaizzy/mlx-audio.git" soundfile numpy

# 2. build + run the app (uses the dev .venv automatically)
./app/bundle.sh release
open Voice.app
```

To produce a fully self-contained app (embedded Python runtime, what releases ship):

```bash
./app/make_runtime.sh        # one time: relocatable CPython + deps into app/runtime
./app/bundle.sh release      # bundles the runtime into Voice.app
./app/make_dmg.sh            # themed installer → Voice.dmg
```

Signing & notarization for distribution: see [`scripts/notarize.sh`](scripts/notarize.sh).

## Tests

```bash
.venv/bin/python -m pytest engine/tests/ -q     # engine: mel exactness, AGC, cleanup guard
swift test --package-path app                   # app: versioning, notes, post-processing
VOICE_E2E=1 .venv/bin/python -m pytest engine/tests/test_worker_protocol.py  # full loop (mic + model)
```

## Project layout

```
app/      macOS app (SwiftPM) — UI, hotkeys, paste, settings, updater
engine/   Python engine — worker protocol, streaming, AGC  (+ tests)
scripts/  icon/DMG rendering, DMG layout, notarization
tools/    research & diagnostics (benchmarks, SNR analysis, lang tests)
voice.pen Pencil design file — every screen the app implements
```

## Acknowledgements

Voice stands on excellent open work:

- [NVIDIA Nemotron 3.5 ASR](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) — the streaming speech model (NVIDIA Open Model License)
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) by Prince Canuma — MLX port of the model family
- [MLX](https://github.com/ml-explore/mlx) & [mlx-lm](https://github.com/ml-explore/mlx-lm) — Apple's array framework
- [Liquid AI LFM2.5-350M](https://huggingface.co/mlx-community/LFM2.5-350M-8bit) — optional on-device text cleanup
- [Fraunces](https://github.com/undercasetype/Fraunces) & [Inter](https://github.com/rsms/inter) typefaces (OFL)

## Contributing

PRs welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, branch conventions, and the release process. Be kind: [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © 2026 Wistfare. Downloaded models keep their own licenses (see [LICENSE](LICENSE) notes).
