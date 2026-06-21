#!/usr/bin/env python3
"""
Unit tests for build_playlist.py's pure data-shaping helpers.

These deliberately avoid spotipy / network / OAuth: build_playlist keeps all
filtering, deduping and planning logic free of third-party imports, so this
suite imports the module directly and exercises the decision logic with plain
dicts that mimic Spotify track objects.

Run: python3 test_build_playlist.py
"""

import unittest

import build_playlist as bp

TSWIFT = "06HL4z0CvFAxyc27GXpf02"  # Taylor Swift's real artist id (label only)
OTHER = "4F84IBURUo98rz4r61KF70"   # some other artist id


def track(uri, artists, is_local=False, name=None):
    return {
        "uri": uri,
        "is_local": is_local,
        "name": name,
        "artists": [{"id": a} for a in artists],
    }


class CreditHelpers(unittest.TestCase):
    def test_by_artist_true_when_credited_anywhere(self):
        self.assertTrue(bp.track_is_by_artist(track("u", [OTHER, TSWIFT]), TSWIFT))

    def test_by_artist_false_when_absent(self):
        self.assertFalse(bp.track_is_by_artist(track("u", [OTHER]), TSWIFT))

    def test_primary_artist_checks_first_slot_only(self):
        self.assertTrue(bp.track_is_primary_artist(track("u", [TSWIFT, OTHER]), TSWIFT))
        self.assertFalse(bp.track_is_primary_artist(track("u", [OTHER, TSWIFT]), TSWIFT))


class KeepTrack(unittest.TestCase):
    def test_own_album_keeps_everything(self):
        # Even a track where she's somehow not first is kept on her own release.
        self.assertTrue(bp.keep_track(track("u", [TSWIFT]), TSWIFT, "album"))
        self.assertTrue(bp.keep_track(track("u", [OTHER, TSWIFT]), TSWIFT, "single"))

    def test_appears_on_keeps_only_genuine_features(self):
        # Guest feature (she's credited, not primary) -> keep.
        self.assertTrue(
            bp.keep_track(track("u", [OTHER, TSWIFT]), TSWIFT, "appears_on")
        )
        # Her own song surfacing on a 3rd-party comp (she's primary) -> drop,
        # so we don't double-count her catalog from compilations.
        self.assertFalse(
            bp.keep_track(track("u", [TSWIFT, OTHER]), TSWIFT, "appears_on")
        )
        # Not credited at all -> drop.
        self.assertFalse(bp.keep_track(track("u", [OTHER]), TSWIFT, "appears_on"))

    def test_local_and_uriless_tracks_dropped(self):
        self.assertFalse(bp.keep_track(track("u", [TSWIFT], is_local=True), TSWIFT, "album"))
        self.assertFalse(bp.keep_track(track("", [TSWIFT]), TSWIFT, "album"))


class DedupeByUri(unittest.TestCase):
    def test_collapses_exact_uri_dupes_stable_order(self):
        ts = [track("a", [TSWIFT]), track("b", [TSWIFT]), track("a", [TSWIFT])]
        out = bp.dedupe_by_uri(ts)
        self.assertEqual([t["uri"] for t in out], ["a", "b"])

    def test_keeps_rerecords_with_distinct_uris(self):
        # "Cruel Summer" vs "Cruel Summer (Taylor's Version)" => different URIs => both kept.
        ts = [track("orig", [TSWIFT]), track("tv", [TSWIFT])]
        self.assertEqual(len(bp.dedupe_by_uri(ts)), 2)


