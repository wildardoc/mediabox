#!/bin/bash
# scripts/toggle-plex-notifications.sh
# Toggle Plex notifications on/off for media processing

set -euo pipefail

MEDIABOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$MEDIABOX_DIR/.env"

# Function to show current status
show_status() {
    if [[ -f "$ENV_FILE" ]]; then
        local current_setting=$(grep "^ENABLE_PLEX_NOTIFICATIONS=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "true")
        case "$current_setting" in
            true|True|TRUE|yes|Yes|YES|1|on|On|ON)
                echo "✅ Plex notifications are currently ENABLED"
                echo "   Media files will trigger Plex library scans after processing"
                return 0
                ;;
            *)
                echo "❌ Plex notifications are currently DISABLED"
                echo "   Media files will be processed but Plex won't be notified"
                return 1
                ;;
        esac
    else
        echo "⚠️  Configuration file not found: $ENV_FILE"
        echo "   Run ./mediabox.sh to set up the system first"
        exit 1
    fi
}

# Function to update setting
update_setting() {
    local new_value="$1"
    
    if grep -q "^ENABLE_PLEX_NOTIFICATIONS=" "$ENV_FILE"; then
        # Update existing setting
        sed -i "s/^ENABLE_PLEX_NOTIFICATIONS=.*/ENABLE_PLEX_NOTIFICATIONS=$new_value/" "$ENV_FILE"
    else
        # Add new setting
        echo "ENABLE_PLEX_NOTIFICATIONS=$new_value" >> "$ENV_FILE"
    fi
    
    echo "✅ Plex notifications setting updated to: $new_value"
}

# Main script logic
echo "Mediabox - Plex Notification Toggle"
echo "===================================="
echo

# Show current status and capture the return code
set +e  # Temporarily disable exit on error
show_status
current_enabled=$?
set -e  # Re-enable exit on error
echo

# Handle command line arguments
case "${1:-}" in
    --status)
        exit 0
        ;;
    --enable)
        if [[ "$current_enabled" -eq 0 ]]; then
            echo "Plex notifications are already enabled"
        else
            update_setting "true"
            echo
            echo "Updated status:"
            show_status > /dev/null
        fi
        exit 0
        ;;
    --disable)
        if [[ "$current_enabled" -eq 1 ]]; then
            echo "Plex notifications are already disabled"
        else
            update_setting "false"
            echo
            echo "Updated status:"
            show_status > /dev/null
        fi
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Toggle Plex notification settings for media processing."
        echo
        echo "OPTIONS:"
        echo "  --status      Show current notification status"
        echo "  --enable      Enable Plex notifications"
        echo "  --disable     Disable Plex notifications"
        echo "  --help, -h    Show this help message"
        echo
        echo "Interactive mode (no arguments): Prompt to toggle setting"
        echo
        echo "WHEN TO DISABLE:"
        echo "• Plex server is frequently offline"
        echo "• Processing large batches where notifications aren't needed immediately"
        echo "• Using external Plex scanning tools"
        echo "• Troubleshooting media processing issues"
        echo
        echo "NOTE: Disabling notifications means Plex won't automatically scan for"
        echo "new files after processing. You'll need to manually refresh your libraries."
        exit 0
        ;;
    "")
        # Interactive mode
        ;;
    *)
        echo "Error: Unknown option '$1'"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Interactive toggle
echo "Would you like to toggle the Plex notification setting?"
if [[ "$current_enabled" -eq 0 ]]; then
    echo "Current: ENABLED → Change to DISABLED"
    read -r -p "Disable Plex notifications? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        update_setting "false"
        echo
        echo "ℹ️  Plex notifications disabled. To re-enable later:"
        echo "   ./scripts/toggle-plex-notifications.sh --enable"
    else
        echo "No changes made"
    fi
else
    echo "Current: DISABLED → Change to ENABLED"  
    read -r -p "Enable Plex notifications? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        update_setting "true"
        echo
        echo "ℹ️  Plex notifications enabled. Media processing will trigger library scans."
    else
        echo "No changes made"
    fi
fi

echo
echo "Current status:"
show_status > /dev/null
