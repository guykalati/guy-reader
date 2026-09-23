> [!WARNING] **Skepticism Disclaimer**
> I am moderately confident: the automated test suites verify that the speech engine defaults to Apple Evan, switches voices immediately, clamps speeds in 0.1x increments, and parses sentences and tweets properly, while `make clean && make` compiles cleanly with zero warnings; however, physical Fn+Space event interception and GUI window resizing in a live user desktop session require macOS Accessibility permissions which cannot be granted non-interactively in this environment.

## 1. What I changed

- **`src/main.m`**:
  - Replaced Carbon Option + Space hotkey with a global `CGEventTap` and `NSEvent` global/local monitors for **Fn + Space** (`keyCode == 49` with `kCGEventFlagMaskSecondaryFn` / `NSEventModifierFlagFunction`), consuming the event so space is not typed in active fields.
  - Updated Menu Bar status item tooltip and menu item to reflect `Fn + Space`.
  - Added clean window management: updated style mask to `NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable | NSWindowStyleMaskNonactivatingPanel`, added message handlers for `minimize` (`orderOut:` to hide to menu bar) and `exit` (`terminate:` with speech shutdown), and handled smooth drag-resizing (`resizeWindowDelta` and `resizeWindow`).
  - Upgraded text extraction to a two-tier pipeline: exact mouse selection detection via Accessibility API and hardware-level Cmd+C with pasteboard change count monitoring; followed by smart fallback for Twitter/X (extracting the foreground tweet in the viewport) and web articles (Readability-style extraction filtering navigation, headers, footers, timestamps, and metric counts).
  - Ensured the panel does not steal focus before sending copy events to the foreground app.
- **`src/speech_engine.h` & `src/speech_engine.m`**:
  - Configured **Apple Evan (Enhanced)** as the primary default voice out-of-the-box (`apple-evan`).
  - Added a dedicated `setSpeedRate:` setter ensuring active `AVAudioPlayer` playback immediately alters rate when changed without waiting for sentence completion.
  - Added voice routing supporting Apple Evan (preferring Enhanced/Premium quality), Hebrew Carmit, and Edge/Google/ElevenLabs voices.
  - Wrapped all delegate invocations (`speechDidFinishSentence`, `speechDidStartSpeaking`, `speechDidPause`) in `dispatch_async(dispatch_get_main_queue(), ...)` ensuring thread-safe WebKit evaluation.
  - Handled Edge TTS failure/error paths to seamlessly fallback to Apple speech instead of hanging.
- **`src/ui/index.html`**:
  - Added clean Minimize (—) and Exit (✕) window control buttons to the pill bar.
  - Updated all hotkey references and tooltips from `⌥ + Space` to `Fn + Space`.
  - Set `apple-evan` as the default selected option in the voice selector dropdown.
  - Added interactive resize handles for right-edge and bottom-right corner dragging.
- **`src/ui/app.js`**:
  - Initialized state voice to `apple-evan`.
  - Fixed the voice switching bug: changing the dropdown now immediately re-synthesizes the active sentence in the newly chosen voice without requiring a restart.
  - Removed duplicate native call in `speakEdgeVoice` (was calling both `speakEdge` and `edgeTTS`).
  - Implemented real-time follow-along highlighting with centered smooth auto-scrolling on sentence boundaries.
  - Connected Minimize and Exit buttons to native message handlers.
  - Implemented interactive drag-resizing logic that updates native panel dimensions dynamically.
- **`src/ui/style.css`**:
  - Styled Minimize and Exit buttons with hover states (with subtle red highlight for Exit).
  - Prominently styled the active sentence with Glaido lime (`#BFF549`), glowing box-shadow, and solid accent border.
  - Updated container and drawer flex layout to smoothly scale to any resized width and height.
  - Styled drag resize handles for border and corner resizing.
- **`src/Info.plist`**:
  - Added `NSAppleEventsUsageDescription` for browser text extraction via AppleScript.
- **`Makefile`**:
  - Added `test` target compiling and running both Objective-C and JavaScript test suites.
- **`tests/test_speech_engine.m` & `tests/test_smart_extractor.js`**:
  - Created automated test suites verifying default voice initialization, Hebrew detection, speed rate adjustments, sentence boundary parsing, Twitter/X foreground tweet extraction, and boilerplate filtering.

