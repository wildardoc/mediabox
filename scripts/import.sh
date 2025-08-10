#!/bin/bash

# Enhanced import.sh script for *arr applications
# Processes newly imported media files through media_update.py conversion system
# Supports Radarr (movies), Sonarr (TV shows), and Lidarr (music) webhook integration
# Based on official *arr environment variable specifications

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_UPDATE_SCRIPT="$SCRIPT_DIR/media_update.py"
LOG_DIR="$SCRIPT_DIR"
MAX_LOG_SIZE=10485760  # 10MB in bytes

# Enhanced logging function with timestamp and level
log_message() {
    local level="$1"
    local message="$2"
    local silent="${3:-false}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$LOG_DIR/import_$(date '+%Y%m%d').log"
    
    local log_entry="[$timestamp] [$level] $message"
    
    if [[ "$silent" == "true" ]]; then
        echo "$log_entry" >> "$log_file"
    else
        echo "$log_entry" | tee -a "$log_file"
    fi
    
    # Rotate log if it exceeds max size
    if [ -f "$log_file" ] && [ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        mv "$log_file" "${log_file}.old"
        echo "[$timestamp] [INFO] Log rotated due to size limit" > "$log_file"
    fi
}

# Validate required components
validate_environment() {
    local skip_validation="${1:-false}"
    
    if [[ "$skip_validation" == "true" ]]; then
        log_message "INFO" "Environment validation skipped for test event"
        return 0
    fi
    
    if [[ ! -f "$MEDIA_UPDATE_SCRIPT" ]]; then
        log_message "ERROR" "media_update.py not found at: $MEDIA_UPDATE_SCRIPT"
        exit 1
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_message "ERROR" "python3 not found in PATH"
        exit 1
    fi
    
    log_message "INFO" "Environment validation passed"
}

# Detect media type and extract relevant path information from *arr environment variables
detect_media_info() {
    local media_path=""
    local media_type=""
    local title=""
    local event_type=""
    local result_output=""
    
    # Check for Sonarr environment variables (TV Shows)
    # Handle both uppercase and lowercase formats
    if [[ -n "${Sonarr_EventType:-}" ]] || [[ -n "${sonarr_eventtype:-}" ]]; then
        event_type="${Sonarr_EventType:-${sonarr_eventtype:-}}"
        media_type="tv"
        title="${Sonarr_Series_Title:-${sonarr_series_title:-Unknown Series}}"
        
        # Handle different Sonarr event types
        case "$event_type" in
            "Download")
                media_path="${Sonarr_Series_Path:-${sonarr_series_path:-}}"
                log_message "INFO" "Sonarr Download event for series: $title" >&2
                if [[ -n "${Sonarr_EpisodeFile_Path:-${sonarr_episodefile_path:-}}" ]]; then
                    log_message "DEBUG" "Episode file: ${Sonarr_EpisodeFile_Path:-${sonarr_episodefile_path:-}}" >&2
                fi
                result_output="$media_type|$media_path|$title|$event_type"
                ;;
            "Test")
                log_message "INFO" "Sonarr test event received" >&2
                result_output="test|test_path|Sonarr Test|Test"
                ;;
            *)
                log_message "INFO" "Sonarr event '$event_type' - no processing required" >&2
                result_output="skip|skip|Sonarr Skip|$event_type"
                ;;
        esac
        
    # Check for Radarr environment variables (Movies)
    # Handle both uppercase and lowercase formats
    elif [[ -n "${Radarr_EventType:-}" ]] || [[ -n "${radarr_eventtype:-}" ]]; then
        event_type="${Radarr_EventType:-${radarr_eventtype:-}}"
        media_type="movie"
        title="${Radarr_Movie_Title:-${radarr_movie_title:-Unknown Movie}} (${Radarr_Movie_Year:-${radarr_movie_year:-Unknown}})"
        
        # Handle different Radarr event types
        case "$event_type" in
            "Download")
                media_path="${Radarr_Movie_Path:-${radarr_movie_path:-}}"
                log_message "INFO" "Radarr Download event for movie: $title" >&2
                if [[ -n "${Radarr_MovieFile_Path:-${radarr_moviefile_path:-}}" ]]; then
                    log_message "DEBUG" "Movie file: ${Radarr_MovieFile_Path:-${radarr_moviefile_path:-}}" >&2
                fi
                result_output="$media_type|$media_path|$title|$event_type"
                ;;
            "Test")
                log_message "INFO" "Radarr test event received" >&2
                result_output="test|test_path|Radarr Test|Test"
                ;;
            *)
                log_message "INFO" "Radarr event '$event_type' - no processing required" >&2
                result_output="skip|skip|Radarr Skip|$event_type"
                ;;
        esac
        
    # Check for Lidarr environment variables (Music)
    # Handle both uppercase and lowercase formats
    elif [[ -n "${Lidarr_EventType:-}" ]] || [[ -n "${lidarr_eventtype:-}" ]]; then
        event_type="${Lidarr_EventType:-${lidarr_eventtype:-}}"
        media_type="audio"
        title="${Lidarr_Artist_Name:-${lidarr_artist_name:-Unknown Artist}} - ${Lidarr_Album_Title:-${lidarr_album_title:-Unknown Album}}"
        
        # Handle different Lidarr event types
        case "$event_type" in
            "Download")
                media_path="${Lidarr_Artist_Path:-${lidarr_artist_path:-}}"
                log_message "INFO" "Lidarr Download event for album: $title" >&2
                if [[ -n "${Lidarr_TrackFile_Path:-${lidarr_trackfile_path:-}}" ]]; then
                    log_message "DEBUG" "Track file: ${Lidarr_TrackFile_Path:-${lidarr_trackfile_path:-}}" >&2
                fi
                result_output="$media_type|$media_path|$title|$event_type"
                ;;
            "Test")
                log_message "INFO" "Lidarr test event received" >&2
                result_output="test|test_path|Lidarr Test|Test"
                ;;
            *)
                log_message "INFO" "Lidarr event '$event_type' - no processing required" >&2
                result_output="skip|skip|Lidarr Skip|$event_type"
                ;;
        esac
        
    # Fallback to command-line arguments (legacy mode)
    elif [[ -n "$1" ]]; then
        media_path="$1"
        media_type="${2:-both}"
        title="Legacy: $(basename "$media_path")"
        event_type="Manual"
        log_message "INFO" "Legacy mode: processing $media_path as $media_type" >&2
        result_output="$media_type|$media_path|$title|$event_type"
        
    else
        log_message "ERROR" "No recognized *arr environment variables or arguments found" >&2
        log_message "DEBUG" "Available environment variables:" >&2
        env | grep -iE "(sonarr_|radarr_|lidarr_)" | sort | while read -r line; do
            log_message "DEBUG" "  $line" >&2
        done
        
        # Log all environment variables if no *arr variables found (for debugging)
        if ! env | grep -iqE "(sonarr_|radarr_|lidarr_)"; then
            log_message "DEBUG" "No *arr environment variables found. All environment variables:" >&2
            env | sort | while read -r line; do
                log_message "DEBUG" "  $line" >&2
            done
        fi
        result_output="error|error|Error|Error"
    fi
    
    # Validate media path exists (only for real processing, not for test/skip/error)
    # Parse the media_type from result_output to get the correct value
    local parsed_media_type=$(echo "$result_output" | cut -d'|' -f1)
    local parsed_media_path=$(echo "$result_output" | cut -d'|' -f2)
    
    if [[ "$parsed_media_type" != "test" && "$parsed_media_type" != "skip" && "$parsed_media_type" != "error" ]]; then
        if [[ -z "$parsed_media_path" ]]; then
            log_message "ERROR" "Media path is empty for $parsed_media_type event: $event_type" >&2
            result_output="error|error|Empty Path|$event_type"
        elif [[ ! -d "$parsed_media_path" ]] && [[ ! -f "$parsed_media_path" ]]; then
            log_message "ERROR" "Media path does not exist: $parsed_media_path" >&2
            result_output="error|error|Invalid Path: $parsed_media_path|$event_type"
        fi
    fi
    
    echo "$result_output"
}

