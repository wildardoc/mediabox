# Smart Bulk Media Conversion System

## Overview

The Smart Bulk Conversion System provides intelligent, resource-aware bulk media processing for Mediabox installations. It automatically scales conversion processes based on system resources, prioritizes critical services (Plex, downloads), and handles ZFS memory management properly.

## System Components

### Core Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `smart-bulk-convert.sh` | Main conversion engine with resource management | Primary conversion tool |
| `smart-monitor.sh` | Real-time monitoring dashboard | Optional visual monitoring |
| `prepare-bulk-conversion.sh` | Safety check and system validation | Pre-conversion verification |
| `smart_convert_config.json` | Configuration file | Customize behavior and thresholds |

### Legacy Scripts (Still Available)

| Script | Purpose | Usage |
|--------|---------|-------|
| `bulk-convert.sh` | Simple sequential conversion | Basic bulk processing |
| `bulk-convert-parallel.sh` | Fixed parallel conversion | Manual parallel processing |
| `cleanup-conversions.py` | Validation and cleanup | Post-conversion maintenance |

## Quick Start

### 1. Basic Usage (Single Terminal)
```bash
cd /Storage/docker/mediabox/scripts

# Convert movies with smart resource management
./smart-bulk-convert.sh /Storage/media/movies

# Convert TV shows  
./smart-bulk-convert.sh /Storage/media/tv
```

### 2. Long-Running Sessions (Recommended)
```bash
cd /Storage/docker/mediabox/scripts

# Start in screen for persistence
screen -S conversion
./smart-bulk-convert.sh /Storage/media/movies

# Detach: Ctrl+A, D
# Reattach: screen -r conversion
```

### 3. With Monitoring (Two Terminals)
```bash
# Terminal 1: Start conversion
screen -S conversion -d -m ./smart-bulk-convert.sh /Storage/media/movies

# Terminal 2: Monitor progress
./smart-monitor.sh

# Check screen status
screen -list
```

## Configuration

### Default Configuration File: `smart_convert_config.json`

```json
{
    "max_cpu_percent": 75,
    "max_memory_percent": 90,
    "max_load_average": 8.0,
    "min_available_memory_gb": 4,
    "check_interval": 30,
    "max_parallel_jobs": 4,
    "min_parallel_jobs": 1,
    "plex_priority": true,
    "download_priority": true,
    "zfs_aware": true,
    "target_directories": [
        "/Storage/media/movies",
        "/Storage/media/tv"
    ],
    "pause_for_processes": [
        "PlexTranscoder",
        "plex_ffmpeg",
        "import.sh",
        "media_update.py"
    ],
    "video_extensions": [
        "mkv", "mp4", "avi", "mov", "wmv", "flv"
    ]
}
```

### Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_cpu_percent` | 75 | Maximum CPU usage before reducing jobs |
| `max_memory_percent` | 90 | Maximum memory pressure before reducing jobs |
| `max_load_average` | 8.0 | Maximum load average before reducing jobs |
| `min_available_memory_gb` | 4 | Minimum free memory to maintain (ZFS-aware) |
| `check_interval` | 30 | Seconds between resource checks |
| `max_parallel_jobs` | 4 | Maximum concurrent conversion jobs |
| `plex_priority` | true | Give priority to Plex transcoding |
| `download_priority` | true | Give priority to download/import processes |
| `zfs_aware` | true | Use ZFS-aware memory calculations |

### Creating Custom Configurations

```bash
# Create default configuration
./smart-bulk-convert.sh --create-config

# Use custom configuration
./smart-bulk-convert.sh --config my_config.json /Storage/media/movies

# Override specific settings
./smart-bulk-convert.sh --max-jobs 2 --cpu-limit 60 /Storage/media/movies
```

## Command Line Options

### smart-bulk-convert.sh Options

```bash
Usage: ./smart-bulk-convert.sh [OPTIONS] <target_directory>

OPTIONS:
    -c, --config FILE    Use custom configuration file
    -j, --max-jobs N     Maximum parallel jobs (default: 4)
    -i, --interval N     Check interval in seconds (default: 30)
    --cpu-limit N        Max CPU usage percentage (default: 75)
    --memory-limit N     Max memory usage percentage (default: 90)
    --create-config      Create default configuration file
    -h, --help          Show help

EXAMPLES:
    ./smart-bulk-convert.sh /Storage/media/movies
    ./smart-bulk-convert.sh --max-jobs 2 /Storage/media/tv
    ./smart-bulk-convert.sh --cpu-limit 60 /Storage/media/movies
```

