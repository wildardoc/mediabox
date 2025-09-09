#!/bin/bash
# Safe bulk conversion preparation - checks for active processes

cd "$(dirname "${BASH_SOURCE[0]}")"
source "../.env" 2>/dev/null || { echo "❌ .env not found"; exit 1; }

echo "🔍 SAFE CONVERSION PREPARATION CHECK"
echo "====================================="

# Check for active media processes
echo "📡 Checking for active media processes..."

# Check for running ffmpeg processes
ffmpeg_processes=$(pgrep -f ffmpeg | wc -l)
if [[ $ffmpeg_processes -gt 0 ]]; then
    echo "⚠️  WARNING: $ffmpeg_processes active ffmpeg process(es) detected"
    echo "   Active conversions:"
    pgrep -f ffmpeg | while read pid; do
        ps -p $pid -o pid,etime,cmd --no-headers | head -c 100
        echo "..."
    done
    echo ""
    echo "❌ RECOMMENDATION: Wait for active conversions to complete before bulk processing"
    echo "   Monitor with: ps aux | grep ffmpeg"
    exit 1
fi

# Check for media_update.py processes
media_update_processes=$(pgrep -f media_update.py | wc -l)
if [[ $media_update_processes -gt 0 ]]; then
    echo "⚠️  WARNING: $media_update_processes active media_update.py process(es) detected"
    pgrep -f media_update.py | while read pid; do
        ps -p $pid -o pid,etime,cmd --no-headers
    done
    echo ""
    echo "❌ RECOMMENDATION: Wait for active media processing to complete"
    exit 1
fi

# Check for import.sh processes (webhook activity)
import_processes=$(pgrep -f import.sh | wc -l)
if [[ $import_processes -gt 0 ]]; then
    echo "⚠️  WARNING: $import_processes active import.sh process(es) detected"
    echo "   This indicates recent webhook activity from *arr applications"
    pgrep -f import.sh | while read pid; do
        ps -p $pid -o pid,etime,cmd --no-headers
    done
    echo ""
    echo "❌ RECOMMENDATION: Wait for webhook imports to complete before bulk processing"
    exit 1
fi

echo "✅ No active media processing detected"
echo ""

# Check system resources
echo "💻 Current system resources:"
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
memory_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2*100}')
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

echo "   CPU usage: ${cpu_usage}%"
echo "   Memory usage: ${memory_usage}%"
echo "   Load average: ${load_avg}"
echo ""

# Check recent webhook activity
echo "📊 Recent webhook activity (last 30 minutes):"
recent_imports=$(find . -name "import_$(date +%Y%m%d).log" -mmin -30 2>/dev/null | wc -l)
if [[ $recent_imports -gt 0 ]]; then
    echo "   Recent import activity detected in logs"
    tail -5 import_$(date +%Y%m%d).log 2>/dev/null | grep -E "\[(INFO|ERROR)\]" | tail -3
    echo ""
    echo "⚠️  Consider waiting 10-15 minutes after last import activity"
else
    echo "   No recent import activity detected"
fi
echo ""

# Check for temp files from interrupted conversions
echo "🧹 Checking for orphaned temp files..."
temp_files=$(find "$MOVIEDIR" "$TVDIR" -name "*.tmp.mp4" -o -name "*.tmp.mp3" 2>/dev/null | wc -l)
if [[ $temp_files -gt 0 ]]; then
    echo "   Found $temp_files orphaned temp files"
    echo "   These are likely from previous interrupted conversions"
    echo ""
    echo "💡 You can clean these up with: ./cleanup-conversions.sh --live"
    echo "   (But since you mentioned cleanup was already run, these might be from very recent activity)"
else
    echo "✅ No orphaned temp files found"
fi
echo ""

# Final recommendations
echo "🎯 SAFE BULK CONVERSION RECOMMENDATIONS:"
echo "========================================"
echo ""

if [[ $ffmpeg_processes -eq 0 && $media_update_processes -eq 0 && $import_processes -eq 0 ]]; then
    echo "✅ SAFE TO PROCEED with bulk conversion"
    echo ""
    echo "🚀 Recommended next steps:"
    echo "   1. Start a screen session: screen -S bulk-conversion"
    echo "   2. Monitor system resources: htop (in another terminal)"
    echo "   3. Begin with movies: ./bulk-convert.sh movies"
    echo ""
    echo "📈 Monitoring during conversion:"
    echo "   • Watch logs: tail -f bulk-conversion-logs/bulk-conversion.log"
    echo "   • Check progress: ls bulk-conversion-logs/"
    echo "   • Monitor resources: htop, iotop"
    echo ""
    echo "⏹️  To stop safely: Ctrl+C in the conversion script (will finish current file)"
else
    echo "⚠️  WAIT RECOMMENDED - Active processes detected"
    echo ""
    echo "🕐 Check again in 15-30 minutes with:"
    echo "     ./prepare-bulk-conversion.sh"
fi
echo ""

echo "💾 Storage check:"
available_gb=$(df --output=avail "$MOVIEDIR" | tail -1 | awk '{print int($1/1024/1024)}')
echo "   Available space: ${available_gb}GB"
if [[ $available_gb -lt 500 ]]; then
    echo "   ⚠️  WARNING: Less than 500GB available - monitor disk space during conversion"
else
    echo "   ✅ Sufficient disk space available"
fi
