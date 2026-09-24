#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# 1. Check if already running
if curl -fsS --max-time 1 http://127.0.0.1:5050/health >/dev/null 2>&1; then
  echo "=================================================="
  echo "✅ Guy Reader Speech Engine is ALREADY RUNNING!"
  echo "   URL: http://127.0.0.1:5050"
  echo "=================================================="
  exit 0
fi

# 2. Find python interpreter
PYTHON="$DIR/.venv_guy/bin/python"
if [ ! -x "$PYTHON" ]; then PYTHON="$DIR/venv/bin/python"; fi
if [ ! -x "$PYTHON" ]; then PYTHON="$(which python3)"; fi

echo "🚀 Starting Guy Reader Speech Engine on port 5050..."
nohup "$PYTHON" "$DIR/speech_engine.py" >"$DIR/server.log" 2>&1 &

# 3. Wait for readiness (up to 15 seconds for model warmup)
for i in {1..50}; do
  if curl -fsS --max-time 1 http://127.0.0.1:5050/health >/dev/null 2>&1; then
    echo "=================================================="
    echo "✅ Guy Reader Speech Engine is UP & READY!"
    echo "   URL: http://127.0.0.1:5050"
    echo "   Voices: Robo-Shaul Hebrew, Edge Avri/Hila, Kokoro English"
    echo "   Ready for Chrome Extension & Mac App"
    echo "=================================================="
    exit 0
  fi
  sleep 0.3
done

echo "❌ Error: Speech engine did not respond in time. Check $DIR/server.log for details."
exit 1
