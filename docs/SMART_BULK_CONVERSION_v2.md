# Smart Bulk Media Converter

## Overview
The Smart Bulk Media Converter is an intelligent, resource-aware batch processing system that automatically converts large libraries of movies and TV shows while optimizing system performance and handling power outages gracefully.

## Features

### 🧠 **Intelligent Resource Management**
- **Dynamic Job Scaling**: Automatically adjusts 1-5 concurrent conversions based on CPU, memory, and load
- **ZFS-Aware**: Optimized memory calculations for ZFS ARC systems
- **Priority Process Detection**: Gives priority to Plex transcoding and downloads
- **Threshold-Based Control**: Configurable CPU (98%), memory (90%), and load average (30.0) limits

### ⚡ **Power Outage Recovery**
- **Auto-Boot Cleanup**: Removes orphaned processes and temporary files after restart
- **Auto-Start**: Automatically resumes conversions 2 minutes after boot
- **Process Adoption**: Detects and adopts existing conversion processes on startup
- **Crash Recovery**: Handles unexpected terminations gracefully

### 🎯 **Multi-Directory Processing**
- Processes both `/Storage/media/movies` and `/Storage/media/tv` simultaneously
- Intelligent queue building across all target directories
- Prioritizes based on file age and conversion needs

### 🔧 **GPU Acceleration Support**
- Automatic VAAPI hardware acceleration detection
- Graceful fallback to optimized software encoding
- Docker GPU device mapping for container access

## Quick Start

### Start Smart Converter
```bash
cd /Storage/docker/mediabox/scripts
./smart-bulk-convert.sh /Storage/media/movies /Storage/media/tv
```

### Monitor Progress
```bash
# View in screen session
screen -r mediabox-converter

# Follow logs
tail -f smart_bulk_convert_*.log

# Check statistics
cat conversion_stats.json
```

### Auto-Start Setup (Power Outage Recovery)
```bash
# Install cron jobs for automatic recovery
crontab -e

# Add these lines:
@reboot sleep 60 && /Storage/docker/mediabox/scripts/cleanup-on-boot.sh
@reboot sleep 120 && /Storage/docker/mediabox/scripts/start-smart-converter.sh
```

## Configuration

### Main Configuration File: `smart_convert_config.json`
```json
{
    "max_cpu_percent": 98,
    "max_memory_percent": 90,
    "max_load_average": 30.0,
    "min_available_memory_gb": 2,
    "check_interval": 30,
    "max_parallel_jobs": 5,
    "min_parallel_jobs": 1,
    "plex_priority": true,
    "download_priority": false,
    "zfs_aware": true,
    "target_directories": [
        "/Storage/media/movies",
        "/Storage/media/tv"
    ],
    "pause_for_processes": [
        "PlexTranscoder",
        "plex_ffmpeg"
    ]
}
```

### Command Line Options
```bash
./smart-bulk-convert.sh [OPTIONS] <directory1> [directory2] ...

Options:
  --max-jobs N      Maximum parallel jobs (overrides config)
  --cpu-limit N     CPU threshold percentage
  --memory-limit N  Memory threshold percentage  
  --load-limit N    Load average threshold
  --config FILE     Use custom configuration file
```

## System Requirements

### Hardware Recommendations
- **CPU**: Multi-core processor (8+ cores recommended for 5 jobs)
- **RAM**: 16GB+ (ZFS systems need more for ARC)
- **Storage**: Fast storage for temporary files during conversion
- **GPU**: Optional VAAPI-compatible GPU for hardware acceleration

### Software Dependencies
- Docker with GPU support (if using hardware acceleration)
- Python 3.8+
- FFmpeg with VAAPI support
- Screen (for background execution)
- bc (for floating-point calculations)

## Monitoring and Troubleshooting

### Real-Time Monitoring
```bash
# System resources
watch -n 5 'uptime && free -h'

# Active conversions
watch -n 10 'ps aux | grep media_update.py | grep -v grep'

# Conversion progress
tail -f smart_bulk_convert_*.log | grep -E "Active jobs|Starting conversion|Completed"
```

### Log Files
- **Main Log**: `smart_bulk_convert_YYYYMMDD_HHMMSS.log`
- **Statistics**: `conversion_stats.json`
- **Boot Cleanup**: `cleanup_boot_YYYYMMDD_HHMMSS.log`
- **Individual Conversions**: `media_update_YYYYMMDD.log`

### Common Issues

#### High System Load
- Converter automatically reduces jobs when CPU > 98%
- Check for competing processes (Plex, downloads)
- Adjust `max_parallel_jobs` in config if needed

#### Conversions Not Starting
- Verify directories exist and are accessible
- Check system resource thresholds in config
- Review priority process detection in logs

#### Power Outage Recovery
- Boot cleanup runs automatically after 60 seconds
- Smart converter starts automatically after 120 seconds
- Manual restart: `./start-smart-converter.sh`

## Performance Optimization

### For High-End Systems
```json
{
    "max_parallel_jobs": 8,
    "max_cpu_percent": 95,
    "check_interval": 15
}
```

### For Conservative Systems
```json
{
    "max_parallel_jobs": 2,
    "max_cpu_percent": 80,
    "max_load_average": 8.0
}
```

### ZFS Systems
- Set `zfs_aware: true` for optimized memory calculations
- Monitor ARC usage: `arc_summary`
- Ensure adequate available memory for conversions

## Integration

### With Plex
- Automatic priority detection for Plex transcoding
- Reduces conversion jobs when Plex is actively transcoding
- GPU sharing between Plex and conversions

### With *arr Stack
- Compatible with webhook-triggered conversions
- Adopts webhook-started processes into job tracking
- Coordinated resource management

### With Docker
- Full container integration with GPU device mapping
- Automatic service health monitoring
- Container restart detection and adaptation

## Advanced Usage

### Custom Conversion Queues
```bash
# Movies only
./smart-bulk-convert.sh /Storage/media/movies

# TV shows only  
./smart-bulk-convert.sh /Storage/media/tv

# Custom directories
./smart-bulk-convert.sh /Storage/media/anime /Storage/media/documentaries
```

### Development and Testing
```bash
# Create test configuration
./smart-bulk-convert.sh --create-config

# Dry run (build queue only)
./smart-bulk-convert.sh --max-jobs 0 /Storage/media/movies

# Verbose debugging
tail -f smart_bulk_convert_*.log | grep DEBUG
```

## Maintenance

### Weekly Maintenance
- Log rotation happens automatically
- Clean up old statistics files: `find . -name "conversion_stats_*.json" -mtime +7 -delete`
- Monitor disk space for temporary files

### After System Updates
- Verify Docker GPU access: `docker run --rm --device=/dev/dri:/dev/dri ubuntu:20.04 ls -la /dev/dri`
- Test hardware acceleration: `scripts/test-gpu-acceleration.sh`
- Restart smart converter with updated dependencies

This system provides enterprise-grade automated media processing with comprehensive error handling, logging, and maintenance automation specifically optimized for production environments with power reliability concerns.
