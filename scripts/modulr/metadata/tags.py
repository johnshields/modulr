"""Tag IO across MP3, WAV and M4A.

Backends dispatch on extension:
  * `_ID3Backend` -- handles mp3 + wav (both expose ID3 frames via mutagen)
  * `_MP4Backend` -- handles m4a/mp4/aac via MP4 atoms
TagIO is the public facade; pipelines + CLI use it without caring about format.
"""
import os
import re
import shutil
import sys
from abc import ABC, abstractmethod

from mutagen.aiff import AIFF
from mutagen.mp3 import MP3
from mutagen.wave import WAVE
from mutagen.mp4 import MP4, MP4Cover, MP4FreeForm, AtomDataType
from mutagen.id3 import (
    ID3, TIT2, TPE1, TBPM, TKEY, APIC, error as ID3Error,
)

from ..logger import log, log_error
from ..theory.constants import FRAME_MAP
from ..theory.keys import normalise_musical
from .files import preserve_nnn_prefix, slug


# Logical frame name -> MP4 atom key. Custom key uses iTunes-style freeform atom.
_MP4_ATOMS = {
    "title":  "\xa9nam",
    "artist": "\xa9ART",
    "album":  "\xa9alb",
    "genre":  "\xa9gen",
    "year":   "\xa9day",
}
_MP4_BPM_ATOM = "tmpo"
_MP4_KEY_ATOM = "----:com.apple.iTunes:initialkey"
_MP4_COVER_ATOM = "covr"
_MP4_TRACKNUM_ATOM = "trkn"

_ID3_EXTS = {"mp3", "wav", "aif", "aiff"}
_MP4_EXTS = {"m4a", "mp4", "aac"}


class _Backend(ABC):
    @abstractmethod
    def has_pair(self, path) -> bool: ...
    @abstractmethod
    def read_pair(self, path) -> tuple: ...
    @abstractmethod
    def read_artist(self, path) -> str | None: ...
    @abstractmethod
    def read_title(self, path) -> str | None: ...
    @abstractmethod
    def write_pair(self, path, bpm, musical, title=None, artist=None): ...
    @abstractmethod
    def set_title(self, path, new_title): ...
    @abstractmethod
    def set_tag(self, path, frame, value): ...
    @abstractmethod
    def set_tags(self, path, kvs): ...
    @abstractmethod
    def set_artwork(self, path, data, mime): ...
    @abstractmethod
    def read_artwork(self, path) -> tuple: ...
    @abstractmethod
    def remove_artwork(self, path): ...
    @abstractmethod
    def rewrite_normalised_key(self, path, musical): ...
    @abstractmethod
    def sync_title_to_filename(self, path): ...


