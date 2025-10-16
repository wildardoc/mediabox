# HDR to SDR Tone Mapping

## Overview

Mediabox now automatically detects and converts HDR (High Dynamic Range) video content to SDR (Standard Dynamic Range) during media processing. This prevents the "pink/magenta tint" issue that occurs when HDR content is played on SDR displays or transcoded without proper color space conversion.

## Problem Statement

### The Pink Tint Issue

When HDR10 video (using **smpte2084** PQ transfer and **BT.2020** color space) is transcoded or played on an SDR display (expecting **BT.709** color space), the color values are misinterpreted, resulting in:

- Pink/magenta color tint
- Washed out or incorrect colors
- Poor viewing experience

**Example:**
- **Original**: Cross S01E01 (3840x2160, HDR10, smpte2084, bt2020nc, 10-bit)
- **Plex Optimized**: 1920x1080, SDR, bt709, 8-bit - **works correctly**
- **Without tone mapping**: Pink tint on bedroom TV

## Solution

### Automatic HDR Detection

The `detect_hdr_video()` function identifies:

1. **HDR10** - PQ (smpte2084) transfer function
2. **HLG** (Hybrid Log-Gamma) - arib-std-b67 transfer
3. **Dolby Vision** - Side data markers
4. **BT.2020 HDR** - 10/12-bit with BT.2020 primaries

**Detection criteria:**
- Color transfer characteristic (smpte2084, arib-std-b67)
- Color primaries (bt2020)
- Bit depth (10-bit or 12-bit)
- Pixel format (yuv420p10le, etc.)

### Tone Mapping Filter Chain

When HDR content is detected, the following FFmpeg filter chain is applied:

```bash
zscale=t=linear:npl=100,           # 1. Convert to linear light
format=gbrpf32le,                  # 2. Use 32-bit float for precision
zscale=p=bt709,                    # 3. Convert primaries to BT.709
tonemap=tonemap=hable:desat=0,     # 4. Apply Hable (filmic) tone mapping
zscale=t=bt709:m=bt709:r=tv,       # 5. Convert transfer/matrix to BT.709
format=yuv420p,                    # 6. Convert to 8-bit YUV 4:2:0
scale=w=-2:h=1080                  # 7. Optional: Scale to 1080p
```

**Why Hable tone mapping?**
- Natural, filmic color reproduction
- Preserves detail in highlights and shadows
- Industry-proven algorithm (used in gaming/film)

### Software Encoding Requirement

**CRITICAL**: HDR tone mapping uses the **zscale** filter, which is **NOT compatible with VAAPI hardware acceleration**. When HDR content is detected:

- Forces `libx264` (software encoding)
- Uses `medium` preset for quality/speed balance
- VAAPI paths are bypassed

**Performance Impact:**
- Slower than VAAPI (expected)
- Typical: 1-3x real-time on modern CPUs
- Worth the tradeoff for correct color reproduction

## Usage

### Automatic Processing (Recommended)

HDR detection and tone mapping are **fully automatic** when using:

1. **Webhook integration** (`import.sh`)
   - Sonarr/Radarr/Lidarr trigger automatic conversion
   - HDR content detected and tone mapped on import

2. **Manual processing** (`media_update.py`)
   ```bash
   cd scripts
   python3 media_update.py --dir "/path/to/media" --type video
   python3 media_update.py --file "/path/to/file.mp4" --type both
   ```

3. **Smart bulk converter** (`smart-bulk-convert.sh`)
   ```bash
   ./smart-bulk-convert.sh /Storage/media/movies /Storage/media/tv
   ```

### Example Log Output

```
🎨 HDR content detected: HDR10
   Color: bt2020, Transfer: smpte2084, 10-bit
✅ HDR→SDR tone mapping will be applied
Using software encoding for HDR tone mapping
```

## Testing

### Verify HDR Detection

```bash
cd /Storage/docker/mediabox/scripts
/Storage/docker/mediabox/scripts/.venv/bin/python3 -c "
import ffmpeg
import media_update

probe = ffmpeg.probe('/path/to/hdr/video.mp4')
hdr_info = media_update.detect_hdr_video(probe)

if hdr_info['is_hdr']:
    print(f'HDR Type: {hdr_info[\"hdr_type\"]}')
    print(f'Transfer: {hdr_info[\"color_transfer\"]}')
    print(f'Primaries: {hdr_info[\"color_primaries\"]}')
    print(f'Bit Depth: {hdr_info[\"bit_depth\"]}-bit')
"
```

### Test Conversion

```bash
# Test on a single HDR file
cd scripts
python3 media_update.py --file "/Storage/media/tv/Cross/Season 01/Cross - S01E01 - Hero Complex WEBDL-2160p.mp4" --type video

# Check output has proper SDR color space
ffprobe "output_file.mp4" 2>&1 | grep -E "color_transfer|color_primaries|color_space"
# Expected: bt709, bt709, bt709
```

## Technical Details

### HDR Formats Supported

| Format | Transfer | Primaries | Detection |
|--------|----------|-----------|-----------|
| HDR10 | smpte2084 | bt2020 | ✅ Full |
| HDR10+ | smpte2084 | bt2020 | ✅ Detected as HDR10 |
| HLG | arib-std-b67 | bt2020 | ✅ Full |
| Dolby Vision | varies | bt2020 | ✅ Side data detection |
| BT.2020 10-bit | varies | bt2020 | ✅ Primaries + bit depth |

### Color Space Conversion

