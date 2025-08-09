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
            if filename.lower().endswith(video_exts):
                files.append(os.path.join(dirpath, filename))
    return files

def get_audio_files(root_dir):
    audio_exts = ('.flac', '.wav', '.aiff', '.ape', '.wv', '.m4a', '.ogg', '.opus', '.wma')
    files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith(audio_exts):
                # Skip already converted MP3 files
                if not filename.lower().endswith('.mp3'):
                    files.append(os.path.join(dirpath, filename))
    return files

def get_media_files(root_dir, media_type='both'):
    """Get media files based on type: 'video', 'audio', or 'both'."""
    if media_type == 'video':
        return get_video_files(root_dir)
    elif media_type == 'audio':
        return get_audio_files(root_dir)
    else:  # both
        return get_video_files(root_dir) + get_audio_files(root_dir)

def extract_pgs_subtitles(input_file, probe):
    """Extract PGS subtitles as separate .sup files"""        
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
    subtitle_stream_counter = 0
    audio_stream_counter = 0
    for stream in probe['streams']:
        if stream['codec_type'] == 'audio':
            idx = stream['index']
            lang = stream.get('tags', {}).get('language', '').lower()
            if not lang:
                audio_lang_metadata.extend(['-metadata:s:a:' + str(audio_stream_counter), 'language=eng'])
            channels = int(stream.get('channels', 0))
            if channels >= 6:
                surround_candidates.append((idx, lang))
            audio_stream_counter += 1
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
            surround_idx, _ = surround_candidates[0]

    # Audio mapping
    audio_maps = []
    audio_labels = []
    filter_complex = []
    if surround_idx is not None:
        # Map surround channel and label
        audio_maps += ['-map', f'0:{surround_idx}']
        audio_labels += ['-metadata:s:a:0', 'title=Surround']
        # Create stereo from surround with compression
        filter_complex = [
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
        *filter_complex,
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

    # Audio conversion settings
    args = [
        '-c:a', 'libmp3lame',  # Use LAME MP3 encoder
        '-b:a', '320k',        # 320kbps bitrate for high quality
        '-f', 'mp3',           # Force MP3 format
        '-y'                   # Overwrite output
    ]
    
    # Preserve metadata if available
    for stream in probe.get('streams', []):
        if stream['codec_type'] == 'audio':
            # Copy common audio metadata
            break
    
    # Copy metadata tags
    args.extend(['-map_metadata', '0'])
    
    return args

def transcode_file(input_file):
    # Determine if this is a video or audio file
    video_exts = ('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv')
    audio_exts = ('.flac', '.wav', '.aiff', '.ape', '.wv', '.m4a', '.ogg', '.opus', '.wma')
    
    is_video = input_file.lower().endswith(video_exts)
    is_audio = input_file.lower().endswith(audio_exts)
    
    if not is_video and not is_audio:
        logging.warning(f"Unsupported file format: {input_file}")
        print(f"Unsupported file format: {input_file}")
        return
    
    base, ext = os.path.splitext(input_file)
    
    # Determine target format and extension
    if is_video:
        target_ext = '.mp4'
    else:  # is_audio
        target_ext = '.mp3'
    
    final_output_file = base + target_ext
    
    # Use temp file if transcoding in place, otherwise use final name directly
    if input_file.lower() == final_output_file.lower():
        temp_output_file = base + '.tmp' + target_ext
        output_file = temp_output_file
    else:
        output_file = final_output_file
    
    global unfinished_output_file
    unfinished_output_file = output_file

    # Check if conversion is needed
    try:
        probe = ffmpeg.probe(input_file)
        
        if is_video:
            # Video file logic (existing)
            vcodec = next((s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'video'), None)
            audio_codecs = [s['codec_name'] for s in probe['streams'] if s['codec_type'] == 'audio']
            all_aac = all(codec == 'aac' for codec in audio_codecs) if audio_codecs else True
            
            # Check if we have surround sound but missing stereo track
            has_surround = False
            has_stereo = False
            for stream in probe['streams']:
                if stream['codec_type'] == 'audio':
                    channels = int(stream.get('channels', 0))
                    if channels >= 6:
                        has_surround = True
                    elif channels == 2:
                        has_stereo = True
            
            # If we have surround but no stereo, we need to transcode to add compressed stereo
            needs_stereo_track = has_surround and not has_stereo
            
            if vcodec == 'h264' and all_aac and input_file.lower().endswith('.mp4') and not needs_stereo_track:
                print(f"Skipping: {input_file} is already H.264/AAC MP4.")
                logging.info(f"Skipping: {input_file} is already H.264/AAC MP4.")
                return
            elif needs_stereo_track:
                print(f"Transcoding: {input_file} has surround sound but missing stereo track.")
                logging.info(f"Transcoding: {input_file} has surround sound but missing stereo track.")
        
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
        args = build_ffmpeg_command(input_file, probe)
    else:  # is_audio
        args = build_audio_ffmpeg_command(input_file, probe)
    
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
            
            # If we used a temp file, move it to the final location
            if output_file != final_output_file:
                try:
                    if os.path.exists(final_output_file):
                        os.remove(final_output_file)  # Remove original before moving temp
                    os.rename(output_file, final_output_file)
                    logging.info(f"Moved temp file to final location: {final_output_file}")
                    print(f"Moved temp file to final location: {final_output_file}")
                except Exception as e:
                    logging.error(f"Failed to move temp file to final location: {e}")
                    print(f"Failed to move temp file to final location: {e}")
                    return
            
            logging.info(f"Success: {final_output_file}")
            print(f"Success: {final_output_file}")
            
            # Only remove source file if it's different from final output file
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

def main():
    parser = argparse.ArgumentParser(description="Transcode media files.")
    parser.add_argument('--dir', type=str, help='Directory to search for media files')
    parser.add_argument('--file', type=str, help='Single media file to convert')
    parser.add_argument('--type', type=str, choices=['video', 'audio', 'both'], default='both', 
                       help='Type of media to process: video, audio, or both (default: both)')
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
            transcode_file(file_path)
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
            transcode_file(f)
        except Exception as e:
            logging.error(f"Error processing {f}: {e}")
            print(f"Error processing {f}: {e}")
    logging.info("Transcoding complete.")
    print("Transcoding complete.")

if __name__ == "__main__":
    main()