#!/usr/bin/env python3
"""
Detect BPM + key per mp3, write tags, optionally rename.
Accepts: --folder DIR  or  --file PATH
Streams "PROGRESS: i/n filename" lines to stdout.
"""
import argparse
import os
import re
import shutil
import sys

import librosa
import numpy as np
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, TBPM, TKEY, APIC, error as ID3Error

DONE_PATTERN = re.compile(r"^\d{3}_.+_[a-z0-9]+_\d+\.mp3$", re.IGNORECASE)

CAMELOT = {
    (0,  1): "8B",  (0,  0): "5A",
    (1,  1): "3B",  (1,  0): "12A",
    (2,  1): "10B", (2,  0): "7A",
    (3,  1): "5B",  (3,  0): "2A",
    (4,  1): "12B", (4,  0): "9A",
    (5,  1): "7B",  (5,  0): "4A",
    (6,  1): "2B",  (6,  0): "11A",
    (7,  1): "9B",  (7,  0): "6A",
    (8,  1): "4B",  (8,  0): "1A",
    (9,  1): "11B", (9,  0): "8A",
    (10, 1): "6B",  (10, 0): "3A",
    (11, 1): "1B",  (11, 0): "10A",
}

# Musical notation per (pitch_class, mode) — major=1, minor=0
MUSICAL = {
    (0,  1): "C",   (0,  0): "Cm",
    (1,  1): "Db",  (1,  0): "C#m",
    (2,  1): "D",   (2,  0): "Dm",
    (3,  1): "Eb",  (3,  0): "Ebm",
    (4,  1): "E",   (4,  0): "Em",
    (5,  1): "F",   (5,  0): "Fm",
    (6,  1): "F#",  (6,  0): "F#m",
    (7,  1): "G",   (7,  0): "Gm",
    (8,  1): "Ab",  (8,  0): "Abm",
    (9,  1): "A",   (9,  0): "Am",
    (10, 1): "Bb",  (10, 0): "Bbm",
    (11, 1): "B",   (11, 0): "Bbm" if False else "Bm",
}


def detect_keys_and_bpm(path):
    y, sr = librosa.load(path, sr=22050, mono=True, duration=180)
    tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
    bpm = float(np.atleast_1d(tempo)[0])
    while bpm < 100:
        bpm *= 2
    while bpm > 175:
        bpm /= 2
    bpm = int(round(bpm))

    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    chroma_mean = chroma.mean(axis=1)
    major = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                      2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
    minor = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                      2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
    best_score, best_key, best_mode = -np.inf, 0, 1
    for key in range(12):
        for mode, profile in [(1, major), (0, minor)]:
            score = np.corrcoef(chroma_mean, np.roll(profile, key))[0, 1]
            if score > best_score:
                best_score, best_key, best_mode = score, key, mode
    return CAMELOT[(best_key, best_mode)], MUSICAL[(best_key, best_mode)], bpm


def write_tags(path, bpm, camelot, title=None, artist=None):
    """Write BPM + Key tags. Preserve artwork + existing title/artist if not provided."""
    try:
        audio = MP3(path, ID3=ID3)
    except Exception:
        return
    try:
        audio.add_tags()
    except ID3Error:
        pass

    audio.tags.add(TBPM(encoding=3, text=str(bpm)))
    audio.tags.add(TKEY(encoding=3, text=camelot))
    if title:
        audio.tags.add(TIT2(encoding=3, text=title))
    if artist:
        audio.tags.add(TPE1(encoding=3, text=artist))
    audio.save(v2_version=3)


def slug(s):
    """Sluggify: lowercase, replace spaces/punct with hyphens, collapse repeats.
    Also strips trailing key+bpm patterns and leading NNN- prefix."""
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    # Strip trailing -KEY-BPM (e.g. -bmin-139, -c#m-140, -a-136) — repeat for stacked
    while True:
        new = re.sub(r"-[a-z#]{1,6}-\d{2,3}$", "", s)
        if new == s:
            break
        s = new
    # Strip leading NNN- prefix
    s = re.sub(r"^\d{2,3}-", "", s)
    return s


