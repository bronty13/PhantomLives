#!/usr/bin/env python3
# =============================================================================
#
#   MESSAGES EXPORTER — UNIT TESTS
#
#   File:        test_export_messages.py
#   Requires:    Python 3.9+ (stdlib unittest only; emoji lib optional but
#                recommended — several word-mode tests are skipped without it)
#
#   Description:
#     Pure-function unit tests. No chat.db or AddressBook access; nothing
#     here requires Full Disk Access. Run from this directory:
#
#         python3 test_export_messages.py                 # system python
#         ~/.venvs/messages-exporter/bin/python3 test_export_messages.py
#
#     Exit code is 0 on success, non-zero on any failure (friendly to CI).
#
# =============================================================================

import importlib.util
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

# ─── Module loader ──────────────────────────────────────────────────────────
# The script lives in a hyphenated directory (messages-exporter/) so a plain
# `import export_messages` won't work. Load it by path instead.

HERE = Path(__file__).parent.resolve()
SCRIPT_PATH = HERE / 'export_messages.py'

_spec = importlib.util.spec_from_file_location('export_messages', SCRIPT_PATH)
em = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(em)


# ─── Helpers for crafting attributedBody blobs ──────────────────────────────

def make_ab_blob(text, prefix_bytes=b'\x01\x94\x84\x01', extra_marker=None):
    """Synthesize a minimal attributedBody-like blob containing `text`.

    Layout: [NSString][prefix_bytes][optional extra marker][+][len_byte][utf8].
    """
    utf8 = text.encode('utf-8')
    if len(utf8) > 127:
        raise ValueError('test helper only handles strings <=127 bytes')
    blob = b'NSString' + prefix_bytes
    if extra_marker is not None:
        blob += extra_marker
    blob += b'+' + bytes([len(utf8)]) + utf8
    return blob


# ─── slug() ─────────────────────────────────────────────────────────────────

class TestSlug(unittest.TestCase):
    def test_empty_returns_placeholder(self):
        self.assertEqual(em.slug('', mode='strip'), 'NO_TEXT')
        self.assertEqual(em.slug('   ', mode='word'), 'NO_TEXT')
        self.assertEqual(em.slug(None, mode='keep'), 'NO_TEXT')

    def test_strip_mode_drops_emoji_and_punct(self):
        self.assertEqual(em.slug('Hello world!', mode='strip'), 'Hello_world')
        self.assertEqual(em.slug('Hi 🔥', mode='strip'), 'Hi')
        self.assertEqual(em.slug('one, two, three', mode='strip'),
                         'one_two_three')

    def test_keep_mode_preserves_emoji(self):
        self.assertEqual(em.slug('Hi 🔥', mode='keep'), 'Hi_🔥')
        self.assertEqual(em.slug('yes ❤️', mode='keep'), 'yes_❤️')

    @unittest.skipUnless(em.HAS_EMOJI, 'emoji library not installed')
    def test_word_mode_replaces_emoji_with_name(self):
        self.assertEqual(em.slug('Hi 🔥', mode='word'), 'Hi_(fire)')
        self.assertIn('(red_heart)', em.slug('She said ❤️', mode='word'))
        self.assertIn('(face_with_tears_of_joy)',
                      em.slug('lol 😂', mode='word'))

    def test_unicode_letters_preserved(self):
        # café / 日本語 survive all modes (word has isalnum filter too).
        self.assertEqual(em.slug('café bar', mode='strip'), 'café_bar')
        self.assertEqual(em.slug('café bar', mode='word'), 'café_bar')
        self.assertEqual(em.slug('café bar', mode='keep'), 'café_bar')
        self.assertEqual(em.slug('日本語 text', mode='keep'), '日本語_text')

    def test_max_length_truncation(self):
        long_text = 'a' * 500
        self.assertEqual(len(em.slug(long_text, mode='strip', mx=50)), 50)
        self.assertEqual(len(em.slug(long_text, mode='strip', mx=120)), 120)

    def test_whitespace_collapses_to_underscore(self):
        self.assertEqual(em.slug('hi    there\t\nfriend', mode='strip'),
                         'hi_there_friend')

    def test_parens_behavior_per_mode(self):
        # Strip mode is strict: parens dropped along with other punctuation.
        self.assertEqual(em.slug('check (this) out', mode='strip'),
                         'check_this_out')
        # Word and keep preserve parens so the emoji demojize output
        # "(face_blowing_a_kiss)" survives intact.
        self.assertEqual(em.slug('check (this) out', mode='word'),
                         'check_(this)_out')
        self.assertEqual(em.slug('check (this) out', mode='keep'),
                         'check_(this)_out')


