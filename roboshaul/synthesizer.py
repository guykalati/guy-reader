"""Robo-Shaul Neural Hebrew Speech Synthesizer.

Wraps NVIDIA Tacotron 2 + WaveGlow trained on SASPEECH (Shaul Amsterdamski)
with automatic Hebrew diacritization (Nakdimon) and phonetic mapping (HebrewToEnglish).
"""

from __future__ import annotations
import io
import re
import sys
import threading
from pathlib import Path
import numpy as np
import scipy.io.wavfile as wavfile

# Ensure tacotron2 and waveglow directories are in sys.path for unpickling & sub-imports
_PKG_DIR = Path(__file__).resolve().parent
_TACOTRON_DIR = _PKG_DIR / "tacotron2"
_WAVEGLOW_DIR = _PKG_DIR / "waveglow"

for _p in [str(_PKG_DIR), str(_TACOTRON_DIR), str(_WAVEGLOW_DIR)]:
    if _p not in sys.path:
        sys.path.insert(0, _p)

try:
    import torch
except ImportError:
    torch = None

try:
    import nakdimon
except ImportError:
    nakdimon = None

try:
    import HebrewToEnglish
except ImportError:
    HebrewToEnglish = None

try:
    import glow
    from tacotron2.hparams import create_hparams
    from tacotron2.model import Tacotron2
    from tacotron2.text import text_to_sequence
    from waveglow.denoiser import Denoiser
except ImportError as _e:
    glow = None
    create_hparams = None
    Tacotron2 = None
    text_to_sequence = None
    Denoiser = None


def has_niqqud(text: str) -> bool:
    """Check if text already contains Hebrew vowel points (niqqud)."""
    return bool(re.search(r"[\u0591-\u05BD\u05BF\u05C1\u05C2\u05C4\u05C5\u05C7]", text))