# Execute media conversion
execute_conversion() {
    local media_type="$1"
    local media_path="$2"
    local title="$3"
    local event_type="$4"
    
    log_message "INFO" "Starting media conversion for $media_type: $title"
    log_message "INFO" "Processing path: $media_path"
    log_message "DEBUG" "Event type: $event_type"
    
    # Build media_update.py command based on media type
    local cmd_args=()
    
    case "$media_type" in
        "tv")
            # TV shows - focus on video conversion with subtitle preservation
            if [[ -d "$media_path" ]]; then
                cmd_args+=(--dir "$media_path")
            else
                cmd_args+=(--file "$media_path")
            fi
            cmd_args+=(--type video)
            ;;
        "movie")
            # Movies - comprehensive processing with audio and video
            if [[ -d "$media_path" ]]; then
                cmd_args+=(--dir "$media_path")
            else
                cmd_args+=(--file "$media_path")
            fi
            cmd_args+=(--type both)
            ;;
        "audio")
            # Music - audio-only conversion
            if [[ -d "$media_path" ]]; then
                cmd_args+=(--dir "$media_path")
            else
                cmd_args+=(--file "$media_path")
            fi
            cmd_args+=(--type audio)
            ;;
        "both")
            # Legacy mode - comprehensive processing
            if [[ -d "$media_path" ]]; then
                cmd_args+=(--dir "$media_path")
            else
                cmd_args+=(--file "$media_path")
            fi
            cmd_args+=(--type both)
            ;;
        *)
            log_message "ERROR" "Unknown media type: $media_type"
            return 1
            ;;
    esac
    
    # Log conversion parameters
    log_message "INFO" "Conversion parameters:"
    log_message "INFO" "  Media type: $media_type"
    log_message "INFO" "  Path: $media_path"
    log_message "INFO" "  Arguments: ${cmd_args[*]}"
    
    # Execute conversion
    log_message "INFO" "Executing: python3 $MEDIA_UPDATE_SCRIPT ${cmd_args[*]}"
    
    # Change to script directory to ensure relative paths work
    cd "$SCRIPT_DIR" || {
        log_message "ERROR" "Failed to change to script directory: $SCRIPT_DIR"
        return 1
    }
    
    if python3 "$MEDIA_UPDATE_SCRIPT" "${cmd_args[@]}"; then
        local exit_code=$?
        log_message "INFO" "Media conversion completed successfully for: $title"
        
        # Log additional success details based on media type
        case "$media_type" in
            "tv"|"movie")
                log_message "INFO" "Video conversion and subtitle preservation completed"
                ;;
            "audio")
                log_message "INFO" "Audio conversion to MP3 320kbps completed"
                ;;
            "both")
                log_message "INFO" "Comprehensive audio/video conversion completed"
                ;;
        esac
        
        return 0
    else
        local exit_code=$?
        log_message "ERROR" "Media conversion failed for: $title (exit code: $exit_code)"
        
        # Log failure context
        log_message "ERROR" "Failed command: python3 $MEDIA_UPDATE_SCRIPT ${cmd_args[*]}"
        log_message "ERROR" "Working directory: $(pwd)"
        log_message "ERROR" "Python version: $(python3 --version 2>&1 || echo 'Python3 not found')"
        
        return $exit_code
    fi
}