# ─── norm() / san() ─────────────────────────────────────────────────────────

class TestPhoneAndFilename(unittest.TestCase):
    def test_norm_strips_formatting(self):
        self.assertEqual(em.norm('+1 (419) 216-1011'), '4192161011')
        self.assertEqual(em.norm('419.216.1011'), '4192161011')
        self.assertEqual(em.norm('14192161011'), '4192161011')
        # Less than 10 digits: return as-is (no truncation)
        self.assertEqual(em.norm('911'), '911')

    def test_san_replaces_unsafe_chars(self):
        self.assertEqual(em.san('foo/bar'), 'foo_bar')
        self.assertEqual(em.san('a<b>c:d'), 'a_b_c_d')
        self.assertEqual(em.san('question?mark*star'), 'question_mark_star')
        # Control chars
        self.assertEqual(em.san('line1\nline2'), 'line1_line2')
        # Safe chars survive
        self.assertEqual(em.san('hello_world-1.2'), 'hello_world-1.2')


# ─── parse() / mts() / tts() ────────────────────────────────────────────────

class TestDateHelpers(unittest.TestCase):
    def test_parse_all_formats(self):
        # All three accepted input shapes; output is UTC-aware.
        a = em.parse('2026-04-23 10:21:00')
        b = em.parse('2026-04-23 10:21')
        c = em.parse('2026-04-23')
        for x in (a, b, c):
            self.assertEqual(x.tzinfo, timezone.utc)
        # Same clock time on the day: a and b should be equal.
        self.assertEqual(a, b)

    def test_parse_bad_raises(self):
        with self.assertRaises(ValueError):
            em.parse('not a date')
        with self.assertRaises(ValueError):
            em.parse('2026/04/23')

    def test_mts_seconds_vs_nanoseconds(self):
        # A known instant: 2001-01-01 00:00:00 UTC (Mac epoch) = mac-seconds 0.
        zero = em.mts(0)
        self.assertEqual(zero, datetime(2001, 1, 1, tzinfo=timezone.utc))
        # Same moment expressed in nanoseconds.
        zero_ns = em.mts(0.0)  # float 0 < 1e10, so still seconds path
        self.assertEqual(zero_ns, zero)
        # 1 second after mac epoch, in nanoseconds
        one_sec_ns = em.mts(1e9)   # 1e9 > 1e10 is False, still seconds
        # Use a value clearly in nanosecond regime
        modern_ns = 8e17  # much > 1e10
        dt = em.mts(modern_ns)
        # Should land in the 2020s, not way in the future
        self.assertGreater(dt.year, 2020)
        self.assertLess(dt.year, 2050)

    def test_tts_roundtrip(self):
        dt = em.parse('2026-04-23 10:21:00')
        secs = em.tts(dt)
        back = em.mts(secs)
        self.assertEqual(back, dt)


# ─── knd() ──────────────────────────────────────────────────────────────────

class TestKind(unittest.TestCase):
    def test_photo_by_mime(self):
        self.assertEqual(em.knd('image/jpeg', '.jpg'), 'photo')
        self.assertEqual(em.knd('image/png', '.png'), 'photo')

    def test_photo_by_extension(self):
        self.assertEqual(em.knd(None, '.heic'), 'photo')
        self.assertEqual(em.knd(None, '.WEBP'), 'photo')  # case-insensitive

    def test_video_by_mime_or_ext(self):
        self.assertEqual(em.knd('video/mp4', '.mp4'), 'video')
        self.assertEqual(em.knd(None, '.mov'), 'video')

    def test_other_is_file(self):
        self.assertEqual(em.knd('application/pdf', '.pdf'), 'file')
        self.assertEqual(em.knd(None, '.txt'), 'file')
        self.assertEqual(em.knd('', ''), 'file')


# ─── uniq() ─────────────────────────────────────────────────────────────────

class TestUniq(unittest.TestCase):
    def test_first_name_is_bare(self):
        with tempfile.TemporaryDirectory() as d:
            seen = set()
            p = em.uniq(Path(d), 'foo', '.jpg', seen)
            self.assertEqual(p.name, 'foo.jpg')
            self.assertIn('foo.jpg', seen)

    def test_collision_adds_suffix(self):
        with tempfile.TemporaryDirectory() as d:
            seen = {'foo.jpg'}
            p = em.uniq(Path(d), 'foo', '.jpg', seen)
            self.assertEqual(p.name, 'foo_2.jpg')
            q = em.uniq(Path(d), 'foo', '.jpg', seen)
            self.assertEqual(q.name, 'foo_3.jpg')
            r = em.uniq(Path(d), 'foo', '.jpg', seen)
            self.assertEqual(r.name, 'foo_4.jpg')


