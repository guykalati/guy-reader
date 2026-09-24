#!/bin/bash
PLIST_PATH="$HOME/Library/LaunchAgents/com.guyreader.speechengine.plist"
if [ -f "$PLIST_PATH" ]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "✅ Auto-start disabled."
else
  echo "ℹ️ Auto-start was not enabled."
fi
