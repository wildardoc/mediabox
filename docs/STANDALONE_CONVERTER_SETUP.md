# Standalone Media Converter Setup

## Overview

The standalone media converter allows you to run `media_update.py` on **any Linux system** without the full Mediabox Docker stack. This is ideal for:

- **Dedicated conversion workstations** with powerful hardware
- **Desktop systems with NVIDIA GPUs** for faster encoding
- **Temporary batch processing** during library upgrades
- **Multi-system workflows** (convert on desktop, deploy to server)

## Use Case: Multi-Month Library Upgrade

### Problem
Processing a large media library (700+ movies, hundreds of TV episodes) can take **weeks or months** on a server, especially with HDR tone mapping requiring CPU-intensive software encoding.

### Solution
Use your **Ubuntu 24.04 desktop with NVIDIA GPU** to handle the heavy conversion workload:

```
┌─────────────────────────┐         ┌──────────────────────────┐
│  Ubuntu 24.04 Desktop   │         │   Media Server (NAS)     │
│  ─────────────────────  │         │  ──────────────────────  │
│                         │         │                          │
│  • NVIDIA GPU           │────────▶│  • Stores media files    │
│  • High-end CPU         │ Convert │  • Runs Plex/Sonarr      │
│  • Fast conversion      │  files  │  • Serves to clients     │
│  • 5-10x faster         │         │  • Lightweight tasks     │
│                         │         │                          │
└─────────────────────────┘         └──────────────────────────┘
       (Conversion)                       (Storage/Serving)
```

## Installation

### Prerequisites

**Ubuntu 24.04 Desktop** (or similar):
- Python 3.8+
- FFmpeg 4.2+
- NVIDIA GPU with drivers (optional, for hardware acceleration)
- Network access to media files (NFS/SMB mount or local copy)

### Quick Install

1. **Clone the repository or copy the scripts:**
   ```bash
   # Option 1: Clone full repo
   git clone https://github.com/wildardoc/mediabox.git
   cd mediabox/scripts/
   
   # Option 2: Copy just the installer and media_update.py
   scp user@mediaserver:/Storage/docker/mediabox/scripts/install-media-converter.sh .
   scp user@mediaserver:/Storage/docker/mediabox/scripts/media_update.py .
   scp user@mediaserver:/Storage/docker/mediabox/scripts/requirements.txt .
   ```

2. **Run the installer:**
   ```bash
   cd scripts/
   chmod +x install-media-converter.sh
   ./install-media-converter.sh --gpu=nvidia
   ```

3. **Reload your shell:**
   ```bash
   source ~/.bashrc
   ```

4. **Test installation:**
   ```bash
   media-converter --help
   ```

### Installation Options

```bash
# Auto-detect GPU (recommended)
./install-media-converter.sh

# Force NVIDIA GPU support
./install-media-converter.sh --gpu=nvidia

# Force Intel VAAPI support
./install-media-converter.sh --gpu=intel

# Software encoding only (no GPU)
./install-media-converter.sh --gpu=none

# Custom installation directory
INSTALL_DIR=/opt/mediabox ./install-media-converter.sh
```

## Mounting Media from Server

### Option 1: NFS Mount (Recommended)

**On the media server:**
```bash
# Install NFS server
sudo apt install nfs-kernel-server

# Add export to /etc/exports
sudo nano /etc/exports

# Add this line (adjust IP for your desktop):
/Storage/media 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

# Apply changes
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

**On your Ubuntu desktop:**
```bash
# Install NFS client
sudo apt install nfs-common

# Create mount point
sudo mkdir -p /mnt/media

# Mount NFS share
sudo mount -t nfs mediaserver:/Storage/media /mnt/media

# Verify mount
ls -la /mnt/media/movies

# Make persistent (add to /etc/fstab)
echo "mediaserver:/Storage/media /mnt/media nfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
```

### Option 2: SMB/CIFS Mount

**On your Ubuntu desktop:**
```bash
# Install CIFS utilities
sudo apt install cifs-utils

# Create mount point
sudo mkdir -p /mnt/media

# Mount SMB share
sudo mount -t cifs //mediaserver/media /mnt/media -o username=youruser,password=yourpass

