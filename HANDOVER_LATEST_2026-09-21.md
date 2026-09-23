# Guy Reader handover: current state after click-to-read, strict Avri, and X extraction repairs

Copy this document into the next agent conversation. Treat it as the latest state as of 2026-09-21.

## Mission and workspace

Continue and validate **Guy Reader**, a macOS text-to-speech app with a Brave/Chrome companion extension.

- Workspace: `/Users/gyklty/Desktop/Guy/TTS`
- Read `AGENTS.md` before editing. This repository uses the Matt Pocock lifecycle: specification, local tickets, TDD, implementation, and two-axis review.
- Current ticket: `.scratch/unified-reader/issues/09-click-to-read-and-word-follow-along.md`
- Latest authoritative handover: this file.
- This workspace has no usable Git metadata. Preserve all current files and do not reset or clean the directory.
- A pre-ticket-09 backup is at `.scratch/unified-reader/ticket09-backup/`.

## User intent that must remain true

1. In the desktop app, the user can click text in another app and then click **Read**. Reading begins at the clicked word and continues through the remaining accessible passage.
2. An explicit highlighted selection has priority over the remembered click.
3. Existing clipboard content is read only through **Paste**. The **Read** button must never silently read an old clipboard value.
4. In Brave/Chrome, clicking or selecting a word and starting the reader continues through the article or post and highlights the current word in the page.
5. When the user selects **Avri**, the browser must keep Avri. It must never silently change to Hila or Carmit. If Avri is unavailable, stop and show an error.
6. X/Twitter reading must target the clicked tweet or long-form article body. Navigation labels such as `Article` and `Conversation`, unrelated headers, sidebars, and controls are not reading content.
7. Stop must cancel pending capture, browser commands, audio, native speech, polling, and highlights.
8. Sentence transitions should sound natural. Avoid a separate network wait between sentences when prefetching is possible.

## Final behavior

### Desktop app

- `src/main.m` installs a global mouse-up observer and records accessible text at the clicked position using `GRReadingTextAtElement`.
- Exact highlighted text is checked first through Accessibility. `GRPreferredReadingText` centralizes the priority: exact selection, then a click from the same app.
- Click reading returns the clicked word plus later accessible blocks through `GRReadingSuffix`.
- If an app does not expose selected text through Accessibility, the existing capture pipeline can simulate Command-C and accept only a **new** pasteboard revision created by that capture. It does not consume pre-existing clipboard text.
- The explicit `pasteClipboard` UI action is the only path intended to read the current clipboard.
- Browser targets are delegated to the extension through `POST /trigger`. Native fallback is used when the extension cannot handle the page.
- Stop increments capture and browser session generations, invalidates polling, sends browser Stop, and stops native speech.
- The rebuilt application is `Guy_reader.app`.

### Browser extension

- `extension/content.js` remembers the clicked DOM caret using `caretPositionFromPoint` or `caretRangeFromPoint`.
- Visible text is mapped back to source text nodes. Hidden controls and junk descendants are excluded, and `<br>` or block boundaries remain word boundaries.
- CSS Custom Highlight ranges paint the sentence and word without wrapping or rewriting the source DOM.
- Exact synchronized mode uses real Web Speech word-boundary events and joins consecutive same-language sentences to reduce punctuation gaps.
- Neural mode uses the chosen neural voice, prefetches the next sentence, and estimates the active word from media time because Edge/Kokoro audio does not return alignment metadata.
- Pause/Resume preserves the clicked word offset.
- Voice and mode settings persist in `chrome.storage.local`.
- Selecting an Edge voice such as Avri automatically uses neural mode. The voice selector remains visible.
- Avri and Hila are strict identities. `extension/background.js` no longer falls back from failed Edge synthesis to the local Carmit endpoint. The content script stops with an error instead of substituting a speaker.
- Only one tab owns browser playback. Starting in a new tab stops the old tab. Reader-state messages from other tabs are ignored.
- Desktop bridge commands carry an expiry and request ID. Expired or late commands cannot start playback after desktop fallback or Stop.

### X/Twitter extraction

- On `x.com` and `twitter.com`, extraction first uses the container nearest the clicked point.
- Preferred containers are `twitterArticleReadView`, `longformRichTextComponent`, `article[data-testid="tweet"]`, and `article`.
- Without a clicked container, the largest visible X article candidate is chosen.
- `Article`, `Conversation`, tab lists, navigation, timestamps, buttons, ads, and side content are excluded.
- A regression fixture based on the user's screenshot verifies that the spoken text begins with the actual post body and excludes the two tab labels.

### Speech and highlighting tradeoff

- **Avri fidelity:** Avri playback uses Edge neural audio and estimated word timing. This preserves the exact requested speaker.
- **Exact word boundaries:** exact browser boundaries require an installed Web Speech voice; on macOS this is normally Evan for English or Carmit for Hebrew.
- Do not silently choose exact highlighting over the user's selected voice. The current implementation prioritizes the selected voice.

## Important files changed

