#!/usr/bin/env python3
"""Does denoising fix the soft-voice/low-SNR drop? Compare ASR word recall on
noisy clips with vs without DeepFilterNet enhancement (the real SNR fix).

DeepFilterNet runs at 48 kHz, so we resample 16k -> 48k -> enhance -> 16k -> ASR.
"""
import numpy as np
import soundfile as sf
import mlx.core as mx
from collections import Counter
from scipy.signal import resample_poly

from mlx_audio.stt import load
from mlx_audio.sts.models.deepfilternet import DeepFilterNetModel
from online_stream import OnlineStreamer, normalize_rms, MODEL

np.random.seed(0)


def dbfs(a):
    return 20 * np.log10(np.sqrt(np.mean(np.square(a))) + 1e-9)


def stream_text(model, audio, sr=16000):
    s = OnlineStreamer(model, "auto")
    b = int(sr * 0.1)
    for i in range(0, len(audio), b):
        s.push(audio[i : i + b])
    s.finalize()
    return s.text.strip()


def recall(ref, hyp):
    norm = lambda t: t.lower().replace(".", "").replace(",", "").split()
    hc = Counter(norm(hyp))
    hit = sum((hc.update({w: -1}) or 1) if hc[w] > 0 else 0 for w in norm(ref))
    return hit, len(norm(ref))


def denoise(dfn, audio16k):
    up = resample_poly(audio16k, 48000, 16000).astype(np.float32)
    enh = np.asarray(dfn.enhance_array(up), dtype=np.float32)
    return resample_poly(enh, 16000, 48000).astype(np.float32)


def main():
    asr = load(MODEL)
    print("loading DeepFilterNet ...", flush=True)
    dfn = DeepFilterNetModel.from_pretrained(model_name_or_path="mlx-community/DeepFilterNet-mlx")

    audio, sr = sf.read("audio/long.wav", dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]
    audio = audio / (np.max(np.abs(audio)) + 1e-9) * 0.6
    gt = asr.generate(mx.array(audio), language="auto").text.strip()
    nw = len(gt.replace(".", "").replace(",", "").split())

    noise = (np.random.randn(len(audio)) * (10 ** (-55.0 / 20))).astype(np.float32)

    print(f"\nreference words: {nw}\n")
    print(f"{'speech dBFS':>11} {'SNR':>6} | {'raw':>7} {'+AGC':>7} {'AGC>DFN':>9} {'AGC>DFN>AGC':>12}")
    print("-" * 62)
    for sc in [0.1, 0.03, 0.01]:
        speech = (audio * sc).astype(np.float32)
        noisy = (speech + noise).astype(np.float32)
        snr = dbfs(speech) - (-55.0)
        raw = recall(gt, stream_text(asr, noisy))[0]
        agc = recall(gt, stream_text(asr, normalize_rms(noisy)))[0]
        # capture-realistic pipeline: level first, then denoise
        agc_dfn = recall(gt, stream_text(asr, denoise(dfn, normalize_rms(noisy))))[0]
        agc_dfn_agc = recall(gt, stream_text(asr, normalize_rms(denoise(dfn, normalize_rms(noisy)))))[0]
        print(f"{dbfs(speech):11.1f} {snr:5.0f}dB | {raw:4d}/{nw} {agc:4d}/{nw} "
              f"{agc_dfn:6d}/{nw} {agc_dfn_agc:9d}/{nw}")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
