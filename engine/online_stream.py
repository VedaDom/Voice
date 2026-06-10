#!/usr/bin/env python3
"""True online (push-based) streaming for Nemotron 3.5 ASR — the product engine.

Unlike the earlier `live.py` (energy-VAD + offline re-transcription, which clipped
word onsets and reset context), this drives the model's *native* cache-aware
streaming incrementally: every audio frame is encoded exactly once, context is
never reset, and the RNN-T hypothesis is APPEND-ONLY (emitted tokens are final —
no un-typing). It reuses the package's own `_stream_block` + decode loop, refactored
into a `push(samples)` API fed by a live mic (or a file, in --selftest).

    ./.venv/bin/python online_stream.py --selftest audio/long.wav   # prove correctness
    ./.venv/bin/python online_stream.py --mic                       # live dictation
"""
import argparse
import queue
import resource
import statistics
import sys
import time

import numpy as np
import mlx.core as mx

from mlx_audio.stt import load
from mlx_audio.stt.models.nemotron_asr import tokenizer as tok
from mlx_audio.stt.models.nemotron_asr.audio import log_mel_spectrogram
from mlx_audio.stt.models.nemotron_asr.streaming import _stream_block, _PRE_ENCODE_MEL_CACHE
from mlx_audio.stt.models.nemo.alignment import (
    AlignedToken,
    sentences_to_result,
    tokens_to_sentences,
)

MODEL = "mlx-community/nemotron-3.5-asr-streaming-0.6b"


class IncrementalMel:
    """Streaming log-mel exactly matching nemotron_asr.audio.log_mel_spectrogram.

    The offline mel uses center=True with constant padding, so frame k is the
    512-sample window centered at sample k*160. A frame is *stable* once the
    audio extends 256 samples past its center — its value can never change as
    more audio arrives. push() emits only stable frames (O(new) work, exact);
    finalize() emits the zero-padded tail frames the offline version produces.
    """

    def __init__(self, preproc):
        from mlx_audio.utils import STR_TO_WINDOW_FN, hanning, mel_filters

        self.p = preproc
        self.hop = preproc.hop_length
        self.n_fft = preproc.n_fft
        self.half = preproc.n_fft // 2
        window_fn = STR_TO_WINDOW_FN.get(preproc.window, None)
        win = window_fn(preproc.win_length) if window_fn else hanning(preproc.win_length)
        if win.shape[0] < self.n_fft:
            left = (self.n_fft - win.shape[0]) // 2
            right = self.n_fft - win.shape[0] - left
            win = mx.concatenate(
                [mx.zeros((left,), dtype=win.dtype), win, mx.zeros((right,), dtype=win.dtype)]
            )
        self.window = win
        self.filters = mel_filters(
            preproc.sample_rate, self.n_fft, preproc.features,
            norm="slaney", mel_scale="slaney",
        )
        self._y = np.zeros(0, dtype=np.float32)  # preemphasized stream
        self._last_raw = None
        self._done = 0  # frames emitted so far

    def push(self, x):
        x = np.asarray(x, dtype=np.float32)
        if x.size == 0:
            return None
        if self.p.preemph and self.p.preemph > 0:
            prev = np.float32(x[0] if self._last_raw is None else self._last_raw)
            shifted = np.concatenate([[prev], x[:-1]])
            y = x - np.float32(self.p.preemph) * shifted
            if self._last_raw is None:
                y[0] = x[0]
            self._last_raw = x[-1]
        else:
            y = x
        self._y = np.concatenate([self._y, y])
        n = len(self._y)
        stable = 0 if n < self.half else (n - self.half) // self.hop + 1
        if stable <= self._done:
            return None
        return self._frames(self._done, stable)

    def finalize(self):
        n = len(self._y)
        if n == 0:
            return None
        total = 1 + n // self.hop
        if total <= self._done:
            return None
        return self._frames(self._done, total)

    def _frames(self, f0, f1):
        n = len(self._y)
        start = f0 * self.hop - self.half
        end = (f1 - 1) * self.hop + self.half
        left = max(0, -start)
        right = max(0, end - n)
        seg = self._y[max(0, start):min(end, n)]
        if left or right:
            seg = np.pad(seg, (left, right))
        self._done = f1
        from mlx_audio.utils import stft

        s = stft(mx.array(seg), self.n_fft, self.hop, self.n_fft,
                 self.window, center=False)
        s = mx.square(mx.abs(s)).astype(mx.float32)
        m = self.filters.astype(s.dtype) @ s.T
        m = mx.log(m + mx.array(self.p.log_zero_guard_value, dtype=m.dtype))
        return mx.expand_dims(m.T, axis=0)


