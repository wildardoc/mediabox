#!/usr/bin/env python3
"""
Mediabox Media Database Module
================================

JSON-based caching system for media file metadata.
Stores .mediabox_cache.json files in each directory alongside media files.
Provides fast fingerprint-based lookup to avoid repeated ffprobe calls.

Benefits of directory-based JSON files:
- Works across different mount points (no path dependencies)
- Self-contained and portable
- Easy to backup with media files
- No central database to manage
"""

import os
import sys
import hashlib
import json
from datetime import datetime
from pathlib import Path

MEDIA_DATABASE_VERSION = "1.0.0"
CACHE_FILENAME = ".mediabox_cache.json"

class MediaDatabase:
    """JSON-based media file metadata cache using per-directory cache files"""
    
    def __init__(self, db_path=None):
        """
        Initialize media database.
        
        Args:
            db_path (str, optional): Not used for JSON implementation (kept for compatibility)
        """
        # JSON implementation doesn't use a central database
        # Each directory gets its own .mediabox_cache.json file
        self.db_path = "Per-directory JSON files"
        self.cache = {}  # In-memory cache for current operation
    
    def _get_cache_file_path(self, filepath):
        """Get the cache file path for a given media file's directory"""
        directory = os.path.dirname(os.path.abspath(filepath))
        return os.path.join(directory, CACHE_FILENAME)
    
    def _load_cache(self, cache_file):
        """Load cache from JSON file"""
        if os.path.exists(cache_file):
            try:
                with open(cache_file, 'r') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError):
                return {}
        return {}
    
    def _save_cache(self, cache_file, cache_data):
        """Save cache to JSON file with atomic write"""
        try:
            # Write to temp file first, then rename (atomic operation)
            temp_file = cache_file + '.tmp'
            with open(temp_file, 'w') as f:
                json.dump(cache_data, f, indent=2, default=str)
            os.rename(temp_file, cache_file)
        except IOError as e:
            print(f"Warning: Could not save cache file {cache_file}: {e}")
    
    def get_file_fingerprint(self, filepath):
        """
        Generate quick fingerprint for file without full probe.
        
        Uses filename (without path) + size + mtime for cross-system compatibility.
        This allows cache to work across different mount points:
        - Host: /Storage/media/tv/Show/file.mkv
        - Container: /tv/Show/file.mkv
        - Desktop NFS: /FileServer/media/tv/Show/file.mkv
        
        Args:
            filepath (str): Absolute path to media file
            
        Returns:
            dict: Fingerprint with hash, path, size, mtime
        """
        try:
            stat = os.stat(filepath)
            filename = os.path.basename(filepath)
            
            # Create hash from filename, size, and mtime for quick comparison
            hash_input = f"{filename}|{stat.st_size}|{stat.st_mtime}".encode('utf-8')
            fingerprint_hash = hashlib.sha256(hash_input).hexdigest()
            
            return {
                'hash': fingerprint_hash,
                'path': filepath,
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'filename': filename
            }
        except (OSError, FileNotFoundError) as e:
            return None
    
    def has_cached_probe(self, fingerprint):
        """
        Check if probe results exist in cache for this fingerprint.
        
        Args:
            fingerprint (dict): Fingerprint from get_file_fingerprint()
            
        Returns:
            bool: True if cached probe exists and is valid
        """
        if not fingerprint:
            return False
        
        cache_file = self._get_cache_file_path(fingerprint['path'])
        cache_data = self._load_cache(cache_file)
        
        if not cache_data:
            return False
        
        # Check if this file's entry exists
        entry = cache_data.get(fingerprint['hash'])
        if not entry:
            return False
        
        # Check if we have actual probe data
        if not entry.get('codec_video'):
            return False
        
        return True
    
    def get_cached_probe(self, fingerprint):
        """
        Retrieve cached probe results.
        
        Args:
            fingerprint (dict): Fingerprint from get_file_fingerprint()
            
        Returns:
            dict: Cached probe data in ffmpeg.probe() compatible format, or None
        """
        if not fingerprint:
            return None
        
        cache_file = self._get_cache_file_path(fingerprint['path'])
        cache_data = self._load_cache(cache_file)
        
        if not cache_data:
            return None
        
        entry = cache_data.get(fingerprint['hash'])
        if not entry:
            return None

        entry = cache_data.get(fingerprint['hash'])
        if not entry:
            return None
        
        # Reconstruct probe-like structure for compatibility with existing code
        probe = {
            'format': {
                'filename': fingerprint['path'],
                'size': str(entry.get('file_size', 0)),
                'duration': str(entry.get('duration', 0)),
                'bit_rate': str(entry.get('bitrate', 0))
            },
            'streams': []
        }
        
        # Video stream
        if entry.get('codec_video'):
            video_stream = {
                'index': 0,
                'codec_type': 'video',
                'codec_name': entry['codec_video'],
                'width': entry.get('width'),
                'height': entry.get('height'),
                'pix_fmt': 'yuv420p',
                'color_transfer': entry.get('color_transfer', ''),
                'color_primaries': entry.get('color_primaries', ''),
                'color_space': entry.get('color_space', '')
            }
            probe['streams'].append(video_stream)
        
        # Audio stream
        if entry.get('codec_audio'):
            audio_stream = {
                'index': 1,
                'codec_type': 'audio',
                'codec_name': entry['codec_audio'],
                'channels': int(entry.get('audio_channels', '2').split('.')[0]),
                'channel_layout': entry.get('audio_layout', 'stereo')
            }
            probe['streams'].append(audio_stream)
        
        return probe
    
    def get_cached_action(self, fingerprint):
        """
        Get the cached conversion action decision.
        
        Args:
            fingerprint (dict): Fingerprint from get_file_fingerprint()
            
        Returns:
            str: Action ('skip', 'needs_conversion', etc.) or None
        """
        if not fingerprint:
            return None
        
        cache_file = self._get_cache_file_path(fingerprint['path'])
        cache_data = self._load_cache(cache_file)
        
        if not cache_data:
            return None
        
        entry = cache_data.get(fingerprint['hash'])
        return entry.get('action') if entry else None
    
    def store_probe(self, fingerprint, probe, action='unknown', conversion_params=None):
        """
        Store probe results and decision in cache.
        
        Args:
            fingerprint (dict): Fingerprint from get_file_fingerprint()
            probe (dict): ffmpeg.probe() result
            action (str): Decision ('skip', 'needs_conversion', etc.)
            conversion_params (dict, optional): Parameters for conversion
        """
        if not fingerprint or not probe:
            return
        
        # Extract data from probe
        video_stream = next((s for s in probe.get('streams', []) if s['codec_type'] == 'video'), None)
        audio_streams = [s for s in probe.get('streams', []) if s['codec_type'] == 'audio']
        
        # Video data
        codec_video = video_stream.get('codec_name') if video_stream else None
        width = int(video_stream.get('width', 0)) if video_stream else None
        height = int(video_stream.get('height', 0)) if video_stream else None
        resolution = f"{width}x{height}" if width and height else None
        
        # HDR detection
        is_hdr = False
        hdr_type = None
        color_transfer = video_stream.get('color_transfer', '') if video_stream else ''
        color_primaries = video_stream.get('color_primaries', '') if video_stream else ''
        color_space = video_stream.get('color_space', '') if video_stream else ''
        
        if color_transfer == 'smpte2084':
            is_hdr = True
            hdr_type = 'HDR10'
        elif color_transfer == 'arib-std-b67':
            is_hdr = True
            hdr_type = 'HLG'
        elif color_primaries == 'bt2020' and '10' in video_stream.get('pix_fmt', ''):
            is_hdr = True
            hdr_type = 'HDR (BT.2020)'
        
        # Bit depth
        pix_fmt = video_stream.get('pix_fmt', '') if video_stream else ''
        bit_depth = 10 if '10' in pix_fmt else 8
        
        # Audio data
        codec_audio = audio_streams[0].get('codec_name') if audio_streams else None
        has_stereo = any(s.get('channels') == 2 for s in audio_streams)
        has_surround = any(s.get('channels', 0) > 2 for s in audio_streams)
        audio_channels = str(audio_streams[0].get('channels', 0)) if audio_streams else '0'
        audio_layout = audio_streams[0].get('channel_layout', '') if audio_streams else ''
        
        # Format data
        format_data = probe.get('format', {})
        duration = float(format_data.get('duration', 0))
        bitrate = int(format_data.get('bit_rate', 0))
        
        # Build cache entry
        from datetime import datetime
        entry = {
            'fingerprint_hash': fingerprint['hash'],
            'file_path': fingerprint['path'],
            'file_name': fingerprint.get('filename', os.path.basename(fingerprint['path'])),
            'file_size': fingerprint['size'],
            'file_mtime': fingerprint['mtime'],
            'last_scanned': datetime.now().isoformat(),
            
            'codec_video': codec_video,
            'codec_audio': codec_audio,
            'resolution': resolution,
            'width': width,
            'height': height,
            'duration': duration,
            'bitrate': bitrate,
            
            'is_hdr': is_hdr,
            'hdr_type': hdr_type,
            'color_transfer': color_transfer,
            'color_primaries': color_primaries,
            'color_space': color_space,
            'bit_depth': bit_depth,
            
            'audio_channels': audio_channels,
            'audio_layout': audio_layout,
            'has_stereo_track': has_stereo,
            'has_surround_track': has_surround,
            
            'action': action,
            'conversion_params': conversion_params,
            'processing_version': MEDIA_DATABASE_VERSION,
            
            'conversion_count': 0,
            'last_conversion_duration': None
        }
        
        # Load existing cache for this directory
        cache_file = self._get_cache_file_path(fingerprint['path'])
        cache_data = self._load_cache(cache_file)
        
        # Update with new entry
        cache_data[fingerprint['hash']] = entry
        
        # Save back to file
        self._save_cache(cache_file, cache_data)
    
    def update_after_conversion(self, original_fingerprint, new_filepath=None, success=True, error_message=None, duration=None, action_taken=None):
        """
        Update database after file conversion completes.
        
        Handles three scenarios:
        1. In-place conversion (original modified): Update existing entry with new fingerprint
        2. New file created (original deleted): Remove old entry, create new one
        3. Conversion failed: Mark entry with error
        
        Args:
            original_fingerprint (dict): Fingerprint of original file
            new_filepath (str, optional): Path to converted file (None if original deleted)
            success (bool): Whether conversion succeeded
            error_message (str, optional): Error message if failed
            duration (float, optional): Conversion duration in seconds
            action_taken (str, optional): Description of action taken (for logging)
        """
        if not original_fingerprint:
            return
        
        cache_file = self._get_cache_file_path(original_fingerprint['path'])
        cache_data = self._load_cache(cache_file)
        
        entry = cache_data.get(original_fingerprint['hash'])
        if not entry:
            return
        
        from datetime import datetime
        
        if success:
            # Check if original file still exists (in-place conversion)
            original_exists = os.path.exists(original_fingerprint['path'])
            
            if new_filepath and os.path.exists(new_filepath):
                # Get new fingerprint of converted file
                new_fingerprint = self.get_file_fingerprint(new_filepath)
                
                if new_fingerprint:
                    # Check if this is a different directory (rare, but possible)
                    new_cache_file = self._get_cache_file_path(new_filepath)
                    if new_cache_file != cache_file:
                        # File moved to different directory - remove from old cache
                        del cache_data[original_fingerprint['hash']]
                        self._save_cache(cache_file, cache_data)
                        
                        # Add to new directory's cache
                        new_cache_data = self._load_cache(new_cache_file)
                        entry['last_processed'] = datetime.now().isoformat()
                        entry['conversion_count'] = entry.get('conversion_count', 0) + 1
                        entry['last_conversion_duration'] = duration
                        entry['action'] = 'skip'
                        entry['processing_error'] = None
                        entry['fingerprint_hash'] = new_fingerprint['hash']
                        entry['file_path'] = new_fingerprint['path']
                        entry['file_size'] = new_fingerprint['size']
                        entry['file_mtime'] = new_fingerprint['mtime']
                        new_cache_data[new_fingerprint['hash']] = entry
                        self._save_cache(new_cache_file, new_cache_data)
                        return
                    
                    # Same directory - update entry
                    entry['last_processed'] = datetime.now().isoformat()
                    entry['conversion_count'] = entry.get('conversion_count', 0) + 1
                    entry['last_conversion_duration'] = duration
                    entry['action'] = 'skip'
                    entry['processing_error'] = None
                    
                    # If fingerprint changed (file was modified), update the hash key
                    if new_fingerprint['hash'] != original_fingerprint['hash']:
                        # Remove old entry
                        del cache_data[original_fingerprint['hash']]
                        
                        # Update entry with new fingerprint details
                        entry['fingerprint_hash'] = new_fingerprint['hash']
                        entry['file_path'] = new_fingerprint['path']
                        entry['file_size'] = new_fingerprint['size']
                        entry['file_mtime'] = new_fingerprint['mtime']
                        
                        # Add as new entry
                        cache_data[new_fingerprint['hash']] = entry
                    else:
                        # Update in place
                        cache_data[original_fingerprint['hash']] = entry
            
            elif not original_exists:
                # Original file was deleted and no new file provided - remove cache entry
                del cache_data[original_fingerprint['hash']]
                
            else:
                # Original still exists - update in place
                entry['last_processed'] = datetime.now().isoformat()
                entry['conversion_count'] = entry.get('conversion_count', 0) + 1
                entry['last_conversion_duration'] = duration
                entry['action'] = 'skip'
                entry['processing_error'] = None
                cache_data[original_fingerprint['hash']] = entry
        else:
            # Mark as failed
            entry['processing_error'] = error_message
            entry['last_processed'] = datetime.now().isoformat()
            cache_data[original_fingerprint['hash']] = entry
        
        # Save updated cache
        self._save_cache(cache_file, cache_data)
    
    def query_by_filter(self, directories=None, **filters):
        """
        Query cache files with filters across multiple directories.
        
        Args:
            directories (list): List of directories to search (scans all JSON files if None)
            **filters: Keyword arguments for filtering
                - is_hdr (bool): Filter by HDR status
                - action (str): Filter by action needed
                - resolution (str): Filter by resolution
                - codec_video (str): Filter by video codec
                - codec_audio (str): Filter by audio codec
        
        Returns:
            list: List of matching entries as dicts
        """
        results = []
        
        if not directories:
            return results
        
        for directory in directories:
            cache_file = os.path.join(directory, CACHE_FILENAME)
            if not os.path.exists(cache_file):
                continue
            
            cache_data = self._load_cache(cache_file)
            if not cache_data:
                continue
            
            # Filter entries
            for fingerprint_hash, entry in cache_data.items():
                match = True
                
                if 'is_hdr' in filters and entry.get('is_hdr') != filters['is_hdr']:
                    match = False
                
                if 'action' in filters and entry.get('action') != filters['action']:
                    match = False
                
                if 'resolution' in filters and entry.get('resolution') != filters['resolution']:
                    match = False
                
                if 'codec_video' in filters and entry.get('codec_video') != filters['codec_video']:
                    match = False
                
                if 'codec_audio' in filters and entry.get('codec_audio') != filters['codec_audio']:
                    match = False
                
                if match:
                    results.append(entry.copy())
        
        # Sort by file path
        results.sort(key=lambda x: x.get('file_path', ''))
        return results
    
    def get_statistics(self, directories=None):
        """
        Get cache statistics across multiple directories.
        
        Args:
            directories (list): List of directories to scan (required)
        
        Returns:
            dict: Statistics about cached files
        """
        stats = {
            'total_files': 0,
            'by_action': {},
            'hdr_files': 0,
            'by_resolution': {},
            'by_codec_video': {},
            'by_codec_audio': {}
        }
        
        if not directories:
            return stats
        
        for directory in directories:
            cache_file = os.path.join(directory, CACHE_FILENAME)
            if not os.path.exists(cache_file):
                continue
            
            cache_data = self._load_cache(cache_file)
            if not cache_data:
                continue
            
            for entry in cache_data.values():
                stats['total_files'] += 1
                
                # By action
                action = entry.get('action', 'unknown')
                stats['by_action'][action] = stats['by_action'].get(action, 0) + 1
                
                # HDR count
                if entry.get('is_hdr'):
                    stats['hdr_files'] += 1
                
                # By resolution
                resolution = entry.get('resolution')
                if resolution:
                    stats['by_resolution'][resolution] = stats['by_resolution'].get(resolution, 0) + 1
                
                # By codec
                codec_video = entry.get('codec_video')
                if codec_video:
                    stats['by_codec_video'][codec_video] = stats['by_codec_video'].get(codec_video, 0) + 1
                
                codec_audio = entry.get('codec_audio')
                if codec_audio:
                    stats['by_codec_audio'][codec_audio] = stats['by_codec_audio'].get(codec_audio, 0) + 1
        
        # Sort by count (top 10 for each category)
        stats['by_resolution'] = dict(sorted(stats['by_resolution'].items(), key=lambda x: x[1], reverse=True)[:10])
        stats['by_codec_video'] = dict(sorted(stats['by_codec_video'].items(), key=lambda x: x[1], reverse=True)[:10])
        stats['by_codec_audio'] = dict(sorted(stats['by_codec_audio'].items(), key=lambda x: x[1], reverse=True)[:10])
        
        return stats
    
    def cleanup_missing_files(self, directory):
        """
        Remove cache entries for files that no longer exist in the given directory.
        
        Args:
            directory (str): Directory to cleanup cache for
        
        Returns:
            int: Number of entries removed
        """
        cache_file = os.path.join(directory, CACHE_FILENAME)
        cache_data = self._load_cache(cache_file)
        
        if not cache_data:
            return 0
        
        removed = 0
        to_remove = []
        
        for fingerprint_hash, entry in cache_data.items():
            filepath = entry.get('file_path')
            if filepath and not os.path.exists(filepath):
                to_remove.append(fingerprint_hash)
                removed += 1
        
        # Remove missing entries
        for fingerprint_hash in to_remove:
            del cache_data[fingerprint_hash]
        
        # Save if we removed anything
        if removed > 0:
            self._save_cache(cache_file, cache_data)
        
        return removed
    
    def cleanup_all_directories(self, directories):
        """
        Clean up cache entries for missing files across multiple directories.
        
        Useful for periodic maintenance to remove entries for files that were
        deleted outside the system (manual deletion, *arr cleanup, etc.)
        
        Args:
            directories (list): List of directories to scan and cleanup
        
        Returns:
            dict: Summary of cleanup {'total_removed': int, 'directories_cleaned': int}
        """
        total_removed = 0
        directories_cleaned = 0
        
        for directory in directories:
            if not os.path.isdir(directory):
                continue
            
            # Walk subdirectories to find all cache files
            for root, dirs, files in os.walk(directory):
                if CACHE_FILENAME in files:
                    removed = self.cleanup_missing_files(root)
                    if removed > 0:
                        total_removed += removed
                        directories_cleaned += 1
        
        return {
            'total_removed': total_removed,
            'directories_cleaned': directories_cleaned
        }
    
    def close(self):
        """Close database connection (no-op for JSON backend)"""
        pass
    
    def __enter__(self):
        """Context manager support"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager cleanup"""
        self.close()


