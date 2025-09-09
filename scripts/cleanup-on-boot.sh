#!/bin/bash

# Cleanup script for system boot - handles post-power-outage recovery
# Cleans up orphaned processes, logs, and prepares for smart converter restart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/cleanup_boot_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log "INFO" "Starting post-boot cleanup for mediabox system"

# 1. Clean up any orphaned media_update.py processes
log "INFO" "Checking for orphaned media conversion processes..."
orphaned_pids=$(pgrep -f "media_update\.py" || true)
if [[ -n "$orphaned_pids" ]]; then
    log "WARN" "Found orphaned conversion processes, terminating..."
    echo "$orphaned_pids" | xargs -r kill -TERM || true
    sleep 5
    # Force kill if still running
    remaining_pids=$(pgrep -f "media_update\.py" || true)
    if [[ -n "$remaining_pids" ]]; then
        log "WARN" "Force killing remaining processes..."
        echo "$remaining_pids" | xargs -r kill -KILL || true
    fi
    log "INFO" "Orphaned processes cleaned up"
else
    log "INFO" "No orphaned processes found"
fi

# 2. Clean up old log files (keep last 7 days)
log "INFO" "Cleaning up old log files..."
find "$SCRIPT_DIR" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
find "$SCRIPT_DIR" -name "*.log.gz" -type f -mtime +30 -delete 2>/dev/null || true

# 3. Clean up old conversion statistics
find "$SCRIPT_DIR" -name "conversion_stats_*.json" -type f -mtime +7 -delete 2>/dev/null || true

# 4. Remove any temporary conversion files
log "INFO" "Cleaning up temporary files..."
find /Storage/media -name "*.tmp.mp4" -type f -mtime +1 -delete 2>/dev/null || true
find /Storage/media -name "*.tmp.mkv" -type f -mtime +1 -delete 2>/dev/null || true

# 5. Check Docker container status
log "INFO" "Checking Docker container health..."
cd "$SCRIPT_DIR/.."
docker-compose ps --format "table {{.Name}}\t{{.Status}}" | tee -a "$LOG_FILE"

# 6. Verify media directories are accessible
log "INFO" "Verifying media directories..."
for dir in "/Storage/media/movies" "/Storage/media/tv"; do
    if [[ -d "$dir" && -r "$dir" ]]; then
        file_count=$(find "$dir" -name "*.mkv" -o -name "*.mp4" | wc -l)
        log "INFO" "Directory $dir accessible with $file_count video files"
    else
        log "ERROR" "Directory $dir not accessible!"
    fi
done

# 7. Wait for system to stabilize
log "INFO" "Waiting for system to stabilize..."
sleep 30

log "INFO" "Post-boot cleanup completed successfully"
log "INFO" "System ready for smart bulk converter startup"

# Return success
exit 0
