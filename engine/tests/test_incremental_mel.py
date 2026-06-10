"""IncrementalMel must match the offline mel front-end the model was built on.

These tests need mlx / mlx-audio but no model download or microphone.
"""
import numpy as np
import pytest

mx = pytest.importorskip("mlx.core")
pytest.importorskip("mlx_audio")

from mlx_audio.stt.models.nemotron_asr.audio import log_mel_spectrogram  # noqa: E402
from mlx_audio.stt.models.nemotron_asr.config import PreprocessArgs  # noqa: E402

from online_stream import IncrementalMel  # noqa: E402


def _stream(audio, chunks, p):
    im = IncrementalMel(p)
    parts = []
    i = 0
    rng = np.random.default_rng(7)
    while i < len(audio):
        n = int(rng.integers(*chunks))
        m = im.push(audio[i:i + n])
        i += n
        if m is not None:
            parts.append(np.array(m))
    tail = im.finalize()
    if tail is not None:
        parts.append(np.array(tail))
    return np.concatenate(parts, axis=1)


@pytest.mark.parametrize("seconds,chunks", [(3.0, (400, 4000)), (1.2, (160, 800))])
def test_matches_offline_mel(seconds, chunks):
    p = PreprocessArgs()
    rng = np.random.default_rng(1)
    audio = (rng.standard_normal(int(p.sample_rate * seconds)) * 0.1).astype(np.float32)

    ref = np.array(log_mel_spectrogram(mx.array(audio), p))
    inc = _stream(audio, chunks, p)

    assert ref.shape == inc.shape
    # fp accumulation differs per matmul shape; anything < 1e-2 is far below
    # the bf16 encoder's own quantization step
    assert float(np.abs(ref - inc).max()) < 1e-2


def test_push_emits_only_stable_frames():
    p = PreprocessArgs()
    im = IncrementalMel(p)
    # 100 ms: 1600 samples -> stable frames = (1600-256)//160 + 1 = 9
    m = im.push(np.zeros(1600, dtype=np.float32))
    assert m is not None and m.shape[1] == 9
    # finalize adds the zero-padded tail the offline version produces: total 11
    tail = im.finalize()
    assert tail is not None and m.shape[1] + tail.shape[1] == 1 + 1600 // 160
