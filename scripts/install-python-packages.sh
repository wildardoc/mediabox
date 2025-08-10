#!/bin/bash

# Custom initialization script to install Python packages
# This runs during container startup

echo "**** Installing Python packages for media processing ****"

# Check if packages are already installed to avoid reinstalling on every restart
if ! python3 -c "import ffmpeg" >/dev/null 2>&1; then
    echo "**** Installing ffmpeg-python and future packages ****"
    pip3 install --break-system-packages ffmpeg-python==0.2.0 future==1.0.0
    echo "**** Python packages installation completed ****"
else
    echo "**** Python packages already installed ****"
fi