**HDR (Input):**
- Transfer: smpte2084 (PQ), arib-std-b67 (HLG)
- Primaries: bt2020
- Matrix: bt2020nc
- Bit Depth: 10-bit or 12-bit

**SDR (Output):**
- Transfer: bt709
- Primaries: bt709
- Matrix: bt709
- Bit Depth: 8-bit

### Filter Chain Explanation

1. **Linear Light Conversion** (`zscale=t=linear:npl=100`)
   - Converts from PQ/HLG to linear light representation
   - `npl=100` sets nominal peak luminance to 100 nits

2. **32-bit Float Format** (`format=gbrpf32le`)
   - Uses floating point for precision during tone mapping
   - Prevents banding and color shifts

3. **Primaries Conversion** (`zscale=p=bt709`)
   - Converts color primaries from BT.2020 to BT.709
   - Wide color gamut → Standard color gamut

4. **Tone Mapping** (`tonemap=tonemap=hable:desat=0`)
   - Compresses HDR luminance range (0-10000 nits) to SDR (0-100 nits)
   - Hable algorithm preserves color saturation
   - `desat=0` prevents desaturation

5. **Transfer/Matrix Conversion** (`zscale=t=bt709:m=bt709:r=tv`)
   - Sets transfer characteristic to BT.709
   - Sets color matrix to BT.709
   - `r=tv` uses TV/limited range (16-235)

6. **8-bit YUV** (`format=yuv420p`)
   - Converts to standard 8-bit 4:2:0 chroma subsampling
   - Compatible with all players

7. **Optional Scaling** (`scale=w=-2:h=1080`)
   - Downscales to 1080p if needed
   - `-2` ensures even width for codec compatibility

## Performance

### Encoding Speed

| Scenario | Speed | Notes |
|----------|-------|-------|
| VAAPI (non-HDR) | 5-10x real-time | Hardware accelerated |
| Software (non-HDR) | 2-4x real-time | libx264 medium preset |
| **HDR Tone Mapping** | 1-3x real-time | zscale + libx264 |

### Resource Usage

- **CPU**: High during HDR conversion (expected)
- **Memory**: Moderate (32-bit float processing)
- **GPU**: Not used (zscale is CPU-only)

**Optimization tip:** Let smart-bulk-convert.sh manage parallel jobs to balance system load.

## Troubleshooting

### Issue: Pink/Magenta Tint Still Visible

**Causes:**
1. File not processed yet (check conversion logs)
2. Using original file instead of converted version
3. Player incorrectly interpreting HDR metadata

**Solutions:**
```bash
# Check if file was processed
grep "HDR content detected" scripts/media_update_*.log

# Verify output color space
ffprobe output.mp4 2>&1 | grep color_transfer
# Should show: color_transfer=bt709

# Force reprocessing
python3 media_update.py --file "/path/to/file.mp4" --type video
```

### Issue: Conversion Too Slow

**Expected behavior** - HDR tone mapping is CPU-intensive and slower than hardware encoding.

**Workarounds:**
1. Use smart-bulk-convert.sh for intelligent resource management
2. Process during off-hours
3. Increase parallel jobs (if CPU allows): Edit `scripts/smart_convert_config.json`

### Issue: HDR Not Detected

**Check detection:**
```bash
cd scripts
/Storage/docker/mediabox/scripts/.venv/bin/python3 -c "
import ffmpeg, media_update
probe = ffmpeg.probe('/path/to/file.mp4')
hdr = media_update.detect_hdr_video(probe)
print(hdr)
"
```

**If `is_hdr: false` but file is HDR:**
- Check color_transfer value in probe output
- Update detection logic if new HDR format

## Integration with Plex

### How Plex Optimized Versions Work

Plex's "Optimize" feature creates SDR versions using similar tone mapping:
- Detects HDR content
- Applies tone mapping during optimization
- Creates 1080p SDR version

**Mediabox approach:**
- Same concept, but during import/webhook processing
- Automatic for all new content
- Uses Hable tone mapping (industry-proven algorithm)

### Recommended Plex Settings

1. **Disable automatic optimization** - Mediabox handles it
2. **Use Direct Play** for processed SDR files
3. **Keep HDR originals** in separate directory (optional)

## Future Enhancements

Potential improvements:

1. **Preserve HDR originals** - Keep both HDR and SDR versions
2. **HDR10+ dynamic metadata** - Enhanced tone mapping with scene-by-scene data
3. **Hardware acceleration** - If/when zscale supports VAAPI
4. **Configurable algorithms** - Reinhard, Mobius, Linear options
5. **Metadata database** - Track which files were tone mapped

## References

- [FFmpeg zscale filter](https://ffmpeg.org/ffmpeg-filters.html#zscale-1)
- [ITU-R BT.2100 (HDR standard)](https://www.itu.int/rec/R-REC-BT.2100)
- [SMPTE ST 2084 (PQ transfer)](https://ieeexplore.ieee.org/document/7291707)
- [HLG (Hybrid Log-Gamma)](https://www.bbc.co.uk/rd/projects/high-dynamic-range/hlg)

## Summary

✅ **Automatic HDR detection** for HDR10, HLG, Dolby Vision  
✅ **Professional tone mapping** using Hable algorithm  
✅ **Prevents pink tint** on SDR displays  
✅ **Full integration** with webhook and manual processing  
✅ **Production-ready** with comprehensive logging

**No configuration required** - HDR content is automatically detected and converted to SDR with proper color space handling.
