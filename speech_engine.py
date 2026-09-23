"""Guy Reader Speech Engine

Unified, local-first speech synthesis for English (Kokoro-82M) and Hebrew (Phonikud).
"""

from __future__ import annotations
import io
import re
import subprocess
import tempfile
import asyncio
import uuid
import time
from dataclasses import dataclass, field
from pathlib import Path
import numpy as np
import soundfile as sf

# Kokoro ONNX import
try:
    from kokoro_onnx import Kokoro
except ImportError:
    Kokoro = None

# Phonikud import
try:
    import phonikud
except ImportError:
    phonikud = None

# Robo-Shaul Hebrew TTS import
try:
    from roboshaul import RoboShaulSynthesizer
except ImportError:
    RoboShaulSynthesizer = None


def detect_language(text: str) -> str:
    """Detect whether a sentence is primarily Hebrew or English."""
    if not text:
        return "en"
    hebrew_chars = len(re.findall(r"[\u0590-\u05FF]", text))
    english_chars = len(re.findall(r"[a-zA-Z]", text))

    if hebrew_chars > 0 and (hebrew_chars >= english_chars or hebrew_chars >= 2):
        return "he"
    return "en"


def split_sentences(raw_text: str) -> list[str]:
    """Split raw text into clean sentences without breaking on decimals, URLs, or abbreviations."""
    if not raw_text:
        return []
    cleaned = raw_text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not cleaned:
        return []

    text = cleaned

    PLACEHOLDER = chr(0xE000)

    # 1. Protect numbers with decimals (e.g. 3.5, $19.99)
    text = re.sub(r"(\d)\.(\d)", rf"\g<1>{PLACEHOLDER}\g<2>", text)

    # 2. Protect email addresses
    text = re.sub(
        r"([a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)",
        lambda m: m.group(0).replace(".", PLACEHOLDER),
        text,
    )

    # 3. Protect URLs
    text = re.sub(
        r"(https?://[^\s]+)",
        lambda m: m.group(0).replace(".", PLACEHOLDER),
        text,
        flags=re.IGNORECASE,
    )

    # 4. Protect abbreviations (e.g. Dr., U.S., e.g., i.e., Mr., Mrs., etc.)
    abbreviations = [
        r"Dr\.", r"Mr\.", r"Mrs\.", r"Ms\.", r"Prof\.", r"Sr\.", r"Jr\.",
        r"vs\.", r"etc\.", r"e\.g\.", r"i\.e\.", r"U\.S\.", r"Inc\.", r"Corp\.",
        r"Co\.", r"Ltd\.", r"al\."
    ]
    for abbr in abbreviations:
        text = re.sub(
            r"\b" + abbr,
            lambda m: m.group(0).replace(".", PLACEHOLDER),
            text,
            flags=re.IGNORECASE,
        )

    # 5. Split on sentence terminals: . ! ? ׃ followed by quotes or whitespace
    regex = r"[^.!?\n׃]+(?:[.!?׃]+['\"”’\)\]]*|(?=[\n]|$))|[^.!?\n׃]+$"
    matches = [m.group(0) for m in re.finditer(regex, text)]
    if not matches:
        matches = [text]

    results = []
    for s in matches:
        restored = s.replace(PLACEHOLDER, ".").strip()
        # Only keep if contains at least one letter or digit
        if restored and re.search(r"[\w\u0590-\u05FF]", restored):
            results.append(restored)

    return results


@dataclass
class SynthesisResult:
    audio_bytes: bytes
    sample_rate: int
    duration_seconds: float
    language: str
    words: list[dict] = field(default_factory=list)


