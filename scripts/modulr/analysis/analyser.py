"""Composite track analyser — combines BPM + Key detection into one DJ result."""
from ..theory.constants import CAMELOT, MUSICAL
from .bpm import (
    BPMDetector,
    EssentiaBPMDetector,
    FallbackBPMDetector,
    LibrosaBPMDetector,
    MadmomBPMDetector,
)
from .key import (
    EssentiaKeyDetector,
    FallbackKeyDetector,
    KeyDetector,
    LibrosaKeyDetector,
    MadmomKeyDetector,
)


class TrackAnalyser:
    """Composes BPM + Key detection into one DJ-friendly result.
    BPM is clamped to the [DJ_MIN_BPM, DJ_MAX_BPM] band by halving / doubling.
    """

    DJ_MIN_BPM = 100
    DJ_MAX_BPM = 175

    def __init__(self, bpm_detector: BPMDetector, key_detector: KeyDetector):
        self._bpm_detector = bpm_detector
        self._key_detector = key_detector

    def analyse(self, path):
        # Decode once and share the buffer with both Essentia detectors.
        audio = self._preload(path)
        bpm = self._clamp_bpm(self._bpm_detector.detect(path, audio=audio))
        pc, mode = self._key_detector.detect(path, audio=audio)
        return CAMELOT[(pc, mode)], MUSICAL[(pc, mode)], bpm

    @staticmethod
    def _preload(path):
        """Essentia buffer for the shared fast path; None if Essentia is unavailable."""
        try:
            from .audio import load_essentia
            return load_essentia(path)
        except Exception:
            return None

    @classmethod
    def _clamp_bpm(cls, bpm):
        while bpm < cls.DJ_MIN_BPM:
            bpm *= 2
        while bpm > cls.DJ_MAX_BPM:
            bpm /= 2
        return int(round(bpm))


def default_analyser() -> TrackAnalyser:
    """Preferred wiring: Essentia primary (fast, rekordbox-like), madmom then librosa."""
    bpm = FallbackBPMDetector(
        EssentiaBPMDetector(),
        FallbackBPMDetector(MadmomBPMDetector(), LibrosaBPMDetector()),
    )
    key = FallbackKeyDetector(
        EssentiaKeyDetector(),
        FallbackKeyDetector(MadmomKeyDetector(), LibrosaKeyDetector()),
    )
    return TrackAnalyser(bpm, key)
