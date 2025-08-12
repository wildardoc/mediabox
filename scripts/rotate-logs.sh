#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Log rotation script for mediabox
# Manages media_update and import log files to prevent disk space issues
# 
# Retention policy:
# - Keep recent logs (0-14 days): Uncompressed for easy access
# - Keep older logs (14-90 days): Compressed to save space  
# - Purge ancient logs (90+ days): Deleted to prevent unlimited growth

LOG_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$LOG_DIR" || exit 1

echo "Starting log rotation process..."
echo "Log directory: $LOG_DIR"

# Counters
COMPRESSED=0
DELETED=0
TOTAL_SIZE_BEFORE=0
TOTAL_SIZE_AFTER=0

# Calculate total size before cleanup
if command -v du >/dev/null 2>&1; then
    TOTAL_SIZE_BEFORE=$(du -sb *_*.log *_*.log.gz 2>/dev/null | awk '{sum += $1} END {print sum+0}')
    echo "Total log size before cleanup: $(numfmt --to=iec $TOTAL_SIZE_BEFORE 2>/dev/null || echo "${TOTAL_SIZE_BEFORE} bytes")"
fi

# 1. Delete logs older than 90 days
echo "Deleting logs older than 90 days..."
find . -name "media_update_*.log" -type f -mtime +90 -delete 2>/dev/null && DELETED=$((DELETED + $(find . -name "media_update_*.log" -type f -mtime +90 2>/dev/null | wc -l)))
find . -name "import_*.log" -type f -mtime +90 -delete 2>/dev/null && DELETED=$((DELETED + $(find . -name "import_*.log" -type f -mtime +90 2>/dev/null | wc -l)))
find . -name "media_update_*.log.gz" -type f -mtime +90 -delete 2>/dev/null && DELETED=$((DELETED + $(find . -name "media_update_*.log.gz" -type f -mtime +90 2>/dev/null | wc -l)))
find . -name "import_*.log.gz" -type f -mtime +90 -delete 2>/dev/null && DELETED=$((DELETED + $(find . -name "import_*.log.gz" -type f -mtime +90 2>/dev/null | wc -l)))

# 2. Compress logs older than 14 days (but less than 90 days)
echo "Compressing logs older than 14 days..."
find . -name "media_update_*.log" -type f -mtime +14 -mtime -90 | while read -r file; do
    if [[ -f "$file" && ! -f "$file.gz" ]]; then
        echo "Compressing: $file"
        gzip "$file" 2>/dev/null && COMPRESSED=$((COMPRESSED + 1))
    fi
done

find . -name "import_*.log" -type f -mtime +14 -mtime -90 | while read -r file; do
    if [[ -f "$file" && ! -f "$file.gz" ]]; then
        echo "Compressing: $file"  
        gzip "$file" 2>/dev/null && COMPRESSED=$((COMPRESSED + 1))
    fi
done

# 3. Clean up any zero-byte logs (often created by failed runs)
echo "Removing zero-byte log files..."
find . -name "media_update_*.log" -type f -size 0 -delete 2>/dev/null
find . -name "import_*.log" -type f -size 0 -delete 2>/dev/null

# Calculate total size after cleanup
if command -v du >/dev/null 2>&1; then
    TOTAL_SIZE_AFTER=$(du -sb *_*.log *_*.log.gz 2>/dev/null | awk '{sum += $1} END {print sum+0}')
    echo "Total log size after cleanup: $(numfmt --to=iec $TOTAL_SIZE_AFTER 2>/dev/null || echo "${TOTAL_SIZE_AFTER} bytes")"
    
    if [[ $TOTAL_SIZE_BEFORE -gt 0 ]]; then
        SPACE_SAVED=$((TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER))
        echo "Space saved: $(numfmt --to=iec $SPACE_SAVED 2>/dev/null || echo "${SPACE_SAVED} bytes")"
    fi
fi

# Summary
echo "Log rotation completed:"
echo "  - Files compressed: $COMPRESSED"
echo "  - Files deleted: $DELETED"
echo "  - Current log files:"
ls -lh *_*.log *_*.log.gz 2>/dev/null | head -10

echo "Log rotation process finished."
