#!/bin/bash

# Analyze Missing Audio Files
# Checks all files flagged as having no audio and generates a detailed report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${1:-$(ls -t "$SCRIPT_DIR"/media_update_*.log | head -1)}"
OUTPUT_REPORT="$SCRIPT_DIR/missing_audio_report_$(date +%Y%m%d_%H%M%S).txt"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file not found: $LOG_FILE"
    exit 1
fi

echo "Analyzing missing audio files from: $(basename "$LOG_FILE")"
echo "Output report: $OUTPUT_REPORT"
echo ""

# Extract unique files with missing audio (properly handle spaces in filenames)
mapfile -t FILES < <(grep "Skipping.*No English or unlabeled audio" "$LOG_FILE" | \
                     sed 's/.*Skipping //' | sed 's/: No English.*//' | sort -u)

echo "Found ${#FILES[@]} files with missing/non-English audio"
echo ""

# Create report header
cat > "$OUTPUT_REPORT" << EOF
Missing Audio Analysis Report
Generated: $(date)
Log file: $(basename "$LOG_FILE")
Total files analyzed: ${#FILES[@]}

================================================================================
SUMMARY
================================================================================

EOF

# Analyze each file
declare -A audio_status
audio_status["NO_AUDIO"]=0
audio_status["NON_ENGLISH"]=0
audio_status["FILE_NOT_FOUND"]=0

echo "Analyzing files (this may take a moment)..."

for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        ((audio_status["FILE_NOT_FOUND"]++))
        echo "FILE NOT FOUND: $file" >> "$OUTPUT_REPORT"
        continue
    fi
    
    # Check for any audio streams
    audio_count=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l)
    
    if [[ $audio_count -eq 0 ]]; then
        ((audio_status["NO_AUDIO"]++))
        echo "NO AUDIO: $file" >> "$OUTPUT_REPORT"
        
        # Get file size to check if it's corrupted
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        size_mb=$((size / 1024 / 1024))
        echo "  Size: ${size_mb}MB" >> "$OUTPUT_REPORT"
    else
        # Has audio but non-English or unrecognized tags
        ((audio_status["NON_ENGLISH"]++))
        echo "NON-ENGLISH AUDIO: $file" >> "$OUTPUT_REPORT"
        
        # Get audio stream details
        ffprobe -v quiet -select_streams a -show_entries stream=index,codec_name,channels:stream_tags=language,title -of default=noprint_wrappers=1 "$file" 2>/dev/null | grep -E "^(index|codec_name|channels|TAG:language|TAG:title)=" | sed 's/^/  /' >> "$OUTPUT_REPORT"
    fi
    echo "" >> "$OUTPUT_REPORT"
done

# Update summary
cat >> "$OUTPUT_REPORT" << EOF

================================================================================
STATISTICS
================================================================================

Files with NO audio streams:     ${audio_status["NO_AUDIO"]}
Files with non-English audio:    ${audio_status["NON_ENGLISH"]}
Files not found:                 ${audio_status["FILE_NOT_FOUND"]}

================================================================================
RECOMMENDATIONS
================================================================================

EOF

if [[ ${audio_status["NO_AUDIO"]} -gt 0 ]]; then
    cat >> "$OUTPUT_REPORT" << EOF
FILES WITH NO AUDIO (${audio_status["NO_AUDIO"]} files):
These files are corrupted and need to be re-downloaded/re-ripped.
They were likely damaged during a previous conversion attempt.

To generate a list for re-download:
grep "^NO AUDIO:" "$OUTPUT_REPORT" | sed 's/NO AUDIO: //' > files_to_redownload.txt

EOF
fi

if [[ ${audio_status["NON_ENGLISH"]} -gt 0 ]]; then
    cat >> "$OUTPUT_REPORT" << EOF
FILES WITH NON-ENGLISH AUDIO (${audio_status["NON_ENGLISH"]} files):
These files have audio but it's tagged with a non-English language code.
Options:
1. Re-download with English audio
2. Add a flag to force-process non-English audio
3. Manually retag the audio streams as English if they are actually English

EOF
fi

# Print summary to console
echo ""
echo "Analysis complete!"
echo "=================="
echo "Files with NO audio:      ${audio_status["NO_AUDIO"]}"
echo "Files with non-English:   ${audio_status["NON_ENGLISH"]}"
echo "Files not found:          ${audio_status["FILE_NOT_FOUND"]}"
echo ""
echo "Full report: $OUTPUT_REPORT"

# Create redownload list if there are files with no audio
if [[ ${audio_status["NO_AUDIO"]} -gt 0 ]]; then
    REDOWNLOAD_LIST="$SCRIPT_DIR/files_to_redownload_$(date +%Y%m%d_%H%M%S).txt"
    grep "^NO AUDIO:" "$OUTPUT_REPORT" | sed 's/NO AUDIO: //' > "$REDOWNLOAD_LIST"
    echo ""
    echo "🚨 CRITICAL: ${audio_status["NO_AUDIO"]} files have NO AUDIO and need re-download"
    echo "Re-download list: $REDOWNLOAD_LIST"
fi

echo ""
echo "✅ Report generated: $OUTPUT_REPORT"