class SpeechEngine:
    """Local-first Speech Engine using Kokoro-82M and Phonikud."""

    def __init__(self, models_dir: str | Path | None = None):
        if models_dir is not None:
            self.models_dir = Path(models_dir)
        else:
            default_dir = Path(__file__).resolve().parent / "models"
            self.models_dir = default_dir if default_dir.exists() else Path("models")
        self.kokoro_model_path = self.models_dir / "kokoro-v1.0.onnx"
        self.kokoro_voices_path = self.models_dir / "voices-v1.0.bin"
        self._kokoro = None
        self._init_kokoro()
        self._roboshaul = None
        self._init_roboshaul()

    def _init_kokoro(self):
        if Kokoro and self.kokoro_model_path.exists() and self.kokoro_voices_path.exists():
            try:
                self._kokoro = Kokoro(
                    str(self.kokoro_model_path),
                    str(self.kokoro_voices_path),
                )
                self._warmup_background()
            except Exception as e:
                print(f"[SpeechEngine] Error initializing Kokoro: {e}")

    def _init_roboshaul(self):
        if RoboShaulSynthesizer:
            try:
                synth = RoboShaulSynthesizer(self.models_dir / "roboshaul")
                if synth.is_available():
                    self._roboshaul = synth
                    print("[SpeechEngine] Robo-Shaul synthesizer detected and ready.")
            except Exception as e:
                print(f"[SpeechEngine] Notice initializing Robo-Shaul: {e}")

    def _warmup_background(self):
        """Warm up ONNX model execution graphs in background to eliminate cold start latency on M4."""
        import threading
        def _warmup():
            try:
                if self._kokoro:
                    self._kokoro.create("Warmup.", voice="af_sarah", speed=1.0, lang="en-us")
                    print("[SpeechEngine] Kokoro-82M ONNX model warmed up successfully.")
            except Exception as e:
                print(f"[SpeechEngine] Warmup notice: {e}")

        threading.Thread(target=_warmup, daemon=True).start()

    def synthesize_sentence(
        self,
        text: str,
        voice: str | None = None,
        speed: float = 1.0,
    ) -> SynthesisResult:
        """Synthesize a single sentence to audio."""
        lang = detect_language(text)

        # Robo-Shaul Hebrew voice
        if voice in ("he-roboshaul", "roboshaul") or (lang == "he" and voice and "shaul" in voice.lower()):
            if self._roboshaul:
                try:
                    return self._synthesize_roboshaul(text, speed)
                except Exception as e:
                    print(f"[SpeechEngine] Robo-Shaul synthesis error, falling back to Edge Avri: {e}")
                    return self._synthesize_edge(text, "edge-he-avri", speed)
            return self._synthesize_edge(text, "edge-he-avri", speed)

        # Edge TTS voices (Hebrew Avri/Hila or English Jenny/Guy)
        if voice and voice.startswith("edge-"):
            return self._synthesize_edge(text, voice, speed)

        if lang == "en" and self._kokoro:
            kokoro_voice = voice if voice and voice.startswith(("af_", "am_", "bf_", "bm_")) else "af_sarah"
            samples, sample_rate = self._kokoro.create(
                text,
                voice=kokoro_voice,
                speed=float(speed),
                lang="en-us",
            )
            # Write WAV bytes in-memory
            buf = io.BytesIO()
            sf.write(buf, samples, sample_rate, format="WAV")
            audio_bytes = buf.getvalue()
            duration = float(len(samples)) / float(sample_rate)

            return SynthesisResult(
                audio_bytes=audio_bytes,
                sample_rate=sample_rate,
                duration_seconds=duration,
                language="en",
            )

        if lang == "en":
            return self._synthesize_native(text, speed, lang)

        # Hebrew synthesis strictly via Edge TTS (Avri/Hila), zero Carmit fallback
        return self._synthesize_edge(text, voice or "edge-he-avri", speed)

    def _synthesize_roboshaul(self, text: str, speed: float) -> SynthesisResult:
        """Synthesize Hebrew text via local Robo-Shaul (Tacotron2 + WaveGlow)."""
        audio_bytes, sample_rate, duration = self._roboshaul.synthesize(text, speed=speed)
        return SynthesisResult(
            audio_bytes=audio_bytes,
            sample_rate=sample_rate,
            duration_seconds=duration,
            language="he",
        )

    def _synthesize_edge(
        self,
        text: str,
        voice: str | None,
        speed: float,
    ) -> SynthesisResult:
        """Synthesize text via Edge TTS (Avri/Hila for Hebrew, Jenny/Guy for English)."""
        lang = detect_language(text)
        if lang == "he" or (voice and "he-" in voice):
            edge_voice = "he-IL-HilaNeural" if (voice and "hila" in voice.lower()) else "he-IL-AvriNeural"
            result_lang = "he"
        else:
            edge_voice = "en-US-GuyNeural" if (voice and "guy" in voice.lower()) else "en-US-JennyNeural"
            result_lang = "en"

        # Calculate rate string e.g. "+10%", "-20%"
        rate_val = int(round((speed - 1.0) * 100))
        rate_str = f"{rate_val:+d}%" if rate_val != 0 else "+0%"

        try:
            import asyncio
            import edge_tts

            async def _run_edge():
                communicate = edge_tts.Communicate(text, edge_voice, rate=rate_str)
                chunks = []
                async for chunk in communicate.stream():
                    if chunk["type"] == "audio":
                        chunks.append(chunk["data"])
                return b"".join(chunks)

            try:
                loop = asyncio.get_running_loop()
            except RuntimeError:
                loop = None

            if loop and loop.is_running():
                import concurrent.futures
                with concurrent.futures.ThreadPoolExecutor() as pool:
                    audio_data = pool.submit(lambda: asyncio.run(asyncio.wait_for(_run_edge(), timeout=10.0))).result()
            else:
                audio_data = asyncio.run(asyncio.wait_for(_run_edge(), timeout=10.0))

            if audio_data and len(audio_data) > 0:
                return SynthesisResult(
                    audio_bytes=audio_data,
                    sample_rate=24000,
                    duration_seconds=float(len(audio_data)) / 48000.0,
                    language=result_lang,
                )
            raise RuntimeError("Edge TTS returned zero audio bytes")
        except Exception as e:
            print(f"[SpeechEngine] Edge TTS synthesis error ({edge_voice}): {e}")
            if result_lang == "he":
                raise RuntimeError(f"Edge TTS Hebrew synthesis failed ({edge_voice}): {e}")
            raise RuntimeError(f"Edge TTS synthesis failed ({edge_voice}): {e}")

    def _synthesize_native(self, text: str, speed: float, language: str) -> SynthesisResult:
        """Render installed macOS speech to WAV for offline English. Never used for Hebrew."""
        if language == "he":
            raise RuntimeError("Carmit Hebrew speech is disabled. Please use Edge Neural voices (Avri/Hila).")
        try:
            listing = subprocess.run(
                ["/usr/bin/say", "-v", "?"], capture_output=True, text=True,
                check=True, timeout=5,
            ).stdout
            locale = "en_US"
            names = [line.split(locale)[0].strip() for line in listing.splitlines() if locale in line]
            preferred = "Evan (Enhanced)"
            if not names:
                raise RuntimeError("No installed en_US speech voice")
            voice = preferred if preferred in names else names[0]
            with tempfile.TemporaryDirectory(prefix="guy-reader-") as directory:
                output = Path(directory) / "speech.wav"
                subprocess.run(
                    ["/usr/bin/say", "-v", voice, "-r", str(round(175 * speed)),
                     "-o", str(output), "--file-format=WAVE", "--data-format=LEI16@24000", "-f", "-"],
                    input=text, capture_output=True, text=True, check=True, timeout=30,
                )
                audio_bytes = output.read_bytes()
            samples, sample_rate = sf.read(io.BytesIO(audio_bytes))
            if samples.size == 0 or not np.isfinite(samples).all() or not np.any(samples):
                raise RuntimeError("Installed voice produced empty or silent speech")
            return SynthesisResult(audio_bytes, sample_rate, len(samples) / sample_rate, language)
        except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
            raise RuntimeError(f"Speech synthesis unavailable for {language}: {exc}") from exc


