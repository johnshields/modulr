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
    """Build canonical stem (title only). Reads ID3 TIT2 if available, else parses filename."""
    try:
        audio = MP3(path, ID3=ID3)
        if audio.tags:
            title = (audio.tags.get("TIT2").text[0] if audio.tags.get("TIT2") else "").strip()
            if title:
                return slug(title)
    except Exception:
        pass

    # Fallback: parse filename, strip NNN_ prefix, _KEY_BPM suffix, and trailing _artist
    stem = filename[:-4]
    parts = stem.split("_")
    while (len(parts) >= 3
           and parts[-1].isdigit()
           and re.match(r"^[A-Za-z0-9#]{1,6}$", parts[-2])):
        parts = parts[:-2]
    if len(parts) >= 2 and re.match(r"^\d{2,3}$", parts[0]):
        parts = parts[1:]
    # Take only first part (title), drop artist if present
    return slug(parts[0]) if parts else ""


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


def process_one(path, do_rename, idx=None, total=None, allow_skip=True):
    filename = os.path.basename(path)
    if idx is not None:
        print(f"PROGRESS: {idx}/{total} {filename}", flush=True)

    if allow_skip and has_both_tags(path):
        print(f"SKIP: {filename} (already tagged)", flush=True)
        return

    try:
        camelot, musical, bpm = detect_keys_and_bpm(path)
    except Exception as e:
        print(f"ERROR: {filename}: {e}", flush=True)
        return

    print(f"RESULT: {filename} key={musical} ({camelot}) bpm={bpm}", flush=True)
    write_tags(path, bpm, musical)

    if do_rename:
        stem = build_clean_stem(path, filename)
        new_name = f"{stem}_{musical}_{bpm}.mp3"
        new_path = os.path.join(os.path.dirname(path), new_name)
        if new_path != path:
            shutil.move(path, new_path)
            print(f"RENAMED: {filename} -> {new_name}", flush=True)


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
        print(f"OK: {filename} (already clean)", flush=True)
        return
    if os.path.exists(new_path):
        print(f"SKIP: {filename} -> {new_name} (collision)", flush=True)
        return
    shutil.move(path, new_path)
    print(f"RENAMED: {filename} -> {new_name}", flush=True)


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
    p.add_argument("--set-title", nargs=2, metavar=("PATH", "TITLE"),
                   help="Set TIT2 only, preserving all other frames including artwork")
    p.add_argument("--set-tag", nargs=3, metavar=("PATH", "FRAME", "VALUE"),
                   help="Set a single ID3 frame (title|artist|album|genre|bpm|year|key) preserving others")
    p.add_argument("--set-artwork", nargs=3, metavar=("PATH", "IMAGE", "MIME"),
                   help="Replace APIC artwork. IMAGE can be /dev/stdin")
    p.add_argument("--remove-artwork", metavar="PATH",
                   help="Remove all APIC artwork frames")
    args = p.parse_args()

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
        process_one(args.file, args.rename, allow_skip=False)
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
        process_one(path, args.rename, idx=i, total=len(files))
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
