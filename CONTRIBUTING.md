# Contributing to Voice

Thanks for helping build private, on-device dictation. This guide covers setup, conventions, and how changes ship.

## Development setup

Requirements: Apple Silicon Mac, macOS 14+, Xcode 15+ (command line tools), [uv](https://docs.astral.sh/uv/).

```bash
git clone git@github.com:Wistfare/voice.git && cd voice
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python \
    "git+https://github.com/Blaizzy/mlx-audio.git" soundfile numpy pytest
./app/bundle.sh release && open Voice.app
```

The dev build runs the engine from your checkout's `.venv` — no embedded runtime needed while developing. The first launch downloads the ASR model (~1.2 GB) into the Hugging Face cache.

Useful during engine work:

```bash
.venv/bin/python engine/online_stream.py --selftest audio/long.wav   # exactness gate
.venv/bin/python tools/stream_bench.py audio/long.wav               # latency sweep
```

(Generate the test clips first with `say` — see `tools/`; the `audio/` directory is gitignored.)

## Project principles

1. **Privacy is the product.** No feature may send audio or text off-device. No telemetry.
2. **No decorative settings.** Every toggle must do exactly what it says — if it can't be implemented honestly, it doesn't ship.
3. **The design file is the spec.** UI matches `voice.pen` (open with Pencil). Design changes go to the .pen file first.
4. **Streaming correctness is sacred.** Any engine change must keep `--selftest` at EXACT MATCH and the test suite green.

## Branches, commits, PRs

- `main` is protected — all changes land via pull request with CI green and one approving review.
- Branch names: `feat/<short-topic>`, `fix/<short-topic>`, `docs/…`, `chore/…`.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/): `feat: add deferred transcription mode`, `fix(overlay): pin panel top edge`.
- A PR should be one coherent change with tests for engine/logic work and a screenshot (or screen recording) for UI work.

## Tests

```bash
.venv/bin/python -m pytest engine/tests/ -q   # fast, no model needed
swift test --package-path app
VOICE_E2E=1 .venv/bin/python -m pytest engine/tests/test_worker_protocol.py -s  # local only: mic + model
```

CI runs the first two on every PR.

## Releases

Releases are built automatically:

1. Maintainer bumps the version and tags: `git tag v0.2.0 && git push origin v0.2.0`.
2. The [Release workflow](.github/workflows/release.yml) builds the embedded runtime, the app, and the themed `Voice.dmg`, then publishes a GitHub Release with generated notes.
3. (Maintainers) Sign + notarize the DMG locally with the Wistfare Developer ID via `scripts/notarize.sh`, and replace the release asset so users get a friction-free install.

## Reporting issues

Use the issue templates. For dictation-accuracy reports, include macOS + chip, the language setting, and — if you're comfortable — the `worker.err.log` from `~/Library/Application Support/Voice/`. Never post recordings you don't want public.
