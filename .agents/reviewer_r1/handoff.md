# Adversarial Review Report — Round 1

> [!WARNING] **Skepticism Disclaimer**
> I have confirmed all core fixes with automated unit test suites (60/60 tests passing) and a clean compiler build; however, physical Fn + Space keystrokes in a live desktop session require macOS Accessibility permissions which cannot be granted non-interactively in this sandbox environment.

## 1. What the prior attempt got wrong

1. **Edge TTS network fallback triggered duplicate concurrent speech requests:**
   - **Input:** Any Edge TTS failure (network offline, HTTP 403, or connection reset).
   - **Expected:** A single clean fallback to local Apple speech synthesis.
   - **Actual:** `speechDidStartSpeaking` was called twice (or three times), starting conflicting concurrent utterances, causing speech stutter and desynchronization.
   - **Root cause:** Both `sendMessage:cfgMessage` error and `receiveMessageWithCompletionHandler:` error handlers independently dispatched fallback calls to `speakText:voice:rate:` without a synchronization guard.

2. **Hebrew text fallback assigned English voice identifier:**
   - **Input:** Reading Hebrew text with `edge-he-avri` when Edge TTS network is unavailable.
   - **Expected:** Fallback to Apple Hebrew voice (`apple-carmit`).
   - **Actual:** `currentVoice` property became `apple-evan` even while speaking Hebrew text.
   - **Root cause:** Hardcoded fallback `[strongSelf speakText:text voice:@"apple-evan" rate:rate]` in all error handlers.

3. **False-positive Hebrew voice detection on ElevenLabs voice `eleven-rachel`:**
   - **Input:** User selects ElevenLabs Rachel (`eleven-rachel`) and loads English text.
   - **Expected:** Voice remains Rachel.
   - **Actual:** UI auto-switched voice to `apple-evan`.
   - **Root cause:** `state.voice.includes('he')` substring match matched the `"he"` inside the English name `"rachel"` (`"rachel".indexOf("he") === 3`).

4. **Boilerplate filter completely deleted short words ("OK", "Go", "Hi"):**
   - **Input:** User highlights a short word like "OK" or "Go".
   - **Expected:** Glaido speaks "OK" or "Go".
   - **Actual:** `filterBoilerplate:` returned an empty string `""` and the app spoke nothing.
   - **Root cause:** Blanket condition `if (trimmed.length < 3) continue;` dropped any line under 3 characters regardless of whether it was valid text or noise.

5. **DOM smart extractor ignored active browser mouse selection:**
   - **Input:** User highlighted a specific passage with the mouse on Twitter/X or a web page where AX API was unpopulated.
   - **Expected:** Glaido extracts and reads the user's highlighted passage.
   - **Actual:** Extracted the entire viewport tweet or article instead of the highlighted passage.
   - **Root cause:** `kSmartExtractJS` lacked a `window.getSelection().toString()` check before running viewport query selectors.

6. **Replay after finishing text only replayed the last sentence:**
   - **Input:** Playback finishes all sentences in a passage, then user presses Play.
   - **Expected:** Re-reads the text from sentence 0.
   - **Actual:** Replayed only the last sentence and stopped immediately.
   - **Root cause:** `onSentenceFinished()` did not reset `state.currentIndex` to 0 upon reaching the end of the text.

7. **Compact pill stretched into an empty box on corner drag:**
   - **Input:** User dragged the corner resize handle while in compact pill mode (drawer closed).
   - **Expected:** Only window width adjusts; height remains the compact pill height (60px).
   - **Actual:** Window height expanded downward into a large black container with an empty space under the pill bar.
   - **Root cause:** `setupResizeHandle` passed raw `dh` to native even when `!state.drawerOpen`.

8. **Expanding drawer near the bottom edge expanded off-screen:**
   - **Input:** User clicks drawer expand chevron when the pill is in the lower portion of the display.
   - **Expected:** Drawer remains on screen within visible screen bounds.
   - **Actual:** Drawer expanded below the display visible bounds.
   - **Root cause:** Missing `NSScreen.visibleFrame` clamping in `resizeWindow` and `resizeWindowDelta`.

9. **Clicking "Read" button while Glaido was frontmost did nothing:**
   - **Input:** User clicked the "Read" pill button while Glaido panel was active.
   - **Expected:** Read clipboard content if available.
   - **Actual:** Silent return.
   - **Root cause:** `captureAndSpeak` unconditionally returned if `frontApp.bundleIdentifier` matched Glaido.

10. **Window dragging failed via WebKit event interception:**
    - **Input:** User dragged the drag zone in the pill.
    - **Expected:** Floating pill moves smoothly with the mouse.
    - **Actual:** WebKit consumed mouse events; `-webkit-app-region: drag` is an Electron-only property ignored by Apple WebKit.
    - **Root cause:** Lack of native `performWindowDragWithEvent:` invocation on `mousedown`.

## 2. What I changed

