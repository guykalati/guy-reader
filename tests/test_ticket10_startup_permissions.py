"""Test Suite for Ticket 10:
- Eliminate startup Accessibility permission popup on macOS
"""

from pathlib import Path
import re

REPO_ROOT = Path(__file__).parent.parent
MAIN_M = REPO_ROOT / "src" / "main.m"
MAKEFILE = REPO_ROOT / "Makefile"


def test_no_startup_accessibility_prompt_in_main_m():
    """Verify that kAXTrustedCheckOptionPrompt is completely removed from main.m to prevent popup on startup."""
    content = MAIN_M.read_text(encoding="utf-8")
    assert "kAXTrustedCheckOptionPrompt" not in content, "kAXTrustedCheckOptionPrompt must be removed so macOS does not popup permission prompt on startup"
    assert "AXIsProcessTrustedWithOptions" not in content, "AXIsProcessTrustedWithOptions should not be called with prompt on startup"


def test_open_accessibility_settings_menu_item():
    """Verify that accessibility settings can be opened on demand via the status menu rather than on launch."""
    content = MAIN_M.read_text(encoding="utf-8")
    assert "openAccessibilitySettings" in content, "Should have openAccessibilitySettings selector for on-demand settings access"


def test_makefile_stable_codesign_identifier():
    """Verify that Makefile codesign uses explicit identifier com.guy.guyreader for bundle stability."""
    content = MAKEFILE.read_text(encoding="utf-8")
    assert "-i com.guy.guyreader" in content, "Makefile codesign should specify -i com.guy.guyreader"
