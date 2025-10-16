# Cache Cleanup Strategy

## Overview

The JSON-based per-directory cache system requires cleanup mechanisms to remove stale entries when files are deleted outside the normal conversion workflow.

## Cleanup Scenarios

### 1. **Automatic Cleanup During Conversion**

**When**: `media_update.py` converts a file  
**How**: `update_after_conversion()` handles cache updates automatically

#### Scenario A: In-Place Conversion
```
Original: movie.mkv (fingerprint: abc123)
Converted: movie.mkv (fingerprint: def456 - file modified)

Action: Remove old entry (abc123), add new entry (def456)
```

#### Scenario B: New File Created, Original Deleted
```
Original: movie.mkv (fingerprint: abc123)
Converted: movie.mp4 (fingerprint: xyz789)
Delete: movie.mkv

Action: Remove old entry (abc123), add new entry (xyz789)
```

#### Scenario C: Conversion Failed
```
Original: movie.mkv (fingerprint: abc123)
Converted: FAILED

Action: Update entry (abc123) with error message
```

### 2. **Manual File Deletion**

**When**: User deletes files manually via file manager or command line  
**Problem**: Cache entry remains (stale)  
**Solution**: Periodic cleanup scan

### 3. **External System Deletion**

**When**: Sonarr/Radarr/Lidarr deletes files (upgrades, unwatched cleanup, etc.)  
**Problem**: Cache entry remains (stale)  
**Solution**: Periodic cleanup scan

### 4. **File Move/Rename**

**When**: Files moved to different directories or renamed  
**Problem**: Old cache entry points to non-existent path  
**Solution**: Periodic cleanup scan

## Cleanup Methods

### MediaDatabase.cleanup_missing_files(directory)

Cleans a single directory's cache file.

```python
from media_database import MediaDatabase

db = MediaDatabase()
removed = db.cleanup_missing_files("/Storage/media/movies/The Matrix (1999)")
print(f"Removed {removed} stale entries")
```

**Process**:
1. Load `.mediabox_cache.json` from directory
2. Check each entry's `file_path` exists
3. Remove entries for missing files
4. Save updated cache (atomic write)

**Returns**: Number of entries removed

### MediaDatabase.cleanup_all_directories(directories)

Recursively cleans all subdirectories in given paths.

```python
from media_database import MediaDatabase

db = MediaDatabase()
result = db.cleanup_all_directories([
    "/Storage/media/movies",
    "/Storage/media/tv"
])
print(f"Cleaned {result['directories_cleaned']} directories")
print(f"Removed {result['total_removed']} stale entries")
```

**Process**:
1. Walk each directory tree recursively
2. Find all `.mediabox_cache.json` files
3. Clean each cache file
4. Aggregate statistics

**Returns**: Dictionary with `total_removed` and `directories_cleaned` counts

## Integration Points

### build_media_database.py

The scanner tool should offer cleanup as an option:

```bash
# Clean up stale entries during scan
python3 build_media_database.py --scan --cleanup /Storage/media/movies

# Cleanup-only mode
python3 build_media_database.py --cleanup /Storage/media/movies /Storage/media/tv
```

**Recommended**: Run cleanup before/after full scans to maintain cache hygiene.

### media_update.py

Already handles cleanup automatically during conversion via `update_after_conversion()`.

**No additional action needed** - cleanup is integrated into the conversion workflow.

### Cron Jobs

For production systems, schedule periodic cleanup:

```bash
# Weekly cleanup on Sundays at 3 AM
0 3 * * 0 /Storage/docker/mediabox/scripts/cleanup-cache.sh
```

**cleanup-cache.sh** (to be created):
```bash
#!/bin/bash
cd /Storage/docker/mediabox/scripts
python3 build_media_database.py --cleanup /Storage/media/movies /Storage/media/tv /Storage/media/music
```

## Performance Considerations

### Cleanup Cost

- **Per-directory**: Fast (single JSON file read/write)
- **Recursive scan**: Proportional to number of directories with cache files
- **File existence checks**: Fast (stat syscall)

### When to Run

✅ **Safe times**:
- During scheduled maintenance windows
- Before/after full library scans
- Off-peak hours (overnight)

⚠️ **Avoid**:
- During active conversions
- During library scans
- During peak usage hours

