#!/usr/bin/env python3
"""
Mediabox Media Database Builder
================================

Scan media directories and build/update the metadata cache database.
This provides fast lookups for media_update.py and enables powerful queries.

USAGE:
------
# Scan entire library
python3 build_media_database.py --scan /Storage/media/movies /Storage/media/tv

# Scan specific directory
python3 build_media_database.py --scan "/Storage/media/tv/Show Name"

# Update existing entries (re-probe changed files)
python3 build_media_database.py --update

# Clean up missing files from database
python3 build_media_database.py --cleanup

# Show statistics
python3 build_media_database.py --stats

FEATURES:
---------
• Fast fingerprint-based change detection
• Skips unchanged files (massive speedup on re-runs)
• Directory-by-directory processing (memory efficient)
• Progress reporting with ETA
• Automatic HDR detection and cataloging
• Parallel processing support (future enhancement)
"""

import os
import sys
import argparse
import time
import json
from datetime import datetime, timedelta
from pathlib import Path

# Add script directory to Python path for imports
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

# Load configuration and activate virtual environment
CONFIG_PATH = os.path.join(script_dir, "mediabox_config.json")
try:
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)
    
    venv_path = config.get("venv_path")
    if venv_path and os.path.exists(venv_path):
        # Add venv site-packages to Python path
        site_packages = os.path.join(
            venv_path, "lib", f"python{sys.version_info.major}.{sys.version_info.minor}", "site-packages"
        )
        if site_packages not in sys.path:
            sys.path.insert(0, site_packages)
        
        # Set virtual environment variables
        os.environ["VIRTUAL_ENV"] = venv_path
        os.environ["PATH"] = os.path.join(venv_path, "bin") + os.pathsep + os.environ.get("PATH", "")
except Exception as e:
    print(f"Warning: Could not activate virtual environment: {e}")
    print("Continuing with system Python packages...")

from media_database import MediaDatabase

# Import ffmpeg if available
try:
    import ffmpeg
    FFMPEG_AVAILABLE = True
except ImportError:
    FFMPEG_AVAILABLE = False
    print("Warning: ffmpeg-python not available. Install with: pip install ffmpeg-python")

# Supported media extensions
VIDEO_EXTS = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.m2ts', '.m4v', '.webm')
# Audio files are not scanned - they don't benefit from metadata caching
# For audio conversion, use media_update.py directly (simple extension check is sufficient)