- `src/main.m`: click/selection priority, explicit clipboard boundary, browser session cancellation, daemon coordination, updated Read labels.
- `src/reading_origin.h` and `src/reading_origin.m`: clicked suffix extraction, AX tree traversal, enclosing-group mapping, selection-over-click policy.
- `src/speech_engine.h` and `src/speech_engine.m`: native word-boundary delegate events with playback-generation guards.
- `src/ui/app.js`: connected synchronized speech, native word highlighting, mark cleanup, browser transport state, Stop behavior.
- `src/ui/index.html` and `src/ui/style.css`: Stop control, synchronized-mode setting, current-word presentation, corrected Read label.
- `extension/content.js`: click origin, visible-source mapping, X extraction, highlights, strict Edge voice routing, persistence, prefetch, transport.
- `extension/content.css`: CSS Custom Highlight styles for sentence and current word.
- `extension/background.js`: strict Edge failure, one-tab ownership, correlated/expiring bridge commands.
- `speech_engine.py`: correlated browser commands, `/reader-state`, WebSocket reader state, request expiry.
- `start_guy_reader.sh`: starts and health-checks the localhost bridge before opening the GUI.
- `Makefile`: includes `reading_origin.m` and the clicked-origin regression suite.
- `tests/test_extension_playback.js`: browser playback, Avri identity, clicked offset, X structure, prefetch, and highlight tests.
- `tests/test_reader_playback.js`: desktop playback and word-mark cleanup tests.
- `tests/test_reader_coordinator.m`: explicit clipboard boundary tests.
- `tests/test_clicked_origin.m`: clicked suffix and selection priority tests.
- `tests/test_speech_boundaries.m`: real macOS word-boundary mapping.
- `tests/test_ticket09_follow_along.py`: browser command acknowledgment and expiry.

## Final verification evidence

The final full run completed successfully:

- `make test`
  - Clicked origin: 5 passed.
  - JavaScript app/extension playback: 23 passed.
  - Native selection and explicit-Paste coordinator: 3 passed.
  - Native speech engine: 40/40 passed.
  - Extractor and UI logic: 160/160 passed.
- `.venv_guy/bin/pytest -q tests/test_ticket07_improvements.py tests/test_ticket09_follow_along.py`: 10 passed with two third-party deprecation warnings.
- Real macOS boundary test: five boundary events; the second sentence mapped correctly.
- `make bundle`: successful build with no compiler errors.
- Live `GET http://127.0.0.1:5050/health`: returned `status: ok` with Kokoro loaded.
- The rebuilt app was launched successfully after the final build.

The native speech suite needs access to macOS speech services. A sandbox-only run may fail or behave intermittently; rerun it with macOS speech access before treating a native failure as a product regression.

## Current operational state and required manual step

- The final app build was running and the local bridge was healthy at the last check.
- The last health response reported `connected_extensions: 0`. The unpacked Brave extension still needs a manual reload before live browser behavior can use the latest source.
- Reload it at `brave://extensions`, then refresh the X/article tab. Browser security prevented the previous agent from operating that internal Brave page automatically.
- After reload, test both extension buttons and the injected page pill.

## Recommended live acceptance checks

1. In a native app with accessible text, click a word, switch to Guy Reader, and click **Read**. Confirm it begins at that word and continues.
2. Highlight a short phrase and click **Read**. Confirm the highlighted phrase wins over the remembered click and old clipboard content.
3. Put unrelated text on the clipboard, click source text without highlighting, and click **Read**. Confirm the unrelated clipboard text is not read.
4. On a Hebrew web passage, select Avri. Confirm the mode becomes neural, Avri remains selected across sentences, and no Hila/Carmit voice appears.
5. Temporarily make Edge unavailable. Confirm the reader stops with an Avri-unavailable message instead of changing speaker.
6. On an X long-form post like the supplied example, click the first content sentence and read. Confirm `Article`, `Conversation`, unrelated headers, and diagram labels are not spoken.
7. Pause and Resume after starting from a later word. Confirm the word position is preserved.
8. Start reading in one tab, then another. Confirm the first tab stops.
9. Press Stop while a browser Read command or synthesis request is pending. Confirm nothing starts afterward.

## Known constraints and stale documentation

- Native click extraction depends on macOS Accessibility permission and the target app's AX tree. Some canvas, image, protected PDF, or custom-rendered surfaces may not expose a readable clicked position.
- X changes its DOM periodically. If extraction regresses, inspect the current clicked container and update the narrow X selector/fixture rather than broadening extraction to the whole page.
- Edge neural audio does not supply word timestamps in this implementation. Its highlighted word is an estimate tied to media time.
- Use `Launch_Guy_reader.command` for a cold start. The launcher starts the Python bridge before the GUI. Directly opening the app is reliable when port 5050 is already healthy; GUI-child Python startup stalled during one macOS live check.
- `CONTEXT.md` is partly stale: it mentions active global hotkeys and a Phonikud pipeline that the current implementation does not fully deliver.
- Earlier sections of `walkthrough.md` describe automatic browser Carmit fallback. The latest follow-up section and this handover supersede that behavior: browser Avri is strict and does not fall back.
- Older ticket counts in ticket 09 predate the final follow-up regressions. Use the verification counts in this handover.

## Commands for the next agent

```bash
cd '/Users/gyklty/Desktop/Guy/TTS'

# Start the daemon and app through the supported launcher
./Launch_Guy_reader.command

# Confirm the bridge
curl -sS --max-time 3 http://127.0.0.1:5050/health

# Full native and JavaScript suite
make test

# Focused Python contracts
.venv_guy/bin/pytest -q tests/test_ticket07_improvements.py tests/test_ticket09_follow_along.py

# Rebuild the application
make bundle
```

## Continuation rules

- Reproduce a reported failure before editing and add a regression at the public UI, bridge, AX, or DOM seam that failed.
- Preserve strict Avri identity and explicit Paste semantics.
- Preserve user-owned files and the ticket backups.
- Rebuild `Guy_reader.app` after native or bundled UI changes.
- Reload the unpacked extension and refresh the target page after extension changes.
- Finish only after focused regressions, the full appropriate suite, a fresh build, and a concise update to this handover or `walkthrough.md`.
