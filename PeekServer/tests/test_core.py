"""PeekServer core tests — stdlib unittest (no deps). Run: python3 -m unittest discover -s tests"""
import os
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peekserver import db, media, scan  # noqa: E402


def make_png(path, rgb=(180, 90, 140), w=64, h=64):
    raw = bytearray()
    for _ in range(h):
        raw.append(0)
        raw += bytes(rgb) * w
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw)))
                + chunk(b"IEND", b""))


class CoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mediadir = os.path.join(self.tmp, "media")
        os.makedirs(self.mediadir)
        for i in range(3):
            make_png(os.path.join(self.mediadir, f"p{i}.png"))
        db.init(os.path.join(self.tmp, "db.sqlite"))
        self.root = {"path": self.mediadir, "label": "T", "kind": "photos"}

    # classification
    def test_classify(self):
        self.assertEqual(media.classify("/x/a.HEIC"), "image")
        self.assertEqual(media.classify("/x/a.mov"), "video")
        self.assertEqual(media.classify("/x/a.m4a"), "audio")
        self.assertEqual(media.classify("/x/a.txt"), "other")

    def test_file_id_stable(self):
        self.assertEqual(db.file_id("/a/b.jpg"), db.file_id("/a/b.jpg"))
        self.assertNotEqual(db.file_id("/a/b.jpg"), db.file_id("/a/c.jpg"))

    # scanning
    def test_scan_finds_media_ignores_noise(self):
        open(os.path.join(self.mediadir, ".DS_Store"), "w").close()
        open(os.path.join(self.mediadir, "notes.txt"), "w").close()
        n = scan.scan_root(self.root)
        self.assertEqual(n, 3)  # 3 pngs, dotfile + txt ignored
        total, _ = db.list_media(root=self.mediadir)
        self.assertEqual(total, 3)

    # decisions + retrieval
    def test_decision_with_keywords_albums(self):
        scan.scan_root(self.root)
        _, items = db.list_media(root=self.mediadir)
        mid = items[0]["id"]
        rec = db.update_decision(mid, {"keep": 1, "is_favorite": 1, "title": "t",
                                       "caption": "c", "keywords": ["a", "b"], "albums": ["X"]})
        self.assertEqual(rec["keep"], 1)
        self.assertEqual(rec["is_favorite"], 1)
        self.assertEqual(sorted(rec["keywords"]), ["a", "b"])
        self.assertEqual(rec["albums"], ["X"])

    def test_rescan_preserves_decisions(self):
        scan.scan_root(self.root)
        mid = db.list_media(root=self.mediadir)[1][0]["id"]
        db.update_decision(mid, {"keep": 1})
        scan.scan_root(self.root)  # rescan
        self.assertEqual(db.get_media(mid)["keep"], 1)

    def test_filters_and_counts(self):
        scan.scan_root(self.root)
        items = db.list_media(root=self.mediadir)[1]
        db.update_decision(items[0]["id"], {"keep": 1})
        db.update_decision(items[1]["id"], {"keep": 0})
        self.assertEqual(db.list_media(root=self.mediadir, decision="undecided")[0], 1)
        self.assertEqual(db.list_media(root=self.mediadir, decision="kept")[0], 1)
        self.assertEqual(db.list_media(root=self.mediadir, decision="skipped")[0], 1)
        roots = db.roots_with_counts()
        self.assertEqual(roots[0]["kept"], 1)
        self.assertEqual(roots[0]["skipped"], 1)

    def test_missing_file_marked_not_deleted(self):
        scan.scan_root(self.root)
        items = db.list_media(root=self.mediadir)[1]
        mid = items[0]["id"]
        db.update_decision(mid, {"keep": 1})
        os.remove(items[0]["file_path"])
        scan.scan_root(self.root)
        rec = db.get_media(mid)
        self.assertIsNotNone(rec["missing_at"])     # flagged missing
        self.assertEqual(rec["keep"], 1)            # decision preserved

    # thumbnails (uses macOS sips)
    def test_thumbnail_generation(self):
        scan.scan_root(self.root)
        it = db.list_media(root=self.mediadir)[1][0]
        dst = media.thumb_path(os.path.join(self.tmp, "thumbs"), it["id"])
        self.assertTrue(media.ensure_thumb(it["file_path"], dst, it["file_type"], 128))
        self.assertGreater(os.path.getsize(dst), 0)


class TestPeriodicScanInterval(unittest.TestCase):
    """The pure interval-resolution used to schedule auto-rescans (0.4.0)."""

    def test_default_and_conversion(self):
        from peekserver import server
        self.assertEqual(server.periodic_scan_interval({"scanIntervalMinutes": 15}), 900)
        self.assertEqual(server.periodic_scan_interval({"scanIntervalMinutes": 1}), 60)

    def test_disabled_and_missing(self):
        from peekserver import server
        self.assertEqual(server.periodic_scan_interval({"scanIntervalMinutes": 0}), 0)
        self.assertEqual(server.periodic_scan_interval({}), 0)          # absent → disabled

    def test_bad_values_are_safe(self):
        from peekserver import server
        self.assertEqual(server.periodic_scan_interval({"scanIntervalMinutes": -5}), 0)   # clamped
        self.assertEqual(server.periodic_scan_interval({"scanIntervalMinutes": "x"}), 0)  # non-int


if __name__ == "__main__":
    unittest.main()
