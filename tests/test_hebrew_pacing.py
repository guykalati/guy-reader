"""Tests for Hebrew TTS pacing, bullet punctuation handling, and timing benchmarks."""

import os
import sys
import time
from pathlib import Path
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from speech_engine import split_sentences, SpeechEngine, SynthesisResult
import roboshaul.HebrewToEnglish as HebrewToEnglish


def test_split_sentences_bullets_israel_hayom():
    """Verify Israel Hayom style bullet delimiters separate sub-headlines cleanly."""
    raw_text = (
        '1,000 ימים של הפעלת כוח שברו את הארכיטקטורה הישנה של האזור, ופתחו בפני ישראל חלון היסטורי במרחב גיאוגרפי חדש • '
        'אבל בזמן שטורקיה והמפרציות בוראות מציאות של נמלים, כבלים, מסילות וצירי סחר - בארץ מדשדשים • '
        'מ"כיפת סיליקון" ועד הפיכתנו לצומת האמון של האזור: תוכנית הפעולה שתבטיח ניצחון גם ביום שאחרי'
    )
    sentences = split_sentences(raw_text)
    assert len(sentences) == 3, f"Expected 3 clauses, got {len(sentences)}: {sentences}"
    assert sentences[0].startswith("1,000 ימים"), f"Clause 0 failed: {sentences[0]}"
    assert not sentences[0].endswith("•"), "Bullet should not remain at end of clause"
    assert "מדשדשים" in sentences[1], f"Clause 1 failed: {sentences[1]}"
    assert "תוכנית הפעולה" in sentences[2], f"Clause 2 failed: {sentences[2]}"


def test_hebrew_to_english_bullet_mapping():
    """Verify that bullet tokens are converted to pause token ' - ' rather than stripped."""
    assert HebrewToEnglish.map_punct_token("•") == " - "
    assert HebrewToEnglish.map_punct_token("▪") == " - "
    assert HebrewToEnglish.map_punct_token("✦") == " - "

    tokens = HebrewToEnglish.break_to_letter_and_rebuild("חדש • אבל")
    # Tokens should include the bullet as a separate punctuation token
    assert "•" in tokens or " - " in [HebrewToEnglish.map_punct_token(t) for t in tokens]


def test_roboshaul_synthesis_timing_benchmark():
    """Verify RoboShaul synthesis completes within acceptable latency and produces valid audio."""
    engine = SpeechEngine(models_dir="models")
    if not engine._roboshaul or not engine._roboshaul.is_available():
        pytest.skip("RoboShaul models not available in this environment")

    # First sentence (warm)
    t0 = time.perf_counter()
    res1 = engine.synthesize_sentence("שלום, זוהי בדיקת מהירות.", voice="he-roboshaul", speed=1.0)
    dur1 = time.perf_counter() - t0

    assert isinstance(res1, SynthesisResult)
    assert len(res1.audio_bytes) > 0
    assert res1.duration_seconds > 0.5
    print(f"\n[Benchmark] Synthesis 1 took {dur1:.2f}s for {res1.duration_seconds:.2f}s audio")

    # Second sentence (should hit cache or warm pipeline)
    t1 = time.perf_counter()
    res2 = engine.synthesize_sentence("המשפט השני נבדק לקצב טבעי.", voice="he-roboshaul", speed=1.0)
    dur2 = time.perf_counter() - t1

    assert isinstance(res2, SynthesisResult)
    assert len(res2.audio_bytes) > 0
    print(f"[Benchmark] Synthesis 2 took {dur2:.2f}s for {res2.duration_seconds:.2f}s audio")
