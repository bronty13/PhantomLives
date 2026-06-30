#!/usr/bin/env python3
"""Tests for oldfiles. Pure stdlib (unittest) — run: python3 test_oldfiles.py"""

import os
import tempfile
import time
import unittest
from pathlib import Path

import oldfiles as of


class TestDuration(unittest.TestCase):
    def test_units(self):
        self.assertAlmostEqual(of.parse_duration("1y"), 365 * 86400)
        self.assertAlmostEqual(of.parse_duration("6mo"), 6 * 30 * 86400)
        self.assertAlmostEqual(of.parse_duration("2w"), 14 * 86400)
        self.assertAlmostEqual(of.parse_duration("90d"), 90 * 86400)
        self.assertAlmostEqual(of.parse_duration("48h"), 48 * 3600)

    def test_bare_integer_is_days(self):
        self.assertAlmostEqual(of.parse_duration("30"), 30 * 86400)

    def test_aliases_and_spaces(self):
        self.assertAlmostEqual(of.parse_duration("1 year"), 365 * 86400)
        self.assertAlmostEqual(of.parse_duration("3 months"), 90 * 86400)

    def test_invalid(self):
        for bad in ("", "abc", "1x", "y"):
            with self.assertRaises(ValueError):
                of.parse_duration(bad)


class TestSize(unittest.TestCase):
    def test_units(self):
        self.assertEqual(of.parse_size("2048"), 2048)
        self.assertEqual(of.parse_size("1K"), 1024)
        self.assertEqual(of.parse_size("100M"), 100 * 1024 ** 2)
        self.assertEqual(of.parse_size("1G"), 1024 ** 3)
        self.assertEqual(of.parse_size("1.5G"), int(1.5 * 1024 ** 3))

    def test_invalid(self):
        with self.assertRaises(ValueError):
            of.parse_size("big")


class TestGuard(unittest.TestCase):
    def test_blocks_structural_roots(self):
        for p in ("/", "/System", "/usr", "/var", str(Path.home()),
                  str(Path.home() / "Library"), "/Users", "/Volumes"):
            blocked, _ = of.is_protected(p)
            self.assertTrue(blocked, f"{p} should be protected")

    def test_allows_normal_dirs(self):
        with tempfile.TemporaryDirectory() as d:
            sub = os.path.join(d, "stuff")
            os.makedirs(sub)
            blocked, _ = of.is_protected(sub)
            self.assertFalse(blocked, f"{sub} should be allowed")


class TestFileTimeSelection(unittest.TestCase):
    def test_fields(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "x.txt")
            Path(f).write_text("hi")
            st = os.stat(f)
            self.assertEqual(of.file_time(st, "modified"), st.st_mtime)
            self.assertEqual(of.file_time(st, "accessed"), st.st_atime)
            # created falls back to mtime where birthtime is absent.
            self.assertEqual(of.file_time(st, "created"),
                             float(getattr(st, "st_birthtime", st.st_mtime)))


