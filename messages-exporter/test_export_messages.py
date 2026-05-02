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
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

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


# ─── Raw-mode helpers ──────────────────────────────────────────────────────

class TestHashesFile(unittest.TestCase):
    def test_known_hashes_of_empty_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'empty.bin'
            p.write_bytes(b'')
            # Well-known digests of the empty input — useful canaries:
            # if the chunk loop ever short-circuits on EOF differently,
            # these will catch it.
            h = em.hashes_file(p)
            self.assertEqual(h['md5'],
                'd41d8cd98f00b204e9800998ecf8427e')
            self.assertEqual(h['sha1'],
                'da39a3ee5e6b4b0d3255bfef95601890afd80709')
            self.assertEqual(h['sha256'],
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')

    def test_known_hashes_of_abc(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'abc.bin'
            p.write_bytes(b'abc')
            h = em.hashes_file(p)
            self.assertEqual(h['md5'],
                '900150983cd24fb0d6963f7d28e17f72')
            self.assertEqual(h['sha1'],
                'a9993e364706816aba3e25717850c26c9cd0d89d')
            self.assertEqual(h['sha256'],
                'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')

    def test_handles_files_larger_than_chunk(self):
        # Confirm chunked reading doesn't drop bytes for any of the three.
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'big.bin'
            payload = b'x' * (3 * (1 << 20) + 17)  # 3 MiB + change
            p.write_bytes(payload)
            import hashlib
            h = em.hashes_file(p)
            self.assertEqual(h['md5'],    hashlib.md5(payload).hexdigest())
            self.assertEqual(h['sha1'],   hashlib.sha1(payload).hexdigest())
            self.assertEqual(h['sha256'], hashlib.sha256(payload).hexdigest())

    def test_returns_lowercase_hex(self):
        # Forensic tools are case-sensitive about hash representation;
        # standardize on lowercase.
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'x.bin'
            p.write_bytes(b'forensic')
            h = em.hashes_file(p)
            for algo in ('md5', 'sha1', 'sha256'):
                self.assertEqual(h[algo], h[algo].lower())
                self.assertTrue(all(c in '0123456789abcdef' for c in h[algo]))


class TestFsStat(unittest.TestCase):
    def test_returns_size_and_iso_timestamps(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'f.txt'
            p.write_text('hello', encoding='utf-8')
            st = em.fs_stat(p)
            self.assertEqual(st['size_bytes'], 5)
            # Both required timestamp fields present and parseable as ISO.
            self.assertIn('mtime', st)
            self.assertIn('ctime', st)
            datetime.fromisoformat(st['mtime'])
            datetime.fromisoformat(st['ctime'])
            # birthtime is macOS-specific but should be present in CI on Mac.
            if 'birthtime' in st:
                datetime.fromisoformat(st['birthtime'])


class TestRawPrefix(unittest.TestCase):
    def _dt(self, *parts):
        # Naive local-time datetime — raw_prefix uses .strftime directly,
        # tz handling is the caller's job (main() passes an astimezone()'d dt).
        return datetime(*parts)

    def test_me_prefix(self):
        dt = self._dt(2026, 4, 26, 15, 55, 0)
        self.assertEqual(
            em.raw_prefix(1, dt, is_from_me=True, sender_handle=None,
                          contact='Sallie'),
            '00001_20260426T155500_Me')

    def test_other_with_handle(self):
        dt = self._dt(2026, 4, 26, 15, 55, 0)
        self.assertEqual(
            em.raw_prefix(42, dt, is_from_me=False,
                          sender_handle='+15551234567', contact='Sallie'),
            '00042_20260426T155500_+15551234567')

    def test_other_falls_back_to_contact_when_handle_missing(self):
        dt = self._dt(2026, 4, 26, 15, 55, 0)
        self.assertEqual(
            em.raw_prefix(7, dt, is_from_me=False, sender_handle=None,
                          contact='Sallie'),
            '00007_20260426T155500_Sallie')

    def test_unknown_when_no_handle_and_no_contact(self):
        dt = self._dt(2026, 4, 26, 15, 55, 0)
        self.assertEqual(
            em.raw_prefix(7, dt, is_from_me=False, sender_handle=None,
                          contact=None),
            '00007_20260426T155500_unknown')

    def test_unsafe_chars_in_sender_are_sanitized(self):
        dt = self._dt(2026, 4, 26, 15, 55, 0)
        # san() replaces /\<>:|?* with _
        self.assertEqual(
            em.raw_prefix(1, dt, is_from_me=False,
                          sender_handle='bad/name?', contact='X'),
            '00001_20260426T155500_bad_name_')

    def test_seq_zero_padded_to_5_digits(self):
        dt = self._dt(2026, 4, 26, 15, 55, 0)
        p = em.raw_prefix(99999, dt, True, None, 'X')
        self.assertTrue(p.startswith('99999_'))
        # Width 5 doesn't truncate larger numbers (Python format pads, not truncates).
        p2 = em.raw_prefix(123456, dt, True, None, 'X')
        self.assertTrue(p2.startswith('123456_'))


class TestExportRawSmoke(unittest.TestCase):
    """End-to-end-ish test of export_raw() with a fake msgs/atts pair.

    We synthesize one message with a body and one with a fake attachment
    pointing at a real on-disk file inside the temp dir. No chat.db needed.
    The asserts focus on the artifacts: directory layout, sha256 in the
    metadata, transcript shape, chain-of-custody log lines.
    """

    def test_writes_expected_artifacts_and_records_hashes(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d) / 'OUT'
            base.mkdir()
            # Synthesize a source attachment file.
            src_dir = Path(d) / 'src'
            src_dir.mkdir()
            src = src_dir / 'photo.jpg'
            src.write_bytes(b'\xff\xd8\xff\xe0FAKEJPEG')

            # Two messages: one text-only from "Me", one from contact with
            # an attachment. mts() expects mac-epoch nanoseconds for modern
            # macOS — tts() returns seconds, so we feed it tts(...) * 1e9.
            t0 = em.parse('2026-04-26 15:55:00')
            t1 = em.parse('2026-04-26 15:56:00')
            msgs = [
                # (rowid, date, is_from_me, text, attributedBody, handle)
                (1001, em.tts(t0) * 1e9, 1, 'hello from me', None, None),
                (1002, em.tts(t1) * 1e9, 0, '', None, '+15551234567'),
            ]
            atts = {
                1001: [],
                1002: [(str(src), 'image/jpeg', 'photo.jpg', 9001)],
            }

            counts = em.export_raw(
                base=base, contact='Sallie',
                handles=['+15551234567'],
                start_dt=t0, end_dt=t1,
                msgs=msgs, atts=atts,
            )

            # Counters: one photo, no videos, no other, no errors.
            self.assertEqual(counts['pc'], 1)
            self.assertEqual(counts['vc'], 0)
            self.assertEqual(counts['fc'], 0)
            self.assertEqual(counts['errors'], 0)

            # Required artifacts written.
            for name in ('transcript.txt', 'manifest.json',
                         'metadata.json', 'chain_of_custody.log'):
                self.assertTrue((base / name).exists(),
                                f'{name} should exist')

            # Body file for message 1 (Me, text-only).
            body_files = list(base.glob('00001_*_Me.txt'))
            self.assertEqual(len(body_files), 1)
            self.assertEqual(body_files[0].read_text(encoding='utf-8'),
                             'hello from me')

            # Attachment for message 2 — saved with original filename, byte-identical.
            saved = list(base.glob('00002_*_photo.jpg'))
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0].read_bytes(), src.read_bytes(),
                             'raw mode must preserve original bytes')

            # metadata.json structure + all three hashes captured.
            md = json.loads((base / 'metadata.json').read_text())
            self.assertEqual(md['export']['mode'], 'raw')
            self.assertEqual(md['export']['contact'], 'Sallie')
            self.assertEqual(md['export']['counts']['photos'], 1)
            self.assertEqual(len(md['messages']), 2)
            att_rec = md['messages'][1]['attachments'][0]
            self.assertEqual(att_rec['orig_filename'], 'photo.jpg')
            self.assertEqual(att_rec['saved_as'], saved[0].name)
            self.assertEqual(att_rec['kind'], 'photo')
            self.assertEqual(att_rec['size_bytes'], len(b'\xff\xd8\xff\xe0FAKEJPEG'))
            # All three hashes of the synthetic file are deterministic.
            import hashlib
            payload = b'\xff\xd8\xff\xe0FAKEJPEG'
            self.assertEqual(att_rec['hashes']['md5'],
                             hashlib.md5(payload).hexdigest())
            self.assertEqual(att_rec['hashes']['sha1'],
                             hashlib.sha1(payload).hexdigest())
            self.assertEqual(att_rec['hashes']['sha256'],
                             hashlib.sha256(payload).hexdigest())
            # fs_timestamps populated, error nil.
            self.assertIsNotNone(att_rec['fs_timestamps'])
            self.assertIsNone(att_rec['error'])
            # Body file metadata: body_hashes carries all three too.
            body_msg = md['messages'][0]
            self.assertIsNotNone(body_msg['body_hashes'])
            self.assertEqual(body_msg['body_hashes']['sha256'],
                             hashlib.sha256(b'hello from me').hexdigest())
            self.assertEqual(body_msg['body_hashes']['md5'],
                             hashlib.md5(b'hello from me').hexdigest())
            self.assertEqual(body_msg['body_hashes']['sha1'],
                             hashlib.sha1(b'hello from me').hexdigest())

            # Chain-of-custody log: START, VERSION, WRITE_BODY, COPY, END.
            # Both COPY and WRITE_BODY records carry md5+sha1+sha256.
            log = (base / 'chain_of_custody.log').read_text()
            self.assertIn('START contact="Sallie"', log)
            self.assertIn('VERSION exporter=', log)
            self.assertIn('WRITE_BODY', log)
            self.assertIn(f'sha256={att_rec["hashes"]["sha256"]}', log)
            self.assertIn(f'md5={att_rec["hashes"]["md5"]}', log)
            self.assertIn(f'sha1={att_rec["hashes"]["sha1"]}', log)
            self.assertIn('COPY src=', log)
            self.assertIn('END messages=2 photos=1', log)
            # The compact manifest.json still surfaces sha256 for quick
            # diff-vs-export checks, while the full hash set lives in
            # metadata.json.
            mf = json.loads((base / 'manifest.json').read_text())
            self.assertEqual(mf[1]['att'][0]['sha256'],
                             att_rec['hashes']['sha256'])

    def test_missing_source_records_error_without_failing(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d) / 'OUT'
            base.mkdir()
            t0 = em.parse('2026-04-26 15:55:00')
            msgs = [(2001, em.tts(t0) * 1e9, 0, '', None, '+15551234567')]
            # Source path that does not exist on disk.
            atts = {2001: [('/nonexistent/path/missing.jpg', 'image/jpeg',
                            'missing.jpg', 9999)]}

            counts = em.export_raw(
                base=base, contact='X', handles=['+15551234567'],
                start_dt=t0, end_dt=t0, msgs=msgs, atts=atts,
            )
            self.assertEqual(counts['errors'], 1)
            md = json.loads((base / 'metadata.json').read_text())
            att_rec = md['messages'][0]['attachments'][0]
            self.assertEqual(att_rec['error'], 'MISSING_SOURCE')
            self.assertIsNone(att_rec['saved_as'])
            # No file should have been created in the output dir.
            self.assertEqual(list(base.glob('*missing.jpg*')), [])
            log = (base / 'chain_of_custody.log').read_text()
            self.assertIn('MISSING_SOURCE', log)


# ─── Transcription helpers ──────────────────────────────────────────────────

class TestIsTranscribable(unittest.TestCase):
    def test_video_by_mime(self):
        self.assertTrue(em.is_transcribable('video/mp4', '.mp4'))
        self.assertTrue(em.is_transcribable('video/quicktime', '.mov'))

    def test_video_by_ext_when_mime_missing(self):
        self.assertTrue(em.is_transcribable(None, '.mov'))
        self.assertTrue(em.is_transcribable('', '.MOV'))    # case-insensitive

    def test_audio_by_ext(self):
        self.assertTrue(em.is_transcribable(None, '.mp3'))
        self.assertTrue(em.is_transcribable(None, '.m4a'))
        self.assertTrue(em.is_transcribable(None, '.caf'))   # iMessage voice memos
        self.assertTrue(em.is_transcribable(None, '.wav'))

    def test_audio_by_mime(self):
        # Audio mime without an extension we recognize still transcribes.
        self.assertTrue(em.is_transcribable('audio/x-something', '.bin'))

    def test_photo_skipped(self):
        self.assertFalse(em.is_transcribable('image/jpeg', '.jpg'))
        self.assertFalse(em.is_transcribable(None, '.heic'))

    def test_other_files_skipped(self):
        self.assertFalse(em.is_transcribable('application/pdf', '.pdf'))
        self.assertFalse(em.is_transcribable(None, '.txt'))
        self.assertFalse(em.is_transcribable(None, ''))


class TestPythonAtLeast(unittest.TestCase):
    def test_returns_true_for_self(self):
        # Whatever Python ran the test suite is >= 3.0; pin a concrete
        # lower bound just below current to make sure the check is real.
        self.assertTrue(em._python_at_least(sys.executable, 3, 0))

    def test_returns_false_for_nonexistent_path(self):
        self.assertFalse(em._python_at_least('/nonexistent/python', 3, 10))

    def test_returns_false_for_too_high_version(self):
        # 99.99 is plausibly never going to ship.
        self.assertFalse(em._python_at_least(sys.executable, 99, 99))


class TestFindPythonForTranscribe(unittest.TestCase):
    def test_env_override_when_compatible(self):
        # If the test runner is on >=3.10 itself, sys.executable is a
        # valid override; verify the resolution path. On 3.9 we skip.
        if sys.version_info < (3, 10):
            self.skipTest('no 3.10+ available to point at')
        with mock.patch.dict(os.environ,
                             {'TRANSCRIBE_PYTHON': sys.executable}):
            self.assertEqual(em.find_python_for_transcribe(), sys.executable)

    def test_env_override_ignored_when_incompatible(self):
        # /usr/bin/false exits non-zero so version probe fails.
        with mock.patch.dict(os.environ,
                             {'TRANSCRIBE_PYTHON': '/usr/bin/false'}):
            self.assertNotEqual(em.find_python_for_transcribe(),
                                '/usr/bin/false')

    def test_env_override_ignored_when_missing(self):
        with mock.patch.dict(os.environ,
                             {'TRANSCRIBE_PYTHON': '/nonexistent/python'}):
            # Either returns None or a fallback PATH match; should
            # never return the bogus override.
            r = em.find_python_for_transcribe()
            self.assertNotEqual(r, '/nonexistent/python')


class TestFindTranscribeScript(unittest.TestCase):
    def test_env_override_when_file_exists(self):
        with tempfile.NamedTemporaryFile(suffix='.py', delete=False) as f:
            path = f.name
        try:
            with mock.patch.dict(os.environ, {'TRANSCRIBE_SCRIPT': path}):
                self.assertEqual(em.find_transcribe_script(), Path(path))
        finally:
            os.unlink(path)

    def test_env_override_returns_none_when_missing(self):
        with mock.patch.dict(os.environ,
                             {'TRANSCRIBE_SCRIPT': '/nonexistent/path.py'}):
            self.assertIsNone(em.find_transcribe_script())

    def test_no_env_falls_back_to_default(self):
        # Just exercise the lookup. The default may or may not exist on
        # the test runner's machine; either result is acceptable here —
        # we just want the call not to raise.
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop('TRANSCRIBE_SCRIPT', None)
            r = em.find_transcribe_script()
            self.assertTrue(r is None or isinstance(r, Path))


class TestTranscribeAttachment(unittest.TestCase):
    """`transcribe_attachment` shells out to a child process. We don't run
    real Whisper here — we mock subprocess.Popen with a tiny fake that
    can simulate success, failure exit codes, and missing-output cases.
    """

    def _make_fake_popen(self, *, returncode, stdout_lines=(),
                         json_to_write=None, json_path_holder=None):
        """Return a function suitable for monkey-patching subprocess.Popen.

        json_path_holder is a list whose [0] element is set to the
        json_path argument the helper passed in cmd[5], so the fake can
        write a JSON file there to simulate transcribe.py producing
        output. Pass `json_to_write=None` to simulate no-output success.
        """
        outer = self

        class FakeProc:
            def __init__(self, cmd, **_kwargs):
                # cmd format: [python, script, '-i', src, '-o', json,
                #              '-f', 'json', '-m', model]
                if json_path_holder is not None and len(cmd) > 5:
                    json_path_holder[0] = cmd[5]
                self.stdout = iter(s + '\n' for s in stdout_lines)
                self.returncode = returncode
                self._json = json_to_write
                self._path = cmd[5] if len(cmd) > 5 else None

            def wait(self, timeout=None):
                if self._json is not None and self._path:
                    Path(self._path).write_text(json.dumps(self._json),
                                                encoding='utf-8')

            def kill(self):
                pass
        return FakeProc

    def test_missing_script_returns_actionable_error(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'video.MOV'
            dest.write_bytes(b'fake')
            r = em.transcribe_attachment(
                src_path=dest, dest_attachment_path=dest,
                model='turbo', script=None, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('transcribe.py not found', r['error'])

    def test_success_writes_json_and_synthesizes_txt_with_segments(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'video.MOV'
            dest.write_bytes(b'fake')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            payload = {
                'segments': [
                    {'start': 0.0, 'end': 2.0, 'text': '  Hello there.'},
                    {'start': 2.0, 'end': 4.0, 'text': 'How are you?  '},
                ],
                'language': 'en',
            }
            FakePopen = self._make_fake_popen(
                returncode=0, json_to_write=payload)
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertTrue(r['ok'], f'expected success, got: {r}')
            self.assertIsNotNone(r['json_path'])
            self.assertIsNotNone(r['txt_path'])
            self.assertEqual(r['json_path'].name, 'video.MOV.transcript.json')
            self.assertEqual(r['txt_path'].name,  'video.MOV.transcript.txt')
            # txt sidecar joins segment text with newlines, stripped.
            self.assertEqual(r['txt_path'].read_text(encoding='utf-8'),
                             'Hello there.\nHow are you?')

    def test_success_with_no_segments_uses_top_level_text(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'voice.m4a'
            dest.write_bytes(b'fake')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            payload = {'text': 'Just a single phrase.'}
            FakePopen = self._make_fake_popen(
                returncode=0, json_to_write=payload)
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertTrue(r['ok'])
            self.assertEqual(r['txt_path'].read_text(encoding='utf-8'),
                             'Just a single phrase.')

    def test_exit_code_3_with_explicit_error_uses_transcribe_message(self):
        # Exit 3 in transcribe.py = ffmpeg failed to decode. When the
        # script also emits its documented "Error: ..." line, that's what
        # the user wants to see (not our paraphrased exit-code mapping).
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'corrupt.mp4'
            dest.write_bytes(b'not actually a video')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            FakePopen = self._make_fake_popen(
                returncode=3,
                stdout_lines=['Error: ffmpeg failed (exit code 1).'])
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('ffmpeg failed', r['error'])
            # Partial json (none in this case) cleaned up.
            self.assertFalse((dest.parent / 'corrupt.mp4.transcript.json').exists())

    def test_exit_code_3_with_no_explicit_error_falls_back_to_mapping(self):
        # When the child died on exit 3 with no "Error: ..." line, the
        # exit-code mapping IS the best signal we have.
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'corrupt.mp4'
            dest.write_bytes(b'x')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            FakePopen = self._make_fake_popen(returncode=3)
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('ffmpeg could not decode', r['error'])

    def test_exit_code_2_maps_to_dependency_error(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'a.mov'
            dest.write_bytes(b'x')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            FakePopen = self._make_fake_popen(returncode=2)
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('mlx-whisper', r['error'])

    def test_python_traceback_classified_as_crash_not_misleading_label(self):
        # Regression: exit 1 + "Traceback ..." must not surface as
        # "input file not found" — that mapping was the documented
        # exit-1 message but Python's default uncaught-exception exit
        # code is also 1, so any crash got mis-classified.
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'a.mov'
            dest.write_bytes(b'x')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            FakePopen = self._make_fake_popen(
                returncode=1,
                stdout_lines=[
                    'Traceback (most recent call last):',
                    '  File "transcribe.py", line 53, in _bootstrap_venv',
                    '    subprocess.run(...)',
                    'subprocess.CalledProcessError: pip install failed',
                ])
            # Need the python_for_transcribe lookup to succeed so we
            # actually run the Popen path. Mock it.
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('crashed', r['error'])
            self.assertIn('CalledProcessError', r['error'])
            # And specifically NOT the misleading exit-1 default reason.
            self.assertNotIn('input file not found', r['error'])

    def test_explicit_error_line_is_surfaced_verbatim(self):
        # When transcribe.py emits its documented "Error: ..." line, we
        # show it directly rather than the exit-code mapping.
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'a.mov'
            dest.write_bytes(b'x')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            FakePopen = self._make_fake_popen(
                returncode=1,
                stdout_lines=['Error: Input file not found: /missing.mp4'])
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('Input file not found: /missing.mp4', r['error'])

    def test_no_python_available_returns_actionable_error(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'a.mov'
            dest.write_bytes(b'x')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=None):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('Python 3.10+', r['error'])
            self.assertIn('TRANSCRIBE_PYTHON', r['error'])

    def test_exit_zero_with_no_json_is_treated_as_failure(self):
        # transcribe.py promises to write the file when -o is provided.
        # If exit was 0 but the file is missing, something is genuinely
        # wrong — surface it rather than letting hashes_file() crash.
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'a.mov'
            dest.write_bytes(b'x')
            script = Path(d) / 'transcribe.py'
            script.write_text('# stub')
            FakePopen = self._make_fake_popen(
                returncode=0, json_to_write=None)  # don't write file
            with mock.patch.object(em, 'find_python_for_transcribe',
                                   return_value=sys.executable), \
                 mock.patch('subprocess.Popen', FakePopen):
                r = em.transcribe_attachment(
                    src_path=dest, dest_attachment_path=dest,
                    model='turbo', script=script, stream_label='[t]')
            self.assertFalse(r['ok'])
            self.assertIn('produced no JSON output', r['error'])


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
