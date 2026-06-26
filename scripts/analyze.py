#!/usr/bin/env python3
"""Modulr analyse + tag CLI.
Thin dispatcher over the modulr package. Maintains the stdout protocol
consumed by Audio/PythonRunner.swift (PROGRESS / DONE / ERROR lines).
"""
import argparse
import os
import sys
import warnings

warnings.filterwarnings("ignore")

# Allow `python scripts/analyze.py ...` from project root regardless of cwd.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from modulr.logger import log_error
from modulr.mastering.loudness import LoudnessNormaliser
from modulr.mastering.silence import SilenceTrimmer
from modulr.mastering.tweak import TempoPitchBaker
from modulr.metadata.tags import TagIO
from modulr.pipelines import (
    AnalysePipeline,
    BrightenPipeline,
    ConvertPipeline,
    ResetPipeline,
    StripNumbersPipeline,
    SyncFilenamePipeline,
)


def _build_parser():
    p = argparse.ArgumentParser()
    p.add_argument("--folder")
    p.add_argument("--file")
    p.add_argument("--rename", action="store_true")
    p.add_argument("--only-untagged", action="store_true",
                   help="With --folder, skip tracks that already have BPM and key")
    p.add_argument("--reset", action="store_true",
                   help="Strip _KEY_BPM and NNN_ from filenames; do not analyse")
    p.add_argument("--keep-numbers", action="store_true",
                   help="With --reset, preserve existing NNN_ prefix")
    p.add_argument("--normalize", metavar="FOLDER",
                   help="Measure loudness of all tracks; report gain plan")
    p.add_argument("--normalize-file", metavar="FILE",
                   help="Boost one track to safe peak (-0.3 dBFS)")
    p.add_argument("--apply", action="store_true",
                   help="With --normalize/--normalize-file, re-encode to apply gain")
    p.add_argument("--sync-filename", metavar="FOLDER",
                   help="Append _KEY_BPM to filenames using existing tags")
    p.add_argument("--strip-numbers", action="store_true",
                   help="Strip leading NNN_ order prefix; preserve _KEY_BPM. "
                        "Combine with --folder or --file.")
    p.add_argument("--bake-tweak", nargs=5,
                   metavar=("PATH", "RATE", "CENTS", "BPM", "KEY"),
                   help="Bake tempo+pitch into a track. Use - for missing BPM/KEY.")
    p.add_argument("--set-title", nargs=2, metavar=("PATH", "TITLE"))
    p.add_argument("--set-tag", nargs=3, metavar=("PATH", "FRAME", "VALUE"))
    p.add_argument("--set-artwork", nargs=3, metavar=("PATH", "IMAGE", "MIME"))
    p.add_argument("--remove-artwork", metavar="PATH")
    p.add_argument("--convert-mp3", metavar="FILE",
                   help="Transcode wav/m4a to 320 kbps CBR MP3 next to source")
    p.add_argument("--convert-folder-mp3", metavar="FOLDER",
                   help="Bulk transcode every non-mp3 audio file in FOLDER to 320 kbps MP3")
    p.add_argument("--delete-source", action="store_true",
                   help="With --convert-folder-mp3, delete each original after successful encode")
    p.add_argument("--brighten", metavar="FILE",
                   help="Run ffmpeg exciter + high-shelf on FILE; writes a _bright sibling")
    p.add_argument("--trim-silence", metavar="FILE",
                   help="Trim trailing silence over 10s from FILE")
    p.add_argument("--trim-silence-folder", metavar="FOLDER",
                   help="Trim trailing silence over 10s from every track in FOLDER")
    p.add_argument("--boost-file-sibling", metavar="FILE",
                   help="Measure peak + write a _loud sibling lifted to ~ -0.3 dBFS")
    return p


def _dispatch_analyse(args):
    pipeline = AnalysePipeline()
    if args.file:
        pipeline.run_one(
            args.file, args.rename,
            allow_skip=False, keep_numbers=args.keep_numbers,
        )
        return
    if not args.folder:
        log_error("need --folder or --file")
        sys.exit(1)
    pipeline.run_folder(args.folder, args.rename,
                        keep_numbers=args.keep_numbers,
                        only_untagged=args.only_untagged)


def _dispatch_reset(args):
    pipeline = ResetPipeline()
    if args.file:
        pipeline.run_one(args.file, keep_numbers=args.keep_numbers)
        return
    if not args.folder:
        log_error("--reset needs --folder or --file")
        sys.exit(1)
    pipeline.run_folder(args.folder, keep_numbers=args.keep_numbers)


def _dispatch_strip_numbers(args):
    pipeline = StripNumbersPipeline()
    if args.file:
        pipeline.run_one(args.file)
        return
    if not args.folder:
        log_error("--strip-numbers needs --folder or --file")
        sys.exit(1)
    pipeline.run_folder(args.folder)


def _dispatch_bake(args):
    bk_path, rate_s, cents_s, bpm_s, key_s = args.bake_tweak
    try: rate = float(rate_s)
    except (ValueError, TypeError): rate = 1.0
    try: cents = float(cents_s)
    except (ValueError, TypeError): cents = 0.0
    bpm = int(bpm_s) if bpm_s and bpm_s != "-" else None
    key = key_s if key_s and key_s != "-" else None
    TempoPitchBaker().bake(bk_path, rate, cents, new_bpm=bpm, new_key=key)


def main():
    args = _build_parser().parse_args()
    tag_io = TagIO()

    if args.normalize:
        LoudnessNormaliser().match_folder(args.normalize, apply=args.apply); return
    if args.normalize_file:
        LoudnessNormaliser().boost_one(args.normalize_file, apply=args.apply); return
    if args.sync_filename:
        SyncFilenamePipeline().run(args.sync_filename); return
    if args.bake_tweak:
        _dispatch_bake(args); return
    if args.set_title:
        tag_io.set_title(*args.set_title); return
    if args.set_tag:
        tag_io.set_tag(*args.set_tag); return
    if args.set_artwork:
        tag_io.set_artwork(*args.set_artwork); return
    if args.remove_artwork:
        tag_io.remove_artwork(args.remove_artwork); return
    if args.convert_mp3:
        ConvertPipeline().convert_to_mp3(args.convert_mp3); return
    if args.convert_folder_mp3:
        ConvertPipeline().convert_folder(
            args.convert_folder_mp3, delete_original=args.delete_source
        ); return
    if args.brighten:
        BrightenPipeline().brighten(args.brighten); return
    if args.boost_file_sibling:
        LoudnessNormaliser().boost_to_sibling(args.boost_file_sibling); return
    if args.trim_silence:
        SilenceTrimmer().trim_one(args.trim_silence); return
    if args.trim_silence_folder:
        SilenceTrimmer().trim_folder(args.trim_silence_folder); return

    if args.reset:
        _dispatch_reset(args); return
    if args.strip_numbers:
        _dispatch_strip_numbers(args); return

    _dispatch_analyse(args)


if __name__ == "__main__":
    main()
