#!/bin/bash
#
# Standalone Media Converter Installation Script
# 
# This script installs only the media_update.py conversion tools without
# the full Mediabox Docker stack. Ideal for dedicated conversion workstations
# with powerful hardware (NVIDIA GPUs, high-end CPUs).
#
# Usage: ./install-media-converter.sh [--gpu nvidia|intel|none]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/mediabox-converter}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
GPU_TYPE="${1:-auto}"  # auto, nvidia, intel, none

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Banner
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║     Mediabox Standalone Media Converter Installer         ║"
echo "║                                                           ║"
echo "║  Install media_update.py conversion tools on any system   ║"
echo "║  Optimized for dedicated conversion workstations          ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Parse command line arguments
if [[ "${1:-}" =~ ^--gpu=(nvidia|intel|none)$ ]]; then
    GPU_TYPE="${1#--gpu=}"
elif [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << 'EOF'
Mediabox Standalone Media Converter Installation

USAGE:
    ./install-media-converter.sh [OPTIONS]

OPTIONS:
    --gpu=TYPE          Specify GPU acceleration type
                        Values: auto, nvidia, intel, none
                        Default: auto (auto-detect)
    
    -h, --help          Show this help message

ENVIRONMENT VARIABLES:
    INSTALL_DIR         Installation directory (default: ~/.local/share/mediabox-converter)
    BIN_DIR             Binary symlink directory (default: ~/.local/bin)

EXAMPLES:
    # Auto-detect GPU
    ./install-media-converter.sh

    # Force NVIDIA GPU support
    ./install-media-converter.sh --gpu=nvidia

    # Force Intel VAAPI support
    ./install-media-converter.sh --gpu=intel

    # Software encoding only (no GPU)
    ./install-media-converter.sh --gpu=none

    # Custom installation directory
    INSTALL_DIR=/opt/mediabox ./install-media-converter.sh

FEATURES:
    ✓ HDR to SDR tone mapping (automatic)
    ✓ Audio enhancement (dialogue normalization, stereo mixing)
    ✓ Subtitle processing (forced/English extraction)
    ✓ Hardware acceleration (NVIDIA/Intel/software fallback)
    ✓ Batch processing capabilities
    ✓ Production-ready logging

REQUIREMENTS:
    - Ubuntu 18.04+ / Debian 10+ / similar Linux distribution
    - Python 3.8+
    - FFmpeg 4.2+ (will be installed if missing)
    - 4GB+ RAM (8GB+ recommended for 4K HDR)
    - For GPU: NVIDIA drivers or Intel i965-va-driver

EOF
    exit 0
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error_exit "This script should NOT be run as root. Run as regular user." 1
fi

# System requirements check
log_info "Checking system requirements..."

# Check OS
if [[ ! -f /etc/os-release ]]; then
    error_exit "Cannot detect OS. /etc/os-release not found." 1
fi

source /etc/os-release
log_info "Detected OS: ${NAME} ${VERSION}"

# Check Python version
if ! command -v python3 &> /dev/null; then
    error_exit "Python 3 is required but not installed. Install with: sudo apt install python3" 1
fi

PYTHON_VERSION=$(python3 --version | awk '{print $2}')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ $PYTHON_MAJOR -lt 3 ]] || [[ $PYTHON_MAJOR -eq 3 && $PYTHON_MINOR -lt 8 ]]; then
    error_exit "Python 3.8+ required. Found: $PYTHON_VERSION" 1
fi

log_success "Python $PYTHON_VERSION detected"

# Check for pip
if ! command -v pip3 &> /dev/null; then
    log_warning "pip3 not found. Installing python3-pip..."
    sudo apt update && sudo apt install -y python3-pip python3-venv || error_exit "Failed to install pip3" 1
fi

# Check for FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    log_warning "FFmpeg not found. Installing..."
    sudo apt update && sudo apt install -y ffmpeg || error_exit "Failed to install FFmpeg" 1
fi

FFMPEG_VERSION=$(ffmpeg -version | head -1 | awk '{print $3}')
log_success "FFmpeg $FFMPEG_VERSION detected"

# Verify FFmpeg has zscale filter (required for HDR tone mapping)
if ! ffmpeg -filters 2>/dev/null | grep -q "zscale"; then
    log_warning "FFmpeg zscale filter not found. HDR tone mapping may not work."
    log_warning "Consider upgrading FFmpeg to version 4.2 or later."
fi

# GPU Detection and Setup
log_info "Detecting GPU capabilities..."

DETECTED_GPU="none"
GPU_PACKAGE=""