def build_clean_stem(path, filename):
    """Build canonical stem (title only).
    Strips _KEY_BPM, NNN_ prefix, drops _artist segment, and removes any
    tokens that match the TPE1 artist tag.
    """
    stem = filename[:-4]
    parts = stem.split("_")
    while (len(parts) >= 3
           and parts[-1].isdigit()
           and re.match(r"^[A-Za-z0-9#]{1,6}$", parts[-2])):
        parts = parts[:-2]
    if len(parts) >= 2 and re.match(r"^\d{2,3}$", parts[0]):
        parts = parts[1:]
    title_part = slug(parts[0]) if parts else ""

    # Remove artist tokens if TPE1 known
    try:
        audio = MP3(path, ID3=ID3)
        artist_tag = audio.tags.get("TPE1") if audio.tags else None
        if artist_tag:
            try: artist = artist_tag.text[0]
            except Exception: artist = ""
            if artist:
                artist_tokens = set(t for t in re.split(r"[^a-z0-9]+", slug(artist)) if t)
                if artist_tokens:
                    tokens = re.split(r"[-_]+", title_part)
                    kept = [t for t in tokens if t.lower() not in artist_tokens and t]
                    cleaned = "-".join(kept)
                    if cleaned: title_part = cleaned
    except Exception:
        pass
    return title_part


def has_both_tags(path):
    """True if file already has TBPM and TKEY tags."""
    try:
        audio = MP3(path, ID3=ID3)
        if audio.tags is None:
            return False
        has_bpm = audio.tags.get("TBPM") is not None
        has_key = audio.tags.get("TKEY") is not None
        return has_bpm and has_key
    except Exception:
        return False


def read_tag_values(path):
    """Return (musical_key, bpm) from existing TKEY/TBPM tags or (None, None)."""
    try:
        audio = MP3(path, ID3=ID3)
        if audio.tags is None: return None, None
        key_tag = audio.tags.get("TKEY")
        bpm_tag = audio.tags.get("TBPM")
        key = (key_tag.text[0] if key_tag else None) or None
        bpm = None
        if bpm_tag:
            try: bpm = int(bpm_tag.text[0])
            except Exception: pass
        return key, bpm
    except Exception:
        return None, None


def process_one(path, do_rename, idx=None, total=None, allow_skip=True, keep_numbers=False):
    filename = os.path.basename(path)
    if idx is not None:
        print(f"PROGRESS: {idx}/{total} {filename}", flush=True)

    musical = None
    bpm = None

    if allow_skip and has_both_tags(path):
        # Skip detection, but still apply rename using existing tag values
        existing_key, existing_bpm = read_tag_values(path)
        if existing_key and existing_bpm:
            musical = existing_key
            bpm = existing_bpm
            print(f"SKIP: {filename} (already tagged) key={musical} bpm={bpm}", flush=True)
        else:
            print(f"SKIP: {filename} (already tagged)", flush=True)
            return
    else:
        try:
            _, musical, bpm = detect_keys_and_bpm(path)
        except Exception as e:
            print(f"ERROR: {filename}: {e}", flush=True)
            return
        print(f"RESULT: {filename} key={musical} bpm={bpm}", flush=True)
        write_tags(path, bpm, musical)

    if do_rename and musical is not None and bpm is not None:
        stem = build_clean_stem(path, filename)
        new_name = f"{stem}_{musical}_{bpm}.mp3"
        if keep_numbers:
            m = re.match(r"^(\d{2,4}_)", filename)
            if m and not new_name.startswith(m.group(1)):
                new_name = m.group(1) + new_name
        new_path = os.path.join(os.path.dirname(path), new_name)
        if new_path == path:
            sync_title_to_filename(path)
        elif rename_and_sync_title(path, new_path):
            print(f"RENAMED: {filename} -> {new_name}", flush=True)


