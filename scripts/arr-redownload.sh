#!/bin/bash

# Automated Sonarr/Radarr Re-download Script
# Triggers searches for corrupted files via API, then deletes them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration - UPDATE THESE VALUES
SONARR_URL="http://media.lan:8989"
SONARR_API_KEY="dc2d2d551dba46248b80411b7b221e37"  # Get from: Settings → General → Security → API Key

RADARR_URL="http://media.lan:7878"
RADARR_API_KEY="607fe110c0f54acebac247d94a58ab97"  # Get from: Settings → General → Security → API Key

# Input file with corrupted files
CORRUPTED_FILES_LIST=""

# Options
DELETE_FILES=false  # Set to true to auto-delete after queueing searches
DRY_RUN=true       # Set to false to actually execute

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 <corrupted_files_list.txt> [options]

Triggers Sonarr/Radarr searches for corrupted media files via API.

Options:
    --delete        Delete files after queueing searches
    --no-dry-run    Actually execute (default is dry-run mode)
    --help          Show this help message

Configuration:
    Edit this script to set your Sonarr/Radarr URLs and API keys.

Example:
    $0 library_no_audio_20251112_184357.txt
    $0 library_no_audio_20251112_184357.txt --delete --no-dry-run

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete)
            DELETE_FILES=true
            shift
            ;;
        --no-dry-run)
            DRY_RUN=false
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$CORRUPTED_FILES_LIST" ]]; then
                CORRUPTED_FILES_LIST="$1"
            else
                echo "Unknown option: $1"
                usage
            fi
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$CORRUPTED_FILES_LIST" ]]; then
    echo -e "${RED}Error: No input file specified${NC}"
    usage
fi

if [[ ! -f "$CORRUPTED_FILES_LIST" ]]; then
    echo -e "${RED}Error: File not found: $CORRUPTED_FILES_LIST${NC}"
    exit 1
fi

# Check API keys
if [[ -z "$SONARR_API_KEY" || -z "$RADARR_API_KEY" ]]; then
    echo -e "${YELLOW}Warning: API keys not configured!${NC}"
    echo "Please edit this script and set:"
    echo "  SONARR_API_KEY (line ~12)"
    echo "  RADARR_API_KEY (line ~15)"
    echo ""
    echo "Get API keys from: Settings → General → Security → API Key"
    exit 1
fi

echo "========================================="
echo "Sonarr/Radarr Corrupted File Handler"
echo "========================================="
echo "Input file:    $CORRUPTED_FILES_LIST"
echo "Delete files:  $DELETE_FILES"
echo "Dry run:       $DRY_RUN"
echo ""

# Count files
total_files=$(wc -l < "$CORRUPTED_FILES_LIST")
echo "Found $total_files corrupted files to process"
echo ""

# Counters
tv_files=0
movie_files=0
tv_searches_queued=0
movie_searches_queued=0
files_deleted=0
errors=0

# Function to get series ID from path
get_series_info() {
    local file_path="$1"
    local series_name=""
    
    # Extract series name from path: /FileServer/media/tv/Series Name/Season XX/...
    if [[ "$file_path" =~ /FileServer/media/tv/([^/]+)/Season\ ([0-9]+)/.*[Ss]([0-9]+)[Ee]([0-9]+) ]]; then
        series_name="${BASH_REMATCH[1]}"
        season_num="${BASH_REMATCH[2]}"
        episode_num="${BASH_REMATCH[4]}"
        
        # Query Sonarr API for series
        local response
        response=$(curl -s -X GET "$SONARR_URL/api/v3/series" \
            -H "X-Api-Key: $SONARR_API_KEY" 2>/dev/null || echo "")
        
        if [[ -z "$response" ]]; then
            echo "error:API call failed"
            return 1
        fi
        
        # Find series by matching title (case insensitive)
        local series_id
        series_id=$(echo "$response" | jq -r --arg name "$series_name" \
            '.[] | select(.title | ascii_downcase == ($name | ascii_downcase)) | .id' | head -1)
        
        if [[ -z "$series_id" || "$series_id" == "null" ]]; then
            echo "error:Series not found in Sonarr"
            return 1
        fi
        
        # Get episode ID
        local episode_response
        episode_response=$(curl -s -X GET "$SONARR_URL/api/v3/episode?seriesId=$series_id" \
            -H "X-Api-Key: $SONARR_API_KEY" 2>/dev/null || echo "")
        
        local episode_id
        episode_id=$(echo "$episode_response" | jq -r \
            --arg season "$season_num" --arg episode "$episode_num" \
            '.[] | select(.seasonNumber == ($season | tonumber) and .episodeNumber == ($episode | tonumber)) | .id' | head -1)
        
        if [[ -z "$episode_id" || "$episode_id" == "null" ]]; then
            echo "error:Episode not found"
            return 1
        fi
        
        echo "$series_id:$episode_id:$series_name S${season_num}E${episode_num}"
        return 0
    else
        echo "error:Could not parse series info from path"
        return 1
    fi
}