if [[ "$GPU_TYPE" == "auto" ]]; then
    # Auto-detect NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        NVIDIA_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        if [[ -n "$NVIDIA_GPU" ]]; then
            DETECTED_GPU="nvidia"
            log_success "NVIDIA GPU detected: $NVIDIA_GPU"
        fi
    fi
    
    # Auto-detect Intel
    if [[ "$DETECTED_GPU" == "none" ]] && lspci | grep -qi "VGA.*Intel"; then
        DETECTED_GPU="intel"
        log_success "Intel GPU detected"
        GPU_PACKAGE="i965-va-driver-shaders intel-media-va-driver-non-free"
    fi
    
    if [[ "$DETECTED_GPU" == "none" ]]; then
        log_warning "No GPU detected. Will use software encoding."
    fi
else
    DETECTED_GPU="$GPU_TYPE"
    log_info "GPU type forced to: $DETECTED_GPU"
fi

# Install GPU drivers if needed
if [[ "$DETECTED_GPU" == "intel" ]] && [[ -n "$GPU_PACKAGE" ]]; then
    log_info "Installing Intel VAAPI drivers..."
    sudo apt update && sudo apt install -y $GPU_PACKAGE || log_warning "Failed to install Intel drivers. Will fallback to software."
fi

if [[ "$DETECTED_GPU" == "nvidia" ]]; then
    # Check for nvidia-docker/nvidia-container-toolkit (not needed for standalone, but good to have)
    log_info "NVIDIA GPU detected. Ensure FFmpeg is compiled with NVENC support."
    log_warning "For NVENC hardware encoding, FFmpeg must be built with --enable-cuda-nvcc and --enable-nvenc"
    log_warning "Consider using FFmpeg from conda-forge or building from source if needed."
fi

# Create installation directory
log_info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# Create Python virtual environment
log_info "Creating Python virtual environment..."
if [[ -d "$INSTALL_DIR/.venv" ]]; then
    log_warning "Virtual environment already exists. Removing and recreating..."
    rm -rf "$INSTALL_DIR/.venv"
fi

python3 -m venv "$INSTALL_DIR/.venv" || error_exit "Failed to create virtual environment" 1
log_success "Virtual environment created"

# Get the directory where this script is located (needed for file operations below)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate virtual environment
source "$INSTALL_DIR/.venv/bin/activate"

# Install Python dependencies
log_info "Installing Python dependencies..."
pip install --upgrade pip setuptools wheel

# Install all required dependencies from requirements.txt if available, otherwise install manually
if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
    log_info "Installing from requirements.txt..."
    pip install -r "$SCRIPT_DIR/requirements.txt" || error_exit "Failed to install Python dependencies" 1
else
    log_warning "requirements.txt not found, installing dependencies manually..."
    pip install ffmpeg-python==0.2.0 future==1.0.0 PlexAPI==4.15.8 requests==2.31.0 || error_exit "Failed to install Python dependencies" 1
fi
log_success "Python dependencies installed"

# Copy media_update.py script
log_info "Installing media_update.py..."

if [[ ! -f "$SCRIPT_DIR/media_update.py" ]]; then
    error_exit "media_update.py not found in $SCRIPT_DIR. Please run from the scripts/ directory." 1
fi

cp "$SCRIPT_DIR/media_update.py" "$INSTALL_DIR/" || error_exit "Failed to copy media_update.py" 1
chmod +x "$INSTALL_DIR/media_update.py"
log_success "media_update.py installed"

# Copy file locking module for distributed processing
log_info "Installing file locking support..."
if [[ -f "$SCRIPT_DIR/file_lock.py" ]]; then
    cp "$SCRIPT_DIR/file_lock.py" "$INSTALL_DIR/" || log_warning "Failed to copy file_lock.py"
    log_success "file_lock.py installed (distributed processing support)"
else
    log_warning "file_lock.py not found - distributed processing may not work"
fi

# Copy media database files if they exist (optional but recommended for caching)
log_info "Installing database support files..."
if [[ -f "$SCRIPT_DIR/media_database.py" ]]; then
    cp "$SCRIPT_DIR/media_database.py" "$INSTALL_DIR/" || log_warning "Failed to copy media_database.py"
    log_success "media_database.py installed (caching enabled)"
else
    log_warning "media_database.py not found - caching will be disabled"
fi

if [[ -f "$SCRIPT_DIR/build_media_database.py" ]]; then
    cp "$SCRIPT_DIR/build_media_database.py" "$INSTALL_DIR/" || log_warning "Failed to copy build_media_database.py"
    chmod +x "$INSTALL_DIR/build_media_database.py"
    log_info "build_media_database.py installed"