def find_ffmpeg():
    """Locate ffmpeg binary. App-launched processes have minimal PATH."""
    import shutil as _sh
    if got := _sh.which("ffmpeg"): return got
    for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]:
        if os.path.exists(p): return p
    raise FileNotFoundError("ffmpeg not found. Install via `brew install ffmpeg`.")


def measure_volume(path):
    """Return (mean_db, max_db) using ffmpeg volumedetect."""
    import subprocess
    ffmpeg = find_ffmpeg()
    proc = subprocess.run(
        [ffmpeg, "-hide_banner", "-nostats", "-i", path,
         "-af", "volumedetect", "-f", "null", "-"],
        stderr=subprocess.PIPE, stdout=subprocess.PIPE
    )
    text = proc.stderr.decode("utf-8", errors="ignore")
    mean = None
    peak = None
    for line in text.splitlines():
        if "mean_volume:" in line:
            try: mean = float(line.split("mean_volume:")[1].strip().split()[0])
            except Exception: pass
        elif "max_volume:" in line:
            try: peak = float(line.split("max_volume:")[1].strip().split()[0])
            except Exception: pass
    return mean, peak


def apply_gain(path, gain_db):
    """Re-encode file with volume filter. Replaces original via temp file."""
    import subprocess, tempfile
    ffmpeg = find_ffmpeg()
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    codec = {"mp3": "libmp3lame", "m4a": "aac", "aac": "aac", "wav": "pcm_s16le"}.get(ext, "copy")
    tmp = tempfile.NamedTemporaryFile(suffix="." + ext, delete=False)
    tmp.close()
    cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
           "-i", path,
           "-af", f"volume={gain_db}dB",
           "-c:a", codec, "-q:a", "0",
           "-map_metadata", "0", "-id3v2_version", "3",
           tmp.name]
    proc = subprocess.run(cmd, stderr=subprocess.PIPE)
    if proc.returncode == 0:
        shutil.move(tmp.name, path)
        return True
    try: os.unlink(tmp.name)
    except Exception: pass
    return False


def sync_filename_to_tags(folder):
    """For each track with TKEY+TBPM, ensure filename ends with _KEY_BPM."""
    files = sorted(
        os.path.join(folder, f)
        for f in os.listdir(folder)
        if f.lower().endswith(".mp3") and not f.startswith(".")
    )
    print(f"TOTAL: {len(files)}", flush=True)
    for i, p in enumerate(files, 1):
        name = os.path.basename(p)
        print(f"PROGRESS: {i}/{len(files)} {name}", flush=True)
        key, bpm = read_tag_values(p)
        if not key or not bpm:
            print(f"SKIP: {name} (missing tags)", flush=True)
            continue
        # Already has matching suffix?
        stem_no_ext = name[:-4]
        suffix = f"_{key}_{bpm}"
        if stem_no_ext.lower().endswith(suffix.lower()):
            print(f"OK: {name} (already has suffix)", flush=True)
            continue
        clean = build_clean_stem(p, name)
        new_name = f"{clean}{suffix}.mp3"
        # Preserve NNN_ prefix if original had one
        m = re.match(r"^(\d{2,4}_)", name)
        if m and not new_name.startswith(m.group(1)):
            new_name = m.group(1) + new_name
        new_path = os.path.join(os.path.dirname(p), new_name)
        if new_path == p:
            sync_title_to_filename(p)
            print(f"OK: {name} (synced title)", flush=True)
            continue
        if os.path.exists(new_path):
            print(f"SKIP: {name} -> {new_name} (collision)", flush=True)
            continue
        if rename_and_sync_title(p, new_path):
            print(f"RENAMED: {name} -> {new_name}", flush=True)
    print("DONE", flush=True)