# Or use credentials file for security
echo "username=youruser" | sudo tee /root/.smbcredentials
echo "password=yourpass" | sudo tee -a /root/.smbcredentials
sudo chmod 600 /root/.smbcredentials

sudo mount -t cifs //mediaserver/media /mnt/media -o credentials=/root/.smbcredentials

# Make persistent (/etc/fstab)
echo "//mediaserver/media /mnt/media cifs credentials=/root/.smbcredentials,_netdev 0 0" | sudo tee -a /etc/fstab
```

### Option 3: Local Copy (Fast Network)

If you have fast network and storage:
```bash
# Copy to local SSD for maximum speed
rsync -avh --progress user@mediaserver:/Storage/media/movies/ /media/local/movies/

# Process locally
media-converter --dir /media/local/movies --type video

# Copy back when done
rsync -avh --progress /media/local/movies/ user@mediaserver:/Storage/media/movies/
```

## NVIDIA GPU Optimization

### Verify NVIDIA Setup

```bash
# Check GPU
nvidia-smi

# Check FFmpeg NVENC support
ffmpeg -encoders 2>/dev/null | grep nvenc

# Expected output:
# V..... h264_nvenc           NVIDIA NVENC H.264 encoder
# V..... hevc_nvenc           NVIDIA NVENC hevc encoder
```

### FFmpeg with NVENC Support

Ubuntu 24.04's FFmpeg may not have NVENC enabled. Options:

#### Option 1: Install FFmpeg from conda-forge (Easiest)
```bash
# Install miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

# Create environment with FFmpeg
conda create -n ffmpeg -c conda-forge ffmpeg
conda activate ffmpeg

# Verify NVENC
ffmpeg -encoders | grep nvenc

# Use this FFmpeg for conversions
which ffmpeg  # Should show conda path
```

#### Option 2: Build FFmpeg from source
```bash
# Install build dependencies
sudo apt install build-essential yasm cmake libtool libc6 libc6-dev unzip wget \
  libnuma1 libnuma-dev libx264-dev libx265-dev libvpx-dev libfdk-aac-dev \
  libmp3lame-dev libopus-dev libaom-dev

# Clone FFmpeg
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg

# Configure with NVENC
./configure \
  --enable-nonfree \
  --enable-cuda-nvcc \
  --enable-libnpp \
  --extra-cflags=-I/usr/local/cuda/include \
  --extra-ldflags=-L/usr/local/cuda/lib64 \
  --enable-nvenc \
  --enable-gpl \
  --enable-libx264 \
  --enable-libx265

# Build and install
make -j$(nproc)
sudo make install
```

### Performance Expectations

| Hardware | Resolution | Format | Speed |
|----------|-----------|--------|-------|
| NVIDIA RTX 3060+ | 4K → 1080p | SDR (non-HDR) | 15-30x real-time |
| NVIDIA RTX 3060+ | 4K → 1080p | HDR tone mapping | 2-5x real-time |
| Intel i7/i9 (software) | 4K → 1080p | SDR (non-HDR) | 3-6x real-time |
| Intel i7/i9 (software) | 4K → 1080p | HDR tone mapping | 1-3x real-time |

**Note:** HDR tone mapping uses `zscale` filter which requires **software encoding** (CPU). NVENC cannot be used with zscale, so GPU provides no acceleration for HDR content.

## Processing Workflow

### Strategy 1: Batch Processing by Directory

Process entire TV show or movie collections:

```bash
# Process all movies
media-converter --dir /mnt/media/movies --type video --downgrade-resolution

# Process specific TV show
media-converter --dir /mnt/media/tv/ShowName --type video

