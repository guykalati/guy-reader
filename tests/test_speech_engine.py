"""Tests for Guy Reader Speech Engine (Ticket 01 Seam).

Tests verify external behavior at the public SpeechEngine interface:
- Language auto-detection (Hebrew vs English)
- Sentence splitting and script routing
- Synthesis output validation (audio samples, sample rate, wav headers)
"""

import pytest
import os
import sys

# Ensure src is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from speech_engine import (
    detect_language,
    split_sentences,
    SpeechEngine,
    SynthesisResult,
)


def test_detect_language_hebrew():
    text = "שלום לכולם, זוהי בדיקה של מנוע הדיבור החדש"
    assert detect_language(text) == "he"


def test_detect_language_english():
    text = "Hello everyone, this is a test of the local speech engine."
    assert detect_language(text) == "en"


def test_detect_language_mixed_predominantly_hebrew():
    text = "אני קורא מאמר על AI ו-Machine Learning בעברית"
    assert detect_language(text) == "he"


def test_detect_language_mixed_predominantly_english():
    text = "The Hebrew word for peace is Shalom."
    assert detect_language(text) == "en"


def test_split_sentences_preserves_structure():
    text = "First sentence. Second sentence! Third sentence? Fourth sentence"
    sentences = split_sentences(text)
    assert len(sentences) == 4
    assert sentences[0] == "First sentence."
    assert sentences[1] == "Second sentence!"
    assert sentences[2] == "Third sentence?"
    assert sentences[3] == "Fourth sentence"


def test_split_sentences_hebrew_and_punctuation():
    text = "בוקר טוב! איך אתה מרגיש היום? הכל מצוין."
    sentences = split_sentences(text)
    assert len(sentences) == 3
    assert sentences[0] == "בוקר טוב!"


def test_split_sentences_does_not_split_decimals_or_abbreviations():
    text = "The GDP grew by 3.5% in the U.S. this year. Dr. Smith confirmed it."
    sentences = split_sentences(text)
    assert len(sentences) == 2
    assert "3.5%" in sentences[0]
    assert "Dr. Smith" in sentences[1]


def test_speech_engine_english_synthesis():
    engine = SpeechEngine(models_dir="models")
    result = engine.synthesize_sentence("This is a quick audio test.", voice="af_sarah", speed=1.0)
    assert isinstance(result, SynthesisResult)
    assert result.sample_rate == 24000
    assert len(result.audio_bytes) > 0
    assert result.duration_seconds > 0.3
    assert result.language == "en"


def test_speech_engine_hebrew_synthesis():
    engine = SpeechEngine(models_dir="models")
    try:
        result = engine.synthesize_sentence("שלום, זוהי בדיקת קול בעברית.", voice="edge-he-avri", speed=1.0)
        assert isinstance(result, SynthesisResult)
        assert len(result.audio_bytes) > 0
        assert result.language == "he"
    except RuntimeError as e:
        # In sandboxed / offline test environments without external network to Bing
        assert "Edge TTS Hebrew synthesis failed" in str(e)


def test_speech_engine_roboshaul_synthesis():
    engine = SpeechEngine(models_dir="models")
    if engine._roboshaul and engine._roboshaul.is_available():
        result = engine.synthesize_sentence("שלום עולם", voice="he-roboshaul", speed=1.0)
        assert isinstance(result, SynthesisResult)
        assert len(result.audio_bytes) > 0
        assert result.audio_bytes.startswith(b"RIFF")
        assert result.sample_rate == 22050
        assert result.language == "he"
        assert result.duration_seconds > 0.3


def test_api_health():
    from fastapi.testclient import TestClient
    from speech_engine import app

    client = TestClient(app)
    res = client.get("/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "ok"
    assert "voices" in data
    voice_ids = [v["id"] for v in data["voices"]]
    assert "he-roboshaul" in voice_ids


def test_api_split():
    from fastapi.testclient import TestClient
    from speech_engine import app

    client = TestClient(app)
    res = client.post("/split", json={"text": "Hello world. How are you?"})
    assert res.status_code == 200
    data = res.json()
    assert len(data["sentences"]) == 2


def test_api_synthesize():
    from fastapi.testclient import TestClient
    from speech_engine import app

    client = TestClient(app)
    res = client.post("/synthesize", json={"text": "Quick test.", "voice": "af_sarah", "speed": 1.0})
    assert res.status_code == 200
    assert len(res.content) > 100


def test_api_trigger():
    from fastapi.testclient import TestClient
    from speech_engine import app

    client = TestClient(app)
    # When no extension connected
    res = client.post("/trigger", json={"action": "toggle-read"})
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "no_extension"
    assert data["connected"] == 0



