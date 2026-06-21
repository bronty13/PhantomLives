#!/usr/bin/env python3
"""Unit tests for build_decade.py's pure helpers (no network)."""

import unittest
import build_decade as bd


class Norm(unittest.TestCase):
    def test_strips_punct_and_case(self):
        self.assertEqual(bd._norm("Hip-Hop/R&B Hits: 1985"), "hip hop r b hits 1985")
        # curly apostrophe in Apple's "'80s Metal Essentials" normalizes to match.
        self.assertEqual(bd._norm("’80s Metal Essentials"), "80s metal essentials")
        self.assertEqual(bd._norm("80s Metal Essentials"), "80s metal essentials")


class Dedupe(unittest.TestCase):
    def test_preserves_order_first_wins(self):
        self.assertEqual(bd.dedupe(["a", "b", "a", "c", "b"]), ["a", "b", "c"])

    def test_empty(self):
        self.assertEqual(bd.dedupe([]), [])


class DecadeSpec(unittest.TestCase):
    def test_80s_config_sane(self):
        spec = bd.DECADES["80s"]
        self.assertEqual(spec["years"], list(range(1980, 1990)))
        self.assertIn("Metal", spec["essentials"])
        self.assertTrue(all("{y}" in t for t in spec["genre_templates"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
