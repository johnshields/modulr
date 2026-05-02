"""Composite track analyser — combines BPM + Key detection into one DJ result."""
from ..theory.constants import CAMELOT, MUSICAL
from .bpm import (
    BPMDetector,
    FallbackBPMDetector,
    LibrosaBPMDetector,
    MadmomBPMDetector,
)
from .key import (
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
        bpm = self._clamp_bpm(self._bpm_detector.detect(path))
        pc, mode = self._key_detector.detect(path)
        return CAMELOT[(pc, mode)], MUSICAL[(pc, mode)], bpm

    @classmethod
    def _clamp_bpm(cls, bpm):
        while bpm < cls.DJ_MIN_BPM:
            bpm *= 2
        while bpm > cls.DJ_MAX_BPM:
            bpm /= 2
        return int(round(bpm))


def default_analyser() -> TrackAnalyser:
    """Currently-preferred wiring: madmom primary, librosa fallback."""
    bpm = FallbackBPMDetector(MadmomBPMDetector(), LibrosaBPMDetector())
    key = FallbackKeyDetector(MadmomKeyDetector(), LibrosaKeyDetector())
    return TrackAnalyser(bpm, key)