class _ID3Backend(_Backend):
    """mp3, wav and aiff. All wrap ID3 frames through mutagen."""

    def _open(self, path):
        ext = path.lower().rsplit(".", 1)[-1]
        cls = MP3 if ext == "mp3" else (AIFF if ext in ("aif", "aiff") else WAVE)
        try:
            audio = cls(path, ID3=ID3) if ext == "mp3" else cls(path)
        except Exception:
            return None
        try:
            audio.add_tags()
        except (ID3Error, Exception):
            pass
        return audio

    @staticmethod
    def _save(audio):
        audio.save(v2_version=3)

    def has_pair(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return False
        return audio.tags.get("TBPM") is not None and audio.tags.get("TKEY") is not None

    def read_pair(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return None, None
        raw_key = None
        if (tag := audio.tags.get("TKEY")) and tag.text:
            raw_key = tag.text[0] or None
        key = normalise_musical(raw_key) if raw_key else None
        bpm = None
        if (tag := audio.tags.get("TBPM")) and tag.text:
            try: bpm = int(tag.text[0])
            except (ValueError, TypeError): pass
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

    def read_title(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None:
            return None
        tag = audio.tags.get("TIT2")
        if not tag or not tag.text:
            return None
        try:
            raw = tag.text[0] or None
        except Exception:
            return None
        return raw or None

    def write_pair(self, path, bpm, musical, title=None, artist=None):
        audio = self._open(path)
        if audio is None: return
        audio.tags.add(TBPM(encoding=3, text=str(bpm)))
        audio.tags.add(TKEY(encoding=3, text=musical))
        if title: audio.tags.add(TIT2(encoding=3, text=title))
        if artist: audio.tags.add(TPE1(encoding=3, text=artist))
        self._save(audio)

    def set_title(self, path, new_title):
        audio = self._open(path)
        if audio is None: log_error(path); return
        audio.tags.add(TIT2(encoding=3, text=new_title))
        self._save(audio)

    def set_tag(self, path, frame, value):
        cls = FRAME_MAP.get(frame)
        if cls is None:
            log_error(f"unknown frame {frame}"); return
        audio = self._open(path)
        if audio is None: log_error(path); return
        if value == "":
            audio.tags.delall(cls.__name__)
        else:
            audio.tags.add(cls(encoding=3, text=str(value)))
        self._save(audio)

    def set_tags(self, path, kvs):
        audio = self._open(path)
        if audio is None: log_error(path); return
        for k, v in kvs.items():
            cls = FRAME_MAP.get(k)
            if cls is None: continue
            if v in (None, ""):
                audio.tags.delall(cls.__name__)
                continue
            audio.tags.add(cls(encoding=3, text=str(v)))
        self._save(audio)

    def set_artwork(self, path, data, mime):
        audio = self._open(path)
        if audio is None: log_error(path); return
        audio.tags.delall("APIC")
        audio.tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=data))
        self._save(audio)

    def read_artwork(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None: return None, None
        pics = audio.tags.getall("APIC")
        if not pics: return None, None
        pic = pics[0]
        return pic.data, (pic.mime or "image/jpeg")

    def remove_artwork(self, path):
        audio = self._open(path)
        if audio is None or audio.tags is None: return
        audio.tags.delall("APIC")
        self._save(audio)

    def rewrite_normalised_key(self, path, musical):
        audio = self._open(path)
        if audio is None: return
        current = audio.tags.get("TKEY")
        if current and current.text and current.text[0] == musical:
            return
        audio.tags.add(TKEY(encoding=3, text=musical))
        try: self._save(audio)
        except Exception: pass

    def sync_title_to_filename(self, path):
        stem = os.path.splitext(os.path.basename(path))[0]
        audio = self._open(path)
        if audio is None: return
        audio.tags.add(TIT2(encoding=3, text=stem))
        self._save(audio)


class _MP4Backend(_Backend):
    """m4a / mp4 / aac. Maps logical frames to MP4 atoms (iTunes convention)."""

    def _open(self, path):
        try:
            return MP4(path)
        except Exception:
            return None

    @staticmethod
    def _save(audio):
        audio.save()

    @staticmethod
    def _freeform(value):
        return MP4FreeForm(value.encode("utf-8"), dataformat=AtomDataType.UTF8)

    @staticmethod
    def _decode_freeform(items):
        if not items: return None
        item = items[0]
        if isinstance(item, MP4FreeForm):
            try: return bytes(item).decode("utf-8", errors="ignore").strip() or None
            except Exception: return None
        if isinstance(item, bytes):
            try: return item.decode("utf-8", errors="ignore").strip() or None
            except Exception: return None
        return str(item).strip() or None

    def has_pair(self, path):
        audio = self._open(path)
        if audio is None: return False
        return _MP4_BPM_ATOM in audio and _MP4_KEY_ATOM in audio

    def read_pair(self, path):
        audio = self._open(path)
        if audio is None: return None, None
        bpm = None
        if (v := audio.get(_MP4_BPM_ATOM)) and v:
            try: bpm = int(v[0])
            except (ValueError, TypeError): pass
        raw_key = self._decode_freeform(audio.get(_MP4_KEY_ATOM))
        key = normalise_musical(raw_key) if raw_key else None
        return key, bpm

    def read_artist(self, path):
        audio = self._open(path)
        if audio is None: return None
        v = audio.get(_MP4_ATOMS["artist"])
        if not v: return None
        try: return str(v[0]).strip() or None
        except Exception: return None

    def read_title(self, path):
        audio = self._open(path)
        if audio is None: return None
        v = audio.get(_MP4_ATOMS["title"])
        if not v: return None
        try: return str(v[0]).strip() or None
        except Exception: return None

    def write_pair(self, path, bpm, musical, title=None, artist=None):
        audio = self._open(path)
        if audio is None: return
        audio[_MP4_BPM_ATOM] = [int(bpm)]
        audio[_MP4_KEY_ATOM] = [self._freeform(musical)]
        if title: audio[_MP4_ATOMS["title"]] = [title]
        if artist: audio[_MP4_ATOMS["artist"]] = [artist]
        self._save(audio)

    def set_title(self, path, new_title):
        audio = self._open(path)
        if audio is None: log_error(path); return
        audio[_MP4_ATOMS["title"]] = [new_title]
        self._save(audio)

    def _atom_for(self, frame):
        if frame == "bpm": return _MP4_BPM_ATOM, "int"
        if frame == "key": return _MP4_KEY_ATOM, "freeform"
        if frame == "tracknum": return _MP4_TRACKNUM_ATOM, "trkn"
        atom = _MP4_ATOMS.get(frame)
        return (atom, "str") if atom else (None, None)

    def set_tag(self, path, frame, value):
        atom, kind = self._atom_for(frame)
        if atom is None:
            log_error(f"unknown frame {frame}"); return
        audio = self._open(path)
        if audio is None: log_error(path); return
        if value == "":
            audio.pop(atom, None)
        elif kind == "int":
            try: audio[atom] = [int(value)]
            except (ValueError, TypeError):
                log_error(f"{frame} expects int"); return
        elif kind == "freeform":
            audio[atom] = [self._freeform(str(value))]
        elif kind == "trkn":
            n, total = self._parse_trkn(str(value))
            audio[atom] = [(n, total)]
        else:
            audio[atom] = [str(value)]
        self._save(audio)

    @staticmethod
    def _parse_trkn(raw):
        """Parse '5' or '5/12' into (5, 12). Default total to 0 when omitted."""
        try:
            if "/" in raw:
                a, b = raw.split("/", 1)
                return int(a), int(b)
            return int(raw), 0
        except (ValueError, TypeError):
            return 0, 0

    def set_tags(self, path, kvs):
        audio = self._open(path)
        if audio is None: log_error(path); return
        for k, v in kvs.items():
            atom, kind = self._atom_for(k)
            if atom is None: continue
            if v in (None, ""):
                audio.pop(atom, None)
                continue
            if kind == "int":
                try: audio[atom] = [int(v)]
                except (ValueError, TypeError): continue
            elif kind == "freeform":
                audio[atom] = [self._freeform(str(v))]
            elif kind == "trkn":
                audio[atom] = [self._parse_trkn(str(v))]
            else:
                audio[atom] = [str(v)]
        self._save(audio)

    def set_artwork(self, path, data, mime):
        audio = self._open(path)
        if audio is None: log_error(path); return
        fmt = MP4Cover.FORMAT_PNG if mime == "image/png" else MP4Cover.FORMAT_JPEG
        audio[_MP4_COVER_ATOM] = [MP4Cover(data, imageformat=fmt)]
        self._save(audio)

    def read_artwork(self, path):
        audio = self._open(path)
        if audio is None: return None, None
        covers = audio.get(_MP4_COVER_ATOM) or []
        if not covers: return None, None
        cov = covers[0]
        mime = "image/png" if cov.imageformat == MP4Cover.FORMAT_PNG else "image/jpeg"
        return bytes(cov), mime

    def remove_artwork(self, path):
        audio = self._open(path)
        if audio is None: return
        audio.pop(_MP4_COVER_ATOM, None)
        self._save(audio)

    def rewrite_normalised_key(self, path, musical):
        audio = self._open(path)
        if audio is None: return
        current = self._decode_freeform(audio.get(_MP4_KEY_ATOM))
        if current == musical: return
        audio[_MP4_KEY_ATOM] = [self._freeform(musical)]
        try: self._save(audio)
        except Exception: pass

    def sync_title_to_filename(self, path):
        stem = os.path.splitext(os.path.basename(path))[0]
        audio = self._open(path)
        if audio is None: return
        audio[_MP4_ATOMS["title"]] = [stem]
        self._save(audio)


class TagIO:
    """Format-aware tag IO. Public API mirrors the legacy mp3-only TagIO."""

    SUPPORTED_EXTS = _ID3_EXTS | _MP4_EXTS

    _id3_backend = _ID3Backend()
    _mp4_backend = _MP4Backend()

    def _backend(self, path) -> _Backend | None:
        ext = path.lower().rsplit(".", 1)[-1]
        if ext in _ID3_EXTS: return self._id3_backend
        if ext in _MP4_EXTS: return self._mp4_backend
        return None

    @classmethod
    def supports(cls, path) -> bool:
        return path.lower().rsplit(".", 1)[-1] in cls.SUPPORTED_EXTS

    # Readers

    def has_pair(self, path):
        b = self._backend(path); return b.has_pair(path) if b else False

    def read_pair(self, path):
        b = self._backend(path); return b.read_pair(path) if b else (None, None)

    def read_artist(self, path):
        b = self._backend(path); return b.read_artist(path) if b else None

    def read_title(self, path):
        b = self._backend(path); return b.read_title(path) if b else None

    # Writers

    def write_pair(self, path, bpm, musical, title=None, artist=None):
        b = self._backend(path)
        if b: b.write_pair(path, bpm, musical, title=title, artist=artist)

    def set_title(self, path, new_title):
        b = self._backend(path)
        if b is None: log_error(path); return
        b.set_title(path, new_title)
        log(f"TITLE_SET: {os.path.basename(path)} -> {new_title}")

    def set_tag(self, path, frame, value):
        b = self._backend(path)
        if b is None: log_error(path); return
        b.set_tag(path, frame, value)
        log(f"TAG_SET: {os.path.basename(path)} {frame}={value}")

    def set_tags(self, path, kvs):
        b = self._backend(path)
        if b is None: log_error(path); return
        b.set_tags(path, kvs)
        log(f"TAGS_SET: {os.path.basename(path)}")

    def carry_metadata(self, src, dst):
        """Mirror text frames + artwork from src to dst after an ffmpeg encode.
        Useful for cross-format conversions where -map_metadata 0 is unreliable
        (especially APIC <-> covr) and for re-encode siblings (_bright, _loud).
        """
        src_b = self._backend(src)
        dst_b = self._backend(dst)
        if src_b is None or dst_b is None:
            return

        # Text frames — read pair (key+bpm) and per-frame names from source.
        key, bpm = src_b.read_pair(src)
        artist = src_b.read_artist(src)
        kvs = {}
        if key: kvs["key"] = key
        if bpm: kvs["bpm"] = bpm
        if artist: kvs["artist"] = artist
        for frame, atom in (("title", "title"), ("album", "album"),
                             ("genre", "genre"), ("year", "year"),
                             ("tracknum", "tracknum")):
            value = self._read_frame_text(src_b, src, frame)
            if value is not None:
                kvs[frame] = value
        if kvs:
            dst_b.set_tags(dst, kvs)

        # Artwork — backend-aware read + write.
        data, mime = src_b.read_artwork(src)
        if data and mime:
            dst_b.set_artwork(dst, data, mime)

    @staticmethod
    def _read_frame_text(backend, path, frame):
        """Backend-agnostic single-frame read for the fields covered by
        FRAME_MAP / _MP4_ATOMS. Returns the raw string value or None.
        """
        audio = backend._open(path)
        if audio is None: return None
        if isinstance(backend, _ID3Backend):
            cls = FRAME_MAP.get(frame)
            if cls is None or audio.tags is None: return None
            tag = audio.tags.get(cls.__name__)
            if not tag or not tag.text: return None
            try: return str(tag.text[0]) or None
            except Exception: return None
        if isinstance(backend, _MP4Backend):
            atom, kind = backend._atom_for(frame)
            if atom is None: return None
            v = audio.get(atom)
            if not v: return None
            if kind == "trkn":
                pair = v[0]
                try:
                    n, total = pair
                    return f"{n}/{total}" if total else str(n)
                except Exception:
                    return str(pair)
            try: return str(v[0]) or None
            except Exception: return None
        return None

    def set_artwork(self, path, image_path, mime):
        b = self._backend(path)
        if b is None: log_error(path); return
        if image_path == "/dev/stdin":
            data = sys.stdin.buffer.read()
        else:
            with open(image_path, "rb") as f:
                data = f.read()
        b.set_artwork(path, data, mime)
        log(f"ARTWORK_SET: {os.path.basename(path)}")

    def remove_artwork(self, path):
        b = self._backend(path)
        if b is None: return
        b.remove_artwork(path)
        log(f"ARTWORK_REMOVED: {os.path.basename(path)}")

    def rewrite_normalised_key(self, path, musical):
        b = self._backend(path)
        if b: b.rewrite_normalised_key(path, musical)

    # Title to filename invariant

    def sync_title_to_filename(self, path):
        b = self._backend(path)
        if b: b.sync_title_to_filename(path)

    def rename_and_sync_title(self, old_path, new_path):
        """Move file then sync title tag to new stem. Returns True iff moved."""
        if old_path != new_path:
            if os.path.exists(new_path):
                return False
            shutil.move(old_path, new_path)
        self.sync_title_to_filename(new_path)
        return old_path != new_path

    # Filename derivation that needs tag access

    def build_clean_stem(self, path, filename):
        """Canonical title-only stem from the TITLE tag or filename,
        stripping trailing _KEY_BPM, leading NNN_, and ARTIST-tag tokens.
        """
        artist = self.read_artist(path)
        title_tag = self.read_title(path)
        if title_tag:
            raw = title_tag
            # Drop a leading "Artist - " from the title when no ARTIST tag exists.
            if not artist:
                halves = re.split(r"\s[-–—]\s", raw, maxsplit=1)
                if len(halves) == 2:
                    raw = halves[1]
            # Strip a trailing _KEY_BPM (musical, Camelot or Open Key) before slugging.
            raw = re.sub(r"_(?:[A-G][#b]?m?|\d{1,2}[abmd])_\d{2,3}$", "", raw, flags=re.IGNORECASE)
            title_part = slug(raw)
            # Drop a trailing slugged digit key.
            title_part = re.sub(r"-\d{1,2}[abmd]-\d{2,3}$", "", title_part)
        else:
            stem, _ext = os.path.splitext(filename)
            halves = re.split(r"\s[-–—]\s", stem, maxsplit=1)
            if len(halves) == 2:
                stem = halves[1]
            parts = stem.split("_")
            while (len(parts) >= 3
                   and parts[-1].isdigit()
                   and re.match(r"^[A-Za-z0-9#]{1,6}$", parts[-2])):
                parts = parts[:-2]
            if len(parts) >= 2 and re.match(r"^\d{2,3}$", parts[0]):
                parts = parts[1:]
            title_part = slug(parts[0]) if parts else ""

        # Drop a featured-artist clause; those names belong in the ARTIST tag.
        title_part = re.sub(r"-(?:feat|ft|featuring)(?:-.*)?$", "", title_part)
        stripped = self._strip_artist_tokens(title_part, artist)
        stripped = self._strip_edition(stripped)
        # Keep a named remixer even when it lives only in the filename.
        phrase = (self._extract_remix_phrase(title_tag or "")
                  or self._extract_remix_phrase(os.path.splitext(filename)[0]))
        if phrase:
            pslug = slug(phrase)
            if pslug and pslug not in stripped:
                stripped = f"{stripped}-{pslug}" if stripped else pslug
        return stripped

    @staticmethod
    def _strip_artist_tokens(title_part, artist):
        """Drop slug tokens that match the artist, regardless of dash position."""
        if not artist:
            return title_part
        artist_tokens = {t for t in slug(artist).split("-") if t}
        if not artist_tokens:
            return title_part
        tokens = title_part.split("-")
        cleaned = "-".join(t for t in tokens if t and t not in artist_tokens)
        return cleaned or title_part

    _EDITIONS = sorted([
        "extended-mix", "extended-version", "extended-edit",
        "original-mix", "original-version", "original-edit",
        "radio-edit", "radio-version", "radio-mix",
        "club-mix", "club-edit", "album-version", "single-version",
    ], key=len, reverse=True)

    @classmethod
    def _strip_edition(cls, stem):
        """Drop a trailing generic edition (Original Mix, Extended Version, ...)."""
        for ed in cls._EDITIONS:
            if stem != ed and stem.endswith("-" + ed):
                return stem[: -len(ed) - 1]
        return stem

    _REMIX_KINDS = {"remix", "edit", "bootleg", "vip", "flip", "rework",
                    "refix", "dub", "mix", "version", "remake"}

    @classmethod
    def _extract_remix_phrase(cls, raw):
        """Full '(Name Remix/Edit/...)' phrase, e.g. 'Han Conscious Remix'; '' for generic editions."""
        editions = set(cls._EDITIONS)
        for grp in re.findall(r"\(([^)]*)\)", raw or ""):
            grp = grp.strip()
            if not grp or slug(grp) in editions:
                continue
            words = grp.split()
            if len(words) >= 2 and words[-1].lower() in cls._REMIX_KINDS:
                return grp
        return ""

    @classmethod
    def _remixer_name(cls, raw):
        """Remixer name without the kind word, e.g. 'Han Conscious'."""
        phrase = cls._extract_remix_phrase(raw)
        return " ".join(phrase.split()[:-1]) if phrase else ""

    def derived_artist(self, path, filename):
        """Artist credit: original artist plus any remixer named in the title or filename.
        Original comes from the ARTIST tag, else the leading 'Artist - ' of the title.
        """
        existing = (self.read_artist(path) or "").strip()
        title_tag = self.read_title(path)
        raw = title_tag or os.path.splitext(filename)[0]
        remixer = self._remixer_name(title_tag or "") or self._remixer_name(os.path.splitext(filename)[0])
        if existing:
            original = existing
        else:
            halves = re.split(r"\s[-–—]\s", raw, maxsplit=1)
            original = halves[0].strip() if len(halves) == 2 else ""
        if not remixer or remixer.lower() in original.lower():
            return original
        return f"{original}, {remixer}" if original else remixer

    def derived_dj_name(self, path, key, bpm, keep_numbers=False):
        """Canonical NNN_stem_KEY_BPM<ext> name, preserving original extension."""
        filename = os.path.basename(path)
        stem = self.build_clean_stem(path, filename)
        ext = os.path.splitext(filename)[1].lower() or ".mp3"
        new_name = f"{stem}_{key}_{bpm}{ext}"
        if keep_numbers:
            new_name = preserve_nnn_prefix(filename, new_name)
        return new_name
