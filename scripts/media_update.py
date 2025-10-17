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

# Downgrade 4K videos to 1080p with automatic filename updating
python3 media_update.py --file "/path/to/Movie.4K.mkv" --downgrade-resolution

# Audio-only conversion
python3 media_update.py --dir "/music/folder" --type audio

# Force enhanced stereo creation (boosted dialogue)
python3 media_update.py --file "/path/to/movie.mkv" --force-stereo

# Downgrade 4K/higher resolution to 1080p maximum
python3 media_update.py --file "/path/to/4k-movie.mkv" --downgrade-resolution

# Combine options
python3 media_update.py --dir "/path/to/media" --force-stereo --downgrade-resolution

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
• PLEX_FORCE_THOROUGH_REFRESH=true/false - Force thorough metadata refresh for multi-audio files (default: true)

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

# Import media database for caching
try:
    from media_database import MediaDatabase
    DATABASE_AVAILABLE = True
except ImportError:
    DATABASE_AVAILABLE = False
    print("Warning: media_database not available. Caching disabled.")

# Import file locking for distributed processing
try:
    from file_lock import FileLock
    FILELOCK_AVAILABLE = True
except ImportError:
    FILELOCK_AVAILABLE = False
    print("Warning: file_lock not available. Distributed processing may have conflicts.")

