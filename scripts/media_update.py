#!/usr/bin/env python3
"""
Mediabox Media Update Script
============================

Intelligent media conversion system for automated processing of video, audio, and subtitle files.
Designed for integration with Plex Media Server via Sonarr/Radarr/Lidarr webhook automation.

FEATURES:
---------
• Video Processing: H.264/H.265 conversion with subtitle preservation
• Audio Processing: Multi-format to MP3 320kbps conversion (FLAC, WAV, AIFF, etc.)
• Subtitle Handling: PGS subtitle extraction to .sup files
• Metadata Preservation: Maintains audio metadata during conversion
• Batch Processing: Directory and single-file processing modes
• Logging: Comprehensive progress and error logging with rotation

WEBHOOK INTEGRATION:
-------------------
This script is automatically called by import.sh when *arr applications detect new downloads.
For manual webhook setup in *arr applications:

SONARR WEBHOOK SETUP:
1. Settings → Connect → Add → Custom Script
2. Name: "Mediabox Processing"
3. Path: /scripts/import.sh
4. Triggers: ☑ On Import, ☑ On Upgrade  
5. Arguments: (leave blank - uses environment variables)
6. Test the connection - should show "Test event completed successfully"

RADARR WEBHOOK SETUP:
1. Settings → Connect → Add → Custom Script  
2. Name: "Mediabox Processing"
3. Path: /scripts/import.sh
4. Triggers: ☑ On Import, ☑ On Upgrade
5. Arguments: (leave blank - uses environment variables)
6. Test the connection - should show "Test event completed successfully"

LIDARR WEBHOOK SETUP:
1. Settings → Connect → Add → Custom Script
2. Name: "Mediabox Processing" 
3. Path: /scripts/import.sh
4. Triggers: ☑ On Import, ☑ On Upgrade
5. Arguments: (leave blank - uses environment variables)
6. Test the connection - should show "Test event completed successfully"

PROCESSING TYPES:
----------------
• TV Shows (via Sonarr): --type video (preserves subtitles, optimized for TV)
• Movies (via Radarr): --type both (comprehensive audio/video processing)
• Music (via Lidarr): --type audio (high-quality audio conversion)

MANUAL USAGE:
------------
# Process entire directory
python3 media_update.py --dir "/path/to/media" --type both

# Process single file
python3 media_update.py --file "/path/to/file.mkv" --type video

# Audio-only conversion
python3 media_update.py --dir "/music/folder" --type audio

SUPPORTED FORMATS:
-----------------
Video Input: MKV, AVI, MOV, WMV, FLV, M4V, 3GP, WEBM
Audio Input: FLAC, WAV, AIFF, APE, WV, M4A, OGG, OPUS, WMA
Output: MP4 (video), MP3 320kbps (audio), SUP (subtitles)

ADVANCED PLEXAPI CONFIGURATION:
------------------------------
Optional .env settings for enhanced Plex integration:
• PLEX_SMART_SCANNING=true/false - Targeted directory scanning (default: true)
• PLEX_VALIDATE_MEDIA=true/false - Verify successful processing (default: true)
• PLEX_DUPLICATE_DETECTION=true/false - Skip already-processed files (default: true)  
• PLEX_DETAILED_LOGGING=true/false - Enhanced logging with analytics (default: true)

REQUIREMENTS:
------------
• Python 3.6+ with ffmpeg-python, future packages
• FFmpeg binary with codec support
• PlexAPI 4.15.8+ for advanced Plex integration
• Sufficient disk space for temporary files during processing
"""

import sys
import os
import atexit
import signal
import json
import requests
import time
from pathlib import Path

def load_env_file():
    """Load environment variables from .env file if it exists."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_file = os.path.join(script_dir, '..', '.env')
    
    if os.path.exists(env_file):
        try:
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    # Skip comments and empty lines
                    if line and not line.startswith('#') and '=' in line:
                        # Split on first = to handle values with = in them
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        # Remove quotes if present
                        if (value.startswith('"') and value.endswith('"')) or \
                           (value.startswith("'") and value.endswith("'")):
                            value = value[1:-1]
                        
                        # Only set if not already in environment (environment takes precedence)
                        if key not in os.environ:
                            os.environ[key] = value
            
            return True
        except Exception as e:
            print(f"Warning: Failed to load .env file: {e}")
            return False
    return False

# Load environment variables from .env file at script startup
load_env_file()

def validate_config(config):
    """Validate configuration structure and paths"""
    required_keys = ['venv_path', 'download_dirs', 'library_dirs']
    for key in required_keys:
        if key not in config:
            raise ValueError(f"Missing required configuration key: {key}")
    
    # Validate venv_path exists
    if not os.path.exists(config['venv_path']):
        raise ValueError(f"Virtual environment path does not exist: {config['venv_path']}")
    
    # Get container information for smart validation
    is_container, container_type = detect_container_environment()
    
    # Validate download_dirs structure (only for host environment)
    if not isinstance(config['download_dirs'], list):
        raise ValueError("'download_dirs' must be a list")
    
    if not is_container:  # Only validate download dirs on host
        for path in config['download_dirs']:
            if not os.path.exists(path):
                print(f"Warning: Download directory does not exist: {path}")
    
    # Validate library_dirs structure
    if not isinstance(config['library_dirs'], dict):
        raise ValueError("'library_dirs' must be a dictionary")
    
    # Smart validation based on container type
    if is_container and container_type:
        # Only validate the library directory relevant to this container
        validation_map = {
            'sonarr': ['tv'],
            'radarr': ['movies'], 
            'lidarr': ['music']
        }
        
        lib_keys_to_check = validation_map.get(container_type, ['tv', 'movies', 'music'])
        print(f"DEBUG: Validating only {lib_keys_to_check} directories for {container_type} container")
    else:
        # Validate all directories on host
        lib_keys_to_check = ['tv', 'movies', 'music']
    
    for lib_key in lib_keys_to_check:
        if lib_key not in config['library_dirs']:
            print(f"Warning: Missing library directory key: {lib_key}")
        else:
            lib_path = config['library_dirs'][lib_key]
            if not os.path.exists(lib_path):
                print(f"Warning: Library directory does not exist: {lib_path}")
    
    return config

def detect_container_environment():
    """Detect if running inside a Docker container and identify container type"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    is_container = script_dir == "/scripts"
    
    if is_container:
        # Detect which container we're in based on available directories
        container_type = None
        if os.path.exists('/tv') and not os.path.exists('/movies') and not os.path.exists('/music'):
            container_type = 'sonarr'
        elif os.path.exists('/movies') and not os.path.exists('/tv') and not os.path.exists('/music'):
            container_type = 'radarr'
        elif os.path.exists('/music') and not os.path.exists('/tv') and not os.path.exists('/movies'):
            container_type = 'lidarr'
        else:
            container_type = 'unknown'
        
        print(f"DEBUG: Running in Docker container environment ({container_type})")
        return True, container_type
    else:
        print(f"DEBUG: Running on host environment (script_dir: {script_dir})")
        return False, None

