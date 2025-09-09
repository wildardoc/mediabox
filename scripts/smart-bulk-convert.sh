#!/bin/bash

# Smart Bulk Conversion Manager
# Intelligently manages bulk media conversion based on system resources
# Scales up/down conversion processes based on CPU, memory, and active processes

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/smart_bulk_convert_$(date +%Y%m%d_%H%M%S).log"
STATS_FILE="$SCRIPT_DIR/conversion_stats.json"
CONFIG_FILE="$SCRIPT_DIR/smart_convert_config.json"

# Default thresholds (can be overridden by config file)
MAX_CPU_PERCENT=75          # Stop adding processes above this CPU usage
MAX_MEMORY_PERCENT=80       # Stop adding processes above this memory usage
MAX_LOAD_AVERAGE=8.0        # Stop adding processes above this load average
MIN_AVAILABLE_MEMORY_GB=2   # Minimum free memory to maintain
CHECK_INTERVAL=30           # Seconds between resource checks
MAX_PARALLEL_JOBS=4         # Maximum concurrent conversion jobs
MIN_PARALLEL_JOBS=1         # Minimum concurrent conversion jobs
PLEX_PRIORITY=true          # Give Plex transcoding priority
DOWNLOAD_PRIORITY=true      # Give downloaders priority

# Runtime variables
CURRENT_JOBS=0
TOTAL_PROCESSED=0
TOTAL_ERRORS=0
START_TIME=$(date +%s)
CONVERSION_QUEUE=()
ACTIVE_PIDS=()
TARGET_DIRS=()

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "INFO" "Loading configuration from $CONFIG_FILE"
        # Parse JSON config (basic implementation)
        if command -v jq >/dev/null 2>&1; then
            MAX_CPU_PERCENT=$(jq -r '.max_cpu_percent // 75' "$CONFIG_FILE")
            MAX_MEMORY_PERCENT=$(jq -r '.max_memory_percent // 80' "$CONFIG_FILE")
            MAX_LOAD_AVERAGE=$(jq -r '.max_load_average // 8.0' "$CONFIG_FILE")
            MAX_PARALLEL_JOBS=$(jq -r '.max_parallel_jobs // 4' "$CONFIG_FILE")
            CHECK_INTERVAL=$(jq -r '.check_interval // 30' "$CONFIG_FILE")
            # Handle boolean values correctly
            local plex_priority_val=$(jq -r '.plex_priority' "$CONFIG_FILE")
            local download_priority_val=$(jq -r '.download_priority' "$CONFIG_FILE")
            [[ "$plex_priority_val" == "true" ]] && PLEX_PRIORITY=true || PLEX_PRIORITY=false
            [[ "$download_priority_val" == "true" ]] && DOWNLOAD_PRIORITY=true || DOWNLOAD_PRIORITY=false
        fi
    else
        log "INFO" "No config file found, using defaults"
    fi
}

# Create default config file
create_default_config() {
    cat > "$CONFIG_FILE" << EOF
{
    "max_cpu_percent": 75,
    "max_memory_percent": 80,
    "max_load_average": 8.0,
    "min_available_memory_gb": 2,
    "check_interval": 30,
    "max_parallel_jobs": 4,
    "min_parallel_jobs": 1,
    "plex_priority": true,
    "download_priority": true,
    "target_directories": [
        "/content/movies",
        "/content/tv"
    ],
    "pause_for_processes": [
        "PlexTranscoder",
        "plex_ffmpeg",
        "import.sh",
        "media_update.py"
    ]
}
EOF
    log "INFO" "Created default configuration at $CONFIG_FILE"
}