def normalize_file(path, apply=False):
    """Boost a single track to ~ -0.3 dBFS peak (max headroom-safe gain)."""
    name = os.path.basename(path)
    print(f"PROGRESS: 1/1 {name}", flush=True)
    try:
        mean, peak = measure_volume(path)
    except FileNotFoundError as e:
        print(f"ERROR: {e}", flush=True)
        print("DONE", flush=True)
        return
    if peak is None:
        print(f"ERROR: {name}: could not measure", flush=True)
        return
    print(f"MEASURE: {name} mean={mean:.1f}dB peak={peak:.1f}dB", flush=True)
    gain = max(0.0, -0.3 - peak)
    if gain < 0.5:
        print(f"PLAN: {name} gain=+0.0dB (already loud)", flush=True)
        print("DONE", flush=True)
        return
    print(f"PLAN: {name} gain=+{gain:.1f}dB", flush=True)
    if apply:
        ok = apply_gain(path, gain)
        print(f"{'APPLIED' if ok else 'ERROR'}: {name}", flush=True)
    print("DONE", flush=True)


def normalize_folder(folder, apply=False):
    try:
        find_ffmpeg()
    except FileNotFoundError as e:
        print(f"ERROR: {e}", flush=True)
        print("DONE", flush=True)
        return

    files = sorted(
        os.path.join(folder, f)
        for f in os.listdir(folder)
        if f.lower().endswith((".mp3", ".m4a", ".wav", ".aac")) and not f.startswith(".")
    )
    print(f"TOTAL: {len(files)}", flush=True)

    # Phase 1: measure
    measurements = []
    for i, p in enumerate(files, 1):
        name = os.path.basename(p)
        print(f"PROGRESS: {i}/{len(files)} {name}", flush=True)
        mean, peak = measure_volume(p)
        if peak is None:
            print(f"ERROR: {name}: could not measure", flush=True)
            continue
        measurements.append((p, mean, peak))
        print(f"MEASURE: {name} mean={mean:.1f}dB peak={peak:.1f}dB", flush=True)

    if not measurements:
        print("DONE", flush=True)
        return

    # Target = quietest peak among the loudest band (max mean ref).
    # Boost others up to match the maximum mean_volume, capped by headroom.
    target_mean = max(m for _, m, _ in measurements if m is not None)
    print(f"TARGET: mean={target_mean:.1f}dB", flush=True)

    # Phase 2: gain plan + optional apply
    for i, (p, mean, peak) in enumerate(measurements, 1):
        name = os.path.basename(p)
        if mean is None: continue
        raw_gain = target_mean - mean
        # Cap so peak + gain <= -0.3 dB (small safety)
        max_safe_gain = -0.3 - peak
        gain = min(raw_gain, max_safe_gain)
        gain = max(gain, 0)  # never reduce
        if gain < 0.5:
            print(f"PLAN: {name} gain=+0.0dB (skip)", flush=True)
            continue
        print(f"PLAN: {name} gain=+{gain:.1f}dB", flush=True)
        if apply:
            print(f"PROGRESS: {i}/{len(measurements)} applying {name}", flush=True)
            ok = apply_gain(p, gain)
            print(f"{'APPLIED' if ok else 'ERROR'}: {name}", flush=True)
    print("DONE", flush=True)


def reset_one(path, idx=None, total=None, keep_numbers=False):
    filename = os.path.basename(path)
    if idx is not None:
        print(f"PROGRESS: {idx}/{total} {filename}", flush=True)
    stem = build_clean_stem(path, filename)
    if not stem:
        print(f"SKIP: {filename} (empty stem)", flush=True)
        return
    if keep_numbers:
        m = re.match(r"^(\d{2,4}_)", filename)
        if m:
            stem = m.group(1) + stem
    new_name = f"{stem}.mp3"
    new_path = os.path.join(os.path.dirname(path), new_name)
    if new_path == path:
        sync_title_to_filename(path)
        print(f"OK: {filename} (synced title)", flush=True)
        return
    if os.path.exists(new_path):
        print(f"SKIP: {filename} -> {new_name} (collision)", flush=True)
        return
    if rename_and_sync_title(path, new_path):
        print(f"RENAMED: {filename} -> {new_name}", flush=True)


