#!/usr/bin/env python3
"""Tests for the Apple Notes + Reminders archivers (synthetic SQLite DBs).

Run:  python3 test_apple_archiver.py
"""
import gzip
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

import notes_archiver as na
import reminders_archiver as ra


def note_proto(text):
    """Minimal gzip'd protobuf the decoder recognizes: field 2, wiretype 2 (string)."""
    b = bytes([0x12, len(text)]) + text.encode('utf-8')
    return gzip.compress(b)


def make_notestore(path, notes):
    """notes: list of (identifier, title, body, folder_pk, deleted)."""
    conn = sqlite3.connect(path)
    conn.executescript("""
        DROP TABLE IF EXISTS ZICCLOUDSYNCINGOBJECT; DROP TABLE IF EXISTS ZICNOTEDATA;
        CREATE TABLE ZICCLOUDSYNCINGOBJECT(Z_PK INTEGER PRIMARY KEY, ZIDENTIFIER TEXT,
            ZTITLE1 TEXT, ZTITLE2 TEXT, ZFOLDER INTEGER, ZNOTEDATA INTEGER,
            ZCREATIONDATE3 REAL, ZCREATIONDATE1 REAL, ZCREATIONDATE REAL,
            ZMODIFICATIONDATE1 REAL, ZMODIFICATIONDATE REAL, ZMARKEDFORDELETION INTEGER);
        CREATE TABLE ZICNOTEDATA(Z_PK INTEGER PRIMARY KEY, ZDATA BLOB);
    """)
    # folder row
    conn.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZTITLE2) VALUES(100,'Recipes')")
    pk = 1
    for (ident, title, body, folder_pk, deleted) in notes:
        conn.execute('INSERT INTO ZICNOTEDATA(Z_PK,ZDATA) VALUES(?,?)', (pk, note_proto(body)))
        conn.execute('INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZIDENTIFIER,ZTITLE1,ZFOLDER,'
                     'ZNOTEDATA,ZCREATIONDATE3,ZMODIFICATIONDATE1,ZMARKEDFORDELETION) '
                     'VALUES(?,?,?,?,?,?,?,?)',
                     (pk + 200, ident, title, folder_pk, pk, 700000000.0, 700000100.0, 1 if deleted else 0))
        pk += 1
    conn.commit(); conn.close()


def make_reminders(path, lists, reminders):
    conn = sqlite3.connect(path)
    conn.executescript("""
        DROP TABLE IF EXISTS ZREMCDBASELIST; DROP TABLE IF EXISTS ZREMCDREMINDER;
        CREATE TABLE ZREMCDBASELIST(Z_PK INTEGER PRIMARY KEY, ZNAME TEXT);
        CREATE TABLE ZREMCDREMINDER(Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT, ZNOTES TEXT,
            ZDUEDATE REAL, ZCOMPLETED INTEGER, ZCOMPLETIONDATE REAL, ZFLAGGED INTEGER,
            ZPRIORITY INTEGER, ZCREATIONDATE REAL, ZLIST INTEGER);
    """)
    for pk, name in lists:
        conn.execute('INSERT INTO ZREMCDBASELIST(Z_PK,ZNAME) VALUES(?,?)', (pk, name))
    pk = 1
    for (title, notes, due, completed, flagged, prio, listpk) in reminders:
        conn.execute('INSERT INTO ZREMCDREMINDER(Z_PK,ZTITLE,ZNOTES,ZDUEDATE,ZCOMPLETED,'
                     'ZCOMPLETIONDATE,ZFLAGGED,ZPRIORITY,ZCREATIONDATE,ZLIST) '
                     'VALUES(?,?,?,?,?,?,?,?,?,?)',
                     (pk, title, notes, due, 1 if completed else 0,
                      700000200.0 if completed else None, 1 if flagged else 0,
                      prio, 700000000.0, listpk))
        pk += 1
    conn.commit(); conn.close()


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.db = str(self.root / 'NoteStore.sqlite')
        self.archive = str(self.root / 'NotesArchive')

    def tearDown(self):
        self.tmp.cleanup()

    def _manifest(self):
        p = Path(self.archive) / 'manifest.jsonl'
        return [json.loads(l) for l in p.read_text().splitlines() if l.strip()] if p.exists() else []

    def test_decode_and_archive(self):
        make_notestore(self.db, [('N1', 'Chimichurri', 'Smoky red sauce recipe', 100, False)])
        r = na.run_archive(self.db, self.archive)
        self.assertEqual(r['notes'], 1)
        self.assertEqual(len(self._manifest()), 1)
        md = list((Path(self.archive) / 'notes').glob('Recipes/*.md'))
        self.assertEqual(len(md), 1)
        body = md[0].read_text()
        self.assertIn('Smoky red sauce recipe', body)      # protobuf decoded
        self.assertIn('Folder: Recipes', body)
        self.assertTrue((Path(self.archive) / 'notes.html').exists())
        self.assertTrue((Path(self.archive) / '_index.csv').exists())

    def test_idempotent(self):
        make_notestore(self.db, [('N1', 'A', 'body one', 100, False)])
        na.run_archive(self.db, self.archive)
        r = na.run_archive(self.db, self.archive)
        self.assertEqual(r['new_versions'], 0)
        self.assertEqual(len(self._manifest()), 1)

    def test_versioning_on_edit(self):
        make_notestore(self.db, [('N1', 'A', 'body one', 100, False)])
        na.run_archive(self.db, self.archive)
        # Edit the note body, re-run → a new version is appended, latest rendered.
        make_notestore(self.db, [('N1', 'A', 'body two EDITED', 100, False)])
        r = na.run_archive(self.db, self.archive)
        self.assertEqual(r['new_versions'], 1)
        self.assertEqual(len(self._manifest()), 2)          # both versions kept
        self.assertEqual(r['notes'], 1)                     # one current note
        md = list((Path(self.archive) / 'notes').glob('Recipes/*.md'))[0].read_text()
        self.assertIn('body two EDITED', md)

    def test_deleted_note_preserved(self):
        make_notestore(self.db, [('N1', 'Gone', 'about to delete', 100, True)])
        na.run_archive(self.db, self.archive)
        self.assertIn('DELETED', list((Path(self.archive) / 'notes').glob('Recipes/*.md'))[0].read_text())


