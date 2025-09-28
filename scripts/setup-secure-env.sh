#!/bin/bash
# scripts/setup-secure-env.sh
# Create secure credential management

set -euo pipefail

MEDIABOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$HOME/.mediabox"
SECURE_ENV="$ENV_DIR/credentials.env"

# Check if running in auto mode (called from mediabox.sh)
AUTO_MODE=false
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

echo "Setting up secure credential storage..."

# Create secure directory
mkdir -p "$ENV_DIR"
chmod 700 "$ENV_DIR"  # Only user can access

# Get credentials based on mode
if [[ "$AUTO_MODE" == true ]]; then
    # Auto mode: use environment variables passed from mediabox.sh
    if [[ -z "${PIAUNAME:-}" ]] || [[ -z "${PIAPASS:-}" ]] || [[ -z "${CPDAEMONUN:-}" ]] || [[ -z "${CPDAEMONPASS:-}" ]]; then
        echo "Error: Required environment variables not set for auto mode"
        exit 1
    fi
    pia_username="$PIAUNAME"
    pia_password="$PIAPASS" 
    daemon_user="$CPDAEMONUN"
    daemon_pass="$CPDAEMONPASS"
    
    # Optional Plex credentials
    plex_username="${PLEX_USERNAME:-}"
    plex_password="${PLEX_PASSWORD:-}"
    
    echo "Using credentials provided by mediabox.sh"
    if [[ -n "$plex_username" ]]; then
        echo "Including Plex credentials"
    fi
else
    # Interactive mode: prompt for credentials, preserving existing values
    echo "Creating secure credentials file..."
    
    # Load existing credentials if file exists
    existing_pia_username=""
    existing_pia_password=""
    existing_daemon_user=""
    existing_daemon_pass=""
    existing_plex_username=""
    existing_plex_password=""
    
    if [[ -f "$SECURE_ENV" ]]; then
        echo "📋 Existing credentials file found!"
        echo "   For each setting, press Enter to keep existing value or type new value."
        echo ""
        
        # Load existing values
        existing_pia_username=$(grep "^PIAUNAME=" "$SECURE_ENV" 2>/dev/null | cut -d'=' -f2 || true)
        existing_pia_password=$(grep "^PIAPASS=" "$SECURE_ENV" 2>/dev/null | cut -d'=' -f2 || true)
        existing_daemon_user=$(grep "^CPDAEMONUN=" "$SECURE_ENV" 2>/dev/null | cut -d'=' -f2 || true)
        existing_daemon_pass=$(grep "^CPDAEMONPASS=" "$SECURE_ENV" 2>/dev/null | cut -d'=' -f2 || true)
        existing_plex_username=$(grep "^PLEX_USERNAME=" "$SECURE_ENV" 2>/dev/null | cut -d'=' -f2 || true)
        existing_plex_password=$(grep "^PLEX_PASSWORD=" "$SECURE_ENV" 2>/dev/null | cut -d'=' -f2 || true)
    fi
    
    # PIA Username
    if [[ -n "$existing_pia_username" ]]; then
        read -r -p "PIA Username (current: $existing_pia_username): " pia_username_input
        pia_username="${pia_username_input:-$existing_pia_username}"
    else
        read -r -p "Enter PIA Username: " pia_username
    fi
    
    # PIA Password
    if [[ -n "$existing_pia_password" ]]; then
        echo "PIA Password (press Enter to keep existing, or type new password)"
        read -r -s -p "PIA Password: " pia_password_input
        pia_password="${pia_password_input:-$existing_pia_password}"
    else
        read -r -s -p "Enter PIA Password (required): " pia_password
    fi
    echo
    
    # Daemon Username
    if [[ -n "$existing_daemon_user" ]]; then
        read -r -p "Daemon username (current: $existing_daemon_user): " daemon_user_input
        daemon_user="${daemon_user_input:-$existing_daemon_user}"
    else
        read -r -p "Enter daemon username: " daemon_user
    fi
    
    # Daemon Password
    if [[ -n "$existing_daemon_pass" ]]; then
        echo "Daemon Password (press Enter to keep existing, or type new password)"
        read -r -s -p "Daemon Password: " daemon_pass_input
        daemon_pass="${daemon_pass_input:-$existing_daemon_pass}"
    else
        read -r -s -p "Enter daemon password (required): " daemon_pass
    fi
    echo
    
    # Optional Plex credentials
    echo
    echo "Plex Integration (optional):"
    if [[ -n "$existing_plex_username" ]]; then
        read -r -p "MyPlex username (current: $existing_plex_username, or press Enter to skip): " plex_username_input
        if [[ "$plex_username_input" == "REMOVE" ]]; then
            plex_username=""
            plex_password=""
            echo "Plex credentials will be removed"
        elif [[ -n "$plex_username_input" ]]; then
            plex_username="$plex_username_input"
            echo "MyPlex Password (required for new username)"
            read -r -s -p "Enter MyPlex password: " plex_password
            echo
        else
            plex_username="$existing_plex_username"
            # Keep existing password if we're keeping the username
            if [[ -n "$existing_plex_password" ]]; then
                echo "MyPlex Password (press Enter to keep existing, or type new password)"
                read -r -s -p "MyPlex Password: " plex_password_input
                plex_password="${plex_password_input:-$existing_plex_password}"
                echo
                if [[ -z "$plex_password_input" ]]; then
                    echo "Keeping existing Plex password"
                fi
            else
                echo "MyPlex Password (required)"
                read -r -s -p "Enter MyPlex password: " plex_password
                echo
            fi
        fi
    else
        read -r -p "Enter MyPlex username (email, or press Enter to skip): " plex_username
        if [[ -n "$plex_username" ]]; then
            echo "MyPlex Password (required)"
            read -r -s -p "Enter MyPlex password: " plex_password
            echo
        fi
    fi
