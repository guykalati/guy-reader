#!/bin/bash
echo "Stopping Pocket TTS Reader server..."
if lsof -i :8000 >/dev/null 2>&1; then
    lsof -ti:8000 | xargs kill -9 2>/dev/null
    echo "✅ Pocket TTS server on port 8000 has been stopped successfully."
else
    echo "ℹ️ Pocket TTS server is not currently running."
fi
