#!/usr/bin/env python3
"""Bake-off: which small local LLM best corrects ASR errors WITH context,
without rewriting clean text? Candidates run with the worker's actual prompt
shape (few-shot + context line + guard-compatible output).
"""
import difflib
import time

from mlx_lm import load, generate
from mlx_lm.sample_utils import make_sampler

CANDIDATES = [
    "mlx-community/LFM2.5-350M-8bit",          # current
    "mlx-community/gemma-3-1b-it-4bit",
    "mlx-community/LFM2.5-1.2B-Instruct-4bit",
    "mlx-community/Qwen3-1.7B-4bit",
]

SHOTS = [
    {"role": "user", "content": "Context: We reviewed the budget.\nText: i beleive the meting is tomorow at nine"},
    {"role": "assistant", "content": "I believe the meeting is tomorrow at nine."},
    {"role": "user", "content": "Context: (none)\nText: can you send me the figma link for the new on boarding flow"},
    {"role": "assistant", "content": "Can you send me the Figma link for the new onboarding flow?"},
]

SYS = ("Fix spelling, homophone and small speech-recognition errors in dictated text. "
       "Use the context to pick the intended word when the transcript misheard it. "
       "Keep the wording, tone and meaning exactly the same. "
       "Never add, remove, reorder or rephrase words — only correct errors. "
       "Output only the corrected text.")

# (context, text, what we hope changes / stays)
TESTS = [
    ("You see, it was supposed to be not right.",
     "Like it is very long, the word the model used.",
     "long → wrong"),
    ("I checked the numbers twice and they do not add up.",
     "The result is long, we need to fix it before the demo.",
     "long → wrong"),
    ("(none)", "Can you here me now?", "here → hear"),
    ("(none)", "Their going to the meeting at three.", "Their → They're"),
    ("(none)",
     "Hello, this is Dominique speaking. I think we should do this in a way that benefits all humankind.",
     "MUST STAY UNCHANGED"),
]


def main():
    for repo in CANDIDATES:
        print(f"\n{'='*70}\n{repo}")
        try:
            t0 = time.time()
            model, tok = load(repo)
            print(f"  load: {time.time()-t0:.1f}s")
        except Exception as e:
            print(f"  LOAD FAILED: {e}")
            continue
        for ctx, text, hope in TESTS:
            msgs = ([{"role": "system", "content": SYS}] + SHOTS
                    + [{"role": "user", "content": f"Context: {ctx}\nText: {text}"}])
            try:
                prompt = tok.apply_chat_template(msgs, add_generation_prompt=True,
                                                 enable_thinking=False)
            except TypeError:
                prompt = tok.apply_chat_template(msgs, add_generation_prompt=True)
            t0 = time.time()
            out = generate(model, tok, prompt=prompt,
                           max_tokens=len(text.split()) * 3 + 48,
                           sampler=make_sampler(temp=0.0), verbose=False).strip()
            dt = time.time() - t0
            sim = difflib.SequenceMatcher(None, text.lower(), out.lower()).ratio()
            print(f"  [{hope}] {dt:.2f}s sim={sim:.2f}")
            print(f"    IN : {text}")
            print(f"    OUT: {out[:140]}")
        del model
        import mlx.core as mx
        mx.clear_cache()


if __name__ == "__main__":
    main()
