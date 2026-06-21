#!/usr/bin/env python3
"""Unit tests for sync_playlist.py's pure matching helpers (no network)."""

import unittest
import sync_playlist as sp


class NormTitle(unittest.TestCase):
    def test_strips_dash_suffix(self):
        self.assertEqual(sp.norm_title("Hotel California - 2013 Remaster"), "hotel california")
        self.assertEqual(sp.norm_title("Ob-La-Di, Ob-La-Da - Remastered 2009"), "ob la di ob la da")

    def test_strips_parens_and_feat(self):
        self.assertEqual(sp.norm_title("American Pie (Full Length Version)"), "american pie")
        self.assertEqual(sp.norm_title("Stay (feat. Someone)"), "stay")
        self.assertEqual(sp.norm_title("Song ft. X"), "song")

    def test_punctuation_and_case(self):
        self.assertEqual(sp.norm_title("Jack & Diane"), "jack diane")

    def test_feat_prefix_word_not_eaten(self):
        # Regression: "Feather"/"Feature" must NOT be truncated by the feat stripper.
        self.assertEqual(sp.norm_title("Feather"), "feather")
        self.assertEqual(sp.norm_title("Feature Presentation"), "feature presentation")
        # but a real "feat." marker IS stripped:
        self.assertEqual(sp.norm_title("Stay feat. Rihanna"), "stay")


class CensoredMatch(unittest.TestCase):
    def test_asterisk_wildcard_matches(self):
        self.assertEqual(sp.match_score("Lily Allen", "Fuck You", "Lily Allen", "F**k You"), 22)

    def test_non_censored_unaffected(self):
        self.assertEqual(sp.match_score("Lily Allen", "Fuck You", "Other", "F**k You"), 0)  # wrong artist


class NormArtist(unittest.TestCase):
    def test_primary_only_and_the(self):
        self.assertEqual(sp.norm_artist("The Beatles"), "beatles")
        self.assertEqual(sp.norm_artist("Renee Olstead, Chris Botti"), "renee olstead")
        self.assertEqual(sp.norm_artist("Hall & Oates"), "hall")


class MatchScore(unittest.TestCase):
    def test_exact_both(self):
        self.assertEqual(sp.match_score("The Eagles", "Hotel California - Live", "Eagles", "Hotel California"), 22)

    def test_parens_strip_makes_exact(self):
        # "(Full Length Version)" is stripped → exact normalized title → 22.
        self.assertEqual(sp.match_score("Don McLean", "American Pie", "Don McLean", "American Pie (Full Length Version)"), 22)

    def test_title_containment(self):
        # Genuine containment (no parens to strip): source ⊂ candidate → 21.
        self.assertEqual(sp.match_score("Eagles", "Hotel California", "Eagles", "Hotel California Reprise"), 21)

    def test_wrong_song_is_zero(self):
        self.assertEqual(sp.match_score("Eagles", "Hotel California", "Eagles", "Take It Easy"), 0)

    def test_wrong_artist_is_zero(self):
        self.assertEqual(sp.match_score("Eagles", "Hotel California", "Gipsy Kings", "Hotel California"), 0)


class PickBest(unittest.TestCase):
    def test_prefers_clean_over_demo(self):
        cands = [
            {"id": "demo", "artistName": "John Mellencamp", "name": "Jack & Diane (Writing Demo)"},
            {"id": "std", "artistName": "John Mellencamp", "name": "Jack & Diane"},
        ]
        best, score = sp.pick_best("John Mellencamp", "Jack & Diane", cands)
        self.assertEqual(best["id"], "std")
        self.assertEqual(score, 22)

    def test_prefers_clean_over_live(self):
        cands = [
            {"id": "live", "artistName": "Yazoo", "name": "Mr Blue (Live)"},
            {"id": "std", "artistName": "Yazoo", "name": "Mr Blue"},
        ]
        best, _ = sp.pick_best("Yazoo", "Mr Blue", cands)
        self.assertEqual(best["id"], "std")

    def test_no_match_returns_none(self):
        best, score = sp.pick_best("Eagles", "Hotel California",
                                   [{"id": "x", "artistName": "Eagles", "name": "Take It Easy"}])
        self.assertIsNone(best)
        self.assertEqual(score, 0)

    def test_variant_accepted_when_only_option(self):
        cands = [{"id": "live", "artistName": "Yazoo", "name": "Mr Blue (Live)"}]
        best, _ = sp.pick_best("Yazoo", "Mr Blue", cands)
        self.assertEqual(best["id"], "live")


if __name__ == "__main__":
    unittest.main(verbosity=2)
