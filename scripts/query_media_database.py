#!/usr/bin/env python3
"""
Mediabox Media Database Query Tool
===================================

Query and report on media database contents.
Provides powerful filtering and analysis of cached metadata.

USAGE:
------
# List all HDR files
python3 query_media_database.py --hdr

# Find files needing conversion
python3 query_media_database.py --needs-conversion

# Show files by action
python3 query_media_database.py --by-action

# Search for specific files
python3 query_media_database.py --search "Breaking Bad"

# Show 4K files
python3 query_media_database.py --resolution 3840x2160

# Export conversion queue
python3 query_media_database.py --needs-conversion --export queue.txt

# Show recent processing history
python3 query_media_database.py --history --days 7

FEATURES:
---------
• Filter by HDR, resolution, codec, action needed
• Search by filename/path
• Processing history tracking
• Export results to file
• JSON output for scripting
"""

import os
import sys
import argparse
import json
from datetime import datetime, timedelta
from pathlib import Path

# Add script directory to Python path for imports
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from media_database import MediaDatabase


class MediaQueryTool:
    """Query and analyze media database"""
    
    def __init__(self, db_path=None):
        self.db = MediaDatabase(db_path)
    
    def query_hdr_files(self):
        """List all HDR files"""
        results = self.db.query_by_filter(is_hdr=True)
        
        if not results:
            print("No HDR files found in database")
            return []
        
        print(f"🎬 HDR Files ({len(results)} total)")
        print("=" * 80)
        
        for row in results:
            path = row.get('file_path', 'Unknown')  # Changed from 'path' to 'file_path'
            resolution = row.get('resolution', 'Unknown')
            color_transfer = row.get('color_transfer', 'Unknown')
            action = row.get('action', 'Unknown')
            
            print(f"📁 {path}")
            print(f"   Resolution: {resolution}")
            print(f"   Transfer:   {color_transfer}")
            print(f"   Action:     {action}")
            print()
        
        return results
    
    def query_needs_conversion(self):
        """List files needing conversion"""
        results = self.db.conn.execute("""
            SELECT path, action, resolution, video_codec, audio_codec, file_size_bytes
            FROM media_cache
            WHERE action NOT IN ('skip', '')
            ORDER BY file_size_bytes DESC
        """).fetchall()
        
        if not results:
            print("✅ No files need conversion")
            return []
        
        print(f"🔄 Files Needing Conversion ({len(results)} total)")
        print("=" * 80)
        
        # Group by action
        by_action = {}
        for row in results:
            action = row['action']
            if action not in by_action:
                by_action[action] = []
            by_action[action].append(row)
        
        total_size = sum(row['file_size_bytes'] or 0 for row in results)
        print(f"Total size: {self._format_size(total_size)}")
        print()
        
        for action, files in sorted(by_action.items()):
            print(f"\n{action} ({len(files)} files):")
            print("-" * 80)
            
            for row in files[:10]:  # Limit to 10 per category
                path = row['file_path']
                resolution = row['resolution'] or 'Unknown'
                vcodec = row['video_codec'] or 'N/A'
                acodec = row['audio_codec'] or 'N/A'
                size = self._format_size(row['file_size_bytes'] or 0)
                
                print(f"  {Path(path).name}")
                print(f"    Path:       {path}")
                print(f"    Resolution: {resolution} | Video: {vcodec} | Audio: {acodec} | Size: {size}")
            
            if len(files) > 10:
                print(f"  ... and {len(files) - 10} more")
        
        return results
    
    def query_by_action(self, action=None):
        """Group files by action"""
        if action:
            results = self.db.query_by_filter(action=action)
        else:
            results = self.db.conn.execute("""
                SELECT action, COUNT(*) as count, SUM(file_size_bytes) as total_size
                FROM media_cache
                GROUP BY action
                ORDER BY count DESC
            """).fetchall()
        
        if not results:
            print("No results found")
            return []
        
        if action:
            # Specific action query
            print(f"📋 Files with action: {action} ({len(results)} total)")
            print("=" * 80)
            
            for row in results:
                print(f"📁 {row['file_path']}")
                if row.get('resolution'):
                    print(f"   {row['resolution']} | {row.get('video_codec', 'N/A')}")
                print()
        else:
            # Summary by action
            print(f"📊 Files Grouped by Action")
            print("=" * 80)
            
            for row in results:
                action = row['action'] or '(none)'
                count = row['count']
                size = self._format_size(row['total_size'] or 0)
                
                print(f"{action:35} {count:6,} files | {size:>10}")
        
        return results
    
    def query_by_resolution(self, resolution=None):
        """Query files by resolution"""
        if resolution:
            results = self.db.query_by_filter(resolution=resolution)
            
            if not results:
                print(f"No files found with resolution: {resolution}")
                return []
            
            print(f"📺 Files at {resolution} ({len(results)} total)")
            print("=" * 80)
            
            for row in results:
                print(f"📁 {row['file_path']}")
                print(f"   Codec: {row.get('video_codec', 'Unknown')}")
                print(f"   Action: {row.get('action', 'Unknown')}")
                print()
        else:
            # Summary by resolution
            results = self.db.conn.execute("""
                SELECT resolution, COUNT(*) as count, SUM(file_size_bytes) as total_size
                FROM media_cache
                WHERE resolution IS NOT NULL AND resolution != ''
                GROUP BY resolution
                ORDER BY count DESC
            """).fetchall()
            
            print(f"📺 Files Grouped by Resolution")
            print("=" * 80)
            
            for row in results:
                res = row['resolution']
                count = row['count']
                size = self._format_size(row['total_size'] or 0)
                
                print(f"{res:15} {count:6,} files | {size:>10}")
        
        return results
    
    def search(self, query_str):
        """Search for files by path/name"""
        results = self.db.conn.execute("""
            SELECT * FROM media_cache
            WHERE path LIKE ?
            ORDER BY path
        """, (f'%{query_str}%',)).fetchall()
        
        if not results:
            print(f"No files found matching: {query_str}")
            return []
        
        print(f"🔍 Search Results for '{query_str}' ({len(results)} found)")
        print("=" * 80)
        
        for row in results:
            path = row['file_path']
            resolution = row['resolution'] or 'Unknown'
            action = row['action'] or 'skip'
            is_hdr = row['is_hdr']
            
            hdr_tag = " [HDR]" if is_hdr else ""
            
            print(f"📁 {path}")
            print(f"   {resolution} | {action}{hdr_tag}")
            print()
        
        return results
    
    def show_history(self, days=30):
        """Show recent processing history"""
        cutoff = datetime.now() - timedelta(days=days)
        
        results = self.db.conn.execute("""
            SELECT * FROM processing_log
            WHERE processed_at >= ?
            ORDER BY processed_at DESC
        """, (cutoff,)).fetchall()
        
        if not results:
            print(f"No processing history in the last {days} days")
            return []
        
        print(f"📜 Processing History (last {days} days) - {len(results)} items")
        print("=" * 80)
        
        for row in results:
            timestamp = row['processed_at']
            path = row['file_path']
            action = row['action']
            success = row['success']
            
            status = "✅" if success else "❌"
            
            print(f"{status} {timestamp} - {action}")
            print(f"   {path}")
            if row['notes']:
                print(f"   Notes: {row['notes']}")
            print()
        
        return results
    
    def export_results(self, results, output_file):
        """Export results to file"""
        if not results:
            print("No results to export")
            return
        
        try:
            with open(output_file, 'w') as f:
                for row in results:
                    if isinstance(row, dict):
                        path = row.get('file_path', '')
                    else:
                        path = row['file_path'] if 'path' in row.keys() else ''
                    
                    if path:
                        f.write(f"{path}\n")
            
            print(f"✅ Exported {len(results)} paths to: {output_file}")
        except Exception as e:
            print(f"❌ Error exporting results: {e}")
    
    def export_json(self, results, output_file):
        """Export results as JSON"""
        if not results:
            print("No results to export")
            return
        
        try:
            # Convert sqlite3.Row objects to dicts
            data = []
            for row in results:
                if isinstance(row, dict):
                    data.append(row)
                else:
                    data.append(dict(zip(row.keys(), row)))
            
            with open(output_file, 'w') as f:
                json.dump(data, f, indent=2, default=str)
            
            print(f"✅ Exported {len(results)} entries to: {output_file}")
        except Exception as e:
            print(f"❌ Error exporting JSON: {e}")
    
    @staticmethod
    def _format_size(size_bytes):
        """Format bytes as human-readable size"""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f} PB"


