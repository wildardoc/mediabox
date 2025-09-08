#!/usr/bin/env python3
"""
Media Conversion Cleanup Script

This script scans the media library for files with multiple extensions (original + converted),
validates the converted files using ffprobe, and safely removes either the source or 
converted file based on validation results.

Features:
- Finds duplicate files (e.g., movie.mkv + movie.mp4)
- Uses ffprobe to validate converted files
- Compares runtime, resolution, and checks for errors
- Safe dry-run mode by default
- Comprehensive logging
- Permission-aware file removal
"""

import os
import sys
import json
import logging
import argparse
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from datetime import datetime

# Configure logging
def setup_logging(log_level: str = "INFO") -> None:
    """Setup logging configuration"""
    log_filename = f"cleanup_conversions_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    
    logging.basicConfig(
        level=getattr(logging, log_level.upper()),
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_filename),
            logging.StreamHandler(sys.stdout)
        ]
    )
    logging.info(f"Logging to: {log_filename}")

class MediaValidator:
    """Validates media files using ffprobe"""
    
    def __init__(self):
        self.ffprobe_cmd = "ffprobe"
    
    def get_media_info(self, file_path: str) -> Optional[Dict]:
        """Get media information using ffprobe"""
        try:
            cmd = [
                self.ffprobe_cmd,
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                "-show_error",
                file_path
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                logging.error(f"ffprobe failed for {file_path}: {result.stderr}")
                return None
            
            return json.loads(result.stdout)
            
        except subprocess.TimeoutExpired:
            logging.error(f"ffprobe timeout for {file_path}")
            return None
        except json.JSONDecodeError as e:
            logging.error(f"JSON decode error for {file_path}: {e}")
            return None
        except Exception as e:
            logging.error(f"Error probing {file_path}: {e}")
            return None
    
    def validate_conversion(self, original_path: str, converted_path: str) -> Tuple[bool, str]:
        """
        Validate that a conversion was successful
        Returns: (is_valid, reason)
        """
        original_info = self.get_media_info(original_path)
        converted_info = self.get_media_info(converted_path)
        
        if not original_info:
            return False, "Could not probe original file"
        
        if not converted_info:
            return False, "Could not probe converted file"
        
        # Check for errors in converted file
        if "error" in converted_info and converted_info["error"]:
            return False, f"Converted file has errors: {converted_info['error']}"
        
        # Get format information
        orig_format = original_info.get("format", {})
        conv_format = converted_info.get("format", {})
        
        # Check if converted file has duration
        orig_duration = float(orig_format.get("duration", 0))
        conv_duration = float(conv_format.get("duration", 0))
        
        if conv_duration == 0:
            return False, "Converted file has no duration"
        
        # Duration should be within 5% of original (allowing for slight differences)
        duration_diff = abs(orig_duration - conv_duration) / orig_duration if orig_duration > 0 else 1
        if duration_diff > 0.05:  # 5% tolerance
            return False, f"Duration mismatch: {orig_duration:.1f}s vs {conv_duration:.1f}s ({duration_diff*100:.1f}% diff)"
        
        # Check video streams
        orig_video = [s for s in original_info.get("streams", []) if s.get("codec_type") == "video"]
        conv_video = [s for s in converted_info.get("streams", []) if s.get("codec_type") == "video"]
        
        if not conv_video:
            return False, "Converted file has no video stream"
        
        if orig_video and conv_video:
            orig_v = orig_video[0]
            conv_v = conv_video[0]
            
            # Check resolution (should be same or smaller)
            orig_width = int(orig_v.get("width", 0))
            orig_height = int(orig_v.get("height", 0))
            conv_width = int(conv_v.get("width", 0))
            conv_height = int(conv_v.get("height", 0))
            
            if conv_width == 0 or conv_height == 0:
                return False, "Converted file has invalid resolution"
            
            # Resolution should not be larger than original
            if conv_width > orig_width or conv_height > orig_height:
                return False, f"Converted resolution larger than original: {conv_width}x{conv_height} vs {orig_width}x{orig_height}"
        
        # Check file size - converted should not be 0 bytes
        conv_size = int(conv_format.get("size", 0))
        if conv_size == 0:
            return False, "Converted file is 0 bytes"
        
        # Check for minimum reasonable file size (at least 1MB)
        if conv_size < 1024 * 1024:
            return False, f"Converted file too small: {conv_size} bytes"
        
        logging.info(f"Validation passed: {os.path.basename(converted_path)} "
                    f"({conv_duration:.1f}s, {conv_width}x{conv_height}, {conv_size/1024/1024:.1f}MB)")
        
        return True, "Conversion validated successfully"

class ConversionCleanup:
    """Main cleanup class"""
    
    def __init__(self, media_dirs: List[str], dry_run: bool = True):
        self.media_dirs = media_dirs
        self.dry_run = dry_run
        self.validator = MediaValidator()
        
        # Common video extensions
        self.source_extensions = {'.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.ts'}
        self.target_extension = '.mp4'
        
        # Statistics
        self.stats = {
            'files_scanned': 0,
            'pairs_found': 0,
            'valid_conversions': 0,
            'invalid_conversions': 0,
            'source_files_removed': 0,
            'converted_files_removed': 0,
            'errors': 0
        }
    
    def find_conversion_pairs(self) -> List[Tuple[str, str]]:
        """Find pairs of original and converted files"""
        pairs = []
        
        for media_dir in self.media_dirs:
            if not os.path.exists(media_dir):
                logging.warning(f"Media directory does not exist: {media_dir}")
                continue
            
            logging.info(f"Scanning directory: {media_dir}")
            
            for root, dirs, files in os.walk(media_dir):
                # Create a map of base filenames to full paths
                file_map = {}
                for file in files:
                    file_path = os.path.join(root, file)
                    file_ext = Path(file).suffix.lower()
                    base_name = Path(file).stem
                    
                    self.stats['files_scanned'] += 1
                    
                    if file_ext in self.source_extensions or file_ext == self.target_extension:
                        if base_name not in file_map:
                            file_map[base_name] = {}
                        file_map[base_name][file_ext] = file_path
                
                # Find pairs
                for base_name, extensions in file_map.items():
                    if self.target_extension in extensions:
                        # Find any source extension that pairs with this mp4
                        for ext in self.source_extensions:
                            if ext in extensions:
                                source_path = extensions[ext]
                                converted_path = extensions[self.target_extension]
                                pairs.append((source_path, converted_path))
                                self.stats['pairs_found'] += 1
                                logging.info(f"Found pair: {os.path.basename(source_path)} -> {os.path.basename(converted_path)}")
                                break  # Only take the first matching source extension
        
        return pairs
    
    def safe_remove_file(self, file_path: str) -> bool:
        """Safely remove a file with permission handling"""
        try:
            if self.dry_run:
                logging.info(f"[DRY RUN] Would remove: {file_path}")
                return True
            
            # Check if we can remove the file
            if not os.access(file_path, os.W_OK):
                logging.warning(f"No write permission for: {file_path}")
                # Try to change permissions if we own the file
                try:
                    os.chmod(file_path, 0o666)
                    logging.info(f"Changed permissions for: {file_path}")
                except PermissionError:
                    logging.error(f"Cannot change permissions for: {file_path}")
                    return False
            
            os.remove(file_path)
            logging.info(f"Removed: {file_path}")
            return True
            
        except Exception as e:
            logging.error(f"Error removing {file_path}: {e}")
            return False
    
    def process_conversion_pair(self, source_path: str, converted_path: str) -> None:
        """Process a single conversion pair"""
        logging.info(f"\nProcessing pair:")
        logging.info(f"  Source: {source_path}")
        logging.info(f"  Converted: {converted_path}")
        
        # Get file sizes for comparison
        try:
            source_size = os.path.getsize(source_path)
            converted_size = os.path.getsize(converted_path)
            
            logging.info(f"  Sizes: {source_size/1024/1024:.1f}MB -> {converted_size/1024/1024:.1f}MB "
                        f"({(converted_size/source_size)*100:.1f}% of original)")
        except OSError as e:
            logging.error(f"Error getting file sizes: {e}")
            self.stats['errors'] += 1
            return
        
        # Validate the conversion
        is_valid, reason = self.validator.validate_conversion(source_path, converted_path)
        
        if is_valid:
            logging.info(f"  ✅ Conversion valid: {reason}")
            self.stats['valid_conversions'] += 1
            
            # Remove source file
            if self.safe_remove_file(source_path):
                self.stats['source_files_removed'] += 1
            else:
                self.stats['errors'] += 1
                
        else:
            logging.warning(f"  ❌ Conversion invalid: {reason}")
            self.stats['invalid_conversions'] += 1
            
            # Remove converted file (it's bad)
            if self.safe_remove_file(converted_path):
                self.stats['converted_files_removed'] += 1
            else:
                self.stats['errors'] += 1
    
    def run(self) -> None:
        """Run the cleanup process"""
        logging.info("Starting media conversion cleanup")
        logging.info(f"Mode: {'DRY RUN' if self.dry_run else 'LIVE'}")
        logging.info(f"Media directories: {self.media_dirs}")
        
        # Find all conversion pairs
        pairs = self.find_conversion_pairs()
        
        if not pairs:
            logging.info("No conversion pairs found")
            return
        
        logging.info(f"Found {len(pairs)} conversion pairs to process")
        
        # Process each pair
        for i, (source_path, converted_path) in enumerate(pairs, 1):
            logging.info(f"\n--- Processing pair {i}/{len(pairs)} ---")
            try:
                self.process_conversion_pair(source_path, converted_path)
            except Exception as e:
                logging.error(f"Error processing pair {i}: {e}")
                self.stats['errors'] += 1
        
        # Print final statistics
        self.print_statistics()
    
    def print_statistics(self) -> None:
        """Print final statistics"""
        logging.info("\n" + "="*50)
        logging.info("CLEANUP STATISTICS")
        logging.info("="*50)
        logging.info(f"Files scanned: {self.stats['files_scanned']}")
        logging.info(f"Conversion pairs found: {self.stats['pairs_found']}")
        logging.info(f"Valid conversions: {self.stats['valid_conversions']}")
        logging.info(f"Invalid conversions: {self.stats['invalid_conversions']}")
        logging.info(f"Source files removed: {self.stats['source_files_removed']}")
        logging.info(f"Converted files removed: {self.stats['converted_files_removed']}")
        logging.info(f"Errors encountered: {self.stats['errors']}")
        logging.info("="*50)

def main():
    parser = argparse.ArgumentParser(description="Clean up media conversion duplicates")
    parser.add_argument('--dirs', nargs='+', 
                       default=['/Storage/media/movies', '/Storage/media/tv', '/Storage/media/music'],
                       help='Media directories to scan')
    parser.add_argument('--live', action='store_true',
                       help='Actually remove files (default is dry-run)')
    parser.add_argument('--log-level', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                       default='INFO', help='Log level')
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(args.log_level)
    
    # Validate directories
    valid_dirs = []
    for dir_path in args.dirs:
        if os.path.exists(dir_path):
            valid_dirs.append(dir_path)
        else:
            logging.warning(f"Directory does not exist: {dir_path}")
    
    if not valid_dirs:
        logging.error("No valid directories to scan")
        sys.exit(1)
    
    # Create and run cleanup
    cleanup = ConversionCleanup(valid_dirs, dry_run=not args.live)
    
    try:
        cleanup.run()
    except KeyboardInterrupt:
        logging.info("Cleanup interrupted by user")
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
