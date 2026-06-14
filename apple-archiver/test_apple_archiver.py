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

import plistlib

import notes_archiver as na
import reminders_archiver as ra
import callhistory_archiver as ca
import voicememos_archiver as va
import safari_archiver as sa
import calendar_archiver as cala
import books_archiver as ba
import podcasts_archiver as pa
import stickies_archiver as sta
import archive_index as ai
import mail_archiver as ma
from email.message import EmailMessage


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
            ZMODIFICATIONDATE1 REAL, ZMODIFICATIONDATE REAL, ZMARKEDFORDELETION INTEGER,
            ZNOTE INTEGER, ZMEDIA INTEGER, ZTYPEUTI TEXT, ZFILENAME TEXT);
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

    def test_note_attachment_linked(self):
        make_notestore(self.db, [('N1', 'Trip', 'trip photos', 100, False)])
        # The note above is Z_PK 201 (pk+200). Add a media object + attachment row.
        conn = sqlite3.connect(self.db)
        conn.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZIDENTIFIER) VALUES(66,'MEDIA-UUID-1')")
        conn.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZNOTE,ZMEDIA,ZTYPEUTI,ZFILENAME) "
                     "VALUES(300,201,66,'public.png','pic.png')")
        conn.commit(); conn.close()
        # Place the media file where the archiver expects it (media/<uuid>/<gen>/file).
        md = Path(self.archive) / 'media' / 'MEDIA-UUID-1' / '1'
        md.mkdir(parents=True)
        (md / 'pic.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'x' * 50)
        r = na.run_archive(self.db, self.archive)
        self.assertEqual(r['media'], 1)
        h = (Path(self.archive) / 'notes.html').read_text()
        self.assertIn('media/MEDIA-UUID-1/1/pic.png', h)
        self.assertIn('<img', h)
        g = next(e for e in self._manifest() if e['id'] == 'N1')
        self.assertEqual(g['attachments'][0]['media'], 'MEDIA-UUID-1')


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


class CallHistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.db = str(self.root / 'CallHistory.storedata')
        self.archive = str(self.root / 'CallsArchive')
        conn = sqlite3.connect(self.db)
        conn.executescript("""
            CREATE TABLE ZCALLRECORD(Z_PK INTEGER PRIMARY KEY, ZADDRESS TEXT, ZNAME TEXT,
                ZORIGINATED INTEGER, ZCALLTYPE INTEGER, ZANSWERED INTEGER,
                ZDURATION REAL, ZDATE REAL, ZSERVICE_PROVIDER TEXT);
        """)
        conn.execute("INSERT INTO ZCALLRECORD VALUES(1,'+15551112222','Mom',1,1,1,65.0,700000000.0,'AT&T')")
        conn.execute("INSERT INTO ZCALLRECORD VALUES(2,'+15553334444',NULL,0,1,0,0,700000100.0,NULL)")
        conn.commit(); conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_calls(self):
        r = ca.run_archive(self.db, self.archive)
        self.assertEqual(r['calls'], 2)
        h = (Path(self.archive) / 'calls.html').read_text()
        self.assertIn('Mom', h)
        self.assertIn('missed', h)                  # incoming + unanswered
        self.assertTrue((Path(self.archive) / 'calls.csv').exists())

    def test_idempotent(self):
        ca.run_archive(self.db, self.archive)
        self.assertEqual(ca.run_archive(self.db, self.archive)['new'], 0)

    def test_encrypted_address_blob(self):
        # macOS <=12 stores ZADDRESS as an encrypted blob — must not dump raw bytes.
        conn = sqlite3.connect(self.db)
        conn.execute("INSERT INTO ZCALLRECORD VALUES(3,?,NULL,0,1,1,30.0,700000200.0,NULL)",
                     (b'\xb4\x0a#\x07\xef\xfd\xa5\xfe\xc9',))
        conn.commit(); conn.close()
        ca.run_archive(self.db, self.archive)
        csv = (Path(self.archive) / 'calls.csv').read_text()
        self.assertNotIn("\\x", csv)              # no raw byte escapes leaked
        self.assertIn('(encrypted)', csv)

    def test_decrypted_sidecar_upgrades_encrypted_call(self):
        # An encrypted call, then a GUI-helper sidecar recovers its number: the
        # SAME call is upgraded (latest version wins), not duplicated.
        conn = sqlite3.connect(self.db)
        conn.execute("INSERT INTO ZCALLRECORD VALUES(3,?,NULL,0,1,1,30.0,700000200.0,NULL)",
                     (b'\xb4\x0a#\x07\xef\xfd\xa5\xfe\xc9',))
        conn.commit(); conn.close()
        ca.run_archive(self.db, self.archive)
        self.assertEqual(ca.run_archive(self.db, self.archive)['calls'], 3)

        epoch = 700000200.0 + ca.CORE_DATA_EPOCH          # timezone-proof match key
        side = Path(self.archive) / 'calls_decrypted.json'
        side.write_text(json.dumps({'calls': [
            {'epoch': epoch, 'address': '+15559998888'}]}))
        r = ca.run_archive(self.db, self.archive, decrypted_path=str(side))
        self.assertEqual(r['new'], 1)                      # one upgraded version appended
        self.assertEqual(r['calls'], 3)                    # not duplicated
        csv = (Path(self.archive) / 'calls.csv').read_text()
        self.assertIn('+15559998888', csv)                # recovered number shown
        self.assertNotIn('(encrypted)', csv)              # the encrypted call was upgraded
        self.assertEqual(len(csv.strip().splitlines()), 1 + 3)   # header + 3 calls, no dup row


class VoiceMemosTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.archive = self.root / 'VMArchive'
        (self.archive / 'recordings').mkdir(parents=True)
        for fn in ('20260126 134059-AAAA.m4a', '20250715 235247-BBBB.m4a'):
            (self.archive / 'recordings' / fn).write_bytes(b'\x00\x00\x00\x20ftypM4A ')

    def tearDown(self):
        self.tmp.cleanup()

    def test_file_driven(self):
        r = va.run_archive(None, str(self.archive))     # no DB → files drive it
        self.assertEqual(r['memos'], 2)
        h = (Path(self.archive) / 'voicememos.html').read_text()
        self.assertEqual(h.count('<audio'), 2)
        self.assertIn('2026-01-26 13:40', h)            # date parsed from filename


class SafariTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.sdir = self.root / 'Safari'; self.sdir.mkdir()
        self.archive = str(self.root / 'SafariArchive')
        conn = sqlite3.connect(str(self.sdir / 'History.db'))
        conn.executescript("""
            CREATE TABLE history_items(id INTEGER PRIMARY KEY, url TEXT);
            CREATE TABLE history_visits(id INTEGER PRIMARY KEY, history_item INTEGER,
                title TEXT, visit_time REAL);
        """)
        conn.execute("INSERT INTO history_items VALUES(1,'https://example.com')")
        conn.execute("INSERT INTO history_visits VALUES(1,1,'Example',700000000.0)")
        conn.commit(); conn.close()
        # A Bookmarks.plist with one bookmark + one reading-list item.
        bm = {'WebBookmarkType': 'WebBookmarkTypeLeaf', 'URLString': 'https://bm.com',
              'URIDictionary': {'title': 'My Bookmark'}}
        rl = {'WebBookmarkType': 'WebBookmarkTypeLeaf', 'URLString': 'https://read.com',
              'URIDictionary': {'title': 'Read Later'}, 'ReadingList': {'DateAdded': '2026-01-01'}}
        root = {'WebBookmarkType': 'WebBookmarkTypeList', 'Title': '', 'Children': [
            {'WebBookmarkType': 'WebBookmarkTypeList', 'Title': 'Favorites', 'Children': [bm]},
            {'WebBookmarkType': 'WebBookmarkTypeList', 'Title': 'com.apple.ReadingList', 'Children': [rl]},
        ]}
        with open(self.sdir / 'Bookmarks.plist', 'wb') as fh:
            plistlib.dump(root, fh)

    def tearDown(self):
        self.tmp.cleanup()

    def test_history_bookmarks_readinglist(self):
        r = sa.run_archive(str(self.sdir), self.archive)
        self.assertEqual(r['visits'], 1)
        self.assertEqual(r['bookmarks'], 1)
        self.assertEqual(r['readinglist'], 1)
        self.assertIn('Example', (Path(self.archive) / 'history.html').read_text())
        self.assertIn('My Bookmark', (Path(self.archive) / 'bookmarks.html').read_text())
        self.assertIn('Read Later', (Path(self.archive) / 'readinglist.html').read_text())

    def test_idempotent(self):
        sa.run_archive(str(self.sdir), self.archive)
        self.assertEqual(sa.run_archive(str(self.sdir), self.archive)['new'], 0)


class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.db = str(self.root / 'Calendar.sqlitedb')
        self.archive = str(self.root / 'CalArchive')
        conn = sqlite3.connect(self.db)
        conn.executescript("""
            CREATE TABLE Calendar(ROWID INTEGER PRIMARY KEY, title TEXT);
            CREATE TABLE Location(ROWID INTEGER PRIMARY KEY, title TEXT, address TEXT);
            CREATE TABLE CalendarItem(ROWID INTEGER PRIMARY KEY, summary TEXT, description TEXT,
                start_date REAL, end_date REAL, all_day INTEGER, calendar_id INTEGER,
                location_id INTEGER);
        """)
        conn.execute("INSERT INTO Calendar VALUES(1,'Family')")
        conn.execute("INSERT INTO Location VALUES(1,'Home','1 Main St')")
        conn.execute("INSERT INTO CalendarItem VALUES(1,'Dentist','cleaning',700000000.0,700003600.0,0,1,1)")
        conn.execute("INSERT INTO CalendarItem VALUES(2,'Holiday',NULL,700100000.0,700186400.0,1,1,NULL)")
        conn.commit(); conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_events_and_ics(self):
        r = cala.run_archive(self.db, self.archive)
        self.assertEqual(r['events'], 2)
        self.assertEqual(r['calendars'], 1)
        ics = (Path(self.archive) / 'ics' / 'Family.ics').read_text()
        self.assertIn('BEGIN:VEVENT', ics)
        self.assertIn('SUMMARY:Dentist', ics)
        self.assertIn('VALUE=DATE:', ics)          # the all-day event
        self.assertIn('LOCATION:Home', ics)
        self.assertTrue((Path(self.archive) / 'calendar.html').exists())

    def test_idempotent(self):
        cala.run_archive(self.db, self.archive)
        self.assertEqual(cala.run_archive(self.db, self.archive)['new'], 0)

    def test_legacy_zcalendaritem(self):
        # macOS <=12 'Calendar Cache' Core Data schema.
        db2 = str(self.root / 'Calendar Cache')
        conn = sqlite3.connect(db2)
        conn.executescript("""
            CREATE TABLE ZCALENDARITEM(Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT, ZNOTES TEXT,
                ZSTARTDATE REAL, ZENDDATE REAL, ZISALLDAY INTEGER, ZCALENDAR INTEGER,
                ZSTRUCTUREDLOCATION INTEGER);
        """)
        conn.execute("INSERT INTO ZCALENDARITEM(Z_PK,ZTITLE,ZSTARTDATE,ZENDDATE,ZISALLDAY) "
                     "VALUES(1,'Soccer practice',700000000.0,700003600.0,0)")
        conn.commit(); conn.close()
        r = cala.run_archive(db2, str(self.root / 'CalArchive2'))
        self.assertEqual(r['events'], 1)
        self.assertIn('Soccer practice',
                      (Path(self.root / 'CalArchive2') / 'calendar.html').read_text())


class BooksTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.docs = self.root / 'Documents'
        (self.docs / 'BKLibrary').mkdir(parents=True)
        (self.docs / 'AEAnnotation').mkdir(parents=True)
        self.archive = str(self.root / 'BooksArchive')
        lib = sqlite3.connect(str(self.docs / 'BKLibrary' / 'BKLibrary-1.sqlite'))
        lib.executescript("CREATE TABLE ZBKLIBRARYASSET(Z_PK INTEGER PRIMARY KEY, "
                          "ZASSETID TEXT, ZTITLE TEXT, ZAUTHOR TEXT);")
        lib.execute("INSERT INTO ZBKLIBRARYASSET VALUES(1,'ASSET1','Dune','Frank Herbert')")
        lib.commit(); lib.close()
        an = sqlite3.connect(str(self.docs / 'AEAnnotation' / 'AEAnnotation-1.sqlite'))
        an.executescript("CREATE TABLE ZAEANNOTATION(Z_PK INTEGER PRIMARY KEY, ZANNOTATIONASSETID TEXT, "
                         "ZANNOTATIONSELECTEDTEXT TEXT, ZANNOTATIONNOTE TEXT, ZANNOTATIONLOCATION TEXT, "
                         "ZANNOTATIONCREATIONDATE REAL, ZANNOTATIONSTYLE INTEGER, ZANNOTATIONDELETED INTEGER);")
        an.execute("INSERT INTO ZAEANNOTATION VALUES(1,'ASSET1','Fear is the mind-killer','remember this','epubcfi(/6)',700000000.0,3,0)")
        an.execute("INSERT INTO ZAEANNOTATION VALUES(2,'ASSET1','deleted highlight',NULL,'epubcfi(/7)',700000001.0,1,1)")
        an.commit(); an.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_highlights(self):
        r = ba.run_archive(str(self.docs), self.archive)
        self.assertEqual(r['highlights'], 1)        # the deleted one is excluded
        self.assertEqual(r['books'], 1)
        md = (Path(self.archive) / 'books' / 'Dune.md').read_text()
        self.assertIn('Fear is the mind-killer', md)
        self.assertIn('remember this', md)
        h = (Path(self.archive) / 'books.html').read_text()
        self.assertIn('Frank Herbert', h)

    def test_idempotent(self):
        ba.run_archive(str(self.docs), self.archive)
        self.assertEqual(ba.run_archive(str(self.docs), self.archive)['new'], 0)


class PodcastsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.db = str(self.root / 'MTLibrary.sqlite')
        self.archive = str(self.root / 'PodArchive')
        conn = sqlite3.connect(self.db)
        conn.executescript("""
            CREATE TABLE ZMTPODCAST(Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT, ZAUTHOR TEXT,
                ZFEEDURL TEXT, ZWEBPAGEURL TEXT, ZCATEGORY TEXT, ZSUBSCRIBED INTEGER);
            CREATE TABLE ZMTEPISODE(Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZTITLE TEXT);
        """)
        conn.execute("INSERT INTO ZMTPODCAST VALUES(1,'Security Now','TWiT','http://feed','http://web','Tech',1)")
        conn.execute("INSERT INTO ZMTEPISODE VALUES(1,1,'Ep1')")
        conn.execute("INSERT INTO ZMTEPISODE VALUES(2,1,'Ep2')")
        conn.commit(); conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_podcasts(self):
        r = pa.run_archive(self.db, self.archive)
        self.assertEqual(r['podcasts'], 1)
        idx = (Path(self.archive) / '_index.csv').read_text()
        self.assertIn('Security Now', idx)
        self.assertIn('2', idx)                     # episode count
        self.assertIn('Security Now', (Path(self.archive) / 'podcasts.html').read_text())

    def test_idempotent(self):
        pa.run_archive(self.db, self.archive)
        self.assertEqual(pa.run_archive(self.db, self.archive)['new'], 0)


class StickiesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.data = self.root / 'Stickies'; self.data.mkdir()
        self.archive = str(self.root / 'StkArchive')
        d = self.data / 'AAAA-BBBB.rtfd'; d.mkdir()
        (d / 'TXT.rtf').write_text(
            r'{\rtf1\ansi\ansicpg1252 Grocery list\par milk and eggs}', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def test_stickies(self):
        r = sta.run_archive(str(self.data), self.archive)
        self.assertEqual(r['stickies'], 1)
        txt = '\n'.join(p.read_text() for p in (Path(self.archive) / 'notes').glob('*.txt'))
        self.assertIn('Grocery list', txt)
        self.assertIn('milk and eggs', txt)

    def test_idempotent(self):
        sta.run_archive(str(self.data), self.archive)
        self.assertEqual(sta.run_archive(str(self.data), self.archive)['new'], 0)


class ArchiveIndexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.dl = Path(self.tmp.name)
        (self.dl / 'RachelNotesArchive').mkdir()
        (self.dl / 'RachelNotesArchive' / 'notes.html').write_text('<html>notes</html>')
        (self.dl / 'RachelNotesArchive' / '_index.csv').write_text('title\nA\nB\n')
        (self.dl / 'RachelCallsArchive').mkdir()
        (self.dl / 'RachelCallsArchive' / 'calls.html').write_text('<html>calls</html>')
        (self.dl / 'RachelCallsArchive' / 'calls.csv').write_text('date\nx\n')
        # An unrelated folder must be ignored.
        (self.dl / 'SomethingElse').mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_landing_page(self):
        out = str(self.dl / 'Rachel-Archives.html')
        n = ai.build('Rachel', str(self.dl), out)
        self.assertEqual(n, 2)                       # only the two real archive folders
        doc = Path(out).read_text()
        self.assertIn('Notes', doc)
        self.assertIn('Call history', doc)
        self.assertIn('RachelNotesArchive/notes.html', doc)
        self.assertIn('2 items', doc)                # _index.csv minus header
        self.assertNotIn('SomethingElse', doc)


class MailTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.store = self.root / 'V9'
        self.archive = str(self.root / 'MailArchive')
        acct = self.store / 'AE14B604-ACCT' / 'INBOX.mbox' / 'MBX-UUID' / 'Data'
        msgs = acct / 'Messages'; msgs.mkdir(parents=True)

        # (1) Full .emlx with an inline attachment.
        m = EmailMessage()
        m['From'] = 'Alice <alice@example.com>'; m['To'] = 'rachel@me.com'
        m['Subject'] = 'Hello there'; m['Date'] = 'Sat, 13 Jun 2026 12:30:00 -0700'
        m['Message-ID'] = '<abc@example.com>'
        m.set_content('This is the body text.')
        m.add_attachment(b'\x89PNGDATA', maintype='image', subtype='png', filename='pic.png')
        (msgs / '1.emlx').write_bytes(self._emlx(m.as_bytes()))

        # (2) .partial.emlx whose attachment lives in the sibling Attachments tree.
        p = EmailMessage()
        p['From'] = 'Bob <bob@example.com>'; p['To'] = 'rachel@me.com'
        p['Subject'] = 'Wedding info'; p['Date'] = 'Sun, 14 Jun 2026 09:00:00 -0700'
        p['Message-ID'] = '<def@example.com>'
        p.set_content('See attached PDF.')
        (msgs / '2.partial.emlx').write_bytes(self._emlx(p.as_bytes()))
        att = acct / 'Attachments' / '2' / '2'; att.mkdir(parents=True)
        (att / 'report.pdf').write_bytes(b'%PDF-1.4 fake')

        # (3) Two attachments with the SAME filename — must not clobber each other.
        d = EmailMessage()
        d['From'] = 'Carol <carol@example.com>'; d['To'] = 'rachel@me.com'
        d['Subject'] = 'Two photos'; d['Date'] = 'Mon, 15 Jun 2026 10:00:00 -0700'
        d['Message-ID'] = '<ghi@example.com>'
        d.set_content('Two same-named pics.')
        d.add_attachment(b'AAA', maintype='image', subtype='jpeg', filename='photo.jpg')
        d.add_attachment(b'BBB', maintype='image', subtype='jpeg', filename='photo.jpg')
        (msgs / '3.emlx').write_bytes(self._emlx(d.as_bytes()))

        # (4) An HTML email shipping a full document (head/style/body) — must be
        # cleaned so its global CSS can't leak into our page (the blank-space bug).
        e = EmailMessage()
        e['From'] = 'News <news@example.com>'; e['To'] = 'rachel@me.com'
        e['Subject'] = 'Newsletter'; e['Date'] = 'Tue, 16 Jun 2026 08:00:00 -0700'
        e['Message-ID'] = '<jkl@example.com>'
        e.set_content('plain fallback')
        e.add_alternative(
            '<html><head><style>body{min-height:3000px;margin:200px}</style></head>'
            '<body><p>Real newsletter content here.</p></body></html>', subtype='html')
        (msgs / '4.emlx').write_bytes(self._emlx(e.as_bytes()))

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def _emlx(msg_bytes):
        return (str(len(msg_bytes)).encode() + b'\n' + msg_bytes +
                b'<?xml version="1.0"?><plist></plist>')

    def test_archive(self):
        r = ma.run_archive(str(self.store), self.archive)
        self.assertEqual(r['messages'], 4)
        self.assertEqual(r['failed'], 0)
        self.assertEqual(r['attachments'], 4)        # pic.png + report.pdf + 2× photo.jpg
        doc = (Path(self.archive) / 'mail.html').read_text()
        self.assertIn('Hello there', doc)
        self.assertIn('Wedding info', doc)

    def test_html_body_is_cleaned(self):
        # The HTML email's global <style>/<body> wrappers must be stripped so they
        # can't leak CSS (min-height/margin) and create blank space; content stays.
        ma.run_archive(str(self.store), self.archive)
        page = next(p for p in (Path(self.archive) / 'messages').rglob('*.html')
                    if 'Newsletter' in p.read_text())
        body = page.read_text()
        marker = body.split('class="htmlbody"', 1)[1]
        self.assertNotIn('min-height:3000px', marker)   # leaked global rule gone
        self.assertNotIn('<body', marker.split('</div>')[0])
        self.assertIn('Real newsletter content here.', marker)

    def test_index_has_attachment_filter(self):
        ma.run_archive(str(self.store), self.archive)
        doc = (Path(self.archive) / 'mail.html').read_text()
        self.assertIn('data-cls="has-att"', doc)        # the filter checkbox
        self.assertIn('class="item has-att"', doc)      # at least one tagged card
        self.assertIn('With attachments only', doc)

    def test_same_named_attachments_not_clobbered(self):
        ma.run_archive(str(self.store), self.archive)
        jpgs = sorted(p.name for p in (Path(self.archive) / 'attachments').rglob('*.jpg'))
        self.assertEqual(jpgs, ['photo-2.jpg', 'photo.jpg'])   # both survived, de-duped
        # Re-importable .eml exported + attachments extracted.
        self.assertTrue(list((Path(self.archive) / 'messages').rglob('*.eml')))
        self.assertTrue(list((Path(self.archive) / 'attachments').rglob('pic.png')))
        self.assertTrue(list((Path(self.archive) / 'attachments').rglob('report.pdf')))

    def test_idempotent(self):
        ma.run_archive(str(self.store), self.archive)
        self.assertEqual(ma.run_archive(str(self.store), self.archive)['new'], 0)

    def test_eml_reimportable(self):
        ma.run_archive(str(self.store), self.archive)
        eml = next(iter((Path(self.archive) / 'messages').rglob('*.eml')))
        reparsed = ma.email.message_from_bytes(eml.read_bytes())
        self.assertIn('example.com', reparsed['From'])

    def test_partial_attachment_rejoined(self):
        # The .partial.emlx body carries no payload; the file must come from disk.
        ma.run_archive(str(self.store), self.archive)
        pdf = next(iter((Path(self.archive) / 'attachments').rglob('report.pdf')))
        self.assertEqual(pdf.read_bytes(), b'%PDF-1.4 fake')


if __name__ == '__main__':
    unittest.main(verbosity=2)