class RoboShaulSynthesizer:
    """High-performance local Hebrew speech synthesizer for Robo-Shaul."""

    _global_load_lock = threading.Lock()

    def __init__(self, models_dir: Path | str | None = None, device: str | None = None, use_denoiser: bool = False):
        if models_dir is not None:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = _PKG_DIR.parent / "models" / "roboshaul"

        self.tacotron_path = self.models_dir / "roboshaul_90K.pt"
        self.waveglow_path = self.models_dir / "waveglow_256channels_universal_v5.pt"
        self.use_denoiser = use_denoiser

        if device:
            self.device = torch.device(device) if torch else None
        elif torch and torch.backends.mps.is_available():
            self.device = torch.device("mps")
        elif torch and torch.cuda.is_available():
            self.device = torch.device("cuda")
        elif torch:
            self.device = torch.device("cpu")
        else:
            self.device = None

        self.tacotron_model = None
        self.waveglow_model = None
        self.denoiser = None
        self._lock = threading.Lock()
        self._loaded = False

    def is_available(self) -> bool:
        """Check if models and dependencies are available."""
        return (
            torch is not None
            and nakdimon is not None
            and HebrewToEnglish is not None
            and Tacotron2 is not None
            and self.tacotron_path.exists()
            and self.waveglow_path.exists()
        )

    def load_models(self) -> bool:
        """Load Tacotron 2 and WaveGlow models into memory."""
        with RoboShaulSynthesizer._global_load_lock:
            if self._loaded:
                return True

            if not self.is_available():
                print(f"[RoboShaul] Models or dependencies missing (tacotron: {self.tacotron_path.exists()}, waveglow: {self.waveglow_path.exists()})")
                return False

            try:
                print(f"[RoboShaul] Loading models onto {self.device}...")
                # 1. Tacotron 2
                hparams = create_hparams()
                hparams.sampling_rate = 22050
                hparams.max_decoder_steps = 1000
                hparams.gate_threshold = 0.1

                self.tacotron_model = Tacotron2(hparams)
                taco_ckpt = torch.load(self.tacotron_path, map_location=self.device, weights_only=False)
                self.tacotron_model.load_state_dict(taco_ckpt["state_dict"])
                self.tacotron_model = self.tacotron_model.to(self.device).eval()

                # 2. WaveGlow
                wg_ckpt = torch.load(self.waveglow_path, map_location=self.device, weights_only=False)
                self.waveglow_model = wg_ckpt["model"].to(self.device).eval()
                for k in self.waveglow_model.convinv:
                    k.float()

                if self.use_denoiser:
                    self.denoiser = Denoiser(self.waveglow_model).to(self.device)
                else:
                    self.denoiser = None

                # Pre-warm Nakdimon ONNX graph and MPS shaders to avoid first-sentence delay
                try:
                    import nakdimon.predict
                    nakdimon.predict.predict("שלום", maxlen=64)
                    dummy_seq = torch.zeros((1, 2), dtype=torch.long, device=self.device)
                    with torch.no_grad():
                        _, dummy_mel, _, _ = self.tacotron_model.inference(dummy_seq)
                        _ = self.waveglow_model.infer(dummy_mel, sigma=0.8)
                except Exception:
                    pass

                self._loaded = True
                print("[RoboShaul] Models loaded successfully!")
                return True
            except Exception as e:
                print(f"[RoboShaul] Failed to load models: {e}")
                self._loaded = False
                return False

    @staticmethod
    def _trim_silence(audio_np: np.ndarray, sample_rate: int = 22050, threshold: float = 0.012, pad_ms: int = 40) -> np.ndarray:
        """Trim dead silence from ends while keeping a natural decay to avoid abrupt cutoffs."""
        abs_audio = np.abs(audio_np)
        above = np.where(abs_audio > threshold)[0]
        if len(above) == 0:
            return audio_np
        pad_samples = int(pad_ms * sample_rate / 1000)
        start_idx = max(0, above[0] - pad_samples)
        end_idx = min(len(audio_np), above[-1] + pad_samples)
        trimmed = audio_np[start_idx:end_idx].copy()

        # Apply gentle 10ms cosine fade-out at the tail to prevent clicks
        fade_samples = min(int(0.010 * sample_rate), len(trimmed))
        if fade_samples > 0:
            taper = 0.5 * (1.0 + np.cos(np.linspace(0, np.pi, fade_samples)))
            trimmed[-fade_samples:] *= taper
        return trimmed

    def synthesize(self, text: str, speed: float = 1.0) -> tuple[bytes, int, float]:
        """Synthesize Hebrew text to 22.05 kHz 16-bit WAV bytes.

        Returns:
            (audio_bytes, sample_rate, duration_seconds)
        """
        if not self._loaded:
            if not self.load_models():
                raise RuntimeError("Robo-Shaul models could not be loaded")

        cleaned = text.strip()
        if not cleaned:
            raise ValueError("Input text is empty")

        # 1. Diacritize with Nakdimon using adaptive sequence length (100x faster than fixed 10k)
        if not has_niqqud(cleaned):
            maxlen = min(1000, max(64, len(cleaned) + 32))
            try:
                import nakdimon.predict
                vocalized = nakdimon.predict.predict(cleaned, maxlen=maxlen)
            except Exception:
                vocalized = nakdimon.diacritize(cleaned)
        else:
            vocalized = cleaned

        # 2. Convert vocalized Hebrew to ARPAbet phonetic sounds
        phonetic = HebrewToEnglish.HebrewToEnglish(vocalized)
        if not phonetic.strip():
            phonetic = cleaned

        # 3. Convert phonetic string to Tacotron sequence
        sequence = np.array(text_to_sequence(phonetic, ["english_cleaners"]))[None, :]
        sequence_tensor = torch.from_numpy(sequence).long().to(self.device)

        # 4. Neural inference
        with self._lock, torch.no_grad():
            _, mel_outputs_postnet, _, _ = self.tacotron_model.inference(sequence_tensor)
            audio = self.waveglow_model.infer(mel_outputs_postnet, sigma=0.8)
            if self.use_denoiser and self.denoiser:
                audio = self.denoiser(audio, strength=0.01)[:, 0]
            audio_np = audio[0].cpu().numpy().astype(np.float32)

        sample_rate = 22050

        # 5. Trim trailing/leading silence for natural, instant pacing between dots/sentences
        audio_np = self._trim_silence(audio_np, sample_rate=sample_rate)

        # 6. Speed adjustment via librosa time stretching if speed != 1.0
        if speed != 1.0 and 0.5 <= speed <= 2.5:
            try:
                import librosa
                audio_np = librosa.effects.time_stretch(audio_np, rate=float(speed))
            except Exception as e:
                print(f"[RoboShaul] Time stretch warning: {e}")

        # 7. Normalize and encode as 16-bit PCM WAV
        max_val = np.max(np.abs(audio_np))
        if max_val > 1.0:
            audio_np = audio_np / max_val

        audio_int16 = (audio_np * 32767.0).astype(np.int16)
        buf = io.BytesIO()
        wavfile.write(buf, sample_rate, audio_int16)
        audio_bytes = buf.getvalue()
        duration = float(len(audio_int16)) / float(sample_rate)

        return audio_bytes, sample_rate, duration