### smart-monitor.sh Options

```bash
Usage: ./smart-monitor.sh [OPTIONS]

OPTIONS:
    -i, --interval N     Refresh interval in seconds (default: 5)
    -h, --help          Show help
```

## System Behavior

### Resource Scaling Logic

The system dynamically adjusts the number of parallel conversion jobs based on:

1. **High Priority Processes**: Reduces jobs by 50% when Plex or downloads are active
2. **CPU Usage**: Reduces jobs when CPU exceeds threshold
3. **Memory Pressure**: Reduces jobs when available memory is low (ZFS-aware)
4. **Load Average**: Reduces jobs when system load is high
5. **Critical Memory**: Pauses all conversions if available memory drops below minimum

### ZFS Memory Management

Traditional memory monitoring fails on ZFS systems because ZFS ARC (cache) uses most available RAM. The smart converter uses `MemAvailable` from `/proc/meminfo` which accounts for reclaimable memory including ZFS ARC.

**Example:**
- Traditional calculation: 95% memory used (incorrect)
- ZFS-aware calculation: 8.9GB available for applications (correct)

### File Type Detection

The system processes all video formats supported by `media_update.py`:
- **MKV files**: Primary targets for H.264/AAC conversion
- **MP4 files**: Checked for audio optimization needs
- **AVI, MOV, WMV, FLV**: Converted to optimized MP4

### Priority Process Detection

Automatically detects and prioritizes:
- **Plex transcoding**: `PlexTranscoder`, `plex.*ffmpeg`
- **Media imports**: `import.sh`, `media_update.py`
- **Downloads**: Active download processes

## Monitoring and Logging

### Log Files

| File | Contents |
|------|----------|
| `smart_bulk_convert_YYYYMMDD_HHMMSS.log` | Detailed operation log with decisions |
| `conversion_stats.json` | Real-time statistics and progress |
| `media_update_YYYYMMDD.log` | Individual conversion results |

### Statistics Tracking

The system maintains real-time statistics:
- Total files processed
- Processing rate (files/hour)
- Current active jobs
- Queue remaining
- Estimated completion time

### Real-Time Monitoring

The `smart-monitor.sh` provides a live dashboard showing:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                        SMART BULK CONVERTER MONITOR                         ║
╚══════════════════════════════════════════════════════════════════════════════╝

=== SYSTEM RESOURCES ===
CPU: 45% | Available: 8.9/40.0 GB | Load: 2.1 | ZFS ARC: 21.0GB

Active Processes:
  None detected

=== CONVERSION STATISTICS ===
Runtime: 02:15:30
Processed: 127 files
Active Jobs: 2
Queue Remaining: 603 files
Processing Rate: 56.4 files/hour
Estimated Completion: 10:42:15

Progress: [████████████░░░░░░░░░░░░░░░░░░░░] 17%
```

## Session Management

### Screen/Tmux Integration

```bash
# Start conversion in screen
screen -S conversion
./smart-bulk-convert.sh /Storage/media/movies
# Detach: Ctrl+A, D

# Reattach to session
screen -r conversion

# List sessions
screen -list

# Kill session
screen -S conversion -X quit
```

### Background Operation

```bash
# Start in background with nohup
nohup ./smart-bulk-convert.sh /Storage/media/movies > conversion.out 2>&1 &

# Monitor progress
tail -f conversion.out
```

## Troubleshooting

### Common Issues

#### 1. High System Load
**Symptoms**: System becomes sluggish
**Solution**: Lower `max_parallel_jobs` or `max_cpu_percent`

```bash
./smart-bulk-convert.sh --max-jobs 1 --cpu-limit 50 /Storage/media/movies
```

#### 2. Out of Memory
**Symptoms**: System becomes unresponsive
**Solution**: Increase `min_available_memory_gb`

```json
{
    "min_available_memory_gb": 8
}
```

#### 3. Plex Transcoding Interference
**Symptoms**: Plex buffering during conversions
**Solution**: System automatically detects and reduces jobs

#### 4. Conversion Errors
**Symptoms**: Files failing to convert
**Solution**: Check individual conversion logs

```bash
# Check recent conversion errors
grep -i error smart_bulk_convert_*.log

