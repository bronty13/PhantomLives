#!/usr/bin/env python3
"""Tests for archive_messages.py — the append-only, all-conversations archiver.

Builds a tiny synthetic chat.db (only the columns the archiver queries) and
verifies: all-chats enumeration, GUID-dedup idempotency, the incremental
watermark, attributedBody text decode (via the reused get_body), and
attachment path mapping. Standard library only.

Run:  python3 test_archive_messages.py
"""
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

import archive_messages as am


def make_db(path, messages):
    """messages: list of dicts with keys
       rowid, guid, date, is_from_me, text, ab(bytes|None), handle_id,
       chat_id, attachments(list of (filename, mime, xfer))
       plus chats: dict chat_rowid -> (guid, identifier, display_name)
    Provided as (chats, messages)."""
    chats, msgs = messages
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE handle(ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat(ROWID INTEGER PRIMARY KEY, guid TEXT,
                          chat_identifier TEXT, display_name TEXT);
        CREATE TABLE message(ROWID INTEGER PRIMARY KEY, guid TEXT, date INTEGER,
                             is_from_me INTEGER, text TEXT, attributedBody BLOB,
                             handle_id INTEGER);
        CREATE TABLE chat_message_join(chat_id INTEGER, message_id INTEGER);
        CREATE TABLE attachment(ROWID INTEGER PRIMARY KEY, filename TEXT,
                                mime_type TEXT, transfer_name TEXT);
        CREATE TABLE message_attachment_join(message_id INTEGER, attachment_id INTEGER);
    """)
    handles = {}
    for cid, (guid, ident, disp) in chats.items():
        conn.execute('INSERT INTO chat(ROWID,guid,chat_identifier,display_name) '
                     'VALUES(?,?,?,?)', (cid, guid, ident, disp))
    att_rowid = 0
    for m in msgs:
        hid = None
        if m.get('handle'):
            hid = handles.get(m['handle'])
            if hid is None:
                hid = len(handles) + 1
                handles[m['handle']] = hid
                conn.execute('INSERT INTO handle(ROWID,id) VALUES(?,?)', (hid, m['handle']))
        conn.execute('INSERT INTO message(ROWID,guid,date,is_from_me,text,'
                     'attributedBody,handle_id) VALUES(?,?,?,?,?,?,?)',
                     (m['rowid'], m['guid'], m['date'], m['is_from_me'],
                      m.get('text'), m.get('ab'), hid))
        conn.execute('INSERT INTO chat_message_join(chat_id,message_id) VALUES(?,?)',
                     (m['chat_id'], m['rowid']))
        for (fname, mime, xfer) in m.get('attachments', []):
            att_rowid += 1
            conn.execute('INSERT INTO attachment(ROWID,filename,mime_type,'
                         'transfer_name) VALUES(?,?,?,?)', (att_rowid, fname, mime, xfer))
            conn.execute('INSERT INTO message_attachment_join(message_id,'
                         'attachment_id) VALUES(?,?)', (m['rowid'], att_rowid))
    conn.commit()
    conn.close()


# Realistic Mac-epoch nanosecond timestamps (mts() treats >1e10 as ns).
T1 = 700000000000000000
T2 = 700000001000000000
T3 = 700000002000000000
T4 = 700000003000000000

CHATS = {
    1: ('iMessage;-;+15551112222', '+15551112222', None),       # 1:1
    2: ('iMessage;+;chat999', 'chat999', 'Family Group'),       # group
}


def base_messages():
    # attributedBody blob that get_body should decode to "hello" (text empty).
    ab = b'\x00NSString\x01\x94\x84\x01+' + bytes([5]) + b'hello'
    return (CHATS, [
        {'rowid': 1, 'guid': 'G1', 'date': T1, 'is_from_me': 0,
         'text': 'first message', 'handle': '+15551112222', 'chat_id': 1},
        {'rowid': 2, 'guid': 'G2', 'date': T2, 'is_from_me': 1,
         'text': '', 'ab': ab, 'chat_id': 1,
         'attachments': [('~/Library/Messages/Attachments/ab/12/GUID/IMG_1.HEIC',
                          'image/heic', 'IMG_1.HEIC')]},
        {'rowid': 3, 'guid': 'G3', 'date': T2, 'is_from_me': 0,
         'text': 'group hi', 'handle': '+15553334444', 'chat_id': 2},
    ])


class ArchiveMessagesTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = str(self.root / 'chat.db')
        self.archive = str(self.root / 'Archive')

    def tearDown(self):
        self.tmp.cleanup()

    def _manifest(self):
        p = Path(self.archive) / 'manifest.jsonl'
        if not p.exists():
            return []
        return [json.loads(l) for l in p.read_text().splitlines() if l.strip()]

    def test_backfill_all_chats(self):
        make_db(self.db, base_messages())
        r = am.run_archive(self.db, self.archive, full=True)
        self.assertEqual(r['appended'], 3)
        self.assertEqual(r['conversations_touched'], 2)        # both chats
        entries = self._manifest()
        self.assertEqual(len(entries), 3)
        # Two conversation transcript files exist.
        convs = list((Path(self.archive) / 'conversations').glob('*/transcript.txt'))
        self.assertEqual(len(convs), 2)

    def test_attributedbody_decoded(self):
        make_db(self.db, base_messages())
        am.run_archive(self.db, self.archive, full=True)
        g2 = next(e for e in self._manifest() if e['guid'] == 'G2')
        self.assertEqual(g2['text'], 'hello')                  # decoded from blob
        self.assertEqual(g2['sender'], 'Me')                   # is_from_me=1

    def test_attachment_path_mapping(self):
        make_db(self.db, base_messages())
        am.run_archive(self.db, self.archive, full=True)
        g2 = next(e for e in self._manifest() if e['guid'] == 'G2')
        self.assertEqual(len(g2['attachments']), 1)
        at = g2['attachments'][0]
        self.assertEqual(at['kind'], 'photo')
        self.assertEqual(at['path'], 'attachments/ab/12/GUID/IMG_1.HEIC')

    def test_idempotent_rerun(self):
        make_db(self.db, base_messages())
        am.run_archive(self.db, self.archive, full=True)
        r2 = am.run_archive(self.db, self.archive)            # incremental
        self.assertEqual(r2['appended'], 0)                   # nothing new
        self.assertEqual(len(self._manifest()), 3)            # no duplicates
        # And a --full re-run must still not duplicate (GUID dedup).
        r3 = am.run_archive(self.db, self.archive, full=True)
        self.assertEqual(r3['appended'], 0)
        self.assertEqual(len(self._manifest()), 3)

    def test_incremental_watermark(self):
        make_db(self.db, base_messages())
        am.run_archive(self.db, self.archive, full=True)
        # Add a newer message and re-run incrementally.
        conn = sqlite3.connect(self.db)
        conn.execute('INSERT INTO message(ROWID,guid,date,is_from_me,text,handle_id) '
                     'VALUES(?,?,?,?,?,?)', (4, 'G4', T4, 0, 'later message', 1))
        conn.execute('INSERT INTO chat_message_join(chat_id,message_id) VALUES(?,?)', (1, 4))
        conn.commit(); conn.close()
        r = am.run_archive(self.db, self.archive)
        self.assertEqual(r['appended'], 1)
        self.assertEqual(len(self._manifest()), 4)
        self.assertTrue(any(e['guid'] == 'G4' for e in self._manifest()))

    def test_transcript_has_text_and_attachment_ref(self):
        make_db(self.db, base_messages())
        am.run_archive(self.db, self.archive, full=True)
        text = '\n'.join(p.read_text() for p in
                         (Path(self.archive) / 'conversations').glob('*/transcript.txt'))
        self.assertIn('first message', text)
        self.assertIn('hello', text)
        self.assertIn('attachments/ab/12/GUID/IMG_1.HEIC', text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
