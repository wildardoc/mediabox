# Smart Bulk Conversion - Quick Reference

## 🚀 Quick Start Commands

```bash
cd /Storage/docker/mediabox/scripts

# Start conversion in screen (recommended)
screen -S conversion -d -m ./smart-bulk-convert.sh /Storage/media/movies

# Monitor progress (optional second terminal)
./smart-monitor.sh

# Check screen sessions
screen -list

# Reattach to conversion
screen -r conversion
```

## 📊 Status Checking

```bash
# View recent log entries
tail -f smart_bulk_convert_*.log

# Check current statistics
cat conversion_stats.json | jq .

# Quick system check
./prepare-bulk-conversion.sh
```

## ⚙️ Common Configurations

### Conservative (Low Resource Usage)
```bash
./smart-bulk-convert.sh --max-jobs 1 --cpu-limit 50 /Storage/media/movies
```

### Aggressive (High Performance)
```bash
./smart-bulk-convert.sh --max-jobs 6 --cpu-limit 85 /Storage/media/movies
```

### Custom Config
```bash
# Edit configuration
nano smart_convert_config.json

# Use custom config
./smart-bulk-convert.sh --config my_config.json /Storage/media/movies
```

## 🔧 Session Management

```bash
# Start in screen (persistent)
screen -S conversion
./smart-bulk-convert.sh /Storage/media/movies
# Detach: Ctrl+A, D

# List sessions
screen -list

# Reattach
screen -r conversion

# Kill session
screen -S conversion -X quit
```

## 📈 Monitoring Dashboard

```bash
# Real-time monitoring (separate terminal)
./smart-monitor.sh

# Shows:
# - CPU/Memory/Load with colors
# - Active Plex/Download processes  
# - Conversion progress and ETA
# - Recent log entries
```

## 🎯 Processing Order

1. **Movies first** (730 files) - smaller dataset for testing
2. **TV shows next** (7,091 files) - larger bulk processing

## 🛡️ Safety Features

- **Auto-detects** Plex transcoding and reduces jobs
- **ZFS-aware** memory management (uses MemAvailable)
- **Resource scaling** based on CPU/memory/load
- **Atomic operations** prevent file corruption
- **Graceful shutdown** on Ctrl+C

## 📁 File Coverage

- **MKV** → MP4 (H.264/AAC conversion)
- **AVI, MOV, WMV, FLV** → MP4 (full conversion)
- **MP4** → Audio optimization if needed

## 🆘 Troubleshooting

```bash
# System too slow?
./smart-bulk-convert.sh --max-jobs 1 --cpu-limit 60 /path

# Out of memory?
# Edit smart_convert_config.json: "min_available_memory_gb": 8

# Check for errors
grep -i error smart_bulk_convert_*.log

# Restart if needed
screen -S conversion -X quit
screen -S conversion -d -m ./smart-bulk-convert.sh /Storage/media/movies
```

## 🔄 Current Session Status

**Your Current Session:**
- **Screen ID**: `1467580.smart-conversion`
- **Status**: Running movies conversion
- **Target**: /Storage/media/movies (730 files)
- **Reattach**: `screen -r conversion`

---
*For full documentation see: `/Storage/docker/mediabox/docs/SMART_BULK_CONVERSION.md`*
