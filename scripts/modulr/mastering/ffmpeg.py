"""ffmpeg facade — binary discovery, encode jobs, volume measurement, gain apply."""
import os
import shutil
import subprocess
import tempfile


class FfmpegRunner:
    """Resolves the ffmpeg binary + runs encode jobs.
    macOS apps inherit minimal PATH so the binary is searched explicitly.
    """

    SEARCH_PATHS = (
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
    )

    EXT_TO_CODEC = {
        "mp3": "libmp3lame",
        "m4a": "aac",
        "aac": "aac",
        "wav": "pcm_s16le",
    }

    def __init__(self):
        self._cached_bin = None

    def binary(self):
        if self._cached_bin:
            return self._cached_bin
        if found := shutil.which("ffmpeg"):
            self._cached_bin = found
            return found
        for p in self.SEARCH_PATHS:
            if os.path.exists(p):
                self._cached_bin = p
                return p
        raise FileNotFoundError("ffmpeg not found. Install via `brew install ffmpeg`.")

    def codec_for(self, path):
        ext = os.path.splitext(path)[1].lower().lstrip(".")
        return self.EXT_TO_CODEC.get(ext, "copy")

    def encode(self, src, filter_chain):
        """Encode src through filter_chain to a temp file. Returns (out_path, err_text).
        Used by the in-place ops (loudness boost, tempo/pitch bake) that swap
        the result back over the original via shutil.move.
        """
        ext = os.path.splitext(src)[1].lower()
        tmp = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
        tmp.close()
        ok, err = self.transcode(src, tmp.name, filters=filter_chain, quality="0")
        if not ok:
            return None, err
        return tmp.name, None

    def trim_tail(self, src, end_seconds):
        """Copy src up to end_seconds into a temp file, no re-encode.
        Returns (out_path, err_text).
        """
        ext = os.path.splitext(src)[1].lower()
        tmp = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
        tmp.close()
        cmd = [self.binary(), "-y", "-hide_banner", "-loglevel", "error",
               "-i", src, "-t", f"{end_seconds:.3f}", "-c", "copy",
               "-map_metadata", "0", tmp.name]
        proc = subprocess.run(cmd, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            try: os.unlink(tmp.name)
            except Exception: pass
            return None, proc.stderr.decode("utf-8", errors="ignore")
        return tmp.name, None

    def transcode(self, src, dst, *, filters=None, codec=None, bitrate=None,
                  quality=None, extra_args=None):
        """Run a single ffmpeg invocation src -> dst with optional filter chain,
        codec override, bitrate and codec-specific extras (e.g. LAME -cutoff).
        Returns (ok: bool, err_text: Optional[str]).
        """
        cmd = [self.binary(), "-y", "-hide_banner", "-loglevel", "error", "-i", src]
        if filters:
            cmd += ["-af", filters]
        cmd += ["-c:a", codec or self.codec_for(dst)]
        if bitrate:
            cmd += ["-b:a", bitrate]
        if quality is not None:
            cmd += ["-q:a", str(quality)]
        if extra_args:
            cmd += list(extra_args)
        cmd += ["-map_metadata", "0", "-id3v2_version", "3", dst]
        proc = subprocess.run(cmd, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            try: os.unlink(dst)
            except Exception: pass
            return False, proc.stderr.decode("utf-8", errors="ignore")
        return True, None


class VolumeMeter:
    """Wraps ffmpeg volumedetect output parsing."""

    def __init__(self, ffmpeg: FfmpegRunner):
        self._ffmpeg = ffmpeg

    def measure(self, path):
        """Returns (mean_db, peak_db). Either may be None on parse fail."""
        proc = subprocess.run(
            [self._ffmpeg.binary(), "-hide_banner", "-nostats", "-i", path,
             "-af", "volumedetect", "-f", "null", "-"],
            stderr=subprocess.PIPE, stdout=subprocess.PIPE,
        )
        text = proc.stderr.decode("utf-8", errors="ignore")
        return self._parse(text)

    @staticmethod
    def _parse(text):
        mean = peak = None
        for line in text.splitlines():
            if "mean_volume:" in line:
                try: mean = float(line.split("mean_volume:")[1].strip().split()[0])
                except Exception: pass
            elif "max_volume:" in line:
                try: peak = float(line.split("max_volume:")[1].strip().split()[0])
                except Exception: pass
        return mean, peak


class GainApplier:
    """Replaces a file in place with a volume-shifted re-encode."""

    def __init__(self, ffmpeg: FfmpegRunner):
        self._ffmpeg = ffmpeg

    def apply(self, path, gain_db):
        out, _err = self._ffmpeg.encode(path, f"volume={gain_db}dB")
        if out is None:
            return False
        shutil.move(out, path)
        return True
