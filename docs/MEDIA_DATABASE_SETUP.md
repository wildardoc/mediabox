# Media Database Setup Guide

## ✅ **No Additional Setup Required!**

The media database system uses **only existing dependencies** and requires **no changes** to setup scripts.

---

## 📦 **Dependencies**

### **Database Scripts Use:**
- `sqlite3` - Built into Python (no installation needed)
- `ffmpeg-python==0.2.0` - ✅ Already in `requirements.txt`
- Standard library modules: `os`, `sys`, `json`, `hashlib`, `datetime`, `pathlib`, `argparse`

### **Already Installed By:**
- ✅ `mediabox.sh` - Installs `requirements.txt` during initial setup
- ✅ `install-media-converter.sh` - Installs `requirements.txt` for standalone deployments
- ✅ Docker containers - Auto-install dependencies on startup

---

## 🚀 **Ready to Use Immediately**

If you've already run `mediabox.sh` or have Docker containers running, the database system works **out of the box**:

```bash
# No setup needed - just run!
python3 build_media_database.py --scan /Storage/media/movies
python3 query_media_database.py --hdr
```

### **Automatic Features:**
- ✅ **Auto-activates venv** - Reads `mediabox_config.json` for venv path
- ✅ **Auto-creates database** - Creates `~/.local/share/mediabox/media_cache.db` on first run
- ✅ **Auto-creates directory** - Creates `~/.local/share/mediabox/` if needed
- ✅ **Auto-initializes schema** - Creates tables and indexes automatically

---

## 🔧 **First Run**

### **When You First Use the Database:**

```bash
cd /Storage/docker/mediabox/scripts

# Scan your library (creates database automatically)
python3 build_media_database.py --scan /Storage/media/movies /Storage/media/tv

# Expected output:
# 🔍 Scanning directories...
#    Database: /home/robert/.local/share/mediabox/media_cache.db
#    Directories: 2
# 
# 📁 Scanning: /Storage/media/movies
#    Found 700 media files
#    Progress: [████████████████████████████████████████] 700/700 (100.0%)
# 
# ============================================================
# 📊 Scan Complete
# ============================================================
# Total files scanned:    700
#   • New files:          700
#   • HDR detected:       45
# Time elapsed:           0:23:15
```

### **Database Location:**
- **Default:** `~/.local/share/mediabox/media_cache.db`
- **Custom:** Use `--db /custom/path/cache.db` with any script
- **Permissions:** Auto-created with user-only access (600)

---

## 🔄 **Integration with Existing Scripts**

### **media_update.py**
The database integration is **automatic** and **opt-in**:

- ✅ If `media_database.py` exists → Uses caching
- ✅ If `media_database.py` missing → Works normally (no caching)
- ✅ If database unavailable → Graceful fallback (no errors)

### **smart-bulk-convert.sh**
Works automatically with caching:
- Calls `media_update.py` which has database integration
- No changes needed to smart converter
- Cache speedup applies automatically

---

## 📋 **Verification Checklist**

Run these commands to verify everything is ready:

### **1. Check Python Dependencies**
```bash
cd /Storage/docker/mediabox/scripts
source .venv/bin/activate
python3 -c "import sqlite3, ffmpeg; print('✅ All dependencies available')"
```

### **2. Check Database Scripts Exist**
```bash
ls -lh scripts/media_database.py scripts/build_media_database.py scripts/query_media_database.py
```

### **3. Test Database Creation**
```bash
python3 build_media_database.py --stats
# Should create database and show:
# Total files: 0  (empty database)
```

### **4. Check Database File**
```bash
ls -lh ~/.local/share/mediabox/media_cache.db
# Should show database file with user-only permissions
```

---

## 🛠️ **Manual Setup (Edge Cases)**

### **If Virtual Environment Missing:**

```bash
cd /Storage/docker/mediabox/scripts

# Create venv
python3 -m venv .venv

# Activate
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### **If requirements.txt Missing:**

```bash
# Install manually
pip install ffmpeg-python==0.2.0 future==1.0.0 PlexAPI==4.15.8 requests==2.31.0
```

### **If Database Directory Not Created:**

```bash
# Auto-created on first run, but can create manually:
mkdir -p ~/.local/share/mediabox
chmod 700 ~/.local/share/mediabox
```

---

## 🐳 **Docker Container Support**

### **Container Integration:**

The database scripts work in Docker containers with **no modifications**:

```yaml
# docker-compose.yml excerpt
sonarr:
  volumes:
    - ./scripts:/scripts
    - ~/.local/share/mediabox:/root/.local/share/mediabox  # Database persistence
```

### **Database Location in Containers:**
- Same path works: `~/.local/share/mediabox/media_cache.db`
- Maps to `/root/.local/share/mediabox/` inside container
- Shared across all containers if volume mounted

---

## 📊 **System Requirements**

### **Minimum Requirements:**
- Python 3.6+ (already required by mediabox)
- 10MB disk space (database grows with library size)
- SQLite support (built into Python)

### **Recommended:**
- Python 3.8+ (better performance)
- 50MB disk space (room for growth)
- SSD storage (faster database operations)

### **Database Size Estimates:**
- 100 movies: ~1MB database
- 1,000 movies: ~10MB database
- 5,000 movies: ~50MB database

---

## ❓ **FAQ**

### **Q: Do I need to run mediabox.sh again?**
**A:** No! If you've already run `mediabox.sh`, all dependencies are installed.

### **Q: Do I need to modify Docker containers?**
**A:** No! Containers auto-install dependencies from `requirements.txt` on startup.

### **Q: Will this break existing workflows?**
**A:** No! The integration is backward compatible and non-breaking.

### **Q: What if I don't want to use the database?**
**A:** It's opt-in! Just don't run the database scripts. `media_update.py` works with or without it.

### **Q: Can I delete the database?**
**A:** Yes! Simply: `rm -f ~/.local/share/mediabox/media_cache.db`
The database will be recreated on next scan.

### **Q: Does this work on the desktop (standalone converter)?**
**A:** Yes! `install-media-converter.sh` already installs `requirements.txt`, so database scripts work immediately.

---

## 🎯 **Quick Start (TL;DR)**

If you've already set up mediabox, **you're ready to go**:

```bash
# Just run it!
cd /Storage/docker/mediabox/scripts
python3 build_media_database.py --scan /Storage/media/movies
python3 query_media_database.py --stats
```

**That's it!** No additional setup required. 🎉

---

**Last Updated:** January 2025  
**Mediabox Version:** 2.0+  
**Database Version:** 1.0
