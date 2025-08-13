#!/bin/bash
set -euo pipefail

# ZFS Dataset Conversion Script for Mediabox
# Converts existing Docker service directories to ZFS datasets
# Usage: ./make_zfs.sh <service_name>
# Example: ./make_zfs.sh sonarr

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <service_name>"
    echo "Example: $0 sonarr"
    echo ""
    echo "Available services:"
    echo "  delugevpn, homer, lidarr, nzbget, overseerr"
    echo "  portainer, prowlarr, radarr, sonarr, tautulli, maintainerr"
    exit 1
fi

SERVICE="$1"

# Validate service exists
if [[ ! -d "$SERVICE" ]]; then
    echo "❌ Service directory '$SERVICE' does not exist"
    exit 1
fi

# Check if we're on ZFS
if ! command -v zfs >/dev/null 2>&1; then
    echo "❌ ZFS not available on this system"
    exit 1
fi

# Get current ZFS dataset for this directory
CURRENT_DIR=$(realpath "$PWD")
PARENT_DATASET=$(zfs list -H -o name,mountpoint | awk -v path="$CURRENT_DIR" '$2 == path || index(path, $2"/") == 1 {print $1; exit}')

if [[ -z "$PARENT_DATASET" ]]; then
    echo "❌ Current directory is not on a ZFS filesystem"
    exit 1
fi

echo "🔍 Converting $SERVICE directory to ZFS dataset..."
echo "   Parent dataset: $PARENT_DATASET"
echo "   Target dataset: $PARENT_DATASET/$SERVICE"

# Stop the Docker container
echo "⏹️  Stopping $SERVICE container..."
docker-compose stop "$SERVICE" || echo "⚠️  Container $SERVICE may not be running"

# Move existing directory to temporary location  
TEMP_DIR="temp_$SERVICE"
echo "📦 Moving existing data to temporary location..."
mv "$SERVICE" "$TEMP_DIR"

# Create ZFS dataset
echo "🗂️  Creating ZFS dataset..."
sudo zfs create "$PARENT_DATASET/$SERVICE"

# Set proper ownership
echo "👤 Setting ownership..."
sudo chown "$USER:$USER" "$SERVICE"

# Sync data back
echo "📋 Syncing data back from temporary directory..."
sudo rsync -avP "$TEMP_DIR/" "$SERVICE/"

# Clean up temporary directory
echo "🧹 Cleaning up temporary directory..."
rm -rf "$TEMP_DIR"

# Restart the Docker container
echo "▶️  Starting $SERVICE container..."
docker-compose start "$SERVICE"

echo "✅ Successfully converted $SERVICE to ZFS dataset!"
echo "   Dataset: $PARENT_DATASET/$SERVICE"
echo "   Mountpoint: $PWD/$SERVICE"

