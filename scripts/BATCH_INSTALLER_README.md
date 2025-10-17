# Windows 11 Installation - Batch Installer

This is the **working installer** for Windows 11 systems. The PowerShell installer (`install-media-converter.ps1`) has been deprecated due to encoding issues.

## ✅ Quick Start

### Prerequisites
- Windows 11 (or Windows 10 1809+)
- Administrator access (for installing Python & FFmpeg)

### Installation Steps

**1. Install Python & FFmpeg** (Administrator PowerShell):
```powershell
winget install Python.Python.3.12
winget install Gyan.FFmpeg
```

**2. Close and reopen terminal** (for PATH changes)

**3. Run the batch installer**:
```cmd
cd C:\path\to\mediabox\scripts
.\install-media-converter.bat
```

**4. Close and reopen terminal again**

**5. Test installation**:
```cmd
media-converter --help
```

## 🎯 What the Installer Does

The batch file (`install-media-converter.bat`) automatically:
- ✅ Verifies Python 3.8+ is installed
- ✅ Verifies FFmpeg is installed
- ✅ Creates installation directory at `%LOCALAPPDATA%\mediabox-converter`
- ✅ Creates Python virtual environment
- ✅ Installs Python dependencies (ffmpeg-python, PlexAPI, etc.)
- ✅ Copies `media_update.py` and database tools
- ✅ Creates configuration file
- ✅ Creates wrapper batch script
- ✅ Adds installation directory to user PATH

## 📦 Installation Location

Everything installs to:
```
C:\Users\<YourUsername>\AppData\Local\mediabox-converter\
├── .venv\                      # Python virtual environment
├── media_update.py             # Main conversion script
├── media_database.py           # Database backend
├── build_media_database.py     # Cache builder
├── query_media_database.py     # Database query tool
├── mediabox_config.json        # Configuration file
├── media-converter.bat         # Command wrapper
└── requirements.txt            # Python dependencies
```

## 🚀 Usage After Installation

### Basic Commands

**Process a single file:**
```cmd
media-converter --file "C:\Media\movie.mkv" --type video
```

**Process entire directory:**
```cmd
media-converter --dir "C:\Media\Movies" --type both
```

**HDR tone mapping (4K to 1080p):**
```cmd
media-converter --file "C:\Media\4k-movie.mkv" --type video --downgrade-resolution
```

**Audio conversion:**
```cmd
media-converter --dir "C:\Music" --type audio
```

### Network Shares

**Map network drive:**
```cmd
net use Z: \\server\media /persistent:yes
media-converter --dir "Z:\movies" --type video
```

**Or use UNC paths directly:**
```cmd
media-converter --dir "\\server\media\movies" --type video
```

## 🔧 Configuration

Edit the configuration file:
```cmd
notepad %LOCALAPPDATA%\mediabox-converter\mediabox_config.json
```

### Key Settings

**GPU acceleration:**
- `"gpu_type": "auto"` - Auto-detect GPU
- `"gpu_type": "nvidia"` - Force NVIDIA NVENC
- `"gpu_type": "intel"` - Force Intel Quick Sync
- `"gpu_type": "none"` - Software encoding only

**Video transcoding:**
```json
"transcoding": {
  "video": {
    "codec": "libx264",
    "crf": 23,
    "audio_codec": "aac"
  }
}
```

**Audio transcoding:**
```json
"audio": {
  "codec": "libmp3lame",
  "bitrate": "320k"
}
```

## 🐛 Troubleshooting

### "media-converter not found"
**Solution:** Use full path or restart terminal:
```cmd
%LOCALAPPDATA%\mediabox-converter\media-converter.bat --help
```

### "Python not found" during installation
**Solution:**
1. Install Python: `winget install Python.Python.3.12`
2. Close and reopen terminal
3. Run installer again

### "FFmpeg not found" during conversion
**Solution:**
1. Install FFmpeg: `winget install Gyan.FFmpeg`
2. Close and reopen terminal
3. Verify: `ffmpeg -version`

