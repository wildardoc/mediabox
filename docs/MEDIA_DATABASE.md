# Media Database System - Quick Reference

## 📋 **Overview**

The media database system provides **intelligent metadata caching** to dramatically speed up media processing workflows. By fingerprinting files and caching their ffprobe results, we can skip expensive re-probing operations on subsequent runs.

### **Key Benefits**
- **11x faster scans**: ~23 minutes → ~2 minutes for 700 movies on re-scan
- **Smart change detection**: Only re-probes files that have changed
- **Conversion tracking**: Maintains history of all processing operations
- **Powerful queries**: Find HDR files, conversion queue, statistics

### **Architecture**
```
┌─────────────────────┐
│  media_database.py  │ ← Core SQLite library
└─────────────────────┘
         ↑
    ┌────┴─────┬────────────────┬──────────────────┐
    │          │                │                  │
┌───┴───────┐  │  ┌─────────────┴──┐  ┌───────────┴───────┐
│build_*.py │  │  │ query_*.py     │  │ media_update.py   │
│(Scanner)  │  │  │ (Query Tool)   │  │ (Auto-caching)    │
└───────────┘  │  └────────────────┘  └───────────────────┘
               │
               └→ All scripts share same SQLite database
```

---

## 🔧 **Core Components**

### **1. media_database.py**
Shared library providing database operations.

**No manual venv activation required** - All scripts automatically activate the virtual environment from `mediabox_config.json`.

**Key Methods:**
```python
db = MediaDatabase()

# Fingerprinting (fast - no ffprobe)
fingerprint = db.get_file_fingerprint("/path/to/movie.mkv")

# Check cache
if db.has_cached_probe(fingerprint):
    cached = db.get_cached_probe(fingerprint)
    probe = json.loads(cached['probe_json'])

# Store new probe
db.store_probe(fingerprint, probe, action='needs_conversion')

# Update after conversion
db.update_after_conversion(fingerprint, success=True, action_taken='video_converted')

# Query
results = db.query_by_filter(is_hdr=True)
stats = db.get_statistics()

# Cleanup
removed = db.cleanup_missing_files()
db.close()
```

**Database Schema:**
- `media_cache` table: File fingerprints, probe results, metadata, processing status
- `processing_log` table: Conversion history with timestamps
- Indexes on: path, action, last_scanned, is_hdr, resolution

---

### **2. build_media_database.py**
Scan and catalog media libraries.

**Automatic venv activation** - No need to run `source .venv/bin/activate` first!

**Usage:**
```bash
# Scan entire library (initial build)
python3 build_media_database.py --scan /Storage/media/movies /Storage/media/tv

# Scan specific directory
python3 build_media_database.py --scan "/Storage/media/tv/Breaking Bad"

# Re-scan to find new/changed files (fast - uses cache)
python3 build_media_database.py --scan /Storage/media/movies

# Force re-probe all files (slow)
python3 build_media_database.py --scan /Storage/media/movies --force

# Show statistics
python3 build_media_database.py --stats

# Clean up deleted files
python3 build_media_database.py --cleanup

# Verbose output (show every file)
python3 build_media_database.py --scan /Storage/media/movies -v
```

**Features:**
- Progress bar with ETA
- Smart caching (skips unchanged files)
- Automatic HDR detection
- Action determination (what conversion needed)
- Summary statistics

**Expected Performance:**
- First scan: ~23 minutes for 700 movies (full ffprobe)
- Re-scan: ~2 minutes (cache hits, fingerprint checks only)
- Changed files: Automatically detected and re-probed

---

### **3. query_media_database.py**
Query and analyze cached metadata.

**Usage:**
```bash
# List all HDR files
python3 query_media_database.py --hdr

# Find files needing conversion
python3 query_media_database.py --needs-conversion

# Search for specific show
python3 query_media_database.py --search "Breaking Bad"

# Show files by action (summary)
python3 query_media_database.py --by-action

# Show specific action
python3 query_media_database.py --by-action needs_hdr_tonemap

# Filter by resolution (summary)
python3 query_media_database.py --resolution

# Show 4K files
python3 query_media_database.py --resolution 3840x2160

# Processing history (last 30 days)
python3 query_media_database.py --history

# Processing history (last 7 days)
python3 query_media_database.py --history --days 7

# Database statistics
python3 query_media_database.py --stats

# Export results (paths only)
python3 query_media_database.py --needs-conversion --export queue.txt

# Export as JSON
python3 query_media_database.py --hdr --export-json hdr_files.json
```

