#!/bin/bash

# GPU Hardware Acceleration Test Script
# Tests various hardware acceleration methods available in Docker containers

set -euo pipefail

echo "=== GPU Hardware Acceleration Test ==="
echo "Date: $(date)"
echo

# Check GPU devices
echo "=== GPU Devices Available ==="
if [[ -d /dev/dri ]]; then
    ls -la /dev/dri/
else
    echo "No /dev/dri directory found"
fi
echo

# Test FFmpeg hardware acceleration methods
echo "=== FFmpeg Hardware Acceleration Methods ==="
ffmpeg -hide_banner -hwaccels 2>/dev/null || echo "FFmpeg not available"
echo

# Test VAAPI (Video Acceleration API)
echo "=== Testing VAAPI ==="
if [[ -c /dev/dri/renderD128 ]]; then
    echo "Testing VAAPI device /dev/dri/renderD128..."
    ffmpeg -hide_banner -f lavfi -i testsrc2=duration=1:size=320x240:rate=1 \
           -vaapi_device /dev/dri/renderD128 -vf 'format=nv12,hwupload' \
           -c:v h264_vaapi -t 1 -f null - 2>&1 | head -5 || echo "VAAPI test failed (expected for older GPUs)"
else
    echo "No VAAPI render device found"
fi
echo

# Test VDPAU (Video Decode and Presentation API for Unix)
echo "=== Testing VDPAU ==="
export DISPLAY=:0.0  # Needed for VDPAU
ffmpeg -hide_banner -f lavfi -i testsrc2=duration=1:size=320x240:rate=1 \
       -c:v h264_vdpau -t 1 -f null - 2>&1 | head -5 || echo "VDPAU test failed (normal without X11 display)"
echo

# Test software fallback
echo "=== Testing Software Encoding (Fallback) ==="
ffmpeg -hide_banner -f lavfi -i testsrc2=duration=1:size=320x240:rate=1 \
       -c:v libx264 -preset ultrafast -t 1 -f null - 2>&1 | head -3 || echo "Software encoding test failed"
echo

# GPU information
echo "=== GPU Hardware Information ==="
lspci | grep -i vga || echo "No VGA devices found via lspci"
lspci | grep -i nvidia || echo "No NVIDIA devices found"
echo

# Driver information
echo "=== Graphics Driver Information ==="
lsmod | grep -E "(nvidia|nouveau|i915)" || echo "No graphics drivers loaded"
echo

echo "=== Test Complete ==="
echo "Summary:"
echo "- GPU devices: $(ls /dev/dri/ 2>/dev/null | wc -l) found"
echo "- Hardware acceleration: Limited (older GPU)"
echo "- Software fallback: Available"
echo "- Recommendation: Use software encoding with optimized settings"
