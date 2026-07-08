"""Filename + folder helpers — listing, slugging, NNN_ prefix preservation."""
import os
import re
import unicodedata

from ..theory.constants import AUDIO_EXT_LOUDNESS


def list_mp3s(folder):
    return sorted(
        os.path.join(folder, f)
        for f in os.listdir(folder)
        if f.lower().endswith(".mp3") and not f.startswith(".")
    )


def list_audio(folder, exts=AUDIO_EXT_LOUDNESS):
    return sorted(
        os.path.join(folder, f)
        for f in os.listdir(folder)
        if f.lower().endswith(exts) and not f.startswith(".")
    )


def slug(s):
    """Lowercase hyphenated. Strips trailing -KEY-BPM and leading NNN-."""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.strip().lower()
    s = re.sub(r"['‘’ʼ`]", "", s)
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    while True:
        new = re.sub(r"-[a-z#]{1,6}-\d{2,3}$", "", s)
        if new == s:
            break
        s = new
    return re.sub(r"^\d{2,3}-", "", s)


NNN_PREFIX = re.compile(r"^\d{2,4}_")


def preserve_nnn_prefix(orig_filename, new_name):
    """Prepend NNN_ from orig if missing on new_name."""
    m = NNN_PREFIX.match(orig_filename)
    if m and not new_name.startswith(m.group(0)):
        return m.group(0) + new_name
    return new_name
