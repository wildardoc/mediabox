#!/bin/bash

# Auto-start script for smart bulk converter
# Designed to run after boot and system stabilization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERTER_SCRIPT="$SCRIPT_DIR/smart-bulk-convert.sh"
SCREEN_SESSION="mediabox-converter"

# Check if already running
if screen -list | grep -q "$SCREEN_SESSION"; then
    echo "Smart converter already running in screen session: $SCREEN_SESSION"
    exit 0
fi

# Wait for system load to stabilize
echo "Waiting for system to stabilize before starting conversions..."
for i in {1..6}; do
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    echo "Current load: $load_avg (check $i/6)"
    
    # If load is reasonable, proceed
    if (( $(echo "$load_avg < 25.0" | bc -l) )); then
        echo "System load acceptable, starting smart converter..."
        break
    fi
    
    # If this is the last check, start anyway
    if [[ $i -eq 6 ]]; then
        echo "Starting converter anyway after 6 checks..."
        break
    fi
    
    sleep 30
done

# Start smart converter for both movies and TV
echo "Starting smart bulk converter for movies and TV shows..."
cd "$SCRIPT_DIR"
screen -dmS "$SCREEN_SESSION" "$CONVERTER_SCRIPT" /Storage/media/movies /Storage/media/tv

# Verify it started
sleep 5
if screen -list | grep -q "$SCREEN_SESSION"; then
    echo "✅ Smart converter started successfully in screen session: $SCREEN_SESSION"
    echo "📊 Monitor with: screen -r $SCREEN_SESSION"
    echo "📈 View logs with: tail -f $SCRIPT_DIR/smart_bulk_convert_*.log"
else
    echo "❌ Failed to start smart converter"
    exit 1
fi
