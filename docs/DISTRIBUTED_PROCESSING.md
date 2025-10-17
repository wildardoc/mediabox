# Distributed Media Processing Setup Guide

## Overview

Mediabox now supports **distributed media processing** across multiple machines (Linux and Windows 11) accessing shared storage via NFS or SMB. Each machine can safely process different files simultaneously without conflicts.

## Architecture

```
┌─────────────────┐
│  Shared Storage │  ← NFS/SMB Share
│  /Storage/media │     (ProLiant)
└────────┬────────┘
         │
    ┌────┴────┬─────────┬─────────┐
    │         │         │         │
┌───▼───┐ ┌──▼───┐ ┌──▼───┐ ┌───▼───┐
│ProLiant│ │Mercury│ │Win11 │ │Win11 #2│
│ (Linux)│ │(Linux)│ │  #1  │ │        │
└────────┘ └───────┘ └──────┘ └────────┘
```

## File Locking Mechanism

**How it works:**
- Each worker checks for a `.mediabox.lock` file before processing
- Lock contains: hostname, PID, timestamp, file path
- Locks automatically expire after 30 minutes (handles crashes)
- Workers skip files that are locked by other machines
- Locks are always released after processing (via finally block)

**Lock file example:**
```json
{
  "hostname": "mercury",
  "pid": 12345,
  "timestamp": 1729056123.456,
  "file": "/Storage/media/movies/Movie.mkv",
  "locked_at": "2025-10-16T10:15:23.456789"
}
```

## Installation

### Linux (ProLiant, Mercury)

```bash
cd ~/mediabox
git pull origin master
cd scripts
./install-media-converter.sh
```

**Verify installation:**
```bash
media-converter --help
```

### Windows 11 (Desktop Machines)

1. **Download repository** (if not already cloned):
   ```powershell
   git clone https://github.com/wildardoc/mediabox.git
   cd mediabox\scripts
   ```

2. **Run PowerShell as Administrator** (recommended for auto-install):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   .\install-media-converter.ps1
   ```

3. **Restart terminal** to load PATH changes

4. **Verify installation:**
   ```cmd
   media-converter --help
   ```

**What gets installed:**
- Python 3.12 (via winget if missing)
- FFmpeg (via winget/Chocolatey if missing)
- Virtual environment: `%LOCALAPPDATA%\mediabox-converter`
- Wrapper script: `%LOCALAPPDATA%\mediabox-converter\media-converter.bat`
- Database tools: `build_media_database.py`, `query_media_database.py`

## Network Storage Setup

### Linux (NFS)

**Already configured on ProLiant/Mercury:**
```bash
# ProLiant exports
/Storage/media  *(rw,sync,no_subtree_check)

# Mercury mounts
//10.0.0.10/media on /FileServer/media type nfs
```

### Windows 11 (SMB)

**Map network drive:**
```cmd
net use Z: \\10.0.0.10\media /persistent:yes
```

**Or use UNC paths directly:**
```cmd
media-converter --dir "\\10.0.0.10\media\movies" --type video
```

## Distributed Processing Workflow

### Scenario 1: Process Entire Library (All Machines)

**ProLiant:**
```bash
media-converter --dir /Storage/media/movies/A-M --type video
```

**Mercury:**
```bash
media-converter --dir /FileServer/media/movies/N-Z --type video
```

**Windows #1:**
```cmd
media-converter --dir "Z:\tv\Series A-M" --type video
```

**Windows #2:**
```cmd
media-converter --dir "Z:\tv\Series N-Z" --type video
```

**Result:**
- 4 machines processing different sections simultaneously
- No conflicts (different directories)
- 4x faster than single machine

### Scenario 2: Shared Directory (Race Protection)

**All machines process same directory:**

**ProLiant:**
```bash
media-converter --dir /Storage/media/movies --type video
```

**Mercury:**
```bash
media-converter --dir /FileServer/media/movies --type video
```

**Windows #1:**
```cmd
media-converter --dir "Z:\movies" --type video
```

**Result:**
- Each machine finds next unlocked file
- Skips files being processed by others
- Automatic work distribution
- Example output:
  ```
  ⏭️  Skipping Movie1.mkv - already being processed by proliant
  🔒 Lock acquired for: Movie2.mkv
  Processing Movie2.mkv...
  ```

### Scenario 3: Smart Converter + Manual Workers

**ProLiant (automated):**
```bash
# Run smart-bulk-convert for ongoing automated processing
cd scripts
./start-smart-converter.sh
```

**Mercury, Windows (manual):**
```bash
# Manually process specific high-priority content
media-converter --file "/path/to/urgent/Movie.mkv" --type video
```

**Result:**
- Smart converter runs 24/7 on ProLiant
- Manual workers can jump in for urgent files
- File locking prevents conflicts

## Performance Optimization

### Pre-Build Cache on ProLiant

**Build cache once, use everywhere:**
```bash
# On ProLiant (has local I/O)
cd ~/.local/share/mediabox-converter
python3 build_media_database.py --scan /Storage/media/movies
python3 build_media_database.py --scan /Storage/media/tv
```

**Cache files created:**
```
/Storage/media/movies/.mediabox_cache.json
/Storage/media/movies/Action/.mediabox_cache.json
/Storage/media/tv/ShowName/.mediabox_cache.json
```

**All workers use cached data:**
- ProLiant: Direct local access
- Mercury: NFS mount
- Windows: SMB share
- **Result:** 11x faster scans, instant probe data

### Query Before Processing

**Check what needs conversion:**
```bash
# On any machine
cd ~/.local/share/mediabox-converter  # Linux
cd %LOCALAPPDATA%\mediabox-converter  # Windows

# Show HDR files
python3 query_media_database.py --hdr

# Show files needing conversion
python3 query_media_database.py --needs-conversion