**Query Examples:**

```bash
# Find all HDR content for tone mapping
python3 query_media_database.py --hdr

# Plan conversion queue
python3 query_media_database.py --needs-conversion --export batch_queue.txt

# Check what's already processed
python3 query_media_database.py --by-action skip

# Analyze library composition
python3 query_media_database.py --stats
```

---

### **4. media_update.py Integration**
Automatic caching during conversion.

**How It Works:**
1. **Before ffprobe**: Check fingerprint cache
   - Cache hit → Use cached probe (instant)
   - Cache miss → Run ffprobe and cache result
2. **After conversion**: Update database
   - Record action taken
   - Update processing log
   - Update file status

**Cache Hit Indicators:**
```
📦 Using cached metadata for: Movie.mkv
```

**Cache Miss (Normal):**
```
Probed file (no cache): /path/to/Movie.mkv
📦 Cached probe data for future use
```

**Post-Conversion Update:**
```
✅ Database updated: video_converted, stereo_created
```

**No Changes Required:**
The integration is automatic! Just run media_update.py normally:
```bash
# Automatic caching enabled
python3 media_update.py --file /path/to/movie.mkv
```

---

## 🚀 **Typical Workflows**

### **Initial Setup (One-Time)**
```bash
# 1. Scan entire library (takes ~20-30 minutes for large library)
cd /Storage/docker/mediabox/scripts
python3 build_media_database.py --scan /Storage/media/movies /Storage/media/tv /Storage/media/music

# 2. Review what needs conversion
python3 query_media_database.py --needs-conversion

# 3. Check for HDR content
python3 query_media_database.py --hdr
```

### **Weekly Maintenance**
```bash
# Re-scan for new downloads (fast - 2 minutes for 700 movies)
python3 build_media_database.py --scan /Storage/media/movies /Storage/media/tv

# Clean up deleted files
python3 build_media_database.py --cleanup

# Review conversion queue
python3 query_media_database.py --needs-conversion
```

### **Conversion Planning**
```bash
# 1. Find all files needing HDR tone mapping
python3 query_media_database.py --by-action needs_hdr_tonemap --export hdr_queue.txt

# 2. Process queue
while IFS= read -r file; do
    python3 media_update.py --file "$file"
done < hdr_queue.txt
```

### **Analysis & Reporting**
```bash
# Library statistics
python3 query_media_database.py --stats

# Recent processing activity
python3 query_media_database.py --history --days 7

# Find all 4K content
python3 query_media_database.py --resolution 3840x2160

# Search for specific show
python3 query_media_database.py --search "Game of Thrones"
```

---

## 📊 **Database Statistics**

### **What's Tracked:**
- Total files scanned
- Files by action (skip, needs_conversion, needs_hdr_tonemap, etc.)
- Files by resolution (4K, 1080p, 720p, etc.)
- Files by codec (h264, hevc, mpeg4, etc.)
- HDR file count
- Processing history with timestamps

### **Example Statistics Output:**
```
📊 Database Statistics
============================================================
Total files: 1,247

By action:
  skip                          892
  needs_hdr_tonemap            123
  needs_stereo_track            89
  needs_audio_conversion        67
  needs_video_conversion        76

Top resolutions:
  1920x1080       734
  3840x2160       312
  1280x720        156
  720x404          45

Video codecs:
  h264            892
  hevc            245
  mpeg4            76
  vp9              34

HDR files: 123
============================================================
```

---

## 🔍 **File Fingerprinting**

### **How It Works:**
```python
# SHA256 hash of: path + size + mtime
fingerprint = hashlib.sha256(
    f"{file_path}|{size}|{mtime}".encode()
).hexdigest()
```

### **Why This Approach:**
- **Fast**: No file I/O (uses filesystem metadata)
- **Accurate**: Detects file changes (size/mtime modified)
- **Unique**: Path + size + mtime combination
- **Stable**: Doesn't change unless file changes

### **When Cache Invalidates:**
- File size changes (re-encode, different quality)
- File modified time changes (file replaced)
- File path changes (moved/renamed)