# ─── get_body() ─────────────────────────────────────────────────────────────

class TestGetBody(unittest.TestCase):
    def test_prefers_plain_text_when_present(self):
        self.assertEqual(em.get_body('hello', None), 'hello')
        # Whitespace trimmed
        self.assertEqual(em.get_body('  hello  ', None), 'hello')
        # Even with an attributedBody present, text column wins.
        blob = make_ab_blob('from_blob')
        self.assertEqual(em.get_body('from_text', blob), 'from_text')

    def test_empty_everything_returns_empty_string(self):
        self.assertEqual(em.get_body(None, None), '')
        self.assertEqual(em.get_body('', None), '')
        self.assertEqual(em.get_body('   ', None), '')

    def test_plain_ascii_from_attributedBody(self):
        blob = make_ab_blob('Hello world')
        self.assertEqual(em.get_body('', blob), 'Hello world')
        # Empty text column should route through blob
        self.assertEqual(em.get_body(None, blob), 'Hello world')

    def test_emoji_utf8_from_attributedBody(self):
        blob = make_ab_blob('Hi 🔥')
        self.assertEqual(em.get_body('', blob), 'Hi 🔥')

    def test_unicode_letters_from_attributedBody(self):
        blob = make_ab_blob('café 日本')
        self.assertEqual(em.get_body('', blob), 'café 日本')

    def test_no_nsstring_marker_returns_empty(self):
        self.assertEqual(em.get_body('', b'\x00\x01\x02random bytes'), '')

    def test_false_plus_is_skipped_for_real_one(self):
        # Craft a blob where a '+' appears early but leads to non-printable
        # bytes; the real string follows. The extractor must skip the decoy
        # and land on the valid '+'.
        real_text = 'Hello'
        real_utf8 = real_text.encode('utf-8')
        # 2-byte prefix, then a decoy '+' with a non-printable "length" that
        # would point into garbage, then the real '+' with the actual string.
        blob = (
            b'NSString'
            + b'\x01\x94'                      # short prefix
            + b'+' + bytes([0x05])             # decoy: length=5
            + b'\x00\x01\x02\x03\x04'          # 5 non-printable bytes (decoy)
            + b'+' + bytes([len(real_utf8)])   # real delimiter + length
            + real_utf8                        # real string
        )
        self.assertEqual(em.get_body('', blob), real_text)

    def test_corrupt_blob_returns_empty_not_raises(self):
        # Random bytes starting with NSString but nothing valid after.
        blob = b'NSString' + b'\xff' * 5
        self.assertEqual(em.get_body('', blob), '')

    def test_object_replacement_char_stripped_from_text_column(self):
        # iMessage inserts U+FFFC as an inline-attachment placeholder. It
        # must not leak into captions/filenames.
        self.assertEqual(em.get_body('￼Hello', None), 'Hello')
        self.assertEqual(em.get_body('￼￼￼May 1', None), 'May 1')
        # A caption that is ONLY placeholders is effectively empty.
        self.assertEqual(em.get_body('￼￼', None), '')

    def test_object_replacement_char_stripped_from_attributedBody(self):
        blob = make_ab_blob('￼May 1 - big and bouncey')
        self.assertEqual(em.get_body('', blob), 'May 1 - big and bouncey')
        blob2 = make_ab_blob('￼￼￼Hi 🔥')
        self.assertEqual(em.get_body('', blob2), 'Hi 🔥')


# ─── Capability detection sanity ────────────────────────────────────────────

class TestCapabilityFlags(unittest.TestCase):
    def test_flags_are_booleans(self):
        self.assertIsInstance(em.HAS_SIPS, bool)
        self.assertIsInstance(em.HAS_EXIFTOOL, bool)
        self.assertIsInstance(em.HAS_FFMPEG, bool)
        self.assertIsInstance(em.HAS_PIL, bool)
        self.assertIsInstance(em.HAS_HEIF, bool)
        self.assertIsInstance(em.HAS_EMOJI, bool)

    def test_version_is_semver_ish(self):
        self.assertRegex(em.__version__, r'^\d+\.\d+\.\d+$')


# ─── Runner ─────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    # verbosity=2 prints one line per test, which reads well in CI logs.
    unittest.main(verbosity=2)