# Global Engine Instance
engine = SpeechEngine()

# FastAPI Server Application
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Response, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import base64

app = FastAPI(title="Guy Reader Engine", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class SplitRequest(BaseModel):
    text: str


class SynthesizeRequest(BaseModel):
    text: str
    voice: str | None = None
    speed: float = Field(default=1.0, ge=0.5, le=2.5)


class TriggerRequest(BaseModel):
    action: str = "toggle-read"
    mode: str | None = None
    voice: str | None = None


connected_extensions: set[WebSocket] = set()
active_extension: WebSocket | None = None
pending_commands: dict[str, tuple[WebSocket, asyncio.Future]] = {}
browser_state = {"playing": False, "paused": False, "index": -1, "total": 0}


@app.get("/reader-state")
def reader_state():
    return browser_state


@app.post("/trigger")
async def trigger_endpoint(req: TriggerRequest):
    """Trigger command on connected browser companion extensions."""
    if not connected_extensions:
        return {"status": "no_extension", "connected": 0}
    
    ws = active_extension if active_extension in connected_extensions else next(iter(connected_extensions))
    request_id = uuid.uuid4().hex
    future = asyncio.get_running_loop().create_future()
    pending_commands[request_id] = (ws, future)
    expires_at = int((time.time() + 1.5) * 1000)
    try:
        await ws.send_json({"event": "command", "action": req.action, "mode": req.mode,
                            "voice": req.voice,
                            "requestId": request_id, "expiresAt": expires_at})
        handled = await asyncio.wait_for(future, timeout=1.5)
        return {"status": "ok" if handled else "no_extension", "dispatched": int(handled)}
    except (TimeoutError, RuntimeError, WebSocketDisconnect):
        return {"status": "no_extension", "dispatched": 0}
    finally:
        pending_commands.pop(request_id, None)


@app.get("/health")
def health():
    voices = [
        {"id": "af_sarah", "name": "Sarah (American Female)", "lang": "en"},
        {"id": "am_michael", "name": "Michael (American Male)", "lang": "en"},
        {"id": "edge-en-jenny", "name": "Jenny (English US - Edge AI)", "lang": "en"},
        {"id": "edge-en-guy", "name": "Guy (English US - Edge AI)", "lang": "en"},
        {"id": "he-roboshaul", "name": "Shaul (Hebrew Male - RoboShaul)", "lang": "he"},
        {"id": "edge-he-avri", "name": "Avri (Hebrew Male - Neural)", "lang": "he"},
        {"id": "edge-he-hila", "name": "Hila (Hebrew Female - Neural)", "lang": "he"},
    ]
    return {
        "status": "ok",
        "kokoro": engine._kokoro is not None,
        "roboshaul": engine._roboshaul is not None and engine._roboshaul.is_available(),
        "connected_extensions": len(connected_extensions),
        "voices": voices,
    }


@app.post("/split")
def split(req: SplitRequest):
    sentences = split_sentences(req.text)
    return {
        "sentences": [
            {"text": s, "lang": detect_language(s)}
            for s in sentences
        ]
    }


@app.post("/synthesize")
def synthesize(req: SynthesizeRequest):
    try:
        result = engine.synthesize_sentence(req.text, voice=req.voice, speed=req.speed)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=f"Speech synthesis unavailable: {exc}") from exc
    media_type = "audio/wav" if result.audio_bytes.startswith(b"RIFF") else "audio/mpeg"
    return Response(content=result.audio_bytes, media_type=media_type)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    global active_extension
    await websocket.accept()
    connected_extensions.add(websocket)
    try:
        while True:
            data = await websocket.receive_json()
            action = data.get("action")

            if action == "register":
                await websocket.send_json({"event": "registered", "status": "ok"})

            elif action == "focus":
                active_extension = websocket

            elif action == "command-result":
                pending = pending_commands.get(data.get("requestId"))
                if pending and pending[0] is websocket and not pending[1].done():
                    pending[1].set_result(data.get("success") is True)

            elif action == "reader-state":
                if active_extension is None or active_extension is websocket:
                    active_extension = websocket
                    browser_state.update({"playing": data.get("playing") is True,
                        "paused": data.get("paused") is True,
                        "index": data.get("index", -1), "total": data.get("total", 0)})

            elif action == "split":
                text = data.get("text", "")
                sentences = split_sentences(text)
                await websocket.send_json({
                    "event": "split_result",
                    "sentences": [{"text": s, "lang": detect_language(s)} for s in sentences]
                })

            elif action == "synthesize":
                text = data.get("text", "")
                voice = data.get("voice")
                speed = data.get("speed", 1.0)
                index = data.get("index", 0)

                result = engine.synthesize_sentence(text, voice=voice, speed=speed)
                audio_b64 = base64.b64encode(result.audio_bytes).decode("utf-8")

                await websocket.send_json({
                    "event": "sentence_audio",
                    "index": index,
                    "text": text,
                    "language": result.language,
                    "duration": result.duration_seconds,
                    "audio": audio_b64,
                })

    except WebSocketDisconnect:
        pass
    finally:
        connected_extensions.discard(websocket)
        if active_extension is websocket:
            active_extension = None
            browser_state.update(playing=False, paused=False)
        for owner, future in list(pending_commands.values()):
            if owner is websocket and not future.done(): future.set_result(False)


# Mount Web UI for cross-platform browser access (Windows, macOS, Linux)
_ui_path = Path(__file__).resolve().parent / "src" / "ui"
if _ui_path.exists():
    from fastapi.staticfiles import StaticFiles
    app.mount("/", StaticFiles(directory=str(_ui_path), html=True), name="ui")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5050)
