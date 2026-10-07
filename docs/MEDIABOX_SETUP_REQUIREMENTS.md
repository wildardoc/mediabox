# mediabox.sh Enhancement Requirements for Generic System Setup

## 1. Virtual Environment Management

The host and the *arr containers do **not** share a single virtual environment.
Earlier revisions of this project tried that (host `.venv` bind-mounted into
each container via `./scripts:/scripts`), but it's fundamentally fragile:
the host runs Ubuntu/glibc while the *arr containers run Alpine/musl, and a
Python venv hard-codes its site-packages path to the interpreter's own
major.minor version (`lib/pythonX.Y/site-packages`). Any time the container
image bumps its bundled Python version - which Alpine does independently of
the host - the mounted venv silently stops resolving its installed packages
(`ModuleNotFoundError`), even though nothing in this repo changed.

Instead, each environment manages its own packages, with `requirements.txt`
as the single source of truth for versions:

```bash
# Host virtual environment (used when running scripts directly from the shell)
VENV_DIR="$SCRIPTS_DIR/.venv"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$REQ_FILE"
deactivate

# Each *arr container installs the same requirements.txt into its own system
# Python on startup (see scripts/install-python-packages.sh, wired up via
# custom-cont-init.d). import.sh therefore invokes plain `python3` when
# running inside a container, not the host's .venv.
```

## 2. Container Python Package Verification

After containers start, verify each one has its own copy of the required packages:

```bash
verify_container_venv_access() {
    echo "🔍 Verifying containers have required Python packages..."

    local containers=("sonarr" "radarr" "lidarr")

    for container in "${containers[@]}"; do
        echo "  Checking $container..."

        # Packages are installed system-wide inside each container by
        # custom-cont-init.d/install-python-packages - there is no shared
        # venv to check for a mount anymore.
        if docker exec "$container" python3 -c "import requests, plexapi; print('OK')" 2>/dev/null | grep -q "OK"; then
            echo "    ✅ Python packages accessible"
        else
            echo "    ⚠️  Python packages not accessible (may need container restart)"
        fi
    done
}
```

## 3. Webhook Configuration Setup

Add automated webhook configuration for *arr applications:

```bash
configure_arr_webhooks() {
    echo "⚙️  Configuring *arr application webhooks..."
    
    # Wait for containers to be fully ready
    echo "  Waiting for *arr applications to initialize..."
    sleep 30
    
    local webhook_script="/scripts/import.sh"
    local webhook_name="Mediabox Processing"
    
    echo "  📝 Webhook configuration instructions:"
    echo "     After setup completes, configure webhooks in each *arr application:"
    echo ""
    echo "  🎬 RADARR (Movies):"
    echo "     1. Go to http://localhost:7878 → Settings → Connect"
    echo "     2. Add → Custom Script"
    echo "     3. Name: '$webhook_name'"
    echo "     4. Path: $webhook_script"
    echo "     5. Triggers: ☑ On Import, ☑ On Upgrade"
    echo "     6. Arguments: (leave blank)"
    echo ""
    echo "  📺 SONARR (TV Shows):"
    echo "     1. Go to http://localhost:8989 → Settings → Connect"
    echo "     2. Add → Custom Script"
    echo "     3. Name: '$webhook_name'"
    echo "     4. Path: $webhook_script"
    echo "     5. Triggers: ☑ On Import, ☑ On Upgrade"
    echo "     6. Arguments: (leave blank)"
    echo ""
    echo "  🎵 LIDARR (Music):"
    echo "     1. Go to http://localhost:8686 → Settings → Connect"
    echo "     2. Add → Custom Script"
    echo "     3. Name: '$webhook_name'"
    echo "     4. Path: $webhook_script"
    echo "     5. Triggers: ☑ On Import, ☑ On Upgrade"
    echo "     6. Arguments: (leave blank)"
    echo ""
}
```

## 4. Enhanced Configuration Generation

Update the config generation to be more robust:

```bash
generate_mediabox_config() {
    echo "📝 Generating mediabox configuration..."
    
    # Ensure the config is container-aware
    cat > "$SCRIPTS_DIR/mediabox_config.json" <<EOF
{
  "venv_path": "$VENV_DIR",
  "download_dirs": [
    "$dldirectory/completed", 
    "$dldirectory/incomplete"
  ],
  "library_dirs": {
    "tv": "$tvdirectory",
    "movies": "$moviedirectory",
    "music": "$musicdirectory",
    "misc": "$miscdirectory"
  },
  "container_support": true,
  "plex_integration": {
    "url": "\${PLEX_URL}",
    "token": "\${PLEX_TOKEN}",
    "path_mappings": {
      "tv": "/data/tv",
      "movies": "/data/movies", 
      "music": "/data/music"
    }
  }
}
EOF
    
    echo "✅ Configuration file created: $SCRIPTS_DIR/mediabox_config.json"
}
```

## 5. Plex Integration Setup

Enhanced Plex token setup with better error handling:

