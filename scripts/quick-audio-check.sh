#!/bin/bash

# Quick audio check for files flagged as missing audio

LOG_FILE="${1:-$(ls -t /home/robert/mediabox/scripts/media_update_*.log | head -1)}"
OUTPUT_DIR="/home/robert/mediabox/scripts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

NO_AUDIO_LIST="$OUTPUT_DIR/files_no_audio_$TIMESTAMP.txt"
NON_ENGLISH_LIST="$OUTPUT_DIR/files_non_english_$TIMESTAMP.txt"
NOT_FOUND_LIST="$OUTPUT_DIR/files_not_found_$TIMESTAMP.txt"

echo "Analyzing files from: $(basename "$LOG_FILE")"
echo ""

# Clear output files
> "$NO_AUDIO_LIST"
> "$NON_ENGLISH_LIST"
> "$NOT_FOUND_LIST"

count=0
no_audio=0
non_english=0
not_found=0

# Process each file
while IFS= read -r file; do
    ((count++))
    echo -ne "\rChecking file $count..."
    
    if [[ ! -f "$file" ]]; then
        echo "$file" >> "$NOT_FOUND_LIST"
        ((not_found++))
        continue
    fi
    
    # Quick audio stream count
    audio_count=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l)
    
    if [[ $audio_count -eq 0 ]]; then
        echo "$file" >> "$NO_AUDIO_LIST"
        ((no_audio++))
    else
        echo "$file" >> "$NON_ENGLISH_LIST"
        ((non_english++))
    fi
    
done < <(grep "Skipping.*No English or unlabeled audio" "$LOG_FILE" | sed 's/.*Skipping //' | sed 's/: No English.*//' | sort -u)

echo -e "\r                                      "
echo ""
echo "=================="
echo "ANALYSIS COMPLETE"
echo "=================="
echo "Files with NO audio:      $no_audio"
echo "Files with non-English:   $non_english"
echo "Files not found:          $not_found"
echo ""

if [[ $no_audio -gt 0 ]]; then
    echo "🚨 Files needing re-download (NO AUDIO): $NO_AUDIO_LIST"
fi

if [[ $non_english -gt 0 ]]; then
    echo "📋 Files with non-English audio: $NON_ENGLISH_LIST"
fi

if [[ $not_found -gt 0 ]]; then
    echo "❓ Files not found: $NOT_FOUND_LIST"
fi
