"""BPM detection. Strategy pattern: each detector implements detect(path).

EssentiaBPMDetector -- RhythmExtractor2013 multifeature (fast, accurate for 4/4).
MadmomBPMDetector  -- DL-based RNN+DBN tracker (SOTA, ~9x slower).
LibrosaBPMDetector -- librosa beat_track fallback (fast, less robust).
FallbackBPMDetector -- chains primary -> fallback on exception.
"""
from abc import ABC, abstractmethod


class BPMDetector(ABC):
    @abstractmethod
    def detect(self, path: str, audio=None) -> float:
        """Raw BPM, no clamping. `audio` is an optional preloaded Essentia buffer."""


class EssentiaBPMDetector(BPMDetector):
    """RhythmExtractor2013 multifeature. An order faster than madmom's DBN tracker."""

    def detect(self, path, audio=None):
        from .audio import load_essentia
        import essentia.standard as es
        if audio is None:
            audio = load_essentia(path)
        bpm, _beats, _conf, _, _ = es.RhythmExtractor2013(method="multifeature")(audio)
        if bpm <= 0:
            raise RuntimeError("essentia: no tempo")
        return float(bpm)


class MadmomBPMDetector(BPMDetector):
    """RNN beat activations + DBN tracker. State of the art on tricky tempos."""

    def __init__(self, min_bpm=55, max_bpm=220, fps=100,
                 transition_lambda=100, num_tempi=60):
        self.min_bpm = min_bpm
        self.max_bpm = max_bpm
        self.fps = fps
        self.transition_lambda = transition_lambda
        self.num_tempi = num_tempi

    def detect(self, path, audio=None):
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

    def detect(self, path, audio=None):
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

    def detect(self, path, audio=None):
        try:
            return self.primary.detect(path, audio=audio)
        except Exception:
            return self.fallback.detect(path, audio=audio)
