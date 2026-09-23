#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Kill any existing instance
pkill -f "Guy_reader.app/Contents/MacOS/Guy_reader" 2>/dev/null || true
pkill -f "GlaidoReader.app/Contents/MacOS/GlaidoReader" 2>/dev/null || true
pkill -f "$DIR/speech_engine.py" 2>/dev/null || true

# Always ensure app bundle is fresh
make -s

# Start the local browser bridge before the GUI. Launching framework Python as
# a GUI child can stall in macOS path initialization; the shell-owned daemon is
# also easier to health-check and survives an app UI restart.
PYTHON="$DIR/.venv_guy/bin/python"
if [ ! -x "$PYTHON" ]; then PYTHON="$DIR/venv/bin/python"; fi
nohup "$PYTHON" "$DIR/speech_engine.py" >"$DIR/server.log" 2>&1 &
for _ in {1..30}; do
  if curl -fsS --max-time 1 http://127.0.0.1:5050/health >/dev/null 2>&1; then break; fi
  sleep 0.2
done

if ! curl -fsS --max-time 1 http://127.0.0.1:5050/health >/dev/null 2>&1; then
  echo "Warning: local browser bridge did not become ready. See $DIR/server.log"
fi

# Launch Guy_reader in the background
open "$DIR/Guy_reader.app"

echo "===================================================="
echo "  🔊 Guy_reader Launched Successfully!"
echo "===================================================="
echo "• Look for the floating Obsidian pill and menu bar icon (🔊)."
echo "• Global Shortcuts to Read:"
echo "    - Fn + Space"
echo "    - Control + Space (⌃ + Space)"
echo "• You can also click the [Read] button on the pill directly."
echo "• Default Voice: Apple Evan (Enhanced)"
echo "• Natural Hebrew AI Voices: Edge Avri & Hila"
echo "• Synchronized word following uses installed Evan/Carmit voices."
echo "===================================================="
