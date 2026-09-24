#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/Library/LaunchAgents"
PLIST_PATH="$HOME/Library/LaunchAgents/com.guyreader.speechengine.plist"
PYTHON="$DIR/.venv_guy/bin/python"
if [ ! -x "$PYTHON" ]; then PYTHON="$DIR/venv/bin/python"; fi

cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.guyreader.speechengine</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$DIR/speech_engine.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$DIR/server.log</string>
    <key>StandardErrorPath</key>
    <string>$DIR/server.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo "=================================================="
echo "✅ Guy Reader Auto-Start Enabled!"
echo "   The speech engine will now automatically start"
echo "   whenever your Mac boots or you log in."
echo "=================================================="
