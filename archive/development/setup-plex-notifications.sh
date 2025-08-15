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

# Check if Plex configuration already exists
echo "1. Checking existing Plex configuration..."
if [[ -f "$ENV_FILE" ]]; then
    EXISTING_PLEX_URL=$(grep "^PLEX_URL=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")
    EXISTING_PLEX_TOKEN=$(grep "^PLEX_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")
    
    if [[ -n "$EXISTING_PLEX_URL" && -n "$EXISTING_PLEX_TOKEN" ]]; then
        echo "✅ Found existing Plex configuration:"
        echo "   URL: $EXISTING_PLEX_URL"
        echo "   Token: ${EXISTING_PLEX_TOKEN:0:10}... (masked)"
        
        # Test existing configuration
        echo "2. Testing existing Plex configuration..."
        if curl -s -I --connect-timeout 10 "$EXISTING_PLEX_URL/library/sections?X-Plex-Token=$EXISTING_PLEX_TOKEN" | grep -q "200 OK"; then
            echo "✅ Existing Plex configuration is working!"
            echo "   No setup needed - using existing configuration"
            PLEX_URL="$EXISTING_PLEX_URL"
            PLEX_TOKEN="$EXISTING_PLEX_TOKEN"
            SKIP_SETUP=true
        else
            echo "❌ Existing configuration test failed, setting up fresh..."
            SKIP_SETUP=false
        fi
    else
        echo "ℹ️  No existing Plex configuration found"
        SKIP_SETUP=false
    fi
else
    echo "ℹ️  No .env file found"
    SKIP_SETUP=false
fi

if [[ "$SKIP_SETUP" != "true" ]]; then
    # Check if Plex is running
    echo "3. Checking Plex server status..."
if docker-compose ps plex | grep -q "Up"; then
    echo "✅ Plex container is running"
else
    echo "❌ Plex container is not running"
    echo "   Run: docker-compose up -d plex"
    exit 1
fi

# Test Plex connectivity
echo "4. Testing Plex connectivity..."
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
echo "5. Plex authentication token setup..."
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
echo "6. Testing Plex token..."
if curl -s -I --connect-timeout 10 "$PLEX_URL/library/sections?X-Plex-Token=$PLEX_TOKEN" | grep -q "200 OK"; then
    echo "✅ Plex token is valid"
else
    echo "❌ Plex token test failed"
    echo "   Please verify your token and try again"
    exit 1
fi

# Add configuration to .env file
echo "7. Updating configuration..."
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

fi  # End of SKIP_SETUP check

# Instructions for *arr applications
cat << 'EOF'

🎯 NEXT STEPS - Optimize *arr Applications
==========================================

✅ Plex notification system is configured and tested!

AUTOMATED TOKEN RETRIEVAL (for new setups):
-------------------------------------------
If you need to get a new token or set up on a different system:

   # Method 1: Test connection first
   python3 scripts/get-plex-token.py --test-only --url http://your-server:32400
   
   # Method 2: Get token with MyPlex account  
   python3 scripts/get-plex-token.py --url http://your-server:32400 --username your_username
   
   # Method 3: Comprehensive testing
   python3 scripts/test-plex-comprehensive.py

MANUAL *arr APPLICATION CONFIGURATION:
--------------------------------------
To complete the workflow optimization, disable immediate Plex 
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

TESTING THE COMPLETE WORKFLOW:
------------------------------
   # Test Plex notifications work
   python3 scripts/test-plex-notification.py
   
   # Test with real media file
   python3 scripts/media_update.py --file '/path/to/test/file.mkv' --type video
   
   # Check logs for notification success
   tail -f scripts/media_update_*.log

WORKFLOW AFTER CHANGES:
-----------------------
✅ Download completes → Webhook triggers → media_update.py transcodes → Plex notified
❌ Download completes → *arr notifies Plex → Webhook triggers → Creates duplicates

This ensures Plex only processes the final optimized files!

EOF

echo "🎬 Plex notification setup complete!"
echo "   Test with: python3 scripts/media_update.py --file '/path/to/test/file.mkv' --type video"
