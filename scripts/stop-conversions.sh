#!/bin/bash
# Stop running media conversions gracefully

set -euo pipefail

echo "🛑 Stopping running media conversions..."
echo ""

# Find all media conversion processes
echo "📍 Current conversion processes:"
ps aux | grep -E "(ffmpeg|media_update\.py)" | grep -v grep | while read line; do
    echo "  $line"
done

echo ""
echo "Stopping processes..."

# Stop media_update.py processes first (parent processes)
media_pids=$(ps aux | grep "media_update\.py" | grep -v grep | awk '{print $2}' || true)
if [[ -n "$media_pids" ]]; then
    echo "🔄 Stopping media_update.py processes..."
    for pid in $media_pids; do
        echo "  Stopping PID $pid"
        kill -TERM "$pid" 2>/dev/null || echo "    Already stopped or permission denied"
    done
    
    # Wait a moment for graceful shutdown
    sleep 5
fi

# Stop any remaining ffmpeg processes
ffmpeg_pids=$(ps aux | grep "ffmpeg" | grep -v grep | awk '{print $2}' || true)
if [[ -n "$ffmpeg_pids" ]]; then
    echo "🎬 Stopping ffmpeg processes..."
    for pid in $ffmpeg_pids; do
        echo "  Stopping PID $pid"
        kill -TERM "$pid" 2>/dev/null || echo "    Already stopped or permission denied"
    done
    
    # Wait for processes to terminate gracefully
    sleep 10
    
    # Force kill if still running
    ffmpeg_pids=$(ps aux | grep "ffmpeg" | grep -v grep | awk '{print $2}' || true)
    if [[ -n "$ffmpeg_pids" ]]; then
        echo "⚠️  Force killing remaining ffmpeg processes..."
        for pid in $ffmpeg_pids; do
            echo "  Force killing PID $pid"
            kill -KILL "$pid" 2>/dev/null || echo "    Already stopped"
        done
    fi
fi

echo ""
echo "✅ Checking final state..."
remaining=$(ps aux | grep -E "(ffmpeg|media_update\.py)" | grep -v grep || true)
if [[ -z "$remaining" ]]; then
    echo "🎉 All conversion processes stopped successfully!"
else
    echo "⚠️  Some processes may still be running:"
    echo "$remaining"
fi

echo ""
echo "💡 You can now safely run the cleanup script."
