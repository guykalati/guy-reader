# Guy Reader 🔊

[![macOS](https://img.shields.io/badge/macOS-12.0%2B-black?logo=apple)](https://apple.com)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-blue?logo=windows)](https://microsoft.com)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python)](https://python.org)
[![Kokoro-82M](https://img.shields.io/badge/TTS-Kokoro--82M-green)](https://github.com/hexgrad/kokoro)
[![Robo--Shaul](https://img.shields.io/badge/TTS-Robo--Shaul-orange)](https://github.com/maxmelichov/Text-To-speech)
[![Chrome Extension](https://img.shields.io/badge/Extension-Manifest%20V3-yellow?logo=googlechrome)](https://developer.chrome.com/docs/extensions/mv3/)

> **Next-generation AI Text-to-Speech Reader with synchronized word-by-word follow-along highlighting, offline neural voices, and seamless browser & desktop integration for English and Hebrew.**

---

## ✨ Features

- 🧠 **Local Neural English Speech**: Powered by **Kokoro-82M ONNX** (Sarah & Michael) with zero cloud dependencies or API keys.
- 🎙️ **Local Neural Hebrew Speech**: Powered by **Robo-Shaul** (Tacotron 2 + WaveGlow trained on Shaul Amsterdamski's voice) with automatic diacritization via **Nakdimon ONNX**.
- 🌟 **Edge AI Neural Speech**: Free streaming voices for English (Jenny, Guy) and Hebrew (Avri, Hila). Carmit is permanently eliminated.
- 🌐 **Cross-Platform**:
  - **macOS**: Native floating pill & drawer app (`Guy_reader.app`) written in Cocoa/WebKit with global hotkey (`fn + G`) and click-to-read accessibility.
  - **Windows & Linux**: Web application served directly from the local daemon at `http://127.0.0.1:5050` with full player and drawer functionality.
- 🧩 **Companion Browser Extension**: In-situ DOM reader for Chrome, Edge, and Brave. Highlights sentences and words directly on Twitter/X, news articles, and long-form blogs with click-to-seek playback.
- ⚡ **Zero-Latency Pipelining**: Chained prebuffering synthesizes upcoming sentences in the background for gapless, natural narration.
- 🎛️ **Precision Speed Control**: 0.5x to 2.5x in granular 0.1x steps.

---

## 🤖 Agent Quickstart (Automated Setup)

If you are an **AI coding agent** (Antigravity, Claude Code, Cursor, Copilot) or setting this up from a terminal, execute these exact commands:

### 1. Clone & Set Up Python Environment
```bash
git clone https://github.com/guykalati/guy-reader.git
cd guy-reader

# Create virtual environment (Python 3.10+)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install all dependencies
pip install -r requirements.txt
```

### 2. Download Pre-Trained Neural Models
Downloads Kokoro-82M English ONNX (~337 MB) and Robo-Shaul Hebrew Tacotron2 + WaveGlow (~967 MB):
```bash
python download_models.py
```

### 3. Verify Tests
```bash
# Run backend engine tests
pytest tests/test_speech_engine.py

# Run UI & extractor tests (Node.js)
node --test tests/test_reader_playback.js tests/test_extension_playback.js tests/test_smart_extractor.js
```

---

## 🖥️ Running the Application

### Option A: Local Speech Engine & Cross-Platform Web App
The core daemon provides the FastAPI/WebSocket backend on port 5050 and serves the complete reading UI:

```bash
# Start speech engine & web UI
python speech_engine.py
```

- Open **`http://127.0.0.1:5050`** in any browser (Chrome, Edge, Safari, Firefox) on **macOS, Windows, or Linux**.
- Paste or type any English or Hebrew text, choose your voice, and enjoy full read-along playback!

---

### Option B: macOS Native Desktop App (`Guy_reader.app`)
On macOS, compile and bundle the native floating app:

```bash
# Compile native Cocoa/WebKit bundle
make bundle

# Launch application
open Guy_reader.app
```

#### macOS Hotkeys & Controls:
- **`fn + G`** (or **`fn + Space`**): Read highlighted text, clicked selection, or current foreground article.
- **`Space`** (in app): Toggle Play / Pause.
- **`Esc`**: Minimize floating pill.

---

### Option C: Companion Browser Extension (Chrome / Edge / Brave)
Read articles and tweets directly on the web with in-page glowing highlights:

1. Open your browser and navigate to:
   - Chrome / Brave: `chrome://extensions`
   - Microsoft Edge: `edge://extensions`
2. Enable **Developer mode** (toggle in the top-right corner).
3. Click **Load unpacked**.
4. Select the **`extension/`** directory inside this repository.
5. Make sure `python speech_engine.py` is running on your machine.
6. Open any article or tweet on [x.com](https://x.com), click the floating Guy Reader pill, and start listening!

---

## 🎙️ Available Voices

| Voice ID | Display Name | Language | Engine | Offline? |
| :--- | :--- | :---: | :--- | :---: |
| `af_sarah` | Sarah (American Female) | English | Kokoro-82M Neural ONNX | ✅ Yes |
| `am_michael` | Michael (American Male) | English | Kokoro-82M Neural ONNX | ✅ Yes |
| `he-roboshaul` | Shaul (Hebrew Male - RoboShaul) | Hebrew | Tacotron 2 + WaveGlow | ✅ Yes |
| `edge-he-avri` | Avri (Hebrew Male) | Hebrew | Microsoft Edge Neural | 🌐 Cloud |
| `edge-he-hila` | Hila (Hebrew Female) | Hebrew | Microsoft Edge Neural | 🌐 Cloud |
| `edge-en-jenny` | Jenny (English US) | English | Microsoft Edge Neural | 🌐 Cloud |
| `edge-en-guy` | Guy (English US) | English | Microsoft Edge Neural | 🌐 Cloud |
| `apple-evan` | Evan (Enhanced) | English | macOS Native Speech | ✅ Yes (Mac) |

---

## 📁 Repository Structure

```
guy-reader/
├── speech_engine.py       # Core local TTS server & WebSocket bridge (port 5050)
├── download_models.py     # Automated downloader for Kokoro & Robo-Shaul models
├── requirements.txt       # Pinned Python package dependencies
├── Makefile               # macOS native build & test runner
├── roboshaul/             # Robo-Shaul Hebrew TTS module
│   ├── synthesizer.py     # High-level RoboShaulSynthesizer class
│   ├── HebrewToEnglish.py # Hebrew grapheme to ARPAbet phonetic converter
│   ├── tacotron2/         # NVIDIA Tacotron 2 acoustic model
│   └── waveglow/          # NVIDIA WaveGlow vocoder
├── src/                   # macOS native app & Web UI
│   ├── main.m             # macOS Cocoa window & hotkey coordinator
│   ├── speech_engine.m    # Native AVFoundation & Edge fallback layer
│   ├── reading_origin.m   # Accessibility text inspection (AXUIElement)
│   └── ui/                # Reader UI (HTML/CSS/JS loaded in WebKit/Browser)
├── extension/             # Chromium companion extension (Manifest V3)
│   ├── manifest.json      # Extension manifest
│   ├── content.js         # In-situ DOM extractor & follow-along highlighter
│   └── background.js      # CSP bypass proxy & local engine WebSocket bridge
└── tests/                 # Automated test suites
    ├── test_speech_engine.py     # Python API & synthesis tests
    ├── test_reader_playback.js   # Desktop UI playback tests
    ├── test_extension_playback.js# Browser extension playback tests
    └── test_smart_extractor.js   # Article & Twitter extractor tests
```

---

## 🧪 Testing & Verification

Run the full verification suite anytime:

```bash
# macOS complete test suite
make test

# Python speech engine unit tests
pytest tests/test_speech_engine.py

# Node.js DOM & playback tests
node --test tests/test_reader_playback.js tests/test_extension_playback.js
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
Models are subject to their respective upstream licenses: [Kokoro-82M (Apache 2.0)](https://huggingface.co/hexgrad/Kokoro-82M), [SASPEECH (OpenSLR)](https://openslr.org/134), [Nakdimon (MIT)](https://github.com/elazarg/nakdimon).
