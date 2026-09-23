"""Test Suite for Ticket 07:
- Removal of keyboard shortcuts (app controlled strictly via UI buttons)
- Button layout without overlap/crossing in pill and drawer
- M4 Apple Silicon speed optimizations (non-blocking Cocoa startup, engine warmup, pre-buffering)
- Web extension CSP proxying via background service worker
- Unified selection & clipboard fallback reading
"""

import re
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).parent.parent
MAIN_M = REPO_ROOT / "src" / "main.m"
INDEX_HTML = REPO_ROOT / "src" / "ui" / "index.html"
STYLE_CSS = REPO_ROOT / "src" / "ui" / "style.css"
APP_JS = REPO_ROOT / "src" / "ui" / "app.js"
SPEECH_ENGINE_PY = REPO_ROOT / "speech_engine.py"
EXT_BG = REPO_ROOT / "extension" / "background.js"
EXT_CONTENT = REPO_ROOT / "extension" / "content.js"


def test_no_keyboard_shortcuts_in_main_m():
    """Verify that all global keyboard interception is completely removed from main.m."""
    content = MAIN_M.read_text(encoding="utf-8")
    assert "CarbonHotKeyHandler" not in content, "CarbonHotKeyHandler should be removed"
    assert "RegisterEventHotKey" not in content, "RegisterEventHotKey should be removed"
    assert "EventTapCallback" not in content, "EventTapCallback should be removed"
    assert "CGEventTapCreate" not in content, "CGEventTapCreate should be removed"
    assert "NSEventMaskKeyDown" not in content, "Global keyboard interception must stay removed; mouse-only source tracking is allowed"


def test_no_hotkey_badges_in_ui():
    """Verify that hotkey badges are removed from UI buttons in index.html."""
    content = INDEX_HTML.read_text(encoding="utf-8")
    assert "hotkey-badge" not in content, "hotkey-badge class should be removed"
    assert "fn G / ⌥G" not in content, "fn G hotkey text should be removed from UI"


def test_isolated_window_controls_group_in_html_and_css():
    """Verify window controls (minimize and exit) are grouped in an isolated container."""
    html = INDEX_HTML.read_text(encoding="utf-8")
    assert 'class="window-controls-group"' in html, "window-controls-group container must exist in index.html"
    
    css = STYLE_CSS.read_text(encoding="utf-8")
    assert ".window-controls-group" in css, ".window-controls-group must be styled in style.css"
    assert "flex-shrink: 0" in css or "flex-shrink:0" in css, "Window controls must not shrink or overlap"


def test_floating_panel_width_and_min_size():
    """Verify default floating panel width is increased to at least 500px to prevent button collisions."""
    content = MAIN_M.read_text(encoding="utf-8")
    m_w = re.search(r"CGFloat\s+initWidth\s*=\s*([0-9.]+);", content)
    assert m_w is not None, "initWidth must be defined"
    init_width = float(m_w.group(1))
    assert init_width >= 500.0, f"initWidth should be >= 500px to avoid button crossing, found {init_width}"

    m_min = re.search(r"minSize\s*=\s*NSMakeSize\(([0-9.]+),\s*([0-9.]+)\);", content)
    assert m_min is not None, "minSize must be defined"
    min_width = float(m_min.group(1))
    assert min_width >= 420.0, f"minSize width should be >= 420px, found {min_width}"


def test_non_blocking_cocoa_startup():
    """Verify Cocoa startup does not synchronously block main thread with dispatch_semaphore_wait."""
    content = MAIN_M.read_text(encoding="utf-8")
    # In ensureSpeechEngineDaemonRunning, there should not be a synchronous dispatch_semaphore_wait on main thread
    func_match = re.search(r"- \(void\)ensureSpeechEngineDaemonRunning\s*\{(.*?)\n\}", content, re.DOTALL)
    assert func_match is not None, "ensureSpeechEngineDaemonRunning must exist"
    func_body = func_match.group(1)
    assert "dispatch_semaphore_wait" not in func_body, "ensureSpeechEngineDaemonRunning must be non-blocking (no semaphore wait on main thread)"


def test_speech_engine_warmup():
    """Verify speech_engine.py initializes and warms up Kokoro in background."""
    content = SPEECH_ENGINE_PY.read_text(encoding="utf-8")
    assert "_warmup" in content or "warmup" in content.lower(), "speech_engine.py should have model warmup logic"


def test_app_js_prebuffering():
    """Verify app.js implements streaming pre-buffering for instant sentence-to-sentence playback."""
    content = APP_JS.read_text(encoding="utf-8")
    assert "prebuffer" in content.lower() or "cache" in content.lower(), "app.js must implement sentence pre-buffering"


def test_web_extension_csp_proxy():
    """Verify content.js does not make direct fetch to 127.0.0.1:5050 and background.js handles local engine proxy."""
    content_js = EXT_CONTENT.read_text(encoding="utf-8")
    assert "fetch(`${SPEECH_ENGINE_URL}" not in content_js, "content.js must not directly fetch SPEECH_ENGINE_URL due to page CSP"
    assert "fetch(SPEECH_ENGINE_URL" not in content_js, "content.js must not directly fetch SPEECH_ENGINE_URL due to page CSP"

    bg_js = EXT_BG.read_text(encoding="utf-8")
    assert "check-engine-health" in bg_js, "background.js must handle check-engine-health"
    assert "synthesize-local" in bg_js, "background.js must handle synthesize-local"


def test_clipboard_is_explicit_in_main_m():
    """Read must not consume old clipboard text; Paste remains explicit."""
    content = MAIN_M.read_text(encoding="utf-8")
    assert "Reading existing text from clipboard as fallback" not in content
    assert 'isEqualToString:@"pasteClipboard"' in content