```bash
setup_plex_integration() {
    echo "🎬 Setting up Plex integration..."
    
    local credentials_file="$HOME/.mediabox/credentials.env"
    
    # Check if Plex token exists in .env
    if grep -q "PLEX_TOKEN=" "$ENV_FILE" && [[ -n "$(grep "PLEX_TOKEN=" "$ENV_FILE" | cut -d'=' -f2)" ]]; then
        echo "✅ Plex token found in .env file"
        return 0
    fi
    
    # Try to get Plex token automatically
    if [[ -f "$credentials_file" ]] && [[ -f "$SCRIPTS_DIR/get-plex-token.py" ]]; then
        echo "  🔑 Attempting automatic Plex token retrieval..."
        
        # Activate virtual environment for token script
        source "$VENV_DIR/bin/activate"
        
        if python3 "$SCRIPTS_DIR/get-plex-token.py" --url "http://localhost:32400" --auto-credential-file "$credentials_file" 2>/dev/null; then
            echo "  ✅ Plex token retrieved and saved automatically"
            deactivate
            return 0
        else
            echo "  ⚠️  Automatic token retrieval failed"
            deactivate
        fi
    fi
    
    # Manual setup instructions
    echo "  📝 Manual Plex setup required:"
    echo "     1. Ensure Plex is running: http://localhost:32400"
    echo "     2. Run: cd scripts && python3 get-plex-token.py --interactive"
    echo "     3. Follow the prompts to authenticate with Plex"
    echo ""
}
```

## 6. Post-Installation Validation

Add comprehensive validation:

```bash
validate_installation() {
    echo "🔍 Validating installation..."
    
    # Check containers are running
    local containers=("sonarr" "radarr" "lidarr" "plex" "homer")
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            echo "  ✅ $container container running"
        else
            echo "  ❌ $container container not running"
        fi
    done
    
    # Check Python packages in containers
    echo "  🐍 Checking Python packages in containers..."
    for container in sonarr radarr lidarr; do
        if docker exec "$container" python3 -c "import requests, plexapi; print('OK')" 2>/dev/null | grep -q "OK"; then
            echo "  ✅ Python packages available in $container"
        else
            echo "  ⚠️  Python packages missing in $container"
        fi
    done
    
    # Check scripts directory mount
    for container in sonarr radarr lidarr; do
        if docker exec "$container" test -f "/scripts/import.sh"; then
            echo "  ✅ Scripts mounted in $container"
        else
            echo "  ❌ Scripts not mounted in $container"
        fi
    done
    
    # Test media_update.py
    echo "  🎬 Testing media processing script..."
    source "$VENV_DIR/bin/activate"
    if python3 "$SCRIPTS_DIR/media_update.py" --help >/dev/null 2>&1; then
        echo "  ✅ media_update.py working on host"
    else
        echo "  ❌ media_update.py has issues on host"
    fi
    deactivate
    
    # Test Plex connection
    if [[ -n "${PLEX_TOKEN:-}" ]]; then
        source "$VENV_DIR/bin/activate"
        if python3 -c "
import os
import sys
sys.path.insert(0, '$VENV_DIR/lib/python3.*/site-packages')
from plexapi.server import PlexServer
plex = PlexServer('${PLEX_URL}', '${PLEX_TOKEN}')
print('Plex connection: OK')
" 2>/dev/null; then
            echo "  ✅ Plex connection working"
        else
            echo "  ⚠️  Plex connection issues"
        fi
        deactivate
    else
        echo "  ⚠️  Plex token not configured"
    fi
}
```

## 7. Integration into Main Script

Add these functions to the main execution flow:

```bash
# After containers start (around line 576)
echo "✅ Docker containers started successfully"

# Add container package installation
install_container_python_packages

# Wait a bit for containers to fully initialize
echo "⏳ Waiting for containers to fully initialize..."
sleep 60

# Retry any failed package installations
retry_container_package_installation

# Setup Plex integration
setup_plex_integration

# Generate enhanced configuration
generate_mediabox_config

# Configure webhooks (show instructions)
configure_arr_webhooks

# Final validation
validate_installation

echo ""
echo "🎉 Mediabox setup complete!"
echo ""
echo "📋 Next Steps:"
echo "   1. Configure webhooks in *arr applications (see instructions above)"
echo "   2. Test by downloading media through Sonarr/Radarr/Lidarr"
echo "   3. Check logs: tail -f scripts/import_$(date +%Y%m%d).log"
echo ""
echo "🔧 Manual Commands:"
echo "   • Test conversion: cd scripts && python3 media_update.py --file [path] --type video"
echo "   • Check Plex: cd scripts && python3 test_plex_connection.py"
echo "   • View container logs: docker logs [container_name]"
echo ""
```

## 8. Error Recovery Instructions

Add troubleshooting section:

```bash
show_troubleshooting_info() {
    echo ""
    echo "🔧 TROUBLESHOOTING:"
    echo ""
    echo "If Python packages are missing in containers:"
    echo "   docker exec sonarr pip3 install --break-system-packages ffmpeg-python future PlexAPI requests"
    echo "   docker exec radarr pip3 install --break-system-packages ffmpeg-python future PlexAPI requests"
    echo "   docker exec lidarr pip3 install --break-system-packages ffmpeg-python future PlexAPI requests"
    echo ""
    echo "If Plex token is missing:"
    echo "   cd scripts && python3 get-plex-token.py --interactive"
    echo ""
    echo "To test integration manually:"
    echo "   docker exec sonarr bash /scripts/import.sh"
    echo ""
    echo "For support: Check logs in scripts/ directory"
    echo ""
}
```

This enhancement will make `mediabox.sh` fully generic and handle all the setup automatically that we had to do manually during our troubleshooting session.
