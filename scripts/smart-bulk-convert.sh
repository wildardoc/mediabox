#!/bin/bash

# Smart Bulk Conversion Manager
# Intelligently manages bulk media conversion based on system resources
# Scales up/down conversion processes based on CPU, memory, and active processes

set -uo pipefail

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
RAMP_UP_INTERVAL=30         # Seconds to wait before adding another job (30 seconds)
MAX_PARALLEL_JOBS=4         # Maximum concurrent conversion jobs
MIN_PARALLEL_JOBS=1         # Minimum concurrent conversion jobs
PLEX_PRIORITY=true          # Give Plex transcoding priority
DOWNLOAD_PRIORITY=true      # Give downloaders priority
FORCE_STEREO=false          # Force creation of enhanced stereo tracks

# Runtime variables
CURRENT_JOBS=0
TOTAL_PROCESSED=0
TOTAL_ERRORS=0
START_TIME=$(date +%s)
LAST_RAMP_UP_TIME=$START_TIME    # Track when we last increased job count
CURRENT_TARGET_JOBS=1            # Start conservatively with 1 job
CONVERSION_QUEUE=()
ACTIVE_PIDS=()
TARGET_DIRS=()
QUEUE_INDEX=0  # Track current position in queue globally

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >&2
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
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
            RAMP_UP_INTERVAL=$(jq -r '.ramp_up_interval // 30' "$CONFIG_FILE")
            # Handle boolean values correctly
            local plex_priority_val=$(jq -r '.plex_priority' "$CONFIG_FILE")
            local download_priority_val=$(jq -r '.download_priority' "$CONFIG_FILE")
            local force_stereo_val=$(jq -r '.force_stereo' "$CONFIG_FILE")
            [[ "$plex_priority_val" == "true" ]] && PLEX_PRIORITY=true || PLEX_PRIORITY=false
            [[ "$download_priority_val" == "true" ]] && DOWNLOAD_PRIORITY=true || DOWNLOAD_PRIORITY=false
            [[ "$force_stereo_val" == "true" ]] && FORCE_STEREO=true || FORCE_STEREO=false
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
    "ramp_up_interval": 30,
    "max_parallel_jobs": 4,
    "min_parallel_jobs": 1,
    "plex_priority": true,
    "download_priority": true,
    "force_stereo": false,
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check for Plex transcoding
    if [[ "$PLEX_PRIORITY" == "true" ]]; then
        local plex_processes=$(pgrep -f "PlexTranscoder\|plex.*ffmpeg" 2>/dev/null | wc -l 2>/dev/null || echo "0")
        # Ensure we have a valid number
        if [[ ! "$plex_processes" =~ ^[0-9]+$ ]]; then
            plex_processes=0
        fi
        high_priority_count=$((high_priority_count + plex_processes))
        echo "[$timestamp] [DEBUG] Plex processes detected: $plex_processes" >> "$LOG_FILE"
    fi
    
    # Check for download/import processes  
    if [[ "$DOWNLOAD_PRIORITY" == "true" ]]; then
        local import_processes=$(pgrep -f "import\.sh\|media_update\.py" 2>/dev/null | wc -l 2>/dev/null || echo "0")
        # Ensure we have a valid number
        if [[ ! "$import_processes" =~ ^[0-9]+$ ]]; then
            import_processes=0
        fi
        high_priority_count=$((high_priority_count + import_processes))
        echo "[$timestamp] [DEBUG] Import processes detected: $import_processes" >> "$LOG_FILE"
    fi
    
    echo "[$timestamp] [DEBUG] Total priority processes: $high_priority_count" >> "$LOG_FILE"
    echo $high_priority_count
}