class DedupeByName(unittest.TestCase):
    def test_collapses_same_title_keeps_first(self):
        ts = [
            track("a", [TSWIFT], name="Love Story"),
            track("b", [TSWIFT], name="love story"),  # case-insensitive dupe
            track("c", [TSWIFT], name="Love Story"),
        ]
        out = bp.dedupe_by_name(ts)
        self.assertEqual([t["uri"] for t in out], ["a"])

    def test_preserves_version_variants(self):
        # Different titles -> kept, so re-records/vault/live survive name-dedupe.
        ts = [
            track("a", [TSWIFT], name="Love Story"),
            track("b", [TSWIFT], name="Love Story (Taylor's Version)"),
            track("c", [TSWIFT], name="Love Story - Live"),
        ]
        self.assertEqual(len(bp.dedupe_by_name(ts)), 3)

    def test_skips_untitled(self):
        self.assertEqual(bp.dedupe_by_name([track("a", [TSWIFT], name=None)]), [])


class PlanAdditions(unittest.TestCase):
    def test_only_missing_in_desired_order(self):
        desired = ["a", "b", "c", "d"]
        existing = ["b", "d"]
        self.assertEqual(bp.plan_additions(desired, existing), ["a", "c"])

    def test_dedupes_desired_against_itself(self):
        self.assertEqual(bp.plan_additions(["a", "a", "b"], []), ["a", "b"])

    def test_empty_when_all_present(self):
        self.assertEqual(bp.plan_additions(["a", "b"], ["a", "b"]), [])


def album(track_dicts, total=None):
    items = track_dicts
    return {"id": "alb1", "tracks": {"items": items, "total": total if total is not None else len(items)}}


class TracksFromAlbum(unittest.TestCase):
    def test_extracts_kept_tracks_from_embedded_tracks(self):
        alb = album([
            track("a", [TSWIFT], name="One"),
            track("b", [TSWIFT], name="Two"),
        ])
        out = bp.tracks_from_album(alb, TSWIFT, "album")
        self.assertEqual([t["uri"] for t in out], ["a", "b"])
        self.assertEqual(out[0]["name"], "One")

    def test_applies_keep_rules_for_appears_on(self):
        # On appears_on, only genuine features (credited, not primary) survive.
        alb = album([
            track("feat", [OTHER, TSWIFT], name="Guest"),     # keep
            track("hers", [TSWIFT, OTHER], name="HerOwn"),     # drop (primary)
            track("none", [OTHER], name="NotHers"),            # drop (absent)
        ])
        out = bp.tracks_from_album(alb, TSWIFT, "appears_on")
        self.assertEqual([t["uri"] for t in out], ["feat"])

    def test_empty_or_missing_tracks(self):
        self.assertEqual(bp.tracks_from_album({}, TSWIFT, "album"), [])
        self.assertEqual(bp.tracks_from_album({"tracks": {"items": None}}, TSWIFT, "album"), [])


class AlbumNeedsPagination(unittest.TestCase):
    def test_true_when_total_exceeds_embedded(self):
        alb = {"tracks": {"items": [1] * 50, "total": 73}}
        self.assertTrue(bp.album_needs_track_pagination(alb))

    def test_false_when_complete(self):
        alb = {"tracks": {"items": [1, 2, 3], "total": 3}}
        self.assertFalse(bp.album_needs_track_pagination(alb))

    def test_false_when_total_missing(self):
        self.assertFalse(bp.album_needs_track_pagination({"tracks": {"items": [1]}}))


class CatalogCacheKey(unittest.TestCase):
    def test_stable_and_includes_artist_groups_market(self):
        k = bp.catalog_cache_key("ABC", ("album", "single", "appears_on"), "US")
        self.assertEqual(k, "ABC__album-single-appears_on__US.json")

    def test_varies_by_market_and_groups(self):
        a = bp.catalog_cache_key("ABC", ("album",), "US")
        b = bp.catalog_cache_key("ABC", ("album",), "GB")
        c = bp.catalog_cache_key("ABC", ("album", "single"), "US")
        self.assertNotEqual(a, b)
        self.assertNotEqual(a, c)


class Chunked(unittest.TestCase):
    def test_chunks_respect_size(self):
        self.assertEqual(list(bp.chunked(list(range(5)), 2)), [[0, 1], [2, 3], [4]])

    def test_empty(self):
        self.assertEqual(list(bp.chunked([], 100)), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
