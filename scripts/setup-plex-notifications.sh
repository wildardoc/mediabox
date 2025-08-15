#!/bin/bash
"""
Plex Notification Setup Script
==============================

This script helps configure Plex notifications for the Mediabox media processing system.
After transcoding is complete, media_update.py will notify Plex to scan for new files
instead of having *arr applications notify Plex immediately.

WORKFLOW OPTIMIZATION:
---------------------
OLD: Download → *arr notifies Plex immediately → Transcode (creates duplicates)
NEW: Download → Transcode → media_update.py notifies Plex (cleaner workflow)

This prevents Plex from processing large original files while transcoding is happening.
"""

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

echo "🎬 Mediabox Plex Notification Setup"
echo "===================================="
echo

# Check if Plex is running
echo "1. Checking Plex server status..."
if docker-compose ps plex | grep -q "Up"; then
    echo "✅ Plex container is running"
else
    echo "❌ Plex container is not running"
    echo "   Run: docker-compose up -d plex"
    exit 1
fi

# Test Plex connectivity
echo "2. Testing Plex connectivity..."
PLEX_URLS=("http://localhost:32400" "http://192.168.86.2:32400" "http://media.lan:32400")
PLEX_URL=""

for url in "${PLEX_URLS[@]}"; do
    echo "   Testing: $url"
    if curl -s -I --connect-timeout 5 --max-time 10 "$url/web" >/dev/null 2>&1; then
        echo "   ✅ $url is accessible"
        PLEX_URL="$url"
        break
    else
        echo "   ❌ $url is not accessible"
    fi
done

if [[ -z "$PLEX_URL" ]]; then
    echo "❌ No accessible Plex server found"
    echo "   Make sure Plex is running and accessible"
    exit 1
fi

# Get Plex token
echo "3. Plex authentication token setup..."
echo
echo "To get your Plex token:"
echo "1. Open Plex Web UI: $PLEX_URL/web"
echo "2. Sign in to your Plex account"
echo "3. Go to Settings → General → Network"
echo "4. Look for 'X-Plex-Token' in the browser developer tools (F12)"
echo "5. Or visit: https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/"
echo
read -p "Enter your Plex token: " PLEX_TOKEN

if [[ -z "$PLEX_TOKEN" ]]; then
    echo "❌ Plex token is required for notifications"
    exit 1
fi

# Test the token
echo "4. Testing Plex token..."
if curl -s -I --connect-timeout 10 "$PLEX_URL/library/sections?X-Plex-Token=$PLEX_TOKEN" | grep -q "200 OK"; then
    echo "✅ Plex token is valid"
else
    echo "❌ Plex token test failed"
    echo "   Please verify your token and try again"
    exit 1
fi

# Add configuration to .env file
echo "5. Updating configuration..."
if grep -q "PLEX_URL=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^PLEX_URL=.*|PLEX_URL=$PLEX_URL|" "$ENV_FILE"
else
    echo "PLEX_URL=$PLEX_URL" >> "$ENV_FILE"
fi

if grep -q "PLEX_TOKEN=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^PLEX_TOKEN=.*|PLEX_TOKEN=$PLEX_TOKEN|" "$ENV_FILE"
else
    echo "PLEX_TOKEN=$PLEX_TOKEN" >> "$ENV_FILE"
fi

echo "✅ Configuration saved to .env file"

# Instructions for *arr applications
cat << 'EOF'

🎯 NEXT STEPS - Optimize *arr Applications
==========================================

To complete the workflow optimization, you should disable immediate Plex 
notifications in your *arr applications:

SONARR (http://localhost:8989):
1. Settings → Connect
2. Find any "Plex Media Server" connections
3. Either delete them or disable "On Import/Upgrade" notifications
4. Keep the "Mediabox Processing" webhook enabled

RADARR (http://localhost:7878):
1. Settings → Connect  
2. Find any "Plex Media Server" connections
3. Either delete them or disable "On Import/Upgrade" notifications
4. Keep the "Mediabox Processing" webhook enabled

LIDARR (http://localhost:8686):
1. Settings → Connect
2. Find any "Plex Media Server" connections  
3. Either delete them or disable "On Import/Upgrade" notifications
4. Keep the "Mediabox Processing" webhook enabled

WORKFLOW AFTER CHANGES:
----------------------
✅ Download completes → Webhook triggers → media_update.py transcodes → Plex notified
❌ Download completes → *arr notifies Plex → Webhook triggers → Creates duplicates

This ensures Plex only processes the final optimized files!

EOF

echo "🎬 Plex notification setup complete!"
echo "   Test with: python3 scripts/media_update.py --file '/path/to/test/file.mkv' --type video"
