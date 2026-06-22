#!/usr/bin/env python3
"""Unit tests for generate_covers pure helpers (no network/rendering)."""
import unittest
import generate_covers as gc


class IsArtistComplete(unittest.TestCase):
    def test_artist_completes(self):
        self.assertEqual(gc.is_artist_complete("Metallica Complete [PL]"), "Metallica")
        self.assertEqual(gc.is_artist_complete("The Beatles Complete [PL]"), "The Beatles")

    def test_classical_uses_base_artist(self):
        self.assertEqual(gc.is_artist_complete("Taylor Swift — Classical Renditions [PL]"), "Taylor Swift")

    def test_non_artist_playlists_are_none(self):
        for nm in ["80s — Complete [PL]", "80s Country — Complete [PL]", "Metal — Complete [PL]",
                   "Thrash Metal [PL]", "Life in Music [PL]", "Brent Mason — Played On [PL]",
                   "90s — 1994 [PL]"]:
            self.assertIsNone(gc.is_artist_complete(nm), nm)


class Helpers(unittest.TestCase):
    def test_art_url_substitutes_size(self):
        self.assertEqual(gc.art_url("https://x/{w}x{h}bb.jpg", 600), "https://x/600x600bb.jpg")
        self.assertEqual(gc.art_url("", 600), "")

    def test_safe_is_jpg(self):
        self.assertEqual(gc.safe("80s — Complete [PL]"), "80s_Complete_PL.jpg")
        self.assertEqual(gc.safe("Guns N' Roses Complete [PL]"), "Guns_N_Roses_Complete_PL.jpg")


if __name__ == "__main__":
    unittest.main(verbosity=2)