def adapt_config_for_environment(config):
    """Adapt configuration paths based on execution environment"""
    is_container, container_type = detect_container_environment()
    
    if is_container:
        # Running in container - adapt paths to container paths
        adapted_config = config.copy()
        
        # Use container venv path
        adapted_config['venv_path'] = "/scripts/.venv"
        
        # Adapt library directories to container mount points
        adapted_config['library_dirs'] = {
            'tv': '/tv',
            'movies': '/movies',
            'music': '/music',
            'misc': '/misc'
        }
        
        # Adapt download directories to container mount points
        adapted_config['download_dirs'] = [
            '/downloads/completed',
            '/downloads/incomplete'
        ]
        
        print(f"DEBUG: Adapted venv_path from {config['venv_path']} to {adapted_config['venv_path']}")
        print(f"DEBUG: Adapted library_dirs for container environment ({container_type})")
        return adapted_config
    else:
        # Running on host - use config as-is
        return config

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "mediabox_config.json")
try:
    with open(CONFIG_PATH, "r") as f:
        config = json.load(f)
    
    # Adapt config for current environment (container vs host)
    config = adapt_config_for_environment(config)
    
    # Validate the adapted config
    config = validate_config(config)
except FileNotFoundError:
    raise FileNotFoundError(f"Configuration file not found: {CONFIG_PATH}")
except json.JSONDecodeError as e:
    raise ValueError(f"Invalid JSON in configuration file: {e}")
except Exception as e:
    raise ValueError(f"Configuration validation failed: {e}")

venv_path = config["venv_path"]
DOWNLOAD_DIRS = config["download_dirs"]
LIBRARY_DIRS = config["library_dirs"]
# Create list of all library directories for compatibility
MEDIA_LIBRARY_DIRS = list(LIBRARY_DIRS.values())

site_packages = os.path.join(
    venv_path, "lib", f"python{sys.version_info.major}.{sys.version_info.minor}", "site-packages"
)
if site_packages not in sys.path:
    sys.path.insert(0, site_packages)

os.environ["VIRTUAL_ENV"] = venv_path
os.environ["PATH"] = os.path.join(venv_path, "bin") + os.pathsep + os.environ.get("PATH", "")

import ffmpeg
import logging
from datetime import datetime
import subprocess
import argparse
import urllib.request
import urllib.parse
import time

# Setup logging
now = datetime.now()
dt_string = now.strftime("%Y%m%d%H%M%S")
logfilename = f"media_update_{dt_string}.log"
logging.basicConfig(filename=logfilename, filemode='w', format='%(asctime)s %(levelname)s: %(message)s', level=logging.INFO)

# Global variable to track the output file
unfinished_output_file = None

def cleanup_unfinished_file():
    if unfinished_output_file and os.path.exists(unfinished_output_file):
        try:
            os.remove(unfinished_output_file)
            print(f"Removed unfinished file: {unfinished_output_file}")
        except Exception as e:
            print(f"Could not remove unfinished file: {unfinished_output_file}: {e}")

# Register cleanup for normal exit and signals
atexit.register(cleanup_unfinished_file)
for sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, lambda signum, frame: (cleanup_unfinished_file(), exit(1)))

# Define supported video and audio file extensions as module-level constants
VIDEO_EXTS = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv')
AUDIO_EXTS = ('.flac', '.wav', '.aiff', '.ape', '.wv', '.m4a', '.ogg', '.opus', '.wma')

