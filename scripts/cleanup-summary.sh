#!/bin/bash
# Quick summary script to show what cleanup-conversions.py would do

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/.venv/bin/python"

echo "🔍 Media Conversion Cleanup Summary"
echo "=================================="
echo ""

echo "Scanning TV directory..."
tv_result=$("$VENV_PYTHON" "$SCRIPT_DIR/cleanup-conversions.py" --dirs "/Storage/media/tv" --log-level WARNING 2>/dev/null | grep -E "(Files scanned|pairs found|Valid|Invalid)" || echo "No results")

echo "Scanning Movies directory..." 
movie_result=$("$VENV_PYTHON" "$SCRIPT_DIR/cleanup-conversions.py" --dirs "/Storage/media/movies" --log-level WARNING 2>/dev/null | grep -E "(Files scanned|pairs found|Valid|Invalid)" || echo "No results")

echo ""
echo "📺 TV Results:"
echo "$tv_result"
echo ""
echo "🎬 Movie Results:"  
echo "$movie_result"
echo ""
echo "💡 To clean up corrupted files, run:"
echo "   ./cleanup-conversions.sh --live --dirs '/Storage/media/tv' '/Storage/media/movies'"