# Process with screen for long-running jobs
screen -S conversion
media-converter --dir /mnt/media/movies --type both
# Press Ctrl+A then D to detach
# Reattach: screen -r conversion
```

### Strategy 2: Parallel Processing

Leverage multi-core CPUs by running multiple instances:

```bash
# Create processing script
cat > batch_convert.sh << 'EOF'
#!/bin/bash
for dir in /mnt/media/movies/*/; do
    echo "Processing: $dir"
    media-converter --dir "$dir" --type video --downgrade-resolution
done
EOF

chmod +x batch_convert.sh

# Run in screen
screen -S batch
./batch_convert.sh
```

### Strategy 3: GNU Parallel (Advanced)

Maximum parallelization:

```bash
# Install GNU Parallel
sudo apt install parallel

# Create file list
find /mnt/media/movies -name "*.mp4" -o -name "*.mkv" > /tmp/files.txt

# Process 4 files at a time
cat /tmp/files.txt | parallel -j4 media-converter --file {} --type video --downgrade-resolution

# Monitor progress
watch -n5 'ps aux | grep media-converter | wc -l'
```

### Strategy 4: Smart Bulk Converter (Recommended)

Use the smart bulk converter for intelligent resource management:

```bash
# Copy smart-bulk-convert.sh to desktop
scp user@mediaserver:/Storage/docker/mediabox/scripts/smart-bulk-convert.sh .
scp user@mediaserver:/Storage/docker/mediabox/scripts/smart_convert_config.json .

# Edit config for desktop CPU
nano smart_convert_config.json
# Adjust max_cpu_percent, max_parallel_jobs for your hardware

# Run converter
./smart-bulk-convert.sh /mnt/media/movies /mnt/media/tv

# Monitor in screen
screen -r mediabox-converter
```

## HDR Processing on Desktop

### Advantages
- **Faster CPU:** Desktop CPUs often faster than server CPUs
- **Dedicated resources:** No competition with Plex/Docker services
- **Progress monitoring:** Direct access to watch encoding progress

### Example: Cross TV Show Processing

```bash
# Mount media from server
sudo mount -t nfs mediaserver:/Storage/media /mnt/media

# Process Cross S01 (HDR content)
media-converter --dir "/mnt/media/tv/Cross/Season 01" --type video --downgrade-resolution

# Monitor progress
tail -f media_update_$(date +%Y%m%d).log

# Check HDR detection
grep "HDR content detected" media_update_*.log
```

**Expected output:**
```
🎨 HDR content detected: HDR10
   Color: bt2020, Transfer: smpte2084, 10-bit
✅ HDR→SDR tone mapping will be applied
Using software encoding for HDR tone mapping
```

## Workflow: Multi-Month Upgrade

### Phase 1: Setup (Day 1)

1. **Install on desktop:**
   ```bash
   ./install-media-converter.sh --gpu=nvidia
   ```

2. **Mount media from server:**
   ```bash
   sudo mount -t nfs mediaserver:/Storage/media /mnt/media
   ```

3. **Test conversion:**
   ```bash
   # Pick a sample file
   media-converter --file "/mnt/media/movies/TestMovie/movie.mp4" --type video
   
   # Verify output quality
   ffprobe output.mp4  # Check color_space=bt709
   mpv output.mp4      # Visual quality check
   ```

### Phase 2: Batch Processing (Weeks 1-4)

1. **Create priority list:**
   ```bash
   # Process frequently watched content first
   # Movies with pink tint issues (HDR content)
   # New acquisitions
   ```

2. **Start batch conversion:**
   ```bash
   screen -S conversion
   media-converter --dir /mnt/media/movies --type video --downgrade-resolution
   ```

3. **Monitor progress:**
   ```bash
   # Daily check
   screen -r conversion  # Check progress
   tail -f media_update_*.log
   
   # Count processed vs. remaining
   find /mnt/media/movies -name "*1080p.mp4" | wc -l  # Converted
   find /mnt/media/movies -name "*2160p.mp4" | wc -l  # Remaining
   ```

### Phase 3: Validation (Ongoing)

1. **Verify conversions:**
   ```bash
   # Random sampling
   find /mnt/media/movies -name "*1080p.mp4" | shuf -n10 | while read f; do
       echo "Checking: $f"
       ffprobe "$f" 2>&1 | grep -E "color_transfer|resolution"
   done
   ```

2. **Test playback:**
   - Play converted files on bedroom TV
   - Verify no pink tint
   - Check audio quality (stereo enhancement)

### Phase 4: Completion (Month 3+)

1. **Final sync to server:**
   ```bash
   # Ensure all conversions synced via NFS
   # Or if using local copy:
   rsync -avh --progress /media/local/movies/ user@mediaserver:/Storage/media/movies/
   ```

2. **Cleanup:**
   ```bash
   # Remove original 4K files if desired (save space)
   find /mnt/media/movies -name "*2160p.mp4" -delete
   
   # Or keep both versions
   mkdir /mnt/media/movies-4k-originals
   find /mnt/media/movies -name "*2160p.mp4" -exec mv {} /mnt/media/movies-4k-originals/ \;
   ```

3. **Update Plex:**
   - Plex will automatically detect new 1080p files
   - Refresh library metadata
   - Delete optimized versions (no longer needed)

## Performance Comparison

### Server vs. Desktop Processing

**Example: Cross S01E01 (1.7GB, 4K HDR → 1080p SDR)**

| System | CPU | GPU | Time | Speed |
|--------|-----|-----|------|-------|
| Media Server | Xeon E3-1270v2 | None | ~90 min | 0.7x real-time |
| Desktop | Ryzen 9 5900X | RTX 3070 | ~20 min | 3.2x real-time |
| Desktop (NVENC) | Ryzen 9 5900X | RTX 3070 | N/A | Not usable (HDR) |

**700 movies @ 1.5GB average:**

| System | Total Time |
|--------|-----------|
| Media Server | ~2-3 months |
| Desktop | ~2-3 weeks |

## Troubleshooting

### NFS Mount Timeout/Slow

```bash
# Add performance options to mount
sudo mount -t nfs -o rsize=8192,wsize=8192,timeo=14,intr mediaserver:/Storage/media /mnt/media

# Or in /etc/fstab:
mediaserver:/Storage/media /mnt/media nfs defaults,rsize=8192,wsize=8192,timeo=14,intr,_netdev 0 0
```

### NVENC Not Working

```bash
# Verify NVIDIA driver
nvidia-smi

# Check FFmpeg build
ffmpeg -encoders | grep nvenc

# If missing, use conda-forge FFmpeg (easiest solution)
conda install -c conda-forge ffmpeg
```

### Conversion Slower Than Expected

```bash
# Check CPU usage
htop

# Check if thermal throttling
sensors  # Install: sudo apt install lm-sensors

# Verify not using swap
free -h

# Increase parallel jobs (if CPU allows)
# Edit smart_convert_config.json: max_parallel_jobs: 8
```

### Pink Tint Still Visible After Conversion

```bash
# Verify HDR was detected
grep "HDR content detected" media_update_*.log

# Check output color space
ffprobe output.mp4 2>&1 | grep color_transfer
# Should show: color_transfer=bt709

# If still bt2020/smpte2084, conversion failed
# Retry with verbose logging
media-converter --file "problem_file.mp4" --type video --downgrade-resolution
```

## Best Practices

1. **Test First:** Always test on a few files before batch processing
2. **Use Screen/Tmux:** Long-running jobs should use persistent sessions
3. **Monitor Logs:** Check `media_update_*.log` regularly for errors
4. **Backup Originals:** Keep 4K HDR originals until verified conversions work
5. **Network Bandwidth:** NFS over gigabit Ethernet is sufficient; 10GbE ideal
6. **Storage Space:** Ensure enough space for temp files (2x file size during conversion)
7. **Power Settings:** Disable sleep/hibernation during batch processing

## Cleanup and Uninstallation

### Remove Standalone Converter

```bash
# Remove installation
rm -rf ~/.local/share/mediabox-converter

# Remove wrapper script
rm ~/.local/bin/media-converter

# Remove PATH entry
nano ~/.bashrc
# Delete the "Mediabox Media Converter" section
source ~/.bashrc

# Unmount NFS
sudo umount /mnt/media
```

## Summary

✅ **Install standalone converter on Ubuntu desktop with NVIDIA GPU**  
✅ **Mount media from server via NFS/SMB**  
✅ **Process 4K HDR content 5-10x faster than server**  
✅ **Automatic HDR→SDR tone mapping prevents pink tint**  
✅ **Batch processing with intelligent resource management**  
✅ **Sync converted files back to server**  

**Result:** Multi-month server processing reduced to 2-3 weeks on desktop!

For detailed HDR processing info, see: [HDR_TONE_MAPPING.md](HDR_TONE_MAPPING.md)
