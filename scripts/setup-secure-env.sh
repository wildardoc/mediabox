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
    echo "Using credentials provided by mediabox.sh"
else
    # Interactive mode: prompt for credentials
    echo "Creating secure credentials file..."
    
    read -r -p "Enter PIA Username: " pia_username
    read -r -s -p "Enter PIA Password: " pia_password
    echo
    read -r -p "Enter daemon username: " daemon_user
    read -r -s -p "Enter daemon password: " daemon_pass
    echo
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
        sed -i '/^# Source secure credentials/d' .env
        sed -i '/^\. .*credentials\.env/d' .env

        # Add credentials directly to .env file with source comment
        {
            echo "# Credentials (sourced from $SECURE_ENV)"
            echo "# Keep this file in .gitignore to prevent credential exposure"
            echo "PIAUNAME=$pia_username"
            echo "PIAPASS=$pia_password"
            echo "CPDAEMONUN=$daemon_username"
            echo "CPDAEMONPASS=$daemon_pass" 
            echo "NZBGETUN=$daemon_username"
            echo "NZBGETPASS=$daemon_pass"
            echo ""
        } >> .env
        
        echo "✅ Main .env file updated with credentials (Docker Compose compatible)"
    fi
fi

echo ""
echo "IMPORTANT:"
echo "- Secure credentials stored in: $SECURE_ENV" 
echo "- Credentials added to .env file (Docker Compose compatible)"
echo "- Ensure .env is in .gitignore to prevent credential exposure"
if [[ "$AUTO_MODE" == false ]] && [[ -f .env ]]; then
    echo "- Backup created with timestamp"
fi
