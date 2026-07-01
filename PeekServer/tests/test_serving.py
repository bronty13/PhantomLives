"""Serving-path tests (0.6.0): Range parsing, ETag validators, DB-mtime cache freshness, and
the stale-artifact sweep. Run: python3 -m unittest discover -s tests"""
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peekserver import media  # noqa: E402
from peekserver.server import file_etag, parse_range  # noqa: E402


class TestParseRange(unittest.TestCase):
    """parse_range → (start, end) | None (serve full) | 'unsatisfiable' (416). Size 1000."""

    def test_normal_bounded(self):
        self.assertEqual(parse_range("bytes=0-499", 1000), (0, 499))
        self.assertEqual(parse_range("bytes=500-999", 1000), (500, 999))

    def test_end_clamped_to_size(self):
        self.assertEqual(parse_range("bytes=0-999999", 1000), (0, 999))

    def test_open_ended(self):
        self.assertEqual(parse_range("bytes=200-", 1000), (200, 999))

    def test_suffix_is_last_n_bytes(self):
        # The 0.5.x parser served bytes=-500 as the FIRST 501 bytes — this is the moov-seek fix.
        self.assertEqual(parse_range("bytes=-500", 1000), (500, 999))

    def test_suffix_larger_than_file(self):
        self.assertEqual(parse_range("bytes=-5000", 1000), (0, 999))

    def test_suffix_zero_or_negative_ignored(self):
        self.assertIsNone(parse_range("bytes=-0", 1000))
        self.assertIsNone(parse_range("bytes=--5", 1000))

    def test_start_beyond_size_is_416(self):
        self.assertEqual(parse_range("bytes=1000-", 1000), "unsatisfiable")
        self.assertEqual(parse_range("bytes=5000-6000", 1000), "unsatisfiable")

    def test_inverted_range_ignored(self):
        self.assertIsNone(parse_range("bytes=500-100", 1000))

    def test_malformed_ignored(self):
        self.assertIsNone(parse_range("bytes=abc-def", 1000))
        self.assertIsNone(parse_range("bytes=", 1000))
        self.assertIsNone(parse_range("bytes=5", 1000))       # no dash
        self.assertIsNone(parse_range("items=0-10", 1000))    # wrong unit

    def test_multirange_ignored(self):
        self.assertIsNone(parse_range("bytes=0-1,100-200", 1000))

    def test_absent_or_empty_file(self):
        self.assertIsNone(parse_range(None, 1000))
        self.assertIsNone(parse_range("", 1000))
        self.assertIsNone(parse_range("bytes=0-10", 0))       # zero-byte file → plain 200

    def test_single_byte_ranges(self):
        self.assertEqual(parse_range("bytes=0-0", 1000), (0, 0))
        self.assertEqual(parse_range("bytes=999-999", 1000), (999, 999))


class TestFileEtag(unittest.TestCase):
    def test_shape_and_stability(self):
        self.assertEqual(file_etag("orig", 1234, 99.7), '"orig-1234-99"')
        self.assertEqual(file_etag("orig", 1234, 99.7), file_etag("orig", 1234, 99.2))

    def test_variant_distinguishes_proxy_from_original(self):
        # Same URL can serve original then proxy (/preview) — validators must differ.
        self.assertNotEqual(file_etag("orig", 1234, 99), file_etag("proxy", 1234, 99))

    def test_changed_file_changes_etag(self):
        self.assertNotEqual(file_etag("orig", 1234, 99), file_etag("orig", 1235, 99))
        self.assertNotEqual(file_etag("orig", 1234, 99), file_etag("orig", 1234, 100))