# Determine optimal number of conversion jobs
calculate_optimal_jobs() {
    local stats=$(get_system_stats)
    local cpu_usage=$(echo "$stats" | cut -d',' -f1)
    local mem_percent=$(echo "$stats" | cut -d',' -f2)
    local load_avg=$(echo "$stats" | cut -d',' -f3)
    local available_gb=$(echo "$stats" | cut -d',' -f4)
    
    # Clean and validate numbers
    cpu_usage=$(echo "$cpu_usage" | sed 's/[^0-9]//g')
    mem_percent=$(echo "$mem_percent" | sed 's/[^0-9]//g')
    load_avg=$(echo "$load_avg" | sed 's/[^0-9.]//g')
    available_gb=$(echo "$available_gb" | sed 's/[^0-9.]//g')
    
    # Ensure we have valid numbers for arithmetic - with proper fallbacks
    if [[ -z "$cpu_usage" ]] || [[ ! "$cpu_usage" =~ ^[0-9]+$ ]]; then cpu_usage="50"; fi
    if [[ -z "$mem_percent" ]] || [[ ! "$mem_percent" =~ ^[0-9]+$ ]]; then mem_percent="50"; fi
    if [[ -z "$load_avg" ]] || [[ ! "$load_avg" =~ ^[0-9]*\.?[0-9]+$ ]]; then load_avg="10.0"; fi
    if [[ -z "$available_gb" ]] || [[ ! "$available_gb" =~ ^[0-9]*\.?[0-9]+$ ]]; then available_gb="8.0"; fi
    
    local priority_processes=$(check_priority_processes)
    local current_time=$(date +%s)
    local time_since_last_ramp=$((current_time - LAST_RAMP_UP_TIME))
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [DEBUG] Stats: CPU=${cpu_usage}%,Mem=${mem_percent}%,Load=${load_avg},RAM=${available_gb}GB,Prio=${priority_processes},Target=${CURRENT_TARGET_JOBS}" >> "$LOG_FILE"
    
    # Start with current target (conservative approach)
    local optimal_jobs=$CURRENT_TARGET_JOBS
    local system_healthy=true
    
    # Check if system is under stress - immediate reduction if needed
    if [[ $priority_processes -gt 0 ]]; then
        optimal_jobs=$(( optimal_jobs / 2 ))
        system_healthy=false
        echo "[$timestamp] [INFO] High-priority processes detected, reducing jobs to $optimal_jobs" >> "$LOG_FILE"
    fi
    
    # CPU threshold check
    if [[ $cpu_usage -gt $MAX_CPU_PERCENT ]]; then
        optimal_jobs=$(( optimal_jobs - 1 ))
        system_healthy=false
        log "INFO" "CPU usage high (${cpu_usage}%), reducing jobs to $optimal_jobs" >&2
    fi
    
    # ZFS-aware memory check - use available memory instead of usage percentage  
    local memory_ok=1
    if command -v bc >/dev/null 2>&1; then
        local bc_result=$(echo "$available_gb < $MIN_AVAILABLE_MEMORY_GB" | bc -l 2>/dev/null)
        if [[ "$bc_result" == "1" ]]; then
            memory_ok=0
        fi
    else
        # Fallback comparison without bc - convert to integer for safe comparison
        local available_int=$(echo "$available_gb" | cut -d. -f1)
        [[ -z "$available_int" ]] && available_int="0"
        if [[ $available_int -lt $MIN_AVAILABLE_MEMORY_GB ]]; then
            memory_ok=0
        fi
    fi
    
    if [[ $memory_ok -eq 0 ]]; then
        optimal_jobs=0
        system_healthy=false
        log "WARN" "Low available memory (${available_gb}GB < ${MIN_AVAILABLE_MEMORY_GB}GB), pausing conversions" >&2
    elif [[ $mem_percent -gt $MAX_MEMORY_PERCENT ]]; then
        optimal_jobs=$(( optimal_jobs - 1 ))
        system_healthy=false
        log "INFO" "Memory pressure high (${mem_percent}%), reducing jobs to $optimal_jobs" >&2
    fi
    
    # Load average check with fallback
    local load_high=0
    if command -v bc >/dev/null 2>&1; then
        local bc_result=$(echo "$load_avg > $MAX_LOAD_AVERAGE" | bc -l 2>/dev/null)
        if [[ "$bc_result" == "1" ]]; then
            load_high=1
        fi
    else
        # Fallback comparison without bc
        local load_int=$(echo "$load_avg" | cut -d. -f1)
        [[ -z "$load_int" ]] && load_int="0"
        local max_load_int=$(echo "$MAX_LOAD_AVERAGE" | cut -d. -f1)
        if [[ $load_int -gt $max_load_int ]]; then
            load_high=1
        fi
    fi
    
    if [[ $load_high -eq 1 ]]; then
        optimal_jobs=$(( optimal_jobs - 1 ))
        system_healthy=false
        log "INFO" "Load average high (${load_avg}), reducing jobs to $optimal_jobs" >&2
    fi
    
    # GRADUAL RAMP-UP LOGIC: Only increase if system is healthy and enough time has passed
    if [[ $system_healthy == true && $time_since_last_ramp -ge $RAMP_UP_INTERVAL ]]; then
        # Check if we can safely add another job
        if [[ $CURRENT_TARGET_JOBS -lt $MAX_PARALLEL_JOBS && $CURRENT_JOBS -gt 0 ]]; then
            # System is stable, consider ramping up
            local new_target=$((CURRENT_TARGET_JOBS + 1))
            log "INFO" "System stable for ${time_since_last_ramp}s, ramping up from $CURRENT_TARGET_JOBS to $new_target jobs" >&2
            CURRENT_TARGET_JOBS=$new_target
            LAST_RAMP_UP_TIME=$current_time
            optimal_jobs=$CURRENT_TARGET_JOBS
        fi
    fi
    
    # Update target if we had to reduce due to system stress
    if [[ $optimal_jobs -lt $CURRENT_TARGET_JOBS ]]; then
        CURRENT_TARGET_JOBS=$optimal_jobs
        LAST_RAMP_UP_TIME=$current_time  # Reset ramp-up timer after reduction
        log "INFO" "Reduced target jobs to $CURRENT_TARGET_JOBS due to system stress" >&2
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
        # Set initial target based on existing jobs (but at least 1)
        CURRENT_TARGET_JOBS=$(( CURRENT_JOBS > 0 ? CURRENT_JOBS : 1 ))
        log "INFO" "Adopted $CURRENT_JOBS existing conversion process(es), setting target to $CURRENT_TARGET_JOBS"
    else
        log "INFO" "No existing conversion processes found, starting with target of $CURRENT_TARGET_JOBS"
    fi
}

