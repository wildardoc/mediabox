#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Enhanced Error Handling Functions
check_docker_daemon() {
    echo "🔍 Checking Docker daemon status..."
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker daemon not running. Please start Docker first."
        echo "💡 Try: sudo systemctl start docker"
        exit 1
    fi
    echo "✅ Docker daemon is running"
}

validate_directories() {
    echo "📁 Validating media directories..."
    for dir in "$dldirectory" "$tvdirectory" "$moviedirectory" "$musicdirectory" "$miscdirectory" "$photodirectory"; do
        if [[ -n "$dir" && ! -d "$dir" ]]; then
            echo "⚠️  Directory doesn't exist: $dir"
            read -r -p "Create it? (y/n): " create_dir
            if [[ "$create_dir" == "y" || "$create_dir" == "Y" ]]; then
                if mkdir -p "$dir"; then
                    echo "✅ Created directory: $dir"
                else
                    echo "❌ Failed to create directory: $dir"
                    exit 1
                fi
            else
                echo "⚠️  Continuing without creating $dir"
            fi
        elif [[ -n "$dir" ]]; then
            echo "✅ Directory exists: $dir"
        fi
    done
}

check_permissions() {
    echo "🔐 Checking directory permissions..."
    local test_dir="$PWD/content"
    if [[ ! -w "$test_dir" ]] && ! mkdir -p "$test_dir" 2>/dev/null; then
        echo "❌ Cannot create directories in current location: $PWD"
        echo "💡 Please ensure you have write permissions or run from a different directory"
        exit 1
    fi
    echo "✅ Directory permissions OK"
}

test_network_connectivity() {
    echo "🌐 Testing network connectivity..."
    if ! curl -s --connect-timeout 5 https://api.github.com/repos/docker/compose/releases/latest >/dev/null; then
        echo "⚠️  Limited or no internet connectivity detected"
        echo "💡 Some features may not work properly (updates, VPN config download)"
        read -r -p "Continue anyway? (y/n): " continue_offline
        if [[ "$continue_offline" != "y" && "$continue_offline" != "Y" ]]; then
            echo "❌ Setup cancelled"
            exit 1
        fi
    else
        echo "✅ Network connectivity OK"
    fi
}

safe_docker_operation() {
    local operation="$1"
    local container="$2"
    if ! docker "$operation" "$container" > /dev/null 2>&1; then
        echo "⚠️  Docker $operation failed for $container (this may be normal if container doesn't exist)"
        return 1
    fi
    return 0
}

# Plex Integration Functions
wait_for_plex_service() {
    local max_attempts=20  # 3+ minutes max wait
    local attempt=1
    
    printf "⏳ Waiting for Plex service to be ready...\\n"
    
    for attempt in $(seq 1 $max_attempts); do
        # First check if container is running
        if ! docker compose ps plex | grep -q "Up"; then
            printf "⚠️  Plex container not running (attempt $attempt/$max_attempts)\\n"
            sleep 10
            continue
        fi
        
        # Then test if service responds
        if curl -s --connect-timeout 3 http://localhost:32400/identity >/dev/null 2>&1; then
            printf "✅ Plex service is ready and responding\\n"
            return 0
        fi
        
        printf "⏳ Plex starting up... ($attempt/$max_attempts)\\n"
        sleep 10
    done
    
    printf "❌ Timeout waiting for Plex service to be ready\\n"
    return 1
}

setup_plex_token() {
    local scripts_dir="$PWD/scripts"
    local venv_dir="$scripts_dir/.venv"
    local credentials_file="$HOME/.mediabox/credentials.env"
    
    printf "🔐 Retrieving Plex authentication token...\\n"
    
    # Ensure virtual environment is activated and has dependencies
    if [ ! -d "$venv_dir" ]; then
        printf "❌ Virtual environment not found at $venv_dir\\n"
        return 1
    fi
    
    # Check if credentials file exists
    if [ ! -f "$credentials_file" ]; then
        printf "❌ Credentials file not found at $credentials_file\\n"
        return 1
    fi
    
    # Use the get-plex-token.py script with credentials file
    cd "$scripts_dir" || return 1
    
    if python3 get-plex-token.py --url "http://localhost:32400" --auto-credential-file "$credentials_file" 2>/dev/null; then
        printf "✅ Plex token retrieved and configured successfully!\\n"
        return 0
    else
        printf "❌ Failed to retrieve Plex token automatically\\n"
        return 1
    fi
}

# Check that script was run not as root or with sudo
if [ "$EUID" -eq 0 ]
  then echo "Please do not run this script as root or using sudo"
  exit
fi

# Run initial system checks
check_docker_daemon
check_permissions
test_network_connectivity

# See if we need to check GIT for updates
if [ -e .env ]; then
    # Docker Compose V2 is included with Docker CE and updates automatically
    printf "Docker Compose V2 updates with Docker Engine - no separate update needed.\\n\\n"
    
    # Check for updates to the Mediabox repo
    printf "Updating your local copy of Mediabox.\\n\\n"
    printf "If this file 'mediabox.sh' is updated it will be re-run automatically.\\n\\n"
    git stash > /dev/null 2>&1
    git pull
    if git diff-tree --no-commit-id --name-only -r HEAD | grep -q "mediabox.sh"; then
        mv .env 1.env
        printf "Restarting mediabox.sh"
        ./mediabox.sh
    fi
    if [ -z "$(git diff-tree --no-commit-id --name-only -r HEAD)" ]; then
        printf "Your Mediabox is current - No Update needed.\\n\\n"
        mv .env 1.env
    fi
fi