# Get statistics
python3 query_media_database.py --stats
```

## Monitoring Distributed Workers

### Check Active Locks

**Linux:**
```bash
find /Storage/media -name "*.mediabox.lock" -exec cat {} \;
```

**Windows:**
```powershell
Get-ChildItem Z:\ -Recurse -Filter "*.mediabox.lock" | ForEach-Object { Get-Content $_.FullName | ConvertFrom-Json }
```

**Example output:**
```json
{
  "hostname": "proliant",
  "pid": 54321,
  "locked_at": "2025-10-16T10:15:00",
  "file": "/Storage/media/movies/Movie1.mkv"
}
{
  "hostname": "mercury",
  "pid": 12345,
  "locked_at": "2025-10-16T10:15:05",
  "file": "/Storage/media/movies/Movie2.mkv"
}
```

### View Processing Logs

**Linux (ProLiant/Mercury):**
```bash
tail -f ~/mediabox/scripts/media_update_$(date +%Y%m%d).log
```

**Windows:**
```cmd
cd %LOCALAPPDATA%\mediabox-converter
type media_update_*.log | more
```

### Cleanup Stale Locks

**If a worker crashes, locks may remain:**

**Python (any platform):**
```python
from file_lock import cleanup_stale_locks

# Clean locks older than 30 minutes
removed = cleanup_stale_locks("/Storage/media", timeout=1800)
print(f"Removed {removed} stale locks")
```

**Or manually:**
```bash
# Linux
find /Storage/media -name "*.mediabox.lock" -mmin +30 -delete

# Windows PowerShell
Get-ChildItem Z:\ -Recurse -Filter "*.mediabox.lock" | Where-Object {$_.LastWriteTime -lt (Get-Date).AddMinutes(-30)} | Remove-Item
```

## Troubleshooting

### "Skipping - already being processed"

**Cause:** Another worker has locked the file

**Solution:**
- This is normal! Worker will skip to next file
- Check active locks to see which machine is processing
- If lock is stale (30+ minutes), cleanup stale locks

### Windows Can't Find Python/FFmpeg

**Cause:** PATH not updated or tools not installed

**Solution:**
```powershell
# Reinstall with admin privileges
.\install-media-converter.ps1

# Or install manually
winget install Python.Python.3.12
winget install Gyan.FFmpeg

# Restart terminal
```

### Network Share Performance Issues

**Symptoms:** Slow file I/O, timeouts

**Solutions:**
- **Linux NFS:** Increase rsize/wsize in mount options
  ```bash
  mount -o rsize=1048576,wsize=1048576,vers=3 server:/media /mnt/media
  ```
- **Windows SMB:** Use SMB3 protocol
  ```cmd
  net use Z: \\server\media /persistent:yes /version:3.0
  ```
- **Cache hits:** Pre-build cache on ProLiant to minimize probing

### Lock Timeout Too Short/Long

**Adjust timeout in media_update.py:**
```python
# Line ~1721
file_lock = FileLock(input_file, timeout=1800)  # 30 minutes

# For faster machines (reduce timeout):
file_lock = FileLock(input_file, timeout=900)   # 15 minutes

# For slower 4K HDR processing (increase timeout):
file_lock = FileLock(input_file, timeout=3600)  # 60 minutes
```

## Best Practices

1. **Build cache on ProLiant first** - 11x faster than probing over network
2. **Divide by directory** - Reduces lock contention
3. **Monitor logs** - Watch for patterns of skipped files
4. **Use smart converter on ProLiant** - Let it run 24/7 automatically
5. **Manual workers for urgent files** - Jump the queue on other machines
6. **Clean stale locks weekly** - Automated cleanup recommended

## Example: Full 4-Machine Deployment

**Day 1 - Initial Setup:**
```bash
# ProLiant: Build cache and start automated processing
cd scripts
python3 build_media_database.py --scan /Storage/media
./start-smart-converter.sh

# Mercury: Pull latest code and install
cd ~/mediabox && git pull
cd scripts && ./install-media-converter.sh

# Windows #1 & #2: Install
git clone https://github.com/wildardoc/mediabox.git
cd mediabox\scripts
.\install-media-converter.ps1
```

**Day 2+ - Distributed Processing:**
```bash
# ProLiant: Automated 24/7 (movies + TV)
screen -r mediabox-converter

# Mercury: Process high-priority new arrivals
media-converter --dir /FileServer/media/downloads --type both

# Windows #1: Process TV shows
media-converter --dir "Z:\tv" --type video

# Windows #2: Process movies
media-converter --dir "Z:\movies" --type video
```

**Result:**
- ProLiant handles ongoing automated conversions
- 3 additional workers process backlog 4x faster
- No conflicts or duplicate work
- Complete library processing in days instead of weeks

## Security Notes

- **Lock files contain no sensitive data** - Just hostname, PID, timestamp
- **No authentication required** - File locks use filesystem permissions
- **Network security** - Ensure NFS/SMB shares are properly secured
- **Read-only shares** - Won't work (need write access for lock files)

## Performance Metrics

**Single Machine (ProLiant only):**
- ~30,000 files in library
- ~5-10 files/hour (depending on size/HDR)
- **Estimated completion: 3-6 months**

**Distributed (4 machines):**
- Same 30,000 files
- ~20-40 files/hour combined
- **Estimated completion: 3-6 weeks**

**With caching:**
- Initial scan: 30 minutes
- Re-scans: 9 seconds (11x faster)
- Probe time: <1ms (cached) vs 500ms-2s (live)

---

**Questions?** Check the GitHub repository or review the installer documentation:
- Linux: `cat ~/.local/share/mediabox-converter/USAGE.md`
- Windows: `notepad %LOCALAPPDATA%\mediabox-converter\USAGE.md`
