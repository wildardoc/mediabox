#!/bin/bash
set -euo pipefail

# Mediabox Environment Validation Script
# This script checks if all required components are present for media processing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/mediabox_config.json"

echo "🔍 Validating Mediabox environment..."

# Check configuration file
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Configuration file missing: $CONFIG_FILE"
    echo "💡 Run mediabox.sh setup or manually create the configuration file"
    exit 1
else
    echo "✅ Configuration file found: $CONFIG_FILE"
    
    # Validate JSON syntax
    if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "✅ Configuration file has valid JSON syntax"
    else
        echo "❌ Configuration file has invalid JSON syntax"
        exit 1
    fi
fi

# Check Python dependencies
echo "🐍 Checking Python dependencies..."
python_deps=("ffmpeg" "future" "plexapi" "requests")
missing_deps=()

for dep in "${python_deps[@]}"; do
    if python3 -c "import $dep" > /dev/null 2>&1; then
        echo "✅ Python package '$dep' is available"
    else
        echo "❌ Python package '$dep' is missing"
        missing_deps+=("$dep")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "💡 Install missing dependencies with: pip3 install ${missing_deps[*]}"
    echo "💡 Or run: pip3 install -r requirements.txt"
    exit 1
fi

# Check FFmpeg tools
echo "🎬 Checking FFmpeg tools..."
if command -v ffmpeg > /dev/null 2>&1; then
    echo "✅ ffmpeg is available: $(which ffmpeg)"
else
    echo "❌ ffmpeg is not installed"
    echo "💡 Install with: sudo apt install ffmpeg"
    exit 1
fi

if command -v ffprobe > /dev/null 2>&1; then
    echo "✅ ffprobe is available: $(which ffprobe)"
else
    echo "❌ ffprobe is not installed"
    echo "💡 Install with: sudo apt install ffmpeg"
    exit 1
fi

# Test media_update.py script
echo "📄 Testing media_update.py script..."
if python3 "$SCRIPT_DIR/media_update.py" --help > /dev/null 2>&1; then
    echo "✅ media_update.py script runs successfully"
else
    echo "❌ media_update.py script has errors"
    exit 1
fi

echo "🎉 All environment checks passed! Media processing should work correctly."
echo ""
echo "💡 To test media processing:"
echo "   python3 media_update.py --file /path/to/video.mkv --type both"
echo ""
echo "💡 To test Radarr integration:"
echo "   export Radarr_EventType=Download Radarr_MovieFile_Path=/path/to/video.mkv"
echo "   ./import.sh"