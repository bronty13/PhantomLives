#!/usr/bin/env python3
"""Unit tests for build_decade_charts.py's pure parsing/logic (no network)."""
import unittest
import build_decade_charts as bdc


HOT100 = """
<table class="wikitable sortable">
<tr><th>No.</th><th>Title</th><th>Artist(s)</th></tr>
<tr><td>1</td><td>"Careless Whisper"</td><td>George Michael</td></tr>
<tr><td>2</td><td>"Like a Virgin"</td><td>Madonna</td></tr>
<tr><td>3</td><td>"Wake Me Up Before You Go-Go"</td><td>Wham!</td></tr>
</table>
"""

# Leading legend/key table (no quoted titles) THEN the real chart — the 1970 AC case.
NO1_WITH_LEGEND = """
<table class="wikitable"><tr><td>&#8224;</td><td>Indicates the year-end number one</td></tr></table>
<table class="wikitable">
<tr><th>Issue date</th><th>Title</th><th>Artist(s)</th><th>Ref.</th></tr>
<tr><td>January 5</td><td>"Raindrops Keep Fallin' on My Head"</td><td>B. J. Thomas</td><td>[1]</td></tr>
<tr><td>January 12</td><td>"Both Sides Now"</td><td>Judy Collins</td><td>[2]</td></tr>
<tr><td>January 19</td><td>[3]</td></tr>
</table>
"""

BILLBOARD_YE = (
    'lead o-chart-results-list-row '
    '<h3 class="c-title a-font">Dixie Road</h3>'
    '<span class="c-label x"><a href="/artist/lee-greenwood/">Lee Greenwood</a></span>'
    ' o-chart-results-list-row '
    '<h3 class="c-title a-font">Radio Heart</h3>'
    '<span class="c-label x">Charly McClain</span>'
)


class Hot100(unittest.TestCase):
    def test_parses_rank_title_artist(self):
        rows = bdc.parse_hot100_table(HOT100)
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0], {"artist": "George Michael", "title": "Careless Whisper"})
        self.assertEqual(rows[2]["artist"], "Wham!")           # punctuation preserved


class QuotedTitleTables(unittest.TestCase):
    def test_skips_leading_legend_table(self):
        rows = bdc.parse_quoted_title_tables(NO1_WITH_LEGEND)
        # legend table contributes nothing; rowspan continuation row (only a ref) ignored
        self.assertEqual([r["title"] for r in rows],
                         ["Raindrops Keep Fallin' on My Head", "Both Sides Now"])
        self.assertEqual(rows[0]["artist"], "B. J. Thomas")

    def test_dedupes(self):
        dup = NO1_WITH_LEGEND + NO1_WITH_LEGEND
        self.assertEqual(len(bdc.parse_quoted_title_tables(dup)), 2)


class BillboardYearEnd(unittest.TestCase):
    def test_row_container_split(self):
        rows = bdc.parse_billboard_yearend(BILLBOARD_YE)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], {"artist": "Lee Greenwood", "title": "Dixie Road"})
        self.assertEqual(rows[1]["artist"], "Charly McClain")   # plain-text label, no link


class EraPlausible(unittest.TestCase):
    def test_rejects_modern_fallback_for_old_year(self):
        modern = [{"artist": "Maneskin", "title": "x"}, {"artist": "Evanescence", "title": "y"}]
        self.assertFalse(bdc.era_plausible(modern, 1985))

    def test_accepts_period_artists(self):
        period = [{"artist": "Lee Greenwood", "title": "Dixie Road"},
                  {"artist": "Charly McClain", "title": "Radio Heart"}]
        self.assertTrue(bdc.era_plausible(period, 1985))

    def test_modern_year_always_ok(self):
        self.assertTrue(bdc.era_plausible([{"artist": "Maneskin", "title": "x"}], 2015))

    def test_empty_is_false(self):
        self.assertFalse(bdc.era_plausible([], 1985))


class DecadeYears(unittest.TestCase):
    def test_two_digit_and_four_digit(self):
        self.assertEqual(list(bdc.decade_years("70s")), list(range(1970, 1980)))
        self.assertEqual(list(bdc.decade_years("90s")), list(range(1990, 2000)))
        self.assertEqual(list(bdc.decade_years("2000s")), list(range(2000, 2010)))
        self.assertEqual(list(bdc.decade_years("2010s")), list(range(2010, 2020)))


class EssentialsConfig(unittest.TestCase):
    def test_every_decade_has_metal_and_rock(self):
        for dec, spec in bdc.ESSENTIALS.items():
            self.assertIn("metal", spec, dec)
            self.assertIn("rock", spec, dec)
            self.assertTrue(all(isinstance(s, str) for s in spec["metal"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
