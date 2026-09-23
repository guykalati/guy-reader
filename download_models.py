#!/usr/bin/env python3
"""
Guy Reader Model Downloader.
Downloads pre-trained neural models for:
1. Kokoro-82M English ONNX TTS (kokoro-v1.0.onnx + voices-v1.0.bin)
2. Robo-Shaul Hebrew TTS (roboshaul_90K.pt + waveglow_256channels_universal_v5.pt)

Usage:
    python download_models.py           # Downloads all models
    python download_models.py --kokoro  # Downloads Kokoro English only
    python download_models.py --shaul   # Downloads Robo-Shaul Hebrew only
"""

import sys
import os
import argparse
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
ROBOSHAUL_DIR = MODELS_DIR / "roboshaul"

KOKORO_FILES = [
    {
        "name": "kokoro-v1.0.onnx",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx",
        "dest": MODELS_DIR / "kokoro-v1.0.onnx",
        "min_size": 300_000_000,
    },
    {
        "name": "voices-v1.0.bin",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin",
        "dest": MODELS_DIR / "voices-v1.0.bin",
        "min_size": 20_000_000,
    },
]

ROBOSHAUL_REPO = "notmax123/robo_shaul"
ROBOSHAUL_FILES = [
    ("roboshaul_90K.pt", "roboshaul_90K.pt", 300_000_000),
    ("waveglow_256channels_universal_v5.pt", "waveglow_256channels_universal_v5.pt", 600_000_000),
]


def download_file_with_progress(url: str, dest: Path, desc: str):
    if dest.exists() and dest.stat().st_size > 1000:
        print(f"  ✓ {desc} already exists ({dest.stat().st_size / (1024*1024):.1f} MB)")
        return True

    print(f"  Downloading {desc}...")
    dest.parent.mkdir(parents=True, exist_ok=True)
    temp_dest = dest.with_suffix(".tmp")

    try:
        def _reporthook(block_num, block_size, total_size):
            downloaded = block_num * block_size
            if total_size > 0:
                pct = min(100.0, downloaded * 100.0 / total_size)
                mb_down = downloaded / (1024 * 1024)
                mb_tot = total_size / (1024 * 1024)
                sys.stdout.write(f"\r    [{pct:5.1f}%] {mb_down:6.1f} MB / {mb_tot:6.1f} MB")
            else:
                mb_down = downloaded / (1024 * 1024)
                sys.stdout.write(f"\r    {mb_down:6.1f} MB downloaded")
            sys.stdout.flush()

        # Follow redirects
        opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler)
        urllib.request.install_opener(opener)
        urllib.request.urlretrieve(url, str(temp_dest), reporthook=_reporthook)
        print()
        temp_dest.rename(dest)
        print(f"  ✓ Saved to {dest}")
        return True
    except Exception as e:
        print(f"\n  ✗ Error downloading {desc}: {e}")
        if temp_dest.exists():
            temp_dest.unlink()
        return False


def download_kokoro():
    print("\n--- 1. Downloading Kokoro-82M English Models ---")
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    ok = True
    for item in KOKORO_FILES:
        success = download_file_with_progress(item["url"], item["dest"], item["name"])
        if not success:
            ok = False
    return ok


def download_roboshaul():
    print("\n--- 2. Downloading Robo-Shaul Hebrew Models ---")
    ROBOSHAUL_DIR.mkdir(parents=True, exist_ok=True)
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print("  ✗ huggingface_hub is not installed. Run: pip install huggingface_hub")
        return False

    ok = True
    for remote_name, local_name, min_size in ROBOSHAUL_FILES:
        dest = ROBOSHAUL_DIR / local_name
        if dest.exists() and dest.stat().st_size >= min_size:
            print(f"  ✓ {local_name} already exists ({dest.stat().st_size / (1024*1024):.1f} MB)")
            continue

        print(f"  Downloading {remote_name} from Hugging Face '{ROBOSHAUL_REPO}'...")
        try:
            downloaded = hf_hub_download(
                repo_id=ROBOSHAUL_REPO,
                filename=remote_name,
                local_dir=str(ROBOSHAUL_DIR),
                local_dir_use_symlinks=False,
            )
            print(f"  ✓ Saved to {downloaded}")
        except Exception as e:
            print(f"  ✗ Error downloading {remote_name}: {e}")
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(description="Guy Reader Model Downloader")
    parser.add_argument("--kokoro", action="store_true", help="Download only Kokoro-82M English models")
    parser.add_argument("--shaul", action="store_true", help="Download only Robo-Shaul Hebrew models")
    args = parser.parse_args()

    download_all = not args.kokoro and not args.shaul

    success = True
    if download_all or args.kokoro:
        if not download_kokoro():
            success = False

    if download_all or args.shaul:
        if not download_roboshaul():
            success = False

    if success:
        print("\n🎉 All requested models are ready for synthesis!")
        sys.exit(0)
    else:
        print("\n⚠️ Some models could not be downloaded. Check the errors above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