fi

# Create secure credentials file
cat > "$SECURE_ENV" << EOF
# Mediabox Secure Credentials
# Generated on $(date)
# This file should never be committed to version control
PIAUNAME=$pia_username
PIAPASS=$pia_password
CPDAEMONUN=$daemon_user
CPDAEMONPASS=$daemon_pass
NZBGETUN=$daemon_user
NZBGETPASS=$daemon_pass
EOF

# Add Plex credentials if provided
if [[ -n "$plex_username" ]]; then
    cat >> "$SECURE_ENV" << EOF
PLEX_USERNAME=$plex_username
PLEX_PASSWORD=$plex_password
EOF
fi

chmod 600 "$SECURE_ENV"  # Only user can read/write
echo "✅ Secure credentials file created at: $SECURE_ENV"

# Only update main .env if running interactively (not from mediabox.sh)
if [[ "$AUTO_MODE" == false ]]; then
    # Update main .env to source from secure location
    echo "Updating main .env file..."
    cd "$MEDIABOX_DIR"

    # Backup current .env
    if [[ -f .env ]]; then
        cp .env ".env.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Backup created: .env.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Remove sensitive credentials from main .env and add them directly
    # (Docker Compose .env files don't support shell sourcing)
    if [[ -f .env ]]; then
        sed -i '/^PIAUNAME=/d' .env
        sed -i '/^PIAPASS=/d' .env  
        sed -i '/^CPDAEMONUN=/d' .env
        sed -i '/^CPDAEMONPASS=/d' .env
        sed -i '/^NZBGETUN=/d' .env
        sed -i '/^NZBGETPASS=/d' .env
        sed -i '/^PLEX_USERNAME=/d' .env
        sed -i '/^PLEX_PASSWORD=/d' .env
        sed -i '/^# Source secure credentials/d' .env
        sed -i '/^\. .*credentials\.env/d' .env

        # Add credentials directly to .env file with source comment
        {
            echo "# Credentials (sourced from $SECURE_ENV)"
            echo "# Keep this file in .gitignore to prevent credential exposure"
            echo "PIAUNAME=$pia_username"
            echo "PIAPASS=$pia_password"
            
            # Plex notification settings (enabled by default)
            echo "ENABLE_PLEX_NOTIFICATIONS=true"
            
            echo ""
        } >> .env
        
        echo "✅ Main .env file updated with credentials (Docker Compose compatible)"
    fi
fi

echo ""
echo "IMPORTANT:"
echo "- Secure credentials stored in: $SECURE_ENV" 
echo "- Essential credentials added to .env file (Docker Compose compatible)"
echo "- Plex username/password kept secure in credentials file only"
echo "- Ensure .env is in .gitignore to prevent credential exposure"
if [[ "$AUTO_MODE" == false ]] && [[ -f .env ]]; then
    echo "- Backup created with timestamp"
fi
