"""Key detection. Strategy pattern: each detector returns (pitch_class, mode).

EssentiaKeyDetector -- HPCP + edma profile (matches rekordbox / DJ-tool key calls).
MadmomKeyDetector  -- CNN classifier (SOTA, pretrained).
LibrosaKeyDetector -- HPSS chroma + Temperley profile (fallback, less accurate).
FallbackKeyDetector -- chains primary -> fallback on exception.
"""
from abc import ABC, abstractmethod

from ..theory.constants import MADMOM_KEY_TO_MUSICAL
from ..theory.keys import musical_to_pc_mode


class KeyDetector(ABC):
    @abstractmethod
    def detect(self, path: str, audio=None):
        """Returns (pitch_class:int 0..11, mode:int [1=major, 0=minor]).
        `audio` is an optional preloaded Essentia buffer.
        """


class EssentiaKeyDetector(KeyDetector):
    """Essentia KeyExtractor with the EDM profile, tuned to DJ-tool conventions."""

    _PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
           "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10,
           "Bb": 10, "B": 11}

    def detect(self, path, audio=None):
        from .audio import load_essentia
        import essentia.standard as es
        if audio is None:
            audio = load_essentia(path)
        key, scale, _strength = es.KeyExtractor(
            profileType="edma", hpcpSize=36
        )(audio)
        pc = self._PC.get(key)
        if pc is None:
            raise RuntimeError(f"essentia: unmapped key {key!r}")
        return pc, (1 if scale == "major" else 0)


class MadmomKeyDetector(KeyDetector):
    """CNNKeyRecognitionProcessor — pretrained CNN classifier."""

    def detect(self, path, audio=None):
        from madmom.features.key import (
            CNNKeyRecognitionProcessor, key_prediction_to_label,
        )
        pred = CNNKeyRecognitionProcessor()(path)
        label = key_prediction_to_label(pred)
        musical = MADMOM_KEY_TO_MUSICAL.get(label)
        if musical is None:
            raise RuntimeError(f"madmom: unmapped key label {label!r}")
        return musical_to_pc_mode(musical)


class LibrosaKeyDetector(KeyDetector):
    """HPSS-isolated chroma + Temperley profile correlation. Fallback only."""

    # Temperley (2007): trained on pop corpus, beats Krumhansl-Schmuckler for EDM
    _MAJOR_PROFILE = [5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0]
    _MINOR_PROFILE = [5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]

    def detect(self, path, audio=None):
        import librosa
        import numpy as np
        y, sr = librosa.load(path, sr=22050, mono=True, duration=180)
        y_harm = librosa.effects.harmonic(y, margin=4)
        chroma = librosa.feature.chroma_cens(y=y_harm, sr=sr, hop_length=2048)
        chroma_mean = chroma.mean(axis=1)
        major = np.array(self._MAJOR_PROFILE)
        minor = np.array(self._MINOR_PROFILE)
        best_score, best_pc, best_mode = -float("inf"), 0, 1
        for pc in range(12):
            for mode, profile in ((1, major), (0, minor)):
                score = np.corrcoef(chroma_mean, np.roll(profile, pc))[0, 1]
                if score > best_score:
                    best_score, best_pc, best_mode = score, pc, mode
        return best_pc, best_mode


class FallbackKeyDetector(KeyDetector):
    """Chain two detectors: try primary, fall back on exception."""

    def __init__(self, primary: KeyDetector, fallback: KeyDetector):
        self.primary = primary
        self.fallback = fallback

    def detect(self, path, audio=None):
        try:
            return self.primary.detect(path, audio=audio)
        except Exception:
            return self.fallback.detect(path, audio=audio)
