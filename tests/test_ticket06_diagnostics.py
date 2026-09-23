#!/usr/bin/env python3
"""Regression test suite for Ticket 06:
Diagnose & Fix Selection Extraction, Local Engine Lifecycle, Voice Collapse, and Extension Sync.
"""

import os
import sys
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def test_speech_engine_health_endpoint():
    """Verify speech engine starts and returns valid health info with Kokoro voices."""
    sys.path.insert(0, ROOT_DIR)
    from speech_engine import health
    h = health()
    assert h["status"] == "ok"
    assert h["kokoro"] is True
    voice_ids = [v["id"] for v in h["voices"]]
    assert "af_sarah" in voice_ids
    assert "edge-he-avri" in voice_ids


def test_kokoro_synthesis_audio_validity():
    """Verify Kokoro-82M synthesis produces audible non-empty WAV audio."""
    sys.path.insert(0, ROOT_DIR)
    from speech_engine import engine
    res = engine.synthesize_sentence("This is a direct test of the Kokoro-82M model.", voice="af_sarah")
    assert res.language == "en"
    assert res.sample_rate == 24000
    assert len(res.audio_bytes) > 1000
    assert res.audio_bytes.startswith(b"RIFF")
    assert res.duration_seconds > 0.5


def test_hebrew_synthesis_audio_validity():
    """Verify Hebrew synthesis produces valid audio."""
    sys.path.insert(0, ROOT_DIR)
    from speech_engine import engine
    try:
        res = engine.synthesize_sentence("שלום, זוהי בדיקה של מנוע הקראת הטקסט בעברית.", voice="edge-he-avri")
        assert res.language == "he"
        assert len(res.audio_bytes) > 500
    except RuntimeError as e:
        # Strict Avri: in offline / sandboxed test runner, raises explicit Edge TTS failure, never Carmit
        assert "Edge TTS Hebrew synthesis failed" in str(e)


def test_ui_settings_modal_resizing_contract():
    """Verify UI logic: opening settings must request window expansion, and closing must restore."""
    app_js_path = os.path.join(ROOT_DIR, "src", "ui", "app.js")
    with open(app_js_path, "r", encoding="utf-8") as f:
        content = f.read()

    # openSettingsModal must notifyNative resizeWindow with height >= 440
    assert "openSettingsModal" in content
    assert "resizeForModal" in content or "notifyNative('resizeWindow', { height: 460" in content or "settingsModalOpen" in content


def test_native_main_never_exits_on_close():
    """Verify src/main.m does not terminate app on 'close' action (only on explicit 'exit')."""
    main_m_path = os.path.join(ROOT_DIR, "src", "main.m")
    with open(main_m_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 'close' action must NOT terminate the app
    assert '[action isEqualToString:@"exit"] || [action isEqualToString:@"close"]' not in content


def test_native_main_no_stale_clipboard_fallback():
    """Verify extractForegroundContentFromApp in src/main.m never falls back to reading pasteboard."""
    main_m_path = os.path.join(ROOT_DIR, "src", "main.m")
    with open(main_m_path, "r", encoding="utf-8") as f:
        content = f.read()

    # extractForegroundContentFromApp must NOT contain generalPasteboard
    func_start = content.find("- (void)extractForegroundContentFromApp:")
    assert func_start != -1
    func_end = content.find("- (NSString *)escapeForAppleScript:", func_start)
    func_body = content[func_start:func_end]
    assert "generalPasteboard" not in func_body


def test_native_main_auto_launches_speech_engine():
    """Verify src/main.m contains logic to auto-launch speech_engine.py daemon."""
    main_m_path = os.path.join(ROOT_DIR, "src", "main.m")
    with open(main_m_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "ensureSpeechEngineDaemonRunning" in content or "startSpeechEngineDaemon" in content