class TestCacheFreshness(unittest.TestCase):
    """cache_is_fresh decides from the DB-recorded mtime — never stats the source."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.dst = os.path.join(self.tmp, "cached.jpg")
        with open(self.dst, "wb") as f:
            f.write(b"x")

    def test_iso_to_epoch(self):
        self.assertEqual(media.iso_to_epoch("1970-01-01T00:00:10Z"), 10)
        self.assertIsNone(media.iso_to_epoch(None))
        self.assertIsNone(media.iso_to_epoch("not-a-date"))

    def test_missing_cache_file_is_stale(self):
        self.assertFalse(media.cache_is_fresh(os.path.join(self.tmp, "nope.jpg"), "2026-01-01T00:00:00Z"))

    def test_cache_newer_than_source_is_fresh(self):
        self.assertTrue(media.cache_is_fresh(self.dst, "2020-01-01T00:00:00Z"))

    def test_cache_older_than_source_is_stale(self):
        future = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 86400))
        self.assertFalse(media.cache_is_fresh(self.dst, future))

    def test_unknown_source_mtime_trusts_cache(self):
        self.assertTrue(media.cache_is_fresh(self.dst, None))
        self.assertTrue(media.cache_is_fresh(self.dst, "garbage"))


class TestDisplayTier(unittest.TestCase):
    """/display: the screen-size JPEG tier between /thumb and /full (0.7.0)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.src = os.path.join(self.tmp, "img.png")
        _make_png(self.src)
        self.dst = os.path.join(self.tmp, "display", "ab", "abcd.jpg")

    def test_display_path_sharded_jpg(self):
        self.assertEqual(media.display_path("/cache", "abcd1234ef567890"),
                         "/cache/ab/abcd1234ef567890.jpg")

    def test_generates_display_jpeg_for_image(self):
        self.assertTrue(media.ensure_display(self.src, self.dst, "image", 256))
        self.assertGreater(os.path.getsize(self.dst), 0)

    def test_non_image_refused(self):
        # video preview is /preview's job; audio has no visual — clients fall through to /full
        self.assertFalse(media.ensure_display(self.src, self.dst, "video", 256))
        self.assertFalse(media.ensure_display(self.src, self.dst, "audio", 256))

    def test_missing_source(self):
        self.assertFalse(media.ensure_display(os.path.join(self.tmp, "nope.png"), self.dst, "image", 256))


def _make_png(path, w=64, h=64):
    import struct
    import zlib
    raw = bytearray()
    for _ in range(h):
        raw.append(0)
        raw += bytes((180, 90, 140)) * w
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw)))
                + chunk(b"IEND", b""))


class TestSweepStaleArtifacts(unittest.TestCase):
    """Startup sweep of orphaned *.tmp.mp4 / *.src.* transcode leftovers."""

    def setUp(self):
        self.cache = tempfile.mkdtemp()
        self.shard = os.path.join(self.cache, "ab")
        os.makedirs(self.shard)

    def _make(self, name, age_seconds=7200):
        fp = os.path.join(self.shard, name)
        with open(fp, "wb") as f:
            f.write(b"x")
        old = time.time() - age_seconds
        os.utime(fp, (old, old))
        return fp

    def test_removes_old_orphans_keeps_real_proxies(self):
        tmp = self._make("abcd1234.mp4.tmp.mp4")
        stage = self._make("abcd1234.mp4.src.mov")
        proxy = self._make("abcd1234.mp4")           # a real proxy — must survive
        removed = media.sweep_stale_artifacts(self.cache)
        self.assertEqual(removed, 2)
        self.assertFalse(os.path.exists(tmp))
        self.assertFalse(os.path.exists(stage))
        self.assertTrue(os.path.exists(proxy))

    def test_age_guard_spares_live_staging(self):
        fresh = self._make("live1234.mp4.src.mov", age_seconds=60)   # a running --warm's staging
        self.assertEqual(media.sweep_stale_artifacts(self.cache), 0)
        self.assertTrue(os.path.exists(fresh))

    def test_missing_cache_dir_is_noop(self):
        self.assertEqual(media.sweep_stale_artifacts(os.path.join(self.cache, "nope")), 0)


if __name__ == "__main__":
    unittest.main()