def make_reminders_legacy(path):
    """Legacy (macOS <=12) schema: reminders + lists share ZREMCDOBJECT, with
    title in ZTITLE1, created in ZCREATIONDATE1, list name in ZNAME2."""
    conn = sqlite3.connect(path)
    conn.executescript("""
        DROP TABLE IF EXISTS ZREMCDOBJECT;
        CREATE TABLE ZREMCDOBJECT(Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZNOTES TEXT,
            ZDUEDATE REAL, ZCOMPLETED INTEGER, ZCOMPLETIONDATE REAL, ZFLAGGED INTEGER,
            ZPRIORITY INTEGER, ZCREATIONDATE1 REAL, ZLIST INTEGER, ZNAME2 TEXT);
    """)
    conn.execute("INSERT INTO ZREMCDOBJECT(Z_PK,ZNAME2) VALUES(50,'Packing')")     # a list row
    conn.execute("INSERT INTO ZREMCDOBJECT(Z_PK,ZTITLE1,ZCOMPLETED,ZPRIORITY,ZCREATIONDATE1,ZLIST) "
                 "VALUES(1,'Passport',0,1,700000000.0,50)")
    conn.execute("INSERT INTO ZREMCDOBJECT(Z_PK,ZTITLE1,ZCOMPLETED,ZCREATIONDATE1,ZLIST) "
                 "VALUES(2,'Charger',1,700000000.0,50)")
    conn.commit(); conn.close()


class RemindersTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.store = self.root / 'Stores'; self.store.mkdir()
        self.db = str(self.store / 'Data-1.sqlite')
        self.archive = str(self.root / 'RemArchive')

    def tearDown(self):
        self.tmp.cleanup()

    def _manifest(self):
        p = Path(self.archive) / 'manifest.jsonl'
        return [json.loads(l) for l in p.read_text().splitlines() if l.strip()] if p.exists() else []

    def test_archive_lists_and_status(self):
        make_reminders(self.db, [(10, 'Groceries')],
                       [('Milk', 'whole', 700000050.0, False, False, 1, 10),
                        ('Eggs', '', None, True, False, 0, 10)])
        r = ra.run_archive(str(self.store), self.archive)   # pass the Stores DIR
        self.assertEqual(r['reminders'], 2)
        self.assertEqual(r['lists'], 1)
        md = (Path(self.archive) / 'reminders' / 'Groceries.md').read_text()
        self.assertIn('## Open', md)
        self.assertIn('## Completed', md)
        self.assertIn('[ ] Milk', md)
        self.assertIn('[x] Eggs', md)
        self.assertIn('high', md)                            # priority 1 → High
        h = (Path(self.archive) / 'reminders.html').read_text()
        self.assertIn('Hide completed', h)                   # the toggle
        self.assertIn('<details class="item', h)             # collapsible items
        self.assertIn('hide-done', h)                        # toggle wiring

    def test_versioning_on_completion(self):
        make_reminders(self.db, [(10, 'L')], [('Task', '', None, False, False, 0, 10)])
        ra.run_archive(str(self.store), self.archive)
        make_reminders(self.db, [(10, 'L')], [('Task', '', None, True, False, 0, 10)])
        r = ra.run_archive(str(self.store), self.archive)
        self.assertEqual(r['new_versions'], 1)
        self.assertEqual(len(self._manifest()), 2)
        self.assertIn('[x] Task', (Path(self.archive) / 'reminders' / 'L.md').read_text())

    def test_idempotent(self):
        make_reminders(self.db, [(10, 'L')], [('Task', '', None, False, False, 0, 10)])
        ra.run_archive(str(self.store), self.archive)
        r = ra.run_archive(str(self.store), self.archive)
        self.assertEqual(r['new_versions'], 0)

    def test_legacy_zremcdobject_schema(self):
        # macOS <=12 layout (ZREMCDOBJECT, ZTITLE1, ZNAME2) must work too.
        make_reminders_legacy(self.db)
        r = ra.run_archive(str(self.store), self.archive)
        self.assertEqual(r['reminders'], 2)
        self.assertEqual(r['lists'], 1)
        md = (Path(self.archive) / 'reminders' / 'Packing.md').read_text()
        self.assertIn('[ ] Passport', md)
        self.assertIn('[x] Charger', md)
        self.assertIn('high', md)


if __name__ == '__main__':
    unittest.main(verbosity=2)
