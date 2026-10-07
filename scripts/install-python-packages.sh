#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Custom initialization script to install Python packages
# This runs during container startup

echo "**** Installing Python packages for media processing ****"

# Install system-wide into the container's own Python (not the host-built
# /scripts/.venv - that venv is version-pinned to the host's Python and is not
# usable from inside a container running a different Python version).
# Check if packages are already installed to avoid reinstalling on every restart
if ! python3 -c "import ffmpeg, requests, plexapi" >/dev/null 2>&1; then
    echo "**** Installing packages from requirements.txt ****"
    pip3 install --break-system-packages -r /scripts/requirements.txt
    echo "**** Python packages installation completed ****"
else
    echo "**** Python packages already installed ****"
fi
