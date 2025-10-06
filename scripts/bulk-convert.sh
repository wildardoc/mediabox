#!/bin/bash
set -euo pipefail

# Bulk Media Conversion Script
# Efficiently converts entire movie and TV libraries with progress tracking

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
LOG_DIR="./bulk-conversion-logs"
BATCH_SIZE=50  # Process files in batches for better monitoring

# Create log directory
mkdir -p "$LOG_DIR"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/bulk-conversion.log"
}

# Function to estimate completion time
estimate_time() {
    local files_remaining=$1
    local avg_time_per_file=$2
    local total_seconds=$((files_remaining * avg_time_per_file))
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    echo "${hours}h ${minutes}m"
}

# Function to show system resources
show_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local memory=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    local disk_usage=$(df -h "$MOVIEDIR" | awk 'NR==2 {print $5}')
    echo "💻 Resources: CPU: ${cpu_usage}% | Memory: ${memory} | Disk: ${disk_usage}"
}

# Function to process directory with progress tracking
process_directory() {
    local dir="$1"
    local type="$2"
    local description="$3"
    
    log_message "🎬 Starting $description conversion..."
    log_message "📂 Directory: $dir"
    
    # Get list of MKV files
    local mkv_files=()
    while IFS= read -r -d '' file; do
        mkv_files+=("$file")
    done < <(find "$dir" -type f \( -name "*.mkv" -o -name "*.m2ts" \) -print0)
    
    local total_files=${#mkv_files[@]}
    local processed=0
    local skipped=0
    local errors=0
    local start_time=$(date +%s)
    
    log_message "📊 Found $total_files MKV files to process"
    show_resources
    
    if [[ $total_files -eq 0 ]]; then
        log_message "✅ No MKV files found in $description"
        return 0
    fi
    
    # Process files in batches
    for ((i=0; i<total_files; i++)); do
        local file="${mkv_files[i]}"
        local file_start_time=$(date +%s)
        
        # Show progress
        ((processed++))
        local percent=$((processed * 100 / total_files))
        
        log_message "📁 [$processed/$total_files] ($percent%) Processing: $(basename "$file")"
        show_resources
        
        # Check if MP4 already exists and is valid
        local base_name="${file%.*}"
        local mp4_file="${base_name}.mp4"
        
        if [[ -f "$mp4_file" ]]; then
            # Quick validation with ffprobe
            if ffprobe -v quiet -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$mp4_file" >/dev/null 2>&1; then
                log_message "⏭️  Skipping: MP4 already exists and is valid"
                ((skipped++))
                continue
            else
                log_message "🔄 Existing MP4 is invalid, reconverting..."
            fi
        fi
        
        # Process the file
        log_message "⚙️  Converting: $file"
        if "$VENV_PYTHON" "$MEDIA_UPDATE_SCRIPT" --file "$file" --type "$type" >> "$LOG_DIR/conversion-details.log" 2>&1; then
            local file_end_time=$(date +%s)
            local file_duration=$((file_end_time - file_start_time))
            log_message "✅ Completed in ${file_duration}s: $(basename "$file")"
            
            # Update time estimates
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local avg_per_file=$((elapsed / processed))
            local remaining=$((total_files - processed))
            local eta=$(estimate_time $remaining $avg_per_file)
            
            log_message "📈 Progress: $processed/$total_files | ETA: $eta | Avg: ${avg_per_file}s/file"
        else
            log_message "❌ Failed: $(basename "$file")"
            ((errors++))
        fi
        
        # Batch checkpoint every 10 files
        if ((processed % 10 == 0)); then
            log_message "🏁 Checkpoint: $processed files processed, $skipped skipped, $errors errors"
            show_resources
        fi
    done
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local hours=$((total_duration / 3600))
    local minutes=$(((total_duration % 3600) / 60))
    
    log_message "🎉 $description conversion completed!"
    log_message "📊 Final stats: $processed processed, $skipped skipped, $errors errors"
    log_message "⏱️  Total time: ${hours}h ${minutes}m"
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
    log_message "🚀 Starting bulk media conversion"
    log_message "📂 Movies: $MOVIEDIR"
    log_message "📂 TV Shows: $TVDIR"
    
    # Safety check for active processes
    check_active_processes
    
    # Check prerequisites
    if [[ ! -x "$VENV_PYTHON" ]]; then
        log_message "❌ Virtual environment Python not found: $VENV_PYTHON"
        exit 1
    fi
    
    if [[ ! -f "$MEDIA_UPDATE_SCRIPT" ]]; then
        log_message "❌ Media update script not found: $MEDIA_UPDATE_SCRIPT"
        exit 1
    fi
    
    # Option 1: Movies only
    if [[ "${1:-}" == "movies" ]]; then
        process_directory "$MOVIEDIR" "both" "Movie"
        
    # Option 2: TV shows only  
    elif [[ "${1:-}" == "tv" ]]; then
        process_directory "$TVDIR" "video" "TV Show"
        
    # Option 3: Both (sequential)
    elif [[ "${1:-}" == "all" ]]; then
        log_message "🎯 Processing both movies and TV shows sequentially"
        process_directory "$MOVIEDIR" "both" "Movie"
        process_directory "$TVDIR" "video" "TV Show"
        
    else
        echo "Usage: $0 [movies|tv|all]"
        echo ""
        echo "Options:"
        echo "  movies  - Convert movie library only (~119 files)"
        echo "  tv      - Convert TV show library only (~4,413 files)"  
        echo "  all     - Convert both libraries sequentially"
        echo ""
        echo "Logs will be saved to: $LOG_DIR/"
        exit 1
    fi
    
    log_message "✨ Bulk conversion process completed!"
}

# Handle script termination gracefully
trap 'log_message "⚠️  Script interrupted by user"; exit 130' INT TERM

# Execute main function
main "$@"
