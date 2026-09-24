#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "🛑 Stopping Guy Reader Speech Engine..."
pkill -f "$DIR/speech_engine.py" 2>/dev/null || true
echo "✅ Guy Reader Speech Engine stopped."
