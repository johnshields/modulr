"""Metadata layer — ID3 tag IO + filename helpers."""
from .files import list_audio, list_mp3s, preserve_nnn_prefix, slug
from .tags import TagIO

__all__ = ["TagIO", "list_audio", "list_mp3s", "preserve_nnn_prefix", "slug"]
