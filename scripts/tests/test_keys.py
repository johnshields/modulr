"""Pure-function tests for kurley.theory.keys.normalise_musical + musical_to_pc_mode.
Run from project root:  python3 -m unittest scripts.tests.test_keys
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), os.pardir))

from kurley.theory.keys import musical_to_pc_mode, normalise_musical


class NormaliseMusicalTests(unittest.TestCase):
    def test_camelot_to_musical(self):
        self.assertEqual(normalise_musical("8A"), "Am")
        self.assertEqual(normalise_musical("8B"), "C")
        self.assertEqual(normalise_musical("11A"), "F#m")
        self.assertEqual(normalise_musical("10b"), "D")

    def test_lowercase_min_suffix(self):
        self.assertEqual(normalise_musical("emin"), "Em")
        self.assertEqual(normalise_musical("a min"), "Am")
        self.assertEqual(normalise_musical("c#min"), "C#m")

    def test_word_minor(self):
        self.assertEqual(normalise_musical("C# minor"), "C#m")
        self.assertEqual(normalise_musical("Bb minor"), "Bbm")
        self.assertEqual(normalise_musical("a moll"), "Am")

    def test_already_canonical(self):
        for label in ("C", "F#", "Bbm", "Em", "Db"):
            self.assertEqual(normalise_musical(label), label)

    def test_major_suffix_dropped(self):
        self.assertEqual(normalise_musical("Cmaj"), "C")
        self.assertEqual(normalise_musical("Ebmaj"), "Eb")

    def test_empty_or_none(self):
        self.assertIsNone(normalise_musical(""))
        self.assertIsNone(normalise_musical(None))

    def test_garbage_returns_input(self):
        self.assertEqual(normalise_musical("xyz"), "xyz")


class MusicalToPcModeTests(unittest.TestCase):
    def test_known_keys(self):
        self.assertEqual(musical_to_pc_mode("C"), (0, 1))
        self.assertEqual(musical_to_pc_mode("Cm"), (0, 0))
        self.assertEqual(musical_to_pc_mode("F#m"), (6, 0))
        self.assertEqual(musical_to_pc_mode("Bb"), (10, 1))

    def test_unmapped_raises(self):
        with self.assertRaises(ValueError):
            musical_to_pc_mode("Xyz")


if __name__ == "__main__":
    unittest.main()
