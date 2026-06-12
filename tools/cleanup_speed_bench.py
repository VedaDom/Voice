#!/usr/bin/env python3
"""Latency bench for the cleanup pass: baseline vs prompt-cache vs speculative
decoding (Gemma 4 E2B drafting for E4B) vs both. The cleanup prompt has a long
static prefix (system + few-shot examples), so prefix caching should dominate
on short per-sentence generations; speculative decoding may add on top.
"""
import time

import mlx.core as mx
from mlx_lm import load, generate
from mlx_lm.models.cache import make_prompt_cache, can_trim_prompt_cache, trim_prompt_cache
from mlx_lm.sample_utils import make_sampler

SHOTS = [
    {"role": "user", "content": "Context: We reviewed the budget.\nText: i beleive the meting is tomorow at nine"},
    {"role": "assistant", "content": "I believe the meeting is tomorrow at nine."},
    {"role": "user", "content": "Context: The answer it gave is not right.\nText: it keeps giving the long answer every time"},
    {"role": "assistant", "content": "It keeps giving the wrong answer every time."},
    {"role": "user", "content": "Context: (none)\nText: can you send me the figma link for the new on boarding flow"},
    {"role": "assistant", "content": "Can you send me the Figma link for the new onboarding flow?"},
]
SYS = ("Fix spelling, homophone and small speech-recognition errors in dictated text. "
       "Use the context to pick the intended word when the transcript misheard it. "
       "Keep the wording, tone and meaning exactly the same. "
       "Never add, remove, reorder or rephrase words — only correct errors. "
       "Output only the corrected text.")

SENTENCES = [
    ("(none)", "so basically we shud refactor the worker before the demo on thursday"),
    ("so basically we should refactor the worker before the demo on thursday",
     "the streaming pass is fine but the cleanup pass is to slow right now"),
    ("the streaming pass is fine but the cleanup pass is too slow right now",
     "i think there meeting was moved to friday afternoon"),
    ("i think their meeting was moved to friday afternoon",
     "can you here the difference when the level goes up"),
    ("can you hear the difference when the level goes up",
     "lets ship it once the tests are green and the dmg is build"),
    ("(none)", "Hello, this is Dominique speaking. I think this approach benefits everyone."),
]


def prompt_tokens(tok, ctx, text):
    msgs = ([{"role": "system", "content": SYS}] + SHOTS
            + [{"role": "user", "content": f"Context: {ctx}\nText: {text}"}])
    return tok.apply_chat_template(msgs, add_generation_prompt=True)


def run(model, tok, draft=None, use_cache=False, label=""):
    sampler = make_sampler(temp=0.0)
    cache = make_prompt_cache(model) if use_cache else None
    cached = []
    times = []
    outs = []
    for ctx, text in SENTENCES:
        toks = prompt_tokens(tok, ctx, text)
        t0 = time.time()
        kwargs = dict(max_tokens=len(text.split()) * 3 + 32,
                      sampler=sampler, verbose=False)
        if draft is not None:
            kwargs["draft_model"] = draft
        if cache is not None:
            common = 0
            for a, b in zip(cached, toks):
                if a != b:
                    break
                common += 1
            if cached and can_trim_prompt_cache(cache):
                trim_prompt_cache(cache, len(cached) - common)
                cached = cached[:common]
            kwargs["prompt_cache"] = cache
            out = generate(model, tok, prompt=toks[common:], **kwargs)
            cached = list(toks)  # generated tokens get trimmed on the next lcp pass
        else:
            out = generate(model, tok, prompt=toks, **kwargs)
        times.append(time.time() - t0)
        outs.append(out.strip())
    warm = times[1:]
    print(f"  {label:26} first {times[0]:5.2f}s   warm avg {sum(warm)/len(warm):5.2f}s   "
          f"min {min(warm):4.2f}  max {max(warm):4.2f}")
    return outs


def main():
    print("== Gemma 4 E2B (Best tier)")
    e2b, tok = load("mlx-community/gemma-4-e2b-it-4bit")
    base = run(e2b, tok, label="baseline")
    cached = run(e2b, tok, use_cache=True, label="prompt-cache")
    print("  outputs identical:", base == cached)

    print("== Gemma 4 E4B (Max tier)")
    e4b, tok4 = load("mlx-community/gemma-4-E4B-it-qat-4bit")
    base4 = run(e4b, tok4, label="baseline")
    c4 = run(e4b, tok4, use_cache=True, label="prompt-cache")
    print("  outputs identical:", base4 == c4)
    try:
        s4 = run(e4b, tok4, draft=e2b, label="speculative (E2B draft)")
        print("  outputs identical:", base4 == s4)
        sc4 = run(e4b, tok4, draft=e2b, use_cache=True, label="spec + cache")
        print("  outputs identical:", base4 == sc4)
    except Exception as e:
        print("  speculative failed:", str(e)[:160])


if __name__ == "__main__":
    main()