def normalize_rms(audio, target_rms=0.06, max_gain=25.0):
    """One-shot RMS normalization (for whole buffers / offline)."""
    rms = float(np.sqrt(np.mean(np.square(audio))) + 1e-9)
    gain = min(max_gain, target_rms / rms)
    return np.clip(audio * gain, -1.0, 1.0).astype(np.float32)


class AGC:
    """Streaming automatic gain control: track recent RMS and scale toward a
    target level, with a noise floor (don't amplify silence) and a gain cap.

    This is why quiet/soft speech survives: the model uses `normalize: NA`, so
    it needs the waveform near training levels. AGC lifts a soft voice into range
    without dropping anything (unlike a VAD gate)."""

    def __init__(self, sr, target_rms=0.06, max_gain=25.0, floor_rms=0.0015,
                 window_s=0.8, smooth=0.25):
        self.sr = sr
        self.target = target_rms
        self.max_gain = max_gain
        self.floor = floor_rms
        self.window_s = window_s
        self.smooth = smooth
        self.ema = None
        self.gain = 1.0

    def process(self, block):
        dur = max(len(block) / self.sr, 1e-3)
        a = min(1.0, dur / self.window_s)
        rms = float(np.sqrt(np.mean(np.square(block))) + 1e-9)
        self.ema = rms if self.ema is None else (1 - a) * self.ema + a * rms
        desired = 1.0 if self.ema < self.floor else float(
            np.clip(self.target / self.ema, 0.5, self.max_gain))
        self.gain = (1 - self.smooth) * self.gain + self.smooth * desired
        out = np.clip(block * self.gain, -1.0, 1.0).astype(np.float32)
        return out, rms, self.gain