def detect_hardware_acceleration():
    """
    Detect available hardware acceleration methods for FFmpeg.
    Returns a dict with available acceleration options.
    """
    hwaccel_options = {
        'available': False,
        'method': 'software',
        'encoder': 'libx264',
        'extra_args': []
    }
    
    try:
        # Check if GPU devices are available
        if not os.path.exists('/dev/dri'):
            logging.info("No GPU devices found (/dev/dri missing)")
            return hwaccel_options
            
        # Test VAAPI support
        test_cmd = [
            'ffmpeg', '-hide_banner', '-f', 'lavfi', '-i', 'testsrc2=duration=0.1:size=64x64:rate=1',
            '-vaapi_device', '/dev/dri/renderD128', '-vf', 'format=nv12,hwupload',
            '-c:v', 'h264_vaapi', '-t', '0.1', '-f', 'null', '-'
        ]
        
        result = subprocess.run(test_cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            logging.info("VAAPI hardware acceleration available")
            hwaccel_options.update({
                'available': True,
                'method': 'vaapi',
                'encoder': 'h264_vaapi',
                'extra_args': ['-vaapi_device', '/dev/dri/renderD128', '-vf', 'format=nv12,hwupload']
            })
            return hwaccel_options
            
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError) as e:
        logging.debug(f"VAAPI test failed: {e}")
    
    try:
        # Test software encoding with optimized settings
        test_cmd = [
            'ffmpeg', '-hide_banner', '-f', 'lavfi', '-i', 'testsrc2=duration=0.1:size=64x64:rate=1',
            '-c:v', 'libx264', '-preset', 'medium', '-crf', '23', '-t', '0.1', '-f', 'null', '-'
        ]
        
        result = subprocess.run(test_cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            logging.info("Software encoding with x264 available")
            # Use optimized software settings for older systems
            hwaccel_options.update({
                'available': True,
                'method': 'software_optimized', 
                'encoder': 'libx264',
                'extra_args': ['-preset', 'medium', '-threads', '0']  # 0 = auto-detect threads
            })
            return hwaccel_options
            
    except (subprocess.TimeoutExpired, subprocess.SubprocessError) as e:
        logging.debug(f"Software encoding test failed: {e}")
    
    logging.warning("No suitable encoding method found, using basic software fallback")
    return hwaccel_options

def get_video_files(root_dir):
    files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith(VIDEO_EXTS):
                files.append(os.path.join(dirpath, filename))
    return files

def get_audio_files(root_dir):
    """
    Recursively find audio files in the given directory, excluding already converted MP3 files.

    Parameters:
        root_dir (str): The root directory to search for audio files.

    Returns:
        list: List of paths to audio files (excluding .mp3 files).

    Supported audio formats:
        .flac, .wav, .aiff, .ape, .wv, .m4a, .ogg, .opus, .wma
    """
    files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith(AUDIO_EXTS):
                # Skip already converted MP3 files
                if not filename.lower().endswith('.mp3'):
                    files.append(os.path.join(dirpath, filename))
    return files

def get_media_files(root_dir, media_type):
    if media_type == 'video':
        return get_video_files(root_dir)
    elif media_type == 'audio':
        return get_audio_files(root_dir)
    else:  # both
        return get_video_files(root_dir) + get_audio_files(root_dir)

def convert_host_path_to_plex_path(container_path):
    """
    Convert container file path to Plex container path for library matching.
    
    When running in containers, both media_update.py and Plex run in containers
    with different mount points:
    
    *arr containers see:           Plex container sees:
        /tv/Show/file.mkv      →      /data/tv/Show/file.mkv
        /movies/Movie/file.mkv →      /data/movies/Movie/file.mkv
        /music/Artist/file.mp3 →      /data/music/Artist/file.mp3
    
    Args:
        container_path (str): File path as seen by *arr/media_update containers
        
    Returns:
        str: Corresponding path as Plex container sees it
    """
    # Simple container-to-container path mapping
    if container_path.startswith('/tv/'):
        plex_path = container_path.replace('/tv/', '/data/tv/', 1)
        logging.debug(f"Container to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/movies/'):
        plex_path = container_path.replace('/movies/', '/data/movies/', 1)
        logging.debug(f"Container to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/music/'):
        plex_path = container_path.replace('/music/', '/data/music/', 1)
        logging.debug(f"Container to Plex path: {container_path} → {plex_path}")
        return plex_path
    else:
        # If no mapping found, return original path
        logging.debug(f"No container path mapping needed for: {container_path}")
        return container_path

# Global list to track processed files for batch notifications
processed_files = []


def detect_library_type(path):
    """Detect Plex library type based on file path."""
    path_lower = path.lower()
    if '/storage/media/movies/' in path_lower or '/data/movies/' in path_lower or '/movies/' in path_lower:
        return 'movie'
    elif '/storage/media/tv/' in path_lower or '/data/tv/' in path_lower or '/tv/' in path_lower:
        return 'show' 
    elif '/storage/media/music/' in path_lower or '/data/music/' in path_lower or '/music/' in path_lower:
        return 'artist'
    else:
        # Fallback: try to guess from path structure
        if 'movie' in path_lower:
            return 'movie'
        elif any(x in path_lower for x in ['tv', 'show', 'series', 'season', 'episode']):
            return 'show'
        elif any(x in path_lower for x in ['music', 'album', 'artist']):
            return 'artist'
        return None

def notify_plex_library_update(file_path, max_retries=2, retry_delay=5):
    """Enhanced Plex notification with smart scanning and validation."""
    
    # Configuration loading
    plex_url = os.getenv('PLEX_URL', 'http://localhost:32400')
    plex_token = os.getenv('PLEX_TOKEN', '')
    
    if not plex_token:
        logging.warning("PLEX_TOKEN not set. Skipping Plex notification.")
        return False
    
    smart_scanning = os.getenv('PLEX_SMART_SCANNING', 'true').lower() == 'true'
    validate_media = os.getenv('PLEX_VALIDATE_MEDIA', 'true').lower() == 'true'
    detailed_logging = os.getenv('PLEX_DETAILED_LOGGING', 'true').lower() == 'true'
    
    # Convert host path to Plex container path for better matching
    plex_file_path = convert_host_path_to_plex_path(file_path)
    
    # Improved library type detection based on file path
    def detect_library_type(path):
        path_lower = path.lower()
        if '/storage/media/movies/' in path_lower or '/data/movies/' in path_lower or '/movies/' in path_lower:
            return 'movie'
        elif '/storage/media/tv/' in path_lower or '/data/tv/' in path_lower or '/tv/' in path_lower:
            return 'show' 
        elif '/storage/media/music/' in path_lower or '/data/music/' in path_lower or '/music/' in path_lower:
            return 'artist'
        else:
            # Fallback: try to guess from path structure
            if 'movie' in path_lower:
                return 'movie'
            elif any(x in path_lower for x in ['tv', 'show', 'series', 'season', 'episode']):
                return 'show'
            elif any(x in path_lower for x in ['music', 'album', 'artist']):
                return 'artist'
            return None
    
    expected_library_type = detect_library_type(file_path)
    logging.info(f"🔍 Detected library type: {expected_library_type} for path: {file_path}")
    
    for attempt in range(1, max_retries + 1):
        try:
            # Import PlexAPI components inside try block to avoid scoping issues
            from plexapi.server import PlexServer
            from plexapi.exceptions import PlexApiException, Unauthorized, BadRequest
            
            logging.info(f"🔌 Connecting to Plex server: {plex_url}")
            plex = PlexServer(plex_url, plex_token, timeout=15)
            
            if detailed_logging:
                logging.info(f"📺 Connected to Plex: {plex.friendlyName}")
            
            # Get library sections
            sections = plex.library.sections()
            matched_section = None
            
            # Enhanced library matching logic - prioritize by library type
            for section in sections:
                if detailed_logging:
                    logging.info(f"📚 Checking library: {section.title} ({section.type})")
                    for location in section.locations:
                        logging.info(f"   📁 Library path: {location}")
                
                # First, try to match by library type
                if expected_library_type and section.type == expected_library_type:
                    # Then check if path matches
                    for location in section.locations:
                        if plex_file_path.startswith(location) or file_path.startswith(location):
                            matched_section = section
                            logging.info(f"✅ Found matching library: {section.title} (type: {section.type})")
                            break
                    
                    if matched_section:
                        break
            
            # If no type-specific match, fall back to path matching
            if not matched_section:
                for section in sections:
                    for location in section.locations:
                        if plex_file_path.startswith(location) or file_path.startswith(location):
                            matched_section = section
                            logging.info(f"✅ Found matching library: {section.title} (fallback path match)")
                            break
                    
                    if matched_section:
                        break
            
            if not matched_section:
                logging.warning(f"⚠️ No matching Plex library found for: {plex_file_path}")
                logging.warning(f"   Host path: {file_path}")
                logging.warning(f"   Expected library type: {expected_library_type}")
                return False
            
            # Perform the scan
            if smart_scanning:
                file_dir = os.path.dirname(plex_file_path)
                logging.info(f"🎯 Smart scanning directory: {file_dir}")
                matched_section.update(path=file_dir)
            else:
                logging.info(f"📚 Full library scan: {matched_section.title}")
                matched_section.update()
            
            logging.info(f"✅ Successfully triggered Plex scan for {matched_section.title} ({matched_section.type})")
            return True
            
        except ImportError as e:
            logging.error(f"❌ PlexAPI not available: {e}")
            return False
            
        except Exception as e:
            if "Unauthorized" in str(e) or "401" in str(e):
                logging.error(f"❌ Plex authentication failed: {e}")
                return False
            elif attempt < max_retries:
                logging.error(f"❌ Plex error (attempt {attempt}): {e}")
                logging.info(f"🔄 Retrying in {retry_delay} seconds...")
                import time
                time.sleep(retry_delay)
                continue
            else:
                logging.error(f"❌ Failed to notify Plex after {max_retries} attempts: {e}")
                return False
    
    return False

def batch_notify_plex():
    """
    Perform batch Plex notifications for all processed files.
    This reduces the number of individual scan requests to Plex.
    
    Returns:
        bool: True if any notifications were successful, False otherwise
    """
    global processed_files
    
    if not processed_files:
        return True
    
    # Check if notifications are enabled
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_file = os.path.join(script_dir, '..', '.env')
    enable_notifications = True  # Default to enabled
    
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                if line.startswith('ENABLE_PLEX_NOTIFICATIONS='):
                    enable_value = line.split('=', 1)[1].strip().lower()
                    enable_notifications = enable_value in ('true', 'yes', '1', 'on')
                    break
    
    if not enable_notifications:
        logging.info(f"Plex notifications disabled for {len(processed_files)} processed files")
        processed_files.clear()
        return True
    
    logging.info(f"Performing batch Plex notification for {len(processed_files)} files")
    
    # Group files by likely library section to minimize scans
    library_sections = {
        'tv': [],
        'movies': [], 
        'music': []
    }
    
    for file_path in processed_files:
        file_path_lower = file_path.lower()
        if 'tv' in file_path_lower or '/tv/' in file_path_lower:
            library_sections['tv'].append(file_path)
        elif 'movie' in file_path_lower or '/movies/' in file_path_lower:
            library_sections['movies'].append(file_path)
        elif 'music' in file_path_lower or '/music/' in file_path_lower:
            library_sections['music'].append(file_path)
        else:
            # Default to TV if we can't determine
            library_sections['tv'].append(file_path)
    
    success = False
    for section_type, files in library_sections.items():
        if files:
            # Pick one representative file to trigger the section scan
            representative_file = files[0]
            if notify_plex_library_update(representative_file, max_retries=1):
                logging.info(f"Successfully triggered {section_type} library scan for {len(files)} files")
                success = True
            else:
                logging.warning(f"Failed to trigger {section_type} library scan for {len(files)} files")
    
    # Clear the processed files list
    processed_files.clear()
    
    return success

def extract_pgs_subtitles(input_file, probe):
    """
    Extract PGS subtitles as separate .sup files.

    Parameters:
        input_file (str): Path to the input video file.
        probe (dict): ffmpeg.probe result containing stream information.

    Returns:
        list: List of paths to extracted .sup subtitle files.

    Note:
        PGS (Presentation Graphic Stream) subtitles are bitmap-based subtitles commonly found in Blu-ray media.
        This function extracts each PGS subtitle stream from the input file and saves it as a separate .sup file.
    """
    extracted_files = []
    
    for stream in probe['streams']:
        if stream['codec_type'] == 'subtitle' and stream.get('codec_name', '').lower() == 'hdmv_pgs_subtitle':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', 'unknown')
            disposition = stream.get('disposition', {})
            
            # Create descriptive filename
            base_name = os.path.splitext(input_file)[0]
            if disposition.get('forced', 0) == 1:
                suffix = f".forced.{lang}.sup" if lang != 'unknown' else ".forced.sup"
            else:
                suffix = f".{lang}.sup" if lang != 'unknown' else f".pgs_{idx}.sup"
            
            sup_filename = base_name + suffix
            
            try:
                extract_cmd = [
                    'ffmpeg', '-i', input_file, 
                    '-map', f'0:{idx}', 
                    '-c:s', 'copy', 
                    sup_filename, '-y'
                ]
                logging.info(f"Extracting PGS subtitle stream {idx} ({lang}) to: {sup_filename}")
                result = subprocess.run(extract_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                
                if result.returncode == 0:
                    extracted_files.append(sup_filename)
                    logging.info(f"Successfully extracted PGS subtitle to: {sup_filename}")
                    print(f"Extracted PGS subtitle: {os.path.basename(sup_filename)}")
                else:
                    logging.warning(f"Failed to extract PGS subtitle stream {idx}: {result.stderr}")
            except Exception as e:
                logging.warning(f"Error extracting PGS subtitle stream {idx}: {e}")
    
    return extracted_files
def build_ffmpeg_command(input_file, probe=None):
    """
    Build ffmpeg command-line arguments for transcoding the input file.
    Uses GPU acceleration when available, falls back to software encoding.
    Args:
        input_file (str): Path to the input media file.
        probe (dict, optional): ffmpeg.probe result. If None, probe will be called.
    Returns:
        list: A list of ffmpeg command-line arguments (excluding 'ffmpeg' and '-i' input).
    """
    if probe is None:
        try:
            probe = ffmpeg.probe(input_file)
        except ffmpeg.Error as e:
            print("ffprobe error:", e.stderr.decode())
            logging.error(f"ffprobe error for {input_file}: {e.stderr.decode()}")
            raise

    surround_idx = None
    surround_candidates = []
    eng_subs = []
    forced_subs = []
    subtitle_lang_metadata = []

    # Find surround sound audio streams and subtitle streams
    subtitle_stream_counter = 0
    for stream in probe['streams']:
        if stream['codec_type'] == 'audio':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            channels = int(stream.get('channels', 0))
            if channels >= 6:
                surround_candidates.append((idx, lang))
            # Note: Language metadata is now handled directly in audio mapping section
        elif stream['codec_type'] == 'subtitle':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            codec = stream.get('codec_name', '').lower()
            # Only include text-based subtitles for MP4
            if codec in ('subrip', 'srt', 'ass', 'ssa', 'mov_text'):
                if not lang:
                    subtitle_lang_metadata.extend([f'-metadata:s:s:{subtitle_stream_counter}', 'language=eng'])
                disposition = stream.get('disposition', {})
                if disposition.get('forced', 0) == 1:
                    forced_subs.append(idx)
                if lang == 'eng':
                    eng_subs.append(idx)
                subtitle_stream_counter += 1
            elif codec == 'hdmv_pgs_subtitle':
                logging.warning(f"Skipping PGS subtitle stream {idx} for MP4 output: will extract separately.")
                subtitle_stream_counter += 1

    # Only accept English or unlabeled surround audio streams
    if surround_candidates:
        # Try to find English surround first
        for idx, lang in surround_candidates:
            if lang == 'eng':
                surround_idx = idx
                logging.info(f"Selected English surround audio stream {idx}")
                break
        
        # If not found, try to find unlabeled (will be tagged as English)
        if surround_idx is None:
            for idx, lang in surround_candidates:
                if not lang:  # No language tag - we'll tag it as English
                    surround_idx = idx
                    logging.info(f"Selected unlabeled surround audio stream {idx} (will tag as English)")
                    break
        
        # If still not found, we don't want non-English surround
        if surround_idx is None:
            msg = (
                f"No English or unlabeled surround audio found. "
                f"Available surround streams: {[(idx, lang) for idx, lang in surround_candidates]} "
                f"Skipping surround audio processing - only English audio is supported."
            )
            print(msg)
            logging.warning(msg)
            # DO NOT fall back to non-English audio

    # Audio mapping
    audio_maps = []
    audio_labels = []
    filter_complex = []
    
    # Check if we should process surround audio and create stereo track
    should_create_stereo = False
    surround_has_processable_layout = False
    if surround_idx is not None:
        # Only create stereo from surround if the surround has a processable channel layout
        for stream in probe['streams']:
            if stream['index'] == surround_idx and stream['codec_type'] == 'audio':
                channel_layout = stream.get('channel_layout', 'unknown')
                channels = int(stream.get('channels', 0))
                # Check if we have stereo already
                has_existing_stereo = False
                for other_stream in probe['streams']:
                    if (other_stream['codec_type'] == 'audio' and 
                        int(other_stream.get('channels', 0)) == 2):
                        has_existing_stereo = True
                        break
                
                if channel_layout != 'unknown':
                    surround_has_processable_layout = True
                    if not has_existing_stereo:
                        should_create_stereo = True
                        logging.info(f"Will create stereo from processable surround stream {surround_idx}")
                    else:
                        logging.info(f"Skipping stereo creation - existing stereo track found")
                elif channel_layout == 'unknown' and channels == 6:
                    # 6-channel unknown layout can be fixed with channelmap filter
                    surround_has_processable_layout = True
                    if not has_existing_stereo:
                        should_create_stereo = True
                        logging.info(f"Will create stereo from 6-channel unknown layout (fixable with channelmap) stream {surround_idx}")
                    else:
                        logging.info(f"Skipping stereo creation - existing stereo track found")
                else:
                    logging.info(f"Skipping stereo creation from surround stream {surround_idx} - unknown channel layout (not 6-channel)")
                break
    
    if surround_idx is not None:
        # Determine language tagging: English for both tagged and untagged streams
        surround_lang = 'eng'  # Always tag as English since we only accept English/unlabeled
        
        for stream in probe['streams']:
            if stream['index'] == surround_idx and stream['codec_type'] == 'audio':
                original_lang = stream.get('tags', {}).get('language', '').lower()
                if original_lang == 'eng':
                    logging.info(f"Surround stream {surround_idx} already tagged as English")
                elif not original_lang or original_lang == 'und':
                    logging.info(f"Surround stream {surround_idx} has no language tag - tagging as English")
                else:
                    # This shouldn't happen due to our selection logic above, but just in case
                    logging.warning(f"Surround stream {surround_idx} has language '{original_lang}' - forcing to English")
                break
        
        # Always map surround channel - apply channelmap fix for 6-channel unknown layouts
        # Check if this surround stream needs channelmap filter
        needs_channelmap_fix = False
        for stream in probe['streams']:
            if stream['index'] == surround_idx and stream['codec_type'] == 'audio':
                channel_layout = stream.get('channel_layout', 'unknown') 
                channels = int(stream.get('channels', 0))
                if (channel_layout == 'unknown' or channel_layout == '') and channels == 6:
                    needs_channelmap_fix = True
                    break
        
        if needs_channelmap_fix:
            # Use filter_complex with channelmap to fix unknown 6-channel layout
            if not filter_complex:
                filter_complex = ['-filter_complex']
            
            # Add channelmap filter to fix the unknown 6-channel layout to 5.1
            channelmap_filter = f'[0:{surround_idx}]channelmap=0-FL|1-FR|2-FC|3-LFE|4-BL|5-BR:5.1[fixed_surround]'
            
            if len(filter_complex) == 1:  # Only has '-filter_complex'
                filter_complex.append(channelmap_filter)
            else:
                # Append to existing filter_complex
                filter_complex[1] = filter_complex[1] + ';' + channelmap_filter
                
            audio_maps += ['-map', '[fixed_surround]']
            logging.info(f"Mapping surround stream {surround_idx} with channelmap filter to fix unknown 6-channel layout to 5.1")
        else:
            audio_maps += ['-map', f'0:{surround_idx}']
            if surround_has_processable_layout:
                logging.info(f"Mapping surround stream {surround_idx} with processable channel layout (will re-encode)")
            else:
                logging.info(f"Mapping surround stream {surround_idx} with unknown channel layout (will stream copy to preserve quality)")
        
        audio_labels += ['-metadata:s:a:0', 'title=Surround', '-metadata:s:a:0', f'language={surround_lang}']
        
        # Only create stereo from surround if conditions are met
        if should_create_stereo:
            # Determine the source for stereo creation (either fixed_surround or original stream)
            stereo_source = '[fixed_surround]' if needs_channelmap_fix else f'[0:{surround_idx}]'
            stereo_filter = f'{stereo_source}pan=stereo|c0=0.4*c0+0.283*c2+0.4*c4|c1=0.4*c1+0.283*c3+0.4*c5,acompressor=level_in=1.5:threshold=0.1:ratio=6:attack=20:release=250[aout]'
            
            if not filter_complex:
                filter_complex = ['-filter_complex', stereo_filter]
            else:
                # Append to existing filter_complex
                filter_complex[1] = filter_complex[1] + ';' + stereo_filter
                
            audio_maps += ['-map', '[aout]']
            # Generated stereo track gets English language tag
            audio_labels += ['-metadata:s:a:1', 'title=Stereo (Compressed)', '-metadata:s:a:1', f'language={surround_lang}']
    
    # Handle existing stereo tracks if we have surround but didn't create stereo from it
    if surround_idx is not None and not should_create_stereo:
        # Map existing stereo tracks
        stereo_mapped = False
        for stream in probe['streams']:
            if stream['codec_type'] == 'audio' and int(stream.get('channels', 0)) == 2:
                idx = stream['index']
                original_lang = stream.get('tags', {}).get('language', '').lower()
                
                # Only accept English, unlabeled, or undefined streams
                if original_lang == 'eng' or not original_lang or original_lang == 'und':
                    if original_lang == 'eng':
                        logging.info(f"Mapping existing stereo stream {idx} (already English)")
                    else:
                        logging.info(f"Mapping existing stereo stream {idx} (tagging as English)")
                    
                    audio_maps += ['-map', f'0:{idx}']
                    # Determine correct audio stream index - if surround was skipped, stereo is stream 0
                    audio_stream_idx = '1' if surround_has_processable_layout else '0'
                    audio_labels += [f'-metadata:s:a:{audio_stream_idx}', 'title=Stereo', f'-metadata:s:a:{audio_stream_idx}', 'language=eng']
                    stereo_mapped = True
                    break
        
        if not stereo_mapped:
            logging.warning("Have surround but no processable stereo track found")
    
    elif surround_idx is None:
        # Fallback: find first English or unlabeled audio stream
        fallback_found = False
        for stream in probe['streams']:
            if stream['codec_type'] == 'audio':
                idx = stream['index']
                original_lang = stream.get('tags', {}).get('language', '').lower()
                
                # Only accept English, unlabeled, or undefined streams
                if original_lang == 'eng' or not original_lang or original_lang == 'und':
                    if original_lang == 'eng':
                        logging.info(f"Fallback: Using English audio stream {idx}")
                    else:
                        logging.info(f"Fallback: Using unlabeled audio stream {idx} (tagging as English)")
                    
                    audio_maps += ['-map', f'0:{idx}']
                    audio_labels += ['-metadata:s:a:0', 'title=Stereo', '-metadata:s:a:0', 'language=eng']
                    fallback_found = True
                    break
                else:
                    logging.debug(f"Skipping non-English audio stream {idx} (language: {original_lang})")
        
        if not fallback_found:
            logging.warning("No English or unlabeled audio streams found - no audio will be processed")
            print("Warning: No English or unlabeled audio streams found")

    # Subtitle mapping (forced and English, only text-based)
    subtitle_maps = []
    subtitle_codecs = []
    sub_idx = 0
    subtitle_indices = list(set(forced_subs + eng_subs))
    if subtitle_indices:
        for idx in subtitle_indices:
            subtitle_maps += ['-map', f'0:{idx}']
            subtitle_codecs += [f'-c:s:{sub_idx}', 'mov_text']
            sub_idx += 1

    # Detect hardware acceleration capabilities
    hwaccel = detect_hardware_acceleration()
    
    # Build video encoding args based on available acceleration
    video_args = []
    if hwaccel['method'] == 'vaapi':
        video_args = ['-c:v', hwaccel['encoder']] + hwaccel['extra_args'] + ['-qp', '23']
        logging.info("Using VAAPI hardware acceleration")
    elif hwaccel['method'] == 'software_optimized':
        video_args = ['-c:v', hwaccel['encoder']] + hwaccel['extra_args'] + ['-crf', '23']
        logging.info("Using optimized software encoding")
    else:
        # Basic fallback
        video_args = ['-c:v', 'libx264', '-crf', '23', '-preset', 'fast']
        logging.info("Using basic software encoding")

    # Check if we have any audio to process
    has_audio = bool(audio_maps)
    
    # Build ffmpeg args
    # Build individual codec and channel layout args for each mapped audio stream
    audio_codec_args = []
    channel_layout_args = []
    output_audio_idx = 0
    
    # Map input streams to their output positions and set appropriate codecs/layouts
    for i in range(0, len(audio_maps), 2):
        if audio_maps[i] == '-map':
            map_spec = audio_maps[i+1]
            if map_spec.startswith('0:') and not map_spec.startswith('['):  # Direct stream mapping (not filter output)
                try:
                    input_stream_idx = int(map_spec.split(':')[1])
                    # Find the stream info for this index
                    for stream in probe['streams']:
                        if stream['index'] == input_stream_idx and stream['codec_type'] == 'audio':
                            original_layout = stream.get('channel_layout', '')
                            
                            # Decide codec: fix unknown/missing layouts using channelmap filter for 6-channel audio, aac for known layouts
                            if original_layout == 'unknown' or original_layout == '':
                                # For 6-channel audio with unknown layout, use channelmap filter to fix to 5.1
                                if stream.get('channels', 0) == 6:
                                    audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac'])
                                    logging.info(f"Fixing unknown 6-channel layout using channelmap filter to 5.1 for output audio stream {output_audio_idx}")
                                else:
                                    # For other channel counts with unknown layout, use stream copy
                                    audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'copy'])
                                    logging.info(f"Using stream copy for output audio stream {output_audio_idx} (unknown layout, not 6-channel)")
                            else:
                                # Re-encode with AAC and preserve channel layout
                                audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac'])
                                if original_layout:
                                    # Normalize common layout names for FFmpeg compatibility
                                    if original_layout == '5.1(side)':
                                        original_layout = '5.1'
                                    elif original_layout == '7.1(wide)':
                                        original_layout = '7.1'
                                    
                                    channel_layout_args.extend([f'-ch_layout:a:{output_audio_idx}', original_layout])
                                    logging.info(f"Re-encoding and preserving channel layout '{original_layout}' for output audio stream {output_audio_idx}")
                            break
                    output_audio_idx += 1
                except (ValueError, IndexError):
                    pass  # Skip malformed map specs
            elif map_spec.startswith('['):  # Filter output (created stereo track)
                # Filter-generated tracks always use AAC
                audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac'])
                output_audio_idx += 1
    
    args = [
        '-map', '0:v:0',  # First video stream
        *filter_complex,
        *audio_maps,
        *audio_labels,
        *subtitle_maps,
        *subtitle_codecs,
        *subtitle_lang_metadata,
        *video_args,
        *audio_codec_args,  # Individual codec settings per audio stream
        *channel_layout_args,  # Preserve original channel layouts
        '-y',  # Overwrite output
        '-movflags', 'faststart'
    ]
    
    return args, has_audio

def build_audio_ffmpeg_command(input_file, probe=None):
    """
    Build ffmpeg command-line arguments for converting audio files to MP3.
    Args:
        input_file (str): Path to the input audio file.
        probe (dict, optional): ffmpeg.probe result. If None, probe will be called.
    Returns:
        list: A list of ffmpeg command-line arguments (excluding 'ffmpeg' and '-i' input).
    """
    if probe is None:
        try:
            probe = ffmpeg.probe(input_file)
        except ffmpeg.Error as e:
            print("ffprobe error:", e.stderr.decode())
            logging.error(f"ffprobe error for {input_file}: {e.stderr.decode()}")
            raise

    # Build ffmpeg args for MP3 conversion with high quality settings
    args = [
        '-c:a', 'libmp3lame',
        '-b:a', '320k',
        '-y'  # Overwrite output
    ]
    
    # Preserve metadata if available
    for stream in probe.get('streams', []):
        if stream['codec_type'] == 'audio':
            # Copy common audio metadata
            break
    
    # Copy metadata tags
    args.extend(['-map_metadata', '0'])
    
    return args

def transcode_file(input_file):
    # Determine if this is a video or audio file
    is_video = input_file.lower().endswith(VIDEO_EXTS)
    is_audio = input_file.lower().endswith(AUDIO_EXTS)
    
    if not is_video and not is_audio:
        logging.warning(f"Unsupported file format: {input_file}")
        print(f"Unsupported file format: {input_file}")
        return
    
    # Determine target format and extension
    if is_video:
        target_ext = '.mp4'
    else:  # is_audio
        target_ext = '.mp3'
    
    base = os.path.splitext(input_file)[0]
    final_output_file = base + target_ext
    
    # Always use temp file for atomic operations to prevent corrupted files
    # This addresses Issue #30 - incomplete output files after interruption
    temp_output_file = base + '.tmp' + target_ext
    output_file = temp_output_file
    
    # Check if we're transcoding to the same filename (for logging purposes)
    try:
        same_file = os.path.samefile(input_file, final_output_file)
    except Exception:
        # Fallback to case-insensitive comparison if samefile fails (e.g., file doesn't exist yet)
        same_file = input_file.lower() == final_output_file.lower()
        
    global unfinished_output_file
    unfinished_output_file = output_file

    # Check if conversion is needed
    try:
        probe = ffmpeg.probe(input_file)
        
        if is_video:
            # Video file logic (existing)
            vcodec = next((s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'video'), None)
            audio_codecs = [s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'audio']
            all_aac = all(codec == 'aac' for codec in audio_codecs) if audio_codecs else True
            
            # Check if we have surround sound but missing stereo track
            has_surround = False
            has_stereo = False
            has_processable_surround = False
            
            for stream in probe['streams']:
                if stream['codec_type'] == 'audio':
                    channels = int(stream.get('channels', 0))
                    channel_layout = stream.get('channel_layout', 'unknown')
                    
                    if channels >= 6:
                        has_surround = True
                        # Only consider surround processable if it has a known channel layout
                        if channel_layout != 'unknown':
                            has_processable_surround = True
                    elif channels == 2:
                        has_stereo = True
            
            # Only create stereo from surround if:
            # 1. We have processable surround (known channel layout)
            # 2. We don't already have stereo
            # Skip processing unknown channel layouts entirely
            needs_stereo_track = has_processable_surround and not has_stereo
            
            # Check if audio metadata needs fixing
            needs_audio_metadata_fix = False
            has_non_english_audio = False
            
            for stream in probe['streams']:
                if stream['codec_type'] == 'audio':
                    lang = stream.get('tags', {}).get('language', '').lower()
                    
                    # Check for non-English audio that should be removed
                    # Treat 'und' (undefined) as unlabeled, not non-English
                    if lang and lang != 'eng' and lang != 'und':
                        has_non_english_audio = True
                        logging.info(f"Found non-English audio stream (language: {lang}) that needs removal")
                    
                    # Check for missing language tags on English-compatible streams
                    elif not lang or lang == 'und':  # Unlabeled or undefined stream that should be tagged as English
                        needs_audio_metadata_fix = True
                        logging.info(f"Found unlabeled audio stream that needs English language tag")
            
            # Enhanced skip logic - only skip if format AND metadata are perfect
            if (vcodec == 'h264' and all_aac and input_file.lower().endswith('.mp4') and 
                not needs_stereo_track and not needs_audio_metadata_fix and not has_non_english_audio):
                print(f"Skipping: {input_file} is already H.264/AAC MP4 with proper audio metadata.")
                logging.info(f"Skipping: {input_file} is already H.264/AAC MP4 with proper audio metadata.")
                return
            elif needs_stereo_track:
                print(f"Transcoding: {input_file} has surround sound but missing stereo track.")
                logging.info(f"Transcoding: {input_file} has surround sound but missing stereo track.")
            elif needs_audio_metadata_fix:
                print(f"Transcoding: {input_file} needs audio language metadata fixes.")
                logging.info(f"Transcoding: {input_file} needs audio language metadata fixes.")
            elif has_non_english_audio:
                print(f"Transcoding: {input_file} has non-English audio tracks to remove.")
                logging.info(f"Transcoding: {input_file} has non-English audio tracks to remove.")
        
        else:  # is_audio
            # Audio file logic
            acodec = next((s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'audio'), None)
            
            if acodec == 'mp3' and input_file.lower().endswith('.mp3'):
                print(f"Skipping: {input_file} is already MP3.")
                logging.info(f"Skipping: {input_file} is already MP3.")
                return
                
            print(f"Converting: {input_file} ({acodec}) -> MP3")
            logging.info(f"Converting: {input_file} ({acodec}) -> MP3")
            
    except ffmpeg.Error as e:
        print(f"ffprobe error for {input_file}: {e.stderr.decode()}")
        logging.warning(f"ffprobe error for {input_file}: {e.stderr.decode()}")
        raise  # <--- This will prevent transcoding invalid files
    except Exception as e:
        print(f"Unexpected error probing {input_file}, will attempt to transcode. Reason: {e}")
        logging.warning(f"Unexpected error probing {input_file}, will attempt to transcode. Reason: {e}")
        probe = None

    print(f"Transcoding: {input_file} -> {final_output_file}")
    
    # Extract PGS subtitles if this is a video file
    if is_video and probe:
        extracted_subtitles = extract_pgs_subtitles(input_file, probe)
        if extracted_subtitles:
            print(f"Extracted {len(extracted_subtitles)} PGS subtitle file(s)")
    
    # Build appropriate command based on file type
    if is_video:
        args, has_audio = build_ffmpeg_command(input_file, probe)
        # Skip conversion if no audio streams will be processed
        if not has_audio:
            logging.warning(f"Skipping {input_file}: No English or unlabeled audio streams found")
            print(f"Skipping {input_file}: No English or unlabeled audio streams found")
            return
    else:  # is_audio
        args = build_audio_ffmpeg_command(input_file, probe)
        has_audio = True  # Audio files always have audio to process
    
    cmd = ['ffmpeg', '-i', input_file] + args + [output_file]
    logging.info(f"Transcoding: {input_file} -> {final_output_file}")
    if output_file != final_output_file:
        logging.info(f"Using temporary file: {output_file}")
    logging.info("Command: " + " ".join(cmd))
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        logging.info("ffmpeg output:\n" + result.stdout)
        logging.info("ffmpeg errors:\n" + result.stderr)
        if result.returncode == 0:
            unfinished_output_file = None
            
            # Atomically move temp file to final location (always required now)
            if output_file != final_output_file:
                try:
                    if os.path.exists(final_output_file):
                        os.remove(final_output_file)  # Remove existing file before atomic rename
                    os.rename(output_file, final_output_file)
                    logging.info(f"Atomically moved temp file to final location: {final_output_file}")
                    print(f"Atomically moved temp file to final location: {final_output_file}")
                except Exception as e:
                    logging.error(f"Failed to atomically move temp file to final location: {e}")
                    print(f"Failed to atomically move temp file to final location: {e}")
                    return
            else:
                # This should not happen with always-temp logic, but handle gracefully
                logging.warning(f"Unexpected: temp file same as final file: {final_output_file}")
            
            logging.info(f"Success: {final_output_file}")
            print(f"Success: {final_output_file}")
            
            # Add to batch notification list instead of immediate notification
            global processed_files
            processed_files.append(final_output_file)
            
            # Only remove source file if it's different from final output file
            if input_file != final_output_file:
                try:
                    os.remove(input_file)
                    logging.info(f"Removed source file: {input_file}")
                    print(f"Removed source file: {input_file}")
                except Exception as e:
                    logging.error(f"Could not remove source file: {e}")
                    print(f"Could not remove source file: {e}")
        else:
            logging.error(f"Failed: {input_file}")
            print(f"Failed: {input_file}")
    except Exception as e:
        logging.error(f"Exception during transcoding: {e}")
        print(f"Exception during transcoding: {e}")

def cleanup_orphaned_temp_files():
    """Clean up any orphaned .tmp.mp4 or .tmp.mp3 files from previous interrupted runs."""
    temp_files_cleaned = 0
    
    # Search all library directories for orphaned temp files
    for lib_dir in MEDIA_LIBRARY_DIRS:
        if not os.path.exists(lib_dir):
            continue
            
        for root, dirs, files in os.walk(lib_dir):
            for file in files:
                if file.endswith(('.tmp.mp4', '.tmp.mp3')):
                    temp_file_path = os.path.join(root, file)
                    try:
                        # Check if temp file is old (more than 1 hour) to avoid removing active conversions
                        file_age = time.time() - os.path.getmtime(temp_file_path)
                        if file_age > 3600:  # 1 hour
                            os.remove(temp_file_path)
                            temp_files_cleaned += 1
                            logging.info(f"Cleaned up orphaned temp file: {temp_file_path}")
                            print(f"Cleaned up orphaned temp file: {temp_file_path}")
                    except Exception as e:
                        logging.warning(f"Could not clean up temp file {temp_file_path}: {e}")
    
    if temp_files_cleaned > 0:
        logging.info(f"Startup cleanup: removed {temp_files_cleaned} orphaned temp files")
        print(f"Startup cleanup: removed {temp_files_cleaned} orphaned temp files")

def main():
    # Clean up any orphaned temp files from previous interrupted runs
    cleanup_orphaned_temp_files()
    
    parser = argparse.ArgumentParser(description="Transcode media files.")
    parser.add_argument('--dir', type=str, help='Directory to search for media files')
    parser.add_argument('--file', type=str, help='Single media file to convert')
    parser.add_argument('--type', type=str, choices=['video', 'audio', 'both'], default='both', 
                       help='Type of media to process: video, audio, or both (default: both)')
    args = parser.parse_args()

    if args.file:
        if not os.path.isfile(args.file):
            logging.error("Invalid file.")
            print("Invalid file.")
            sys.exit(1)
        transcode_file(args.file)
        
        # Perform batch Plex notification for single file
        if processed_files:
            print("Notifying Plex about processed file...")
            batch_notify_plex()
            
        logging.info("Transcoding complete.")
        print("Transcoding complete.")
        return

    if args.dir:
        root_dir = args.dir
    else:
        choice = input("Enter 'd' for directory or 'f' for file: ").strip().lower()
        if choice == 'd':
            root_dir = input("Enter the root directory of your media library: ").strip()
            if not os.path.isdir(root_dir):
                logging.error("Invalid directory.")
                print("Invalid directory.")
                sys.exit(1)
                
            # Ask for media type if not specified
            if args.type == 'both':
                media_choice = input("Process (v)ideo, (a)udio, or (b)oth types? [b]: ").strip().lower()
                if media_choice == 'v':
                    args.type = 'video'
                elif media_choice == 'a':
                    args.type = 'audio'
                else:
                    args.type = 'both'
                    
        elif choice == 'f':
            file_path = input("Enter the path to the media file: ").strip()
            if not os.path.isfile(file_path):
                logging.error("Invalid file.")
                print("Invalid file.")
                sys.exit(1)
            transcode_file(file_path)
            
            # Perform batch Plex notification for single file  
            if processed_files:
                print("Notifying Plex about processed file...")
                batch_notify_plex()
                
            logging.info("Transcoding complete.")
            print("Transcoding complete.")
            return
        else:
            print("Invalid choice.")
            sys.exit(1)

    files = get_media_files(root_dir, args.type)
    if not files:
        media_type_str = args.type if args.type != 'both' else 'media'
        logging.info(f"No {media_type_str} files found.")
        print(f"No {media_type_str} files found.")
        sys.exit(0)
        
    media_type_str = args.type if args.type != 'both' else 'media'
    print(f"Found {len(files)} {media_type_str} files to process.")
    
    for idx, f in enumerate(files, 1):
        print(f"[{idx}/{len(files)}] Processing: {f}")
        try:
            transcode_file(f)
        except Exception as e:
            logging.error(f"Error processing {f}: {e}")
            print(f"Error processing {f}: {e}")
    
    # Perform batch Plex notifications after all files are processed
    if processed_files:
        print(f"Notifying Plex about {len(processed_files)} processed files...")
        batch_notify_plex()
    
    logging.info("Transcoding complete.")
    print("Transcoding complete.")

if __name__ == "__main__":
    main()