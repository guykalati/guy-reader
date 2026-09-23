# 0003: Unified Desktop App and Browser Companion Bridge

## Context
Users consume text across both native macOS apps (PDFs, Notes, Word, Slack) and web browsers (Chrome, Brave, Arc, Safari). Creating two isolated applications causes configuration drift and disjointed user experience, while native apps cannot directly manipulate browser DOM for in-situ highlighting without a bridge.

## Decision
Build Guy Reader as a single Unified macOS Desktop Application backed by a local server (port 5050) and paired with a lightweight Chrome companion extension.
- When reading in a supported browser, the desktop app coordinates with the webpage via the local bridge to deliver in-situ DOM highlighting and click-to-jump seeking.
- When reading native desktop apps (or if the browser extension is inactive), the app seamlessly captures selection/clipboard and displays follow-along text within the native floating Readest drawer.

## Consequences
- The user operates a single application and single hotkey (`Fn + G` / `Option + G`) everywhere.
- In-situ web highlighting and desktop reading share the exact same Kokoro + Phonikud audio synthesis pipeline and settings.