if __name__ == "__main__":
    # Simple test
    import sys
    
    print("MediaDatabase - JSON-based per-directory caching")
    print(f"Cache filename: {CACHE_FILENAME}")
    print(f"Version: {MEDIA_DATABASE_VERSION}")
    
    # Test with a sample directory if provided
    if len(sys.argv) > 1:
        test_dir = sys.argv[1]
        if os.path.isdir(test_dir):
            db = MediaDatabase()
            
            # Find media files
            media_extensions = ('.mkv', '.mp4', '.avi', '.m4v')
            media_files = []
            for file in os.listdir(test_dir):
                if file.lower().endswith(media_extensions):
                    media_files.append(os.path.join(test_dir, file))
            
            print(f"\nFound {len(media_files)} media files in {test_dir}")
            
            # Test fingerprinting
            for filepath in media_files[:3]:  # Test first 3
                fp = db.get_file_fingerprint(filepath)
                if fp:
                    print(f"  {fp['filename']}: {fp['hash'][:16]}...")
                    has_cache = db.has_cached_probe(fp)
                    print(f"    Cached: {has_cache}")
            
            # Get stats for this directory
            stats = db.get_statistics([test_dir])
            print(f"\nCache statistics:")
            print(f"  Total entries: {stats['total_files']}")
            print(f"  HDR files: {stats['hdr_files']}")
            if stats['by_action']:
                print(f"  Actions: {stats['by_action']}")
            
            db.close()
        else:
            print(f"Error: {test_dir} is not a directory")
    else:
        print("\nUsage: python3 media_database.py /path/to/media/directory")
        print("Tests fingerprinting and cache access in the specified directory")
