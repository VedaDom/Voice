#!/usr/bin/env python3
"""Run DeepFilterNet on a real recorded session (fair test on real mic noise),
then compare ASR transcripts and the noise floor before/after."""
import sys
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

from mlx_audio.stt import load
from mlx_audio.sts.models.deepfilternet import DeepFilterNetModel
from online_stream import OnlineStreamer, normalize_rms, MODEL


def dbfs(a):
    return 20 * np.log10(np.sqrt(np.mean(np.square(a))) + 1e-9)


def noise_floor(a, sr):
    n = int(sr * 0.02)
    f = a[: len(a) // n * n].reshape(-1, n)
    fdb = 20 * np.log10(np.sqrt(np.mean(f ** 2, axis=1)) + 1e-9)
    return float(np.percentile(fdb, 10))


def transcribe(model, a, sr=16000):
    s = OnlineStreamer(model, "auto")
    b = int(sr * 0.1)
    for k in range(0, len(a), b):
        s.push(a[k : k + b])
    s.finalize()
    return s.text.strip()


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "session.wav"
    asr = load(MODEL)
    print("loading DeepFilterNet ...", flush=True)
    dfn = DeepFilterNetModel.from_pretrained(model_name_or_path="mlx-community/DeepFilterNet-mlx")

    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]

    up = resample_poly(audio, 48000, 16000).astype(np.float32)
    enh = np.asarray(dfn.enhance_array(up), dtype=np.float32)
    den = resample_poly(enh, 16000, 48000).astype(np.float32)
    out = path.replace(".wav", "_denoised.wav")
    sf.write(out, den, sr, subtype="PCM_16")

    print(f"\nraw      : level {dbfs(audio):6.1f} dBFS  noise floor {noise_floor(audio, sr):6.1f} dBFS")
    print(f"denoised : level {dbfs(den):6.1f} dBFS  noise floor {noise_floor(den, sr):6.1f} dBFS"
          f"  (saved {out})")
    print(f"\nRAW           : {transcribe(asr, audio)}")
    print(f"DENOISED      : {transcribe(asr, den)}")
    print(f"DENOISED+AGC  : {transcribe(asr, normalize_rms(den))}")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