- **`src/speech_engine.h` & `src/speech_engine.m`**:
  - Added `BOOL _edgeFallbackTriggered` guard ensuring fallback is executed strictly once per synthesis attempt.
  - Implemented language-aware fallback routing: Hebrew text falls back to `apple-carmit`, English text to `apple-evan`.
  - Updated `setSpeedRate:` to clamp input rates between 0.5f and 2.5f.
  - Updated `isSpeaking` to respect `_isPaused` immediately without waiting for asynchronous CoreAudio thread sync.
  - Enhanced Evan voice lookup: attempts identifier lookup (`com.apple.voice.enhanced.en-US.Evan`, `com.apple.voice.premium.en-US.Evan`, etc.) before falling back to name scanning and default `en-US`.
  - Added nullability annotations to `voice` parameters in `speakText:` and `speakEdgeTTS:` to eliminate callee warnings.
- **`src/main.m`**:
  - Added 0.35s debounce guard to `handleGlobalHotkey` preventing duplicate triggers when both `CGEventTap` and `NSEvent` monitors fire.
  - In `captureAndSpeak`, enabled reading from clipboard when Glaido is frontmost.
  - Increased simulated Cmd+C delay from 100ms to 150ms for reliable pasteboard updates across heavy browsers.
  - Added `window.getSelection()` check to `kSmartExtractJS` to ensure active mouse selections take precedence over page DOM extraction.
  - Updated `filterBoilerplate:` to test for Unicode alphanumeric characters (`[\p{L}\p{N}]`), properly preserving short words like "OK", "Go", "Hi" while discarding noise like standalone bullet dots.
  - Added native `performWindowDragWithEvent:` handler for action `@"dragWindow"`.
  - Added screen visible bounds clamping to `resizeWindow` and `resizeWindowDelta`.
  - Removed unused variable `appName` in `extractForegroundContentFromApp:`.
- **`src/ui/app.js`**:
  - Added `isHebrewVoice()` helper replacing unsafe substring `.includes('he')`, eliminating false-positive switches on voices like `eleven-rachel`.
  - In `onSentenceFinished()`, reset `state.currentIndex = 0` upon reaching the end of the text, ensuring subsequent Play starts from the beginning.
  - In `toggleDrawer()`, added auto-scrolling to center the active sentence when opening the drawer.
  - In `setupResizeHandle()`, constrained `dh` to 0 when `!state.drawerOpen`, preventing vertical stretching in compact pill mode.
  - Connected `dragZone` `mousedown` to native `dragWindow` action.
- **`src/ui/index.html`**:
  - Added `id="dragZone"` to the `.drag-zone` container element.
- **`tests/test_speech_engine.m`**:
  - Rewrote test suite with 22 adversarial checks covering voice routing, edge fallback uniqueness, language fallback correctness, speed clamping, and real pause/resume state verification.
- **`tests/test_smart_extractor.js`**:
  - Expanded test suite to 38 tests covering short word preservation, `isHebrewVoice` discrimination, selection priority, replay rewind, and compact mode resize constraints.

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - Ran `make test`:
    - `tests/test_speech_engine.m`: 22/22 tests passed (zero failures).
    - `tests/test_smart_extractor.js`: 38/38 tests passed (zero failures).
  - Ran `make clean && make`: cleanly compiled `GlaidoReader.app` with 0 warnings and 0 errors.
  - Process lifecycle test: Launched binary `./GlaidoReader.app/Contents/MacOS/GlaidoReader`, verified active PID, and verified clean process termination.
- **Shallow Verification (manual only):**
  - Inspected DOM IDs, CSS selectors, and script message routing.
- **Unverified aspects:**
  - Live intercept of physical Fn + Space key events on the user's physical keyboard during an active interactive desktop session (requires macOS Accessibility permissions in System Settings -> Privacy & Security -> Accessibility).
  - ElevenLabs and Google Cloud TTS synthesis with real user API keys (paid cloud API keys were not tested against remote billing endpoints).

## 4. Known Issues

- `Minor Robustness Risk` — Global Fn + Space hotkey and hardware Cmd+C keystroke simulation require macOS Accessibility permissions. If not granted by the user in System Settings, macOS restricts event taps. The app prompts the user on launch via `AXIsProcessTrustedWithOptions`.
- `Minor Robustness Risk` — In Safari, running JavaScript via AppleScript requires "Allow JavaScript from Apple Events" in Safari's Develop menu. If disabled, Glaido falls back to AX text extraction and boilerplate filtering.

## 5. Remaining risk & next step

- The implementation has addressed all bugs found in Round 0, verified language detection, voice fallback, short word preservation, window resizing, and process stability with 60 passing tests.
- **Next Step**: In a live desktop session with Accessibility permissions enabled, launch `GlaidoReader.app`, highlight text in Safari/Chrome, and press `Fn + Space` to test real-world audio output and glowing lime follow-along highlighting.
