"""Trailing-silence trimmer — cuts end silence over a threshold via ffmpeg."""
import os
import re
import shutil
import subprocess

from .ffmpeg import FfmpegRunner
from ..logger import log, log_done, log_error, log_progress
from ..metadata.files import list_audio


class SilenceTrimmer:
    THRESHOLD_DB = -50
    DETECT_MIN = 2.0
    MIN_TRAILING = 10.0
    KEEP_TAIL = 0.5

    def __init__(self, ffmpeg: FfmpegRunner | None = None):
        self._ff = ffmpeg or FfmpegRunner()

    def trim_one(self, path, idx=None, total=None):
        name = os.path.basename(path)
        if idx is not None:
            log_progress(idx, total, name)
        info = self._analyse(path)
        if info is None:
            log_error(f"{name}: analysis failed")
            return
        duration, trailing_start = info
        if trailing_start is None:
            log(f"SKIP: {name} (no trailing silence)")
            return
        trailing = duration - trailing_start
        if trailing < self.MIN_TRAILING:
            log(f"SKIP: {name} (tail {trailing:.1f}s < {int(self.MIN_TRAILING)}s)")
            return
        out, err = self._ff.trim_tail(path, trailing_start + self.KEEP_TAIL)
        if out is None:
            log_error(f"{name}: {(err or '')[:200]}")
            return
        shutil.move(out, path)
        log(f"TRIMMED: {name} (-{trailing:.1f}s)")

    def trim_folder(self, folder):
        files = list_audio(folder)
        log(f"TOTAL: {len(files)}")
        for i, p in enumerate(files, 1):
            self.trim_one(p, idx=i, total=len(files))
        log_done()

    def _analyse(self, path):
        cmd = [self._ff.binary(), "-hide_banner", "-i", path,
               "-af", f"silencedetect=noise={self.THRESHOLD_DB}dB:d={self.DETECT_MIN}",
               "-f", "null", "-"]
        proc = subprocess.run(cmd, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
        text = proc.stderr.decode("utf-8", errors="ignore")
        duration = self._parse_duration(text)
        if duration is None:
            return None
        starts = [float(x) for x in re.findall(r"silence_start:\s*([0-9.]+)", text)]
        ends = [float(x) for x in re.findall(r"silence_end:\s*([0-9.]+)", text)]
        if starts and (len(starts) > len(ends) or ends[-1] >= duration - 1.0):
            return duration, starts[-1]
        return duration, None

    @staticmethod
    def _parse_duration(text):
        m = re.search(r"Duration:\s*(\d+):(\d+):(\d+\.\d+)", text)
        if not m:
            return None
        return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
