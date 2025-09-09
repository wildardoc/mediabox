#!/bin/bash
# Quick estimation script for bulk conversion planning

cd "$(dirname "${BASH_SOURCE[0]}")"
source "../.env" 2>/dev/null || { echo "❌ .env not found"; exit 1; }

echo "📊 BULK CONVERSION PLANNING"
echo "=================================="

# Count files
movie_mkvs=$(find "$MOVIEDIR" -type f -name "*.mkv" | wc -l)
tv_mkvs=$(find "$TVDIR" -type f -name "*.mkv" | wc -l)
total_mkvs=$((movie_mkvs + tv_mkvs))

echo "📁 File counts:"
echo "  Movies (MKV):    $movie_mkvs files"
echo "  TV Shows (MKV):  $tv_mkvs files"
echo "  Total to convert: $total_mkvs files"
echo ""

# Size analysis
echo "💾 Storage analysis:"
movie_size=$(find "$MOVIEDIR" -name "*.mkv" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
tv_size=$(find "$TVDIR" -name "*.mkv" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
echo "  Movies (MKV):    $movie_size"
echo "  TV Shows (MKV):  $tv_size"

# Get available disk space
available=$(df -h "$MOVIEDIR" | awk 'NR==2 {print $4}')
echo "  Available space: $available"
echo ""

# Time estimates (based on typical conversion rates)
echo "⏱️  Time estimates (approximate):"
echo ""
echo "📈 Conservative estimates (assuming 0.5x real-time for video conversion):"
echo "  Average movie (2h):     ~60 minutes conversion time"
echo "  Average TV episode (45m): ~22 minutes conversion time"
echo ""

movie_hours=$((movie_mkvs * 60 / 60))
tv_hours=$((tv_mkvs * 22 / 60))
total_hours=$((movie_hours + tv_hours))

echo "🎬 Single-threaded estimates:"
echo "  Movies only:     ${movie_hours} hours ($(($movie_hours / 24)) days)"
echo "  TV shows only:   ${tv_hours} hours ($(($tv_hours / 24)) days)"
echo "  Total sequential: ${total_hours} hours ($(($total_hours / 24)) days)"
echo ""

# Parallel estimates
for cores in 2 4 8; do
    parallel_hours=$((total_hours / cores))
    parallel_days=$((parallel_hours / 24))
    echo "🚀 ${cores}-core parallel: ${parallel_hours} hours (${parallel_days} days)"
done
echo ""

echo "💡 RECOMMENDATIONS:"
echo "=================================="
echo ""
echo "🎯 Strategy 1: Start Small (Recommended)"
echo "  1. Test with movies first (smaller dataset: $movie_mkvs files)"
echo "     ./bulk-convert.sh movies"
echo "  2. Then tackle TV shows if satisfied with results"
echo "     ./bulk-convert.sh tv"
echo ""
echo "🚀 Strategy 2: Parallel Processing (Faster)"
echo "  • Install GNU parallel: sudo apt install parallel"
echo "  • Use 2-4 parallel jobs depending on CPU/storage"
echo "  • Start with: ./bulk-convert-parallel.sh movies"
echo ""
echo "⚠️  IMPORTANT CONSIDERATIONS:"
echo "  • Ensure 50%+ free disk space for temporary files"
echo "  • Monitor CPU temperature during heavy processing"
echo "  • Consider running during off-peak hours"
echo "  • Use screen/tmux for long-running processes"
echo "  • Test atomic operations are working: some conversions will create .tmp files"
echo ""
echo "🔧 PREPARATION STEPS:"
echo "  1. Run cleanup first: ./cleanup-conversions.sh --live"
echo "  2. Check system resources: htop, df -h"
echo "  3. Start screen session: screen -S conversion"
echo "  4. Begin with: ./bulk-convert.sh movies"
echo ""
