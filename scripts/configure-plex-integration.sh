#!/bin/bash
#
# Configure Plex Integration for Standalone Media Converter
# Updates the mediabox_config.json with Plex settings
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CONFIG_FILE="$HOME/.local/share/mediabox-converter/mediabox_config.json"
ENV_FILE="$HOME/.local/share/mediabox-converter/.env"

echo -e "${GREEN}=== Plex Integration Configuration ===${NC}\n"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
    echo "Please run install-media-converter.sh first."
    exit 1
fi

# Get Plex URL
echo -e "${YELLOW}Enter Plex Server URL${NC}"
echo "Examples: http://media.lan:32400 or http://192.168.1.100:32400"
read -p "Plex URL: " PLEX_URL

# Validate URL format
if [[ ! "$PLEX_URL" =~ ^https?:// ]]; then
    echo -e "${RED}Error: URL must start with http:// or https://${NC}"
    exit 1
fi

# Get Plex Token
echo -e "\n${YELLOW}Plex Authentication${NC}"
echo "Choose authentication method:"
echo "  1. Enter Plex username/password (recommended - auto-retrieve token)"
echo "  2. Enter existing Plex token manually"
read -p "Choice [1/2]: " AUTH_CHOICE

PLEX_TOKEN=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$AUTH_CHOICE" == "1" ]]; then
    echo -e "\n${YELLOW}Retrieving Plex token automatically...${NC}"
    echo "You will be prompted for your Plex credentials."
    echo ""
    
    read -p "Plex username (email): " PLEX_USERNAME
    
    if [[ -z "$PLEX_USERNAME" ]]; then
        echo -e "${RED}Error: Username is required${NC}"
        exit 1
    fi
    
    # Call get-plex-token.py which will prompt for password securely
    # Capture the token from the output
    TOKEN_OUTPUT=$(python3 "$SCRIPT_DIR/get-plex-token.py" --url "$PLEX_URL" --username "$PLEX_USERNAME" 2>&1)
    
    PLEX_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -oP '(?<=Token: ).*' | head -1)
    
    if [[ -z "$PLEX_TOKEN" ]]; then
        echo -e "${RED}Error: Failed to retrieve Plex token${NC}"
        echo "Output from token retrieval:"
        echo "$TOKEN_OUTPUT"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Token retrieved successfully${NC}"
else
    echo -e "\n${YELLOW}Enter Plex Token${NC}"
    echo "To find your token manually:"
    echo "  1. Open Plex Web (Settings → Network → Show Advanced)"
    echo "  2. Look for X-Plex-Token parameter"
    read -p "Plex Token: " PLEX_TOKEN
    
    if [[ -z "$PLEX_TOKEN" ]]; then
        echo -e "${RED}Error: Plex token cannot be empty${NC}"
        exit 1
    fi
fi

# Get path mappings
echo -e "\n${YELLOW}Configure Path Mappings${NC}"
echo "These map paths on THIS machine to paths in Plex."
echo ""

# Get current library paths from config
TV_PATH=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['library_dirs']['tv'])" 2>/dev/null || echo "")
MOVIES_PATH=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['library_dirs']['movies'])" 2>/dev/null || echo "")
MUSIC_PATH=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['library_dirs']['music'])" 2>/dev/null || echo "")

if [[ -z "$TV_PATH" ]]; then
    echo -e "${RED}Error: No library paths configured. Please configure library directories first.${NC}"
    exit 1
fi

echo -e "Your converter sees TV at: ${GREEN}$TV_PATH${NC}"
echo "How does Plex see this path?"
echo "Examples: /data/tv, /mnt/media/tv, /Storage/media/tv"
echo "Common: If Plex is on different server, often /data/tv or /Storage/media/tv"
read -p "Plex TV path: " PLEX_TV_PATH

if [[ -z "$PLEX_TV_PATH" && -n "$TV_PATH" ]]; then
    echo -e "${YELLOW}Using same path as converter: $TV_PATH${NC}"
    PLEX_TV_PATH="$TV_PATH"
fi

echo -e "\nYour converter sees Movies at: ${GREEN}$MOVIES_PATH${NC}"
read -p "Plex Movies path: " PLEX_MOVIES_PATH

if [[ -z "$PLEX_MOVIES_PATH" && -n "$MOVIES_PATH" ]]; then
    echo -e "${YELLOW}Using same path as converter: $MOVIES_PATH${NC}"
    PLEX_MOVIES_PATH="$MOVIES_PATH"
fi

echo -e "\nYour converter sees Music at: ${GREEN}$MUSIC_PATH${NC}"
read -p "Plex Music path: " PLEX_MUSIC_PATH

if [[ -z "$PLEX_MUSIC_PATH" && -n "$MUSIC_PATH" ]]; then
    echo -e "${YELLOW}Using same path as converter: $MUSIC_PATH${NC}"
    PLEX_MUSIC_PATH="$MUSIC_PATH"
fi

# Update config file
echo -e "\n${YELLOW}Updating configuration...${NC}"

python3 << EOF
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

config['plex_integration']['url'] = '$PLEX_URL'
config['plex_integration']['token'] = '$PLEX_TOKEN'
config['plex_integration']['path_mappings']['tv'] = '$PLEX_TV_PATH'
config['plex_integration']['path_mappings']['movies'] = '$PLEX_MOVIES_PATH'
config['plex_integration']['path_mappings']['music'] = '$PLEX_MUSIC_PATH'

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print("✓ Configuration updated")
EOF

# Update .env file with Plex settings
if [[ ! -f "$ENV_FILE" ]]; then
    touch "$ENV_FILE"
fi

# Remove old Plex settings if they exist
sed -i '/^PLEX_URL=/d' "$ENV_FILE" 2>/dev/null || true
sed -i '/^PLEX_TOKEN=/d' "$ENV_FILE" 2>/dev/null || true

# Add new settings
cat >> "$ENV_FILE" << EOF

# Plex Integration
PLEX_URL=$PLEX_URL
PLEX_TOKEN=$PLEX_TOKEN
EOF

echo -e "${GREEN}✓ .env file updated${NC}"

# Test connection
echo -e "\n${YELLOW}Testing Plex connection...${NC}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Plex-Token: $PLEX_TOKEN" "$PLEX_URL/library/sections" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}✓ Successfully connected to Plex!${NC}"
    
    # Show available libraries
    echo -e "\n${YELLOW}Available Plex Libraries:${NC}"
    curl -s -H "X-Plex-Token: $PLEX_TOKEN" "$PLEX_URL/library/sections" | \
        python3 -c "import sys, xml.etree.ElementTree as ET; root=ET.parse(sys.stdin).getroot(); [print(f\"  - {d.get('title')} ({d.get('type')}): {d.get('key')}\") for d in root.findall('.//Directory')]" 2>/dev/null || true
else
    echo -e "${RED}✗ Failed to connect to Plex (HTTP $HTTP_CODE)${NC}"
    echo "Please verify:"
    echo "  - Plex server is running and accessible"
    echo "  - URL is correct: $PLEX_URL"
    echo "  - Token is valid"
    exit 1
fi

echo -e "\n${GREEN}=== Configuration Complete! ===${NC}"
echo ""
echo "Configuration saved to: $CONFIG_FILE"
echo "Environment saved to: $ENV_FILE"
echo ""
echo "The media converter will now automatically trigger Plex library scans after conversion."

exit 0
