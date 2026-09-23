# 0002: Sentence-Level Bilingual Streaming Pipeline

## Context
Synthesizing long mixed-language articles in bulk creates unacceptable delays (5-10 seconds of silence before playback) and prevents seamless code-switching between Hebrew and English.

## Decision
Implement a sentence-by-sentence streaming synthesis pipeline with per-sentence Unicode script detection. Hebrew sentences route to Phonikud, while English sentences route to Kokoro-82M. Sentences are pre-buffered concurrently, and user seeks ("Click-to-Jump") immediately flush the playback buffer and re-anchor synthesis.

## Consequences
- Audio begins playing within ~150ms of activation.
- Seeking is responsive with zero audio overlap.
- Memory consumption remains low since entire articles are never rendered to a single monolithic audio file.
