"""Static lookup tables used across modules."""
from mutagen.id3 import TIT2, TPE1, TALB, TCON, TBPM, TKEY, TDRC, TRCK


# (pitch_class, mode) -> Camelot wheel label. major=1, minor=0
CAMELOT = {
    (0,  1): "8B",  (0,  0): "5A",
    (1,  1): "3B",  (1,  0): "12A",
    (2,  1): "10B", (2,  0): "7A",
    (3,  1): "5B",  (3,  0): "2A",
    (4,  1): "12B", (4,  0): "9A",
    (5,  1): "7B",  (5,  0): "4A",
    (6,  1): "2B",  (6,  0): "11A",
    (7,  1): "9B",  (7,  0): "6A",
    (8,  1): "4B",  (8,  0): "1A",
    (9,  1): "11B", (9,  0): "8A",
    (10, 1): "6B",  (10, 0): "3A",
    (11, 1): "1B",  (11, 0): "10A",
}

# (pitch_class, mode) -> short musical label
MUSICAL = {
    (0,  1): "C",   (0,  0): "Cm",
    (1,  1): "Db",  (1,  0): "Dbm",
    (2,  1): "D",   (2,  0): "Dm",
    (3,  1): "Eb",  (3,  0): "Ebm",
    (4,  1): "E",   (4,  0): "Em",
    (5,  1): "F",   (5,  0): "Fm",
    (6,  1): "F#",  (6,  0): "F#m",
    (7,  1): "G",   (7,  0): "Gm",
    (8,  1): "Ab",  (8,  0): "Abm",
    (9,  1): "A",   (9,  0): "Am",
    (10, 1): "Bb",  (10, 0): "Bbm",
    (11, 1): "B",   (11, 0): "Bm",
}

CAMELOT_TO_MUSICAL = {
    "1A": "Abm", "1B": "B",   "2A": "Ebm", "2B": "F#",
    "3A": "Bbm", "3B": "Db",  "4A": "Fm",  "4B": "Ab",
    "5A": "Cm",  "5B": "Eb",  "6A": "Gm",  "6B": "Bb",
    "7A": "Dm",  "7B": "F",   "8A": "Am",  "8B": "C",
    "9A": "Em",  "9B": "G",   "10A": "Bm", "10B": "D",
    "11A": "F#m","11B": "A",  "12A": "Dbm","12B": "E",
}

# madmom CNNKeyRecognitionProcessor returns "C major" / "C# minor" form.
MADMOM_KEY_TO_MUSICAL = {
    "C major":"C","C# major":"Db","Db major":"Db","D major":"D",
    "D# major":"Eb","Eb major":"Eb","E major":"E","F major":"F",
    "F# major":"F#","Gb major":"F#","G major":"G","G# major":"Ab",
    "Ab major":"Ab","A major":"A","A# major":"Bb","Bb major":"Bb",
    "B major":"B",
    "C minor":"Cm","C# minor":"Dbm","Db minor":"Dbm","D minor":"Dm",
    "D# minor":"Ebm","Eb minor":"Ebm","E minor":"Em","F minor":"Fm",
    "F# minor":"F#m","Gb minor":"F#m","G minor":"Gm","G# minor":"Abm",
    "Ab minor":"Abm","A minor":"Am","A# minor":"Bbm","Bb minor":"Bbm",
    "B minor":"Bm",
}

# Logical frame name -> mutagen ID3 frame class
FRAME_MAP = {
    "title": TIT2, "artist": TPE1, "album": TALB,
    "genre": TCON, "bpm": TBPM, "year": TDRC, "key": TKEY,
    "tracknum": TRCK,
}

AUDIO_EXT_LOUDNESS = (".mp3", ".m4a", ".wav", ".aac", ".aif", ".aiff")
