"""End-to-end pipelines orchestrating analysers + tag IO + filename ops.
Each pipeline class owns one CLI-facing operation:
  AnalysePipeline        -- detect BPM/key, write tags, optional rename
  ResetPipeline          -- strip _KEY_BPM and NNN_ from filenames
  SyncFilenamePipeline   -- append _KEY_BPM to filenames using existing tags
  ConvertPipeline        -- transcode wav/m4a to 320 kbps MP3 via ffmpeg
  BrightenPipeline       -- ffmpeg exciter + high-shelf for dull / lossy tracks
"""
import os

from .analysis.analyser import TrackAnalyser, default_analyser
from .logger import log, log_done, log_error, log_progress
from .mastering.ffmpeg import FfmpegRunner
from .metadata.files import list_audio, preserve_nnn_prefix
from .metadata.tags import TagIO

_TAG_EXTS = (".mp3", ".m4a", ".wav", ".mp4", ".aac", ".aif", ".aiff")


class _BasePipeline:
    """Shared dependency wiring + folder iteration plumbing."""

    def __init__(self, tag_io: TagIO | None = None):
        self.tag_io = tag_io or TagIO()

    def _iterate_folder(self, folder, handler, **kwargs):
        files = list_audio(folder, exts=_TAG_EXTS)
        log(f"TOTAL: {len(files)}")
        for i, path in enumerate(files, 1):
            handler(path, idx=i, total=len(files), **kwargs)
        log_done()


class AnalysePipeline(_BasePipeline):
    """Detect BPM + key, write tags, optionally rename to DJ format.
    Already-tagged tracks short-circuit detection but still rename on demand.
    """

    def __init__(self, analyser: TrackAnalyser | None = None,
                 tag_io: TagIO | None = None):
        super().__init__(tag_io)
        self.analyser = analyser or default_analyser()

    def run_one(self, path, do_rename, idx=None, total=None,
                allow_skip=True):
        filename = os.path.basename(path)
        if idx is not None:
            log_progress(idx, total, filename)

        musical, bpm = self._resolve(path, filename, allow_skip)
        if musical is None:
            return
        if do_rename:
            self._rename_to_dj(path, filename, musical, bpm)

    def run_folder(self, folder, do_rename, only_untagged=False):
        """Iterate over folder. When `only_untagged` is set, pre-filter the
        list so progress reflects the un-analysed subset only, instead of
        marching past every track and printing SKIP for the tagged ones.
        """
        import os
        from .metadata.files import list_audio
        files = list_audio(folder, exts=_TAG_EXTS)
        if only_untagged:
            files = [p for p in files if not self.tag_io.has_pair(p)]
        log(f"TOTAL: {len(files)}")
        for i, path in enumerate(files, 1):
            self.run_one(
                path, do_rename,
                idx=i, total=len(files),
                allow_skip=not only_untagged,
            )
        log_done()

    def _resolve(self, path, filename, allow_skip):
        """Return (musical, bpm) — either from tags (skip) or fresh detection."""
        if allow_skip and self.tag_io.has_pair(path):
            existing_key, existing_bpm = self.tag_io.read_pair(path)
            if existing_key and existing_bpm:
                self.tag_io.rewrite_normalised_key(path, existing_key)
                log(f"SKIP: {filename} (already tagged) "
                    f"key={existing_key} bpm={existing_bpm}")
                return existing_key, existing_bpm
            log(f"SKIP: {filename} (already tagged)")
            return None, None

        try:
            _, musical, bpm = self.analyser.analyse(path)
        except Exception as e:
            log_error(f"{filename}: {e}")
            return None, None
        log(f"RESULT: {filename} key={musical} bpm={bpm}")
        self.tag_io.write_pair(path, bpm, musical)
        return musical, bpm

    def _rename_to_dj(self, path, filename, musical, bpm):
        directory = os.path.dirname(path)
        ext = os.path.splitext(filename)[1].lower() or ".mp3"
        clean = self.tag_io.build_clean_stem(path, filename)
        # Resolve the artist credit before the move.
        artist = self.tag_io.derived_artist(path, filename)
        suffix = f"_{musical}_{bpm}"
        new_name = f"{clean}{suffix}{ext}"
        new_path = os.path.join(directory, new_name)
        if new_path == path:
            self.tag_io.sync_title_to_filename(path)
            self._apply_artist(path, artist)
            return
        # Disambiguate a clashing target, preserving the _KEY_BPM suffix.
        n = 2
        while os.path.exists(new_path):
            new_name = f"{clean}-{n}{suffix}{ext}"
            new_path = os.path.join(directory, new_name)
            n += 1
        if self.tag_io.rename_and_sync_title(path, new_path):
            log(f"RENAMED: {filename} -> {new_name}")
            self._apply_artist(new_path, artist)

    def _apply_artist(self, path, artist):
        """Write the ARTIST tag only when it changes."""
        if not artist:
            return
        if (self.tag_io.read_artist(path) or "").strip() == artist:
            return
        self.tag_io.set_tag(path, "artist", artist)