def sync_title_to_filename(path):
    """TIT2 = filename stem. No transformations. Always identical."""
    if not path.lower().endswith(".mp3"): return
    stem = os.path.splitext(os.path.basename(path))[0]
    try:
        audio = MP3(path, ID3=ID3)
        try: audio.add_tags()
        except ID3Error: pass
        audio.tags.add(TIT2(encoding=3, text=stem))
        audio.save(v2_version=3)
    except Exception:
        pass


def rename_and_sync_title(old_path, new_path):
    """Rename file and write new stem into TIT2 so name+title stay in sync."""
    moved = False
    if old_path != new_path:
        if os.path.exists(new_path): return False
        shutil.move(old_path, new_path)
        moved = True
    sync_title_to_filename(new_path)
    return moved


def set_title(path, new_title):
    """Write TIT2 to file without touching other frames (preserves artwork)."""
    try:
        audio = MP3(path, ID3=ID3)
    except Exception as e:
        print(f"ERROR: {path}: {e}", flush=True)
        return
    try:
        audio.add_tags()
    except ID3Error:
        pass
    audio.tags.add(TIT2(encoding=3, text=new_title))
    audio.save(v2_version=3)
    print(f"TITLE_SET: {os.path.basename(path)} -> {new_title}", flush=True)


def set_tags(path, kvs):
    """Set arbitrary text frames (TIT2, TPE1, TALB, TCON, TBPM, TDRC) preserving artwork."""
    try:
        audio = MP3(path, ID3=ID3)
    except Exception as e:
        print(f"ERROR: {e}", flush=True)
        return
    try:
        audio.add_tags()
    except ID3Error:
        pass
    from mutagen.id3 import TALB, TCON, TDRC
    frame_map = {"title": TIT2, "artist": TPE1, "album": TALB,
                 "genre": TCON, "bpm": TBPM, "year": TDRC, "key": TKEY}
    for k, v in kvs.items():
        if k not in frame_map: continue
        if v is None or v == "":
            audio.tags.delall(frame_map[k].__name__)
            continue
        audio.tags.add(frame_map[k](encoding=3, text=str(v)))
    audio.save(v2_version=3)
    print(f"TAGS_SET: {os.path.basename(path)}", flush=True)


def set_tag(path, frame, value):
    """Set a single ID3 frame, preserving all others (including artwork)."""
    from mutagen.id3 import TALB, TCON, TDRC
    frame_map = {
        "title": TIT2, "artist": TPE1, "album": TALB,
        "genre": TCON, "bpm": TBPM, "year": TDRC, "key": TKEY
    }
    cls = frame_map.get(frame)
    if cls is None:
        print(f"ERROR: unknown frame {frame}", flush=True)
        return
    try:
        audio = MP3(path, ID3=ID3)
    except Exception as e:
        print(f"ERROR: {e}", flush=True)
        return
    try:
        audio.add_tags()
    except ID3Error:
        pass
    if value == "":
        audio.tags.delall(cls.__name__)
    else:
        audio.tags.add(cls(encoding=3, text=str(value)))
    audio.save(v2_version=3)
    print(f"TAG_SET: {os.path.basename(path)} {frame}={value}", flush=True)


def set_artwork(path, image_path, mime):
    """Replace artwork. image_path can be /dev/stdin to read from stdin."""
    try:
        audio = MP3(path, ID3=ID3)
    except Exception as e:
        print(f"ERROR: {e}", flush=True)
        return
    try:
        audio.add_tags()
    except ID3Error:
        pass
    if image_path == "/dev/stdin":
        data = sys.stdin.buffer.read()
    else:
        with open(image_path, "rb") as f:
            data = f.read()
    audio.tags.delall("APIC")
    audio.tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=data))
    audio.save(v2_version=3)
    print(f"ARTWORK_SET: {os.path.basename(path)}", flush=True)


