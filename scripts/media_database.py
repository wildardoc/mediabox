#!/usr/bin/env python3
"""
Mediabox Media Database Library
================================

Shared SQLite database management for media file caching and metadata storage.
Provides fast fingerprinting and decision caching to avoid repeated ffprobe calls.

FEATURES:
---------
• File fingerprinting (size, mtime, hash-based)
• Probe result caching (codec, resolution, HDR, audio)
• Conversion decision tracking
• Processing history and version tracking
• Cache invalidation on file changes

USAGE:
------
from media_database import MediaDatabase

db = MediaDatabase()
fingerprint = db.get_file_fingerprint('/path/to/file.mp4')

if db.has_cached_probe(fingerprint):
    probe = db.get_cached_probe(fingerprint)
else:
    probe = ffmpeg.probe(file)
    db.store_probe(fingerprint, probe, action='needs_conversion')
"""

import os
import sys
import sqlite3
import hashlib
import json
from datetime import datetime
from pathlib import Path

# Script version for cache invalidation
MEDIA_DATABASE_VERSION = "1.0.0"

class MediaDatabase:
    """SQLite-based media file metadata cache and decision tracker"""
    
    def __init__(self, db_path=None):
        """
        Initialize media database connection.
        
        Args:
            db_path (str, optional): Path to SQLite database file.
                                    Defaults to ~/.local/share/mediabox/media_cache.db
        """
        if db_path is None:
            db_dir = os.path.expanduser("~/.local/share/mediabox")
            os.makedirs(db_dir, exist_ok=True)
            db_path = os.path.join(db_dir, "media_cache.db")
        
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row  # Enable column access by name
        self._initialize_schema()
    
    def _initialize_schema(self):
        """Create database tables if they don't exist"""
        cursor = self.conn.cursor()
        
        # Main cache table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS media_cache (
                fingerprint_hash TEXT PRIMARY KEY,
                file_path TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                file_mtime REAL NOT NULL,
                last_scanned TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                
                -- Probe results (cached)
                codec_video TEXT,
                codec_audio TEXT,
                resolution TEXT,
                width INTEGER,
                height INTEGER,
                duration REAL,
                bitrate INTEGER,
                
                -- HDR information
                is_hdr BOOLEAN DEFAULT 0,
                hdr_type TEXT,
                color_transfer TEXT,
                color_primaries TEXT,
                color_space TEXT,
                bit_depth INTEGER,
                
                -- Audio information
                audio_channels TEXT,
                audio_layout TEXT,
                has_english_audio BOOLEAN DEFAULT 0,
                has_stereo_track BOOLEAN DEFAULT 0,
                has_surround_track BOOLEAN DEFAULT 0,
                
                -- Subtitle information
                has_english_subtitles BOOLEAN DEFAULT 0,
                has_forced_subtitles BOOLEAN DEFAULT 0,
                
                -- Decision and action
                action TEXT,  -- 'skip', 'needs_conversion', 'needs_audio', 'needs_video', 'needs_hdr_tonemap'
                conversion_params TEXT,  -- JSON blob
                
                -- Processing history
                last_processed TIMESTAMP,
                processing_version TEXT,
                processing_error TEXT,
                
                -- Statistics
                conversion_count INTEGER DEFAULT 0,
                last_conversion_duration REAL
            )
        """)
        
        # Indexes for performance
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_path ON media_cache(file_path)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_action ON media_cache(action)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_last_scanned ON media_cache(last_scanned)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_is_hdr ON media_cache(is_hdr)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_resolution ON media_cache(resolution)")
        
        # Processing log table (for history tracking)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS processing_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fingerprint_hash TEXT NOT NULL,
                file_path TEXT NOT NULL,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                action TEXT,
                success BOOLEAN,
                error_message TEXT,
                duration REAL,
                version TEXT,
                FOREIGN KEY (fingerprint_hash) REFERENCES media_cache(fingerprint_hash)
            )
        """)
        
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_log_timestamp ON processing_log(timestamp)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_log_fingerprint ON processing_log(fingerprint_hash)")
        
        self.conn.commit()
    
    def get_file_fingerprint(self, filepath):
        """
        Generate quick fingerprint for file without full probe.
        
        Args:
            filepath (str): Absolute path to media file
            
        Returns:
            dict: Fingerprint with hash, path, size, mtime
        """
        try:
            stat = os.stat(filepath)
            # Create hash from path, size, and mtime for quick comparison
            hash_input = f"{filepath}|{stat.st_size}|{stat.st_mtime}".encode('utf-8')
            fingerprint_hash = hashlib.sha256(hash_input).hexdigest()
            
            return {
                'hash': fingerprint_hash,
                'path': filepath,
                'size': stat.st_size,
                'mtime': stat.st_mtime
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
        
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT fingerprint_hash, codec_video, last_scanned, processing_version
            FROM media_cache 
            WHERE fingerprint_hash = ?
        """, (fingerprint['hash'],))
        
        row = cursor.fetchone()
        if not row:
            return False
        
        # Check if we have actual probe data (codec_video should exist)
        if not row['codec_video']:
            return False
        
        # Optional: Invalidate cache if processing version changed
        # if row['processing_version'] != MEDIA_DATABASE_VERSION:
        #     return False
        
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
        
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT * FROM media_cache 
            WHERE fingerprint_hash = ?
        """, (fingerprint['hash'],))
        
        row = cursor.fetchone()
        if not row:
            return None
        
        # Reconstruct probe-like structure for compatibility with existing code
        probe = {
            'format': {
                'filename': row['file_path'],
                'size': str(row['file_size']),
                'duration': str(row['duration']) if row['duration'] else '0',
                'bit_rate': str(row['bitrate']) if row['bitrate'] else '0'
            },
            'streams': []
        }
        
        # Video stream
        if row['codec_video']:
            video_stream = {
                'index': 0,
                'codec_type': 'video',
                'codec_name': row['codec_video'],
                'width': row['width'],
                'height': row['height'],
                'pix_fmt': 'yuv420p',  # Default, will be updated from detailed data
                'color_transfer': row['color_transfer'] or '',
                'color_primaries': row['color_primaries'] or '',
                'color_space': row['color_space'] or ''
            }
            probe['streams'].append(video_stream)
        
        # Audio stream (simplified - actual implementation should handle multiple streams)
        if row['codec_audio']:
            audio_stream = {
                'index': 1,
                'codec_type': 'audio',
                'codec_name': row['codec_audio'],
                'channels': int(row['audio_channels'].split('.')[0]) if row['audio_channels'] else 2,
                'channel_layout': row['audio_layout'] or 'stereo'
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
        
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT action FROM media_cache 
            WHERE fingerprint_hash = ?
        """, (fingerprint['hash'],))
        
        row = cursor.fetchone()
        return row['action'] if row else None
    
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
        
        # Prepare conversion params JSON
        params_json = json.dumps(conversion_params) if conversion_params else None
        
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO media_cache (
                fingerprint_hash, file_path, file_size, file_mtime, last_scanned,
                codec_video, codec_audio, resolution, width, height, duration, bitrate,
                is_hdr, hdr_type, color_transfer, color_primaries, color_space, bit_depth,
                audio_channels, audio_layout, has_stereo_track, has_surround_track,
                action, conversion_params, processing_version
            ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP,
                      ?, ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?,
                      ?, ?, ?)
        """, (
            fingerprint['hash'], fingerprint['path'], fingerprint['size'], fingerprint['mtime'],
            codec_video, codec_audio, resolution, width, height, duration, bitrate,
            is_hdr, hdr_type, color_transfer, color_primaries, color_space, bit_depth,
            audio_channels, audio_layout, has_stereo, has_surround,
            action, params_json, MEDIA_DATABASE_VERSION
        ))
        
        self.conn.commit()
    
    def update_after_conversion(self, original_fingerprint, new_filepath, success=True, error_message=None, duration=None):
        """
        Update database after file conversion completes.
        
        Args:
            original_fingerprint (dict): Fingerprint of original file
            new_filepath (str): Path to converted file (may be same as original)
            success (bool): Whether conversion succeeded
            error_message (str, optional): Error message if failed
            duration (float, optional): Conversion duration in seconds
        """
        if not original_fingerprint:
            return
        
        cursor = self.conn.cursor()
        
        # Log the processing event
        cursor.execute("""
            INSERT INTO processing_log (
                fingerprint_hash, file_path, timestamp, action, success, error_message, duration, version
            ) VALUES (?, ?, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?)
        """, (
            original_fingerprint['hash'], original_fingerprint['path'], 
            'conversion', success, error_message, duration, MEDIA_DATABASE_VERSION
        ))
        
        if success:
            # Get new fingerprint of converted file
            new_fingerprint = self.get_file_fingerprint(new_filepath)
            
            if new_fingerprint:
                # Update the cache entry to mark as processed
                cursor.execute("""
                    UPDATE media_cache 
                    SET last_processed = CURRENT_TIMESTAMP,
                        conversion_count = conversion_count + 1,
                        last_conversion_duration = ?,
                        action = 'skip',
                        processing_error = NULL
                    WHERE fingerprint_hash = ?
                """, (duration, original_fingerprint['hash']))
                
                # If fingerprint changed (file was modified), create new cache entry
                if new_fingerprint['hash'] != original_fingerprint['hash']:
                    # Mark old entry as processed
                    cursor.execute("""
                        UPDATE media_cache 
                        SET action = 'replaced'
                        WHERE fingerprint_hash = ?
                    """, (original_fingerprint['hash'],))
                    
                    # Create new entry for converted file (will need to be probed again for accurate data)
                    cursor.execute("""
                        INSERT OR IGNORE INTO media_cache (
                            fingerprint_hash, file_path, file_size, file_mtime, 
                            last_scanned, action, processing_version
                        ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, 'skip', ?)
                    """, (
                        new_fingerprint['hash'], new_fingerprint['path'], 
                        new_fingerprint['size'], new_fingerprint['mtime'],
                        MEDIA_DATABASE_VERSION
                    ))
        else:
            # Mark as failed
            cursor.execute("""
                UPDATE media_cache 
                SET processing_error = ?
                WHERE fingerprint_hash = ?
            """, (error_message, original_fingerprint['hash']))
        
        self.conn.commit()
    
    def query_by_filter(self, **filters):
        """
        Query database with filters.
        
        Args:
            **filters: Keyword arguments for filtering
                - is_hdr (bool): Filter by HDR status
                - action (str): Filter by action needed
                - resolution (str): Filter by resolution
                - codec_video (str): Filter by video codec
                - codec_audio (str): Filter by audio codec
        
        Returns:
            list: List of matching rows as dicts
        """
        query = "SELECT * FROM media_cache WHERE 1=1"
        params = []
        
        if 'is_hdr' in filters:
            query += " AND is_hdr = ?"
            params.append(1 if filters['is_hdr'] else 0)
        
        if 'action' in filters:
            query += " AND action = ?"
            params.append(filters['action'])
        
        if 'resolution' in filters:
            query += " AND resolution = ?"
            params.append(filters['resolution'])
        
        if 'codec_video' in filters:
            query += " AND codec_video = ?"
            params.append(filters['codec_video'])
        
        if 'codec_audio' in filters:
            query += " AND codec_audio = ?"
            params.append(filters['codec_audio'])
        
        query += " ORDER BY file_path"
        
        cursor = self.conn.execute(query, params)
        return [dict(row) for row in cursor.fetchall()]
    
    def get_statistics(self):
        """
        Get database statistics.
        
        Returns:
            dict: Statistics about cached files
        """
        cursor = self.conn.cursor()
        
        stats = {}
        
        # Total files
        cursor.execute("SELECT COUNT(*) as count FROM media_cache")
        stats['total_files'] = cursor.fetchone()['count']
        
        # By action
        cursor.execute("SELECT action, COUNT(*) as count FROM media_cache GROUP BY action")
        stats['by_action'] = {row['action']: row['count'] for row in cursor.fetchall()}
        
        # HDR files
        cursor.execute("SELECT COUNT(*) as count FROM media_cache WHERE is_hdr = 1")
        stats['hdr_files'] = cursor.fetchone()['count']
        
        # By resolution
        cursor.execute("SELECT resolution, COUNT(*) as count FROM media_cache WHERE resolution IS NOT NULL GROUP BY resolution ORDER BY count DESC LIMIT 10")
        stats['by_resolution'] = {row['resolution']: row['count'] for row in cursor.fetchall()}
        
        # By codec
        cursor.execute("SELECT codec_video, COUNT(*) as count FROM media_cache WHERE codec_video IS NOT NULL GROUP BY codec_video ORDER BY count DESC")
        stats['by_codec'] = {row['codec_video']: row['count'] for row in cursor.fetchall()}
        
        return stats
    
    def cleanup_missing_files(self):
        """
        Remove cache entries for files that no longer exist.
        
        Returns:
            int: Number of entries removed
        """
        cursor = self.conn.cursor()
        cursor.execute("SELECT fingerprint_hash, file_path FROM media_cache")
        
        removed = 0
        for row in cursor.fetchall():
            if not os.path.exists(row['file_path']):
                cursor.execute("DELETE FROM media_cache WHERE fingerprint_hash = ?", (row['fingerprint_hash'],))
                removed += 1
        
        self.conn.commit()
        return removed
    
    def close(self):
        """Close database connection"""
        self.conn.close()
    
    def __enter__(self):
        """Context manager support"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager cleanup"""
        self.close()


if __name__ == "__main__":
    # Simple test
    db = MediaDatabase()
    print(f"Database initialized at: {db.db_path}")
    stats = db.get_statistics()
    print(f"Total files in cache: {stats['total_files']}")
    db.close()