# Main execution
main() {
    log_message "INFO" "Starting *arr post-processing script"
    log_message "DEBUG" "Script directory: $SCRIPT_DIR"
    
    # Log detected event information
    local detected_event="${Sonarr_EventType:-${sonarr_eventtype:-${Radarr_EventType:-${radarr_eventtype:-${Lidarr_EventType:-${lidarr_eventtype:-Unknown}}}}}}"
    local detected_app="Unknown"
    
    if [[ -n "${Sonarr_EventType:-${sonarr_eventtype:-}}" ]]; then
        detected_app="Sonarr"
    elif [[ -n "${Radarr_EventType:-${radarr_eventtype:-}}" ]]; then
        detected_app="Radarr"
    elif [[ -n "${Lidarr_EventType:-${lidarr_eventtype:-}}" ]]; then
        detected_app="Lidarr"
    elif [[ -n "$1" ]]; then
        detected_app="Legacy"
        detected_event="Manual"
    fi
    
    log_message "INFO" "Detected application: $detected_app"
    log_message "INFO" "Event type: $detected_event"
    
    # Check for test event early to skip validation
    local is_test_event=false
    if [[ "$detected_event" == "Test" ]]; then
        is_test_event=true
    fi
    
    # Validate environment (skip for test events)
    validate_environment "$is_test_event"
    
    # Detect media information
    local media_info
    media_info=$(detect_media_info "$@")
    IFS='|' read -r media_type media_path title event_type <<< "$media_info"
    
    log_message "DEBUG" "Parsed media info: type=$media_type, path=$media_path, title=$title, event=$event_type"
    
    # Handle special cases
    if [[ "$media_type" == "test" ]]; then
        log_message "INFO" "Test event completed successfully"
        log_message "INFO" "Summary: $title completed"
        exit 0
    elif [[ "$media_type" == "skip" ]]; then
        log_message "INFO" "Event skipped - no processing required"
        log_message "INFO" "Summary: $title - no action needed"
        exit 0
    elif [[ "$media_type" == "error" ]]; then
        log_message "ERROR" "Error detected during environment parsing: $title"
        exit 1
    fi
    
    # Execute conversion based on detected media type
    if execute_conversion "$media_type" "$media_path" "$title" "$event_type"; then
        log_message "INFO" "Post-processing completed successfully"
        log_message "INFO" "Summary: $detected_app $event_type event for '$title' processed successfully"
        exit 0
    else
        log_message "ERROR" "Post-processing failed"
        log_message "ERROR" "Summary: $detected_app $event_type event for '$title' failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"