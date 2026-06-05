"""Folder-level loudness matching + single-file boost."""
import os

from ..logger import log, log_done, log_error, log_progress
from ..metadata.files import list_audio
from .ffmpeg import FfmpegRunner, GainApplier, VolumeMeter


class LoudnessNormaliser:
    """Folder mode: match every track to the loudest track's mean,
    capped by per-track headroom. Two-pass (measure all, then apply).
    Single-file mode: boost one track to safe peak.
    """

    SAFE_HEADROOM_DB = 0.3
    MIN_USEFUL_GAIN_DB = 0.5

    def __init__(self, ffmpeg: FfmpegRunner | None = None,
                 meter: VolumeMeter | None = None,
                 gain: GainApplier | None = None):
        ff = ffmpeg or FfmpegRunner()
        self._ffmpeg = ff
        self._meter = meter or VolumeMeter(ff)
        self._gain = gain or GainApplier(ff)

    # Single file

    def boost_one(self, path, apply=False):
        name = os.path.basename(path)
        log_progress(1, 1, name)
        try:
            mean, peak = self._meter.measure(path)
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return
        if peak is None:
            log_error(f"{name}: could not measure"); return
        log(f"MEASURE: {name} mean={mean:.1f}dB peak={peak:.1f}dB")
        gain = max(0.0, -self.SAFE_HEADROOM_DB - peak)
        if gain < self.MIN_USEFUL_GAIN_DB:
            log(f"PLAN: {name} gain=+0.0dB (already loud)"); log_done(); return
        log(f"PLAN: {name} gain=+{gain:.1f}dB")
        if apply:
            ok = self._gain.apply(path, gain)
            log(f"{'APPLIED' if ok else 'ERROR'}: {name}")
        log_done()

    def boost_to_sibling(self, path):
        """Write a `<stem>_loud<ext>` next to source with the safe-peak boost
        applied; leaves original intact so the caller can A/B and commit.
        """
        import os
        import shutil
        name = os.path.basename(path)
        log_progress(1, 1, name)
        try:
            mean, peak = self._meter.measure(path)
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return
        if peak is None:
            log_error(f"{name}: could not measure"); log_done(); return
        log(f"MEASURE: {name} mean={mean:.1f}dB peak={peak:.1f}dB")
        gain = max(0.0, -self.SAFE_HEADROOM_DB - peak)
        if gain < self.MIN_USEFUL_GAIN_DB:
            log(f"PLAN: {name} gain=+0.0dB (already loud)"); log_done(); return
        log(f"PLAN: {name} gain=+{gain:.1f}dB")

        stem, ext = os.path.splitext(path)
        dst = f"{stem}_loud{ext}"
        if os.path.exists(dst):
            log_error(f"{os.path.basename(dst)} already exists"); log_done(); return

        out, err = self._ffmpeg.encode(path, f"volume={gain}dB")
        if out is None:
            log_error(f"ffmpeg: {(err or '')[:200]}"); log_done(); return
        shutil.move(out, dst)
        log(f"BOOSTED: {os.path.basename(dst)} gain=+{gain:.1f}dB")
        log_done()

    # Folder match

    def match_folder(self, folder, apply=False):
        try:
            self._ffmpeg.binary()
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return

        files = list_audio(folder)
        log(f"TOTAL: {len(files)}")

        measurements = self._measure_all(files)
        if not measurements:
            log_done(); return

        target_mean = max(m for _, m, _ in measurements if m is not None)
        log(f"TARGET: mean={target_mean:.1f}dB")

        self._apply_plan(measurements, target_mean, apply=apply)
        log_done()

    def _measure_all(self, files):
        out = []
        for i, p in enumerate(files, 1):
            name = os.path.basename(p)
            log_progress(i, len(files), name)
            mean, peak = self._meter.measure(p)
            if peak is None:
                log_error(f"{name}: could not measure"); continue
            out.append((p, mean, peak))
            log(f"MEASURE: {name} mean={mean:.1f}dB peak={peak:.1f}dB")
        return out

    def _apply_plan(self, measurements, target_mean, apply):
        for i, (p, mean, peak) in enumerate(measurements, 1):
            name = os.path.basename(p)
            if mean is None:
                continue
            gain = self._safe_gain(target_mean - mean, peak)
            if gain < self.MIN_USEFUL_GAIN_DB:
                log(f"PLAN: {name} gain=+0.0dB (skip)")
                continue
            log(f"PLAN: {name} gain=+{gain:.1f}dB")
            if apply:
                log_progress(i, len(measurements), f"applying {name}")
                ok = self._gain.apply(p, gain)
                log(f"{'APPLIED' if ok else 'ERROR'}: {name}")

    @classmethod
    def _safe_gain(cls, raw_gain, peak):
        max_safe = -cls.SAFE_HEADROOM_DB - peak
        return max(min(raw_gain, max_safe), 0)