class MediaScanner:
    """Scan and catalog media files"""
    
    def __init__(self, db_path=None, verbose=False):
        self.db = MediaDatabase(db_path)
        self.verbose = verbose
        self.stats = {
            'scanned': 0,
            'cached': 0,
            'new': 0,
            'modified': 0,
            'errors': 0,
            'hdr_found': 0
        }
        self.start_time = None
        self.scanned_directories = []  # Track directories for stats/cleanup
        self.error_files = []  # Track files that had errors for summary
    
    def scan_directories(self, directories, force_rescan=False):
        """
        Scan directories for media files and update database.
        
        Args:
            directories (list): List of directory paths to scan
            force_rescan (bool): Force re-probe even if cached
        """
        self.start_time = time.time()
        
        print(f"🔍 Scanning directories...")
        print(f"   Database: {self.db.db_path}")
        print(f"   Directories: {len(directories)}")
        print()
        
        for directory in directories:
            if not os.path.isdir(directory):
                print(f"⚠️  Skipping non-directory: {directory}")
                continue
            
            self._scan_directory(directory, force_rescan)
        
        self._print_summary()
    
    def _scan_directory(self, directory, force_rescan=False):
        """Recursively scan a directory"""
        print(f"📁 Scanning: {directory}")
        
        # Track this directory for later stats/cleanup
        if directory not in self.scanned_directories:
            self.scanned_directories.append(directory)
        
        # Get all media files in directory tree
        media_files = []
        dir_count = 0
        skipped_dirs = []
        
        print(f"   🔍 Walking directory tree...")
        for root, dirs, files in os.walk(directory):
            dir_count += 1
            
            # Skip music directories entirely (performance optimization)
            # Modify dirs in-place to prevent os.walk from descending into them
            original_dirs = dirs.copy()
            dirs[:] = [d for d in dirs if d.lower() not in ('music', 'audiobooks', 'podcasts')]
            
            # Track what we skipped for debugging
            for d in original_dirs:
                if d not in dirs:
                    skipped_path = os.path.join(root, d)
                    skipped_dirs.append(skipped_path)
                    print(f"   ⏭️  Skipping: {skipped_path}")
            
            # Show progress every 100 directories
            if dir_count % 100 == 0:
                print(f"   📂 Traversed {dir_count} directories, found {len(media_files)} video files so far...")
            
            # Track subdirectories that contain media
            for file in files:
                # Only scan video files (audio files don't benefit from caching)
                if file.lower().endswith(VIDEO_EXTS):
                    media_files.append(os.path.join(root, file))
                    # Track the directory containing this media file
                    if root not in self.scanned_directories:
                        self.scanned_directories.append(root)
        
        print(f"   ✅ Traversal complete: {dir_count} directories walked, {len(skipped_dirs)} skipped")
        
        total_files = len(media_files)
        if total_files == 0:
            print(f"   No media files found")
            return
        
        print(f"   📹 Found {total_files} video files to process")
        
        # Process each file
        for idx, filepath in enumerate(media_files, 1):
            self._process_file(filepath, force_rescan, idx, total_files)
        
        print()
    
    def _process_file(self, filepath, force_rescan, idx, total):
        """Process a single media file"""
        self.stats['scanned'] += 1
        
        # Generate fingerprint
        fingerprint = self.db.get_file_fingerprint(filepath)
        if not fingerprint:
            error_msg = f"Cannot access file"
            self.error_files.append((filepath, error_msg))
            print(f"   [{idx}/{total}] ⚠️  {error_msg}: {filepath}")
            self.stats['errors'] += 1
            return
        
        # Check if we have cached data
        if not force_rescan and self.db.has_cached_probe(fingerprint):
            self.stats['cached'] += 1
            if self.verbose:
                print(f"   [{idx}/{total}] ✓ Cached: {os.path.basename(filepath)}")
            
            # Update progress every 10 files
            if idx % 10 == 0:
                self._print_progress(idx, total)
            return
        
        # Need to probe the file
        if not FFMPEG_AVAILABLE:
            error_msg = "ffmpeg-python not installed"
            self.error_files.append((filepath, error_msg))
            print(f"   [{idx}/{total}] ⚠️  {error_msg}: {os.path.basename(filepath)}")
            self.stats['errors'] += 1
            return
        
        try:
            # Probe the file
            probe_start = time.time()
            probe = ffmpeg.probe(filepath)
            probe_time = time.time() - probe_start

            # Store in database (action is determined dynamically by needs_conversion())
            self.db.store_probe(fingerprint, probe)
            
            # Update stats
            if force_rescan:
                self.stats['modified'] += 1
                status = "↻ Re-scanned"
            else:
                self.stats['new'] += 1
                status = "✨ New"
            
            # Check if HDR
            is_hdr = self._is_hdr(probe)
            if is_hdr:
                self.stats['hdr_found'] += 1
                status += " [HDR]"
            
            if self.verbose or idx % 10 == 0:
                print(f"   [{idx}/{total}] {status}: {os.path.basename(filepath)} ({action}) [{probe_time:.1f}s]")
            else:
                self._print_progress(idx, total)
                
        except Exception as e:
            self.stats['errors'] += 1
            error_msg = str(e)
            self.error_files.append((filepath, error_msg))
            print(f"   [{idx}/{total}] ❌ Error probing: {filepath}")
            print(f"                  Error: {error_msg}")
    
    def _print_progress(self, current, total):
        """Print progress bar"""
        if not self.verbose:
            percent = (current / total) * 100
            bar_length = 40
            filled = int(bar_length * current / total)
            bar = '█' * filled + '░' * (bar_length - filled)
            
            # Calculate ETA
            elapsed = time.time() - self.start_time
            if current > 0:
                avg_per_file = elapsed / current
                remaining = (total - current) * avg_per_file
                eta = str(timedelta(seconds=int(remaining)))
            else:
                eta = "calculating..."
            
            print(f"\r   Progress: [{bar}] {current}/{total} ({percent:.1f}%) - ETA: {eta}", end='', flush=True)
        
        if current == total:
            print()  # New line when complete
    
    def _is_hdr(self, probe):
        """Check if probe indicates HDR content"""
        video_stream = next((s for s in probe.get('streams', []) if s['codec_type'] == 'video'), None)
        if not video_stream:
            return False
        
        color_transfer = video_stream.get('color_transfer', '')
        color_primaries = video_stream.get('color_primaries', '')
        pix_fmt = video_stream.get('pix_fmt', '')
        
        if color_transfer in ['smpte2084', 'arib-std-b67']:
            return True
        if color_primaries == 'bt2020' and '10' in pix_fmt:
            return True
        
        return False

    def _print_summary(self):
        """Print scan summary"""
        elapsed = time.time() - self.start_time
        
        print()
        print("=" * 60)
        print("📊 Scan Complete")
        print("=" * 60)
        print(f"Total files scanned:    {self.stats['scanned']:,}")
        print(f"  • Used cache:         {self.stats['cached']:,}")
        print(f"  • New files:          {self.stats['new']:,}")
        print(f"  • Re-scanned:         {self.stats['modified']:,}")
        print(f"  • HDR detected:       {self.stats['hdr_found']:,}")
        print(f"  • Errors:             {self.stats['errors']:,}")
        print(f"Time elapsed:           {timedelta(seconds=int(elapsed))}")
        
        # Show error details if any
        if self.error_files:
            print()
            print("⚠️  Errors encountered:")
            for filepath, error_msg in self.error_files:
                print(f"  • {filepath}")
                print(f"    └─ {error_msg}")
        
        print()
        
        # Get database stats
        db_stats = self.db.get_statistics()
        print(f"Database statistics:")
        print(f"  • Total entries:      {db_stats.get('total_files', 0):,}")
        
        if 'by_action' in db_stats and db_stats['by_action']:
            print(f"\nBy action:")
            for action, count in sorted(db_stats['by_action'].items(), key=lambda x: x[1], reverse=True):
                if action:
                    print(f"  • {action:25} {count:,}")
        
        if 'by_resolution' in db_stats and db_stats['by_resolution']:
            print(f"\nTop resolutions:")
            for resolution, count in list(db_stats['by_resolution'].items())[:5]:
                print(f"  • {resolution:15} {count:,}")
        
        print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description='Build and update Mediabox media metadata database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Scan movie and TV libraries
  %(prog)s --scan /Storage/media/movies /Storage/media/tv
  
  # Re-scan to find new files
  %(prog)s --scan /Storage/media/movies
  
  # Force re-probe all files
  %(prog)s --scan /Storage/media/movies --force
  
  # Show database statistics
  %(prog)s --stats

  # Clean up deleted files
  %(prog)s --cleanup

  # Migrate cache to new format (remove legacy fields, verify hashes)
  %(prog)s --migrate /Storage/media/tv /Storage/media/movies /Storage/media/music
        """
    )

    parser.add_argument('--scan', nargs='+', metavar='DIR',
                       help='Scan directories for media files')
    parser.add_argument('--force', action='store_true',
                       help='Force re-probe all files (ignore cache)')
    parser.add_argument('--stats', nargs='*', metavar='DIR',
                       help='Show cache statistics for directories (uses scanned dirs if none specified)')
    parser.add_argument('--cleanup', nargs='*', metavar='DIR',
                       help='Remove cache entries for deleted files (uses scanned dirs if none specified)')
    parser.add_argument('--migrate', nargs='+', metavar='DIR',
                       help='Migrate cache files: remove stale entries, remove legacy fields (file_path, action), verify hashes')
    parser.add_argument('--db', metavar='PATH',
                       help='Database file path (ignored for JSON backend, kept for compatibility)')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Verbose output (show every file)')

    args = parser.parse_args()

    # Allow --stats and --cleanup to be flags without arguments
    show_stats = args.stats is not None
    do_cleanup = args.cleanup is not None
    do_migrate = args.migrate is not None

    if not any([args.scan, show_stats, do_cleanup, do_migrate]):
        parser.print_help()
        sys.exit(1)
    
    # Create scanner
    scanner = MediaScanner(db_path=args.db, verbose=args.verbose)
    
    try:
        # Scan first if requested
        if args.scan:
            scanner.scan_directories(args.scan, force_rescan=args.force)
        
        # Determine directories for cleanup/stats
        # Use explicitly specified directories, or fall back to scanned directories
        cleanup_dirs = args.cleanup if args.cleanup else []
        stats_dirs = args.stats if args.stats else []
        
        # If no directories specified but we scanned something, use those
        if do_cleanup and not cleanup_dirs and scanner.scanned_directories:
            cleanup_dirs = scanner.scanned_directories
        if show_stats and not stats_dirs and scanner.scanned_directories:
            stats_dirs = scanner.scanned_directories
        
        # Cleanup if requested
        if do_cleanup:
            if cleanup_dirs:
                print("🧹 Cleaning up cache entries for missing files...")
                result = scanner.db.cleanup_all_directories(cleanup_dirs)
                print(f"   Directories cleaned: {result['directories_cleaned']}")
                print(f"   Stale entries removed: {result['total_removed']}")
                print()
            else:
                print("⚠️  No directories specified for cleanup")
                print()

        # Migrate if requested
        if do_migrate:
            print("🔄 Migrating cache files to new format...")
            print("   - Removing stale entries (files that no longer exist or changed)")
            print("   - Removing legacy fields (file_path, action)")
            print()
            result = scanner.db.migrate_cache(args.migrate)
            print(f"   Directories processed: {result['directories_processed']}")
            print(f"   Entries migrated (legacy fields removed): {result['entries_migrated']}")
            print(f"   Entries removed (file missing or changed): {result['entries_removed']}")
            if result['errors'] > 0:
                print(f"   Errors: {result['errors']}")
            print()

        # Show stats if requested
        if show_stats:
            if stats_dirs:
                print("📊 Cache Statistics")
                print("=" * 60)
                stats = scanner.db.get_statistics(stats_dirs)
                
                print(f"Total cached files: {stats.get('total_files', 0):,}")
                print()
                
                if 'by_action' in stats and stats['by_action']:
                    print("By action:")
                    for action, count in sorted(stats['by_action'].items(), key=lambda x: x[1], reverse=True):
                        if action:
                            print(f"  {action:30} {count:,}")
                    print()
                
                if 'by_resolution' in stats and stats['by_resolution']:
                    print("Top resolutions:")
                    for resolution, count in list(stats['by_resolution'].items())[:10]:
                        print(f"  {resolution:15} {count:,}")
                    print()
                
                if 'by_codec_video' in stats and stats['by_codec_video']:
                    print("Top video codecs:")
                    for codec, count in list(stats['by_codec_video'].items())[:10]:
                        print(f"  {codec:15} {count:,}")
                    print()
                
                if 'by_codec_audio' in stats and stats['by_codec_audio']:
                    print("Top audio codecs:")
                    for codec, count in list(stats['by_codec_audio'].items())[:10]:
                        print(f"  {codec:15} {count:,}")
                    print()
                
                print(f"HDR files: {stats.get('hdr_files', 0):,}")
                print("=" * 60)
            else:
                print("⚠️  No directories specified for statistics")
                print()
    
    finally:
        scanner.db.close()


if __name__ == '__main__':
    main()