# Function to get movie ID from path
get_movie_info() {
    local file_path="$1"
    local movie_name=""
    
    # Extract movie name from path: /FileServer/media/movies/Movie Name (Year)/...
    if [[ "$file_path" =~ /FileServer/media/movies/([^/]+)/.*\.(mp4|mkv|avi|m4v) ]]; then
        movie_name="${BASH_REMATCH[1]}"
        
        # Query Radarr API for movie
        local response
        response=$(curl -s -X GET "$RADARR_URL/api/v3/movie" \
            -H "X-Api-Key: $RADARR_API_KEY" 2>/dev/null || echo "")
        
        if [[ -z "$response" ]]; then
            echo "error:API call failed"
            return 1
        fi
        
        # Find movie by matching folder name
        local movie_id
        movie_id=$(echo "$response" | jq -r --arg folder "$movie_name" \
            '.[] | select(.path | contains($folder)) | .id' | head -1)
        
        if [[ -z "$movie_id" || "$movie_id" == "null" ]]; then
            echo "error:Movie not found in Radarr"
            return 1
        fi
        
        echo "$movie_id:$movie_name"
        return 0
    else
        echo "error:Could not parse movie info from path"
        return 1
    fi
}

# Function to trigger episode search
trigger_episode_search() {
    local episode_id="$1"
    local display_name="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY RUN]${NC} Would search for: $display_name (Episode ID: $episode_id)"
        return 0
    fi
    
    local response
    response=$(curl -s -X POST "$SONARR_URL/api/v3/command" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"EpisodeSearch\",\"episodeIds\":[$episode_id]}" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        echo -e "${GREEN}✓${NC} Queued search: $display_name"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to queue search: $display_name"
        return 1
    fi
}

# Function to trigger movie search
trigger_movie_search() {
    local movie_id="$1"
    local display_name="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY RUN]${NC} Would search for: $display_name (Movie ID: $movie_id)"
        return 0
    fi
    
    local response
    response=$(curl -s -X POST "$RADARR_URL/api/v3/command" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"MoviesSearch\",\"movieIds\":[$movie_id]}" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        echo -e "${GREEN}✓${NC} Queued search: $display_name"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to queue search: $display_name"
        return 1
    fi
}

# Process each file
echo "Processing files..."
echo ""

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    
    # Skip files that have ERROR prefix or .tmp extension (actively being transcoded)
    if [[ "$file" =~ ^ERROR: ]] || [[ "$file" =~ \.tmp\.(mp4|mkv|avi|m4v)$ ]]; then
        echo -e "${YELLOW}Skipping:${NC} $file (temporary/in-progress file)"
        echo ""
        continue
    fi
    
    # Remove ERROR: prefix if present (for display)
    file="${file#ERROR: }"
    
    # Determine if TV or Movie
    if [[ "$file" =~ /FileServer/media/tv/ ]]; then
        # TV Show
        tv_files=$((tv_files + 1))
        
        echo -e "${YELLOW}TV:${NC} $file"
        
        # Get series info
        info=$(get_series_info "$file")
        
        if [[ "$info" =~ ^error: ]]; then
            echo -e "  ${RED}✗${NC} ${info#error:}"
            errors=$((errors + 1))
        else
            IFS=: read -r series_id episode_id display_name <<< "$info"
            
            # Trigger search
            if trigger_episode_search "$episode_id" "$display_name"; then
                tv_searches_queued=$((tv_searches_queued + 1))
                
                # Delete file if requested
                if [[ "$DELETE_FILES" == "true" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "  ${BLUE}[DRY RUN]${NC} Would delete: $file"
                    else
                        if rm -f "$file" 2>/dev/null; then
                            echo -e "  ${GREEN}✓${NC} Deleted file"
                            files_deleted=$((files_deleted + 1))
                        else
                            echo -e "  ${RED}✗${NC} Failed to delete file"
                        fi
                    fi
                fi
            else
                errors=$((errors + 1))
            fi
        fi
        
    elif [[ "$file" =~ /FileServer/media/movies/ ]]; then
        # Movie
        movie_files=$((movie_files + 1))
        
        echo -e "${YELLOW}Movie:${NC} $file"
        
        # Get movie info
        info=$(get_movie_info "$file")
        
        if [[ "$info" =~ ^error: ]]; then
            echo -e "  ${RED}✗${NC} ${info#error:}"
            errors=$((errors + 1))
        else
            IFS=: read -r movie_id display_name <<< "$info"
            
            # Trigger search
            if trigger_movie_search "$movie_id" "$display_name"; then
                movie_searches_queued=$((movie_searches_queued + 1))
                
                # Delete file if requested
                if [[ "$DELETE_FILES" == "true" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "  ${BLUE}[DRY RUN]${NC} Would delete: $file"
                    else
                        if rm -f "$file" 2>/dev/null; then
                            echo -e "  ${GREEN}✓${NC} Deleted file"
                            files_deleted=$((files_deleted + 1))
                        else
                            echo -e "  ${RED}✗${NC} Failed to delete file"
                        fi
                    fi
                fi
            else
                errors=$((errors + 1))
            fi
        fi
    else
        echo -e "${RED}Unknown:${NC} $file (not in /tv or /movies)"
        errors=$((errors + 1))
    fi
    
    echo ""
    
done < "$CORRUPTED_FILES_LIST"

# Summary
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo "Total files processed:     $total_files"
echo "  TV shows:                $tv_files"
echo "  Movies:                  $movie_files"
echo ""
echo "Searches queued:"
echo "  TV episodes:             $tv_searches_queued"
echo "  Movies:                  $movie_searches_queued"
echo ""
if [[ "$DELETE_FILES" == "true" ]]; then
    echo "Files deleted:             $files_deleted"
fi
echo "Errors:                    $errors"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}DRY RUN MODE - No changes were made${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "To execute for real, run with: --no-dry-run"
    echo ""
fi

echo "Check Sonarr/Radarr Queue for download progress"
echo "  Sonarr: $SONARR_URL/queue"
echo "  Radarr: $RADARR_URL/queue"
