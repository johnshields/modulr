"""BPM detection. Strategy pattern: each detector implements detect(path).

MadmomBPMDetector  -- DL-based RNN+DBN tracker (SOTA, slower).
LibrosaBPMDetector -- librosa beat_track fallback (fast, less robust).
FallbackBPMDetector -- chains primary -> fallback on exception.
"""
from abc import ABC, abstractmethod


class BPMDetector(ABC):
    @abstractmethod
    def detect(self, path: str) -> float:
        """Raw BPM, no clamping."""


class MadmomBPMDetector(BPMDetector):
    """RNN beat activations + DBN tracker. State of the art on tricky tempos."""

    def __init__(self, min_bpm=55, max_bpm=220, fps=100,
                 transition_lambda=100, num_tempi=60):
        self.min_bpm = min_bpm
        self.max_bpm = max_bpm
        self.fps = fps
        self.transition_lambda = transition_lambda
        self.num_tempi = num_tempi

    def detect(self, path):
        from madmom.features.beats import (
            RNNBeatProcessor, DBNBeatTrackingProcessor,
        )
        import numpy as np
        proc = DBNBeatTrackingProcessor(
            min_bpm=self.min_bpm, max_bpm=self.max_bpm, fps=self.fps,
            transition_lambda=self.transition_lambda, num_tempi=self.num_tempi,
        )
        beats = proc(RNNBeatProcessor()(path))
        if len(beats) < 2:
            raise RuntimeError("madmom: too few beats")
        return 60.0 / float(np.median(np.diff(beats)))


class LibrosaBPMDetector(BPMDetector):
    """Faster, less robust. Used as fallback when madmom unavailable."""

    def detect(self, path):
        import librosa
        import numpy as np
        y, sr = librosa.load(path, sr=22050, mono=True, duration=180)
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        return float(np.atleast_1d(tempo)[0])


class FallbackBPMDetector(BPMDetector):
    """Chain two detectors: try primary, fall back on exception."""

    def __init__(self, primary: BPMDetector, fallback: BPMDetector):
        self.primary = primary
        self.fallback = fallback

    def detect(self, path):
        try:
            return self.primary.detect(path)
        except Exception:
            return self.fallback.detect(path)
