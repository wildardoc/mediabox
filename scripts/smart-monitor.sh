#!/bin/bash

# Smart Bulk Converter Monitor
# Real-time monitoring dashboard for the smart bulk conversion process

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATS_FILE="$SCRIPT_DIR/conversion_stats.json"
REFRESH_INTERVAL=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Clear screen and position cursor
clear_screen() {
    printf "\033[2J\033[H"
}

# Format time duration
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

# Get system resource usage with colors (ZFS-aware)
get_colored_system_stats() {
    # CPU usage
    local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/%id,//')
    local cpu_usage=$(echo "100 - $cpu_idle" | bc -l | cut -d. -f1)
    
    # ZFS-aware memory usage
    local mem_info=$(cat /proc/meminfo)
    local total_mem_kb=$(echo "$mem_info" | grep '^MemTotal:' | awk '{print $2}')
    local available_mem_kb=$(echo "$mem_info" | grep '^MemAvailable:' | awk '{print $2}')
    local mem_pressure_percent=$(echo "scale=0; ((($total_mem_kb - $available_mem_kb) * 100) / $total_mem_kb)" | bc)
    local available_gb=$(echo "scale=1; $available_mem_kb / 1024 / 1024" | bc)
    local total_gb=$(echo "scale=1; $total_mem_kb / 1024 / 1024" | bc)
    
    # ZFS ARC info if available
    local zfs_arc_info=""
    if [[ -f /proc/spl/kstat/zfs/arcstats ]]; then
        local arc_size_bytes=$(grep '^size' /proc/spl/kstat/zfs/arcstats | awk '{print $3}')
        local arc_gb=$(echo "scale=1; $arc_size_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")
        zfs_arc_info=" | ${CYAN}ZFS ARC: ${arc_gb}GB${NC}"
    fi
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    
    # Color code based on thresholds
    local cpu_color=$GREEN
    [[ $cpu_usage -gt 60 ]] && cpu_color=$YELLOW
    [[ $cpu_usage -gt 80 ]] && cpu_color=$RED
    
    # Use available memory for coloring (ZFS-friendly)
    local mem_color=$GREEN
    [[ $(echo "$available_gb < 8" | bc -l) -eq 1 ]] && mem_color=$YELLOW
    [[ $(echo "$available_gb < 4" | bc -l) -eq 1 ]] && mem_color=$RED
    
    local load_color=$GREEN
    [[ $(echo "$load_avg > 4" | bc -l) -eq 1 ]] && load_color=$YELLOW
    [[ $(echo "$load_avg > 8" | bc -l) -eq 1 ]] && load_color=$RED
    
    echo -e "${cpu_color}CPU: ${cpu_usage}%${NC} | ${mem_color}Available: ${available_gb}/${total_gb} GB${NC} | ${load_color}Load: ${load_avg}${NC}${zfs_arc_info}"
}

# Check active processes
get_active_processes() {
    local plex_count=$(pgrep -f "PlexTranscoder\|plex.*ffmpeg" | wc -l)
    local import_count=$(pgrep -f "import\.sh\|media_update\.py" | wc -l)
    local ffmpeg_count=$(pgrep -f ffmpeg | wc -l)
    
    echo "Active Processes:"
    [[ $plex_count -gt 0 ]] && echo -e "  ${PURPLE}Plex Transcoding: $plex_count${NC}"
    [[ $import_count -gt 0 ]] && echo -e "  ${YELLOW}Import/Download: $import_count${NC}"
    [[ $ffmpeg_count -gt 0 ]] && echo -e "  ${BLUE}FFmpeg Total: $ffmpeg_count${NC}"
    
    if [[ $plex_count -eq 0 && $import_count -eq 0 && $ffmpeg_count -eq 0 ]]; then
        echo -e "  ${GREEN}None detected${NC}"
    fi
}

