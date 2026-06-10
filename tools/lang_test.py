#!/usr/bin/env python3
"""Does forcing English fix the language-flip garbage on accented speech?
Re-transcribe the problem segments (and the whole file) with auto vs en-US."""
import numpy as np
import soundfile as sf
from mlx_audio.stt import load
from online_stream import OnlineStreamer, MODEL


def main():
    model = load(MODEL)
    audio, sr = sf.read("session2.wav", dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]

    def tx(a, lang):
        s = OnlineStreamer(model, lang)
        b = int(sr * 0.1)
        for k in range(0, len(a), b):
            s.push(a[k : k + b])
        s.finalize()
        return s.text.strip()

    segs = {
        "seg8  (19-35s)": (19.2, 35.4),
        "seg13 (56-57s)": (55.8, 57.5),
        "seg17 (64-66s)": (63.8, 65.8),
    }
    for name, (t0, t1) in segs.items():
        seg = audio[int(t0 * sr) : int(t1 * sr)]
        print(f"[{name}] auto : {tx(seg, 'auto')}")
        print(f"[{name}] en-US: {tx(seg, 'en-US')}")
        print()

    def nonascii(t):
        return sum(1 for c in t if ord(c) > 127)

    auto_full = tx(audio, "auto")
    en_full = tx(audio, "en-US")
    print(f"WHOLE FILE non-ASCII chars  auto={nonascii(auto_full)}  en-US={nonascii(en_full)}")
    print(f"\nen-US WHOLE FILE:\n{en_full}")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
