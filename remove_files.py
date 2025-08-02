#!/usr/bin/env python3
import sys
import os
import re
import json

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "mediabox_config.json")
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

venv_path = config["venv_path"]
DOWNLOAD_DIRS = config["download_dirs"]
TV_LIBRARY_DIR = config["tv_library_dir"]
MOVIE_LIBRARY_DIR = config["movie_library_dir"]
MUSIC_LIBRARY_DIR = config["music_library_dir"]

site_packages = os.path.join(
    venv_path, "lib", f"python{sys.version_info.major}.{sys.version_info.minor}", "site-packages"
)
if site_packages not in sys.path:
    sys.path.insert(0, site_packages)

os.environ["VIRTUAL_ENV"] = venv_path
os.environ["PATH"] = os.path.join(venv_path, "bin") + os.pathsep + os.environ.get("PATH", "")

import time
import ffmpeg
import logging
import argparse

MEDIA_EXTS = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv',
              '.mp3', '.flac', '.aac', '.ogg', '.wav', '.m4a', '.alac', '.opus')
DAYS_OLD = 7
BITRATE_TOLERANCE = 1000000

def setup_logging(logfile):
    logging.basicConfig(filename=logfile, level=logging.INFO, format='%(asctime)s %(levelname)s:%(message)s')

def get_media_info(filepath):
    try:
        probe = ffmpeg.probe(filepath)
        for stream in probe['streams']:
            if stream['codec_type'] == 'video':
                width = stream.get('width')
                height = stream.get('height')
                bit_rate_value = stream.get('bit_rate', 0)
                try:
                    bitrate = int(bit_rate_value)
                except (ValueError, TypeError):
                    bitrate = 0
                return width, height, bitrate
            elif stream['codec_type'] == 'audio':
                channels = stream.get('channels')
                bit_rate_value = stream.get('bit_rate', 0)
                try:
                    bitrate = int(bit_rate_value)
                except (ValueError, TypeError):
                    bitrate = 0
                return channels, None, bitrate
    except Exception as e:
        logging.warning(f"Could not probe {filepath}: {e}")
    return None, None, None

def is_media_match(lib_info, info_tuple):
    width_or_channels_match = lib_info[0] == info_tuple[0]
    height_match = (lib_info[1] == info_tuple[1] or lib_info[1] is None or info_tuple[1] is None)
    if lib_info[2] is not None and info_tuple[2] is not None:
        try:
            bitrate_match = abs(lib_info[2] - info_tuple[2]) < BITRATE_TOLERANCE
        except TypeError:
            bitrate_match = False
    else:
        bitrate_match = False
    return width_or_channels_match and height_match and bitrate_match

def parse_tv_filename(filename):
    # Example: Show.Name.S01E02.Title.mkv
    match = re.search(r'(?P<series>.+?)\.S(?P<season>\d{2})E(?P<episode>\d{2})', filename, re.IGNORECASE)
    if match:
        return match.group('series').replace('.', ' ').strip(), int(match.group('season')), int(match.group('episode'))
    return None, None, None

def find_library_tv_file(series, season, episode, library_tv_dir):
    # Traverse: /tv/Series Name/Season XX/
    for series_dir in os.listdir(library_tv_dir):
        if series_dir.lower().replace(' ', '') == series.lower().replace(' ', ''):
            season_path = os.path.join(library_tv_dir, series_dir, f"Season {season:02d}")
            if os.path.isdir(season_path):
                for fname in os.listdir(season_path):
                    s, se, ep = parse_tv_filename(fname)
                    if s and se == season and ep == episode:
                        return os.path.join(season_path, fname)
    return None

def get_resolution(filepath):
    try:
        probe = ffmpeg.probe(filepath)
        for stream in probe['streams']:
            if stream['codec_type'] == 'video':
                return int(stream.get('width', 0)), int(stream.get('height', 0))
    except Exception:
        pass
    return 0, 0

