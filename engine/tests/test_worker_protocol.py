"""End-to-end worker protocol test (needs the ASR model + a microphone).

Gated behind VOICE_E2E=1 — run locally with:
    VOICE_E2E=1 .venv/bin/python -m pytest engine/tests/test_worker_protocol.py -s
"""
import json
import os
import subprocess
import threading
import time
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    os.environ.get("VOICE_E2E") != "1",
    reason="end-to-end test: needs the ASR model and a microphone (set VOICE_E2E=1)",
)

ROOT = Path(__file__).resolve().parent.parent.parent


def test_protocol_roundtrip():
    py = ROOT / ".venv" / "bin" / "python"
    p = subprocess.Popen(
        [str(py), str(ROOT / "engine" / "worker.py")],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True,
    )
    events = {"level": 0}
    ready = threading.Event()
    final = {}

    def reader():
        for line in p.stdout:
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            ev = e.get("event")
            events[ev] = events.get(ev, 0) + 1
            if ev == "state" and e.get("state") in ("ready", "error"):
                ready.set()
            if ev == "final":
                final.update(e)

    threading.Thread(target=reader, daemon=True).start()

    def send(obj):
        p.stdin.write(json.dumps(obj) + "\n")
        p.stdin.flush()

    try:
        send({"cmd": "setup"})
        assert ready.wait(timeout=300), "engine never became ready"
        send({"cmd": "start", "language": "en-US", "mode": "live"})
        time.sleep(3)
        send({"cmd": "stop"})
        time.sleep(6)
        send({"cmd": "shutdown"})
        time.sleep(1)
    finally:
        p.terminate()

    assert events["level"] > 20, "level events should stream at ~20 Hz"
    assert "text" in final, "stop must produce a final event"