## 2. Why

- **R1 (Global Activation & Window Management)**: Carbon's `RegisterEventHotKey` cannot bind the macOS Fn/Globe key. Implementing `CGEventTap` and `NSEvent` monitors enables global Fn + Space activation anywhere in macOS. Adding Minimize and Exit buttons allows quick pill dismissal to the menu bar or terminating the application. Enabling borderless resizability with interactive drag handles allows responsive resizing in both compact pill and expanded drawer modes.
- **R2 (Voice Switching & Default Voice Fix)**: The previous implementation defaulted to Hebrew Edge Avri, had a race condition issuing duplicate synthesis requests, and failed to restart active playback when the voice dropdown changed. Defaulting to Apple Evan (Enhanced), updating `SpeechEngine` rate immediately, and restarting current sentence playback upon dropdown change satisfies immediate switching without restarting.
- **R3 (Smart Content & Mouse Selection Extraction)**: The previous implementation stole window focus before copying and read stale clipboard content when no text was selected. The new implementation checks `NSPasteboard` change count and Accessibility APIs to capture exact selections, and falls back to a DOM extractor that pinpoints the foreground tweet in the viewport or extracts core article paragraphs while filtering out navigation, buttons, and timestamp boilerplate.
- **R4 (Synchronized Read-Along Highlighting)**: Previously, sentence completions from background audio threads could fail WebKit execution, and the active sentence lacked visual prominence. Dispathing completions to the main queue, applying Glaido lime (`#BFF549`) with glowing box-shadow, and auto-scrolling `block: 'center'` ensures synchronous, readable follow-along playback.

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - Compiled and executed `tests/test_speech_engine.m`: 17/17 tests passed, verifying default voice initialization (`apple-evan`), Hebrew text detection, speed rate clamping (0.5x to 2.5x), voice switching, and playback state.
  - Executed `tests/test_smart_extractor.js` via JavaScriptCore / JXA: 20/20 tests passed, verifying sentence splitting (English and Hebrew with punctuation and boundary cases), 0.1x speed stepping and boundary clamping, Twitter/X foreground tweet extraction from viewport bounds, and web boilerplate/stats filtering.
  - Ran `make test`: both test suites executed and passed with code 0.
  - Ran `make clean && make`: cleanly compiled `GlaidoReader.app` with zero errors and zero warnings.
  - Verified binary architecture (`Mach-O 64-bit arm64`) and dynamic framework links via `otool -L`.
- **Shallow Verification (manual run only):**
  - Eyeballed CSS layout rules for `.glaido-container`, `.drawer`, `.reader-content`, `.sentence-item.active`, and window controls (`.btn-win-ctrl`).
  - Eyeballed `index.html` structure ensuring correct default option `apple-evan` and updated `Fn + Space` labels.
- **Unverified aspects:**
  - Live intercept of physical Fn + Space key events on the user's physical keyboard during an active interactive desktop session (requires macOS Accessibility permissions in System Settings -> Privacy & Security -> Accessibility).
  - External ElevenLabs and Google Cloud TTS synthesis with real user API keys (the app provides free offline Apple Evan and Microsoft Edge AI voices out-of-the-box; paid cloud API keys were not tested against remote billing endpoints).
  - Safari AppleScript DOM execution when the user has not enabled "Allow JavaScript from Apple Events" in Safari's Develop menu (fallback to `text of front document` is tested, but full querySelector execution depends on this Safari setting).

## 4. Known Issues

- `Minor Robustness Risk` — Global Fn + Space hotkey and hardware Cmd+C keystroke simulation require macOS Accessibility permissions. If not granted by the user in System Settings, macOS restricts event taps. The app prompts the user on launch via `AXIsProcessTrustedWithOptions`.
- `Minor Robustness Risk` — In Safari, running JavaScript via AppleScript requires "Allow JavaScript from Apple Events" in Safari's Develop menu. If disabled, Glaido falls back to extracting `text of front document` and filtering out boilerplate.

## 5. Untested Edge Cases & Next Step

- **Edge Case to test first**: Grant Accessibility permissions to `GlaidoReader.app` in macOS System Settings -> Privacy & Security -> Accessibility, focus a browser tab on Twitter/X or a news article, select a sentence with the mouse, and press `Fn + Space` to verify end-to-end audio output and read-along glowing lime highlighting.