# Get system resource usage (ZFS-aware)
get_system_stats() {
    # CPU usage (1-minute average, inverted from idle)
    local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/%id,//' | sed 's/[^0-9.]//g')
    # Ensure we have a valid number
    if [[ ! "$cpu_idle" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        cpu_idle="0"
    fi
    local cpu_usage=$(echo "100 - $cpu_idle" | bc -l 2>/dev/null | cut -d. -f1)
    # Fallback if bc fails
    if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]]; then
        cpu_usage="0"
    fi
    
    # Memory usage - ZFS-aware calculation
    local mem_info=$(cat /proc/meminfo)
    local total_mem_kb=$(echo "$mem_info" | grep '^MemTotal:' | awk '{print $2}')
    local available_mem_kb=$(echo "$mem_info" | grep '^MemAvailable:' | awk '{print $2}')
    
    # Ensure we have valid numbers
    [[ ! "$total_mem_kb" =~ ^[0-9]+$ ]] && total_mem_kb="1000000"
    [[ ! "$available_mem_kb" =~ ^[0-9]+$ ]] && available_mem_kb="500000"
    
    # Calculate memory pressure based on MemAvailable (accounts for ZFS ARC)
    local mem_pressure_percent=$(echo "scale=0; ((($total_mem_kb - $available_mem_kb) * 100) / $total_mem_kb)" | bc 2>/dev/null || echo "50")
    local available_gb=$(echo "scale=1; $available_mem_kb / 1024 / 1024" | bc 2>/dev/null || echo "1.0")
    
    # Load average (1-minute)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs | sed 's/[^0-9.]//g')
    # Ensure we have a valid number
    if [[ ! "$load_avg" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        load_avg="0.0"
    fi
    
    echo "$cpu_usage,$mem_pressure_percent,$load_avg,$available_gb"
}

# Check for high-priority processes
check_priority_processes() {
    local high_priority_count=0
    
    # Check for Plex transcoding
    if [[ "$PLEX_PRIORITY" == "true" ]]; then
        local plex_processes=$(pgrep -f "PlexTranscoder\|plex.*ffmpeg" | wc -l)
        high_priority_count=$((high_priority_count + plex_processes))
    fi
    
    # Check for download/import processes  
    if [[ "$DOWNLOAD_PRIORITY" == "true" ]]; then
        local import_processes=$(pgrep -f "import\.sh\|media_update\.py" | wc -l)
        high_priority_count=$((high_priority_count + import_processes))
    fi
    
    echo $high_priority_count
}

# Determine optimal number of conversion jobs
calculate_optimal_jobs() {
    local stats=$(get_system_stats)
    local cpu_usage=$(echo "$stats" | cut -d',' -f1 | sed 's/[^0-9]//g')
    local mem_percent=$(echo "$stats" | cut -d',' -f2 | sed 's/[^0-9]//g')
    local load_avg=$(echo "$stats" | cut -d',' -f3 | sed 's/[^0-9.]//g')
    local available_gb=$(echo "$stats" | cut -d',' -f4 | sed 's/[^0-9.]//g')
    
    # Ensure we have valid numbers for arithmetic
    [[ ! "$cpu_usage" =~ ^[0-9]+$ ]] && cpu_usage="0"
    [[ ! "$mem_percent" =~ ^[0-9]+$ ]] && mem_percent="0"
    [[ ! "$load_avg" =~ ^[0-9]*\.?[0-9]+$ ]] && load_avg="0.0"
    [[ ! "$available_gb" =~ ^[0-9]*\.?[0-9]+$ ]] && available_gb="1.0"
    
    local priority_processes=$(check_priority_processes)
    local optimal_jobs=$MAX_PARALLEL_JOBS
    
    log "DEBUG" "System stats: CPU=${cpu_usage}%, Memory pressure=${mem_percent}%, Load=${load_avg}, Available=${available_gb}GB, Priority processes=${priority_processes}"
    
    # Reduce jobs if high-priority processes are running
    if [[ $priority_processes -gt 0 ]]; then
        optimal_jobs=$(( optimal_jobs / 2 ))
        log "INFO" "High-priority processes detected, reducing parallel jobs to $optimal_jobs"
    fi
    
    # Check resource thresholds - ensure safe arithmetic operations
    if [[ $cpu_usage -gt $MAX_CPU_PERCENT ]]; then
        optimal_jobs=$(( optimal_jobs - 1 ))
        log "INFO" "CPU usage high (${cpu_usage}%), reducing jobs to $optimal_jobs"
    fi
    
    # ZFS-aware memory check - use available memory instead of usage percentage  
    local memory_ok=1
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$available_gb < $MIN_AVAILABLE_MEMORY_GB" | bc -l 2>/dev/null || echo "0") )); then
            memory_ok=0
        fi
    else
        # Fallback comparison without bc
        local available_int=$(echo "$available_gb" | cut -d. -f1)
        if [[ $available_int -lt $MIN_AVAILABLE_MEMORY_GB ]]; then
            memory_ok=0
        fi
    fi
    
    if [[ $memory_ok -eq 0 ]]; then
        optimal_jobs=0
        log "WARN" "Low available memory (${available_gb}GB < ${MIN_AVAILABLE_MEMORY_GB}GB), pausing conversions"
    elif [[ $mem_percent -gt $MAX_MEMORY_PERCENT ]]; then
        optimal_jobs=$(( optimal_jobs - 1 ))
        log "INFO" "Memory pressure high (${mem_percent}%), reducing jobs to $optimal_jobs"
    fi
    
    # Load average check with fallback
    local load_high=0
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$load_avg > $MAX_LOAD_AVERAGE" | bc -l 2>/dev/null || echo "0") )); then
            load_high=1
        fi
    else
        # Fallback comparison without bc
        local load_int=$(echo "$load_avg" | cut -d. -f1)
        local max_load_int=$(echo "$MAX_LOAD_AVERAGE" | cut -d. -f1)
        if [[ $load_int -gt $max_load_int ]]; then
            load_high=1
        fi
    fi
    
    if [[ $load_high -eq 1 ]]; then
        optimal_jobs=$(( optimal_jobs - 1 ))
        log "INFO" "Load average high (${load_avg}), reducing jobs to $optimal_jobs"
    fi
    
    # Ensure we stay within bounds
    if [[ $optimal_jobs -lt 0 ]]; then
        optimal_jobs=0
    elif [[ $optimal_jobs -gt $MAX_PARALLEL_JOBS ]]; then
        optimal_jobs=$MAX_PARALLEL_JOBS
    fi
    
    echo $optimal_jobs
}

# Detect and adopt existing conversion processes
detect_existing_conversions() {
    log "INFO" "Detecting existing conversion processes..."
    local existing_pids=$(pgrep -f "media_update\.py" || true)
    
    if [[ -n "$existing_pids" ]]; then
        while IFS= read -r pid; do
            if [[ -n "$pid" ]]; then
                ACTIVE_PIDS+=($pid)
                CURRENT_JOBS=$((CURRENT_JOBS + 1))
                log "INFO" "Adopted existing conversion process (PID: $pid)"
            fi
        done <<< "$existing_pids"
        log "INFO" "Adopted $CURRENT_JOBS existing conversion process(es)"
    else
        log "INFO" "No existing conversion processes found"
    fi
}

# Build conversion queue
build_conversion_queue() {
    local target_dirs=("$@")
    log "INFO" "Building conversion queue for directories: ${target_dirs[*]}"
    
    # Video extensions that media_update.py processes
    local video_extensions=("mkv" "mp4" "avi" "mov" "wmv" "flv")
    
    # Find all video files that need conversion in all target directories
    for target_dir in "${target_dirs[@]}"; do
        if [[ ! -d "$target_dir" ]]; then
            log "WARN" "Directory not found: $target_dir, skipping..."
            continue
        fi
        
        log "INFO" "Scanning directory: $target_dir"
        for ext in "${video_extensions[@]}"; do
            while IFS= read -r -d '' file; do
                # Check if this file needs conversion based on media_update.py logic
                if needs_conversion "$file"; then
                    CONVERSION_QUEUE+=("$file")
                fi
            done < <(find "$target_dir" -name "*.${ext}" -type f -print0)
        done
    done
    
    log "INFO" "Found ${#CONVERSION_QUEUE[@]} files requiring conversion across all directories"
}

# Check if a file needs conversion (simplified version of media_update.py logic)
needs_conversion() {
    local file="$1"
    
    # Skip if file doesn't exist
    [[ ! -f "$file" ]] && return 1
    
    # Skip if it's already an optimized MP4 with proper audio
    if [[ "$file" =~ \.mp4$ ]]; then
        # Use ffprobe to check if it already has proper H.264 + AAC
        local probe_result=$(ffprobe -v quiet -print_format json -show_streams "$file" 2>/dev/null)
        if [[ -n "$probe_result" ]]; then
            # Check for H.264 video and AAC audio (basic check)
            if echo "$probe_result" | grep -q '"codec_name": "h264"' && echo "$probe_result" | grep -q '"codec_name": "aac"'; then
                # File might already be optimized, but let media_update.py make final decision
                # For now, assume it needs checking unless it's very recent
                local file_age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
                [[ $file_age_days -lt 7 ]] && return 1  # Skip very recent MP4s
            fi
        fi
    fi
    
    # For MKV and other formats, check if corresponding MP4 exists
    if [[ ! "$file" =~ \.mp4$ ]]; then
        local base_name="${file%.*}"
        local mp4_file="${base_name}.mp4"
        [[ -f "$mp4_file" ]] && return 1  # Skip if MP4 version exists
    fi
    
    return 0  # Needs conversion
}

# Start a conversion job
start_conversion_job() {
    local input_file="$1"
    local job_id="conv_$(date +%s)_$$"
    
    log "INFO" "Starting conversion: $(basename "$input_file")"
    
    # Start conversion in background
    (
        cd "$SCRIPT_DIR"
        if python3 media_update.py --file "$input_file" --type video; then
            echo "SUCCESS:$input_file" >> "${LOG_FILE}.results"
        else
            echo "ERROR:$input_file" >> "${LOG_FILE}.results"
        fi
    ) &
    
    local pid=$!
    ACTIVE_PIDS+=($pid)
    CURRENT_JOBS=$((CURRENT_JOBS + 1))
    
    log "DEBUG" "Started job $job_id (PID: $pid) for $(basename "$input_file")"
}

# Clean up completed jobs
cleanup_completed_jobs() {
    local new_pids=()
    local completed_jobs=0
    
    for pid in "${ACTIVE_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            new_pids+=($pid)
        else
            completed_jobs=$((completed_jobs + 1))
            CURRENT_JOBS=$((CURRENT_JOBS - 1))
            TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
        fi
    done
    
    ACTIVE_PIDS=("${new_pids[@]}")
    
    if [[ $completed_jobs -gt 0 ]]; then
        log "INFO" "Completed $completed_jobs job(s). Active: $CURRENT_JOBS, Total processed: $TOTAL_PROCESSED"
    fi
}

# Update statistics
update_stats() {
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - START_TIME))
    local rate=0
    
    if [[ $elapsed_time -gt 0 && $TOTAL_PROCESSED -gt 0 ]]; then
        rate=$(echo "scale=2; $TOTAL_PROCESSED / ($elapsed_time / 3600)" | bc -l)
    fi
    
    cat > "$STATS_FILE" << EOF
{
    "start_time": $START_TIME,
    "current_time": $current_time,
    "elapsed_hours": $(echo "scale=2; $elapsed_time / 3600" | bc -l),
    "total_processed": $TOTAL_PROCESSED,
    "total_errors": $TOTAL_ERRORS,
    "current_jobs": $CURRENT_JOBS,
    "queue_remaining": ${#CONVERSION_QUEUE[@]},
    "processing_rate_per_hour": $rate
}
EOF
}

# Main processing loop
main_processing_loop() {
    local queue_index=0
    
    while [[ $queue_index -lt ${#CONVERSION_QUEUE[@]} || $CURRENT_JOBS -gt 0 ]]; do
        # Clean up completed jobs
        cleanup_completed_jobs
        
        # Calculate optimal job count
        local optimal_jobs=$(calculate_optimal_jobs)
        
        # Start new jobs if needed and possible
        while [[ $CURRENT_JOBS -lt $optimal_jobs && $queue_index -lt ${#CONVERSION_QUEUE[@]} ]]; do
            start_conversion_job "${CONVERSION_QUEUE[$queue_index]}"
            queue_index=$((queue_index + 1))
        done
        
        # Wait and monitor
        log "INFO" "Active jobs: $CURRENT_JOBS/$optimal_jobs, Queue: $queue_index/${#CONVERSION_QUEUE[@]}, Processed: $TOTAL_PROCESSED"
        update_stats
        
        sleep $CHECK_INTERVAL
    done
    
    log "INFO" "All conversions completed! Total processed: $TOTAL_PROCESSED"
}

# Signal handlers
cleanup() {
    log "INFO" "Shutting down smart bulk converter..."
    
    # Kill all active conversion jobs
    for pid in "${ACTIVE_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log "INFO" "Terminating job PID: $pid"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait for jobs to terminate
    sleep 5
    
    # Force kill if necessary
    for pid in "${ACTIVE_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log "WARN" "Force killing job PID: $pid"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    update_stats
    log "INFO" "Smart bulk converter shutdown complete"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Usage function
usage() {
    cat << EOF
Smart Bulk Media Converter

USAGE: $0 [OPTIONS] <target_directory1> [target_directory2] ...

OPTIONS:
    -c, --config FILE    Use custom configuration file
    -j, --max-jobs N     Maximum parallel jobs (default: $MAX_PARALLEL_JOBS)
    -i, --interval N     Check interval in seconds (default: $CHECK_INTERVAL)
    --cpu-limit N        Max CPU usage percentage (default: $MAX_CPU_PERCENT)
    --memory-limit N     Max memory usage percentage (default: $MAX_MEMORY_PERCENT)
    --load-limit N       Max load average (default: $MAX_LOAD_AVERAGE)
    --create-config      Create default configuration file
    -h, --help          Show this help

EXAMPLES:
    $0 /content/movies /content/tv            # Convert movies and TV with smart resource management
    $0 --max-jobs 5 /content/movies          # Limit to 5 parallel jobs  
    $0 --cpu-limit 95 /content/movies /content/tv  # More conservative CPU usage
    $0 --create-config                       # Create configuration file for customization

The script will:
1. Monitor system resources (CPU, memory, load)
2. Detect high-priority processes (Plex, downloads)
3. Dynamically scale conversion jobs based on available resources
4. Pause/resume automatically based on system load
5. Log all decisions and maintain conversion statistics

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -j|--max-jobs)
            MAX_PARALLEL_JOBS="$2"
            shift 2
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        --cpu-limit)
            MAX_CPU_PERCENT="$2"
            shift 2
            ;;
        --memory-limit)
            MAX_MEMORY_PERCENT="$2"
            shift 2
            ;;
        --load-limit)
            MAX_LOAD_AVERAGE="$2"
            shift 2
            ;;
        --create-config)
            create_default_config
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            TARGET_DIRS+=("$1")
            shift
            ;;
    esac
done

# Validate arguments
if [[ ${#TARGET_DIRS[@]} -eq 0 ]]; then
    echo "Error: At least one target directory required" >&2
    usage
    exit 1
fi

for dir in "${TARGET_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Error: Target directory does not exist: $dir" >&2
        exit 1
    fi
done

# Main execution
log "INFO" "Starting Smart Bulk Media Converter"
log "INFO" "Target directories: ${TARGET_DIRS[*]}"

# Load configuration
load_config

log "INFO" "Configuration: CPU≤${MAX_CPU_PERCENT}%, Memory≤${MAX_MEMORY_PERCENT}%, Load≤${MAX_LOAD_AVERAGE}, Jobs≤${MAX_PARALLEL_JOBS}"

# Build conversion queue
build_conversion_queue "${TARGET_DIRS[@]}"

# Detect and adopt existing conversions
detect_existing_conversions

if [[ ${#CONVERSION_QUEUE[@]} -eq 0 ]]; then
    log "INFO" "No files requiring conversion found"
    exit 0
fi

# Wait for initial safety check
log "INFO" "Performing initial safety check..."
log "DEBUG" "PLEX_PRIORITY=$PLEX_PRIORITY, DOWNLOAD_PRIORITY=$DOWNLOAD_PRIORITY"
while true; do
    priority_processes=$(check_priority_processes)
    log "DEBUG" "Priority processes detected: $priority_processes"
    if [[ $priority_processes -eq 0 ]]; then
        log "INFO" "System ready for bulk conversion"
        break
    else
        log "INFO" "Waiting for $priority_processes high-priority process(es) to complete..."
        sleep $CHECK_INTERVAL
    fi
done

# Start main processing loop
log "INFO" "Beginning smart bulk conversion of ${#CONVERSION_QUEUE[@]} files"
main_processing_loop

log "INFO" "Smart bulk conversion completed successfully!"
