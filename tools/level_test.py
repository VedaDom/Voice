#!/usr/bin/env python3
"""Characterize when soft speech gets dropped, and whether AGC fixes it.

Sweeps the speech level (simulating speaking softer) with and without a realistic
noise floor, transcribing through the SAME streaming engine, raw vs AGC-normalized.
This separates two causes:
  * pure level  -> AGC fixes it (amplifies signal back into range)
  * low SNR     -> AGC does NOT fix it (it amplifies the noise too)

Usage: ./.venv/bin/python level_test.py
"""
import numpy as np
import soundfile as sf
import mlx.core as mx
from collections import Counter

from mlx_audio.stt import load
from online_stream import OnlineStreamer, normalize_rms, MODEL

np.random.seed(0)


def rms(a):
    return float(np.sqrt(np.mean(np.square(a))) + 1e-9)


def dbfs(a):
    return 20 * np.log10(rms(a))


def stream_text(model, audio, sr):
    s = OnlineStreamer(model, "auto")
    b = int(sr * 0.1)
    for i in range(0, len(audio), b):
        s.push(audio[i : i + b])
    s.finalize()
    return s.text.strip()


def recall(ref, hyp):
    norm = lambda t: t.lower().replace(".", "").replace(",", "").split()
    hc = Counter(norm(hyp))
    hit = 0
    for w in norm(ref):
        if hc[w] > 0:
            hc[w] -= 1
            hit += 1
    return hit, len(norm(ref))


def main():
    model = load(MODEL)
    audio, sr = sf.read("audio/long.wav", dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]
    audio = audio / (np.max(np.abs(audio)) + 1e-9) * 0.6  # ~ -20 dBFS reference
    gt = model.generate(mx.array(audio), language="auto").text.strip()
    n_words = len(gt.replace(".", "").replace(",", "").split())

    noise_dbfs = -55.0
    noise = (np.random.randn(len(audio)) * (10 ** (noise_dbfs / 20))).astype(np.float32)

    scales = [0.3, 0.1, 0.03, 0.01, 0.003]
    print(f"\nreference words: {n_words} | added-noise floor: {noise_dbfs:.0f} dBFS\n")
    print(f"{'speech dBFS':>11} | {'clean raw':>10} {'noisy raw':>10} {'noisy+AGC':>10} | SNR")
    print("-" * 62)
    for sc in scales:
        speech = (audio * sc).astype(np.float32)
        sdb = dbfs(speech)
        snr = sdb - noise_dbfs
        clean_raw = recall(gt, stream_text(model, speech, sr))[0]
        noisy = (speech + noise).astype(np.float32)
        noisy_raw = recall(gt, stream_text(model, noisy, sr))[0]
        noisy_agc = recall(gt, stream_text(model, normalize_rms(noisy), sr))[0]
        print(f"{sdb:11.1f} | {clean_raw:7d}/{n_words} {noisy_raw:7d}/{n_words} "
              f"{noisy_agc:7d}/{n_words} | {snr:4.0f} dB")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
