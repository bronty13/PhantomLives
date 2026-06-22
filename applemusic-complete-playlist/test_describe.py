#!/usr/bin/env python3
"""Unit tests for describe.py — each naming category maps to the right blurb."""
import unittest
import describe as d


class Describe(unittest.TestCase):
    def test_decade_master(self):
        s = d.describe("80s — Complete [PL]", 2470)
        self.assertIn("Every 80s hit", s)
        self.assertIn("2,470", s)
        self.assertIn("separate", s.lower())          # notes country is separate

    def test_decade_year(self):
        s = d.describe("80s — 1985 [PL]", 215)
        self.assertIn("1985", s)
        self.assertIn("215", s)

    def test_country_master_vs_year(self):
        self.assertIn("country", d.describe("90s Country — Complete [PL]", 968).lower())
        self.assertIn("1994", d.describe("90s Country — 1994 [PL]", 99))

    def test_ac(self):
        self.assertIn("Adult Contemporary", d.describe("80s Adult Contemporary — Complete [PL]", 195))

    def test_decade_metal_and_rock(self):
        self.assertIn("metal", d.describe("2010s — Metal [PL]", 422).lower())
        self.assertIn("rock", d.describe("70s — Rock [PL]", 100).lower())

    def test_metal_master_and_subgenre(self):
        self.assertIn("thrash", d.describe("Metal — Complete [PL]", 2071).lower())
        self.assertIn("thrash metal", d.describe("Thrash Metal [PL]", 446).lower())
        self.assertIn("metalcore", d.describe("Metalcore [PL]", 100).lower())

    def test_classical_renditions(self):
        s = d.describe("Taylor Swift — Classical Renditions [PL]", 405)
        self.assertIn("Taylor Swift", s)
        self.assertIn("renditions", s.lower())

    def test_standalone(self):
        self.assertIn("diary", d.describe("Life in Music [PL]", 416).lower())
        self.assertIn("Brent Mason", d.describe("Brent Mason — Played On [PL]", 603))

    def test_artist_complete_fallback(self):
        s = d.describe("Metallica Complete [PL]", 1456)
        self.assertIn("Every available Metallica", s)
        self.assertIn("Flavor A", s)

    def test_decade_master_not_caught_by_artist_fallback(self):
        # "{D} — Complete [PL]" also ends in "Complete [PL]"; must hit the decade branch
        self.assertNotIn("Flavor A", d.describe("2000s — Complete [PL]", 2538))


if __name__ == "__main__":
    unittest.main(verbosity=2)
