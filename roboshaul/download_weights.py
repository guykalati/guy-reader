#!/usr/bin/env python3
"""
Robo-Shaul Model Weights Downloader.
Downloads Tacotron 2 (roboshaul_90K.pt) and WaveGlow (waveglow_256channels_universal_v5.pt)
from Hugging Face repo 'notmax123/robo_shaul' into models/roboshaul/.
"""

import os
import sys
from pathlib import Path

REPO_ID = "notmax123/robo_shaul"
FILES = [
    ("roboshaul_90K.pt", "roboshaul_90K.pt"),
    ("waveglow_256channels_universal_v5.pt", "waveglow_256channels_universal_v5.pt"),
]

def get_models_dir() -> Path:
    # Target directory: <repo_root>/models/roboshaul
    base_dir = Path(__file__).resolve().parent.parent
    models_dir = base_dir / "models" / "roboshaul"
    models_dir.mkdir(parents=True, exist_ok=True)
    return models_dir

def download_weights(target_dir: Path | None = None) -> bool:
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print("[RoboShaul] ERROR: huggingface_hub is not installed in the python environment.")
        return False

    if target_dir is None:
        target_dir = get_models_dir()

    print(f"[RoboShaul] Target directory: {target_dir}")
    all_ok = True

    for remote_filename, local_filename in FILES:
        destination = target_dir / local_filename
        if destination.exists() and destination.stat().st_size > 100_000_000:
            print(f"[RoboShaul] Already exists: {local_filename} ({destination.stat().st_size / (1024*1024):.1f} MB)")
            continue

        print(f"[RoboShaul] Downloading {remote_filename} from {REPO_ID}...")
        try:
            downloaded_path = hf_hub_download(
                repo_id=REPO_ID,
                filename=remote_filename,
                local_dir=str(target_dir),
                local_dir_use_symlinks=False,
            )
            print(f"[RoboShaul] Downloaded {local_filename} to {downloaded_path}")
        except Exception as e:
            print(f"[RoboShaul] ERROR downloading {remote_filename}: {e}")
            all_ok = False

    return all_ok

if __name__ == "__main__":
    success = download_weights()
    sys.exit(0 if success else 1)
