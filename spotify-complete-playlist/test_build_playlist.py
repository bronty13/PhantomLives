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


def track(uri, artists, is_local=False):
    return {"uri": uri, "is_local": is_local, "artists": [{"id": a} for a in artists]}


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


class PlanAdditions(unittest.TestCase):
    def test_only_missing_in_desired_order(self):
        desired = ["a", "b", "c", "d"]
        existing = ["b", "d"]
        self.assertEqual(bp.plan_additions(desired, existing), ["a", "c"])

    def test_dedupes_desired_against_itself(self):
        self.assertEqual(bp.plan_additions(["a", "a", "b"], []), ["a", "b"])

    def test_empty_when_all_present(self):
        self.assertEqual(bp.plan_additions(["a", "b"], ["a", "b"]), [])


class Chunked(unittest.TestCase):
    def test_chunks_respect_size(self):
        self.assertEqual(list(bp.chunked(list(range(5)), 2)), [[0, 1], [2, 3], [4]])

    def test_empty(self):
        self.assertEqual(list(bp.chunked([], 100)), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