def should_delete_tv(file_path, library_tv_dir, dry_run=False):
    filename = os.path.basename(file_path)
    series, season, episode = parse_tv_filename(filename)
    if not series:
        # Not a TV episode, fallback to age check
        mtime = os.path.getmtime(file_path)
        age_days = (time.time() - mtime) / (24 * 3600)
        if age_days > DAYS_OLD:
            print(f"{file_path} is old and not matched. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        return False

    lib_file = find_library_tv_file(series, season, episode, library_tv_dir)
    if lib_file:
        dl_w, dl_h = get_resolution(file_path)
        lib_w, lib_h = get_resolution(lib_file)
        if (dl_w, dl_h) <= (lib_w, lib_h):
            print(f"{file_path} is lower/equal resolution than library copy. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        else:
            print(f"{file_path} is higher resolution than library copy. Manual intervention needed.")
            return False
    else:
        # No match in library, fallback to age check
        mtime = os.path.getmtime(file_path)
        age_days = (time.time() - mtime) / (24 * 3600)
        if age_days > DAYS_OLD:
            print(f"{file_path} is old and not matched. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        return False

def parse_movie_filename(filename):
    # Example: Movie.Name.2022.1080p.mkv
    match = re.match(r'(?P<title>.+?)(?:\.\d{4})?\.', filename)
    if match:
        return match.group('title').replace('.', ' ').strip()
    return None

def find_library_movie_file(movie_title, library_movie_dir):
    for movie_dir in os.listdir(library_movie_dir):
        if movie_dir.lower().replace(' ', '') == movie_title.lower().replace(' ', ''):
            movie_path = os.path.join(library_movie_dir, movie_dir)
            for fname in os.listdir(movie_path):
                return os.path.join(movie_path, fname)
    return None

def parse_music_filename(filename):
    # Example: Artist-Album-Track.mp3 or Artist - Album - Track.mp3
    match = re.match(r'(?P<artist>.+?)[-_ ]+(?P<album>.+?)[-_ ]+(?P<track>.+?)\.', filename)
    if match:
        return match.group('artist').strip(), match.group('album').strip(), match.group('track').strip()
    return None, None, None

def find_library_music_file(artist, album, track, library_music_dir):
    for artist_dir in os.listdir(library_music_dir):
        if artist_dir.lower().replace(' ', '') == artist.lower().replace(' ', ''):
            album_path = os.path.join(library_music_dir, artist_dir, album)
            if os.path.isdir(album_path):
                for fname in os.listdir(album_path):
                    if track.lower().replace(' ', '') in fname.lower().replace(' ', ''):
                        return os.path.join(album_path, fname)
    return None

def should_delete_movie(file_path, library_movie_dir, dry_run=False):
    filename = os.path.basename(file_path)
    movie_title = parse_movie_filename(filename)
    if not movie_title:
        # Not a movie, fallback to age check
        mtime = os.path.getmtime(file_path)
        age_days = (time.time() - mtime) / (24 * 3600)
        if age_days > DAYS_OLD:
            print(f"{file_path} is old and not matched. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        return False

    lib_file = find_library_movie_file(movie_title, library_movie_dir)
    if lib_file:
        dl_w, dl_h = get_resolution(file_path)
        lib_w, lib_h = get_resolution(lib_file)
        if (dl_w, dl_h) <= (lib_w, lib_h):
            print(f"{file_path} is lower/equal resolution than library copy. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        else:
            print(f"{file_path} is higher resolution than library copy. Manual intervention needed.")
            return False
    else:
        mtime = os.path.getmtime(file_path)
        age_days = (time.time() - mtime) / (24 * 3600)
        if age_days > DAYS_OLD:
            print(f"{file_path} is old and not matched. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        return False

def should_delete_music(file_path, library_music_dir, dry_run=False):
    filename = os.path.basename(file_path)
    artist, album, track = parse_music_filename(filename)
    if not artist:
        mtime = os.path.getmtime(file_path)
        age_days = (time.time() - mtime) / (24 * 3600)
        if age_days > DAYS_OLD:
            print(f"{file_path} is old and not matched. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        return False

        dl_info = get_media_info(file_path)
        lib_info = get_media_info(lib_file)
        if dl_info[2] is not None and lib_info[2] is not None:
            if dl_info[2] <= lib_info[2]:  # Compare bitrate
                print(f"{file_path} is lower/equal bitrate than library copy. {'[DRY RUN]' if dry_run else 'Deleting.'}")
                if not dry_run:
                    os.remove(file_path)
                return True
            else:
                print(f"{file_path} is higher bitrate than library copy. Manual intervention needed.")
                return False
        else:
            # If bitrate info is missing, fallback to age-based deletion
            mtime = os.path.getmtime(file_path)
            age_days = (time.time() - mtime) / (24 * 3600)
            if age_days > DAYS_OLD:
                print(f"{file_path} is old and not matched (bitrate unknown). {'[DRY RUN]' if dry_run else 'Deleting.'}")
                if not dry_run:
                    os.remove(file_path)
                return True
            return False
            print(f"{file_path} is higher bitrate than library copy. Manual intervention needed.")
            return False
    else:
        mtime = os.path.getmtime(file_path)
        age_days = (time.time() - mtime) / (24 * 3600)
        if age_days > DAYS_OLD:
            print(f"{file_path} is old and not matched. {'[DRY RUN]' if dry_run else 'Deleting.'}")
            if not dry_run:
                os.remove(file_path)
            return True
        return False

def main():
    parser = argparse.ArgumentParser(description="Remove old or duplicate media files safely.")
    parser.add_argument('--dry-run', action='store_true', help="Simulate deletions without removing files.")
    parser.add_argument('--log-file', default="cleanup_downloads.log", help="Path to the log file.")
    args = parser.parse_args()
    setup_logging(args.log_file)

    tv_library_dir = TV_LIBRARY_DIR
    movie_library_dir = MOVIE_LIBRARY_DIR
    music_library_dir = MUSIC_LIBRARY_DIR

    for download_dir in DOWNLOAD_DIRS:
        for dirpath, _, filenames in os.walk(download_dir):
            for filename in filenames:
                if filename.lower().endswith(MEDIA_EXTS):
                    file_path = os.path.join(dirpath, filename)
                    # Try TV, Movie, Music matching in order
                    if should_delete_tv(file_path, tv_library_dir, dry_run=args.dry_run):
                        continue
                    if should_delete_movie(file_path, movie_library_dir, dry_run=args.dry_run):
                        continue
                    if should_delete_music(file_path, music_library_dir, dry_run=args.dry_run):
                        continue
                    # If not matched, fallback to age-based deletion
                    mtime = os.path.getmtime(file_path)
                    age_days = (time.time() - mtime) / (24 * 3600)
                    if age_days > DAYS_OLD:
                        print(f"{file_path} is old and not matched. {'[DRY RUN]' if args.dry_run else 'Deleting.'}")
                        if not args.dry_run:
                            os.remove(file_path)

if __name__ == "__main__":
    main()
