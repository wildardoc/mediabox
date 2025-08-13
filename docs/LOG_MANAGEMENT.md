# Mediabox Log Management

## Overview
Mediabox automatically manages log files to prevent disk space issues while maintaining useful history for troubleshooting.

## Log Retention Policy
- **Recent logs (0-14 days)**: Keep uncompressed for easy access and troubleshooting
- **Older logs (14-90 days)**: Compress with gzip to save ~90% disk space
- **Ancient logs (90+ days)**: Delete to prevent unlimited disk growth

## Automatic Rotation
Log rotation runs automatically via cron:
- **Schedule**: Every Sunday at 2:00 AM
- **Command**: `/Storage/docker/mediabox/scripts/rotate-logs.sh`
- **Output**: Logged to `/Storage/docker/mediabox/scripts/log-rotation.log`

## Manual Log Management

### Run log rotation manually:
```bash
cd /Storage/docker/mediabox/scripts
./rotate-logs.sh
```

### Check log rotation history:
```bash
cat /Storage/docker/mediabox/scripts/log-rotation.log
```

### View compressed logs:
```bash
# View compressed log file
zcat media_update_20250808225651.log.gz | less

# Search in compressed log
zgrep "ERROR" media_update_20250808225651.log.gz
```

## Log Types

### Media Update Logs
- **Pattern**: `media_update_YYYYMMDDHHMMSS.log`
- **Content**: Media processing details, conversion progress, errors
- **Size**: Can be large (10-100MB) for big conversion jobs

### Import Logs
- **Pattern**: `import_YYYYMMDD.log`  
- **Content**: Webhook events, script execution, debugging info
- **Size**: Typically small (KB to low MB)

### Log Rotation Logs
- **File**: `log-rotation.log`
- **Content**: History of rotation operations, space savings
- **Retention**: Not rotated (kept indefinitely, but stays small)

## Troubleshooting

### Check current log sizes:
```bash
ls -lh /Storage/docker/mediabox/scripts/*.log*
```

### Monitor disk space:
```bash
du -h /Storage/docker/mediabox/scripts/
```

### Disable automatic rotation (if needed):
```bash
crontab -e
# Comment out the mediabox log rotation line
```

### Emergency cleanup (if disk full):
```bash
cd /Storage/docker/mediabox/scripts
# Compress all logs immediately
find . -name "*.log" -type f -exec gzip {} \;
# Or delete old logs (careful!)
find . -name "*.log" -mtime +7 -delete
```
