"""ID3 tag IO. All file mutations preserve unrelated frames (artwork, etc)."""
import os
import re
import shutil
import sys

from mutagen.mp3 import MP3
from mutagen.id3 import (
    ID3, TIT2, TPE1, TBPM, TKEY, APIC, error as ID3Error,
)

from ..logger import log, log_error
from ..theory.constants import FRAME_MAP
from ..theory.keys import normalise_musical
from .files import preserve_nnn_prefix, slug


class TagIO:
    """Read + write ID3 tags. All ops preserve other frames (notably APIC)."""

    # Internal mutagen handle helpers

    @staticmethod
    def _open(path):
        try:
            audio = MP3(path, ID3=ID3)
        except Exception:
            return None
        try:
            audio.add_tags()
        except ID3Error:
            pass
        return audio

    @staticmethod
    def _save(audio):
        audio.save(v2_version=3)

    # Readers

    def has_pair(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return False
        return audio.tags.get("TBPM") is not None and audio.tags.get("TKEY") is not None

    def read_pair(self, path):
        """Return (musical_key, bpm) from existing tags, or (None, None)."""
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return None, None
        raw_key = None
        if (tag := audio.tags.get("TKEY")) and tag.text:
            raw_key = tag.text[0] or None
        key = normalise_musical(raw_key) if raw_key else None
        bpm = None
        if (tag := audio.tags.get("TBPM")) and tag.text:
            try:
                bpm = int(tag.text[0])
            except (ValueError, TypeError):
                pass
        return key, bpm

    def read_artist(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return None
        tag = audio.tags.get("TPE1")
        if not tag or not tag.text:
            return None
        try:
            return tag.text[0] or None
        except Exception:
            return None

    # Writers

    def write_pair(self, path, bpm, musical, title=None, artist=None):
        audio = self._open(path)
        if audio is None:
            return
        audio.tags.add(TBPM(encoding=3, text=str(bpm)))
        audio.tags.add(TKEY(encoding=3, text=musical))
        if title:
            audio.tags.add(TIT2(encoding=3, text=title))
        if artist:
            audio.tags.add(TPE1(encoding=3, text=artist))
        self._save(audio)

    def set_title(self, path, new_title):
        audio = self._open(path)
        if audio is None:
            log_error(path); return
        audio.tags.add(TIT2(encoding=3, text=new_title))
        self._save(audio)
        log(f"TITLE_SET: {os.path.basename(path)} -> {new_title}")

    def set_tag(self, path, frame, value):
        cls = FRAME_MAP.get(frame)
        if cls is None:
            log_error(f"unknown frame {frame}"); return
        audio = self._open(path)
        if audio is None:
            log_error(path); return
        if value == "":
            audio.tags.delall(cls.__name__)
        else:
            audio.tags.add(cls(encoding=3, text=str(value)))
        self._save(audio)
        log(f"TAG_SET: {os.path.basename(path)} {frame}={value}")

    def set_tags(self, path, kvs):
        audio = self._open(path)
        if audio is None:
            log_error(path); return
        for k, v in kvs.items():
            cls = FRAME_MAP.get(k)
            if cls is None:
                continue
            if v in (None, ""):
                audio.tags.delall(cls.__name__)
                continue
            audio.tags.add(cls(encoding=3, text=str(v)))
        self._save(audio)
        log(f"TAGS_SET: {os.path.basename(path)}")

    def set_artwork(self, path, image_path, mime):
        audio = self._open(path)
        if audio is None:
            log_error(path); return
        if image_path == "/dev/stdin":
            data = sys.stdin.buffer.read()
        else:
            with open(image_path, "rb") as f:
                data = f.read()
        audio.tags.delall("APIC")
        audio.tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=data))
        self._save(audio)
        log(f"ARTWORK_SET: {os.path.basename(path)}")

    def remove_artwork(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return
        audio.tags.delall("APIC")
        self._save(audio)
        log(f"ARTWORK_REMOVED: {os.path.basename(path)}")

    def rewrite_normalised_key(self, path, musical):
        """Force TKEY into canonical short form so subsequent reads are clean."""
        audio = self._open(path)
        if audio is None:
            return
        current = audio.tags.get("TKEY")
        if current and current.text and current.text[0] == musical:
            return
        audio.tags.add(TKEY(encoding=3, text=musical))
        try:
            self._save(audio)
        except Exception:
            pass

    # Title to filename invariant

    def sync_title_to_filename(self, path):
        """TIT2 := filename stem (literal). Always identical, no transforms."""
        if not path.lower().endswith(".mp3"):
            return
        stem = os.path.splitext(os.path.basename(path))[0]
        audio = self._open(path)
        if audio is None:
            return
        audio.tags.add(TIT2(encoding=3, text=stem))
        self._save(audio)

    def rename_and_sync_title(self, old_path, new_path):
        """Move file then sync TIT2 to new stem. Returns True iff actually moved."""
        if old_path != new_path:
            if os.path.exists(new_path):
                return False
            shutil.move(old_path, new_path)
        self.sync_title_to_filename(new_path)
        return old_path != new_path

    # Filename derivation that needs tag access

    def build_clean_stem(self, path, filename):
        """Canonical title-only stem.
        Strips trailing _KEY_BPM, leading NNN_, and any tokens matching TPE1 artist.
        """
        stem = filename[:-4]
        parts = stem.split("_")
        while (len(parts) >= 3
               and parts[-1].isdigit()
               and re.match(r"^[A-Za-z0-9#]{1,6}$", parts[-2])):
            parts = parts[:-2]
        if len(parts) >= 2 and re.match(r"^\d{2,3}$", parts[0]):
            parts = parts[1:]
        title_part = slug(parts[0]) if parts else ""

        artist = self.read_artist(path)
        if not artist:
            return title_part
        artist_tokens = {t for t in re.split(r"[^a-z0-9]+", slug(artist)) if t}
        if not artist_tokens:
            return title_part
        tokens = re.split(r"[-_]+", title_part)
        cleaned = "-".join(t for t in tokens if t and t.lower() not in artist_tokens)
        return cleaned or title_part

    def derived_dj_name(self, path, key, bpm, keep_numbers=False):
        """Build canonical NNN_stem_KEY_BPM.mp3 name for given track."""
        filename = os.path.basename(path)
        stem = self.build_clean_stem(path, filename)
        new_name = f"{stem}_{key}_{bpm}.mp3"
        if keep_numbers:
            new_name = preserve_nnn_prefix(filename, new_name)
        return new_name