# Build conversion queue
build_conversion_queue() {
    local target_dirs=("$@")
    log "INFO" "Building conversion queue for directories: ${target_dirs[*]}"
    
    # Initialize or update stats at start of scanning
    update_stats
    
    # Video extensions that media_update.py processes
    local video_extensions=("mkv" "mp4" "avi" "mov" "wmv" "flv")
    local files_scanned=0
    
    # Find all video files that need conversion in all target directories
    for target_dir in "${target_dirs[@]}"; do
        if [[ ! -d "$target_dir" ]]; then
            log "WARN" "Directory not found: $target_dir, skipping..."
            continue
        fi
        
        log "INFO" "Scanning directory: $target_dir"
        
        # Use a simpler approach - find all video files at once
        echo "DEBUG: Starting find command for video files..."
        local temp_files=()
        while IFS= read -r -d '' file; do
            temp_files+=("$file")
        done < <(find "$target_dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.wmv" -o -name "*.flv" \) -print0 2>/dev/null)
        
        echo "DEBUG: Found ${#temp_files[@]} total video files"
        
        # Process each file
        for file in "${temp_files[@]}"; do
            # Check if this file needs conversion based on media_update.py logic
            if needs_conversion "$file" 2>/dev/null; then
                CONVERSION_QUEUE+=("$file")
                echo "DEBUG: Added to queue: $(basename "$file")"
            fi
            
            # Update stats periodically during scanning (every 100 files)
            ((files_scanned++))
            if (( files_scanned % 100 == 0 )); then
                echo "DEBUG: Scanned $files_scanned files, queue size: ${#CONVERSION_QUEUE[@]}"
                echo "DEBUG: About to call update_stats..."
                if ! update_stats; then
                    echo "DEBUG: update_stats failed"
                fi
                echo "DEBUG: update_stats completed"
            fi
        done
        
        echo "DEBUG: Completed processing all ${#temp_files[@]} files in directory"
        
        # Update stats after each directory completes
        log "INFO" "Completed scanning: $target_dir (${#CONVERSION_QUEUE[@]} files queued so far)"
        echo "DEBUG: About to call final update_stats..."
        if ! update_stats; then
            echo "DEBUG: Final update_stats failed"
        fi
        echo "DEBUG: Final update_stats completed"
    done
    
    log "INFO" "Found ${#CONVERSION_QUEUE[@]} files requiring conversion across all directories"
    echo "DEBUG: Queue size = ${#CONVERSION_QUEUE[@]}" 
}

