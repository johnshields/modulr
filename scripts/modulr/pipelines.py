"""End-to-end pipelines orchestrating analysers + tag IO + filename ops.
Each pipeline class owns one CLI-facing operation:
  AnalysePipeline        -- detect BPM/key, write tags, optional rename
  ResetPipeline          -- strip _KEY_BPM and NNN_ from filenames
  StripNumbersPipeline   -- strip leading NNN_ from filenames; keep _KEY_BPM
  SyncFilenamePipeline   -- append _KEY_BPM to filenames using existing tags
"""
import os
import re

from .analysis.analyser import TrackAnalyser, default_analyser
from .logger import log, log_done, log_error, log_progress
from .metadata.files import list_mp3s, preserve_nnn_prefix
from .metadata.tags import TagIO


class _BasePipeline:
    """Shared dependency wiring + folder iteration plumbing."""

    def __init__(self, tag_io: TagIO | None = None):
        self.tag_io = tag_io or TagIO()

    def _iterate_folder(self, folder, handler, **kwargs):
        files = list_mp3s(folder)
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
                allow_skip=True, keep_numbers=False):
        filename = os.path.basename(path)
        if idx is not None:
            log_progress(idx, total, filename)

        musical, bpm = self._resolve(path, filename, allow_skip)
        if musical is None:
            return
        if do_rename:
            self._rename_to_dj(path, filename, musical, bpm, keep_numbers)

    def run_folder(self, folder, do_rename, keep_numbers=False):
        self._iterate_folder(
            folder, self.run_one,
            do_rename=do_rename,
            allow_skip=True,
            keep_numbers=keep_numbers,
        )

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

    def _rename_to_dj(self, path, filename, musical, bpm, keep_numbers):
        new_name = self.tag_io.derived_dj_name(path, musical, bpm, keep_numbers=keep_numbers)
        new_path = os.path.join(os.path.dirname(path), new_name)
        if new_path == path:
            self.tag_io.sync_title_to_filename(path)
        elif self.tag_io.rename_and_sync_title(path, new_path):
            log(f"RENAMED: {filename} -> {new_name}")


class ResetPipeline(_BasePipeline):
    """Strip _KEY_BPM and (optionally) leading NNN_ from filenames."""

    def run_one(self, path, idx=None, total=None, keep_numbers=False):
        filename = os.path.basename(path)
        if idx is not None:
            log_progress(idx, total, filename)

        stem = self.tag_io.build_clean_stem(path, filename)
        if not stem:
            log(f"SKIP: {filename} (empty stem)")
            return
        if keep_numbers:
            stem = preserve_nnn_prefix(filename, stem)

        new_name = f"{stem}.mp3"
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

    def run_folder(self, folder, keep_numbers=False):
        self._iterate_folder(folder, self.run_one, keep_numbers=keep_numbers)


class StripNumbersPipeline(_BasePipeline):
    """Remove leading NNN_ order prefix from filenames; preserve everything else."""

    NNN_PREFIX = re.compile(r"^\d{2,4}_")

    def run_one(self, path, idx=None, total=None):
        filename = os.path.basename(path)
        if idx is not None:
            log_progress(idx, total, filename)

        new_name = self.NNN_PREFIX.sub("", filename, count=1)
        if new_name == filename:
            log(f"OK: {filename} (no number prefix)")
            return
        new_path = os.path.join(os.path.dirname(path), new_name)
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
        files = list_mp3s(folder)
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
        if name[:-4].lower().endswith(suffix.lower()):
            log(f"OK: {name} (already has suffix)")
            return
        clean = self.tag_io.build_clean_stem(path, name)
        new_name = preserve_nnn_prefix(name, f"{clean}{suffix}.mp3")
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
