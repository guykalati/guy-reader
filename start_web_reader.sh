#!/bin/bash
DIR="$(dirname "$0")"
cd "$DIR"

echo "=========================================================="
echo "🎙️ Starting Pocket TTS Visual PDF Reader..."
echo "=========================================================="

if ! curl -s http://127.0.0.1:8000/api/voices >/dev/null 2>&1; then
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
    nohup "$DIR/.venv/bin/python" "$DIR/pdf_reader_web.py" --model "$DIR/pocket-tts-english.onnx" --port 8000 > "$DIR/server.log" 2>&1 &
    
    for i in {1..25}; do
        if curl -s http://127.0.0.1:8000/api/voices >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done
fi

open "http://127.0.0.1:8000"
echo "✅ Pocket TTS Reader is running at http://127.0.0.1:8000"