# Check media_update.py logs
ls -la media_update_*.log
```

### Performance Tuning

#### For Powerful Systems (32+ GB RAM, 16+ CPU cores)
```json
{
    "max_cpu_percent": 85,
    "max_parallel_jobs": 8,
    "min_available_memory_gb": 8,
    "check_interval": 15
}
```

#### For Modest Systems (16 GB RAM, 4-8 CPU cores)
```json
{
    "max_cpu_percent": 60,
    "max_parallel_jobs": 2,
    "min_available_memory_gb": 4,
    "check_interval": 60
}
```

#### For ZFS Systems with Large ARC
```json
{
    "max_memory_percent": 95,
    "min_available_memory_gb": 6
}
```

## Integration with Existing Workflow

### Webhook Integration
The smart converter works alongside existing webhook-triggered conversions:
- Webhooks handle individual file imports
- Smart converter handles bulk library processing
- Both use the same `media_update.py` engine

### Maintenance Integration
```bash
# Run after bulk conversion
./cleanup-conversions.py --validate-all
```

### Cron Integration
```bash
# Add to crontab for weekly bulk processing
0 2 * * 0 /Storage/docker/mediabox/scripts/smart-bulk-convert.sh /Storage/media/movies >> /var/log/bulk-convert.log 2>&1
```

## Safety Features

### Process Isolation
- Uses atomic operations to prevent corruption
- Temporary files with unique names
- Proper cleanup on interruption

### Resource Protection
- Never exceeds configured resource limits
- Automatic backoff when system is busy
- Graceful shutdown on signals

### File Safety
- Validates source files before processing
- Creates temporary outputs before atomic rename
- Preserves original files until conversion succeeds

## Migration from Legacy Scripts

### From bulk-convert.sh
```bash
# Old way
./bulk-convert.sh movies

# New way
./smart-bulk-convert.sh /Storage/media/movies
```

### From bulk-convert-parallel.sh
```bash
# Old way
./bulk-convert-parallel.sh movies 4

# New way (automatically scales 1-4 jobs based on resources)
./smart-bulk-convert.sh /Storage/media/movies
```

## Best Practices

### 1. Start Small
Begin with movies directory (smaller dataset) before processing TV shows.

### 2. Monitor First Run
Use `smart-monitor.sh` during first run to verify behavior.

### 3. Tune Configuration
Adjust settings based on your system's performance during initial runs.

### 4. Use Screen/Tmux
Always use screen or tmux for long-running conversions.

### 5. Monitor Disk Space
Ensure adequate free space for temporary files during conversion.

### 6. Check Logs
Regularly review logs for errors or performance issues.

## Advanced Usage

### Custom Processing Scripts
The smart converter can be modified to use different processing backends:

```bash
# Modify start_conversion_job() function to use custom script
start_conversion_job() {
    local input_file="$1"
    # Replace media_update.py with custom processor
    custom_processor.py "$input_file" &
    local pid=$!
    ACTIVE_PIDS+=($pid)
}
```

### Multiple Target Processing
```bash
# Process multiple directories sequentially
for dir in /Storage/media/movies /Storage/media/tv /Storage/media/documentaries; do
    ./smart-bulk-convert.sh "$dir"
done
```

### Integration with External Monitoring
```bash
# Export metrics to external monitoring
jq '.processing_rate_per_hour' conversion_stats.json | curl -X POST -d @- http://monitoring.local/metrics/conversion_rate
```

## System Requirements

### Minimum Requirements
- **CPU**: 4 cores
- **RAM**: 8GB (16GB recommended for ZFS)
- **Storage**: SSD recommended for temp files
- **OS**: Ubuntu 18.04+ with Docker

### Optimal Requirements
- **CPU**: 8+ cores
- **RAM**: 32GB+ (for ZFS with large ARC)
- **Storage**: NVMe SSD for system, ZFS pool for media
- **Network**: Gigabit for NFS/CIFS media access

## Conclusion

The Smart Bulk Conversion System provides production-ready, intelligent media processing that adapts to your system's capabilities and workload. It's designed for 24/7 operation alongside Plex servers and active download systems.

For support or customization, refer to the individual script help options or the Mediabox project documentation.