---

## 🎯 **Action Types**

The database tracks what action is needed for each file:

| Action | Meaning |
|--------|---------|
| `skip` | File is perfect (H.264/AAC, no issues) |
| `needs_video_conversion` | Wrong video codec (not H.264) |
| `needs_audio_conversion` | Wrong audio codec (not AAC) |
| `needs_hdr_tonemap` | HDR content requiring tone mapping |
| `needs_stereo_track` | Surround sound without stereo downmix |
| `needs_51_from_71` | 7.1 audio without 5.1 track |
| `needs_audio_metadata_fix` | Missing/wrong language tags |

---

## 🛠️ **Troubleshooting**

### **Database location:**
```bash
~/.local/share/mediabox/media_cache.db
```

### **Custom database path:**
```bash
python3 build_media_database.py --scan /path --db /custom/path/cache.db
python3 query_media_database.py --hdr --db /custom/path/cache.db
```

### **Reset database:**
```bash
rm -f ~/.local/share/mediabox/media_cache.db
python3 build_media_database.py --scan /Storage/media/movies  # Rebuild
```

### **Check database size:**
```bash
ls -lh ~/.local/share/mediabox/media_cache.db
du -h ~/.local/share/mediabox/
```

### **Verify cache hits:**
```bash
# Run with verbose output
python3 media_update.py --file /path/to/movie.mkv

# Look for:
# "📦 Using cached metadata for: movie.mkv"  <- Cache hit
# "Probed file (no cache): movie.mkv"       <- Cache miss
```

---

## 📈 **Performance Expectations**

### **Initial Scan (No Cache):**
- 700 movies: ~20-25 minutes
- 150 TV shows (~2000 episodes): ~45-60 minutes
- Full library (3000 files): ~60-90 minutes

### **Re-Scan (With Cache):**
- 700 movies: ~2-3 minutes
- 150 TV shows: ~5-8 minutes
- Full library: ~10-15 minutes

### **Individual File Processing:**
- Cache hit: Instant (<0.1s for metadata lookup)
- Cache miss: 1-2s (ffprobe + cache storage)

### **Speedup Factor:**
- **11x faster** on re-scans with no file changes
- **~1.5x faster** on media_update.py with cache enabled

---

## 🔐 **Security & Privacy**

### **What's Stored:**
- File paths, sizes, modification times
- FFmpeg probe output (technical metadata)
- Processing history (actions taken, timestamps)

### **What's NOT Stored:**
- File contents
- Personal information
- Credentials or tokens

### **Database Permissions:**
```bash
# Database auto-created with user-only permissions
ls -l ~/.local/share/mediabox/
# -rw------- (600) - Owner read/write only
```

---

## 🎓 **Advanced Usage**

### **Custom Queries (SQL):**
```bash
# Access database directly
sqlite3 ~/.local/share/mediabox/media_cache.db

# Example queries:
SELECT resolution, COUNT(*) FROM media_cache GROUP BY resolution;
SELECT * FROM media_cache WHERE is_hdr = 1 AND action != 'skip';
SELECT * FROM processing_log ORDER BY processed_at DESC LIMIT 10;
```

### **Export for External Tools:**
```bash
# Export all paths to text file
python3 query_media_database.py --needs-conversion --export queue.txt

# Export full metadata as JSON
python3 query_media_database.py --hdr --export-json hdr_catalog.json

# Use with other scripts
cat queue.txt | xargs -I {} python3 media_update.py --file "{}"
```

### **Integration with Smart Bulk Converter:**
```bash
# The smart converter will automatically use cache!
# No additional configuration required
cd /Storage/docker/mediabox/scripts
./smart-bulk-convert.sh /Storage/media/movies
```

---

## 📚 **Related Documentation**

- [Main README](../README.md) - Complete Mediabox documentation
- [Smart Bulk Conversion](SMART_BULK_CONVERSION_REFERENCE.md) - Batch processing
- [HDR Tone Mapping](HDR_TONE_MAPPING.md) - HDR processing guide
- [Log Management](LOG_MANAGEMENT.md) - Log rotation and cleanup

---

**Last Updated:** January 2025  
**Mediabox Version:** 2.0+  
**Database Version:** 1.0
