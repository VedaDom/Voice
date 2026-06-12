#!/usr/bin/env python3
"""Voice engine worker — persistent process the Mac app talks to over stdio.

Protocol (JSON per line):
  stdin  commands:
    {"cmd": "setup"}                       download (if needed) + load + warm up
    {"cmd": "start", "language": "en-US", "mode": "live|deferred",
     "lookahead": 6, "save_audio": true,
     "cleanup": {"enabled": false, "typos": true, "grammar": false,
                  "style": true, "words": ["Nemotron"]}}
    {"cmd": "pause"}                       pause capture (session context kept)
    {"cmd": "resume"}                      resume capture into the same session
    {"cmd": "stop"}                        end session -> emits "final"
    {"cmd": "cancel"}                      end session, discard
    {"cmd": "retranscribe", "wav": "/path.wav", "language": "en-US", "id": "…"}
    {"cmd": "cleanup_setup"}               download + load the cleanup LLM
    {"cmd": "shutdown"}
  stdout events:
    {"event": "state", "state": "checking|downloading|loading|warming|ready|recording|paused|error", "pct": 0.42, "message": "..."}
    {"event": "cleanup_state", "state": "downloading|ready|error", "pct": 0.4, "message": "..."}
    {"event": "level", "norm": 0.63, "db": -28.4}          ~20 Hz while recording
    {"event": "partial", "text": "..."}                     cumulative transcript
    {"event": "final", "text": "...", "duration": 12.4, "wav": "/path.wav"}
    {"event": "retranscribed", "id": "…", "wav": "...", "text": "..."}

Threading: MLX arrays/streams are NOT shareable across threads, so a single
dedicated engine thread owns ALL MLX work (model load, warmup, streaming).
The stdin reader and the audio callback only put plain data on queues.

Audio: 16 kHz mono. Raw (un-gained) audio is kept for the session WAV; the
model is fed AGC-normalized audio. The RNN-T hypothesis is append-only, so
partial text only ever grows.
"""
import json
import os
import queue
import sys
import threading
import time
from pathlib import Path

import numpy as np

# online_stream.py lives next to this file in the bundled app, or at the
# project root in the dev checkout.
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))
sys.path.insert(0, str(_HERE.parent))

MODEL = "mlx-community/nemotron-3.5-asr-streaming-0.6b"
MODEL_BYTES = 1_270_000_000  # approx total download, for progress estimation
# Cleanup model tiers (Settings ▸ Models), picked by bake-off
# (tools/cleanup_bakeoff.py): "balanced" is light and safe, "best" matches the
# bigger models on standard fixes, "max" is the only one that repairs
# context-dependent homophones ("the result is long" → "wrong").
CLEANUP_MODELS = {
    "balanced": ("mlx-community/LFM2.5-350M-8bit", 380_000_000),
    "best": ("mlx-community/gemma-4-e2b-it-4bit", 1_500_000_000),
    "max": ("mlx-community/gemma-4-E4B-it-qat-4bit", 2_800_000_000),
}
DEFAULT_CLEANUP_TIER = "balanced"
SR = 16000
BLOCK_S = 0.05  # 50 ms blocks -> 20 Hz level events
DATA_DIR = Path(
    os.environ.get("VOICE_DATA_DIR")
    or Path.home() / "Library" / "Application Support" / "Voice"
)
AUDIO_DIR = DATA_DIR / "audio"

_out_lock = threading.Lock()


def emit(obj):
    with _out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def state(s, **kw):
    emit({"event": "state", "state": s, **kw})


def hf_cache_size():
    base = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
    roots = list((base / "hub").glob("models--mlx-community--nemotron*"))
    # while downloading, hf-xet stages chunks under HF_HOME/xet
    roots += [base / "xet"]
    total = 0
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            try:
                if p.is_file():
                    total += p.stat().st_size
            except OSError:
                pass
    return total


def level_norm(db):
    # map -50..-15 dBFS -> 0..1 for the overlay glow
    return float(np.clip((db + 50.0) / 35.0, 0.0, 1.0))