def remove_artwork(path):
    try:
        audio = MP3(path, ID3=ID3)
    except Exception as e:
        print(f"ERROR: {e}", flush=True)
        return
    if audio.tags is None:
        return
    audio.tags.delall("APIC")
    audio.save(v2_version=3)
    print(f"ARTWORK_REMOVED: {os.path.basename(path)}", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--folder")
    p.add_argument("--file")
    p.add_argument("--rename", action="store_true")
    p.add_argument("--reset", action="store_true",
                   help="Strip _KEY_BPM and NNN_ from filenames, do not analyze")
    p.add_argument("--keep-numbers", action="store_true",
                   help="With --reset, preserve existing NNN_ prefix")
    p.add_argument("--normalize", metavar="FOLDER",
                   help="Measure loudness of all tracks; report gain plan")
    p.add_argument("--normalize-file", metavar="FILE",
                   help="Boost one track to safe peak (-0.3 dBFS)")
    p.add_argument("--apply", action="store_true",
                   help="With --normalize/--normalize-file, also re-encode to apply the gain")
    p.add_argument("--sync-filename", metavar="FOLDER",
                   help="Append _KEY_BPM to filenames using existing tags")
    p.add_argument("--set-title", nargs=2, metavar=("PATH", "TITLE"),
                   help="Set TIT2 only, preserving all other frames including artwork")
    p.add_argument("--set-tag", nargs=3, metavar=("PATH", "FRAME", "VALUE"),
                   help="Set a single ID3 frame (title|artist|album|genre|bpm|year|key) preserving others")
    p.add_argument("--set-artwork", nargs=3, metavar=("PATH", "IMAGE", "MIME"),
                   help="Replace APIC artwork. IMAGE can be /dev/stdin")
    p.add_argument("--remove-artwork", metavar="PATH",
                   help="Remove all APIC artwork frames")
    args = p.parse_args()

    if args.normalize:
        normalize_folder(args.normalize, apply=args.apply)
        return
    if args.normalize_file:
        normalize_file(args.normalize_file, apply=args.apply)
        return
    if args.sync_filename:
        sync_filename_to_tags(args.sync_filename)
        return
    if args.set_title:
        set_title(args.set_title[0], args.set_title[1])
        return
    if args.set_tag:
        set_tag(args.set_tag[0], args.set_tag[1], args.set_tag[2])
        return
    if args.set_artwork:
        set_artwork(args.set_artwork[0], args.set_artwork[1], args.set_artwork[2])
        return
    if args.remove_artwork:
        remove_artwork(args.remove_artwork)
        return

    if args.reset:
        if args.file:
            reset_one(args.file, keep_numbers=args.keep_numbers)
            return
        if not args.folder:
            print("ERROR: --reset needs --folder or --file", flush=True)
            sys.exit(1)
        files = sorted(
            os.path.join(args.folder, f)
            for f in os.listdir(args.folder)
            if f.lower().endswith(".mp3") and not f.startswith(".")
        )
        print(f"TOTAL: {len(files)}", flush=True)
        for i, path in enumerate(files, 1):
            reset_one(path, idx=i, total=len(files), keep_numbers=args.keep_numbers)
        print("DONE", flush=True)
        return

    if args.file:
        process_one(args.file, args.rename, allow_skip=False, keep_numbers=args.keep_numbers)
        return

    if not args.folder:
        print("ERROR: need --folder or --file", flush=True)
        sys.exit(1)

    files = sorted(
        os.path.join(args.folder, f)
        for f in os.listdir(args.folder)
        if f.lower().endswith(".mp3") and not f.startswith(".")
    )
    print(f"TOTAL: {len(files)}", flush=True)
    for i, path in enumerate(files, 1):
        process_one(path, args.rename, idx=i, total=len(files), keep_numbers=args.keep_numbers)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