# After update collect some current known variables
if [ -e 1.env ]; then
    # Give updated Message
    printf "Docker Compose and Mediabox have been updated.\\n\\n"
    # Grab the CouchPotato, NBZGet, & PIA usernames & passwords to reuse
    daemonun=$(grep CPDAEMONUN 1.env | cut -d = -f2)
    daemonpass=$(grep CPDAEMONPASS 1.env | cut -d = -f2)
    piauname=$(grep PIAUNAME 1.env | cut -d = -f2)
    piapass=$(grep PIAPASS 1.env | cut -d = -f2)
    pmstag=$(grep PMSTAG 1.env | cut -d = -f2)
    dldirectory=$(grep DLDIR 1.env | cut -d = -f2)
    tvdirectory=$(grep TVDIR 1.env | cut -d = -f2)
    miscdirectory=$(grep MISCDIR 1.env | cut -d = -f2)
    moviedirectory=$(grep MOVIEDIR 1.env | cut -d = -f2)
    musicdirectory=$(grep MUSICDIR 1.env | cut -d = -f2)
    photodirectory=$(grep PHOTODIR 1.env | cut -d = -f2)
    # Echo back the media directioies, and other info to see if changes are needed
    printf "These are the Media Directory paths currently configured.\\n"
    printf "Your DOWNLOAD Directory is: %s \\n" "$dldirectory"
    printf "Your TV Directory is: %s \\n" "$tvdirectory"
    printf "Your MISC Directory is: %s \\n" "$miscdirectory"
    printf "Your MOVIE Directory is: %s \\n" "$moviedirectory"
    printf "Your MUSIC Directory is: %s \\n" "$musicdirectory"
    printf "Your PHOTO Directory is: %s \\n" "$photodirectory"
    printf "\\n\\n"
    read  -r -p "Are these directiores still correct? (y/n) " diranswer "$(echo \n)"
    printf "\\n\\n"
    printf "Your PLEX Release Type is: %s" "$pmstag"
    printf "\\n\\n"
    read  -r -p "Do you need to change your PLEX Release Type? (y/n) " pmsanswer "$(echo \n)"
    printf "\\n\\n"
    read  -r -p "Do you need to change your PIA Credentials? (y/n) " piaanswer "$(echo \n)"
    # Now we need ".env" to exist again so we can stop just the Medaibox containers
    mv 1.env .env
    # Stop the current Mediabox stack
    printf "\\n\\nStopping Current Mediabox containers.\\n\\n"
    if ! docker compose stop; then
        echo "❌ Failed to stop Mediabox containers"
        echo "💡 You may need to stop containers manually: docker compose stop"
        exit 1
    fi
    echo "✅ Mediabox containers stopped successfully"
    # Make a datestampted copy of the existing .env file
    mv .env "$(date +"%Y-%m-%d_%H:%M").env"
fi

# Collect Server/User info:
# Get local Username
localuname=$(id -u -n)
# Get PUID
PUID=$(id -u "$localuname")
# Get GUID
PGID=$(id -g "$localuname")
# Get Docker Group Number
DOCKERGRP=$(grep docker /etc/group | cut -d ':' -f 3)
# Get Hostname
thishost=$(hostname)
# Get IP Address
locip=$(hostname -I | awk '{print $1}')
# Get Time Zone
time_zone=$(cat /etc/timezone)	
# Get CIDR Address
slash=$(ip a | grep "$locip" | cut -d ' ' -f6 | awk -F '/' '{print $2}')
lannet=$(awk -F"." '{print $1"."$2"."$3".0"}'<<<"$locip")/$slash

# Get Private Internet Access Info
if [ -z "$piaanswer" ] || [ "$piaanswer" == "y" ]; then
read -r -p "What is your PIA Username?: " piauname
read -r -s -p "What is your PIA Password? (Will not be echoed): " piapass
printf "\\n\\n"
fi

# Get MyPlex Account Info for Plex Integration
printf "\\n🎬 Configure Plex Integration\\n"
printf "==================================\\n"
printf "To enable automatic library updates after media processing,\\n"
printf "enter your Plex/MyPlex account details (optional - skip with Enter):\\n\\n"

read -r -p "MyPlex Username (email): " plex_username
if [ -n "$plex_username" ]; then
    read -r -s -p "MyPlex Password (Will not be echoed): " plex_password
    printf "\\n"
    plex_enabled="true"
    printf "✅ Plex credentials collected - will configure after containers start\\n"
else
    plex_enabled="false"
    printf "⏭️  Skipping Plex integration - can be configured later\\n"
fi
printf "\\n"

# Get info needed for PLEX Official image
if [ -z "$pmstag" ] || [ "$pmsanswer" == "y" ]; then
read -r -p "Which PLEX release do you want to run? By default 'public' will be used. (latest, public, plexpass): " pmstag
fi
# If not set - set PMS Tag to Public:
if [ -z "$pmstag" ]; then
   pmstag=public
fi

# Ask user if they already have TV, Movie, and Music directories
if [ -z "$diranswer" ]; then
printf "\\n\\n"
printf "If you already have TV - Movie - Music directories you want to use you can enter them next.\\n"
printf "If you want Mediabox to generate it's own directories just press enter to these questions."
printf "\\n\\n"
read -r -p "Where do you store your DOWNLOADS? (Please use full path - /path/to/downloads ): " dldirectory
read -r -p "Where do you store your TV media? (Please use full path - /path/to/tv ): " tvdirectory
read -r -p "Where do you store your MISC media? (Please use full path - /path/to/misc ): " miscdirectory
read -r -p "Where do you store your MOVIE media? (Please use full path - /path/to/movies ): " moviedirectory
read -r -p "Where do you store your MUSIC media? (Please use full path - /path/to/music ): " musicdirectory
read -r -p "Where do you store your PHOTO media? (Please use full path - /path/to/photos ): " photoirectory
fi
if [ "$diranswer" == "n" ]; then
read -r -p "Where do you store your DOWNLOADS? (Please use full path - /path/to/downloads ): " dldirectory
read -r -p "Where do you store your TV media? (Please use full path - /path/to/tv ): " tvdirectory
read -r -p "Where do you store your MISC media? (Please use full path - /path/to/misc ): " miscdirectory
read -r -p "Where do you store your MOVIE media? (Please use full path - /path/to/movies ): " moviedirectory
read -r -p "Where do you store your MUSIC media? (Please use full path - /path/to/music ): " musicdirectory
read -r -p "Where do you store your PHOTO media? (Please use full path - /path/to/photos ): " photodirectory
fi