class ResetPipeline(_BasePipeline):
    """Strip _KEY_BPM and leading NNN_ from filenames."""

    def run_one(self, path, idx=None, total=None):
        filename = os.path.basename(path)
        if idx is not None:
            log_progress(idx, total, filename)

        stem = self.tag_io.build_clean_stem(path, filename)
        if not stem:
            log(f"SKIP: {filename} (empty stem)")
            return

        ext = os.path.splitext(filename)[1].lower() or ".mp3"
        new_name = f"{stem}{ext}"
        new_path = os.path.join(os.path.dirname(path), new_name)
        if new_path == path:
            self.tag_io.sync_title_to_filename(path)
            log(f"OK: {filename} (synced title)")
            return
        if os.path.exists(new_path):
            log(f"SKIP: {filename} -> {new_name} (collision)")
            return
        if self.tag_io.rename_and_sync_title(path, new_path):
            log(f"RENAMED: {filename} -> {new_name}")

    def run_folder(self, folder):
        self._iterate_folder(folder, self.run_one)


class SyncFilenamePipeline(_BasePipeline):
    """Append _KEY_BPM suffix to filenames using existing TKEY/TBPM tags."""

    def run(self, folder):
        files = list_audio(folder, exts=_TAG_EXTS)
        log(f"TOTAL: {len(files)}")
        for i, path in enumerate(files, 1):
            name = os.path.basename(path)
            log_progress(i, len(files), name)
            self._sync_one(path, name)
        log_done()

    def _sync_one(self, path, name):
        key, bpm = self.tag_io.read_pair(path)
        if not key or not bpm:
            log(f"SKIP: {name} (missing tags)")
            return
        suffix = f"_{key}_{bpm}"
        stem_no_ext, ext = os.path.splitext(name)
        if stem_no_ext.lower().endswith(suffix.lower()):
            log(f"OK: {name} (already has suffix)")
            return
        clean = self.tag_io.build_clean_stem(path, name)
        new_name = preserve_nnn_prefix(name, f"{clean}{suffix}{ext or '.mp3'}")
        new_path = os.path.join(os.path.dirname(path), new_name)
        if new_path == path:
            self.tag_io.sync_title_to_filename(path)
            log(f"OK: {name} (synced title)")
            return
        if os.path.exists(new_path):
            log(f"SKIP: {name} -> {new_name} (collision)")
            return
        if self.tag_io.rename_and_sync_title(path, new_path):
            log(f"RENAMED: {name} -> {new_name}")


