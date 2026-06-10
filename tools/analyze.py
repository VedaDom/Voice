#!/usr/bin/env python3
"""Analyze a recorded mic session: noise floor, speech segments, per-segment SNR,
and per-segment transcription — to pinpoint exactly where/why words drop.

    ./.venv/bin/python analyze.py session.wav
"""
import sys
import numpy as np
import soundfile as sf

from mlx_audio.stt import load
from online_stream import OnlineStreamer, normalize_rms, MODEL

FRAME_S = 0.02


def dbfs(a):
    return 20 * np.log10(np.sqrt(np.mean(np.square(a))) + 1e-9) if len(a) else -120.0


def frame_db(a, sr):
    n = int(sr * FRAME_S)
    if n <= 0 or len(a) < n:
        return np.array([dbfs(a)]), n
    f = a[: len(a) // n * n].reshape(-1, n)
    return 20 * np.log10(np.sqrt(np.mean(f ** 2, axis=1)) + 1e-9), n


def segments(voiced, merge_gap=0.3, min_len=0.25):
    segs, start, gap = [], None, 0
    mg = int(merge_gap / FRAME_S)
    for i, v in enumerate(voiced):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap > mg:
                end = i - gap + 1
                if (end - start) * FRAME_S >= min_len:
                    segs.append((start, end))
                start, gap = None, 0
    if start is not None:
        end = len(voiced) - gap
        if (end - start) * FRAME_S >= min_len:
            segs.append((start, end))
    return segs


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "session.wav"
    model = load(MODEL)
    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]

    fdb, n = frame_db(audio, sr)
    noise_floor = float(np.percentile(fdb, 10))     # ~ quietest 10% = silence
    thresh = noise_floor + 8.0                       # speech = 8 dB above floor
    segs = segments(fdb > thresh)

    def transcribe(a):
        s = OnlineStreamer(model, "auto")
        b = int(sr * 0.1)
        for k in range(0, len(a), b):
            s.push(a[k : k + b])
        s.finalize()
        return s.text.strip()

    print(f"\nfile: {path}   {len(audio)/sr:.1f}s @ {sr}Hz")
    print(f"overall level: {dbfs(audio):6.1f} dBFS")
    print(f"noise floor  : {noise_floor:6.1f} dBFS  (speech threshold {thresh:.1f} dBFS)")
    print(f"segments     : {len(segs)} detected\n")

    print("WHOLE FILE")
    print(f"  raw : {transcribe(audio)}")
    print(f"  +AGC: {transcribe(normalize_rms(audio))}\n")

    for idx, (a, b) in enumerate(segs, 1):
        s0, s1 = a * n, b * n
        seg = audio[s0:s1]
        snr = dbfs(seg) - noise_floor
        flag = "OK" if snr >= 10 else ("WEAK" if snr >= 3 else "LOW-SNR")
        print(f"segment {idx}  {s0/sr:5.1f}-{s1/sr:5.1f}s  {dbfs(seg):6.1f} dBFS  "
              f"SNR ~{snr:4.0f} dB  [{flag}]")
        print(f"  raw : {transcribe(seg)}")
        print(f"  +AGC: {transcribe(normalize_rms(seg))}")
    print()


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
