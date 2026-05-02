"""Music theory primitives — keys, mode mappings, ID3 frame metadata."""
from .constants import (
    AUDIO_EXT_LOUDNESS,
    CAMELOT,
    CAMELOT_TO_MUSICAL,
    FRAME_MAP,
    MADMOM_KEY_TO_MUSICAL,
    MUSICAL,
)
from .keys import musical_to_pc_mode, normalise_musical

__all__ = [
    "AUDIO_EXT_LOUDNESS", "CAMELOT", "CAMELOT_TO_MUSICAL",
    "FRAME_MAP", "MADMOM_KEY_TO_MUSICAL", "MUSICAL",
    "musical_to_pc_mode", "normalise_musical",
]
