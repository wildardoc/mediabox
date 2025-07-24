#!/bin/bash
# filepath: /FileServer/docker/mediabox/postimport.sh

VENV_DIR="/Storage/docker/mediabox/.venv"
PY_SCRIPT="/FileServer/docker/mediabox/media_update.py"

# Get the path from Radarr/Sonarr
MEDIA_PATH="$1"

# Optionally, check if it's a file or directory
if [ -f "$MEDIA_PATH" ]; then
    python3 "$PY_SCRIPT" --file "$MEDIA_PATH"
elif [ -d "$MEDIA_PATH" ]; then
    python3 "$PY_SCRIPT" --dir "$MEDIA_PATH"
else
    echo "Invalid media path: $MEDIA_PATH"
    exit 1
fi