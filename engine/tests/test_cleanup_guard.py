"""The cleanup guard must accept honest fixes and reject LLM rewrites."""
import pytest

pytest.importorskip("numpy")

import worker  # noqa: E402


class _StubEngine(worker.Engine):
    """Engine with the LLM stubbed out — guard logic only."""

    def __init__(self, replies):
        super().__init__()
        self.cleanup_model = object()  # non-None enables the path
        self.cleanup_tokenizer = object()
        self._replies = replies
        self._i = 0

    def _run_cleanup_llm(self, text, opts=None, context=""):
        reply = self._replies[self._i % len(self._replies)]
        self._i += 1
        return reply if reply is not None else text


OPTS = {"enabled": True, "typos": True}


def test_disabled_passthrough():
    e = _StubEngine(["SHOULD NEVER APPEAR"])
    assert e._maybe_cleanup("hello there friend", {"enabled": False}) == "hello there friend"
    assert e._maybe_cleanup("hello there friend", None) == "hello there friend"


def test_accepts_close_fix():
    e = _StubEngine(["I believe the meeting is tomorrow."])
    out = e._maybe_cleanup("i beleive the meting is tomorow.", OPTS)
    assert out == "I believe the meeting is tomorrow."


def test_rejects_full_rewrite():
    original = "hello this is dominique speaking about the roadmap."
    e = _StubEngine(["Greetings! Here is a totally different sentence entirely."])
    assert e._maybe_cleanup(original, OPTS) == original


def test_rejects_runaway_length():
    original = "short note about lunch."
    e = _StubEngine(["short note about lunch and also " + "padding " * 30])
    assert e._maybe_cleanup(original, OPTS) == original


def test_sentencewise_isolation():
    # first sentence gets a good fix, second gets a rewrite -> only the
    # second falls back to the original
    e = _StubEngine(["Let's gather the team at three.",
                     "Completely unrelated replacement text here."])
    out = e._maybe_cleanup("lets gather the team at three. my parents were focused on this.", OPTS)
    assert out.startswith("Let's gather the team at three.")
    assert "my parents were focused on this." in out
