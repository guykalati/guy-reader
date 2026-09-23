# Ticket 08: Hebrew speech and text switching

Implemented on 2026-09-20 using the repository's Matt Pocock specification, ticket, diagnosis, TDD, and two-axis review workflow.

## What changed

- Hebrew Edge synthesis has a three-second network budget, then uses the installed macOS Carmit Enhanced voice. The daemon renders real 24 kHz WAV samples through `say`, checks for empty/silent output, and returns HTTP 503 when speech is unavailable. Native Hebrew now uses Carmit instead of looping back to Edge or silently finishing.
- Desktop playback owns asynchronous work by passage generation and playback ID. New passages, seeks, voice changes and previews stop existing audio, clear callbacks and buffers, cancel fetches and revoke object URLs. Late responses and completions are ignored.
- Sentence-level language routing supports mixed English/Hebrew passages. Local audio highlights sentences when playback starts. Speed is applied once by the audio player. Pausing before synthesis completes remains paused; local audio resumes correctly within WKWebView.
- Read checks new selection and changed clipboard content before toggling playback. An unchanged clipboard cannot replace an active selection. Webview activity and manual text are synchronized to the native coordinator. Delayed clipboard polling is invalidated when a newer passage arrives.
- Native speech completion, pause/resume and cloud callbacks are guarded against replacement. The browser companion retains pause during loading, rejects stale audio, routes each sentence appropriately, and can fall back from Edge to the local Carmit endpoint.
- Carmit is available in the desktop voice selectors. Settings previews interrupt old playback and complete without advancing a passage.

## Verification

The initial forced-offline test decoded **12,000 zero samples** and failed. It now passes using actual installed Carmit speech, checking peak amplitude above 0.01 and duration above 0.5 seconds. This requires access to macOS speech services; the sandbox alone produced an empty speech file.

The initial JavaScript text-switch test played `New passage` followed by stale `Old passage`. It now plays only the new passage. The extension pause test and review-driven highlighting/paused-error tests also failed before their fixes.

Final checks:

| Command / suite | Result |
| --- | --- |
| `.venv_guy/bin/python -m pytest tests/ -q` | 32 passed; two existing third-party deprecation warnings |
| `make test`: native speech | 40/40 passed |
| `make test`: existing UI/extractor | 160/160 passed |
| `make test`: native clipboard scenarios | 3 passed |
| `make test`: new desktop/extension JavaScript | 14 passed |
| `make clean && make` | Built successfully; zero compiler warnings/errors |
| JavaScript syntax and Python compilation | Passed |

The Python suite also invokes the JavaScript suite, so these counts are not all additive. Native cloud-fallback tests now force network failure at the OS network boundary instead of relying on live Bing/API availability. Native clipboard tests use an isolated adapter and do not overwrite the user's clipboard.

Logs are in `.scratch/unified-reader/verification/`. Original implementation files are in `.scratch/unified-reader/ticket08-backup/`; this workspace has no Git metadata. The legacy native test forbidding Carmit was updated because it contradicted the supplied handover.

## Review and practical limits

Independent standards and specification reviews found stale clipboard replacement, missing Hebrew highlighting, paused decoder fallback, preview completion ownership, and queued native pause ownership issues. All were repaired; the focused specification recheck passed.

The built app was opened and its Hebrew settings preview was triggered through the actual UI. It transitioned from Speaking back to Ready; the settings panel was then closed. Automated waveform checks establish non-silent speech; they do not judge pronunciation or subjective voice quality. Browser companion behavior was verified using its real scripts and controlled DOM/network/audio adapters; a live browser extension reload and end-to-end page-selection check remain manual verification.

Older ADRs and CONTEXT.md describe Phonikud acoustic synthesis and latency targets. The existing implementation does not deliver that pipeline. This repair implements the handover's explicit Carmit fallback; it does not claim Phonikud synthesis or sub-200ms latency.

## Using the result

Open `Guy_reader.app`. An already-running older app and daemon need a restart to load changes. For the browser companion, reload the unpacked extension and the page being read. Choose Carmit (Offline Hebrew) to avoid an initial network attempt, or retain Avri/Hila with automatic fallback.

Quick manual checks: test Hebrew in Settings; start an English passage and Paste Hebrew while it plays; seek a later sentence; Pause during loading and Resume; copy a new passage and click Paste. Repeat in the browser after extension reload.

## Ticket 09: click-to-read and current-word follow-along

Implemented on 2026-09-21. The desktop app now remembers the last accessible word clicked in the foreground app and reads from there through the remaining passage. Browser Read delegates to the companion extension, which maps the clicked DOM caret to visible source text and highlights the active sentence and word without rewriting the page. Hidden controls are excluded and line breaks remain word boundaries.

Synchronized mode is enabled by default. It joins consecutive same-language sentences so punctuation does not create synthesis/network gaps and uses real browser or macOS speech word-boundary callbacks. Neural mode remains selectable, prefetches the next sentence, and ties its clearly estimated word marker to media time. Pause/Resume preserves the clicked offset.

Stop now invalidates pending native capture, pending browser dispatch, active audio, speech callbacks, polling, and highlights. Browser commands expire, only one tab owns playback, and stale tab state cannot end a newer session. Clipboard text is read only through the explicit Paste control.

Final checks: `make test` passed 3 clicked-origin, 21 JavaScript playback, 3 coordinator, 40 native speech, and 160 extractor/UI checks. The bridge acknowledgment test passed, `make bundle` rebuilt the app, and a real macOS speech run produced five word-boundary events with correct mapping into the second sentence.

The launcher now starts and checks the localhost bridge before opening the GUI. This avoids a macOS GUI-child Python startup stall observed during the live launch check. The final live `/health` response reported `status: ok` with Kokoro loaded.

### Follow-up corrections from live examples

- Desktop Read no longer falls back to pre-existing clipboard text. Exact highlighted text takes priority over a remembered click; Paste is the only command that intentionally reads the existing clipboard.
- Browser Avri is now strict: selecting Avri forces neural playback, persists the choice, bypasses Carmit/local routing, and stops with an error if Avri is unavailable instead of changing to Hila or Carmit.
- X/Twitter extraction prefers the clicked tweet or long-form article container, excludes the `Article` and `Conversation` tabs, and avoids unrelated main-column headers.
