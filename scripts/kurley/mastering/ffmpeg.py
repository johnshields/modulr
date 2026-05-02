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
        """Encode src through filter_chain to a temp file. Returns (out_path, err_text)."""
        ext = os.path.splitext(src)[1].lower()
        tmp = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
        tmp.close()
        cmd = [self.binary(), "-y", "-hide_banner", "-loglevel", "error",
               "-i", src, "-af", filter_chain,
               "-c:a", self.codec_for(src), "-q:a", "0",
               "-map_metadata", "0", "-id3v2_version", "3",
               tmp.name]
        proc = subprocess.run(cmd, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            try: os.unlink(tmp.name)
            except Exception: pass
            return None, proc.stderr.decode("utf-8", errors="ignore")
        return tmp.name, None


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
