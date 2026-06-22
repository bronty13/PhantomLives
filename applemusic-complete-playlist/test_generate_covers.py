#!/usr/bin/env python3
"""Unit tests for generate_covers.categorize() (deterministic, no rendering)."""
import unittest
import generate_covers as gc


class Categorize(unittest.TestCase):
    def test_decade_master(self):
        pal, motif, tag, title = gc.categorize("80s — Complete [PL]")
        self.assertEqual(motif, "80s")
        self.assertEqual(tag, "Decade")
        self.assertEqual(title, "80s — Complete")        # [PL] stripped

    def test_decade_country_vs_ac_vs_metal(self):
        self.assertEqual(gc.categorize("90s Country — 1994 [PL]")[2], "Country")
        self.assertEqual(gc.categorize("80s Adult Contemporary — Complete [PL]")[2], "Adult Contemporary")
        self.assertEqual(gc.categorize("2010s — Metal [PL]")[2], "Metal")
        self.assertEqual(gc.categorize("70s — Rock [PL]")[2], "Rock")

    def test_metal_master_and_subgenre(self):
        self.assertEqual(gc.categorize("Metal — Complete [PL]")[2], "Metal")
        self.assertEqual(gc.categorize("Thrash Metal [PL]")[2], "Metal")

    def test_artist_initials_and_determinism(self):
        a = gc.categorize("Metallica Complete [PL]")
        self.assertEqual(a[1], "M")           # initials motif
        self.assertEqual(a[2], "Artist")
        self.assertEqual(a, gc.categorize("Metallica Complete [PL]"))   # deterministic

    def test_classical_and_standalone(self):
        self.assertEqual(gc.categorize("Taylor Swift — Classical Renditions [PL]")[2], "Classical")
        self.assertEqual(gc.categorize("Life in Music [PL]")[2], "Collection")

    def test_safe_filename(self):
        self.assertEqual(gc.safe("80s — Complete [PL]"), "80s_Complete_PL.png")


if __name__ == "__main__":
    unittest.main(verbosity=2)
