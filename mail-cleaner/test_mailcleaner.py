#!/usr/bin/env python3
"""Unit tests for mail-cleaner's pure logic (no network/IMAP needed).

Run: python3 test_mailcleaner.py
"""
import csv
import tempfile
import unittest
from pathlib import Path

import mailcleaner as mc


class ClassifyUnsub(unittest.TestCase):
    def test_one_click_preferred(self):
        lu = "<https://x.test/u?t=1>, <mailto:u@x.test>"
        lup = "List-Unsubscribe=One-Click"
        self.assertEqual(mc.classify_unsub(lu, lup),
                         ("one-click", "https://x.test/u?t=1"))

    def test_https_without_oneclick_is_http(self):
        # An https link with NO List-Unsubscribe-Post is a landing page, not
        # a one-click endpoint — must not be auto-POSTed.
        lu = "<https://x.test/manage>"
        self.assertEqual(mc.classify_unsub(lu, ""),
                         ("http", "https://x.test/manage"))

    def test_mailto_when_no_oneclick(self):
        lu = "<mailto:leave-123@bounce.test?subject=unsubscribe>"
        method, target = mc.classify_unsub(lu, "")
        self.assertEqual(method, "mailto")
        self.assertTrue(target.startswith("mailto:leave-123@"))

    def test_mailto_beats_plain_http(self):
        lu = "<https://x.test/p>, <mailto:u@x.test>"
        # no one-click marker -> mailto is more reliable than an http page
        self.assertEqual(mc.classify_unsub(lu, "")[0], "mailto")

    def test_none_when_empty(self):
        self.assertEqual(mc.classify_unsub("", ""), ("none", ""))

    def test_tolerates_whitespace_in_brackets(self):
        lu = "< https://x.test/u >"
        self.assertEqual(mc.classify_unsub(lu, "List-Unsubscribe=One-Click"),
                         ("one-click", "https://x.test/u"))


class ParseMailto(unittest.TestCase):
    def test_address_only_defaults(self):
        to, subj, body = mc.parse_mailto("mailto:u@x.test")
        self.assertEqual(to, "u@x.test")
        self.assertEqual(subj, "unsubscribe")
        self.assertEqual(body, "unsubscribe")

    def test_subject_and_body_from_query(self):
        to, subj, body = mc.parse_mailto(
            "mailto:leave@x.test?subject=Unsubscribe%20me&body=stop")
        self.assertEqual(to, "leave@x.test")
        self.assertEqual(subj, "Unsubscribe me")
        self.assertEqual(body, "stop")


class SendersFromCsv(unittest.TestCase):
    def _csv(self, rows):
        d = tempfile.mkdtemp()
        p = Path(d) / "senders.csv"
        with p.open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["address", "name", "count", "total_bytes",
                        "is_newsletter", "unsubscribe"])
            w.writerows(rows)
        return str(p)

    def test_filters_by_newsletter_and_count(self):
        path = self._csv([
            ["promo@a.test", "A", "50", "1", "yes", "<https://a.test>"],
            ["promo@b.test", "B", "2", "1", "yes", "<https://b.test>"],   # too few
            ["friend@c.test", "C", "99", "1", "", ""],                    # not newsletter
            ["promo@d.test", "D", "5", "1", "yes", "<https://d.test>"],
        ])
        got = mc.senders_from_csv(path, min_count=3)
        self.assertEqual(set(got), {"promo@a.test", "promo@d.test"})

    def test_lowercases_addresses(self):
        path = self._csv([["PROMO@A.test", "A", "10", "1", "yes", "x"]])
        self.assertEqual(mc.senders_from_csv(path, 1), ["promo@a.test"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
