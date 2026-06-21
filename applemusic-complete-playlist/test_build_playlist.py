#!/usr/bin/env python3
"""
Unit tests for build_playlist.py's pure helpers (no requests/PyJWT/network).

build_playlist keeps all filtering/dedupe/planning logic free of third-party
imports, so this suite imports the module directly and exercises the decision
logic with plain dicts that mimic Apple Music resource objects.

Run: python3 test_build_playlist.py
"""

import unittest

import build_playlist as bp

ART = "111111"   # our artist's catalog id
OTHER = "999999"


def song(sid, name="X", artist_ids=None, type_="songs", catalog_id=None):
    s = {"id": sid, "type": type_, "attributes": {"name": name}}
    if artist_ids is not None:
        s["relationships"] = {"artists": {"data": [{"id": a, "type": "artists"} for a in artist_ids]}}
    if catalog_id is not None:
        s["attributes"]["playParams"] = {"catalogId": catalog_id}
    return s


class KeepSong(unittest.TestCase):
    def test_own_release_keeps_everything(self):
        self.assertTrue(bp.keep_song(song("a"), ART, is_appears_on=False))
        self.assertTrue(bp.keep_song(song("a", artist_ids=[OTHER]), ART, is_appears_on=False))

    def test_appears_on_keeps_only_credited(self):
        self.assertTrue(bp.keep_song(song("a", artist_ids=[OTHER, ART]), ART, is_appears_on=True))
        self.assertFalse(bp.keep_song(song("a", artist_ids=[OTHER]), ART, is_appears_on=True))

    def test_appears_on_without_artists_rel_drops(self):
        # No artists relationship included -> can't confirm credit -> drop.
        self.assertFalse(bp.keep_song(song("a"), ART, is_appears_on=True))

    def test_idless_dropped(self):
        self.assertFalse(bp.keep_song({"attributes": {}}, ART, is_appears_on=False))


class CreditHelpers(unittest.TestCase):
    def test_song_artist_ids(self):
        self.assertEqual(bp.song_artist_ids(song("a", artist_ids=[ART, OTHER])), [ART, OTHER])
        self.assertEqual(bp.song_artist_ids(song("a")), [])

    def test_credits_artist(self):
        self.assertTrue(bp.song_credits_artist(song("a", artist_ids=[ART]), ART))
        self.assertFalse(bp.song_credits_artist(song("a", artist_ids=[OTHER]), ART))


class PlayCatalogId(unittest.TestCase):
    def test_catalog_song_uses_own_id(self):
        self.assertEqual(bp.song_play_catalog_id(song("cat123")), "cat123")

    def test_library_song_uses_playparams_catalog_id(self):
        s = song("i.libraryid", type_="library-songs", catalog_id="cat999")
        self.assertEqual(bp.song_play_catalog_id(s), "cat999")

    def test_none_when_unknown(self):
        self.assertIsNone(bp.song_play_catalog_id({"type": "library-songs", "id": "i.x", "attributes": {}}))


class DedupeById(unittest.TestCase):
    def test_first_wins_stable(self):
        out = bp.dedupe_by_id([song("a"), song("b"), song("a")])
        self.assertEqual([s["id"] for s in out], ["a", "b"])


class PlanAdditions(unittest.TestCase):
    def test_only_missing_in_order(self):
        self.assertEqual(bp.plan_additions(["a", "b", "c"], ["b"]), ["a", "c"])

    def test_dedupes_desired(self):
        self.assertEqual(bp.plan_additions(["a", "a", "b"], []), ["a", "b"])

    def test_empty_when_all_present(self):
        self.assertEqual(bp.plan_additions(["a", "b"], ["a", "b"]), [])


class Chunked(unittest.TestCase):
    def test_sizes(self):
        self.assertEqual(list(bp.chunked([1, 2, 3, 4, 5], 2)), [[1, 2], [3, 4], [5]])

    def test_empty(self):
        self.assertEqual(list(bp.chunked([], 100)), [])


class LibraryStatus(unittest.TestCase):
    def test_ok_below_warn(self):
        st = bp.library_status(17801)
        self.assertEqual(st["level"], "OK")
        self.assertEqual(st["headroom"], 100000 - 17801)

    def test_warn_at_85pct(self):
        self.assertEqual(bp.library_status(85000)["level"], "WARN")
        self.assertEqual(bp.library_status(84999)["level"], "OK")

    def test_critical_at_95pct(self):
        self.assertEqual(bp.library_status(95000)["level"], "CRITICAL")

    def test_headroom_never_negative(self):
        self.assertEqual(bp.library_status(120000)["headroom"], 0)


class CacheKey(unittest.TestCase):
    def test_includes_storefront_and_artist(self):
        self.assertEqual(bp.catalog_cache_key("123", "us"), "us__123.json")
        self.assertNotEqual(bp.catalog_cache_key("123", "us"), bp.catalog_cache_key("123", "gb"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
