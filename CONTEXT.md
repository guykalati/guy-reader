# CONTEXT.md

## System Overview

**Guy Reader** is a unified, local-first text-to-speech reading suite designed for seamless English and Hebrew reading with synchronized visual follow-along highlighting across both desktop applications and web pages.

## Domain Glossary

- **Unified App**: The single macOS application that orchestrates reading across desktop windows and browser tabs, triggered via global hotkey (`Fn + G`, fallback `Option + G`) or floating controls.
- **Reader Pill**: The compact, draggable floating window in macOS that floats above all apps, hosting transport controls (Play/Pause/Stop), speed adjustment, and the voice settings drawer.
- **Readest Drawer**: The expandable desktop view displaying the text passage with glowing follow-along highlights when reading native macOS applications (PDFs, Notes, Word).
- **Web Follow-Along**: Highlighting individual words and sentences directly inside the active webpage's DOM elements with smooth auto-scroll as audio plays.
- **Web Control Badge**: A compact, floating widget rendered directly inside the web browser providing in-situ transport controls (Play/Pause, Speed, Stop) and the Clean Reader Mode toggle.
- **Clean Reader Mode**: An optional distraction-free overlay mode powered by Mozilla Readability that reformats cluttered web pages into clean typography with synchronized sentence follow-along.
- **Click-to-Jump**: Interactive web capability allowing the user to click any word or sentence on the webpage to immediately seek audio playback to that position.
- **Smart Hierarchy**: The content extraction strategy that prioritizes the user's cursor selection if present, and automatically falls back to full-article extraction from the first word to the end if no text is selected.
- **Article Extractor**: Logic (leveraging Readability standards) that isolates the core article text while filtering out navigation menus, sidebars, and advertising.
- **Local Voice Pipeline**: The offline speech synthesis subsystem powered by Kokoro-82M (for English) and Phonikud (for Hebrew).
- **Sentence-Level Language Router**: The bilingual dispatcher that inspects Unicode script per sentence and dynamically directs Hebrew text to Phonikud and English/Latin text to Kokoro-82M.
- **Streaming Pipeline**: The sentence-by-sentence synthesis and pre-buffering audio pipeline ensuring sub-200ms time-to-first-sound and instant buffer flushing upon seek.
- **Context-Aware Hotkey**: Hotkey re-trigger logic that toggles Play/Pause if the user is listening to the existing passage, or cancels and starts anew if a new selection or page has been focused.