def main():
    parser = argparse.ArgumentParser(
        description='Query Mediabox media metadata database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Show all HDR files
  %(prog)s --hdr
  
  # Find files needing conversion
  %(prog)s --needs-conversion
  
  # Search for a show
  %(prog)s --search "Breaking Bad"
  
  # Show 4K files
  %(prog)s --resolution 3840x2160
  
  # Export conversion queue
  %(prog)s --needs-conversion --export queue.txt
  
  # Show statistics
  %(prog)s --stats
        """
    )
    
    parser.add_argument('--hdr', action='store_true',
                       help='List all HDR files')
    parser.add_argument('--needs-conversion', action='store_true',
                       help='List files needing conversion')
    parser.add_argument('--by-action', metavar='ACTION',
                       help='Show files by action (or summary if no action specified)', nargs='?', const='')
    parser.add_argument('--resolution', metavar='RES',
                       help='Filter by resolution (e.g., 3840x2160) or show summary')
    parser.add_argument('--search', metavar='QUERY',
                       help='Search for files by path/name')
    parser.add_argument('--history', action='store_true',
                       help='Show processing history')
    parser.add_argument('--days', type=int, default=30,
                       help='Days of history to show (default: 30)')
    parser.add_argument('--stats', action='store_true',
                       help='Show database statistics')
    parser.add_argument('--export', metavar='FILE',
                       help='Export results (paths only) to file')
    parser.add_argument('--export-json', metavar='FILE',
                       help='Export results as JSON to file')
    parser.add_argument('--db', metavar='PATH',
                       help='Database file path (default: ~/.local/share/mediabox/media_cache.db)')
    
    args = parser.parse_args()
    
    if not any([args.hdr, args.needs_conversion, args.by_action is not None, 
                args.resolution, args.search, args.history, args.stats]):
        parser.print_help()
        sys.exit(1)
    
    # Create query tool
    tool = MediaQueryTool(db_path=args.db)
    
    try:
        results = []
        
        if args.hdr:
            results = tool.query_hdr_files()
        
        if args.needs_conversion:
            results = tool.query_needs_conversion()
        
        if args.by_action is not None:
            action = args.by_action if args.by_action else None
            results = tool.query_by_action(action)
        
        if args.resolution is not None:
            results = tool.query_by_resolution(args.resolution if args.resolution else None)
        
        if args.search:
            results = tool.search(args.search)
        
        if args.history:
            results = tool.show_history(args.days)
        
        if args.stats:
            print("📊 Database Statistics")
            print("=" * 80)
            stats = tool.db.get_statistics()
            
            print(f"Total files: {stats.get('total_files', 0):,}")
            print()
            
            if 'by_action' in stats and stats['by_action']:
                print("By action:")
                for action, count in sorted(stats['by_action'].items(), key=lambda x: x[1], reverse=True):
                    if action:
                        print(f"  {action:30} {count:,}")
                print()
            
            if 'by_resolution' in stats and stats['by_resolution']:
                print("Top resolutions:")
                for resolution, count in list(sorted(stats['by_resolution'].items(), 
                                                    key=lambda x: x[1], reverse=True))[:10]:
                    print(f"  {resolution:15} {count:,}")
                print()
            
            if 'by_codec' in stats and stats['by_codec']:
                print("Video codecs:")
                for codec, count in sorted(stats['by_codec'].items(), key=lambda x: x[1], reverse=True):
                    print(f"  {codec:15} {count:,}")
                print()
            
            print(f"HDR files: {stats.get('hdr_files', 0):,}")
            print("=" * 80)
        
        # Export if requested
        if args.export and results:
            tool.export_results(results, args.export)
        
        if args.export_json and results:
            tool.export_json(results, args.export_json)
    
    finally:
        tool.db.close()


if __name__ == '__main__':
    main()
