"""Bake a tempo + pitch tweak into a track via ffmpeg.

asetrate+aresample shifts pitch; chained atempo restores length and applies
the supplied tempo rate on top. Tag updates + DJ-format rename keep the file
and TIT2 in sync afterwards.
"""
import os
import shutil

from mutagen.id3 import TBPM, TKEY

from ..logger import log, log_done, log_error, log_progress
from ..metadata.tags import TagIO
from .ffmpeg import FfmpegRunner


class TempoPitchBaker:
    SAMPLE_RATE = 44100
    ATEMPO_LIMIT = 2.0  # ffmpeg atempo accepts 0.5..2.0 per pass

    def __init__(self, ffmpeg: FfmpegRunner | None = None,
                 tag_io: TagIO | None = None):
        self._ffmpeg = ffmpeg or FfmpegRunner()
        self._tag_io = tag_io or TagIO()

    def bake(self, path, rate, cents, new_bpm=None, new_key=None):
        name = os.path.basename(path)
        log_progress(1, 1, name)
        try:
            self._ffmpeg.binary()
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return

        chain = self._build_filter(rate, cents)
        log(f"BAKING: filter={chain}")
        out, err = self._ffmpeg.encode(path, chain)
        if out is None:
            log_error(f"ffmpeg failed: {(err or '')[:200]}")
            log_done()
            return
        shutil.move(out, path)

        self._update_tags(path, new_bpm, new_key)
        self._update_filename(path, name, new_bpm, new_key)

        log(f"APPLIED: {name}")
        log_done()

    # Internals

    @classmethod
    def _build_filter(cls, rate, cents):
        pitch_factor = 2.0 ** (cents / 1200.0)
        final_tempo = rate / pitch_factor

        filters = [f"asetrate={int(cls.SAMPLE_RATE * pitch_factor)}",
                   f"aresample={cls.SAMPLE_RATE}"]
        t = final_tempo
        while t < 1.0 / cls.ATEMPO_LIMIT:
            filters.append(f"atempo={1.0 / cls.ATEMPO_LIMIT}")
            t *= cls.ATEMPO_LIMIT
        while t > cls.ATEMPO_LIMIT:
            filters.append(f"atempo={cls.ATEMPO_LIMIT}")
            t /= cls.ATEMPO_LIMIT
        if abs(t - 1.0) > 0.001:
            filters.append(f"atempo={t:.4f}")
        return ",".join(filters)

    def _update_tags(self, path, new_bpm, new_key):
        if not (path.lower().endswith(".mp3") and (new_bpm or new_key)):
            return
        audio = self._tag_io._open(path)
        if audio is None:
            return
        if new_bpm:
            audio.tags.add(TBPM(encoding=3, text=str(new_bpm)))
        if new_key:
            audio.tags.add(TKEY(encoding=3, text=str(new_key)))
        try:
            self._tag_io._save(audio)
        except Exception as e:
            log_error(f"tag write: {e}")

    def _update_filename(self, path, original_name, new_bpm, new_key):
        if not (new_bpm and new_key):
            return
        new_filename = self._tag_io.derived_dj_name(
            path, new_key, new_bpm, keep_numbers=True
        )
        # derived_dj_name uses current path; rename in original dir
        new_path = os.path.join(os.path.dirname(path), new_filename)
        if new_path != path and not os.path.exists(new_path):
            if self._tag_io.rename_and_sync_title(path, new_path):
                log(f"RENAMED: {original_name} -> {new_filename}")
        else:
            self._tag_io.sync_title_to_filename(path)
