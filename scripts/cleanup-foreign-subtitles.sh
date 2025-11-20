#!/bin/bash

# Cleanup Foreign Language Subtitle Files
# Removes external subtitle files for foreign languages while preserving English subtitles
#
# Usage: ./cleanup-foreign-subtitles.sh <directory> [--dry-run]

if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory> [--dry-run]"
    exit 1
fi

SEARCH_DIR="$1"
DRY_RUN=false

if [ "$2" = "--dry-run" ]; then
    DRY_RUN=true
    echo "🔍 DRY RUN MODE - No files will be deleted"
    echo ""
fi

if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory not found: $SEARCH_DIR"
    exit 1
fi

# Foreign language codes (ISO 639-2/3) - excluding English
LANGS="fre|fra|spa|por|ger|deu|ita|jpn|kor|chi|zho|rus|ara|hin|ben|pol|dut|nld|swe|nor|dan|fin|gre|ell|tur|heb|tha|vie|ind|msa|tam|tel|mar|kan"

echo "Searching for foreign subtitle files in: $SEARCH_DIR"
echo ""

if [ "$DRY_RUN" = true ]; then
    # Dry run - show what would be deleted
    find "$SEARCH_DIR" -type f -regextype posix-extended \
        -regex ".*\.($LANGS)\.(sup|srt|ass|ssa|vtt|sub|idx)$" \
        -exec echo "[DRY RUN] Would delete: {}" \;
else
    # Actually delete the files
    find "$SEARCH_DIR" -type f -regextype posix-extended \
        -regex ".*\.($LANGS)\.(sup|srt|ass|ssa|vtt|sub|idx)$" \
        -exec echo "Deleting: {}" \; \
        -delete
fi

echo ""
echo "Done!"