class ConvertPipeline(_BasePipeline):
    """Transcode wav/m4a to 320 kbps CBR MP3, preserving metadata.
    Output sits next to the source with the same stem; original is left intact
    so Swift can move it to Trash atomically after the convert succeeds.
    """

    BITRATE = "320k"

    def __init__(self, ffmpeg: FfmpegRunner | None = None,
                 tag_io: TagIO | None = None):
        super().__init__(tag_io)
        self._ffmpeg = ffmpeg or FfmpegRunner()

    def convert_folder(self, folder, delete_original=False):
        """Transcode every non-mp3 file in folder. Skips mp3s and existing targets."""
        files = [p for p in list_audio(folder, exts=_TAG_EXTS)
                 if os.path.splitext(p)[1].lower() != ".mp3"]
        log(f"TOTAL: {len(files)}")
        if not files:
            log_done(); return
        try:
            self._ffmpeg.binary()
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return

        for i, src in enumerate(files, 1):
            name = os.path.basename(src)
            log_progress(i, len(files), name)
            self._convert_one(src, log_label=name, delete_original=delete_original)
        log_done()

    def convert_to_mp3(self, src_path):
        name = os.path.basename(src_path)
        log_progress(1, 1, name)
        try:
            self._ffmpeg.binary()
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return
        self._convert_one(src_path, log_label=name, delete_original=False)
        log_done()

    def _convert_one(self, src_path, log_label, delete_original):
        stem, ext = os.path.splitext(src_path)
        if ext.lower() == ".mp3":
            log_error(f"{log_label} is already mp3"); return
        dst = f"{stem}.mp3"
        if os.path.exists(dst):
            log_error(f"{os.path.basename(dst)} already exists"); return

        log(f"CONVERTING: {log_label} -> {os.path.basename(dst)} @ {self.BITRATE}")
        # -cutoff 22050 disables LAME's default ~19 kHz lowpass so the MP3
        # keeps the source's full top-end (matters for WAV/m4a -> MP3 fidelity
        # scoring). Skipping -compression_level since ffmpeg's wrapper inverts
        # LAME's quality scale and the default (5) is already good.
        ok, err = self._ffmpeg.transcode(
            src_path, dst,
            codec="libmp3lame", bitrate=self.BITRATE,
            extra_args=["-cutoff", "22050"],
        )
        if not ok:
            log_error(f"ffmpeg: {(err or '')[:200]}")
            return
        # Carry tags + artwork — ffmpeg -map_metadata 0 is unreliable for APIC
        # across format boundaries (esp. wav/m4a -> mp3).
        self.tag_io.carry_metadata(src_path, dst)
        log(f"CONVERTED: {os.path.basename(dst)}")
        if delete_original:
            try:
                os.unlink(src_path)
                log(f"REMOVED_SOURCE: {log_label}")
            except Exception as e:
                log_error(f"could not remove source: {e}")


class BrightenPipeline(_BasePipeline):
    """ffmpeg exciter + treble shelf for dull / lossy tracks.
    Writes a `_bright` sibling next to the source so the caller can A/B before
    committing. Bitrate matches the source (mp3 / m4a) or PCM for wav.
    """

    BITRATE = "320k"
    EXCITER = "aexciter=amount=2.5:drive=3:blend=0:freq=7500:ceil=11000:listen=disabled"
    SHELF = "treble=g=3.5:f=10000:width_type=q:width=0.7"
    LIMITER = "alimiter=limit=0.97"
    EXT_TO_CODEC = {"mp3": "libmp3lame", "m4a": "aac", "aac": "aac", "wav": "pcm_s16le"}

    def __init__(self, ffmpeg: FfmpegRunner | None = None,
                 tag_io: TagIO | None = None):
        super().__init__(tag_io)
        self._ffmpeg = ffmpeg or FfmpegRunner()

    def brighten(self, src_path):
        name = os.path.basename(src_path)
        log_progress(1, 1, name)
        try:
            self._ffmpeg.binary()
        except FileNotFoundError as e:
            log_error(str(e)); log_done(); return

        stem, ext = os.path.splitext(src_path)
        dst = f"{stem}_bright{ext}"
        if os.path.exists(dst):
            log_error(f"{os.path.basename(dst)} already exists"); log_done(); return

        codec = self.EXT_TO_CODEC.get(ext.lower().lstrip("."), "copy")
        filters = ",".join([self.EXCITER, self.SHELF, self.LIMITER])
        bitrate = None if codec == "pcm_s16le" else self.BITRATE

        log(f"BRIGHTENING: {name} -> {os.path.basename(dst)}")
        ok, err = self._ffmpeg.transcode(
            src_path, dst, filters=filters, codec=codec, bitrate=bitrate,
        )
        if not ok:
            log_error(f"ffmpeg: {(err or '')[:200]}")
            log_done(); return
        self.tag_io.carry_metadata(src_path, dst)
        log(f"BRIGHTENED: {os.path.basename(dst)}")
        log_done()
