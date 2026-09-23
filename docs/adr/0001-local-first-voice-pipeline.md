# 0001: Local-First Voice Pipeline (Kokoro-82M and Phonikud)

## Context
Previous speech synthesis relied on cloud Edge TTS and older acoustic models, resulting in stutter, high latency, repetitive word glitches, and robotic Hebrew pronunciation.

## Decision
Adopt a local-first speech synthesis architecture using `Kokoro-82M` for English and `Phonikud` for Hebrew.

## Considered Options
- **Coqui XTTS v2**: Rejected due to heavy memory footprint (>3GB model), slow startup, and high synthesis latency on local machines.
- **Cloud Edge TTS**: Retained only as an optional secondary fallback; disqualified as primary engine due to network dependency and audio stutter.
- **Local Kokoro-82M + Phonikud**: Accepted for lightweight footprint (~82MB), near-studio English intonation, state-of-the-art Hebrew G2P phonemization, and sub-200ms offline generation.