fi

if [[ -f "$SCRIPT_DIR/query_media_database.py" ]]; then
    cp "$SCRIPT_DIR/query_media_database.py" "$INSTALL_DIR/" || log_warning "Failed to copy query_media_database.py"
    chmod +x "$INSTALL_DIR/query_media_database.py"
    log_info "query_media_database.py installed"
fi

# Copy requirements.txt if it exists
if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
    cp "$SCRIPT_DIR/requirements.txt" "$INSTALL_DIR/"
fi

# Create configuration file
log_info "Creating configuration file..."
cat > "$INSTALL_DIR/mediabox_config.json" << EOF
{
  "venv_path": "$INSTALL_DIR/.venv",
  "env_file": "$INSTALL_DIR/.env",
  "download_dirs": [],
  "library_dirs": {
    "tv": "",
    "movies": "",
    "music": "",
    "misc": ""
  },
  "container_support": false,
  "plex_integration": {
    "url": "",
    "token": "",
    "path_mappings": {
      "tv": "",
      "movies": "",
      "music": ""
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
  },
  "gpu_type": "$DETECTED_GPU"
}
EOF

log_success "Configuration created: $INSTALL_DIR/mediabox_config.json"

# Create wrapper script
log_info "Creating wrapper script..."
cat > "$BIN_DIR/media-converter" << 'EOF'
#!/bin/bash
# Mediabox Media Converter - Wrapper Script
# Auto-generated by install-media-converter.sh

INSTALL_DIR="__INSTALL_DIR__"
VENV_PYTHON="$INSTALL_DIR/.venv/bin/python3"

if [[ ! -f "$VENV_PYTHON" ]]; then
    echo "ERROR: Virtual environment not found at $INSTALL_DIR/.venv"
    echo "Please reinstall using install-media-converter.sh"
    exit 1
fi

# Pass all arguments to media_update.py
exec "$VENV_PYTHON" "$INSTALL_DIR/media_update.py" "$@"
EOF

# Replace placeholder
sed -i "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$BIN_DIR/media-converter"
chmod +x "$BIN_DIR/media-converter"
log_success "Wrapper script created: $BIN_DIR/media-converter"

# Add BIN_DIR to PATH if not already there
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    log_info "Adding $BIN_DIR to PATH..."
    
    # Determine shell config file
    if [[ -f "$HOME/.bashrc" ]]; then
        SHELL_RC="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_RC="$HOME/.bash_profile"
    elif [[ -f "$HOME/.profile" ]]; then
        SHELL_RC="$HOME/.profile"
    else
        SHELL_RC=""
    fi
    
    if [[ -n "$SHELL_RC" ]]; then
        echo "" >> "$SHELL_RC"
        echo "# Mediabox Media Converter" >> "$SHELL_RC"
        echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$SHELL_RC"
        log_success "Added to PATH in $SHELL_RC (reload shell or run: source $SHELL_RC)"
    else
        log_warning "Could not find shell config file. Manually add $BIN_DIR to PATH."
    fi
fi

# Create example usage script
cat > "$INSTALL_DIR/USAGE.md" << 'EOF'
# Mediabox Media Converter - Standalone Usage

## Quick Start

### Process a Single File
```bash
media-converter --file "/path/to/video.mp4" --type video
```

### Process a Directory (Batch)
```bash
media-converter --dir "/path/to/media" --type both
```

### HDR Content (Automatic Detection)
```bash
# HDR will be automatically detected and tone mapped to SDR
media-converter --file "/path/to/hdr_video.mp4" --type video --downgrade-resolution
```

### Audio Enhancement
```bash
# Create dialogue-enhanced stereo track
media-converter --file "/path/to/movie.mp4" --type audio --force-stereo
```

## Command Reference

### Options
- `--file FILE` - Process single file
- `--dir DIR` - Process entire directory
- `--type {video,audio,both}` - Processing type (default: both)
- `--force-stereo` - Force stereo track creation with dialogue enhancement
- `--downgrade-resolution` - Scale 4K+ to 1080p

### Examples

#### 4K HDR Movie to 1080p SDR
```bash
media-converter --file "movie.mp4" --type video --downgrade-resolution
```

#### TV Show Directory (Video Only)
```bash
media-converter --dir "/media/tv/ShowName/Season 01" --type video
```

#### Music Library (Audio Conversion)
```bash
media-converter --dir "/media/music/ArtistName" --type audio
```

## Configuration

Edit `~/.local/share/mediabox-converter/mediabox_config.json` to customize:

- Library directories
- Transcoding settings (codec, quality, bitrate)
- GPU acceleration type

## Logs

Logs are created in the current directory:
- `media_update_YYYYMMDD.log` - Current log
- `media_update_YYYYMMDD.log.gz` - Compressed old logs

## GPU Acceleration

### NVIDIA (NVENC)
Requires FFmpeg built with CUDA/NVENC support. May need custom FFmpeg build.

### Intel (VAAPI)
Automatically detected if drivers installed. Uses `/dev/dri/renderD128`.

### Software Fallback
Always available. Uses libx264 (slower but works everywhere).

## HDR Processing

**Automatic Detection:**
- HDR10 (smpte2084 PQ transfer)
- HLG (Hybrid Log-Gamma)
- Dolby Vision (side data detection)

**Tone Mapping:**
- Hable algorithm (filmic)
- BT.2020 → BT.709 conversion
- 10/12-bit → 8-bit output

**Performance:**
- Software encoding required (zscale filter)
- Expect 1-3x real-time on modern CPUs
- NVIDIA/Intel acceleration not available for HDR tone mapping

## Troubleshooting

### Command Not Found
```bash
# Reload shell configuration
source ~/.bashrc

# Or use full path
~/.local/bin/media-converter --help
```

### GPU Not Detected
```bash
# Check GPU
lspci | grep -i vga

# NVIDIA
nvidia-smi

# Intel VAAPI
ls -la /dev/dri/
```

### FFmpeg Errors
```bash
# Verify FFmpeg installation
ffmpeg -version

# Check zscale filter (HDR support)
ffmpeg -filters | grep zscale
```

## Performance Tips

### Multi-Core Processing
Run multiple instances in parallel for batch processing:
```bash
# Terminal 1
media-converter --file "file1.mp4" --type video &

# Terminal 2
media-converter --file "file2.mp4" --type video &

# Wait for all
wait
```

### Watch Directory
Use with `inotifywait` for automatic processing:
```bash
inotifywait -m /path/to/downloads -e close_write --format '%w%f' | while read file; do
    media-converter --file "$file" --type both
done
```

## Uninstallation

```bash
# Remove installation
rm -rf ~/.local/share/mediabox-converter

# Remove wrapper script
rm ~/.local/bin/media-converter

# Remove PATH entry from shell config
# Edit ~/.bashrc and remove the Mediabox Media Converter section
```

## Support

For issues, see full documentation:
- `/Storage/docker/mediabox/docs/HDR_TONE_MAPPING.md`
- `/Storage/docker/mediabox/README.md`

Or check logs in current directory for detailed error messages.
EOF

log_success "Usage guide created: $INSTALL_DIR/USAGE.md"

# Installation summary
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║              Installation Complete! ✅                     ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
log_success "Installation directory: $INSTALL_DIR"
log_success "Command wrapper: $BIN_DIR/media-converter"
log_success "Configuration: $INSTALL_DIR/mediabox_config.json"
log_success "GPU acceleration: $DETECTED_GPU"

# Show database tools status
if [[ -f "$INSTALL_DIR/media_database.py" ]]; then
    log_success "Database caching: ENABLED (11x faster scans)"
else
    log_warning "Database caching: DISABLED (media_database.py not found)"
fi

echo ""
echo "Next steps:"
echo "  1. Reload your shell: source ~/.bashrc"
echo "  2. Test installation: media-converter --help"
echo "  3. Read usage guide: cat $INSTALL_DIR/USAGE.md"
echo ""

# Show database tools if installed
if [[ -f "$INSTALL_DIR/build_media_database.py" ]]; then
    echo "Database tools installed:"
    echo "  # Build database cache (speeds up re-scans by 11x)"
    echo "  cd $INSTALL_DIR && python3 build_media_database.py --scan /path/to/media"
    echo ""
    echo "  # Query HDR files"
    echo "  cd $INSTALL_DIR && python3 query_media_database.py --hdr"
    echo ""
fi

echo "Conversion examples:"
echo "  # Single file"
echo "  media-converter --file '/path/to/video.mp4' --type video"
echo ""
echo "  # Directory batch processing"
echo "  media-converter --dir '/path/to/media' --type both"
echo ""
echo "  # HDR tone mapping (automatic)"
echo "  media-converter --file 'hdr_movie.mp4' --type video --downgrade-resolution"
echo ""
log_info "For detailed usage, see: $INSTALL_DIR/USAGE.md"
echo ""