### Virtual environment errors
**Solution:** Delete and reinstall:
```cmd
rmdir /s /q %LOCALAPPDATA%\mediabox-converter
cd C:\path\to\mediabox\scripts
.\install-media-converter.bat
```

## 📊 Database Caching (11x Faster)

Build metadata cache for faster re-scans:

```cmd
cd %LOCALAPPDATA%\mediabox-converter
.venv\Scripts\python.exe build_media_database.py --scan "C:\Media\Movies"
```

Query the database:
```cmd
# Show HDR content
.venv\Scripts\python.exe query_media_database.py --hdr

# Show statistics
.venv\Scripts\python.exe query_media_database.py --stats
```

## 🔄 Distributed Processing

Multiple Windows machines can process the same network share simultaneously without conflicts.

**Machine 1:**
```cmd
media-converter --dir "\\server\media\movies\A-M" --type video
```

**Machine 2:**
```cmd
media-converter --dir "\\server\media\movies\N-Z" --type video
```

Files are locked during processing (`.mediabox.lock`) to prevent duplicate work.

## 🗑️ Uninstall

**Remove installation:**
```cmd
rmdir /s /q %LOCALAPPDATA%\mediabox-converter
```

**Remove from PATH:**
1. Press `Win+R` → `sysdm.cpl`
2. Advanced → Environment Variables
3. Edit User PATH
4. Remove `%LOCALAPPDATA%\mediabox-converter`

## 📝 Advanced Options

### All Command-Line Options

```cmd
media-converter [OPTIONS]

Required (one of):
  --file FILE          Process single file
  --dir DIRECTORY      Process entire directory

Optional:
  --type {video,audio,both}    Processing type (default: both)
  --force-stereo              Force enhanced stereo track creation
  --downgrade-resolution      Scale 4K+ content to 1080p max
  --help                      Show help message
```

### Examples

**Force enhanced stereo (boosted dialogue):**
```cmd
media-converter --file "movie.mkv" --force-stereo
```

**Combine options:**
```cmd
media-converter --dir "C:\Movies" --type video --downgrade-resolution --force-stereo
```

**Video only (preserve audio/subs):**
```cmd
media-converter --file "show.mkv" --type video
```

**Audio only (music conversion):**
```cmd
media-converter --dir "C:\Music\FLAC" --type audio
```

## 🌟 Features

### Hardware Acceleration
- **NVIDIA NVENC** - GPU-accelerated encoding (if FFmpeg built with CUDA)
- **Intel Quick Sync** - Integrated GPU acceleration
- **Software fallback** - Works on any system

### Media Processing
- **HDR → SDR tone mapping** - Automatic detection and conversion
- **4K → 1080p downgrading** - Resolution scaling with `--downgrade-resolution`
- **Audio enhancement** - Dialogue boost for stereo tracks
- **Subtitle extraction** - PGS subtitles to .sup files
- **Metadata preservation** - Keeps all metadata during conversion

### Smart Processing
- **File locking** - Prevents duplicate work across multiple machines
- **Database caching** - 11x faster directory scans on re-runs
- **Resume support** - Continues from where it stopped
- **Orphan detection** - Finds and cleans up incomplete conversions

## 📚 Related Documentation

- [MANUAL_WINDOWS_INSTALL.md](MANUAL_WINDOWS_INSTALL.md) - Step-by-step manual installation
- [WINDOWS_INSTALL.md](WINDOWS_INSTALL.md) - Quick installation reference
- [../docs/DISTRIBUTED_PROCESSING.md](../docs/DISTRIBUTED_PROCESSING.md) - Multi-machine setup guide

## 🆘 Support

If you encounter issues:
1. Check this README's troubleshooting section
2. See [MANUAL_WINDOWS_INSTALL.md](MANUAL_WINDOWS_INSTALL.md) for manual installation
3. Verify Python and FFmpeg are in PATH: `python --version` and `ffmpeg -version`
4. Check installation directory exists: `dir %LOCALAPPDATA%\mediabox-converter`

---

**Installation time:** ~5 minutes  
**Prerequisites:** Python 3.8+, FFmpeg  
**Works on:** Windows 10 (1809+), Windows 11
