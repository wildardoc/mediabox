#!/usr/bin/env python3
import sys
import os
import atexit
import signal
import json

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "mediabox_config.json")
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

venv_path = config["venv_path"]
DOWNLOAD_DIRS = config["download_dirs"]
MEDIA_LIBRARY_DIRS = config["media_library_dirs"]

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

# Activate the virtual environment
os.environ["VIRTUAL_ENV"] = venv_path
os.environ["PATH"] = os.path.join(venv_path, "bin") + os.pathsep + os.environ.get("PATH", "")

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

def get_video_files(root_dir):
    video_exts = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv')
    files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith(video_exts) and not filename.endswith('_converted.mp4'):
                files.append(os.path.join(dirpath, filename))
    return files

def build_ffmpeg_command(input_file, probe=None):
    """
    Build ffmpeg command-line arguments for transcoding the input file.
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
    audio_lang_metadata = []
    subtitle_lang_metadata = []

    # Find surround sound audio streams and subtitle streams
    for stream in probe['streams']:
        if stream['codec_type'] == 'audio':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            if not lang:
                audio_lang_metadata.append(f'-metadata:s:a:{idx} language=eng')
            channels = int(stream.get('channels', 0))
            if channels >= 6:
                surround_candidates.append((idx, lang))
        elif stream['codec_type'] == 'subtitle':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            codec = stream.get('codec_name', '').lower()
            # Only include text-based subtitles for MP4
            if codec in ('subrip', 'srt', 'ass', 'ssa', 'mov_text'):
                if not lang:
                    subtitle_lang_metadata.append(f'-metadata:s:s:{idx} language=eng')
                disposition = stream.get('disposition', {})
                if disposition.get('forced', 0) == 1:
                    forced_subs.append(idx)
                if lang == 'eng':
                    eng_subs.append(idx)
            elif codec == 'hdmv_pgs_subtitle':
                logging.warning(f"Skipping PGS subtitle stream {idx} for MP4 output: not supported.")

    # Prefer English surround, then unlabeled, else log/print available
    if surround_candidates:
        # Try to find English surround
        for idx, lang in surround_candidates:
            if lang == 'eng':
                surround_idx = idx
                break
        # If not found, try to find one with no language label
        if surround_idx is None:
            for idx, lang in surround_candidates:
                if not lang:
                    surround_idx = idx
                    break
        # If still not found, flag and log all available surround streams
        if surround_idx is None:
            msg = (
                f"No English surround audio found. "
                f"Available surround streams: {[(idx, lang) for idx, lang in surround_candidates]}"
            )
            print(msg)
            logging.warning(msg)
            # Optionally, pick the first surround as fallback
            surround_idx = surround_candidates[0][0]

    # Audio mapping
    audio_maps = []
    audio_labels = []
    if surround_idx is not None:
        # Map surround channel and label
        audio_maps += ['-map', f'0:{surround_idx}']
        audio_labels += ['-metadata:s:a:0', 'title=Surround']
        # Create stereo from surround with compression
        audio_maps += [
            '-filter_complex',
            f'[0:{surround_idx}]pan=stereo|c0=c0+c2+c4|c1=c1+c3+c5,acompressor=level_in=1.5:threshold=0.1:ratio=6:attack=20:release=250[aout]'
        ]
        audio_maps += ['-map', '[aout]']
        audio_labels += ['-metadata:s:a:1', 'title=Stereo (Compressed)']
    else:
        # Fallback: map first audio stream
        for stream in probe['streams']:
            if stream['codec_type'] == 'audio':
                idx = stream['index']
                audio_maps += ['-map', f'0:{idx}']
                audio_labels += ['-metadata:s:a:0', 'title=Stereo']
                break

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

    # Build ffmpeg args
    args = [
        '-map', '0:v:0',  # First video stream
        *audio_maps,
        *audio_labels,
        *subtitle_maps,
        *subtitle_codecs,
        *audio_lang_metadata,
        *subtitle_lang_metadata,
        '-c:v', 'libx264',
        '-crf', '23',
        '-c:a', 'aac',
        '-y',  # Overwrite output
        '-movflags', 'faststart'
    ]
    return args

def transcode_file(input_file):
    base, _ = os.path.splitext(input_file)
    output_file = base + '_converted.mp4'
    global unfinished_output_file
    unfinished_output_file = output_file

    # Skip if output already exists
    if os.path.exists(output_file):
        print(f"Skipping: {output_file} already exists.")
        logging.info(f"Skipping: {output_file} already exists.")
        return

    # Optional: Check if already H.264/AAC MP4
    try:
        probe = ffmpeg.probe(input_file)
        vcodec = next((s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'video'), None)
        audio_codecs = [s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'audio']
        all_aac = all(codec == 'aac' for codec in audio_codecs) if audio_codecs else True
        if vcodec == 'h264' and all_aac and input_file.lower().endswith('.mp4'):
            print(f"Skipping: {input_file} is already H.264/AAC MP4.")
            logging.info(f"Skipping: {input_file} is already H.264/AAC MP4.")
            return
    except ffmpeg.Error as e:
        print(f"ffprobe error for {input_file}: {e.stderr.decode()}")
        logging.warning(f"ffprobe error for {input_file}: {e.stderr.decode()}")
        raise  # <--- This will prevent transcoding invalid files
    except Exception as e:
        print(f"Unexpected error probing {input_file}, will attempt to transcode. Reason: {e}")
        logging.warning(f"Unexpected error probing {input_file}, will attempt to transcode. Reason: {e}")
        probe = None

    print(f"Transcoding: {input_file} -> {output_file}")
    args = build_ffmpeg_command(input_file, probe)
    cmd = ['ffmpeg', '-i', input_file] + args + [output_file]
    logging.info(f"Transcoding: {input_file} -> {output_file}")
    logging.info("Command: " + " ".join(cmd))
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        logging.info("ffmpeg output:\n" + result.stdout)
        logging.info("ffmpeg errors:\n" + result.stderr)
        if result.returncode == 0:
            unfinished_output_file = None
            logging.info(f"Success: {output_file}")
            print(f"Success: {output_file}")
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

def main():
    parser = argparse.ArgumentParser(description="Transcode media files.")
    parser.add_argument('--dir', type=str, help='Directory to search for media files')
    parser.add_argument('--file', type=str, help='Single media file to convert')
    args = parser.parse_args()

    if args.file:
        if not os.path.isfile(args.file):
            logging.error("Invalid file.")
            print("Invalid file.")
            sys.exit(1)
        transcode_file(args.file)
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
        elif choice == 'f':
            file_path = input("Enter the path to the media file: ").strip()
            if not os.path.isfile(file_path):
                logging.error("Invalid file.")
                print("Invalid file.")
                sys.exit(1)
            transcode_file(file_path)
            logging.info("Transcoding complete.")
            print("Transcoding complete.")
            return
        else:
            print("Invalid choice.")
            sys.exit(1)

    files = get_video_files(root_dir)
    if not files:
        logging.info("No video files found.")
        print("No video files found.")
        sys.exit(0)
    print(f"Found {len(files)} video files to process.")
    for idx, f in enumerate(files, 1):
        print(f"[{idx}/{len(files)}] Processing: {f}")
        try:
            transcode_file(f)
        except Exception as e:
            logging.error(f"Error processing {f}: {e}")
            print(f"Error processing {f}: {e}")
    logging.info("Transcoding complete.")
    print("Transcoding complete.")

if __name__ == "__main__":
    main()