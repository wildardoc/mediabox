#!/bin/bash
set -euo pipefail

# Parallel Bulk Media Conversion Script
# Uses GNU parallel for faster processing of large libraries

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables
if [[ -f "../.env" ]]; then
    source "../.env"
else
    echo "❌ .env file not found"
    exit 1
fi

# Configuration
VENV_PYTHON="./.venv/bin/python"
MEDIA_UPDATE_SCRIPT="./media_update.py"
LOG_DIR="./parallel-conversion-logs"
MAX_JOBS=4  # Adjust based on your CPU cores and disk I/O capacity

# Create log directory
mkdir -p "$LOG_DIR"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/parallel-conversion.log"
}

# Function to process a single file (used by parallel)
process_single_file() {
    local file="$1"
    local type="$2"
    local log_file="$LOG_DIR/file-$(basename "$file" .mkv).log"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $(basename "$file")" >> "$log_file"
    
    # Check if MP4 already exists and is valid
    local base_name="${file%.*}"
    local mp4_file="${base_name}.mp4"
    
    if [[ -f "$mp4_file" ]]; then
        if ffprobe -v quiet -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$mp4_file" >/dev/null 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skipped: MP4 exists and valid" >> "$log_file"
            return 0
        fi
    fi
    
    # Process the file
    local start_time=$(date +%s)
    if "$VENV_PYTHON" "$MEDIA_UPDATE_SCRIPT" --file "$file" --type "$type" >> "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed in ${duration}s: $(basename "$file")" >> "$log_file"
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $(basename "$file")" >> "$log_file"
        return 1
    fi
}

# Export function for parallel
export -f process_single_file
export VENV_PYTHON MEDIA_UPDATE_SCRIPT LOG_DIR

# Function to run parallel conversion
run_parallel_conversion() {
    local dir="$1"
    local type="$2"
    local description="$3"
    
    log_message "🚀 Starting parallel $description conversion (${MAX_JOBS} jobs)"
    log_message "📂 Directory: $dir"
    
    # Check if parallel is available
    if ! command -v parallel >/dev/null 2>&1; then
        log_message "❌ GNU parallel not found. Installing..."
        sudo apt update && sudo apt install -y parallel
    fi
    
    # Create file list
    local file_list="$LOG_DIR/${description,,}-files.txt"
    find "$dir" -type f -name "*.mkv" > "$file_list"
    
    local total_files=$(wc -l < "$file_list")
    log_message "📊 Found $total_files MKV files to process with $MAX_JOBS parallel jobs"
    
    if [[ $total_files -eq 0 ]]; then
        log_message "✅ No MKV files found in $description"
        return 0
    fi
    
    local start_time=$(date +%s)
    
    # Run parallel processing with progress bar
    log_message "⚙️  Starting parallel processing..."
    parallel --progress --jobs "$MAX_JOBS" process_single_file {} "$type" :::: "$file_list"
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local hours=$((total_duration / 3600))
    local minutes=$(((total_duration % 3600) / 60))
    
    # Count results
    local completed=$(find "$LOG_DIR" -name "file-*.log" -exec grep -l "Completed in" {} \; | wc -l)
    local skipped=$(find "$LOG_DIR" -name "file-*.log" -exec grep -l "Skipped:" {} \; | wc -l)
    local failed=$(find "$LOG_DIR" -name "file-*.log" -exec grep -l "Failed:" {} \; | wc -l)
    
    log_message "🎉 Parallel $description conversion completed!"
    log_message "📊 Results: $completed completed, $skipped skipped, $failed failed"
    log_message "⏱️  Total time: ${hours}h ${minutes}m"
    log_message "📈 Average: $((total_duration / MAX_JOBS / 60)) minutes per parallel job"
}

# Function to check for active processes
check_active_processes() {
    local ffmpeg_count=$(pgrep -f ffmpeg | wc -l)
    local media_update_count=$(pgrep -f media_update.py | wc -l)
    local import_count=$(pgrep -f import.sh | wc -l)
    
    if [[ $ffmpeg_count -gt 0 || $media_update_count -gt 0 || $import_count -gt 0 ]]; then
        log_message "⚠️  Active media processes detected:"
        [[ $ffmpeg_count -gt 0 ]] && log_message "   - $ffmpeg_count ffmpeg process(es)"
        [[ $media_update_count -gt 0 ]] && log_message "   - $media_update_count media_update.py process(es)"
        [[ $import_count -gt 0 ]] && log_message "   - $import_count import.sh process(es)"
        log_message "❌ Aborting to avoid interference with active conversions/imports"
        log_message "💡 Wait for processes to complete, then run: ./prepare-bulk-conversion.sh"
        exit 1
    fi
    log_message "✅ No conflicting processes detected"
}

# Main execution
main() {
    log_message "🚀 Starting parallel bulk media conversion"
    log_message "💻 Using $MAX_JOBS parallel jobs"
    
    # Safety check for active processes
    check_active_processes
    
    # Check prerequisites
    if [[ ! -x "$VENV_PYTHON" ]]; then
        log_message "❌ Virtual environment Python not found: $VENV_PYTHON"
        exit 1
    fi
    
    case "${1:-}" in
        "movies")
            run_parallel_conversion "$MOVIEDIR" "both" "Movie"
            ;;
        "tv")
            run_parallel_conversion "$TVDIR" "video" "TV"
            ;;
        "all")
            log_message "🎯 Processing both libraries with parallel jobs"
            run_parallel_conversion "$MOVIEDIR" "both" "Movie"
            run_parallel_conversion "$TVDIR" "video" "TV"
            ;;
        *)
            echo "Parallel Bulk Media Conversion"
            echo "Usage: $0 [movies|tv|all]"
            echo ""
            echo "This script uses GNU parallel for faster processing:"
            echo "  movies  - Convert movies in parallel (~119 files)"
            echo "  tv      - Convert TV shows in parallel (~4,413 files)"
            echo "  all     - Convert both libraries"
            echo ""
            echo "Configuration:"
            echo "  Parallel jobs: $MAX_JOBS (adjust MAX_JOBS in script for your system)"
            echo "  Log directory: $LOG_DIR/"
            echo ""
            echo "System recommendations:"
            echo "  - Ensure sufficient CPU cores (current: $MAX_JOBS jobs)"
            echo "  - Ensure sufficient disk I/O capacity"
            echo "  - Monitor system resources during processing"
            exit 1
            ;;
    esac
    
    log_message "✨ All parallel conversion jobs completed!"
}

# Handle script termination gracefully
trap 'log_message "⚠️  Parallel script interrupted by user"; killall parallel 2>/dev/null || true; exit 130' INT TERM

# Execute main function
main "$@"
