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
ACTIVE_JOB_FILES=()  # Track which files are being processed by each PID
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

# Individual resource functions for baseline tracking
get_cpu_usage() {
    local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/%id,//' | sed 's/[^0-9.]//g')
    if [[ ! "$cpu_idle" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        cpu_idle="0"
    fi
    local cpu_usage=$(echo "100 - $cpu_idle" | bc -l 2>/dev/null | cut -d. -f1)
    if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]]; then
        cpu_usage="0"
    fi
    echo "$cpu_usage"
}

get_memory_usage() {
    local mem_total=$(free | grep "Mem:" | awk '{print $2}')
    local mem_available=$(free | grep "Mem:" | awk '{print $7}')
    if [[ -z "$mem_available" ]]; then
        mem_available=$(free | grep "Mem:" | awk '{print $4}')
    fi
    local mem_used=$((mem_total - mem_available))
    local mem_percent=$(echo "scale=0; ($mem_used * 100) / $mem_total" | bc 2>/dev/null)
    if [[ ! "$mem_percent" =~ ^[0-9]+$ ]]; then
        mem_percent="0"
    fi
    echo "$mem_percent"
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
                ACTIVE_JOB_FILES+=("UNKNOWN_EXISTING_PROCESS")  # We can't know which file
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
        
        # Find all video files in this directory
        local temp_files=()
        for ext in "${video_extensions[@]}"; do
            while IFS= read -r -d '' file; do
                if needs_conversion "$file"; then
                    CONVERSION_QUEUE+=("$file")
                fi
                ((files_scanned++))
                # Update stats periodically during scanning (every 100 files)
                if (( files_scanned % 100 == 0 )); then
                    echo "DEBUG: Scanned $files_scanned files, queue size: ${#CONVERSION_QUEUE[@]}"
                    echo "DEBUG: About to call update_stats..."
                    if ! update_stats; then
                        echo "DEBUG: update_stats failed"
                    fi
                    echo "DEBUG: update_stats completed"
                fi
            done < <(find "$target_dir" -type f -iname "*.${ext}" -print0)
        done
        
        echo "DEBUG: Completed processing directory: $target_dir"
        
        # Update stats after each directory completes
        log "INFO" "Completed scanning: $target_dir (${#CONVERSION_QUEUE[@]} files queued so far)"
        echo "DEBUG: About to call final update_stats..."
        if ! update_stats; then
            echo "DEBUG: Final update_stats failed"
        fi
        echo "DEBUG: Final update_stats completed"
    done
    
    # Deduplicate the queue to prevent processing the same file multiple times
    # This is especially important when running with overlapping directory targets
    # (e.g., specific season → all seasons → all shows → all TV)
    local original_count=${#CONVERSION_QUEUE[@]}
    if [[ $original_count -gt 0 ]]; then
        # Use associative array for efficient deduplication by full file path
        declare -A seen_files
        local deduplicated_queue=()
        
        for file in "${CONVERSION_QUEUE[@]}"; do
            # Use the absolute path as the key to prevent duplicates
            local abs_path
            if abs_path=$(realpath "$file" 2>/dev/null); then
                if [[ ! -v "seen_files[$abs_path]" ]]; then
                    seen_files["$abs_path"]=1
                    deduplicated_queue+=("$file")
                else
                    log "DEBUG" "Skipping duplicate: $(basename "$file") (already queued from another directory)"
                fi
            else
                # If realpath fails, fall back to the original path
                if [[ ! -v "seen_files[$file]" ]]; then
                    seen_files["$file"]=1
                    deduplicated_queue+=("$file")
                else
                    log "DEBUG" "Skipping duplicate: $(basename "$file")"
                fi
            fi
        done
        
        CONVERSION_QUEUE=("${deduplicated_queue[@]}")
        local final_count=${#CONVERSION_QUEUE[@]}
        local duplicates_removed=$((original_count - final_count))
        
        if [[ $duplicates_removed -gt 0 ]]; then
            log "INFO" "Removed $duplicates_removed duplicate files from overlapping directory targets"
        fi
    fi
    
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
    
    # Create job start time marker
    local job_start_file="/tmp/job_start_$(basename "$input_file" | tr ' ' '_').time"
    echo "$(date +%s)" > "$job_start_file"
    
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
    ACTIVE_JOB_FILES+=("$input_file")
    CURRENT_JOBS=$((CURRENT_JOBS + 1))
    
    log "DEBUG" "Started job $job_id (PID: $pid) for $(basename "$input_file")"
}

# Clean up completed jobs
cleanup_completed_jobs() {
    local new_pids=()
    local new_job_files=()
    local completed_jobs=0
    local failed_jobs=0
    
    for i in "${!ACTIVE_PIDS[@]}"; do
        local pid="${ACTIVE_PIDS[$i]}"
        local job_file="${ACTIVE_JOB_FILES[$i]}"
        
        if kill -0 "$pid" 2>/dev/null; then
            # Job still running
            new_pids+=("$pid")
            new_job_files+=("$job_file")
        else
            # Job finished - check if it completed successfully
            local temp_file="${job_file%.*}.tmp.${job_file##*.}"
            local final_file="${job_file%.*}.mp4"
            
            # If temp file still exists, the job was terminated/cancelled, not completed
            if [[ -f "$temp_file" ]]; then
                # Job was terminated/cancelled: requeue it
                failed_jobs=$((failed_jobs + 1))
                CURRENT_JOBS=$((CURRENT_JOBS - 1))
                
                # Clean up the partial temp file
                rm -f "$temp_file"
                
                # Add back to front of queue for retry
                CONVERSION_QUEUE=("$job_file" "${CONVERSION_QUEUE[@]:$QUEUE_INDEX}")
                QUEUE_INDEX=0
                
                log "WARN" "🔄 Requeuing terminated/cancelled job: $(basename "$job_file")"
            else
                # Job finished without temp file - check if it was killed or completed naturally
                local current_time=$(date +%s)
                local job_start_file="/tmp/job_start_$(basename "$job_file" | tr ' ' '_').time"
                local job_status_file="/tmp/job_status_$(basename "$job_file" | tr ' ' '_').status"
                local job_runtime=0
                local was_killed=false
                
                # Check if job was marked as killed
                if [[ -f "$job_status_file" ]]; then
                    local status=$(cat "$job_status_file" 2>/dev/null)
                    if [[ "$status" == "KILLED" ]]; then
                        was_killed=true
                    fi
                    rm -f "$job_status_file"  # Clean up
                fi
                
                if [[ -f "$job_start_file" ]]; then
                    local start_time=$(cat "$job_start_file" 2>/dev/null || echo "$current_time")
                    job_runtime=$((current_time - start_time))
                    rm -f "$job_start_file"  # Clean up
                fi
                
                if [[ "$was_killed" == "true" ]]; then
                    # Job was explicitly killed by load balancer - requeue it
                    failed_jobs=$((failed_jobs + 1))
                    CURRENT_JOBS=$((CURRENT_JOBS - 1))
                    
                    # Add back to front of queue for retry
                    CONVERSION_QUEUE=("$job_file" "${CONVERSION_QUEUE[@]:$QUEUE_INDEX}")
                    QUEUE_INDEX=0
                    
                    log "WARN" "🔄 Requeuing job killed by load balancer (runtime: ${job_runtime}s): $(basename "$job_file")"
                else
                    # Job completed naturally (not killed by load balancer)
                    completed_jobs=$((completed_jobs + 1))
                    CURRENT_JOBS=$((CURRENT_JOBS - 1))
                    TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
                    log "INFO" "✅ Successfully completed conversion (runtime: ${job_runtime}s): $(basename "$job_file")"
                fi
            fi
        fi
    done
    
    ACTIVE_PIDS=("${new_pids[@]}")
    ACTIVE_JOB_FILES=("${new_job_files[@]}")
    
    if [[ $completed_jobs -gt 0 || $failed_jobs -gt 0 ]]; then
        log "INFO" "Jobs completed: $completed_jobs, failed/requeued: $failed_jobs. Active: $CURRENT_JOBS, Total processed: $TOTAL_PROCESSED"
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
    
    # Record baseline resource usage when we start
    local baseline_resources_file="/tmp/smart_convert_baseline_resources"
    local baseline_cpu=$(get_cpu_usage)
    local baseline_mem=$(get_memory_usage)
    echo "CPU:$baseline_cpu" > "$baseline_resources_file"
    echo "MEM:$baseline_mem" >> "$baseline_resources_file"
    log "INFO" "Recorded baseline resources: CPU: ${baseline_cpu}%, Memory: ${baseline_mem}%"
    
    while [[ $QUEUE_INDEX -lt ${#CONVERSION_QUEUE[@]} || $CURRENT_JOBS -gt 0 ]]; do
        # Clean up completed jobs
        cleanup_completed_jobs
        
        # Calculate optimal job count
        local optimal_jobs=$(calculate_optimal_jobs)
        
        # Start new jobs if needed and possible
        # But be conservative after recent job terminations and consider resource proximity
        local recently_killed_file="/tmp/smart_convert_recently_killed"
        local baseline_resources_file="/tmp/smart_convert_baseline_resources"
        local current_time=$(date +%s)
        local last_kill_time=0
        
        if [[ -f "$recently_killed_file" ]]; then
            last_kill_time=$(cat "$recently_killed_file" 2>/dev/null || echo 0)
        fi
        
        local time_since_kill=$((current_time - last_kill_time))
        
        # Don't start new jobs if we killed one in the last 60 seconds
        if [[ $time_since_kill -lt 60 ]]; then
            log "INFO" "Recently killed job ${time_since_kill}s ago. Waiting before starting new jobs to prevent thrashing."
        else
            # Smart resource-based job addition with failure learning
            local can_add_jobs=true
            local failure_history_file="/tmp/smart_convert_failure_history"
            local single_job_baseline_file="/tmp/smart_convert_single_job_baseline"
            local current_cpu=$(get_cpu_usage)
            local current_mem=$(get_memory_usage)
            
            # If we have only 1 job running, record its average resource usage as the real baseline
            if [[ $CURRENT_JOBS -eq 1 && ! -f "$single_job_baseline_file" ]]; then
                echo "CPU:$current_cpu" > "$single_job_baseline_file"
                echo "MEM:$current_mem" >> "$single_job_baseline_file"
                log "INFO" "Recorded single-job baseline: CPU: ${current_cpu}%, Memory: ${current_mem}%"
            fi
            
            # Check if we've previously failed at similar resource levels
            if [[ -f "$failure_history_file" ]]; then
                while IFS=: read -r fail_cpu fail_mem; do
                    # Don't try again if current resources are within 10% of a previous failure
                    if [[ $current_cpu -ge $((fail_cpu - 10)) && $current_mem -ge $((fail_mem - 10)) ]]; then
                        log "INFO" "Current resources (CPU: ${current_cpu}%, MEM: ${current_mem}%) too close to previous failure point (CPU: ${fail_cpu}%, MEM: ${fail_mem}%). Skipping job addition."
                        can_add_jobs=false
                        break
                    fi
                done < "$failure_history_file"
            fi
            
            # If we have a single-job baseline, only add jobs if resources are manageable
            # BUT: Only apply this check if we already have jobs running
            # If no jobs are running, high resources are from other processes, not our conversions
            if [[ "$can_add_jobs" == "true" && -f "$single_job_baseline_file" && $CURRENT_JOBS -gt 0 ]]; then
                local single_cpu=$(grep "CPU:" "$single_job_baseline_file" | cut -d: -f2)
                local single_mem=$(grep "MEM:" "$single_job_baseline_file" | cut -d: -f2)
                
                # Only be conservative if current usage is significantly HIGHER than single-job baseline
                # This indicates system stress beyond what one job normally causes
                if [[ $current_cpu -gt $((single_cpu + 15)) || $current_mem -gt $((single_mem + 15)) ]]; then
                    log "INFO" "Current resources (CPU: ${current_cpu}%, MEM: ${current_mem}%) significantly higher than single-job baseline (CPU: ${single_cpu}%, MEM: ${single_mem}%). Being conservative."
                    can_add_jobs=false
                else
                    log "INFO" "Current resources (CPU: ${current_cpu}%, MEM: ${current_mem}%) within acceptable range of single-job baseline (CPU: ${single_cpu}%, MEM: ${single_mem}%). Can add jobs."
                fi
            elif [[ "$can_add_jobs" == "true" && $CURRENT_JOBS -eq 0 ]]; then
                # No jobs running - high resources are from other processes
                # Still be cautious but use different logic
                if [[ $current_cpu -gt 90 || $current_mem -gt 90 ]]; then
                    log "INFO" "System resources very high (CPU: ${current_cpu}%, MEM: ${current_mem}%) from other processes. Being cautious about starting conversions."
                    can_add_jobs=false
                else
                    log "INFO" "No conversion jobs running. Current resources (CPU: ${current_cpu}%, MEM: ${current_mem}%) from other processes - safe to start conversion."
                fi
            fi
            
            if [[ "$can_add_jobs" == "true" ]]; then
                while [[ $CURRENT_JOBS -lt $optimal_jobs && $QUEUE_INDEX -lt ${#CONVERSION_QUEUE[@]} ]]; do
                    start_conversion_job "${CONVERSION_QUEUE[$QUEUE_INDEX]}"
                    QUEUE_INDEX=$((QUEUE_INDEX + 1))
                done
            fi
        fi
        
        # Terminate excess jobs if current jobs exceed optimal count
        # But wait 30 seconds to confirm sustained overload before killing
        local overload_marker="/tmp/smart_convert_overload_start"
        local current_time=$(date +%s)
        
        if [[ $CURRENT_JOBS -gt $optimal_jobs ]]; then
            # Check if this is a new overload condition
            if [[ ! -f "$overload_marker" ]]; then
                echo "$current_time" > "$overload_marker"
                log "INFO" "System overload detected. Waiting 30 seconds to confirm sustained overload before terminating jobs."
                # Don't kill anything yet, just wait
            else
                # Overload condition exists - check how long it's been
                local overload_start_time=$(cat "$overload_marker" 2>/dev/null || echo "$current_time")
                local overload_duration=$((current_time - overload_start_time))
                
                if [[ $overload_duration -lt 30 ]]; then
                    log "INFO" "Overload duration: ${overload_duration}s. Waiting for sustained overload (30s) before terminating jobs."
                    # Don't kill anything yet
                else
                    # Sustained overload for 30+ seconds - now we can terminate
                    while [[ $CURRENT_JOBS -gt $optimal_jobs ]]; do
                        # CRITICAL: Never terminate if only one job is running
                        if [[ $CURRENT_JOBS -le 1 ]]; then
                            log "INFO" "Only one job running; will not terminate the last job. Waiting for resources to recover."
                            break
                        fi
            
            # Find and terminate the newest job (last in array) to preserve work on longer-running jobs
            if [[ ${#ACTIVE_PIDS[@]} -gt 0 ]]; then
                local newest_index=$((${#ACTIVE_PIDS[@]} - 1))
                local newest_pid="${ACTIVE_PIDS[$newest_index]}"
                if kill -0 "$newest_pid" 2>/dev/null; then
                    # Mark the job as killed so cleanup_completed_jobs knows to requeue it
                    local job_file="${ACTIVE_JOB_FILES[$newest_index]}"
                    local job_status_file="/tmp/job_status_$(basename "$job_file" | tr ' ' '_').status"
                    echo "KILLED" > "$job_status_file"
                    
                    # Record the kill time to prevent immediate restart thrashing
                    echo "$(date +%s)" > "/tmp/smart_convert_recently_killed"
                    
                    # Record the resource levels that caused this failure for future learning
                    local failure_cpu=$(get_cpu_usage)
                    local failure_mem=$(get_memory_usage)
                    echo "${failure_cpu}:${failure_mem}" >> "/tmp/smart_convert_failure_history"
                    
                    log "INFO" "Terminating newest job PID: $newest_pid to preserve work on longer-running jobs (reducing from $CURRENT_JOBS to $optimal_jobs jobs)"
                    log "INFO" "Recorded failure point: CPU: ${failure_cpu}%, Memory: ${failure_mem}% for future reference"
                    
                    # Kill the entire process group to ensure child processes (FFmpeg) are terminated
                    # First try gentle termination of the process group
                    pkill -TERM -P "$newest_pid" 2>/dev/null || true
                    kill -TERM "$newest_pid" 2>/dev/null || true
                    
                    # Wait a moment for graceful termination
                    sleep 3
                    
                    # Force kill any remaining processes in the group
                    pkill -KILL -P "$newest_pid" 2>/dev/null || true
                    kill -KILL "$newest_pid" 2>/dev/null || true
                fi
                # Clean up completed jobs to update counts
                cleanup_completed_jobs
                
                # Wait 30-45 seconds after killing a job to let system resources stabilize
                # before deciding if another job needs to be killed
                log "INFO" "Waiting 30 seconds for system resources to stabilize after job termination..."
                sleep 30
                
                # Re-check optimal jobs after waiting - system might have recovered
                local new_optimal_jobs=$(calculate_optimal_jobs)
                if [[ $CURRENT_JOBS -le $new_optimal_jobs ]]; then
                    log "INFO" "System resources recovered after job termination. No further reductions needed."
                    break
                fi
            else
                # Safety break if no active PIDs but CURRENT_JOBS > 0
                log "WARN" "CURRENT_JOBS=$CURRENT_JOBS but no active PIDs, resetting counter"
                CURRENT_JOBS=0
                break
            fi
        done
                fi
            fi
        else
            # No overload - clean up overload marker if it exists
            [[ -f "$overload_marker" ]] && rm -f "$overload_marker"
        fi
        
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
            log "INFO" "Terminating job PID: $pid and its children"
            # Kill child processes first (FFmpeg), then parent
            pkill -TERM -P "$pid" 2>/dev/null || true
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait for jobs to terminate
    sleep 5
    
    # Force kill if necessary
    for pid in "${ACTIVE_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log "WARN" "Force killing job PID: $pid and its children"
            pkill -KILL -P "$pid" 2>/dev/null || true
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    # Clean up temporary state files
    log "INFO" "Cleaning up temporary state files..."
    rm -f /tmp/smart_convert_* 2>/dev/null || true
    
    update_stats
    log "INFO" "Smart bulk converter shutdown complete"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

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
