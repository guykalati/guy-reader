# Original User Request

## 2026-09-13T16:57:24+03:00

This is a single self-contained fix; keep it small and focused.

Overhaul and upgrade the Glaido Reader macOS app (/Users/gyklty/Desktop/Guy/TTS) with Fn + Space global activation, reliable voice switching with Apple Evan as default, resizable floating window with exit/minimize controls, smart content & mouse selection extraction for Twitter/X and web pages, and live read-along text highlighting.

Working directory: /Users/gyklty/Desktop/Guy/TTS
Integrity mode: development

## Requirements

### R1. Global Activation & Window Management
- Change the global activation hotkey to Fn + Space (replacing Option + Space).
- Add clean Exit (✕) and Minimize (—) buttons to the floating Glaido pill.
- Enable smooth, interactive window resizing in both states (the compact floating pill and the expanded Readest drawer), maintaining layout responsiveness and dragging behavior.

### R2. Voice Switching & Default Voice Fix
- Fix voice selection bug where voice is stuck and does not change when switched in the UI.
- Set Apple Evan (Enhanced) as the primary default voice out-of-the-box.
- Ensure switching between English (Evan Enhanced, Edge Jenny/Guy) and Hebrew AI voices (Edge Avri, Edge Hila, Google, ElevenLabs) takes effect immediately for both manual selection and auto-detected language.

### R3. Smart Content & Mouse Selection Extraction (Twitter/X & Web)
- Enable exact mouse selection reading: when the user selects/marks a starting point or passage in any app (Twitter/X, Safari, Chrome, PDF, Notes), the app captures and reads the complete passage.
- When on Twitter/X or a web page without an explicit mouse selection, intelligently extract the main foreground post or core article text while filtering out navigation menus, timestamps, and extraneous HTML boilerplate.

### R4. Synchronized Read-Along Highlighting
- Fix visual follow-along sentence highlighting in the expanded drawer: ensure the active sentence is prominently highlighted (Glaido lime #BFF549) and auto-scrolls in real-time as speech progresses.

## Acceptance Criteria

### Hotkey & Window
- [ ] Pressing Fn + Space anywhere in macOS triggers reading of the active selection or foreground post.
- [ ] Exit (✕) quits or closes the floating window, and minimize (—) hides the pill to the menu bar.
- [ ] Floating window can be resized in both compact pill and expanded drawer modes without visual glitching.

### Voices & Playback
- [ ] Default voice upon initial launch is Apple Evan (Enhanced).
- [ ] Changing the voice in the dropdown immediately alters the synthesized speech output without restarting.
- [ ] Speed jumps work in 0.1x steps across 0.5x to 2.5x.

### Content Extraction & Highlighting
- [ ] Highlighting text in Chrome/Safari/Twitter and triggering the hotkey reads the exact highlighted text.
- [ ] On Twitter/X, triggering without selection grabs the tweet text currently in view.
- [ ] Active sentence is visually highlighted with glowing lime indicator and synchronized with audio playback.

### Build & Stability
- [ ] make clean && make compiles GlaidoReader.app with zero errors.
- [ ] Application runs stably without hanging or leaking processes.
