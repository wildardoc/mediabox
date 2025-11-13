#!/bin/bash

# Comprehensive Media Library Audio Scan
# Checks ALL video files in the media library for missing/corrupted audio

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Output files
NO_AUDIO_LIST="$SCRIPT_DIR/library_no_audio_$TIMESTAMP.txt"
REPORT="$SCRIPT_DIR/library_audio_scan_$TIMESTAMP.txt"

# Media library paths (adjust if needed)
MEDIA_PATHS=(
    "/FileServer/media/tv"
    "/FileServer/media/movies"
)

# Video extensions to check
VIDEO_EXTS=(-iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.m4v")

echo "========================================="
echo "Media Library Audio Integrity Scan"
echo "========================================="
echo "Started: $(date)"
echo ""

# Clear output files
> "$NO_AUDIO_LIST"
> "$REPORT"

# Write report header
cat >> "$REPORT" << EOF
Media Library Audio Integrity Scan
Generated: $(date)
Scan paths: ${MEDIA_PATHS[*]}

================================================================================
EOF

total_files=0
no_audio_count=0
has_audio_count=0
error_count=0

echo "Building file list..."
echo ""

# Build list of all video files
temp_file_list=$(mktemp)
for media_path in "${MEDIA_PATHS[@]}"; do
    if [[ -d "$media_path" ]]; then
        echo "Scanning: $media_path"
        find "$media_path" -type f \( "${VIDEO_EXTS[@]}" \) >> "$temp_file_list"
    else
        echo "Warning: Path not found: $media_path"
    fi
done

total_files=$(wc -l < "$temp_file_list")
echo ""
echo "Found $total_files video files to check"
echo ""
echo "Analyzing audio streams (this will take a while)..."
echo ""

current=0
last_percent=-1

while IFS= read -r file; do
    ((current++))
    
    # Calculate progress percentage
    percent=$((current * 100 / total_files))
    
    # Only update display every 1%
    if [[ $percent -ne $last_percent ]]; then
        echo -ne "\rProgress: $percent% ($current/$total_files files) | No audio: $no_audio_count | Errors: $error_count"
        last_percent=$percent
    fi
    
    # Check for audio streams
    if ! audio_count=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l); then
        # ffprobe error
        ((error_count++))
        echo "ERROR: $file" >> "$REPORT"
        audio_count=0
    fi
    
    if [[ $audio_count -eq 0 ]]; then
        # No audio streams
        ((no_audio_count++))
        echo "$file" >> "$NO_AUDIO_LIST"
        echo "NO AUDIO: $file" >> "$REPORT"
        
        # Get file size for corruption analysis
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        size_mb=$((size / 1024 / 1024))
        echo "  Size: ${size_mb}MB" >> "$REPORT"
    else
        # Has audio
        ((has_audio_count++))
    fi
    
done < "$temp_file_list"

# Clean up
rm -f "$temp_file_list"

echo -e "\r                                                                                      "
echo ""
echo "========================================="
echo "SCAN COMPLETE"
echo "========================================="
echo "Total files scanned:      $total_files"
echo "Files with audio:         $has_audio_count"
echo "Files with NO audio:      $no_audio_count"
echo "Files with errors:        $error_count"
echo ""

# Write summary to report
cat >> "$REPORT" << EOF

================================================================================
SUMMARY
================================================================================

Total video files scanned:    $total_files
Files with audio:             $has_audio_count
Files with NO audio:          $no_audio_count
Files with probe errors:      $error_count

================================================================================
RECOMMENDATIONS
================================================================================

EOF

if [[ $no_audio_count -gt 0 ]]; then
    echo "🚨 CRITICAL: $no_audio_count files have NO AUDIO streams"
    echo ""
    echo "Files needing attention: $NO_AUDIO_LIST"
    echo "Full report: $REPORT"
    
    cat >> "$REPORT" << EOF
FILES WITH NO AUDIO ($no_audio_count files):
These files are corrupted and need to be re-downloaded or re-ripped.
The complete list has been saved to: $NO_AUDIO_LIST

To delete these files (USE WITH CAUTION):
    while IFS= read -r file; do rm -v "\$file"; done < "$NO_AUDIO_LIST"

To trigger Sonarr/Radarr re-download:
    Delete the files, then use "Unmonitor and Delete" in Sonarr/Radarr,
    then re-add or manually search for the episodes/movies.

EOF
else
    echo "✅ All files have audio streams - library is healthy!"
    cat >> "$REPORT" << EOF
All video files have audio streams. No corrupted files detected.
EOF
fi

if [[ $error_count -gt 0 ]]; then
    echo ""
    echo "⚠️  $error_count files had probe errors - check report for details"
    cat >> "$REPORT" << EOF

FILES WITH PROBE ERRORS ($error_count files):
These files may be corrupted or have unusual formats that ffprobe cannot read.
Review the ERROR entries above for details.

EOF
fi

echo ""
echo "Full report saved to: $REPORT"
echo ""
echo "Finished: $(date)"
