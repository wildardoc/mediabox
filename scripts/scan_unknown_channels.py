#!/usr/bin/env python3
"""
Scan all video files in media directories and identify those with unknown channel layouts.
This helps identify problematic files that cause FFmpeg encoding failures.
"""

import os
import json
import logging
import subprocess
from datetime import datetime
from pathlib import Path

# Setup logging
log_filename = f"unknown_channels_scan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_filename),
        logging.StreamHandler()
    ]
)

# Media directories to scan
MEDIA_DIRS = [
    '/Storage/media/movies',
    '/Storage/media/tv'
]

# Supported video file extensions
VIDEO_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v'}

def scan_file_for_unknown_channels(file_path):
    """
    Scan a single video file for unknown channel layouts.
    Returns dict with file info and any problematic streams.
    """
    try:
        # Use ffprobe directly via subprocess
        cmd = [
            'ffprobe', '-v', 'quiet', '-print_format', 'json', 
            '-show_format', '-show_streams', file_path
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            logging.error(f"FFprobe error for {file_path}: {result.stderr}")
            return None
        
        probe = json.loads(result.stdout)
        
        file_info = {
            'file_path': file_path,
            'file_size_mb': round(os.path.getsize(file_path) / (1024 * 1024), 1),
            'duration': None,
            'problematic_streams': [],
            'all_audio_streams': []
        }
        
        # Extract duration if available
        if 'format' in probe and 'duration' in probe['format']:
            try:
                duration_seconds = float(probe['format']['duration'])
                hours = int(duration_seconds // 3600)
                minutes = int((duration_seconds % 3600) // 60)
                file_info['duration'] = f"{hours:02d}:{minutes:02d}:{int(duration_seconds % 60):02d}"
            except:
                pass
        
        # Check all audio streams
        for stream in probe.get('streams', []):
            if stream.get('codec_type') == 'audio':
                channels = int(stream.get('channels', 0))
                channel_layout = stream.get('channel_layout', 'unknown')
                codec = stream.get('codec_name', 'unknown')
                language = stream.get('tags', {}).get('language', 'und') if 'tags' in stream else 'und'
                
                stream_info = {
                    'index': stream['index'],
                    'channels': channels,
                    'channel_layout': channel_layout,
                    'codec': codec,
                    'language': language
                }
                
                file_info['all_audio_streams'].append(stream_info)
                
                # Flag problematic streams (unknown layout with 6+ channels)
                if channel_layout == 'unknown' and channels >= 6:
                    file_info['problematic_streams'].append(stream_info)
                    logging.warning(f"PROBLEMATIC: {file_path}")
                    logging.warning(f"  Stream {stream['index']}: {channels}ch, layout='{channel_layout}', codec={codec}, lang={language}")
        
        return file_info
        
    except subprocess.SubprocessError as e:
        logging.error(f"FFprobe subprocess error for {file_path}: {e}")
        return None
    except json.JSONDecodeError as e:
        logging.error(f"JSON decode error for {file_path}: {e}")
        return None
    except Exception as e:
        logging.error(f"Unexpected error probing {file_path}: {e}")
        return None

def scan_directory(directory):
    """Recursively scan directory for video files with unknown channel layouts."""
    problematic_files = []
    total_files = 0
    
    if not os.path.exists(directory):
        logging.warning(f"Directory does not exist: {directory}")
        return problematic_files
    
    logging.info(f"Scanning directory: {directory}")
    
    for root, dirs, files in os.walk(directory):
        for file in files:
            if Path(file).suffix.lower() in VIDEO_EXTENSIONS:
                total_files += 1
                file_path = os.path.join(root, file)
                
                # Progress indicator
                if total_files % 50 == 0:
                    logging.info(f"Scanned {total_files} files so far...")
                
                file_info = scan_file_for_unknown_channels(file_path)
                if file_info and file_info['problematic_streams']:
                    problematic_files.append(file_info)
    
    logging.info(f"Completed scanning {directory}: {total_files} files checked")
    return problematic_files

def main():
    """Main function to scan all media directories and generate report."""
    logging.info("Starting unknown channel layout scan")
    logging.info(f"Log file: {log_filename}")
    
    all_problematic_files = []
    
    # Scan each media directory
    for media_dir in MEDIA_DIRS:
        problematic_files = scan_directory(media_dir)
        all_problematic_files.extend(problematic_files)
    
    # Generate summary report
    logging.info("=" * 80)
    logging.info("SCAN SUMMARY")
    logging.info("=" * 80)
    logging.info(f"Total problematic files found: {len(all_problematic_files)}")
    
    if all_problematic_files:
        logging.info("\nPROBLEMATIC FILES (unknown channel layout with 6+ channels):")
        logging.info("-" * 80)
        
        for file_info in all_problematic_files:
            logging.info(f"\nFile: {file_info['file_path']}")
            logging.info(f"  Size: {file_info['file_size_mb']} MB")
            if file_info['duration']:
                logging.info(f"  Duration: {file_info['duration']}")
            
            logging.info("  Problematic audio streams:")
            for stream in file_info['problematic_streams']:
                logging.info(f"    Stream {stream['index']}: {stream['channels']}ch, "
                           f"layout='{stream['channel_layout']}', codec={stream['codec']}, lang={stream['language']}")
            
            logging.info("  All audio streams:")
            for stream in file_info['all_audio_streams']:
                status = "PROBLEM" if stream in file_info['problematic_streams'] else "OK"
                logging.info(f"    [{status}] Stream {stream['index']}: {stream['channels']}ch, "
                           f"layout='{stream['channel_layout']}', codec={stream['codec']}, lang={stream['language']}")
    
    # Save detailed results to JSON file
    json_filename = f"unknown_channels_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    try:
        with open(json_filename, 'w') as f:
            json.dump({
                'scan_date': datetime.now().isoformat(),
                'directories_scanned': MEDIA_DIRS,
                'total_problematic_files': len(all_problematic_files),
                'problematic_files': all_problematic_files
            }, f, indent=2)
        logging.info(f"\nDetailed results saved to: {json_filename}")
    except Exception as e:
        logging.error(f"Failed to save JSON results: {e}")
    
    # Summary for user
    if all_problematic_files:
        logging.info(f"\n🔍 SCAN COMPLETE: Found {len(all_problematic_files)} files with problematic audio streams")
        logging.info(f"📄 Log file: {log_filename}")
        logging.info(f"📊 JSON report: {json_filename}")
        logging.info("\n💡 These files will fail FFmpeg conversion due to unknown channel layouts")
        logging.info("   Consider replacing these files or using alternative source material")
    else:
        logging.info("✅ SCAN COMPLETE: No problematic files found!")
        logging.info("   All video files have properly defined channel layouts")

if __name__ == "__main__":
    main()
