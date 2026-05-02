"""Key-name normalisation. Every key form converges on short MUSICAL ('Em', 'F#', 'Bbm')."""
import re

from .constants import CAMELOT_TO_MUSICAL, MADMOM_KEY_TO_MUSICAL, MUSICAL


def normalise_musical(raw):
    """Map any key form (Camelot, 'emin', 'C# minor', 'Eb min', etc.) to short MUSICAL."""
    if not raw:
        return None
    s = raw.strip()

    if s.upper() in CAMELOT_TO_MUSICAL:
        return CAMELOT_TO_MUSICAL[s.upper()]
    if s in MADMOM_KEY_TO_MUSICAL:
        return MADMOM_KEY_TO_MUSICAL[s]

    pitch, rest = _split_pitch(s.replace(" ", ""))
    if pitch is None:
        return raw

    rest_lower = rest.lower()
    is_minor = (rest_lower.startswith("min")
                or rest_lower == "m"
                or rest_lower.startswith("moll"))
    return pitch + ("m" if is_minor else "")


def musical_to_pc_mode(musical):
    """'Em' -> (4, 0). 'D' -> (2, 1). Raises if unmapped."""
    for (pc, mode), label in MUSICAL.items():
        if label == musical:
            return pc, mode
    raise ValueError(f"unmapped musical {musical!r}")


def _split_pitch(rest):
    """Strip leading pitch + accidental from rest. Returns (pitch_string, remainder)."""
    if len(rest) >= 2 and rest[1] in ("#", "b", "B") and rest[0].isalpha():
        if rest[1] == "B" and rest[0].upper() in "ACDEFG":
            third = rest[2:3]
            if third.isalpha() and third.upper() != "M":
                return rest[0].upper(), rest[1:]
            return rest[0].upper() + "b", rest[2:]
        accidental = "#" if rest[1] == "#" else "b"
        return rest[0].upper() + accidental, rest[2:]
    if rest and rest[0].isalpha():
        return rest[0].upper(), rest[1:]
    return None, rest