# Validate user-provided directory paths with comprehensive checking
validate_user_paths() {
    local path="$1"
    local description="$2"
    
    if [ -n "$path" ]; then
        # Check if path is absolute
        if [[ "$path" != /* ]]; then
            printf "⚠️  Warning: %s path '%s' is not absolute. Consider using full paths starting with '/'.\\n" "$description" "$path"
        fi
        
        # Check if parent directory exists for path creation
        local parent_dir=$(dirname "$path")
        if [ ! -d "$parent_dir" ] && [ "$parent_dir" != "." ]; then
            printf "⚠️  Warning: Parent directory '%s' for %s does not exist. Please ensure it exists or will be created.\\n" "$parent_dir" "$description"
        fi
        
        # Check write permissions if path already exists
        if [ -d "$path" ] && [ ! -w "$path" ]; then
            printf "❌ Error: No write permission for existing %s directory: %s\\n" "$description" "$path"
            return 1
        fi
        
        # Interactive directory creation for missing directories
        if [[ ! -d "$path" ]]; then
            echo "⚠️  Directory doesn't exist: $path"
            read -r -p "Create $description directory? (y/n): " create_dir
            if [[ "$create_dir" == "y" || "$create_dir" == "Y" ]]; then
                if mkdir -p "$path"; then
                    echo "✅ Created directory: $path"
                else
                    echo "❌ Failed to create directory: $path"
                    return 1
                fi
            else
                echo "⚠️  Continuing without creating $path"
            fi
        else
            echo "✅ Directory exists: $path"
        fi
    fi
    return 0
}

# Validate all provided paths
echo "📁 Validating provided directory paths..."
validate_user_paths "$dldirectory" "DOWNLOAD"
validate_user_paths "$tvdirectory" "TV"
validate_user_paths "$miscdirectory" "MISC"
validate_user_paths "$moviedirectory" "MOVIE"
validate_user_paths "$musicdirectory" "MUSIC"
validate_user_paths "$photodirectory" "PHOTO"
echo "✅ Path validation complete"
echo ""

# Create the directory structure with error checking
echo "📁 Creating mediabox directory structure..."

# ZFS Detection and Dataset Creation
detect_zfs() {
    # Check if current directory is on ZFS
    local fs_type
    fs_type=$(df -T . 2>/dev/null | tail -1 | awk '{print $2}')
    [[ "$fs_type" == "zfs" ]]
}

get_zfs_dataset() {
    # Get the most specific ZFS dataset for current directory
    local current_path
    current_path=$(realpath "$PWD")
    local best_match=""
    local best_length=0
    
    zfs list -H -o name,mountpoint | while read -r dataset mountpoint; do
        if [[ "$current_path" == "$mountpoint"* ]] && [[ ${#mountpoint} -gt $best_length ]]; then
            best_match="$dataset"
            best_length=${#mountpoint}
        fi
    done | tail -1
    
    # Alternative approach: find exact match first
    zfs list -H -o name,mountpoint | awk -v path="$current_path" '
    BEGIN { best_len = 0; best_name = "" }
    {
        if (index(path, $2) == 1 && length($2) > best_len) {
            best_len = length($2)
            best_name = $1
        }
    }
    END { print best_name }'
}

create_directory() {
    local dir="$1"
    local use_zfs="${2:-}"
    
    if [[ "$use_zfs" == "true" ]] && detect_zfs; then
        local parent_dataset
        parent_dataset=$(get_zfs_dataset)
        
        if [[ -n "$parent_dataset" ]]; then
            local dataset_name="$parent_dataset/$dir"
            echo "📦 Creating ZFS dataset: $dataset_name"
            
            if sudo zfs create "$dataset_name"; then
                # Set proper ownership
                sudo chown "$USER:$USER" "$dir"
                echo "✅ Created ZFS dataset: $dataset_name"
            else
                echo "❌ Failed to create ZFS dataset: $dataset_name"
                echo "📁 Falling back to regular directory creation..."
                if ! mkdir -p "$dir"; then
                    echo "❌ Failed to create directory: $dir"
                    exit 1
                fi
            fi
        else
            echo "⚠️  Could not determine parent ZFS dataset, using regular mkdir"
            if ! mkdir -p "$dir"; then
                echo "❌ Failed to create directory: $dir"
                exit 1
            fi
        fi
    else
        # Regular directory creation
        if ! mkdir -p "$dir"; then
            echo "❌ Failed to create directory: $dir"
            exit 1
        fi
    fi
}

# ZFS Dataset Creation Option
USE_ZFS_DATASETS="false"
if detect_zfs; then
    echo ""
    echo "🗂️  ZFS filesystem detected!"
    echo "   Current directory is on ZFS, which allows creating datasets instead of regular directories."
    echo "   Benefits of ZFS datasets:"
    echo "   • Individual snapshots for each service"
    echo "   • Compression and deduplication per service"
    echo "   • Individual mount options and quotas"
    echo "   • Better backup and replication capabilities"
    echo ""
    read -r -p "Create ZFS datasets for service directories instead of regular folders? (y/n): " use_zfs_response
    
    if [[ "$use_zfs_response" == "y" || "$use_zfs_response" == "Y" ]]; then
        USE_ZFS_DATASETS="true"
        echo "✅ Will create ZFS datasets for service directories"
    else
        echo "📁 Will use regular directories"
    fi
else
    echo "📁 Regular filesystem detected, using standard directories"
fi
echo ""

# Create the directory structure
if [ -z "$dldirectory" ]; then
    create_directory "downloads/completed"
    create_directory "downloads/incomplete"
    dldirectory="$PWD/downloads"
else
    create_directory "$dldirectory/completed"
    create_directory "$dldirectory/incomplete"
fi
if [ -z "$tvdirectory" ]; then
    create_directory "content/tv"
    tvdirectory="$PWD/content/tv"
fi
if [ -z "$miscdirectory" ]; then
    create_directory "content/misc"
    miscdirectory="$PWD/content/misc"
fi
if [ -z "$moviedirectory" ]; then
    create_directory "content/movies"
    moviedirectory="$PWD/content/movies"
fi
if [ -z "$musicdirectory" ]; then
    create_directory "content/music"
    musicdirectory="$PWD/content/music"
fi
if [ -z "$photodirectory" ]; then
    create_directory "content/photo"
    photodirectory="$PWD/content/photo"
fi

# Create application directories with error checking
echo "📁 Creating application directories..."
create_directory "delugevpn" "$USE_ZFS_DATASETS"
create_directory "historical/env_files"
create_directory "homer" "$USE_ZFS_DATASETS"
create_directory "lidarr" "$USE_ZFS_DATASETS"
create_directory "nzbget" "$USE_ZFS_DATASETS"
create_directory "overseerr" "$USE_ZFS_DATASETS"
create_directory "plex/Library/Application Support/Plex Media Server/Logs"
create_directory "portainer" "$USE_ZFS_DATASETS"
create_directory "prowlarr" "$USE_ZFS_DATASETS"
create_directory "radarr" "$USE_ZFS_DATASETS"
create_directory "sonarr" "$USE_ZFS_DATASETS"
create_directory "tautulli" "$USE_ZFS_DATASETS"
create_directory "maintainerr" "$USE_ZFS_DATASETS"

echo "✅ Directory structure created successfully"

# WireGuard VPN Configuration
echo "🔒 Configuring WireGuard VPN for DelUgeVPN..."
echo "✅ WireGuard is configured and will automatically connect using your PIA credentials"
echo "ℹ️  The container will automatically select the best available PIA WireGuard server"
printf "\\n"

# Create the .env file
echo "Creating the .env file with secure credential sourcing"
printf "\\n"
cat << EOF > .env
# Source secure credentials
. $HOME/.mediabox/credentials.env

###  ------------------------------------------------
###  M E D I A B O X   C O N F I G   S E T T I N G S
###  ------------------------------------------------
###  The values configured here are applied during
###  $ docker compose up
###  -----------------------------------------------
###  DOCKER COMPOSE ENVIRONMENT VARIABLES BEGIN HERE
###  -----------------------------------------------
###
EOF
{
echo "# Default profiles to run when no --profile flag is specified"
echo "# Options: core, full, music, usenet, plex, monitoring, requests, maintenance"
echo "# Use comma-separated list for multiple profiles (e.g., \"core,plex,monitoring\")"
echo "COMPOSE_PROFILES=full"
echo ""
echo "LOCALUSER=$localuname"
echo "HOSTNAME=$thishost"
echo "IP_ADDRESS=$locip"
echo "PUID=$PUID"
echo "PGID=$PGID"
echo "DOCKERGRP=$DOCKERGRP"
echo "PWD=$PWD"
echo "DLDIR=$dldirectory"
echo "TVDIR=$tvdirectory"
echo "MISCDIR=$miscdirectory"
echo "MOVIEDIR=$moviedirectory"
echo "MUSICDIR=$musicdirectory"
echo "PHOTODIR=$photodirectory"
echo "CIDR_ADDRESS=$lannet"
echo "TZ=$time_zone"
echo "PMSTAG=$pmstag"
} >> .env
echo ".env file creation complete"
printf "\\n\\n"

# Clean up old containers (safe operations)
echo "🧹 Cleaning up legacy containers..."
safe_docker_operation "rm" "-f plexpy"
safe_docker_operation "rm" "-f ouroboros" 
safe_docker_operation "rm" "-f uhttpd"
safe_docker_operation "rm" "-f muximux"
[ -d "www/" ] && mv www/ historical/www/
# Adjust for removal of Muximux
safe_docker_operation "rm" "-f muximux"
[ -d "muximux/" ] && mv muximux/ historical/muximux/
# Move back-up .env files
mv 20*.env historical/env_files/ > /dev/null 2>&1
mv historical/20*.env historical/env_files/ > /dev/null 2>&1
# Remove files after switch to using Prep folder
rm -f mediaboxconfig.php > /dev/null 2>&1
rm -f settings.ini.php > /dev/null 2>&1
rm -f prep/mediaboxconfig.php > /dev/null 2>&1

# Download & Launch the containers
echo "🚀 The containers will now be pulled and launched"
echo "This may take a while depending on your download speed"
read -r -p "Press any key to continue... " -n1 -s
printf "\\n\\n"
echo "📥 Starting Docker containers..."
echo "Using profile: \${COMPOSE_PROFILES:-full} (override with --profile flag if needed)"
if ! docker compose up -d --remove-orphans; then
    echo "❌ Failed to start Docker containers"
    echo "💡 Please check docker-compose.yml and .env files for errors"
    echo "💡 Try running: docker compose logs"
    exit 1
fi
echo "✅ Docker containers started successfully"

# Verify virtual environment is accessible in containers
verify_container_venv_access() {
    echo "🔍 Verifying containers can access virtual environment..."
    
    local containers=("sonarr" "radarr" "lidarr")
    local all_good=true
    
    for container in "${containers[@]}"; do
        echo "  Checking $container..."
        
        # Check if .venv directory is mounted
        if docker exec "$container" test -d "/scripts/.venv" 2>/dev/null; then
            echo "    ✅ Virtual environment directory mounted"
        else
            echo "    ❌ Virtual environment directory not mounted"
            all_good=false
            continue
        fi
        
        # Check if Python packages are accessible
        if docker exec "$container" /scripts/.venv/bin/python -c "import requests, plexapi; print('OK')" 2>/dev/null | grep -q "OK"; then
            echo "    ✅ Python packages accessible"
        else
            echo "    ⚠️  Python packages not accessible (may need host venv rebuild)"
            all_good=false
        fi
    done
    
    if [[ "$all_good" == "true" ]]; then
        echo "  ✅ All containers can access virtual environment"
    else
        echo "  ⚠️  Some containers have virtual environment issues"
        echo "  💡 The host virtual environment with required packages will be used"
        echo "  💡 Containers access packages via mounted /scripts/.venv directory"
    fi
}

# Verify container access to virtual environment
verify_container_venv_access

printf "

"

# Install Python packages in containers for media processing
install_container_python_packages() {
    echo "📦 Installing Python packages in *arr containers..."
    
    local packages=(
        "ffmpeg-python==0.2.0"
        "future==1.0.0"  
        "PlexAPI==4.15.8"
        "requests==2.31.0"
    )
    
    local containers=("sonarr" "radarr" "lidarr")
    local retry_file="$SCRIPTS_DIR/.container_package_retry"
    
    # Clear any old retry file
    rm -f "$retry_file"
    
    for container in "${containers[@]}"; do
        echo "  Installing packages in $container..."
        if docker exec "$container" pip3 install --break-system-packages "${packages[@]}" >/dev/null 2>&1; then
            echo "  ✅ Packages installed in $container"
        else
            echo "  ⚠️  Package installation failed in $container (container may not be ready yet)"
            echo "$container" >> "$retry_file"
        fi
    done
    
    # Retry failed installations after a delay
    if [[ -f "$retry_file" ]]; then
        echo "  ⏳ Waiting 60 seconds for containers to fully initialize..."
        sleep 60
        
        echo "  🔄 Retrying package installation for containers that failed..."
        while IFS= read -r container; do
            echo "    Retrying $container..."
            if docker exec "$container" pip3 install --break-system-packages "${packages[@]}" >/dev/null 2>&1; then
                echo "    ✅ Packages installed in $container"
            else
                echo "    ⚠️  $container still not ready - manual installation may be needed later"
                echo "    💡 Manual command: docker exec $container pip3 install --break-system-packages ffmpeg-python future PlexAPI requests"
            fi
        done < "$retry_file"
        rm -f "$retry_file"
    fi
}

# Install packages in containers
install_container_python_packages

printf "\\n\\n"

# Configure the access to the Deluge Daemon
# The same credentials can be used for NZBGet's webui
if [ -z "$daemonun" ]; then
echo "You need to set a username and password for some of the programs - including."
echo "The Deluge daemon, NZBGet's API & web interface."
read -r -p "What would you like to use as the access username?: " daemonun
read -r -p "What would you like to use as the access password?: " daemonpass
printf "\\n\\n"

# Create secure credential storage using external script
echo "Setting up secure credential storage..."
export PIAUNAME="$piauname"
export PIAPASS="$piapass"
export CPDAEMONUN="$daemonun"
export CPDAEMONPASS="$daemonpass"
export NZBGETUN="$daemonun"
export NZBGETPASS="$daemonpass"

# Add Plex credentials if provided
if [ "$plex_enabled" == "true" ]; then
    export PLEX_USERNAME="$plex_username"
    export PLEX_PASSWORD="$plex_password"
fi

"$PWD/scripts/setup-secure-env.sh" --auto
fi

# Finish up the config
printf "Configuring DelugeVPN and Permissions \\n"
printf "This may take a few minutes...\\n\\n"

# Configure DelugeVPN: Set Daemon access on, delete the core.conf~ file
echo "⚙️  Configuring DelugeVPN..."
while [ ! -f delugevpn/config/core.conf ]; do sleep 1; done
safe_docker_operation "stop" "delugevpn"
rm delugevpn/config/core.conf~ > /dev/null 2>&1
perl -i -pe 's/"allow_remote": false,/"allow_remote": true,/g'  delugevpn/config/core.conf
perl -i -pe 's/"move_completed": false,/"move_completed": true,/g'  delugevpn/config/core.conf
if safe_docker_operation "start" "delugevpn"; then
    echo "✅ DelugeVPN configured and restarted"
else
    echo "⚠️  DelugeVPN configuration applied, but restart failed"
fi

# Configure NZBGet
echo "⚙️  Configuring NZBGet..."
[ -d "content/nbzget" ] && mv content/nbzget/* content/ && rmdir content/nbzget
while [ ! -f nzbget/nzbget.conf ]; do sleep 1; done
safe_docker_operation "stop" "nzbget"
perl -i -pe "s/ControlUsername=nzbget/ControlUsername=$daemonun/g"  nzbget/nzbget.conf
perl -i -pe "s/ControlPassword=tegbzn6789/ControlPassword=$daemonpass/g"  nzbget/nzbget.conf
perl -i -pe "s/{MainDir}\/intermediate/{MainDir}\/incomplete/g" nzbget/nzbget.conf
if safe_docker_operation "start" "nzbget"; then
    echo "✅ NZBGet configured and restarted"
else
    echo "⚠️  NZBGet configuration applied, but restart failed"
fi

# Push the Deluge Daemon Access info to Auth file
echo "$daemonun":"$daemonpass":10 >> ./delugevpn/config/auth

# Configure Homer settings and files
echo "⚙️  Configuring Homer..."
while [ ! -f homer/config.yml ]; do sleep 1; done
safe_docker_operation "stop" "homer"
cp prep/config.yml homer/config.yml
cp prep/mediaboxconfig.html homer/mediaboxconfig.html
cp prep/portmap.html homer/portmap.html
cp prep/icons/* homer/icons/
sed -E '/^(PIA|CPDAEMON|NZBGET)/d' < .env > homer/env.txt # Filter out all credentials from displayed .env file
perl -i -pe "s/thishost/$thishost/g" homer/config.yml
perl -i -pe "s/locip/$locip/g" homer/config.yml
perl -i -pe "s/locip/$locip/g" homer/mediaboxconfig.html
perl -i -pe "s/daemonun/$daemonun/g" homer/mediaboxconfig.html
perl -i -pe "s/daemonpass/$daemonpass/g" homer/mediaboxconfig.html
if safe_docker_operation "start" "homer"; then
    echo "✅ Homer configured and restarted"
else
    echo "⚠️  Homer configuration applied, but restart failed"
fi

# Create Port Mapping file
for i in $(docker ps --format {{.Names}} | sort); do printf "\n === $i Ports ===\n" && docker port "$i"; done > homer/ports.txt

# Configure Prowlarr to use FlareSolverr
configure_prowlarr_flaresolverr() {
    echo "⚙️  Configuring Prowlarr to use FlareSolverr..."

    local max_attempts=30
    local attempt=1

    # Wait for Prowlarr config to exist
    echo "   Waiting for Prowlarr to initialize..."
    while [ ! -f prowlarr/config.xml ] && [ $attempt -le $max_attempts ]; do
        sleep 2
        ((attempt++))
    done

    if [ ! -f prowlarr/config.xml ]; then
        echo "   ⚠️  Prowlarr config not found after ${max_attempts} attempts"
        echo "   💡 You can configure FlareSolverr manually in Prowlarr:"
        echo "      Settings → Indexers → Add → FlareSolverr"
        echo "      Host: http://${locip}:8191"
        return 1
    fi

    # Extract API key from config
    local api_key
    api_key=$(grep -oP '(?<=<ApiKey>)[^<]+' prowlarr/config.xml 2>/dev/null)

    if [ -z "$api_key" ]; then
        echo "   ⚠️  Could not extract Prowlarr API key"
        echo "   💡 Configure FlareSolverr manually in Prowlarr"
        return 1
    fi

    # Wait for Prowlarr API to be ready
    echo "   Waiting for Prowlarr API to be ready..."
    attempt=1
    while ! curl -s "http://localhost:9696/api/v1/system/status" -H "X-Api-Key: $api_key" >/dev/null 2>&1 && [ $attempt -le $max_attempts ]; do
        sleep 2
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo "   ⚠️  Prowlarr API not responding"
        return 1
    fi

    # Check if FlareSolverr is already configured
    local existing
    existing=$(curl -s "http://localhost:9696/api/v1/indexerproxy" -H "X-Api-Key: $api_key" 2>/dev/null)

    if echo "$existing" | grep -q "FlareSolverr"; then
        echo "   ✅ FlareSolverr already configured in Prowlarr"
        return 0
    fi

    # First create a tag for FlareSolverr
    local tag_response
    tag_response=$(curl -s -X POST "http://${locip}:9696/api/v1/tag" \
        -H "X-Api-Key: $api_key" \
        -H "Content-Type: application/json" \
        -d '{"label":"flaresolverr"}' 2>/dev/null)

    local tag_id
    tag_id=$(echo "$tag_response" | grep -oP '"id":\s*\K\d+' | head -1)

    if [ -z "$tag_id" ]; then
        # Tag might already exist, try to get it
        tag_id=$(curl -s "http://${locip}:9696/api/v1/tag" -H "X-Api-Key: $api_key" 2>/dev/null | grep -oP '"id":\s*(\d+).*?"label":\s*"flaresolverr"' | grep -oP '"id":\s*\K\d+' | head -1)
    fi

    # Build tags array
    local tags_json="[]"
    if [ -n "$tag_id" ]; then
        tags_json="[$tag_id]"
    fi

    # Add FlareSolverr via API
    local response
    response=$(curl -s -X POST "http://${locip}:9696/api/v1/indexerproxy" \
        -H "X-Api-Key: $api_key" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"FlareSolverr\",\"implementation\":\"FlareSolverr\",\"implementationName\":\"FlareSolverr\",\"configContract\":\"FlareSolverrSettings\",\"fields\":[{\"name\":\"host\",\"value\":\"http://${locip}:8191\"},{\"name\":\"requestTimeout\",\"value\":60}],\"tags\":$tags_json}" 2>/dev/null)

    if echo "$response" | grep -q '"id"'; then
        echo "   ✅ FlareSolverr configured in Prowlarr"
        echo "      Host: http://${locip}:8191"
        return 0
    else
        echo "   ⚠️  Failed to configure FlareSolverr automatically"
        echo "   💡 Configure manually in Prowlarr:"
        echo "      Settings → Indexers → Add → FlareSolverr"
        echo "      Host: http://${locip}:8191"
        return 1
    fi
}

# Configure FlareSolverr in Prowlarr
configure_prowlarr_flaresolverr

# Setup Plex Integration (if enabled)
if [ "$plex_enabled" == "true" ]; then
    printf "\\n🎬 Setting up Plex integration...\\n"
    
    if wait_for_plex_service && setup_plex_token; then
        printf "✅ Plex integration configured successfully!\\n"
        printf "   - Automatic library updates enabled after media processing\\n"
        printf "   - Token stored securely in credentials file\\n"
    else
        printf "❌ Automatic Plex setup failed\\n"
        printf "\\n📋 To configure Plex manually later, run:\\n"
        printf "   cd %s/scripts\\n" "$PWD"
        printf "   python3 get-plex-token.py --interactive\\n"
        printf "\\n📖 See PLEX_TOKEN_SETUP_GUIDE.md for detailed instructions\\n"
    fi
    printf "\\n"
fi

# Completion Message
printf "Setup Complete - Open a browser and go to: \\n\\n"
printf "http://%s \\nOR http://%s If you have appropriate DNS configured.\\n\\n" "$locip" "$thishost"

if [ "$plex_enabled" == "true" ]; then
    printf "🎬 Plex Integration Status:\\n"
    if grep -q "PLEX_TOKEN=" .env 2>/dev/null; then
        printf "   ✅ Configured - Library updates will happen automatically after media processing\\n"
    else
        printf "   ⚠️  Manual setup needed - Run: cd scripts && python3 get-plex-token.py --interactive\\n"
    fi
    printf "\\n"
fi

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
VENV_DIR="$SCRIPTS_DIR/.venv"
REQ_FILE="$SCRIPTS_DIR/requirements.txt"
PY_FILE="$SCRIPTS_DIR/media_update.py"
IMPORT_SH="$SCRIPTS_DIR/import.sh"
PY_SCRIPT="$SCRIPTS_DIR/media_update.py"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# Install required packages
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$REQ_FILE"
deactivate

cat > "$SCRIPTS_DIR/mediabox_config.json" <<EOF
{
  "venv_path": "$VENV_DIR",
  "env_file": "$INSTALL_DIR/.env",
  "database_path": "$SCRIPTS_DIR/media_cache.db",
  "download_dirs": ["$dldirectory/completed", "$dldirectory/incomplete"],
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
  },
  "transcoding": {
    "video": {
      "codec": "libx264",
      "crf": 23,
      "audio_codec": "aac"
    },
    "audio": {
      "codec": "libmp3lame",
      "bitrate": "320k"
    }
  }
}
EOF

# Setup log rotation cron job
echo "Setting up automatic log rotation..."
CRON_ENTRY="0 2 * * 0 cd $SCRIPTS_DIR && ./rotate-logs.sh >> $SCRIPTS_DIR/log-rotation_\$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1"
CRON_COMMENT="# Mediabox log rotation - runs weekly on Sundays at 2 AM"

# Check if cron job already exists
if ! crontab -l 2>/dev/null | grep -q "rotate-logs.sh"; then
    # Add the cron job
    (crontab -l 2>/dev/null; echo "$CRON_COMMENT"; echo "$CRON_ENTRY") | crontab -
    echo "✓ Log rotation cron job added (runs weekly on Sundays at 2 AM)"
else
    echo "✓ Log rotation cron job already exists"
fi

# Setup media cleanup cron job  
echo "Setting up automatic media cleanup..."
CLEANUP_CRON_ENTRY="0 3 * * 1 cd $SCRIPTS_DIR && python3 remove_files.py >> $SCRIPTS_DIR/cleanup_downloads_\$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1"
CLEANUP_CRON_COMMENT="# Mediabox media cleanup - runs weekly on Mondays at 3 AM"

# Check if cleanup cron job already exists
if ! crontab -l 2>/dev/null | grep -q "remove_files.py"; then
    # Add the cleanup cron job
    (crontab -l 2>/dev/null; echo "$CLEANUP_CRON_COMMENT"; echo "$CLEANUP_CRON_ENTRY") | crontab -
    echo "✓ Media cleanup cron job added (runs weekly on Mondays at 3 AM)"
else
    echo "✓ Media cleanup cron job already exists"
fi

# Setup cache cleanup cron job
echo "Setting up automatic cache cleanup..."
CACHE_CLEANUP_CRON_ENTRY="0 4 * * 0 cd $SCRIPTS_DIR && python3 build_media_database.py --cleanup $MOVIEDIR $TVDIR $MUSICDIR >> $SCRIPTS_DIR/cache_cleanup_\$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1"
CACHE_CLEANUP_CRON_COMMENT="# Mediabox cache cleanup - removes stale cache entries weekly on Sundays at 4 AM"

# Check if cache cleanup cron job already exists
if ! crontab -l 2>/dev/null | grep -q "build_media_database.py --cleanup"; then
    # Add the cache cleanup cron job
    (crontab -l 2>/dev/null; echo "$CACHE_CLEANUP_CRON_COMMENT"; echo "$CACHE_CLEANUP_CRON_ENTRY") | crontab -
    echo "✓ Cache cleanup cron job added (runs weekly on Sundays at 4 AM)"
else
    echo "✓ Cache cleanup cron job already exists"
fi

# Setup conversion cleanup cron job (runs on system boot only)
echo "Setting up automatic conversion cleanup..."
CONVERSION_CLEANUP_CRON_ENTRY_BOOT="@reboot cd $SCRIPTS_DIR && ./cleanup-conversions.sh --live >> $SCRIPTS_DIR/cleanup-conversions_\$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1"
CONVERSION_CLEANUP_CRON_COMMENT="# Mediabox conversion cleanup - runs on boot to clean up any corruption from unexpected shutdown"

# Check if conversion cleanup cron job already exists
if ! crontab -l 2>/dev/null | grep -q "cleanup-conversions.sh"; then
    # Add boot cleanup cron job only
    (crontab -l 2>/dev/null; echo "$CONVERSION_CLEANUP_CRON_COMMENT"; echo "$CONVERSION_CLEANUP_CRON_ENTRY_BOOT") | crontab -
    echo "✓ Conversion cleanup cron job added (runs on boot only)"
else
    echo "✓ Conversion cleanup cron job already exists"
fi

# Webhook Configuration Instructions
show_webhook_configuration() {
    echo "🔗 *ARR WEBHOOK CONFIGURATION"
    echo "Configure these webhooks after setup completes:"
    echo ""
    echo "📺 SONARR (TV Shows) - http://localhost:8989"
    echo "   1. Settings → Connect → Add → Custom Script"
    echo "   2. Name: 'Mediabox Processing'"
    echo "   3. Path: /scripts/import.sh"
    echo "   4. Triggers: ☑ On Import, ☑ On Upgrade"
    echo "   5. Arguments: (leave blank)"
    echo ""
    echo "🎬 RADARR (Movies) - http://localhost:7878"
    echo "   1. Settings → Connect → Add → Custom Script"
    echo "   2. Name: 'Mediabox Processing'"
    echo "   3. Path: /scripts/import.sh"
    echo "   4. Triggers: ☑ On Import, ☑ On Upgrade"
    echo "   5. Arguments: (leave blank)"
    echo ""
    echo "🎵 LIDARR (Music) - http://localhost:8686"
    echo "   1. Settings → Connect → Add → Custom Script"
    echo "   2. Name: 'Mediabox Processing'"
    echo "   3. Path: /scripts/import.sh"
    echo "   4. Triggers: ☑ On Import, ☑ On Upgrade"
    echo "   5. Arguments: (leave blank)"
    echo ""
}

# Installation Validation
validate_installation() {
    echo "🔍 INSTALLATION VALIDATION"
    
    # Check containers are running
    local containers=("sonarr" "radarr" "lidarr" "plex" "homer" "portainer" "flaresolverr" "prowlarr")
    echo "Checking container status..."
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            echo "  ✅ $container"
        else
            echo "  ⚠️  $container (not running)"
        fi
    done
    
    # Check virtual environment access in containers
    echo ""
    echo "Checking virtual environment access in *arr containers..."
    for container in sonarr radarr lidarr; do
        if docker exec "$container" /scripts/.venv/bin/python -c "import requests, plexapi; print('OK')" 2>/dev/null | grep -q "OK"; then
            echo "  ✅ $container (venv packages accessible)"
        else
            echo "  ⚠️  $container (venv packages not accessible)"
        fi
    done
    
    # Check scripts mount
    echo ""
    echo "Checking script mounts..."
    for container in sonarr radarr lidarr; do
        if docker exec "$container" test -f "/scripts/import.sh" 2>/dev/null; then
            echo "  ✅ $container (scripts mounted)"
        else
            echo "  ❌ $container (scripts not mounted)"
        fi
    done
    
    # Test host environment
    echo ""
    echo "Checking host environment..."
    if [[ -f "$VENV_DIR/bin/activate" ]]; then
        source "$VENV_DIR/bin/activate"
        if python3 "$SCRIPTS_DIR/media_update.py" --help >/dev/null 2>&1; then
            echo "  ✅ Host Python environment working"
        else
            echo "  ⚠️  Host Python environment has issues"
        fi
        deactivate
    else
        echo "  ❌ Virtual environment not found"
    fi
    
    echo ""
}

# Show troubleshooting information
show_troubleshooting() {
    echo "🔧 TROUBLESHOOTING"
    echo ""
    echo "If virtual environment packages are not accessible in containers:"
    echo "   # Rebuild host virtual environment:"
    echo "   cd scripts && rm -rf .venv"
    echo "   python3 -m venv .venv"
    echo "   source .venv/bin/activate && pip install -r requirements.txt"
    echo ""
    echo "If containers can't access /scripts/.venv:"
    echo "   # Check docker-compose.yml volume mounts for *arr services"
    echo "   # Should include: ./scripts:/scripts"
    echo ""
    echo "If Plex token is missing:"
    echo "   cd scripts && source .venv/bin/activate"
    echo "   python3 get-plex-token.py --interactive"
    echo ""
    echo "To test webhook integration manually:"
    echo "   docker exec sonarr bash -c 'export sonarr_eventtype=Test && /scripts/import.sh'"
    echo ""
    echo "If FlareSolverr is not working:"
    echo "   # Check if FlareSolverr is running:"
    echo "   curl http://localhost:8191/health"
    echo "   # Check FlareSolverr logs:"
    echo "   docker logs flaresolverr"
    echo "   # Verify Prowlarr configuration:"
    echo "   # Settings → Indexers → Indexer Proxies → FlareSolverr should be listed"
    echo "   # Assign 'flaresolverr' tag to indexers that need Cloudflare bypass"
    echo ""
    echo "View logs for debugging:"
    echo "   tail -f scripts/import_\$(date +%Y%m%d).log"
    echo "   tail -f scripts/media_update_*.log"
    echo "   docker logs [container_name]"
    echo ""
}

# Prompt to add shell alias for low-priority batch media conversion
setup_media_update_alias() {
    echo ""
    echo "📝 Shell Alias Setup"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "For manual batch media conversions, you can add a shell alias that"
    echo "automatically runs media_update.py with low priority (nice/ionice)."
    echo ""
    echo "This ensures batch conversions don't interfere with Plex or other services."
    echo ""
    echo "Alias: media_update_batch"
    echo "Command: nice -n 19 ionice -c 2 -n 7 python3 $SCRIPTS_DIR/media_update.py"
    echo ""
    read -r -p "Add this alias to your ~/.bashrc? (y/n): " add_alias

    if [[ "$add_alias" == "y" || "$add_alias" == "Y" ]]; then
        local bashrc="$HOME/.bashrc"

        # Check if alias already exists
        if grep -q "alias media_update_batch=" "$bashrc" 2>/dev/null; then
            echo "⚠️  Alias already exists in ~/.bashrc - skipping"
        else
            # Add alias with helpful comment
            echo "" >> "$bashrc"
            echo "# Mediabox - Low priority batch media conversion" >> "$bashrc"
            echo "alias media_update_batch='nice -n 19 ionice -c 2 -n 7 python3 $SCRIPTS_DIR/media_update.py'" >> "$bashrc"
            echo "✅ Alias added to ~/.bashrc"
            echo ""
            echo "Usage: media_update_batch --dir /path/to/media --type video"
            echo "Note: Reload your shell or run 'source ~/.bashrc' to activate"
        fi
    else
        echo "⏭️  Skipping alias setup"
        echo "You can manually add it later with:"
        echo "  alias media_update_batch='nice -n 19 ionice -c 2 -n 7 python3 $SCRIPTS_DIR/media_update.py'"
    fi
    echo ""
}

# Run validation and show configuration
validate_installation
show_webhook_configuration
show_troubleshooting
setup_media_update_alias

echo ""
echo "Mediabox setup completed successfully!"
echo ""
echo "Automation features:"
echo "  - Webhook processing: Automatic media conversion on download"
echo "  - Log rotation: Weekly compression and cleanup (Sundays at 2 AM)"
echo "  - Media cleanup: Weekly duplicate/old file removal (Mondays at 3 AM)"
echo "  - Conversion cleanup: Corrupted/incomplete file cleanup (on boot only)"
echo ""
echo "Manual operations:"
echo "  - Log rotation: cd $SCRIPTS_DIR && ./rotate-logs.sh"
echo "  - Media cleanup: cd $SCRIPTS_DIR && python3 remove_files.py"
echo "  - Conversion cleanup: cd $SCRIPTS_DIR && ./cleanup-conversions.sh --live"
echo "  - Batch conversion: media_update_batch --dir [path] --type [video|audio|both]"
echo "    (Or directly: cd $SCRIPTS_DIR && python3 media_update.py --dir [path] --type [video|audio|both])"
echo ""
echo "Log locations:"
echo "  - Webhook activity: $SCRIPTS_DIR/import_YYYYMMDD.log"
echo "  - Media processing: $SCRIPTS_DIR/media_update_YYYYMMDDHHMMSS.log"
echo "  - Log rotation: $SCRIPTS_DIR/log-rotation_YYYYMMDD_HHMMSS.log"
echo "  - Media cleanup: $SCRIPTS_DIR/cleanup_downloads_YYYYMMDD_HHMMSS.log"
echo "  - Conversion cleanup: $SCRIPTS_DIR/cleanup-conversions_YYYYMMDD_HHMMSS.log"
echo "  - Retention policy: 14 days uncompressed, 90 days compressed, then deleted"
echo ""

exit
