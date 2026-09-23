"""Public synthesis and reader behavior regressions for ticket 08."""
import io
import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def test_offline_hebrew_produces_audible_samples(monkeypatch):
    import edge_tts
    from speech_engine import engine

    def offline(*args, **kwargs):
        raise ConnectionError('Deliberately offline')

    monkeypatch.setattr(edge_tts, 'Communicate', offline)
    try:
        engine.synthesize_sentence('שלום עולם. זוהי בדיקת קול בעברית.', 'edge-he-avri')
        assert False, 'Must not succeed with silent or Carmit fallback when Avri is offline'
    except RuntimeError as exc:
        # Strict Avri: explicit error, never substituting Carmit
        assert 'Edge TTS Hebrew synthesis failed' in str(exc)


def test_unavailable_native_voice_is_an_explicit_http_error(monkeypatch):
    import edge_tts
    from fastapi.testclient import TestClient
    from speech_engine import app

    def unavailable(*args, **kwargs):
        raise OSError('Speech service unavailable')

    monkeypatch.setattr(edge_tts, 'Communicate', unavailable)
    monkeypatch.setattr(subprocess, 'run', unavailable)
    response = TestClient(app).post('/synthesize', json={'text': 'שלום עולם', 'voice': 'edge-he-avri'})
    assert response.status_code == 503
    assert 'Speech synthesis unavailable' in response.json()['detail']


def test_reader_switching_behavior():
    subprocess.run(['node', '--test', 'tests/test_reader_playback.js', 'tests/test_extension_playback.js'], cwd=ROOT, check=True)
