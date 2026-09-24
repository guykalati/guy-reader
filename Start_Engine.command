#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/start_engine.sh"
echo ""
echo "Press any key or close this window..."
read -n 1 -s -r -p ""