class Engine:
    """Single-threaded MLX owner. Everything model-related runs in run()."""

    def __init__(self):
        self.cmds = queue.Queue()
        self.audio_q = queue.Queue()
        self.model = None
        # 560 ms chunks: words land fast enough for a live overlay and keep
        # real-time headroom even when the GPU is thermally throttled.
        self.acs_right = int(os.environ.get("VOICE_LOOKAHEAD_R", "6"))
        # session state
        self.active = False
        self.mode = "live"
        self.streamer = None
        self.agc = None
        self.raw = []           # un-gained capture (saved to the note's WAV)
        self.fed = []           # AGC-normalized capture (deferred-mode input)
        self.save_audio = True
        self.cleanup_opts = None
        self.mic = None
        self.t0 = 0.0
        self.paused = False
        self.language = "en-US"
        # cleanup LLM (loaded on demand)
        self.cleanup_model = None
        self.cleanup_tokenizer = None
        self.cleanup_tier = DEFAULT_CLEANUP_TIER
        self.shutting_down = False

    # ---------------------------------------------------------------- thread
    def run(self):
        while not self.shutting_down:
            if self.active:
                self._pump_audio()
                try:
                    cmd = self.cmds.get_nowait()
                except queue.Empty:
                    continue
            else:
                try:
                    cmd = self.cmds.get(timeout=0.2)
                except queue.Empty:
                    continue
            self._dispatch(cmd)

    def _dispatch(self, msg):
        cmd = msg.get("cmd")
        if cmd == "setup":
            self._setup()
        elif cmd == "start":
            self._start(msg)
        elif cmd == "pause":
            self._pause()
        elif cmd == "resume":
            self._resume()
        elif cmd == "stop":
            self._end(discard=False)
        elif cmd == "cancel":
            self._end(discard=True)
        elif cmd == "retranscribe":
            self._retranscribe(msg)
        elif cmd == "cleanup_setup":
            self._cleanup_setup(msg)
        elif cmd == "shutdown":
            self._end(discard=True)
            self.shutting_down = True

    # ---------------------------------------------------------------- setup
    def _setup(self):
        if self.model is not None:
            state("ready")
            return
        try:
            already = hf_cache_size() > MODEL_BYTES * 0.95
            state("checking" if already else "downloading", pct=0.0)

            done = threading.Event()
            if not already:
                def poll():
                    while not done.is_set():
                        pct = min(hf_cache_size() / MODEL_BYTES, 0.99)
                        state("downloading", pct=round(pct, 3))
                        done.wait(0.5)
                threading.Thread(target=poll, daemon=True).start()

            from mlx_audio.stt import load
            model = load(MODEL)
            done.set()
            state("loading", pct=1.0)

            import mlx.core as mx
            from online_stream import OnlineStreamer

            state("warming")
            model.default_att_context_size = [56, self.acs_right]
            model.generate(mx.zeros((SR,), dtype=mx.float32), language="en-US")
            s = OnlineStreamer(model, "en-US")
            s.push(np.zeros(int(SR * 0.7), dtype=np.float32))
            s.finalize()
            self.model = model
            state("ready")
        except Exception as e:  # noqa: BLE001
            state("error", message=str(e)[:300])

    # ---------------------------------------------------------------- session
    def _start(self, msg):
        if self.model is None:
            state("error", message="engine not ready")
            return
        if self.active:
            self._end(discard=True)

        from online_stream import AGC, OnlineStreamer

        self.language = msg.get("language", "en-US")
        self.mode = msg.get("mode", "live")
        self.save_audio = bool(msg.get("save_audio", True))
        self.cleanup_opts = msg.get("cleanup") or None
        self.smart_detect = bool(msg.get("smart_detect", False)) and self.language != "auto"
        self.lang_probed = False
        right = int(msg.get("lookahead", self.acs_right))
        self.model.default_att_context_size = [56, right]

        # live mode streams incrementally; deferred mode only captures and
        # transcribes the whole take at the end (best accuracy, no live words)
        self.streamer = OnlineStreamer(self.model, self.language) if self.mode == "live" else None
        self.agc = AGC(SR)
        self.raw = []
        self.fed = []
        self.pending = []
        self.paused = False
        self.active = True
        self.t0 = time.time()
        while not self.audio_q.empty():
            self.audio_q.get_nowait()
        self._open_mic()
        state("recording")

    def _open_mic(self):
        import sounddevice as sd

        def cb(indata, frames, t, status):
            self.audio_q.put(indata[:, 0].copy())

        self.mic = sd.InputStream(
            samplerate=SR, channels=1, dtype="float32",
            blocksize=int(SR * BLOCK_S), callback=cb,
        )
        self.mic.start()

    def _close_mic(self):
        if self.mic:
            self.mic.stop()
            self.mic.close()
            self.mic = None

    def _pause(self):
        if not self.active or self.paused:
            return
        self._close_mic()
        # consume what was already captured, then idle
        while self.pending or not self.audio_q.empty():
            self._pump_audio(stopping=True)
        self.paused = True
        state("paused")

    def _resume(self):
        if not self.active or not self.paused:
            return
        self.paused = False
        self._open_mic()
        state("recording")

    # Never feed the model more than this per iteration: commands (stop,
    # cancel, pause) are only read BETWEEN iterations, so an unbounded batch
    # under backlog (e.g. thermal throttling) would make the app unresponsive.
    MAX_BATCH_S = 2.0

    def _pump_audio(self, stopping=False):
        try:
            self.pending.append(self.audio_q.get(timeout=0.0 if self.pending else 0.05))
        except queue.Empty:
            pass
        while not self.audio_q.empty():
            self.pending.append(self.audio_q.get_nowait())
        if not self.pending:
            return
        cap = max(1, int(self.MAX_BATCH_S / BLOCK_S))
        blocks, self.pending = self.pending[:cap], self.pending[cap:]
        fed = []
        for b in blocks:
            self.raw.append(b)
            if not stopping:
                db = 20 * np.log10(float(np.sqrt(np.mean(b ** 2))) + 1e-9)
                emit({"event": "level", "norm": level_norm(db), "db": round(db, 1)})
            g, _, _ = self.agc.process(b)
            fed.append(g)
            self.fed.append(g)
        if self.streamer is not None:
            new = self.streamer.push(np.concatenate(fed))
            if new and not stopping:
                emit({"event": "partial", "text": self.streamer.text})
            if not stopping:
                self._maybe_probe_language()

    def _maybe_probe_language(self):
        """Smart detect: once ~2 s of audio is in, run a quick language-ID pass
        (the model emits a language tag in auto mode). If the speaker isn't
        using the primary language, rebuild the streamer in the detected one
        and replay the buffered audio — context is only ~2 s, so it's cheap."""
        if not self.smart_detect or self.lang_probed:
            return
        total = sum(len(b) for b in self.fed)
        if total < int(SR * 2.0):
            return
        self.lang_probed = True
        try:
            from online_stream import OnlineStreamer

            audio = np.concatenate(self.fed)
            probe = OnlineStreamer(self.model, "auto")
            probe.push(audio)
            probe.finalize()
            detected = probe.detected_language
            if detected and detected != self.language:
                emit({"event": "language", "detected": detected})
                self.language = detected
                replay = OnlineStreamer(self.model, detected)
                replay.push(audio)
                self.streamer = replay
                emit({"event": "partial", "text": self.streamer.text})
        except Exception:  # noqa: BLE001 — never let the probe kill a session
            pass

    def _end(self, discard):
        if not self.active:
            return
        self._close_mic()
        if discard:
            # instant: throw the backlog away, no model work
            self.pending = []
            while not self.audio_q.empty():
                self.audio_q.get_nowait()
        else:
            # let the UI show progress while a long backlog is chewed through
            state("transcribing")
            while self.pending or not self.audio_q.empty():
                self._pump_audio(stopping=True)

            if self.streamer is not None:                       # live mode
                self.streamer.finalize()
                text = self.streamer.text.strip()
            elif self.fed:                                       # deferred mode
                import mlx.core as mx

                state("transcribing")
                audio = np.concatenate(self.fed)
                text = self.model.generate(
                    mx.array(audio), language=self.language,
                    att_context_size=[56, 13],   # max accuracy for the one pass
                ).text.strip()
            else:
                text = ""

            text = self._maybe_cleanup(text, self.cleanup_opts)
            dur = round(time.time() - self.t0, 2)
            wav_path = ""
            if self.raw and self.save_audio:
                import soundfile as sf

                AUDIO_DIR.mkdir(parents=True, exist_ok=True)
                wav_path = str(AUDIO_DIR / f"{time.strftime('%Y%m%d-%H%M%S')}.wav")
                sf.write(wav_path, np.concatenate(self.raw), SR, subtype="PCM_16")
            emit({"event": "final", "text": text, "duration": dur,
                  "wav": wav_path, "language": self.language})
        self.active = False
        self.streamer = None
        self.agc = None
        self.raw = []
        self.fed = []
        state("ready")

    # ---------------------------------------------------------- retranscribe
    def _retranscribe(self, msg):
        path = msg.get("wav", "")
        nid = msg.get("id", "")
        if self.model is None or not path or not Path(path).exists():
            emit({"event": "retranscribed", "id": nid, "wav": path, "text": "",
                  "error": "audio not available"})
            return
        try:
            import mlx.core as mx
            import soundfile as sf
            from online_stream import normalize_rms

            audio, _sr = sf.read(path, dtype="float32")
            if audio.ndim > 1:
                audio = audio[:, 0]
            audio = normalize_rms(audio)
            text = self.model.generate(
                mx.array(audio),
                language=msg.get("language", self.language),
                att_context_size=[56, 13],
            ).text.strip()
            text = self._maybe_cleanup(text, msg.get("cleanup"))
            emit({"event": "retranscribed", "id": nid, "wav": path, "text": text})
        except Exception as e:  # noqa: BLE001
            emit({"event": "retranscribed", "id": nid, "wav": path, "text": "",
                  "error": str(e)[:200]})

    # ---------------------------------------------------------------- cleanup
    def _cleanup_repo(self, tier=None):
        return CLEANUP_MODELS.get(tier or self.cleanup_tier,
                                  CLEANUP_MODELS[DEFAULT_CLEANUP_TIER])

    def _cleanup_cache_size(self, repo):
        base = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
        slug = "models--" + repo.replace("/", "--")
        total = 0
        d = base / "hub" / slug
        if d.exists():
            for p in d.rglob("*"):
                try:
                    if p.is_file():
                        total += p.stat().st_size
                except OSError:
                    pass
        return total

    def _cleanup_setup(self, msg=None):
        tier = (msg or {}).get("tier", self.cleanup_tier)
        repo, approx = self._cleanup_repo(tier)
        if self.cleanup_model is not None and tier == self.cleanup_tier:
            emit({"event": "cleanup_state", "state": "ready", "tier": tier})
            return
        try:
            already = self._cleanup_cache_size(repo) > approx * 0.9
            emit({"event": "cleanup_state", "state": "downloading", "pct": 0.0,
                  "tier": tier})
            done = threading.Event()
            if not already:
                def poll():
                    while not done.is_set():
                        pct = min(self._cleanup_cache_size(repo) / approx, 0.99)
                        emit({"event": "cleanup_state", "state": "downloading",
                              "pct": round(pct, 3), "tier": tier})
                        done.wait(0.5)
                threading.Thread(target=poll, daemon=True).start()

            from mlx_lm import load as llm_load

            model, tokenizer = llm_load(repo)
            done.set()
            self.cleanup_model = model
            self.cleanup_tokenizer = tokenizer
            self.cleanup_tier = tier
            self._run_cleanup_llm("ok")  # tiny warmup, compiles kernels
            emit({"event": "cleanup_state", "state": "ready", "tier": tier})
        except Exception as e:  # noqa: BLE001
            emit({"event": "cleanup_state", "state": "error", "message": str(e)[:200],
                  "tier": tier})

    def _maybe_cleanup(self, text, opts):
        """Optional LLM cleanup pass. A 350M model can drift on long inputs, so
        each sentence is cleaned independently and accepted ONLY if it stays
        word-similar to the original — a bad rewrite falls back to the raw
        sentence, never the whole note."""
        if (not opts or not opts.get("enabled") or self.cleanup_model is None
                or not text or len(text.split()) < 3):
            return text
        try:
            import difflib
            import re

            sentences = re.findall(r"[^.!?]+[.!?]?\s*", text)
            out = []
            for i, s in enumerate(sentences):
                s_clean = s.strip()
                if len(s_clean.split()) < 2:
                    out.append(s_clean)
                    continue
                # the PREVIOUS sentence gives the model the discourse it needs
                # to fix homophones ("long" vs "wrong") without rewriting
                context = out[-1] if out else (sentences[i - 1].strip() if i else "")
                fixed = self._run_cleanup_llm(s_clean, opts, context).strip().strip('"')
                # character-level similarity: typo fixes stay ~0.85+, while
                # rewrites fall to ~0.3-0.6 (word-level would punish every
                # corrected word as a full mismatch)
                sim = difflib.SequenceMatcher(None, s_clean.lower(),
                                              fixed.lower()).ratio()
                words_ok = 0.6 <= (len(fixed.split()) / max(len(s_clean.split()), 1)) <= 1.5
                out.append(fixed if (fixed and sim >= 0.7 and words_ok) else s_clean)
            return " ".join(out).strip() or text
        except Exception:  # noqa: BLE001
            return text

    # few-shot examples anchor the small model to "correct, don't rewrite"
    _CLEANUP_SHOTS = [
        {"role": "user",
         "content": "Context: We reviewed the budget.\nText: i beleive the meting is tomorow at nine"},
        {"role": "assistant", "content": "I believe the meeting is tomorrow at nine."},
        {"role": "user",
         "content": "Context: The answer it gave is not right.\nText: it keeps giving the long answer every time"},
        {"role": "assistant", "content": "It keeps giving the wrong answer every time."},
        {"role": "user",
         "content": "Context: (none)\nText: can you send me the figma link for the new on boarding flow"},
        {"role": "assistant", "content": "Can you send me the Figma link for the new onboarding flow?"},
    ]

    def _run_cleanup_llm(self, text, opts=None, context=""):
        opts = opts or {}
        sys_rules = ["Fix spelling, homophone and small speech-recognition errors in dictated text.",
                     "Use the context to pick the word the speaker intended when the transcript misheard it.",
                     "Keep the wording, tone and meaning exactly the same.",
                     "Never add, remove, reorder or rephrase words — only correct errors."]
        if opts.get("grammar", False):
            sys_rules.append("Also fix grammar, casing and punctuation.")
        words = [w for w in (opts.get("words") or []) if w][:40]
        if words:
            sys_rules.append("Known correct spellings: " + ", ".join(words) + ".")
        sys_rules.append("Output only the corrected text.")

        user = f"Context: {context or '(none)'}\nText: {text}"
        messages = ([{"role": "system", "content": " ".join(sys_rules)}]
                    + self._CLEANUP_SHOTS
                    + [{"role": "user", "content": user}])
        try:
            prompt = self.cleanup_tokenizer.apply_chat_template(
                messages, add_generation_prompt=True, enable_thinking=False)
        except (TypeError, ValueError):
            prompt = self.cleanup_tokenizer.apply_chat_template(
                messages, add_generation_prompt=True)

        from mlx_lm import generate
        kwargs = {"max_tokens": min(512, len(text.split()) * 3 + 32), "verbose": False}
        try:
            from mlx_lm.sample_utils import make_sampler
            kwargs["sampler"] = make_sampler(temp=0.0)
        except ImportError:
            pass
        return generate(self.cleanup_model, self.cleanup_tokenizer,
                        prompt=prompt, **kwargs)


def main():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    engine = Engine()
    thread = threading.Thread(target=engine.run, daemon=True)
    thread.start()

    emit({"event": "hello", "pid": os.getpid()})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        engine.cmds.put(msg)
        if msg.get("cmd") == "shutdown":
            break
    thread.join(timeout=20.0)
    emit({"event": "bye"})


if __name__ == "__main__":
    main()