class OnlineStreamer:
    """Feed mono 16 kHz float32 audio via push(); get newly-finalized tokens back."""

    def __init__(self, model, language="auto", att_context_size=None):
        self.model = model
        self.language = language or model.default_language
        self.acs = att_context_size or model.default_att_context_size
        enc = model.encoder
        self.sf = enc.args.subsampling_factor
        self.conv_left = enc.args.conv_kernel_size - 1
        self.left_cache = int(self.acs[0])
        self.chunk_frames = int(self.acs[1]) + 1          # native chunk (encoder frames)
        self.chunk_mel = self.chunk_frames * self.sf      # mel frames per chunk
        self.preproc = model.preprocessor_config
        self.frame_sec = self.sf * self.preproc.hop_length / self.preproc.sample_rate
        n = len(enc.layers)
        # encoder streaming state (mirrors streaming.stream_encode locals)
        self.attn_cache = [None] * n
        self.conv_cache = [None] * n
        self.mel_cache = None
        self.emitted = 0
        self.consumed = 0
        # RNN-T decoder streaming state (mirrors nemotron_asr.stream_generate locals)
        self.last_token = model.blank_id
        self.decoder_hidden = None
        self.hypothesis: list[AlignedToken] = []
        self.global_time = 0
        self._token_ids: list[int] = []  # every emitted id, incl. special tags
        # streaming mel front-end (exact, O(new) per push)
        self._imel = IncrementalMel(self.preproc)
        self._mel = None  # accumulated stable mel (1, T, features)

    # --- encoder: emit prompted encoder frames for any newly-complete chunks ----
    def _encode(self, mel, final):
        enc = self.model.encoder
        total = mel.shape[1]
        outs = []
        # During streaming, hold back the bleeding edge (strict <) so the final
        # look-ahead frames are emitted only at finalize(final=True).
        while self.consumed < total and (final or self.consumed + self.chunk_mel < total):
            m = mel[:, self.consumed : self.consumed + self.chunk_mel]
            if m.shape[1] == 0:
                break
            cache_len = 0 if self.mel_cache is None else self.mel_cache.shape[1]
            win = m if self.mel_cache is None else mx.concatenate([self.mel_cache, m], axis=1)
            sub = enc.pre_encode(win, mx.array([win.shape[1]], dtype=mx.int32))[0]
            end = self.consumed + m.shape[1]
            is_final = final and end >= total
            base = (self.consumed - cache_len) // self.sf
            lo = self.emitted - base
            hi = sub.shape[1] if is_final else (end // self.sf - base)
            self.consumed = end
            self.mel_cache = win[:, -_PRE_ENCODE_MEL_CACHE:]
            if hi <= lo:
                self.emitted = base + max(lo, hi)
                continue
            self.emitted = base + hi
            h = sub[:, lo:hi]
            for li, block in enumerate(enc.layers):
                h, self.attn_cache[li], self.conv_cache[li] = _stream_block(
                    block, h, enc.pos_enc, self.attn_cache[li],
                    self.conv_cache[li], self.left_cache, self.conv_left,
                )
            outs.append(self.model.apply_prompt(h, self.language))
        return outs

    # --- RNN-T greedy decode over one prompted chunk (append-only) --------------
    def _decode(self, prompted):
        m = self.model
        new = []
        chunk_len = prompted.shape[1]
        t = 0
        new_symbols = 0
        while t < chunk_len:
            feature = prompted[:, t : t + 1]
            cur = (mx.array([[self.last_token]], dtype=mx.int32)
                   if self.last_token != m.blank_id else None)
            dec_out, (h, c) = m.decoder(cur, self.decoder_hidden)
            dec_out = dec_out.astype(feature.dtype)
            proposed = (h.astype(feature.dtype), c.astype(feature.dtype))
            pred = int(mx.argmax(m.joint(feature, dec_out)))
            if pred != m.blank_id:
                self.last_token = pred
                self.decoder_hidden = proposed
                self._token_ids.append(pred)
                if not tok.is_special_token(pred, m.vocabulary):
                    a = AlignedToken(pred, start=(self.global_time + t) * self.frame_sec,
                                     duration=self.frame_sec,
                                     text=tok.decode([pred], m.vocabulary))
                    self.hypothesis.append(a)
                    new.append(a)
                new_symbols += 1
                if m.max_symbols is not None and new_symbols >= m.max_symbols:
                    t += 1
                    new_symbols = 0
            else:
                t += 1
                new_symbols = 0
        self.global_time += chunk_len
        return new

    def _append_mel(self, m):
        if m is None:
            return
        self._mel = m if self._mel is None else mx.concatenate([self._mel, m], axis=1)
        mx.eval(self._mel)

    def push(self, samples):
        self._append_mel(self._imel.push(samples))
        if self._mel is None:
            return []
        new = []
        for p in self._encode(self._mel, final=False):
            new += self._decode(p)
        return new

    def finalize(self):
        self._append_mel(self._imel.finalize())
        if self._mel is None:
            return []
        new = []
        for p in self._encode(self._mel, final=True):
            new += self._decode(p)
        return new

    @property
    def text(self):
        return sentences_to_result(tokens_to_sentences(self.hypothesis)).text

    @property
    def detected_language(self):
        """Locale tag the model emitted in auto mode (e.g. "en-US"), or None."""
        try:
            return tok.detected_language(self._token_ids, self.model.vocabulary)
        except Exception:  # noqa: BLE001
            return None


def _rss():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9


def selftest(model, path, language, block_ms):
    import soundfile as sf

    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio[:, 0]
    dur = len(audio) / sr
    block = int(sr * block_ms / 1000)

    # warm up streaming kernels so timing reflects steady state
    OnlineStreamer(model, language).finalize()

    streamer = OnlineStreamer(model, language)
    shown = ""
    enc_times = []
    counts = []
    t_start = time.perf_counter()
    for i in range(0, len(audio), block):
        chunk = audio[i : i + block]
        t0 = time.perf_counter()
        new = streamer.push(chunk)
        dt = time.perf_counter() - t0
        if new:
            enc_times.append(dt)
        counts.append(len(streamer.hypothesis))
        if new:
            shown += "".join(a.text for a in new)
            sys.stdout.write(f"\r\033[K… {shown[-110:]}")
            sys.stdout.flush()
    streamer.finalize()
    wall = time.perf_counter() - t_start
    sys.stdout.write("\r\033[K")

    online_text = streamer.text.strip()
    offline_text = model.generate(path, language=language,
                                  att_context_size=streamer.acs).text.strip()

    print(f"audio duration      : {dur:.2f}s   (fed in {block_ms}ms blocks)")
    print(f"streaming wall time : {wall:.2f}s   ->  {dur/wall:.1f}x faster than real-time")
    if enc_times:
        print(f"compute per chunk   : mean {statistics.mean(enc_times)*1000:.1f}ms  "
              f"max {max(enc_times)*1000:.1f}ms   (chunk = {self_chunk_ms(streamer)}ms)")
    print(f"peak memory (RSS)   : {_rss():.2f} GB")
    print(f"append-only check   : {'PASS' if counts == sorted(counts) else 'FAIL'} "
          f"(hypothesis token count never decreased)")
    print()
    print(f"ONLINE  (streamed)  : {online_text}")
    print(f"OFFLINE (generate)  : {offline_text}")
    print()
    if online_text == offline_text:
        print("RESULT: ✅ EXACT MATCH — streamed transcript == offline, no words lost.")
    else:
        print("RESULT: ⚠️ mismatch — diffing:")
        import difflib
        for line in difflib.unified_diff(offline_text.split(), online_text.split(),
                                         "offline", "online", lineterm=""):
            print("   ", line)


def self_chunk_ms(streamer):
    return int(streamer.chunk_frames * streamer.frame_sec * 1000)


def _dbfs(rms):
    return 20 * np.log10(rms + 1e-9)


def _meter_bar(dbfs, width=40):
    level = int(np.clip((dbfs + 60) / 60 * width, 0, width))
    return "#" * level + "-" * (width - level)


def mic(model, language, att_context_size, use_agc=True, fixed_gain=None,
        target_rms=0.06, meter=False):
    import sounddevice as sd

    SR = model.preprocessor_config.sample_rate
    streamer = OnlineStreamer(model, language, att_context_size)
    agc = AGC(SR, target_rms=target_rms) if (use_agc and fixed_gain is None) else None
    mode = ("AGC on" if agc else f"fixed gain x{fixed_gain}" if fixed_gain else "no gain")
    OnlineStreamer(model, language, att_context_size).finalize()  # warm up

    q: "queue.Queue[np.ndarray]" = queue.Queue()

    def cb(indata, frames, t, status):
        if status:
            print(status, file=sys.stderr)
        q.put(indata[:, 0].copy())

    if meter:
        print("Input level meter (raw mic). Speak loud, then soft. Ctrl-C to stop.\n", flush=True)
        with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                            blocksize=int(SR * 0.1), callback=cb):
            try:
                while True:
                    block = q.get()
                    raw = float(np.sqrt(np.mean(np.square(block))) + 1e-9)
                    g = agc.process(block)[2] if agc else 1.0
                    sys.stdout.write(f"\r[{_meter_bar(_dbfs(raw))}] {_dbfs(raw):6.1f} dBFS"
                                     f"  ->  gain x{g:4.1f}")
                    sys.stdout.flush()
            except KeyboardInterrupt:
                print()
        return

    print(f"chunk = {self_chunk_ms(streamer)}ms look-ahead | language = {language} | {mode}")
    print("Ready. Speak — words appear as the model finalizes them. Ctrl-C to stop.\n", flush=True)
    with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                        blocksize=int(SR * 0.1), callback=cb):
        try:
            while True:
                block = q.get()
                if fixed_gain is not None:
                    block = np.clip(block * fixed_gain, -1.0, 1.0).astype(np.float32)
                elif agc:
                    block, _, _ = agc.process(block)
                for a in streamer.push(block):
                    sys.stdout.write(a.text)
                    sys.stdout.flush()
        except KeyboardInterrupt:
            for a in streamer.finalize():
                sys.stdout.write(a.text)
            print("\n\n--- final ---")
            print(streamer.text.strip())


