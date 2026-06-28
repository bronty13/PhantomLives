"""Phase 2 tests — import-worker argv (pure), PurplePeek migration, dry-run worker. stdlib unittest."""
import os
import sqlite3
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peekserver import db, importer, migrate, scan  # noqa: E402


def make_png(path, w=32, h=32):
    raw = bytearray()
    for _ in range(h):
        raw.append(0); raw += bytes((120, 90, 160)) * w
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


class ImportArgvTests(unittest.TestCase):
    def test_basic_argv(self):
        a = importer.build_import_argv("osxphotos", "/m/a.jpg", "T", "C", ["k1", "k2"], ["Alb"],
                                       "/tmp/r.json", favorite=False)
        self.assertEqual(a[:3], ["osxphotos", "import", "/m/a.jpg"])
        self.assertIn("--skip-dups", a)
        self.assertEqual(a[a.index("--title") + 1], "T")
        self.assertEqual(a[a.index("--description") + 1], "C")
        self.assertEqual(a.count("--keyword"), 2)
        self.assertEqual(a[a.index("--album") + 1], "Alb")
        self.assertNotIn("--favorite-rating", a)

    def test_favorite_argv_adds_rating(self):
        a = importer.build_import_argv("osxphotos", "/staged/a.jpg", None, None, [], [],
                                       "/tmp/r.json", favorite=True)
        self.assertIn("--exiftool", a)
        self.assertIn("--favorite-rating", a)
        self.assertEqual(a[a.index("--favorite-rating") + 1], "1")
        self.assertNotIn("--title", a)  # nothing to set


class MigrateTests(unittest.TestCase):
    def _purplepeek_db(self, path, file_path):
        c = sqlite3.connect(path)
        c.executescript("""
            CREATE TABLE media_files(id TEXT PRIMARY KEY, file_path TEXT, keep INTEGER,
              is_favorite INTEGER DEFAULT 0, title TEXT, caption TEXT, is_hidden INTEGER DEFAULT 0);
            CREATE TABLE keywords(id TEXT PRIMARY KEY, name TEXT);
            CREATE TABLE file_keywords(file_id TEXT, keyword_id TEXT);
            CREATE TABLE file_albums(file_id TEXT, album_name TEXT);
        """)
        c.execute("INSERT INTO media_files VALUES('pp1',?,?,?,?,?,?)",
                  (file_path, 1, 1, "Hi", "Cap", 0))
        c.execute("INSERT INTO keywords VALUES('k','beach')")
        c.execute("INSERT INTO file_keywords VALUES('pp1','k')")
        c.execute("INSERT INTO file_albums VALUES('pp1','Summer')")
        # a decided row whose path PeekServer does NOT index → should be unmatched
        c.execute("INSERT INTO media_files VALUES('pp2','/nope/x.jpg',1,0,NULL,NULL,0)")
        c.commit(); c.close()

    def test_mapping_reads_fields_keywords_albums(self):
        tmp = tempfile.mkdtemp()
        pp = os.path.join(tmp, "pp.sqlite")
        self._purplepeek_db(pp, "/m/a.jpg")
        conn = sqlite3.connect(pp)
        decided = migrate.decisions_from_purplepeek(conn); conn.close()
        d = dict(decided)
        self.assertIn("/m/a.jpg", d)
        f = d["/m/a.jpg"]
        self.assertEqual(f["keep"], 1)
        self.assertEqual(f["is_favorite"], 1)
        self.assertEqual(f["title"], "Hi")
        self.assertEqual(f["keywords"], ["beach"])
        self.assertEqual(f["albums"], ["Summer"])

    def test_apply_matches_by_path(self):
        tmp = tempfile.mkdtemp()
        mediadir = os.path.join(tmp, "m"); os.makedirs(mediadir)
        img = os.path.join(mediadir, "a.png"); make_png(img)
        db.init(os.path.join(tmp, "peek.sqlite"))
        scan.scan_root({"path": mediadir, "label": "T", "kind": "photos"})
        pp = os.path.join(tmp, "pp.sqlite")
        self._purplepeek_db(pp, img)  # PurplePeek decision for the real scanned path
        res = migrate.migrate_from_purplepeek(pp)
        self.assertEqual(res["applied"], 1)
        self.assertEqual(res["unmatched"], 1)  # the /nope/x.jpg row
        rec = db.get_media(db.file_id(img))
        self.assertEqual(rec["keep"], 1)
        self.assertEqual(rec["title"], "Hi")
        self.assertEqual(rec["keywords"], ["beach"])


class WorkerDryRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mediadir = os.path.join(self.tmp, "m"); os.makedirs(self.mediadir)
        make_png(os.path.join(self.mediadir, "keep.png"))
        make_png(os.path.join(self.mediadir, "skip.png"))
        with open(os.path.join(self.mediadir, "song.m4a"), "wb") as f:
            f.write(b"\0" * 64)
        db.init(os.path.join(self.tmp, "peek.sqlite"))
        scan.scan_root({"path": self.mediadir, "label": "T", "kind": "photos"})
        self.cfg = {"osxphotosBin": "osxphotos", "exiftoolBin": "exiftool",
                    "stagingDir": os.path.join(self.tmp, "staging"),
                    "keptAudioDir": os.path.join(self.tmp, "audio")}

    def test_dry_run_counts_and_no_side_effects(self):
        items = {it["file_name"]: it for it in db.list_media(root=self.mediadir)[1]}
        db.update_decision(items["keep.png"]["id"], {"keep": 1})
        db.update_decision(items["skip.png"]["id"], {"keep": 0})
        db.update_decision(items["song.m4a"]["id"], {"keep": 1})
        res = importer.process_pending(self.cfg, execute=False)
        s = res["summary"]
        self.assertFalse(s["execute"])
        self.assertEqual(s["to_import"], 1)
        self.assertEqual(s["to_export_audio"], 1)
        self.assertEqual(s["to_trash"], 1)
        # dry-run: nothing imported/trashed/exported in the DB, files untouched
        self.assertTrue(all(x.get("dry_run") for x in res["log"]))
        self.assertIsNone(db.get_media(items["skip.png"]["id"])["deleted_at"])
        self.assertTrue(os.path.exists(os.path.join(self.mediadir, "skip.png")))
        self.assertFalse(os.path.exists(self.cfg["keptAudioDir"]))


if __name__ == "__main__":
    unittest.main()
