# Audio Channelmap Fix for Missing channel_layout Metadata

**Date**: November 13, 2025  
**Issue**: Files with 6-channel audio but missing `channel_layout` field fail processing  
**Git Commit**: 9dfa54d

## Problem

Files like "Luca (2021) WEBDL-2160p.mp4" have 6-channel surround audio but the `channel_layout` field is missing from ffprobe output (not "unknown", completely absent). This caused:

```
[out#0/mp4] Output with label 'fixed_surround' does not exist in any defined filter graph
Error opening output file
```

## Root Cause

1. **Detection**: Script only checked for `channel_layout == 'unknown'`, missed files where field is `None`
2. **Filter chaining**: When creating both original surround AND enhanced stereo:
   - channelmap creates `[fixed_surround]`
   - pan filter consumes `[fixed_surround]` to create stereo
   - `[fixed_surround]` no longer available for output mapping

## Solution

### 1. Enhanced Detection (Line ~1416)
```python
# Check if key exists, not just value
has_layout = 'channel_layout' in stream
channel_layout = stream.get('channel_layout', '') if has_layout else None

# Detect all three cases
if (channel_layout is None or channel_layout == 'unknown' or channel_layout == '') and channels == 6:
    needs_channelmap_fix = True
```

### 2. Proper Filter Chaining with asplit (Line ~1439)
```python
if should_create_stereo:
    # Split channelmap output into two branches
    channelmap_filter = f'[0:a:{audio_idx}]channelmap=0-FL|1-FR|2-FC|3-LFE|4-BL|5-BR:channel_layout=5.1,asplit=2[fixed_surround][for_stereo]'
else:
    channelmap_filter = f'[0:a:{audio_idx}]channelmap=0-FL|1-FR|2-FC|3-LFE|4-BL|5-BR:channel_layout=5.1[fixed_surround]'
```

### 3. Correct Syntax (Line ~1435)
Changed: `:5.1[fixed_surround]`  
To: `:channel_layout=5.1[fixed_surround]`

### 4. Updated Source Selection (Line ~1479)
```python
if needs_channelmap_fix and should_create_stereo:
    surround_source_for_stereo = '[for_stereo]'  # Use split branch
elif needs_channelmap_fix:
    surround_source_for_stereo = '[fixed_surround]'
else:
    surround_source_for_stereo = f'[0:a:{audio_idx}]'
```

## Result

**Before**: Failed immediately with filter graph error  
**After**: Successfully processes, creating both 5.1 surround and enhanced stereo with boosted dialogue

## Example Command Generated

```bash
ffmpeg -i input.mp4 \
  -filter_complex "[0:a:0]channelmap=0-FL|1-FR|2-FC|3-LFE|4-BL|5-BR:channel_layout=5.1,asplit=2[fixed_surround][for_stereo]; \
                   [for_stereo]pan=stereo|c0=0.35*c0+0.5*c2+0.25*c4|c1=0.35*c1+0.5*c2+0.25*c5,acompressor=...[aout]" \
  -map "[fixed_surround]" \
  -map "[aout]" \
  ...
```

## Files Affected

- Luca (2021) WEBDL-2160p.mp4 - **VERIFIED WORKING**
- Any 6-channel file where ffprobe doesn't return `channel_layout` field
- Common in: Disney+, Apple TV+, some Amazon Prime Video downloads

## DO NOT REVERT

This fix addresses a fundamental issue with how ffprobe reports channel layouts. Without it:
- Many modern streaming service downloads will fail
- The `asplit` is required when both preserving AND transforming audio
- The `None` check is required because missing field ≠ "unknown" value

## Testing

To test if a file needs this fix:
```bash
ffprobe -v quiet -print_format json -show_streams "file.mp4" | \
  python3 -c "import json, sys; s = [s for s in json.load(sys.stdin)['streams'] if s.get('channels') == 6][0]; \
  print('Has channel_layout:', 'channel_layout' in s)"
```

If output is `Has channel_layout: False`, this fix is required.