def record_session(model, language, att_context_size, prefix, use_agc=True,
                   fixed_gain=None, target_rms=0.06):
    """Record the RAW mic to <prefix>.wav (+ .jsonl metrics + .txt transcript) for
    offline analysis. Records un-gained audio so true levels/SNR are preserved;
    the live transcript still uses the chosen gain so you see product behavior."""
    import json
    import sounddevice as sd
    import soundfile as sf

    SR = model.preprocessor_config.sample_rate
    streamer = OnlineStreamer(model, language, att_context_size)
    agc = AGC(SR, target_rms=target_rms) if (use_agc and fixed_gain is None) else None
    OnlineStreamer(model, language, att_context_size).finalize()  # warm up

    wav_path, log_path, txt_path = prefix + ".wav", prefix + ".jsonl", prefix + ".txt"
    raw_chunks = []
    logf = open(log_path, "w")
    q: "queue.Queue[np.ndarray]" = queue.Queue()

    def cb(indata, frames, t, status):
        if status:
            print(status, file=sys.stderr)
        q.put(indata[:, 0].copy())

    print(f"Recording -> {wav_path}")
    print("Suggested: say the SAME sentence 3x — NORMAL, then SOFT, then WHISPER,")
    print("pausing ~1s between, then stay silent ~3s (captures the noise floor).")
    print("Ctrl-C to stop.\n", flush=True)

    t0 = time.perf_counter()
    last_log = -1.0
    shown = ""
    try:
        with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                            blocksize=int(SR * 0.1), callback=cb):
            while True:
                block = q.get()
                raw_chunks.append(block)  # RAW (un-gained) for true-SNR analysis
                raw_rms = float(np.sqrt(np.mean(np.square(block))) + 1e-9)
                gain = 1.0
                fed = block
                if fixed_gain is not None:
                    fed = np.clip(block * fixed_gain, -1.0, 1.0).astype(np.float32)
                    gain = fixed_gain
                elif agc:
                    fed, _, gain = agc.process(block)
                for a in streamer.push(fed):
                    shown += a.text
                t = time.perf_counter() - t0
                if t - last_log >= 0.5:
                    last_log = t
                    logf.write(json.dumps({"t": round(t, 2), "raw_dbfs": round(_dbfs(raw_rms), 1),
                                           "gain": round(float(gain), 2),
                                           "tokens": len(streamer.hypothesis)}) + "\n")
                    logf.flush()
                    sys.stdout.write(f"\r\033[K[{_meter_bar(_dbfs(raw_rms))}] "
                                     f"{_dbfs(raw_rms):6.1f}dBFS  {shown[-50:]}")
                    sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    for a in streamer.finalize():
        shown += a.text
    logf.close()
    sys.stdout.write("\r\033[K")

    audio = np.concatenate(raw_chunks) if raw_chunks else np.zeros(0, np.float32)
    sf.write(wav_path, audio, SR, subtype="PCM_16")
    final = streamer.text.strip()
    with open(txt_path, "w") as f:
        f.write(f"settings: language={language} acs={streamer.acs} "
                f"gain={'agc' if agc else (fixed_gain or 'off')} duration_s={len(audio)/SR:.2f}\n\n")
        f.write("final live transcript (chosen gain):\n" + final + "\n\n")
        f.write("token timeline (start_s\ttext):\n")
        for tk in streamer.hypothesis:
            f.write(f"{tk.start:6.2f}\t{tk.text}\n")
    print(f"Saved:\n  {wav_path}  (raw mic, {len(audio)/SR:.1f}s)\n  {log_path}\n  {txt_path}")
    print(f"\nLive transcript: {final}")
    print("\nDone — tell me it's recorded and I'll analyze the WAV directly "
          "(./.venv/bin/python analyze.py %s)." % wav_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", metavar="WAV", help="feed a file incrementally and verify vs offline")
    ap.add_argument("--mic", action="store_true", help="live microphone dictation")
    ap.add_argument("--language", default="auto")
    ap.add_argument("--block-ms", type=int, default=100, help="selftest feed block size")
    ap.add_argument("--right", type=int, default=None,
                    help="att_context look-ahead R (0/3/6/13). Default = model default (13).")
    ap.add_argument("--no-agc", action="store_true", help="disable automatic gain control")
    ap.add_argument("--gain", type=float, default=None, help="apply a fixed input gain instead of AGC")
    ap.add_argument("--target-rms", type=float, default=0.06, help="AGC target level")
    ap.add_argument("--meter", action="store_true", help="show a live input-level meter (no transcription)")
    ap.add_argument("--record", metavar="PREFIX", default=None,
                    help="record raw mic to PREFIX.wav (+ .jsonl/.txt) for analysis")
    args = ap.parse_args()

    print(f"Loading {MODEL} ...", flush=True)
    model = load(MODEL)
    acs = [56, args.right] if args.right is not None else None

    if args.selftest:
        if acs:
            model.default_att_context_size = acs
        selftest(model, args.selftest, args.language, args.block_ms)
    elif args.record:
        record_session(model, args.language, acs, args.record, use_agc=not args.no_agc,
                       fixed_gain=args.gain, target_rms=args.target_rms)
    elif args.mic:
        mic(model, args.language, acs, use_agc=not args.no_agc, fixed_gain=args.gain,
            target_rms=args.target_rms, meter=args.meter)
    else:
        print("Nothing to do: pass --selftest WAV, --mic, or --record PREFIX")


if __name__ == "__main__":
    main()