class _Tree(unittest.TestCase):
    """Builds source/{a.txt, .hidden.txt, big.log, sub/b.txt, sub/deep/c.txt}."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self._mk("a.txt", b"a")
        self._mk(".hidden.txt", b"h")
        self._mk("big.log", b"x" * 5000)
        self._mk("sub/b.txt", b"b")
        self._mk("sub/deep/c.txt", b"c")

    def tearDown(self):
        self.tmp.cleanup()

    def _mk(self, rel, data):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True) if os.path.dirname(rel) else None
        Path(p).write_bytes(data)
        return p

    def _names(self, kw):
        return sorted(os.path.relpath(f, self.root)
                      for f, _ in of.walk_files(self.root, **kw))


_BASE = dict(include_hidden=False, follow_symlinks=False, exts=None, glob=None, min_size=0)


class TestWalkDepth(_Tree):
    def test_depth_zero_top_level_only(self):
        names = self._names({**_BASE, "max_depth": 0})
        self.assertEqual(names, ["a.txt", "big.log"])  # hidden skipped, no descent

    def test_depth_one(self):
        names = self._names({**_BASE, "max_depth": 1})
        self.assertEqual(names, ["a.txt", "big.log", "sub/b.txt"])

    def test_unlimited(self):
        names = self._names({**_BASE, "max_depth": None})
        self.assertEqual(names, ["a.txt", "big.log", "sub/b.txt", "sub/deep/c.txt"])


class TestWalkFilters(_Tree):
    def test_include_hidden(self):
        names = self._names({**_BASE, "max_depth": 0, "include_hidden": True})
        self.assertIn(".hidden.txt", names)

    def test_ext_filter(self):
        names = self._names({**_BASE, "max_depth": None, "exts": {"log"}})
        self.assertEqual(names, ["big.log"])

    def test_glob_filter(self):
        names = self._names({**_BASE, "max_depth": None, "glob": "*.txt"})
        self.assertEqual(names, ["a.txt", "sub/b.txt", "sub/deep/c.txt"])

    def test_min_size(self):
        names = self._names({**_BASE, "max_depth": None, "min_size": 1000})
        self.assertEqual(names, ["big.log"])


class TestCollectMatches(_Tree):
    def test_age_threshold_by_modified(self):
        now = time.time()
        old = now - 400 * 86400   # ~13 months
        # Age a.txt and sub/b.txt; leave the rest recent.
        os.utime(os.path.join(self.root, "a.txt"), (old, old))
        os.utime(os.path.join(self.root, "sub/b.txt"), (old, old))
        cutoff = now - of.parse_duration("1y")
        matches = of.collect_matches(self.root, cutoff, "modified", max_depth=None, **_BASE)
        got = sorted(os.path.relpath(m.path, self.root) for m in matches)
        self.assertEqual(got, ["a.txt", "sub/b.txt"])

    def test_nothing_when_all_recent(self):
        cutoff = time.time() - of.parse_duration("1y")
        matches = of.collect_matches(self.root, cutoff, "modified", max_depth=None, **_BASE)
        self.assertEqual(matches, [])


class TestDelete(_Tree):
    def test_permanent_delete_removes_files(self):
        f = os.path.join(self.root, "a.txt")
        m = of.Match(f, 1, time.time(), "modified")
        removed, failed = of.do_delete([m], permanent=True)
        self.assertEqual(removed, [f])
        self.assertEqual(failed, [])
        self.assertFalse(os.path.exists(f))

    def test_delete_skips_protected(self):
        m = of.Match("/System", 0, 0.0, "modified")
        removed, failed = of.do_delete([m], permanent=True)
        self.assertEqual(removed, [])
        self.assertEqual(len(failed), 1)
        self.assertTrue(os.path.exists("/System"))


class TestMainDryRun(_Tree):
    def test_dry_run_deletes_nothing(self):
        rc = of.main([self.root, "--older-than", "0d", "--quiet"])
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.exists(os.path.join(self.root, "a.txt")))

    def test_protected_source_exits(self):
        with self.assertRaises(SystemExit):
            of.main(["/", "--older-than", "1y"])

    def test_conflicting_actions_exit(self):
        with self.assertRaises(SystemExit):
            of.main([self.root, "--delete", "--delete-permanent"])


class TestExternalVolumeTrashGuard(_Tree):
    def test_home_is_not_a_separate_volume(self):
        # The home dir is on the same volume as itself — never flagged.
        self.assertFalse(of._on_separate_volume(os.path.expanduser("~")))

    def test_delete_trash_on_separate_volume_aborts(self):
        # Simulate the source being on an external volume: --delete (Trash) must
        # refuse (SystemExit) and delete nothing, steering to --delete-permanent.
        orig = of._on_separate_volume
        of._on_separate_volume = lambda p: True
        try:
            with self.assertRaises(SystemExit):
                of.main([self.root, "--older-than", "0d", "--delete", "-y", "--quiet"])
        finally:
            of._on_separate_volume = orig
        self.assertTrue(os.path.exists(os.path.join(self.root, "a.txt")))

    def test_permanent_delete_on_separate_volume_is_allowed(self):
        # The guard is Trash-only; --delete-permanent must still work on a "separate" volume.
        orig = of._on_separate_volume
        of._on_separate_volume = lambda p: True
        try:
            rc = of.main([self.root, "--older-than", "0d", "--delete-permanent", "-y", "--quiet"])
        finally:
            of._on_separate_volume = orig
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(os.path.join(self.root, "a.txt")))

    def test_do_delete_emits_progress(self):
        # A long run must not be silent: progress fires on the cadence.
        import io, contextlib
        files = [of.Match(self._mk(f"p{i}.txt", b"x"), 1, time.time(), "modified")
                 for i in range(5)]
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            removed, failed = of.do_delete(files, permanent=True, progress_every=2)
        self.assertEqual(len(removed), 5)
        self.assertIn("processed", buf.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
