#!/usr/bin/env python3
"""Live microphone dictation demo for Nemotron 3.5 ASR (MLX), fully on-device.

Captures the mic at 16 kHz, shows a live (partial) transcript as you speak, and
commits a final line when you pause. Press Ctrl-C to quit.

This demo uses rolling re-transcription of the current utterance (simple + robust)
and resets on silence so each utterance stays short. For a production app the
incremental `model.stream_generate(...)` path (O(n), no recompute) is preferred.

Run:
    ./.venv/bin/python live.py                 # auto language detection
    ./.venv/bin/python live.py --language en-US # force a language
"""
import argparse
import queue
import sys
import time

import numpy as np
import mlx.core as mx
import sounddevice as sd
from mlx_audio.stt import load

SR = 16000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="mlx-community/nemotron-3.5-asr-streaming-0.6b")
    ap.add_argument("--language", default="auto", help='e.g. en-US, es-ES, or "auto"')
    ap.add_argument("--silence", type=float, default=0.7,
                    help="seconds of silence that ends an utterance")
    ap.add_argument("--threshold", type=float, default=0.012,
                    help="RMS energy below which audio is treated as silence")
    ap.add_argument("--refresh", type=float, default=0.35,
                    help="seconds between partial-transcript refreshes")
    ap.add_argument("--max-utt", type=float, default=30.0,
                    help="force-commit an utterance after this many seconds")
    args = ap.parse_args()

    print(f"Loading {args.model} ...", flush=True)
    model = load(args.model)
    # Warm up so the first real utterance isn't slowed by kernel compilation.
    model.generate(mx.zeros((SR,), dtype=mx.float32), language=args.language)
    print(f"Ready. Language = {args.language}. Speak — pause to commit a line. Ctrl-C to quit.\n",
          flush=True)

    q: "queue.Queue[np.ndarray]" = queue.Queue()

    def callback(indata, frames, time_info, status):
        if status:
            print(f"[audio] {status}", file=sys.stderr)
        q.put(indata[:, 0].copy())

    def transcribe(buf: np.ndarray) -> str:
        res = model.generate(mx.array(buf), language=args.language)
        return res.text.strip()

    buf = np.zeros(0, dtype=np.float32)
    in_speech = False
    silence_run = 0.0          # seconds of trailing silence
    since_refresh = 0.0        # seconds of audio since last partial refresh
    last_partial = ""

    def commit():
        nonlocal buf, in_speech, silence_run, since_refresh, last_partial
        if buf.size > SR * 0.2:  # ignore sub-200ms blips
            text = transcribe(buf)
            if text:
                print(f"\r\033[K✓ {text}")
        buf = np.zeros(0, dtype=np.float32)
        in_speech = False
        silence_run = 0.0
        since_refresh = 0.0
        last_partial = ""

    with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                        blocksize=int(SR * 0.1), callback=callback):
        try:
            while True:
                block = q.get()
                dur = len(block) / SR
                rms = float(np.sqrt(np.mean(block ** 2)) + 1e-9)
                voiced = rms >= args.threshold

                if voiced:
                    in_speech = True
                    silence_run = 0.0
                elif in_speech:
                    silence_run += dur

                if in_speech:
                    buf = np.concatenate([buf, block])
                    since_refresh += dur
                    # live partial transcript
                    if since_refresh >= args.refresh:
                        since_refresh = 0.0
                        text = transcribe(buf)
                        if text and text != last_partial:
                            last_partial = text
                            sys.stdout.write(f"\r\033[K… {text}")
                            sys.stdout.flush()
                    # end-of-utterance conditions
                    if silence_run >= args.silence or len(buf) / SR >= args.max_utt:
                        commit()
        except KeyboardInterrupt:
            commit()
            print("\nDone.")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
