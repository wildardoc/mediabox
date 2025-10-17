@echo off
REM Mediabox Media Converter Installation Script for Windows 11
REM This batch file installs media_update.py and its dependencies

echo.
echo ================================================================
echo.
echo     Mediabox Standalone Media Converter Installer
echo                  Windows 11 Edition
echo.
echo  Install media_update.py conversion tools on Windows
echo  Optimized for dedicated conversion workstations
echo.
echo ================================================================
echo.

REM Set installation directory
set INSTALL_DIR=%LOCALAPPDATA%\mediabox-converter

echo [INFO] Checking Python installation...
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found!
    echo.
    echo Please install Python 3.8+ first:
    echo   1. Run: winget install Python.Python.3.12
    echo   2. Close and reopen this terminal
    echo   3. Run this script again
    echo.
    pause
    exit /b 1
)
echo [SUCCESS] Python is installed

echo [INFO] Checking FFmpeg installation...
ffmpeg -version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] FFmpeg not found!
    echo.
    echo Please install FFmpeg:
    echo   1. Run: winget install Gyan.FFmpeg
    echo   2. Close and reopen this terminal
    echo   3. Run this script again
    echo.
    echo Installation will continue, but conversion won't work without FFmpeg.
    pause
)
echo [SUCCESS] FFmpeg is installed

echo [INFO] Creating installation directory: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo [INFO] Creating Python virtual environment...
python -m venv "%INSTALL_DIR%\.venv"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to create virtual environment
    pause
    exit /b 1
)
echo [SUCCESS] Virtual environment created

echo [INFO] Installing Python dependencies...
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install --upgrade pip setuptools wheel
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install ffmpeg-python==0.2.0
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install future==1.0.0
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install PlexAPI==4.15.8
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install requests==2.31.0
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to install Python dependencies
    pause
    exit /b 1
)
echo [SUCCESS] Python dependencies installed

echo [INFO] Installing media_update.py...
if not exist "%~dp0media_update.py" (
    echo [ERROR] media_update.py not found in %~dp0
    echo [ERROR] Please run this script from the scripts/ directory
    pause
    exit /b 1
)
copy /Y "%~dp0media_update.py" "%INSTALL_DIR%\" >nul
echo [SUCCESS] media_update.py installed

echo [INFO] Installing database support files...
if exist "%~dp0media_database.py" (
    copy /Y "%~dp0media_database.py" "%INSTALL_DIR%\" >nul
    echo [SUCCESS] media_database.py installed
)
if exist "%~dp0build_media_database.py" (
    copy /Y "%~dp0build_media_database.py" "%INSTALL_DIR%\" >nul
    echo [SUCCESS] build_media_database.py installed
)
if exist "%~dp0query_media_database.py" (
    copy /Y "%~dp0query_media_database.py" "%INSTALL_DIR%\" >nul
    echo [SUCCESS] query_media_database.py installed
)
if exist "%~dp0requirements.txt" (
    copy /Y "%~dp0requirements.txt" "%INSTALL_DIR%\" >nul
)

echo [INFO] Creating configuration file...
(
echo {
echo   "venv_path": "C:\\Users\\%USERNAME%\\AppData\\Local\\mediabox-converter\\.venv",
echo   "env_file": "C:\\Users\\%USERNAME%\\AppData\\Local\\mediabox-converter\\.env",
echo   "download_dirs": [],
echo   "library_dirs": {
echo     "tv": "",
echo     "movies": "",
echo     "music": "",
echo     "misc": ""
echo   },
echo   "container_support": false,
echo   "plex_integration": {
echo     "url": "",
echo     "token": "",
echo     "path_mappings": {
echo       "tv": "",
echo       "movies": "",
echo       "music": ""
echo     }
echo   },
echo   "transcoding": {
echo     "video": {
echo       "codec": "libx264",
echo       "crf": 23,
echo       "audio_codec": "aac"
echo     },
echo     "audio": {
echo       "codec": "libmp3lame",
echo       "bitrate": "320k"
echo     }
echo   },
echo   "gpu_type": "auto"
echo }
) > "%INSTALL_DIR%\mediabox_config.json"
echo [SUCCESS] Configuration created

echo [INFO] Creating wrapper script...
(
echo @echo off
echo REM Mediabox Media Converter Wrapper
echo.
echo set INSTALL_DIR=%%LOCALAPPDATA%%\mediabox-converter
echo set VENV_PYTHON=%%INSTALL_DIR%%\.venv\Scripts\python.exe
echo.
echo if not exist "%%VENV_PYTHON%%" ^(
echo     echo ERROR: Virtual environment not found
echo     echo Please check installation at %%INSTALL_DIR%%
echo     exit /b 1
echo ^)
echo.
echo REM Run media_update.py with all arguments
echo "%%VENV_PYTHON%%" "%%INSTALL_DIR%%\media_update.py" %%*
) > "%INSTALL_DIR%\media-converter.bat"
echo [SUCCESS] Wrapper script created

echo [INFO] Adding to system PATH...
powershell -Command "$path = [Environment]::GetEnvironmentVariable('Path', 'User'); if ($path -notlike '*%INSTALL_DIR%*') { [Environment]::SetEnvironmentVariable('Path', $path + ';%INSTALL_DIR%', 'User'); Write-Host '[SUCCESS] Added to PATH' } else { Write-Host '[INFO] Already in PATH' }"

echo.
echo ================================================================
echo.
echo              Installation Complete!
echo.
echo ================================================================
echo.
echo Installation directory: %INSTALL_DIR%
echo Command wrapper: %INSTALL_DIR%\media-converter.bat
echo Configuration: %INSTALL_DIR%\mediabox_config.json
echo.
echo Next steps:
echo   1. Close and reopen your terminal (for PATH changes)
echo   2. Test installation: media-converter --help
echo   3. Read usage guide: notepad %INSTALL_DIR%\USAGE.md
echo.
echo Conversion examples:
echo   # Single file
echo   media-converter --file "C:\Media\video.mp4" --type video
echo.
echo   # Network share
echo   media-converter --dir "\\server\media\movies" --type both
echo.
echo   # HDR tone mapping
echo   media-converter --file "hdr_movie.mp4" --type video --downgrade-resolution
echo.
pause
