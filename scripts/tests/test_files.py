"""Pure-function tests for kurley.metadata.files (slug, preserve_nnn_prefix).
Run from project root:  python3 -m unittest scripts.tests.test_files
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), os.pardir))

from kurley.metadata.files import preserve_nnn_prefix, slug


class SlugTests(unittest.TestCase):
    def test_basic_lowercase_hyphen(self):
        self.assertEqual(slug("Some Track Title"), "some-track-title")

    def test_strip_punct(self):
        self.assertEqual(slug("Don't Stop! (Remix)"), "don-t-stop-remix")

    def test_strip_trailing_key_bpm(self):
        self.assertEqual(slug("song-title-bmin-139"), "song-title")
        self.assertEqual(slug("song-a-136"), "song")

    def test_strip_leading_nnn(self):
        self.assertEqual(slug("001-song-title"), "song-title")
        self.assertEqual(slug("042-some-song"), "some-song")

    def test_collapse_repeats(self):
        self.assertEqual(slug("a__b___c"), "a-b-c")

    def test_strip_stacked_key_bpm(self):
        self.assertEqual(slug("song-bmin-139-fmin-136"), "song")


class PreserveNnnPrefixTests(unittest.TestCase):
    def test_adds_when_missing(self):
        self.assertEqual(
            preserve_nnn_prefix("001_track.mp3", "track_Am_128.mp3"),
            "001_track_Am_128.mp3",
        )

    def test_noop_if_already_prefixed(self):
        self.assertEqual(
            preserve_nnn_prefix("001_track.mp3", "001_track_Am_128.mp3"),
            "001_track_Am_128.mp3",
        )

    def test_noop_if_orig_has_no_prefix(self):
        self.assertEqual(
            preserve_nnn_prefix("track.mp3", "track_Am_128.mp3"),
            "track_Am_128.mp3",
        )

    def test_handles_four_digit_prefix(self):
        self.assertEqual(
            preserve_nnn_prefix("0042_track.mp3", "track.mp3"),
            "0042_track.mp3",
        )


if __name__ == "__main__":
    unittest.main()
