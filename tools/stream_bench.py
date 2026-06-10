#!/usr/bin/env python3
"""Streaming latency benchmark for Nemotron 3.5 ASR (MLX).

For each native latency mode (att_context_size [56,R]), feed the audio through
stream_generate and measure the COMPUTE time per emitted chunk. Real-time live
streaming is feasible only if per-chunk compute < the chunk's real-time duration.

Perceived end-to-end latency ≈ chunk_duration (wait for chunk to fill)
                             + per-chunk compute (processing).
"""
import time, argparse, statistics, resource
import mlx.core as mx
import soundfile as sf
from mlx_audio.stt import load

FRAME_SEC = 0.08  # 8 (subsampling) * 160 (hop) / 16000 (sr)

MODES = [
    ("80ms   [56,0]", [56, 0]),
    ("320ms  [56,3]", [56, 3]),
    ("560ms  [56,6]", [56, 6]),
    ("1120ms [56,13]", [56, 13]),
]


def peak_gb():
    f = getattr(mx, "get_peak_memory", None)
    if f:
        try:
            return round(f() / 1e9, 2)
        except Exception:
            pass
    return None


def reset_peak():
    f = getattr(mx, "reset_peak_memory", None)
    if f:
        try:
            f()
        except Exception:
            pass


def rss_gb():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def stream_once(model, audio, language):
    """Run one streaming pass; return (per_chunk_times, final_text)."""
    times, last, final = [], time.perf_counter(), ""
    for res in model.stream_generate(audio, language=language):
        now = time.perf_counter()
        times.append(now - last)
        last = now
        final = res.text
    return times, final


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--model", default="mlx-community/nemotron-3.5-asr-streaming-0.6b")
    ap.add_argument("--language", default="auto")
    args = ap.parse_args()

    dur = sf.info(args.audio).frames / sf.info(args.audio).samplerate

    t0 = time.perf_counter()
    model = load(args.model)
    print(f"[load] model loaded from disk in {time.perf_counter()-t0:.2f}s "
          f"| peak {peak_gb()} GB | RSS {rss_gb():.2f} GB")
    print(f"[info] audio = {args.audio}  ({dur:.2f}s)  language = {args.language}\n")

    print(f"{'mode':16} {'chunk':>7} {'n':>4} {'mean':>8} {'p90':>8} {'max':>8} "
          f"{'streamRTF':>10} {'headroom':>9} {'~latency':>9}")
    print("-" * 92)

    results = {}
    for name, acs in MODES:
        model.default_att_context_size = acs
        # warm-up pass (compiles streaming kernels for this window) — discarded
        stream_once(model, args.audio, args.language)
        # timed pass
        reset_peak()
        times, final = stream_once(model, args.audio, args.language)

        chunk_sec = (acs[1] + 1) * FRAME_SEC
        warm = times[1:] or times  # drop first chunk (kernel/cache spin-up)
        mean = statistics.mean(warm)
        p90 = sorted(warm)[min(len(warm) - 1, int(0.9 * len(warm)))]
        mx_t = max(warm)
        stream_rtf = sum(times) / dur
        headroom = chunk_sec / mean
        perceived = (chunk_sec + mean) * 1000  # ms

        results[name] = final
        print(f"{name:16} {chunk_sec*1000:5.0f}ms {len(times):4d} "
              f"{mean*1000:6.1f}ms {p90*1000:6.1f}ms {mx_t*1000:6.1f}ms "
              f"{stream_rtf:10.3f} {headroom:7.1f}x {perceived:7.0f}ms")

    print(f"\n[mem] streaming peak {peak_gb()} GB | process RSS {rss_gb():.2f} GB\n")
    print("Final transcripts per mode (should be near-identical):")
    for name, text in results.items():
        print(f"  {name:16} {text.strip()}")


if __name__ == "__main__":
    main()
import sys as _sys  # ENGINE_PATH_SHIM
from pathlib import Path as _P
_sys.path.insert(0, str(_P(__file__).resolve().parent.parent / 'engine'))
