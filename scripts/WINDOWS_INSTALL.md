# Windows 11 Installation Quick Start

## Install on Windows 11

### **Automated Installation (Recommended)**

1. **Clone repository:**
   ```powershell
   git clone https://github.com/wildardoc/mediabox.git
   cd mediabox\scripts
   ```

2. **Install Python & FFmpeg** (as Administrator):
   ```powershell
   winget install Python.Python.3.12
   winget install Gyan.FFmpeg
   ```

3. **Close and reopen terminal**, then run installer:
   ```cmd
   .\install-media-converter.bat
   ```

4. **Restart terminal** and test:
   ```cmd
   media-converter --help
   ```

### **Manual Installation**

If the automated installer fails, see [MANUAL_WINDOWS_INSTALL.md](MANUAL_WINDOWS_INSTALL.md) for step-by-step instructions.

## What Gets Installed

✅ **Python 3.12** (auto-installed via winget if missing)  
✅ **FFmpeg** (auto-installed via winget/Chocolatey if missing)  
✅ **Virtual environment** at `%LOCALAPPDATA%\mediabox-converter`  
✅ **Wrapper script** in PATH for easy access  
✅ **Database tools** for 11x faster scanning  

## Quick Examples

### Map Network Drive
```cmd
net use Z: \\server\media /persistent:yes
```

### Process Files
```cmd
REM Single file
media-converter --file "Z:\movies\Movie.mkv" --type video

REM Entire directory
media-converter --dir "Z:\movies" --type both

REM HDR tone mapping
media-converter --file "movie.mkv" --type video --downgrade-resolution
```

## Distributed Processing

Multiple Windows machines can process the same network share simultaneously:

**Machine 1:**
```cmd
media-converter --dir "Z:\movies\A-M" --type video
```

**Machine 2:**
```cmd
media-converter --dir "Z:\movies\N-Z" --type video
```

**Result:** 2x faster processing, no conflicts!

Files are locked while processing (`.mediabox.lock`), preventing duplicate work.

## Features

🚀 **Hardware Acceleration:**
- NVIDIA NVENC (if FFmpeg compiled with CUDA)
- Intel Quick Sync (auto-detected)
- Software fallback (always works)

📦 **Metadata Caching:**
- 11x faster re-scans
- Shared cache across all machines
- Per-directory JSON files

🔒 **File Locking:**
- Prevents processing conflicts
- Safe for multiple workers
- 30-minute timeout for crashed processes

🎬 **Media Processing:**
- HDR → SDR tone mapping
- 4K → 1080p downgrading
- Audio enhancement (dialogue boost)
- Subtitle extraction

## Configuration

Edit: `%LOCALAPPDATA%\mediabox-converter\mediabox_config.json`

```json
{
  "gpu_type": "nvidia",
  "transcoding": {
    "video": {
      "codec": "libx264",
      "crf": 23
    }
  }
}
```

## Logs

Located in current directory:
```
media_update_20251016.log
media_update_20251015.log.gz
```

## Database Tools

**Build cache:**
```cmd
cd %LOCALAPPDATA%\mediabox-converter
.venv\Scripts\python.exe build_media_database.py --scan Z:\media
```

**Query HDR files:**
```cmd
.venv\Scripts\python.exe query_media_database.py --hdr
```

**Get statistics:**
```cmd
.venv\Scripts\python.exe query_media_database.py --stats
```

## Troubleshooting

### Command Not Found
Restart terminal or use full path:
```cmd
%LOCALAPPDATA%\mediabox-converter\media-converter.bat --help
```

### Python Not Found
```powershell
winget install Python.Python.3.12
```

### FFmpeg Not Found
```powershell
winget install Gyan.FFmpeg
```

## Full Documentation

See: `%LOCALAPPDATA%\mediabox-converter\USAGE.md`

Or online: [DISTRIBUTED_PROCESSING.md](../docs/DISTRIBUTED_PROCESSING.md)

## Uninstall

```cmd
rmdir /s /q %LOCALAPPDATA%\mediabox-converter
```

Remove PATH entry via System Properties → Environment Variables.

---

**Ready to process?** Start with a small test directory first!
