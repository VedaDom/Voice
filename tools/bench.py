#!/usr/bin/env python3
"""Batch-mode benchmark for an MLX STT model.

Measures: model load time, transcription wall time, real-time factor (RTF),
peak MLX (unified-memory) allocation, and process RSS.
"""
import sys, time, argparse, os, resource
import mlx.core as mx


def peak_mem_bytes():
    f = getattr(mx, "get_peak_memory", None)
    if f:
        try:
            return f()
        except Exception:
            pass
    m = getattr(mx, "metal", None)
    if m and hasattr(m, "get_peak_memory"):
        try:
            return m.get_peak_memory()
        except Exception:
            pass
    return None


def reset_peak():
    f = getattr(mx, "reset_peak_memory", None)
    if f:
        try:
            f(); return
        except Exception:
            pass
    m = getattr(mx, "metal", None)
    if m and hasattr(m, "reset_peak_memory"):
        try:
            m.reset_peak_memory()
        except Exception:
            pass


def rss_gb():
    # macOS: ru_maxrss is in bytes
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def gb(b):
    return None if b is None else round(b / 1e9, 3)


def audio_duration(path):
    import soundfile as sf
    info = sf.info(path)
    return info.frames / info.samplerate


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio", nargs="+")
    ap.add_argument("--model", default="mlx-community/nemotron-3.5-asr-streaming-0.6b")
    ap.add_argument("--language", default=None, help="e.g. en-US (None = auto)")
    ap.add_argument("--runs", type=int, default=3)
    args = ap.parse_args()

    from mlx_audio.stt import load

    print(f"[info] model = {args.model}")
    print(f"[info] language = {args.language or 'auto-detect'}")
    t0 = time.perf_counter()
    model = load(args.model)
    load_t = time.perf_counter() - t0
    print(f"[load] loaded in {load_t:.2f}s | MLX peak {gb(peak_mem_bytes())} GB | RSS {rss_gb():.2f} GB")

    def transcribe(path):
        kwargs = {}
        if args.language:
            kwargs["language"] = args.language
        res = model.generate(path, **kwargs)
        return getattr(res, "text", None) or str(res)

    for path in args.audio:
        dur = audio_duration(path)
        print(f"\n=== {os.path.basename(path)}  ({dur:.2f}s audio) ===")
        times = []
        text = ""
        for i in range(args.runs):
            reset_peak()
            t0 = time.perf_counter()
            text = transcribe(path)
            dt = time.perf_counter() - t0
            times.append(dt)
            tag = "cold" if i == 0 else f"warm{i}"
            rtf = dt / dur
            print(f"  [{tag:5}] {dt:6.3f}s  RTF={rtf:5.3f}  ({dur/dt:5.1f}x realtime)"
                  f" | MLX peak {gb(peak_mem_bytes())} GB | RSS {rss_gb():.2f} GB")
        warm = times[1:] or times
        avg = sum(warm) / len(warm)
        print(f"  --> warm avg {avg:.3f}s  RTF={avg/dur:.3f}  ({dur/avg:.1f}x realtime)")
        print(f"  TEXT: {text.strip()}")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