def load_env_file():
    """Load environment variables from .env file if it exists."""
    # Use env_file path from config if available, otherwise fall back to default
    try:
        env_file = config.get("env_file", os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env'))
    except NameError:
        # Fallback if config not loaded yet
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
VIDEO_EXTS = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.m2ts')
AUDIO_EXTS = ('.flac', '.wav', '.aiff', '.ape', '.wv', '.m4a', '.ogg', '.opus', '.wma')

# AAC Quality Settings
AAC_QUALITY_VBR = '2'  # Variable bitrate quality (1=highest, 5=lowest)
AAC_BITRATE_CBR = '192k'  # Constant bitrate fallback

# Audio Filter Settings (included in track names for version tracking)
CENTER_BOOST = '0.5'  # Center channel boost level
FRONT_MIX = '0.35'    # Front channel mix level  
SURROUND_MIX = '0.25' # Surround channel mix level
COMPRESSOR_RATIO = '6'      # Dynamic range compression ratio
COMPRESSOR_THRESHOLD = '0.1' # Compression threshold
COMPRESSOR_ATTACK = '20'     # Attack time
COMPRESSOR_RELEASE = '250'   # Release time

# Track Title Templates with Filter Settings
ENHANCED_STEREO_TITLE = f'English Stereo (C{CENTER_BOOST}-R{COMPRESSOR_RATIO}-AAC-VBR{AAC_QUALITY_VBR})'
FORCE_STEREO_TITLE = f'English Stereo (Dialogue-C{CENTER_BOOST}-R{COMPRESSOR_RATIO}-AAC-VBR{AAC_QUALITY_VBR})'
STANDARD_STEREO_TITLE = f'English Stereo (AAC-CBR{AAC_BITRATE_CBR})'

# Resolution indicators that should be replaced in filenames
RESOLUTION_PATTERNS = [
    # 4K/UHD patterns
    (r'\b(4K|UHD|2160p?)\b', '1080p'),
    # 1440p patterns  
    (r'\b1440p?\b', '1080p'),
    # Other high resolution patterns
    (r'\b(1800p?|1620p?|1200p?)\b', '1080p'),
    # Handle cases where resolution might be at end before file extension
    (r'\.(4K|UHD|2160p?)\.(mkv|mp4|avi)', r'.1080p.\2'),
]

# Subtitle and supporting file extensions
SUPPORTING_FILE_EXTENSIONS = ['.srt', '.vtt', '.ass', '.ssa', '.sub', '.idx', '.sup', '.txt', '.nfo']

def detect_hdr_video(probe):
    """
    Detect if video stream contains HDR content (HDR10, HDR10+, Dolby Vision, HLG).
    
    Args:
        probe (dict): ffmpeg.probe() result dictionary
        
    Returns:
        dict: HDR information with keys:
            - is_hdr (bool): True if HDR content detected
            - hdr_type (str): Type of HDR (HDR10, HDR10+, Dolby Vision, HLG, or None)
            - color_transfer (str): Transfer characteristic (smpte2084, arib-std-b67, etc.)
            - color_primaries (str): Color primaries (bt2020, bt709, etc.)
            - color_space (str): Color space (bt2020nc, bt709, etc.)
            - pix_fmt (str): Pixel format (yuv420p10le, yuv420p, etc.)
            - bit_depth (int): Bit depth (8, 10, 12)
    """
    hdr_info = {
        'is_hdr': False,
        'hdr_type': None,
        'color_transfer': None,
        'color_primaries': None,
        'color_space': None,
        'pix_fmt': None,
        'bit_depth': 8
    }
    
    try:
        # Find video stream
        video_stream = next((s for s in probe['streams'] if s['codec_type'] == 'video'), None)
        if not video_stream:
            return hdr_info
        
        # Extract color information
        color_transfer = video_stream.get('color_transfer', '')
        color_primaries = video_stream.get('color_primaries', '')
        color_space = video_stream.get('color_space', '')
        pix_fmt = video_stream.get('pix_fmt', '')
        
        # Store values
        hdr_info['color_transfer'] = color_transfer
        hdr_info['color_primaries'] = color_primaries
        hdr_info['color_space'] = color_space
        hdr_info['pix_fmt'] = pix_fmt
        
        # Determine bit depth from pixel format
        if '10le' in pix_fmt or '10be' in pix_fmt or 'p10' in pix_fmt:
            hdr_info['bit_depth'] = 10
        elif '12le' in pix_fmt or '12be' in pix_fmt or 'p12' in pix_fmt:
            hdr_info['bit_depth'] = 12
        else:
            hdr_info['bit_depth'] = 8
        
        # Detect HDR types
        if color_transfer == 'smpte2084':
            # PQ transfer function = HDR10/HDR10+
            hdr_info['is_hdr'] = True
            hdr_info['hdr_type'] = 'HDR10'
            # Check for HDR10+ dynamic metadata (would need side_data_list analysis)
            logging.info(f"HDR10 content detected (PQ/SMPTE ST 2084 transfer)")
        elif color_transfer == 'arib-std-b67':
            # HLG transfer function
            hdr_info['is_hdr'] = True
            hdr_info['hdr_type'] = 'HLG'
            logging.info(f"HLG (Hybrid Log-Gamma) HDR content detected")
        elif color_primaries == 'bt2020' and hdr_info['bit_depth'] > 8:
            # BT.2020 color primaries with 10/12-bit = likely HDR even without explicit transfer
            hdr_info['is_hdr'] = True
            hdr_info['hdr_type'] = 'HDR (BT.2020)'
            logging.info(f"HDR content detected (BT.2020 color primaries, {hdr_info['bit_depth']}-bit)")
        
        # Check for Dolby Vision (look for side_data or codec-specific markers)
        if 'side_data_list' in video_stream:
            for side_data in video_stream['side_data_list']:
                if side_data.get('side_data_type') == 'DOVI configuration record':
                    hdr_info['is_hdr'] = True
                    hdr_info['hdr_type'] = 'Dolby Vision'
                    logging.info(f"Dolby Vision HDR content detected")
                    break
        
        return hdr_info
        
    except Exception as e:
        logging.warning(f"Error detecting HDR: {e}")
        return hdr_info

def build_hdr_tonemap_filter(hdr_info, scale_filter=None):
    """
    Build FFmpeg filter for HDR to SDR tone mapping.
    
    Args:
        hdr_info (dict): HDR information from detect_hdr_video()
        scale_filter (str, optional): Existing scale filter (e.g., 'scale=1920:-2')
        
    Returns:
        str: FFmpeg video filter string for tone mapping, or None if no tone mapping needed
    """
    if not hdr_info['is_hdr']:
        return scale_filter  # Return existing scale filter if provided, otherwise None
    
    # Build tone mapping filter using zscale
    # zscale handles color space conversion better than scale for HDR
    tonemap_filters = []
    
    # Step 1: Convert to linear light (required for tone mapping)
    tonemap_filters.append('zscale=t=linear:npl=100')
    
    # Step 2: Apply tone mapping to compress HDR range to SDR
    # Use Hable (filmic) tone mapping for natural results
    tonemap_filters.append('format=gbrpf32le')
    tonemap_filters.append('zscale=p=bt709')
    tonemap_filters.append('tonemap=tonemap=hable:desat=0')
    
    # Step 3: Convert to SDR color space (BT.709)
    tonemap_filters.append('zscale=t=bt709:m=bt709:r=tv')
    
    # Step 4: Convert to 8-bit YUV 4:2:0 for compatibility
    tonemap_filters.append('format=yuv420p')
    
    # Step 5: Add scaling if requested
    if scale_filter:
        tonemap_filters.append(scale_filter.replace('scale=', 'scale=w=').replace(':', ':h='))
    
    filter_string = ','.join(tonemap_filters)
    logging.info(f"Built HDR→SDR tone mapping filter for {hdr_info['hdr_type']}")
    logging.debug(f"Tone mapping filter: {filter_string}")
    
    return filter_string

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
    # Handle both container and host path mappings
    
    # Host path mappings (when running on host system)
    if container_path.startswith('/Storage/media/tv/'):
        plex_path = container_path.replace('/Storage/media/tv/', '/data/tv/', 1)
        logging.debug(f"Host to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/Storage/media/movies/'):
        plex_path = container_path.replace('/Storage/media/movies/', '/data/movies/', 1)
        logging.debug(f"Host to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/Storage/media/music/'):
        plex_path = container_path.replace('/Storage/media/music/', '/data/music/', 1)
        logging.debug(f"Host to Plex path: {container_path} → {plex_path}")
        return plex_path
    
    # Container-to-container path mapping (when running in containers)
    elif container_path.startswith('/tv/'):
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
        logging.debug(f"No path mapping needed for: {container_path}")
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

def notify_plex_library_update(file_path, max_retries=2, retry_delay=5, force_refresh=False):
    """Enhanced Plex notification with smart scanning, validation, and thorough refresh support.
    
    Args:
        file_path: Path to the media file
        max_retries: Number of retry attempts
        retry_delay: Delay between retries
        force_refresh: If True, forces thorough metadata refresh for audio stream changes
    """
    
    # Configuration loading
    plex_url = os.getenv('PLEX_URL', 'http://192.168.86.2:32400')
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
            
            # Enhanced scanning logic with thorough refresh support
            if force_refresh:
                logging.info(f"🔄 Force refresh enabled - performing thorough metadata refresh")
                try:
                    file_dir = os.path.dirname(plex_file_path)
                    filename_without_ext = os.path.splitext(os.path.basename(plex_file_path))[0]
                    
                    # Enhanced search logic for different media types
                    media_item = None
                    
                    if expected_library_type == 'show':
                        # For TV shows, try multiple search strategies
                        # 1. Search by show name (extract from path or filename)
                        show_name = None
                        path_parts = plex_file_path.split('/')
                        for part in path_parts:
                            if part and not part.startswith('Season'):
                                show_name = part
                                break
                        
                        if show_name:
                            logging.info(f"🔍 Searching for TV show: {show_name}")
                            show_results = matched_section.search(show_name)
                            if show_results:
                                show = show_results[0]
                                logging.info(f"📺 Found show: {show.title}")
                                
                                # Search for specific episode within the show
                                try:
                                    # Extract season/episode info from filename
                                    import re
                                    episode_match = re.search(r'S(\d+)E(\d+)', filename_without_ext, re.IGNORECASE)
                                    if episode_match:
                                        season_num = int(episode_match.group(1))
                                        episode_num = int(episode_match.group(2))
                                        
                                        # Try to find the specific episode
                                        for season in show.seasons():
                                            if season.seasonNumber == season_num:
                                                for episode in season.episodes():
                                                    if episode.episodeNumber == episode_num:
                                                        media_item = episode
                                                        logging.info(f"🎯 Found specific episode: {episode.title}")
                                                        break
                                                break
                                except Exception as e:
                                    logging.debug(f"Episode search failed: {e}")
                                
                                # If episode not found, refresh the show
                                if not media_item:
                                    media_item = show
                                    logging.info(f"📺 Using show for refresh: {show.title}")
                    else:
                        # For movies and other media, use filename search
                        search_results = matched_section.search(filename_without_ext)
                        if search_results:
                            media_item = search_results[0]
                            logging.info(f"🎯 Found specific media item: {media_item.title}")
                    
                    # Perform thorough refresh if item found
                    if media_item:
                        # Multiple refresh approaches for maximum effectiveness
                        media_item.refresh()
                        logging.info(f"🔄 Triggered metadata refresh for: {media_item.title}")
                        
                        # For TV shows, also refresh at show level if we found an episode
                        if expected_library_type == 'show' and hasattr(media_item, 'show'):
                            media_item.show().refresh()
                            logging.info(f"📺 Also refreshed show: {media_item.show().title}")
                    
                    # Always perform directory update as additional measure
                    matched_section.update(path=file_dir)
                    logging.info(f"📁 Updated directory: {file_dir}")
                    
                    # Brief delay to allow Plex to process the update
                    import time
                    time.sleep(2)
                    
                    # For maximum effectiveness, also trigger section refresh
                    matched_section.refresh()
                    logging.info(f"📚 Triggered section refresh for: {matched_section.title}")
                        
                except Exception as refresh_error:
                    logging.warning(f"⚠️ Enhanced refresh failed: {refresh_error}")
                    logging.info(f"🔄 Falling back to aggressive directory refresh")
                    file_dir = os.path.dirname(plex_file_path)
                    matched_section.update(path=file_dir)
                    matched_section.refresh()
                    logging.info(f"📚 Performed fallback section refresh")
                    
            elif smart_scanning:
                file_dir = os.path.dirname(plex_file_path)
                logging.info(f"🎯 Smart scanning directory: {file_dir}")
                matched_section.update(path=file_dir)
            else:
                logging.info(f"📚 Full library scan: {matched_section.title}")
                matched_section.update()
            
            refresh_type = "thorough refresh" if force_refresh else ("smart scan" if smart_scanning else "full scan")
            logging.info(f"✅ Successfully triggered Plex {refresh_type} for {matched_section.title} ({matched_section.type})")
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

def should_force_refresh_for_section(files):
    """
    Determine if files in a section likely need thorough Plex refresh.
    This checks for indicators that multi-channel audio processing occurred.
    
    Args:
        files: List of processed file paths
        
    Returns:
        bool: True if thorough refresh should be forced
    """
    import subprocess
    
    for file_path in files[:3]:  # Check up to 3 files to avoid excessive probing
        try:
            # Quick probe to check for multiple audio streams
            result = subprocess.run([
                'ffprobe', '-v', 'quiet', '-select_streams', 'a', 
                '-show_entries', 'stream=channels', '-of', 'csv=p=0',
                file_path
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                audio_channels = result.stdout.strip().split('\n')
                # If we have multiple audio streams or channels suggesting 5.1 + stereo
                if len(audio_channels) >= 2:
                    channel_counts = [int(ch) for ch in audio_channels if ch.isdigit()]
                    # Look for pattern of surround (5.1 = 6ch) + stereo (2ch)
                    if len(channel_counts) >= 2 and (6 in channel_counts or 8 in channel_counts):
                        logging.info(f"🔄 Detected multi-channel setup in {os.path.basename(file_path)} - forcing thorough refresh")
                        return True
                        
        except Exception as e:
            logging.debug(f"Could not probe {file_path} for audio streams: {e}")
            continue
    
    return False

def batch_notify_plex():
    """
    Perform batch Plex notifications for all processed files with smart refresh detection.
    This reduces the number of individual scan requests to Plex while ensuring
    thorough refreshes for files with multiple audio streams.
    
    Returns:
        bool: True if any notifications were successful, False otherwise
    """
    global processed_files
    
    if not processed_files:
        return True
    
    # Check if notifications are enabled
    env_file = config.get("env_file", os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env'))
    enable_notifications = True  # Default to enabled
    force_thorough_refresh = os.getenv('PLEX_FORCE_THOROUGH_REFRESH', 'true').lower() == 'true'
    
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                if line.startswith('ENABLE_PLEX_NOTIFICATIONS='):
                    enable_value = line.split('=', 1)[1].strip().lower()
                    enable_notifications = enable_value in ('true', 'yes', '1', 'on')
                elif line.startswith('PLEX_FORCE_THOROUGH_REFRESH='):
                    refresh_value = line.split('=', 1)[1].strip().lower()
                    force_thorough_refresh = refresh_value in ('true', 'yes', '1', 'on')
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
            
            # Check if any files in this section likely have multiple audio streams
            force_refresh = force_thorough_refresh and should_force_refresh_for_section(files)
            
            if notify_plex_library_update(representative_file, max_retries=1, force_refresh=force_refresh):
                refresh_type = "thorough refresh" if force_refresh else "standard scan"
                logging.info(f"Successfully triggered {section_type} {refresh_type} for {len(files)} files")
                success = True
            else:
                logging.warning(f"Failed to trigger {section_type} library scan for {len(files)} files")
    
    # Clear the processed files list
    processed_files.clear()
    
    return success

def update_filename_resolution(filepath, target_resolution='1080p'):
    """
    Update filename to reflect new resolution, replacing high-resolution indicators.
    
    Args:
        filepath (str): Original file path
        target_resolution (str): Target resolution (default: '1080p')
    
    Returns:
        str: Updated file path with resolution indicator replaced
    """
    import re
    
    # Get directory, filename, and extension
    directory = os.path.dirname(filepath)
    filename = os.path.basename(filepath)
    name, ext = os.path.splitext(filename)
    
    # Apply resolution patterns
    updated_name = name
    for pattern, replacement in RESOLUTION_PATTERNS:
        # Use target_resolution instead of hardcoded replacement if pattern expects it
        if replacement == '1080p':
            replacement = target_resolution
        updated_name = re.sub(pattern, replacement, updated_name, flags=re.IGNORECASE)
    
    # If no pattern matched but we're downgrading, add resolution indicator
    if updated_name == name:  # No changes made
        # Check if we need to add resolution indicator
        # Add it before any quality indicators like WEBDL, BluRay, etc.
        quality_patterns = r'(\b(?:WEBDL|WEB-DL|BluRay|BDRip|DVDRip|HDRip)\b)'
        match = re.search(quality_patterns, updated_name, re.IGNORECASE)
        if match:
            # Insert before quality indicator
            updated_name = updated_name[:match.start()] + target_resolution + ' ' + updated_name[match.start():]
        else:
            # Just append to the end
            updated_name = updated_name + ' ' + target_resolution
    
    # Reconstruct the full path
    new_filename = updated_name + ext
    new_filepath = os.path.join(directory, new_filename)
    
    logging.info(f"Resolution filename update: {filename} -> {new_filename}")
    return new_filepath

def find_and_rename_supporting_files(original_path, new_path):
    """
    Find supporting files (subtitles, etc.) and rename them to match the new video filename.
    
    Args:
        original_path (str): Original video file path
        new_path (str): New video file path
    
    Returns:
        list: List of (old_path, new_path) tuples for renamed files
    """
    renamed_files = []
    
    if not os.path.exists(original_path):
        return renamed_files
    
    # Get base names without extensions
    original_dir = os.path.dirname(original_path)
    original_base = os.path.splitext(os.path.basename(original_path))[0]
    new_base = os.path.splitext(os.path.basename(new_path))[0]
    
    # Only proceed if the base names are actually different
    if original_base == new_base:
        return renamed_files
    
    # Look for supporting files in the same directory
    try:
        for filename in os.listdir(original_dir):
            # Check if this file starts with the original base name
            if filename.startswith(original_base):
                file_path = os.path.join(original_dir, filename)
                
                # Skip the original video file itself
                if file_path == original_path:
                    continue
                
                # Check if it's a supporting file type
                _, ext = os.path.splitext(filename)
                if ext.lower() in SUPPORTING_FILE_EXTENSIONS:
                    # Create new filename
                    suffix = filename[len(original_base):]  # Get everything after the base name
                    new_filename = new_base + suffix
                    new_file_path = os.path.join(original_dir, new_filename)
                    
                    # Rename the file
                    try:
                        os.rename(file_path, new_file_path)
                        renamed_files.append((file_path, new_file_path))
                        logging.info(f"Renamed supporting file: {filename} -> {new_filename}")
                    except OSError as e:
                        logging.warning(f"Could not rename supporting file {file_path}: {e}")
    
    except OSError as e:
        logging.warning(f"Could not list directory {original_dir} for supporting files: {e}")
    
    return renamed_files

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
def build_ffmpeg_command(input_file, probe=None, force_stereo=False, downgrade_resolution=False):
    """
    Build ffmpeg command-line arguments for transcoding the input file.
    Uses GPU acceleration when available, falls back to software encoding.
    Args:
        input_file (str): Path to the input media file.
        probe (dict, optional): ffmpeg.probe result. If None, probe will be called.
        force_stereo (bool): Force creation of enhanced stereo track even if stereo already exists.
        downgrade_resolution (bool): Downgrade video resolution to 1080p maximum if source is higher.
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
    
    # Check if we should process surround audio and create additional tracks
    should_create_stereo = False
    should_create_51_from_71 = False
    surround_has_processable_layout = False
    surround_channels = 0
    
    if surround_idx is not None:
        # Analyze the surround stream to determine what additional tracks to create
        for stream in probe['streams']:
            if stream['index'] == surround_idx and stream['codec_type'] == 'audio':
                channel_layout = stream.get('channel_layout', 'unknown')
                channels = int(stream.get('channels', 0))
                surround_channels = channels
                
                # Check if we have existing stereo and 5.1 tracks
                has_existing_stereo = False
                has_existing_enhanced_stereo = False
                has_existing_51 = False
                for other_stream in probe['streams']:
                    if other_stream['codec_type'] == 'audio' and other_stream['index'] != surround_idx:
                        other_channels = int(other_stream.get('channels', 0))
                        if other_channels == 2:
                            has_existing_stereo = True
                            # Check if this is already an enhanced stereo track with current settings
                            track_title = other_stream.get('tags', {}).get('title', '')
                            current_settings_pattern = f'C{CENTER_BOOST}-R{COMPRESSOR_RATIO}'
                            if current_settings_pattern in track_title or 'Dialogue-' + current_settings_pattern in track_title:
                                has_existing_enhanced_stereo = True
                                logging.info(f"Found existing enhanced stereo track with current settings: '{track_title}'")
                            elif 'English Stereo' in track_title and ('AAC-VBR' in track_title or 'Enhanced' in track_title):
                                logging.info(f"Found enhanced stereo track with different settings: '{track_title}' - will be re-processed")
                        elif other_channels == 6:
                            has_existing_51 = True
                
                if channel_layout != 'unknown':
                    surround_has_processable_layout = True
                    
                    # If we have 7.1 (8 channels) and no existing 5.1, create 5.1 from 7.1
                    if channels == 8 and not has_existing_51:
                        should_create_51_from_71 = True
                        logging.info(f"Will create 5.1 from 7.1 surround stream {surround_idx}")
                    
                    # Create stereo if we don't have existing enhanced stereo OR if forced
                    if not has_existing_enhanced_stereo or force_stereo:
                        should_create_stereo = True
                        if force_stereo and has_existing_enhanced_stereo:
                            logging.info(f"Force creating enhanced stereo from processable surround stream {surround_idx} (existing enhanced stereo will be replaced)")
                        elif has_existing_stereo and not has_existing_enhanced_stereo:
                            logging.info(f"Will create enhanced stereo from processable surround stream {surround_idx} (upgrading basic stereo track)")
                        else:
                            logging.info(f"Will create enhanced stereo from processable surround stream {surround_idx}")
                    else:
                        logging.info(f"Skipping stereo creation - existing enhanced stereo track found")
                        
                elif channel_layout == 'unknown' and channels == 6:
                    # 6-channel unknown layout can be fixed with channelmap filter
                    surround_has_processable_layout = True
                    if not has_existing_enhanced_stereo or force_stereo:
                        should_create_stereo = True
                        if force_stereo and has_existing_enhanced_stereo:
                            logging.info(f"Force creating enhanced stereo from 6-channel unknown layout (fixable with channelmap) stream {surround_idx} (existing enhanced stereo will be replaced)")
                        elif has_existing_stereo and not has_existing_enhanced_stereo:
                            logging.info(f"Will create enhanced stereo from 6-channel unknown layout (fixable with channelmap) stream {surround_idx} (upgrading basic stereo track)")
                        else:
                            logging.info(f"Will create enhanced stereo from 6-channel unknown layout (fixable with channelmap) stream {surround_idx}")
                    else:
                        logging.info(f"Skipping stereo creation - existing enhanced stereo track found")
                elif channel_layout == 'unknown' and channels == 8:
                    # 8-channel unknown layout - could be 7.1, but we can't process unknown layouts safely
                    surround_has_processable_layout = True
                    logging.info(f"8-channel unknown layout detected - will preserve but cannot create additional tracks")
                else:
                    logging.info(f"Skipping additional track creation from surround stream {surround_idx} - unknown channel layout")
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
        
        # Always map the original surround stream to preserve it alongside any created tracks
        map_original_surround = True
        
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
                
            if map_original_surround:
                audio_maps += ['-map', '[fixed_surround]']
                logging.info(f"Mapping surround stream {surround_idx} with channelmap filter to fix unknown 6-channel layout to 5.1")
        else:
            if map_original_surround:
                audio_maps += ['-map', f'0:{surround_idx}']
                if surround_has_processable_layout:
                    logging.info(f"Mapping surround stream {surround_idx} with processable channel layout (will re-encode)")
                else:
                    logging.info(f"Mapping surround stream {surround_idx} with unknown channel layout (will stream copy to preserve quality)")
            # Original surround stream is always preserved alongside any created tracks
        
        # Add metadata for original surround if we're mapping it
        if map_original_surround:
            # Set title based on channel count
            if surround_channels == 8:
                surround_title = '7.1 Surround'
            elif surround_channels == 6:
                surround_title = '5.1 Surround'
            else:
                surround_title = 'Surround'
            audio_labels += ['-metadata:s:a:0', f'title={surround_title}', '-metadata:s:a:0', f'language={surround_lang}']
            next_audio_idx = 1
        else:
            next_audio_idx = 0  # Start from 0 if we're not mapping original surround
        
        # Create 5.1 from 7.1 if needed (done first so stereo can use it)
        surround_source_for_stereo = '[fixed_surround]' if needs_channelmap_fix else f'[0:{surround_idx}]'
        
        if should_create_51_from_71:
            # Create 5.1 from 7.1 by mixing side channels into back channels
            # 7.1 layout: FL, FR, FC, LFE, BL, BR, SL, SR (0,1,2,3,4,5,6,7)
            # 5.1 layout: FL, FR, FC, LFE, BL, BR (0,1,2,3,4,5)
            # Mix: BL = BL + 0.7*SL, BR = BR + 0.7*SR (preserve original center channel balance)
            source_for_51 = '[fixed_surround]' if needs_channelmap_fix else f'[0:{surround_idx}]'
            
            if should_create_stereo:
                # Need to create both 5.1 and stereo - use asplit to duplicate the 5.1 signal
                create_51_filter = f'{source_for_51}pan=5.1|c0=c0|c1=c1|c2=c2|c3=c3|c4=c4+0.7*c6|c5=c5+0.7*c7[surround_51_tmp]; [surround_51_tmp]asplit=2[surround_51][for_stereo]'
                surround_source_for_stereo = '[for_stereo]'
            else:
                # Only creating 5.1, no need for asplit
                create_51_filter = f'{source_for_51}pan=5.1|c0=c0|c1=c1|c2=c2|c3=c3|c4=c4+0.7*c6|c5=c5+0.7*c7[surround_51]'
                surround_source_for_stereo = '[surround_51]'
            
            if not filter_complex:
                filter_complex = ['-filter_complex', create_51_filter]
            else:
                filter_complex[1] = filter_complex[1] + '; ' + create_51_filter
                
            audio_maps += ['-map', '[surround_51]']
            audio_labels += [f'-metadata:s:a:{next_audio_idx}', 'title=5.1 Surround', f'-metadata:s:a:{next_audio_idx}', f'language={surround_lang}']
            next_audio_idx += 1
            
            logging.info(f"Created 5.1 surround track from 7.1, will use for stereo creation")
        
        # Create enhanced stereo from surround if conditions are met
        if should_create_stereo:
            # Enhanced stereo downmix with boosted center channel for better dialogue clarity
            # Original formula: c0=0.4*c0+0.283*c2+0.4*c4|c1=0.4*c1+0.283*c3+0.4*c5
            # Enhanced formula: boost center from 0.283 to 0.5 for better dialogue, reduce surrounds slightly
            # Note: Center channel boost only applied to stereo downmix, not to 5.1 creation
            stereo_filter = f'{surround_source_for_stereo}pan=stereo|c0={FRONT_MIX}*c0+{CENTER_BOOST}*c2+{SURROUND_MIX}*c4|c1={FRONT_MIX}*c1+{CENTER_BOOST}*c2+{SURROUND_MIX}*c5,acompressor=level_in=1.5:threshold={COMPRESSOR_THRESHOLD}:ratio={COMPRESSOR_RATIO}:attack={COMPRESSOR_ATTACK}:release={COMPRESSOR_RELEASE}[aout]'
            
            if surround_channels == 8:
                logging.info(f"Creating enhanced stereo from 7.1/5.1 with boosted center channel ({CENTER_BOOST}) and compression (R{COMPRESSOR_RATIO}) for better dialogue")
            else:  # 5.1 or 6-channel input
                logging.info(f"Creating enhanced stereo from 5.1 with boosted center channel ({CENTER_BOOST}) and compression (R{COMPRESSOR_RATIO}) for better dialogue")
            
            if not filter_complex:
                filter_complex = ['-filter_complex', stereo_filter]
            else:
                # Append to existing filter_complex
                filter_complex[1] = filter_complex[1] + '; ' + stereo_filter
                
            audio_maps += ['-map', '[aout]']
            # Generated stereo track gets English language tag and appropriate title with filter settings
            if force_stereo:
                stereo_title = FORCE_STEREO_TITLE
            else:
                stereo_title = ENHANCED_STEREO_TITLE
            audio_labels += [f'-metadata:s:a:{next_audio_idx}', f'title={stereo_title}', f'-metadata:s:a:{next_audio_idx}', 'language=eng']
    
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
                    # Calculate correct audio stream index based on what we've already mapped
                    current_audio_idx = 0 if not map_original_surround else 1  # Start after surround if mapped
                    if should_create_51_from_71:
                        current_audio_idx += 1  # Account for 5.1 track
                    
                    audio_labels += [f'-metadata:s:a:{current_audio_idx}', f'title={STANDARD_STEREO_TITLE}', f'-metadata:s:a:{current_audio_idx}', 'language=eng']
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
                    audio_labels += ['-metadata:s:a:0', f'title={STANDARD_STEREO_TITLE}', '-metadata:s:a:0', 'language=eng']
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

    # Detect video resolution and determine if scaling is needed
    video_width = 0
    video_height = 0
    needs_scaling = False
    scale_filter = ''
    
    if downgrade_resolution:
        for stream in probe['streams']:
            if stream['codec_type'] == 'video':
                video_width = int(stream.get('width', 0))
                video_height = int(stream.get('height', 0))
                break
        
        # Check if resolution is higher than 1080p
        if video_height > 1080:
            needs_scaling = True
            # Calculate scaling while preserving aspect ratio
            # Scale to 1080p height, let width adjust proportionally
            scale_filter = 'scale=-2:1080'  # -2 ensures width is even number
            logging.info(f"Video resolution {video_width}x{video_height} will be downgraded to 1080p")
        elif video_width > 1920:  # Handle ultra-wide scenarios
            needs_scaling = True
            scale_filter = 'scale=1920:-2'  # Scale width to 1920, adjust height proportionally
            logging.info(f"Video resolution {video_width}x{video_height} will be downgraded to 1920px width")
    
    # Detect HDR content
    hdr_info = detect_hdr_video(probe)
    
    # Build tone mapping filter if HDR detected
    video_filter = None
    if hdr_info['is_hdr']:
        logging.info(f"🎨 HDR content detected: {hdr_info['hdr_type']}")
        logging.info(f"   Color: {hdr_info['color_primaries']}, Transfer: {hdr_info['color_transfer']}, {hdr_info['bit_depth']}-bit")
        
        # Build tone mapping filter (with optional scaling)
        video_filter = build_hdr_tonemap_filter(hdr_info, scale_filter if needs_scaling else None)
        
        # Reset scaling flag since it's now in the tone map filter
        if needs_scaling:
            needs_scaling = False
            scale_filter = None
            
        logging.info(f"✅ HDR→SDR tone mapping will be applied")
    elif needs_scaling:
        # No HDR, but we have scaling
        video_filter = scale_filter
    
    # Detect hardware acceleration capabilities
    hwaccel = detect_hardware_acceleration()
    
    # Build video encoding args based on available acceleration
    # NOTE: HDR tone mapping requires software encoding (zscale filter not compatible with VAAPI)
    video_args = []
    if hdr_info['is_hdr']:
        # Force software encoding for HDR tone mapping (zscale not supported in VAAPI)
        if video_filter:
            video_args = ['-c:v', 'libx264', '-vf', video_filter, '-crf', '23', '-preset', 'medium']
        else:
            video_args = ['-c:v', 'libx264', '-crf', '23', '-preset', 'medium']
        logging.info(f"Using software encoding for HDR tone mapping")
    elif hwaccel['method'] == 'vaapi':
        if needs_scaling:
            # VAAPI scaling - insert scale before hwupload
            vaapi_extra_args = ['-vaapi_device', '/dev/dri/renderD128', '-vf', f'{scale_filter},format=nv12,hwupload']
        else:
            vaapi_extra_args = hwaccel['extra_args']
        video_args = ['-c:v', hwaccel['encoder']] + vaapi_extra_args + ['-qp', '23']
        logging.info(f"Using VAAPI hardware acceleration{' with resolution scaling' if needs_scaling else ''}")
    elif hwaccel['method'] == 'software_optimized':
        if needs_scaling:
            software_extra_args = hwaccel['extra_args'] + ['-vf', scale_filter]
        else:
            software_extra_args = hwaccel['extra_args']
        video_args = ['-c:v', hwaccel['encoder']] + software_extra_args + ['-crf', '23']
        logging.info(f"Using optimized software encoding{' with resolution scaling' if needs_scaling else ''}")
    else:
        # Basic fallback
        if needs_scaling:
            video_args = ['-c:v', 'libx264', '-vf', scale_filter, '-crf', '23', '-preset', 'fast']
        else:
            video_args = ['-c:v', 'libx264', '-crf', '23', '-preset', 'fast']
        logging.info(f"Using basic software encoding{' with resolution scaling' if needs_scaling else ''}")

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
                                    audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac', f'-b:a:{output_audio_idx}', AAC_BITRATE_CBR])
                                    logging.info(f"Fixing unknown 6-channel layout using channelmap filter to 5.1 for output audio stream {output_audio_idx}")
                                else:
                                    # For other channel counts with unknown layout, use stream copy
                                    audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'copy'])
                                    logging.info(f"Using stream copy for output audio stream {output_audio_idx} (unknown layout, not 6-channel)")
                            else:
                                # Re-encode with AAC and preserve channel layout
                                audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac', f'-b:a:{output_audio_idx}', AAC_BITRATE_CBR])
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
            elif map_spec.startswith('['):  # Filter output (created tracks like 5.1 from 7.1, stereo, etc.)
                # Filter-generated tracks always use AAC with quality settings
                if map_spec == '[aout]':  # Enhanced stereo track
                    audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac', f'-q:a:{output_audio_idx}', AAC_QUALITY_VBR])
                else:  # Other generated tracks (5.1 from 7.1)
                    audio_codec_args.extend([f'-c:a:{output_audio_idx}', 'aac', f'-b:a:{output_audio_idx}', AAC_BITRATE_CBR])
                
                # Set appropriate channel layout for filter outputs
                if map_spec == '[surround_51]':
                    channel_layout_args.extend([f'-ch_layout:a:{output_audio_idx}', '5.1'])
                    logging.info(f"Setting 5.1 channel layout for created 5.1 track (output stream {output_audio_idx})")
                elif map_spec == '[aout]':
                    channel_layout_args.extend([f'-ch_layout:a:{output_audio_idx}', 'stereo'])
                    logging.info(f"Setting stereo channel layout for created stereo track (output stream {output_audio_idx})")
                
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

def transcode_file(input_file, force_stereo=False, downgrade_resolution=False):
    # Try to acquire file lock to prevent multiple workers from processing the same file
    file_lock = None
    if FILELOCK_AVAILABLE:
        file_lock = FileLock(input_file, timeout=1800)  # 30 minute timeout
        
        if not file_lock.acquire(wait=False):
            lock_info = file_lock.get_lock_info()
            if lock_info:
                locked_by = lock_info.get('hostname', 'unknown')
                locked_at = lock_info.get('locked_at', 'unknown time')
                logging.info(f"⏭️  Skipping {os.path.basename(input_file)} - locked by {locked_by} at {locked_at}")
                print(f"⏭️  Skipping {os.path.basename(input_file)} - already being processed by {locked_by}")
            else:
                logging.info(f"⏭️  Skipping {os.path.basename(input_file)} - lock exists")
                print(f"⏭️  Skipping {os.path.basename(input_file)} - already being processed")
            return
        
        logging.info(f"🔒 Lock acquired for: {os.path.basename(input_file)}")
    
    try:
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
    
    # Update filename for resolution downgrade if needed
    base = os.path.splitext(input_file)[0]
    if is_video and downgrade_resolution:
        # Check if we actually need to downgrade (will be determined later from probe data)
        potential_new_path = update_filename_resolution(input_file, '1080p')
        potential_base = os.path.splitext(potential_new_path)[0]
        # We'll finalize this decision after we check the actual video resolution
        base_for_resolution_downgrade = potential_base
    else:
        base_for_resolution_downgrade = base
    
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
        # Try to use cached probe data if available
        fingerprint = None
        probe = None
        using_cache = False
        
        if DATABASE_AVAILABLE and hasattr(transcode_file, 'db'):
            fingerprint = transcode_file.db.get_file_fingerprint(input_file)
            if fingerprint and transcode_file.db.has_cached_probe(fingerprint):
                probe = transcode_file.db.get_cached_probe(fingerprint)
                if probe:
                    using_cache = True
                    logging.info(f"Using cached probe data for: {input_file}")
                    print(f"📦 Using cached metadata for: {os.path.basename(input_file)}")
        
        # If no cache, do normal ffmpeg probe
        if probe is None:
            probe = ffmpeg.probe(input_file)
            logging.info(f"Probed file (no cache): {input_file}")
            
            # Store probe in database for future use
            if DATABASE_AVAILABLE and hasattr(transcode_file, 'db') and fingerprint:
                try:
                    # We'll determine action below, store with placeholder for now
                    transcode_file.db.store_probe(fingerprint, probe, action='pending')
                    logging.info(f"📦 Cached probe data for future use")
                except Exception as e:
                    logging.warning(f"Failed to cache probe data: {e}")
        
        if is_video:
            # Video file logic (existing)
            vcodec = next((s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'video'), None)
            audio_codecs = [s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'audio']
            all_aac = all(codec == 'aac' for codec in audio_codecs) if audio_codecs else True
            
            # Check if we have surround sound and what additional tracks might be needed
            has_surround = False
            has_stereo = False
            has_51 = False
            has_71 = False
            has_processable_surround = False
            
            for stream in probe['streams']:
                if stream['codec_type'] == 'audio':
                    channels = int(stream.get('channels', 0))
                    channel_layout = stream.get('channel_layout', 'unknown')
                    
                    if channels == 2:
                        has_stereo = True
                    elif channels == 6:
                        has_surround = True
                        has_51 = True
                        if channel_layout != 'unknown':
                            has_processable_surround = True
                    elif channels == 8:
                        has_surround = True
                        has_71 = True
                        if channel_layout != 'unknown':
                            has_processable_surround = True
            
            # Determine what tracks need to be created
            # Check if we need enhanced stereo based on existing tracks with current settings
            has_enhanced_stereo = False
            if has_stereo:
                for stream in probe['streams']:
                    if (stream['codec_type'] == 'audio' and 
                        int(stream.get('channels', 0)) == 2):
                        track_title = stream.get('tags', {}).get('title', '')
                        current_settings_pattern = f'C{CENTER_BOOST}-R{COMPRESSOR_RATIO}'
                        if current_settings_pattern in track_title or 'Dialogue-' + current_settings_pattern in track_title:
                            has_enhanced_stereo = True
                            logging.info(f"Found existing enhanced stereo with current settings: '{track_title}'")
                            break
                        elif 'English Stereo' in track_title and ('AAC-VBR' in track_title or 'Enhanced' in track_title):
                            logging.info(f"Found enhanced stereo with outdated settings: '{track_title}' - will re-process")
            
            needs_stereo_track = has_processable_surround and (not has_enhanced_stereo or force_stereo)
            needs_51_from_71 = has_71 and not has_51 and has_processable_surround
            
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
            
            # Check if resolution downgrading is needed
            needs_resolution_downgrade = False
            if downgrade_resolution:
                for stream in probe['streams']:
                    if stream['codec_type'] == 'video':
                        video_width = int(stream.get('width', 0))
                        video_height = int(stream.get('height', 0))
                        if video_height > 1080 or video_width > 1920:
                            needs_resolution_downgrade = True
                            logging.info(f"Resolution {video_width}x{video_height} exceeds 1080p - downgrading needed")
                            
                            # Update final output filename to reflect new resolution
                            final_output_file = base_for_resolution_downgrade + target_ext
                            temp_output_file = base_for_resolution_downgrade + '.tmp' + target_ext
                            output_file = temp_output_file
                            logging.info(f"Output filename updated for resolution downgrade: {os.path.basename(final_output_file)}")
                        break
            
            # Enhanced skip logic - only skip if format AND metadata are perfect AND not forcing stereo AND not downgrading resolution
            if (vcodec == 'h264' and all_aac and input_file.lower().endswith(('.mp4', '.mkv')) and 
                not needs_stereo_track and not needs_51_from_71 and not needs_audio_metadata_fix and not has_non_english_audio and not force_stereo and not needs_resolution_downgrade):
                print(f"Skipping: {input_file} is already H.264/AAC with proper audio metadata and all tracks.")
                logging.info(f"Skipping: {input_file} is already H.264/AAC with proper audio metadata and all tracks.")
                return
            elif needs_resolution_downgrade:
                print(f"Transcoding: {input_file} - downgrading resolution from high definition to 1080p.")
                logging.info(f"Transcoding: {input_file} - downgrading resolution from high definition to 1080p.")
            elif force_stereo and has_stereo:
                print(f"Transcoding: {input_file} - forcing enhanced stereo creation with boosted dialogue (--force-stereo).")
                logging.info(f"Transcoding: {input_file} - forcing enhanced stereo creation with boosted dialogue (--force-stereo).")
            elif needs_51_from_71:
                print(f"Transcoding: {input_file} has 7.1 surround - will create 5.1 and enhanced stereo tracks.")
                logging.info(f"Transcoding: {input_file} has 7.1 surround - will create 5.1 and enhanced stereo tracks.")
            elif needs_stereo_track:
                print(f"Transcoding: {input_file} has surround sound - will create enhanced stereo track with boosted dialogue.")
                logging.info(f"Transcoding: {input_file} has surround sound - will create enhanced stereo track with boosted dialogue.")
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
        args, has_audio = build_ffmpeg_command(input_file, probe, force_stereo, downgrade_resolution)
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
                    
                    # Handle supporting file renaming if resolution was downgraded
                    if is_video and downgrade_resolution and needs_resolution_downgrade:
                        original_base_file = base + target_ext
                        if final_output_file != original_base_file:
                            renamed_supporting_files = find_and_rename_supporting_files(original_base_file, final_output_file)
                            if renamed_supporting_files:
                                print(f"Renamed {len(renamed_supporting_files)} supporting file(s) to match new resolution filename")
                                logging.info(f"Renamed {len(renamed_supporting_files)} supporting files for resolution downgrade")
                    
                except Exception as e:
                    logging.error(f"Failed to atomically move temp file to final location: {e}")
                    print(f"Failed to atomically move temp file to final location: {e}")
                    return
            else:
                # This should not happen with always-temp logic, but handle gracefully
                logging.warning(f"Unexpected: temp file same as final file: {final_output_file}")
            
            logging.info(f"Success: {final_output_file}")
            print(f"Success: {final_output_file}")
            
            # Update database with conversion results
            if DATABASE_AVAILABLE and hasattr(transcode_file, 'db') and fingerprint:
                try:
                    action_taken = []
                    if needs_resolution_downgrade:
                        action_taken.append('resolution_downgraded')
                    if needs_stereo_track or force_stereo:
                        action_taken.append('stereo_created')
                    if needs_51_from_71:
                        action_taken.append('5.1_from_7.1')
                    if needs_audio_metadata_fix:
                        action_taken.append('metadata_fixed')
                    if has_non_english_audio:
                        action_taken.append('non_english_removed')
                    if not action_taken:
                        action_taken.append('video_converted')
                    
                    # Update database: pass final_output_file (converted file location)
                    # If input_file will be deleted, original_fingerprint + final_output_file
                    # handles the cache cleanup automatically
                    transcode_file.db.update_after_conversion(
                        fingerprint,
                        new_filepath=final_output_file,
                        success=True,
                        action_taken=', '.join(action_taken)
                    )
                    logging.info(f"✅ Database updated: {', '.join(action_taken)}")
                except Exception as e:
                    logging.warning(f"Failed to update database after conversion: {e}")
            
            # Add to batch notification list instead of immediate notification
            global processed_files
            processed_files.append(final_output_file)
            
            # Only remove source file if it's different from final output file
            # Database update above will handle cache cleanup for deleted original
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
    finally:
        # Always release the file lock
        if file_lock and FILELOCK_AVAILABLE:
            file_lock.release()
            logging.info(f"🔓 Lock released for: {os.path.basename(input_file)}")

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
    global DATABASE_AVAILABLE
    
    # Initialize database for caching if available
    if DATABASE_AVAILABLE:
        try:
            transcode_file.db = MediaDatabase()
            logging.info(f"📦 Database caching enabled: {transcode_file.db.db_path}")
            print(f"📦 Database caching enabled")
        except Exception as e:
            logging.warning(f"Failed to initialize database: {e}")
            print(f"⚠️  Database caching disabled: {e}")
            DATABASE_AVAILABLE = False
    
    # Clean up any orphaned temp files from previous interrupted runs
    cleanup_orphaned_temp_files()
    
    parser = argparse.ArgumentParser(description="Transcode media files.")
    parser.add_argument('--dir', type=str, help='Directory to search for media files')
    parser.add_argument('--file', type=str, help='Single media file to convert')
    parser.add_argument('--type', type=str, choices=['video', 'audio', 'both'], default='both', 
                       help='Type of media to process: video, audio, or both (default: both)')
    parser.add_argument('--force-stereo', action='store_true', 
                       help='Force creation of enhanced stereo track even if stereo already exists (useful for dialogue enhancement)')
    parser.add_argument('--downgrade-resolution', action='store_true',
                       help='Downgrade video resolution to 1080p maximum (scales down 4K/higher resolutions while preserving aspect ratio and updating filename to reflect new resolution)')
    args = parser.parse_args()

    if args.file:
        if not os.path.isfile(args.file):
            logging.error("Invalid file.")
            print("Invalid file.")
            sys.exit(1)
        transcode_file(args.file, args.force_stereo, args.downgrade_resolution)
        
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
            transcode_file(file_path, args.force_stereo, args.downgrade_resolution)
            
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
            transcode_file(f, args.force_stereo, args.downgrade_resolution)
        except Exception as e:
            logging.error(f"Error processing {f}: {e}")
            print(f"Error processing {f}: {e}")
    
    # Perform batch Plex notifications after all files are processed
    if processed_files:
        print(f"Notifying Plex about {len(processed_files)} processed files...")
        batch_notify_plex()
    
    # Close database connection if it was opened
    if DATABASE_AVAILABLE and hasattr(transcode_file, 'db'):
        try:
            transcode_file.db.close()
            logging.info("📦 Database connection closed")
        except Exception as e:
            logging.warning(f"Error closing database: {e}")
    
    logging.info("Transcoding complete.")
    print("Transcoding complete.")

if __name__ == "__main__":
    main()