#!/usr/bin/env python3
import sys
import os

# Ensure venv packages are available even if not activated
venv_path = "/Storage/docker/mediabox/.venv"  # This line will be updated by mediabox.sh
site_packages = os.path.join(
    venv_path, "lib", f"python{sys.version_info.major}.{sys.version_info.minor}", "site-packages"
)
if site_packages not in sys.path:
    sys.path.insert(0, site_packages)

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

def get_video_files(root_dir):
    video_exts = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv')
    files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith(video_exts):
                files.append(os.path.join(dirpath, filename))
    return files

def build_ffmpeg_command(input_file, output_file):
    try:
        probe = ffmpeg.probe(input_file)
    except ffmpeg.Error as e:
        print("ffprobe error:", e.stderr.decode())
        logging.error(f"ffprobe error for {input_file}: {e.stderr.decode()}")
        raise
    audio_streams = []
    surround_idx = None
    surround_channels = 0
    subtitle_maps = []
    subtitle_codecs = []
    eng_subs = []
    forced_subs = []

    # Find surround sound audio stream (5.1 or more channels)
    for stream in probe['streams']:
        if stream['codec_type'] == 'audio':
            channels = int(stream.get('channels', 0))
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            if channels >= 6 and surround_idx is None:
                surround_idx = idx
                surround_channels = channels
        elif stream['codec_type'] == 'subtitle':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            disposition = stream.get('disposition', {})
            if disposition.get('forced', 0) == 1:
                forced_subs.append(idx)
            if lang == 'eng':
                eng_subs.append(idx)

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

    # Subtitle mapping (forced and English)
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
    print(f"Transcoding: {input_file} -> {output_file}")
    args = build_ffmpeg_command(input_file, output_file)
    cmd = ['ffmpeg', '-i', input_file] + args + [output_file]
    logging.info(f"Transcoding: {input_file} -> {output_file}")
    logging.info("Command: " + " ".join(cmd))
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        logging.info("ffmpeg output:\n" + result.stdout)
        logging.info("ffmpeg errors:\n" + result.stderr)
        if result.returncode == 0:
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