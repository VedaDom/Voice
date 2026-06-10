"""AGC: lifts quiet speech toward the target level, leaves silence alone."""
import numpy as np
import pytest

pytest.importorskip("mlx.core")

from online_stream import AGC, normalize_rms  # noqa: E402

SR = 16000


def _rms(x):
    return float(np.sqrt(np.mean(np.square(x))))


def test_quiet_speech_is_lifted():
    rng = np.random.default_rng(3)
    agc = AGC(SR)
    out_rms = 0.0
    for _ in range(40):  # 2 s of quiet "speech"
        block = (rng.standard_normal(int(SR * 0.05)) * 0.005).astype(np.float32)
        out, _, gain = agc.process(block)
        out_rms = _rms(out)
    assert gain > 3.0
    assert out_rms > 0.02


def test_silence_is_not_amplified():
    agc = AGC(SR)
    for _ in range(40):
        block = np.zeros(int(SR * 0.05), dtype=np.float32)
        _, _, gain = agc.process(block)
    assert gain <= 1.5  # floor guard: don't blow up the noise floor


def test_normalize_rms_targets_level():
    rng = np.random.default_rng(4)
    quiet = (rng.standard_normal(SR) * 0.004).astype(np.float32)
    out = normalize_rms(quiet, target_rms=0.06)
    assert abs(_rms(out) - 0.06) < 0.01


def test_gain_is_capped():
    rng = np.random.default_rng(5)
    nearly_silent = (rng.standard_normal(SR) * 1e-5).astype(np.float32)
    out = normalize_rms(nearly_silent, target_rms=0.06, max_gain=25.0)
    assert _rms(out) <= _rms(nearly_silent) * 25.0 * 1.01