# Check if a file needs conversion (simplified version of media_update.py logic)
needs_conversion() {
    local file="$1"
    
    # Skip if file doesn't exist
    if [[ ! -f "$file" ]]; then
        echo "DEBUG: File not found: $file" >&2
        return 1
    fi
    
    # For MKV and other formats, check if corresponding MP4 exists
    if [[ ! "$file" =~ \.mp4$ ]]; then
        local base_name="${file%.*}"
        local mp4_file="${base_name}.mp4"
        if [[ -f "$mp4_file" ]]; then
            echo "DEBUG: MP4 version exists, skipping: $(basename "$file")" >&2
            return 1  # Skip if MP4 version exists
        fi
    fi
    
    # For MP4 files, let media_update.py make the detailed decision
    # The enhanced logic in media_update.py will check format AND metadata
    return 0  # Needs conversion/checking
}

# Start a conversion job
start_conversion_job() {
    local input_file="$1"
    local job_id="conv_$(date +%s)_$$"
    
    log "INFO" "Starting conversion: $(basename "$input_file")"
    
    # Start conversion in background
    (
        cd "$SCRIPT_DIR"
        # Build command with optional --force-stereo flag
        local cmd="python3 media_update.py --file \"$input_file\" --type video"
        if [[ "$FORCE_STEREO" == "true" ]]; then
            cmd="$cmd --force-stereo"
        fi
        
        if eval "$cmd"; then
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
        # Update stats after job completions
        update_stats
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
    
    # Calculate actual remaining items based on global QUEUE_INDEX
    local remaining=$(( ${#CONVERSION_QUEUE[@]} - QUEUE_INDEX ))
    # Log values for debugging
    log "DEBUG" "Stats Update: Total Queue: ${#CONVERSION_QUEUE[@]}, QUEUE_INDEX: $QUEUE_INDEX, Remaining: $remaining"
    
    cat > "$STATS_FILE" << EOF
{
    "start_time": $START_TIME,
    "current_time": $current_time,
    "elapsed_hours": $(echo "scale=2; $elapsed_time / 3600" | bc -l),
    "total_processed": $TOTAL_PROCESSED,
    "total_errors": $TOTAL_ERRORS,
    "current_jobs": $CURRENT_JOBS,
    "queue_remaining": $remaining,
    "queue_total": ${#CONVERSION_QUEUE[@]},
    "processing_rate_per_hour": $rate
}
EOF
}

# Main processing loop
main_processing_loop() {
    # Using global QUEUE_INDEX instead of local queue_index
    
    while [[ $QUEUE_INDEX -lt ${#CONVERSION_QUEUE[@]} || $CURRENT_JOBS -gt 0 ]]; do
        # Clean up completed jobs
        cleanup_completed_jobs
        
        # Calculate optimal job count
        local optimal_jobs=$(calculate_optimal_jobs)
        
        # Start new jobs if needed and possible
        while [[ $CURRENT_JOBS -lt $optimal_jobs && $QUEUE_INDEX -lt ${#CONVERSION_QUEUE[@]} ]]; do
            start_conversion_job "${CONVERSION_QUEUE[$QUEUE_INDEX]}"
            QUEUE_INDEX=$((QUEUE_INDEX + 1))
        done
        
        # Terminate excess jobs if current jobs exceed optimal count
        while [[ $CURRENT_JOBS -gt $optimal_jobs ]]; do
            # Find and terminate the oldest job (first in array)
            if [[ ${#ACTIVE_PIDS[@]} -gt 0 ]]; then
                local oldest_pid="${ACTIVE_PIDS[0]}"
                if kill -0 "$oldest_pid" 2>/dev/null; then
                    log "INFO" "Terminating excess job PID: $oldest_pid (reducing from $CURRENT_JOBS to $optimal_jobs jobs)"
                    kill -TERM "$oldest_pid" 2>/dev/null || true
                    # Wait a moment for termination
                    sleep 2
                fi
                # Clean up completed jobs to update counts
                cleanup_completed_jobs
            else
                # Safety break if no active PIDs but CURRENT_JOBS > 0
                log "WARN" "CURRENT_JOBS=$CURRENT_JOBS but no active PIDs, resetting counter"
                CURRENT_JOBS=0
                break
            fi
        done
        
        # Wait and monitor
        log "INFO" "Active jobs: $CURRENT_JOBS/$optimal_jobs, Queue: $QUEUE_INDEX/${#CONVERSION_QUEUE[@]}, Processed: $TOTAL_PROCESSED"
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
    --force-stereo       Force creation of enhanced stereo tracks for all files
    --create-config      Create default configuration file
    -h, --help          Show this help

EXAMPLES:
    $0 /content/movies /content/tv            # Convert movies and TV with smart resource management
    $0 --max-jobs 5 /content/movies          # Limit to 5 parallel jobs  
    $0 --cpu-limit 95 /content/movies /content/tv  # More conservative CPU usage
    $0 --force-stereo /content/tv             # Force enhanced stereo creation for better dialogue
    $0 --create-config                       # Create configuration file for customization

The script will:
1. Start conservatively with 1 job and gradually ramp up every 30 seconds
2. Monitor system resources (CPU, memory, load)
3. Detect high-priority processes (Plex, downloads)
4. Dynamically scale conversion jobs based on available resources
5. Pause/resume automatically based on system load
6. Log all decisions and maintain conversion statistics

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
        --force-stereo)
            FORCE_STEREO=true
            shift
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

# Initialize stats tracking immediately after config load
update_stats

# Build conversion queue
build_conversion_queue "${TARGET_DIRS[@]}"

# Detect and adopt existing conversions
log "DEBUG" "Starting detect_existing_conversions..."
if ! detect_existing_conversions; then
    log "ERROR" "Failed to detect existing conversions, continuing anyway..."
fi
log "DEBUG" "Completed detect_existing_conversions"

echo "DEBUG: Before check - Queue size = ${#CONVERSION_QUEUE[@]}"
if [[ ${#CONVERSION_QUEUE[@]} -eq 0 ]]; then
    log "INFO" "No files requiring conversion found"
    echo "DEBUG: Exiting because queue is empty"
    exit 0
fi
echo "DEBUG: Queue has files, continuing..."

# Wait for initial safety check
log "INFO" "Performing initial safety check..."
log "DEBUG" "PLEX_PRIORITY=$PLEX_PRIORITY, DOWNLOAD_PRIORITY=$DOWNLOAD_PRIORITY"

# Test the check_priority_processes function first
log "DEBUG" "Testing check_priority_processes function..."
if ! priority_processes=$(check_priority_processes); then
    log "ERROR" "check_priority_processes failed: $priority_processes"
    log "WARN" "Defaulting to 0 priority processes"
    priority_processes=0
fi
log "DEBUG" "Initial priority processes: $priority_processes"

# Test the calculate_optimal_jobs function
log "DEBUG" "Testing calculate_optimal_jobs function..."
if ! optimal_jobs=$(calculate_optimal_jobs); then
    log "ERROR" "calculate_optimal_jobs failed: $optimal_jobs"
    log "WARN" "Defaulting to 1 job"
    optimal_jobs=1
fi
log "DEBUG" "Initial optimal jobs: $optimal_jobs"

while true; do
    if ! priority_processes=$(check_priority_processes 2>&1); then
        log "ERROR" "check_priority_processes failed in loop: $priority_processes"
        priority_processes=0
    fi
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
if ! main_processing_loop; then
    log "ERROR" "Main processing loop failed, exiting..."
    exit 1
fi

log "INFO" "Smart bulk conversion completed successfully!"
