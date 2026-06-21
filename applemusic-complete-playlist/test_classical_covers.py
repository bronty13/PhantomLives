#!/usr/bin/env python3
"""Tests for classical_covers.py's album_qualifies filter (pure)."""
import unittest
import classical_covers as cc

class AlbumQualifies(unittest.TestCase):
    def q(self, artist, name): return cc.album_qualifies("Taylor Swift", artist, name)
    def test_string_quartet_yes(self):
        self.assertTrue(self.q("Vitamin String Quartet", "VSQ Performs Taylor Swift"))
        self.assertTrue(self.q("Piano Tribute Players", "Taylor Swift Piano Tribute"))
    def test_her_own_release_no(self):
        self.assertFalse(self.q("Taylor Swift", "1989 (Taylor's Version)"))
    def test_not_referencing_artist_no(self):
        self.assertFalse(self.q("Vitamin String Quartet", "VSQ Performs Coldplay"))
    def test_jazz_lofi_guitar_karaoke_excluded(self):
        self.assertFalse(self.q("Smooth Jazz All Stars", "Smooth Jazz Renditions of Taylor Swift"))
        self.assertFalse(self.q("Lo-Fi Dreamers", "Lofi Renditions of Taylor Swift"))
        self.assertFalse(self.q("Guitar Tribute Players", "Acoustic Tribute to Taylor Swift"))
        self.assertFalse(self.q("Vox Freaks", "Taylor Swift (Originally Performed) Instrumental"))
    def test_non_classical_pop_cover_no_signal(self):
        self.assertFalse(self.q("Some Band", "A Tribute to Taylor Swift"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