# Display conversion statistics
show_conversion_stats() {
    if [[ ! -f "$STATS_FILE" ]]; then
        echo -e "${YELLOW}No conversion statistics available${NC}"
        echo "Start smart-bulk-convert.sh to begin monitoring"
        return
    fi
    
    # Parse JSON stats (basic parsing)
    local start_time=$(grep '"start_time"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    local current_time=$(grep '"current_time"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    local total_processed=$(grep '"total_processed"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    local total_errors=$(grep '"total_errors"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    local current_jobs=$(grep '"current_jobs"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    local queue_remaining=$(grep '"queue_remaining"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    local processing_rate=$(grep '"processing_rate_per_hour"' "$STATS_FILE" | cut -d':' -f2 | tr -d ' ,')
    
    local elapsed_seconds=$((current_time - start_time))
    local elapsed_formatted=$(format_duration $elapsed_seconds)
    
    # Calculate ETA
    local eta_formatted="Unknown"
    if [[ $(echo "$processing_rate > 0" | bc -l) -eq 1 && $queue_remaining -gt 0 ]]; then
        local eta_hours=$(echo "scale=2; $queue_remaining / $processing_rate" | bc -l)
        local eta_seconds=$(echo "$eta_hours * 3600" | bc -l | cut -d. -f1)
        eta_formatted=$(format_duration $eta_seconds)
    fi
    
    echo -e "${CYAN}=== CONVERSION STATISTICS ===${NC}"
    echo -e "Runtime: ${GREEN}$elapsed_formatted${NC}"
    echo -e "Processed: ${GREEN}$total_processed${NC} files"
    [[ $total_errors -gt 0 ]] && echo -e "Errors: ${RED}$total_errors${NC} files"
    echo -e "Active Jobs: ${BLUE}$current_jobs${NC}"
    echo -e "Queue Remaining: ${YELLOW}$queue_remaining${NC} files"
    echo -e "Processing Rate: ${PURPLE}$processing_rate${NC} files/hour"
    echo -e "Estimated Completion: ${CYAN}$eta_formatted${NC}"
    
    # Progress bar
    local total_files=$((total_processed + queue_remaining))
    if [[ $total_files -gt 0 ]]; then
        local progress_percent=$(echo "scale=0; ($total_processed * 100) / $total_files" | bc)
        local bar_length=40
        local filled_length=$(echo "scale=0; ($progress_percent * $bar_length) / 100" | bc)
        
        printf "Progress: ["
        for ((i=0; i<filled_length; i++)); do printf "${GREEN}█${NC}"; done
        for ((i=filled_length; i<bar_length; i++)); do printf "░"; done
        printf "] ${progress_percent}%%\n"
    fi
}

# Show recent log entries
show_recent_logs() {
    local log_pattern="smart_bulk_convert_*.log"
    local latest_log=$(ls -t $SCRIPT_DIR/$log_pattern 2>/dev/null | head -1)
    
    if [[ -n "$latest_log" ]]; then
        echo -e "\n${CYAN}=== RECENT LOG ENTRIES ===${NC}"
        tail -n 10 "$latest_log" | while read -r line; do
            if [[ "$line" =~ ERROR ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ "$line" =~ WARN ]]; then
                echo -e "${YELLOW}$line${NC}"
            elif [[ "$line" =~ INFO ]]; then
                echo -e "${GREEN}$line${NC}"
            else
                echo "$line"
            fi
        done
    fi
}

# Main monitoring loop
monitor() {
    while true; do
        clear_screen
        
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                        SMART BULK CONVERTER MONITOR                         ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        
        # System resources
        echo -e "${CYAN}=== SYSTEM RESOURCES ===${NC}"
        get_colored_system_stats
        echo
        
        # Active processes
        get_active_processes
        echo
        
        # Conversion statistics
        show_conversion_stats
        
        # Recent logs
        show_recent_logs
        
        echo
        echo -e "${BLUE}Press Ctrl+C to exit monitor${NC} | Refreshing every ${REFRESH_INTERVAL}s | $(date)"
        
        sleep $REFRESH_INTERVAL
    done
}

# Usage
usage() {
    cat << EOF
Smart Bulk Converter Monitor

USAGE: $0 [OPTIONS]

OPTIONS:
    -i, --interval N     Refresh interval in seconds (default: $REFRESH_INTERVAL)
    -h, --help          Show this help

This monitor displays:
- Real-time system resource usage
- Active media processes (Plex, downloads, imports)
- Conversion progress and statistics
- Recent log entries
- ETA for completion

Run this in a separate terminal while smart-bulk-convert.sh is running.

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Check for required tools
for tool in bc top free; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: Required tool '$tool' not found" >&2
        exit 1
    fi
done

# Start monitoring
trap 'echo -e "\n${GREEN}Monitor stopped${NC}"; exit 0' SIGINT SIGTERM
monitor
