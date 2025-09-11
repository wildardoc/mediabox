#!/bin/bash

# Test script for the hybrid surround channel fix
# Tests both unknown layout (stream copy) and normal processing

echo "🧪 Testing Hybrid Surround Channel Fix"
echo "========================================"

cd /Storage/docker/mediabox/scripts

# Test 1: File with unknown channel layout (should use stream copy)
echo ""
echo "📁 Test 1: Lady And The Tramp II (unknown channel layout)"
echo "Expected: Stream copy for surround, re-encode for stereo"
python3 media_update.py --file "/Storage/media/movies/Lady And The Tramp II Scamp's Adventure (2001)/Lady And The Tramp II Scamp's Adventure (2001).mp4" --type video

# Test 2: One of the other problematic files from our scan
echo ""
echo "📁 Test 2: Celtic Woman Homecoming (unknown channel layout)"  
echo "Expected: Stream copy for surround, re-encode for stereo"
python3 media_update.py --file "/Storage/media/movies/Celtic Woman Homecoming - Live From Ireland (2018)/Celtic Woman Homecoming - Live From Ireland (2018) HDTV-720p.mp4" --type video

# Test 3: A file with good channel layout (if available)
echo ""
echo "📁 Test 3: Original MKV with good 5.1 layout"
echo "Expected: Re-encode both surround and stereo with layout preservation"
if [ -f "/Storage/media/movies/Superman III (1983)/Superman III (1983) WEBDL-2160p.mkv" ]; then
    python3 media_update.py --file "/Storage/media/movies/Superman III (1983)/Superman III (1983) WEBDL-2160p.mkv" --type video
else
    echo "⚠️  Original MKV file not available for testing"
fi

echo ""
echo "✅ Testing complete!"
echo ""
echo "🔍 Check the logs for:"
echo "   - 'stream copy to preserve quality' for unknown layouts"
echo "   - 'Re-encoding and preserving channel layout' for known layouts"
echo "   - No more 'Unsupported channel layout' errors"
echo ""
echo "📺 Verify in Plex that:"
echo "   - Files have both surround and stereo tracks"
echo "   - Surround sound works properly"
echo "   - No conversion failures"