### Optimization Tips

1. **Incremental cleanup**: Clean one library at a time
2. **Skip recently modified**: Only check caches older than 24 hours
3. **Parallel processing**: Clean multiple directories concurrently (future enhancement)

## Example Workflows

### Weekly Maintenance

```bash
#!/bin/bash
# Weekly cleanup and re-scan

echo "=== Weekly Cache Maintenance ==="

# 1. Clean up stale entries
echo "Cleaning stale cache entries..."
python3 build_media_database.py --cleanup /Storage/media/movies /Storage/media/tv

# 2. Re-scan for new files
echo "Scanning for new files..."
python3 build_media_database.py --scan /Storage/media/movies /Storage/media/tv

# 3. Generate statistics
echo "Cache statistics:"
python3 query_media_database.py --stats

echo "=== Maintenance Complete ==="
```

### On-Demand Cleanup After Bulk Deletion

```bash
# After manually deleting many files
python3 build_media_database.py --cleanup /Storage/media/movies
```

### Pre-Conversion Cleanup

```bash
# Ensure clean cache before starting smart converter
python3 build_media_database.py --cleanup /Storage/media/movies /Storage/media/tv
./smart-bulk-convert.sh /Storage/media/movies /Storage/media/tv
```

## Edge Cases

### Scenario: File Deleted During Cleanup

**Problem**: File exists during scan, deleted before cache write  
**Impact**: None - next cleanup will catch it  
**Mitigation**: Atomic cache writes prevent corruption

### Scenario: Multiple Systems Cleaning Same Cache

**Problem**: Race condition on cache file writes  
**Impact**: Last write wins, potential entry resurrection  
**Mitigation**: Don't run cleanup from multiple systems simultaneously

### Scenario: Cache File Deleted Manually

**Problem**: User deletes `.mediabox_cache.json`  
**Impact**: Cache rebuilt on next scan (performance hit only)  
**Mitigation**: None needed - cache is regeneratable

### Scenario: Permissions Issue

**Problem**: Cache file not writable  
**Impact**: Cleanup skips that directory, logs warning  
**Mitigation**: Ensure proper permissions on media directories

## Monitoring

### Log Messages

Successful cleanup:
```
Cleaned up orphaned cache entry: /Storage/media/movies/Old Movie.mkv
Removed 15 stale entries from /Storage/media/movies/Action
```

No cleanup needed:
```
All cache entries valid in /Storage/media/tv/Breaking Bad/Season 01
```

Error conditions:
```
Warning: Cannot read cache file /Storage/media/movies/.mediabox_cache.json: Permission denied
```

### Statistics

Track cleanup effectiveness:
```
Cleanup Summary:
- Directories scanned: 150
- Cache files found: 120
- Stale entries removed: 42
- Errors encountered: 0
```

## Best Practices

1. ✅ **Run cleanup before full scans** - Ensures accurate statistics
2. ✅ **Schedule weekly cleanup** - Prevents cache bloat
3. ✅ **Monitor cleanup logs** - Detect deletion patterns
4. ✅ **Test cleanup on subset first** - Verify before full library cleanup
5. ❌ **Don't run cleanup during conversions** - May interfere with active processing
6. ❌ **Don't run from multiple systems** - Risk of race conditions

## Future Enhancements

### Planned Features

- [ ] **Dry-run mode**: Preview what would be deleted without actually cleaning
- [ ] **Age-based cleanup**: Only remove entries older than X days
- [ ] **Orphan detection**: Find cache entries without corresponding files
- [ ] **Statistics export**: Generate cleanup reports in JSON/CSV
- [ ] **Interactive mode**: Review each stale entry before deletion
- [ ] **Backup before cleanup**: Save old cache before cleaning

### Potential Optimizations

- [ ] **Parallel cleanup**: Process multiple directories concurrently
- [ ] **Smart scheduling**: Detect system idle time and auto-cleanup
- [ ] **Delta cleanup**: Only check entries modified since last cleanup
- [ ] **Lock files**: Prevent concurrent cleanup from multiple processes

---

**Last Updated**: 2024-01-15  
**Version**: 1.0.0  
**Status**: Core cleanup methods implemented, integration with scanner pending
