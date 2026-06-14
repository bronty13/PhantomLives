#!/usr/bin/env python3
"""Tests for archive_messages.py — append-only, human-browsable Messages archiver.

Builds a tiny synthetic chat.db (+ a synthetic AddressBook) and verifies:
all-chats enumeration, GUID-dedup idempotency, the incremental watermark,
attributedBody decode (reused get_body), attachment path mapping + per-convo
media COPIES, contact-name resolution, and the derived views (transcript.txt,
index.html, _index.csv). Standard library only.

Run:  python3 test_archive_messages.py
"""
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

import archive_messages as am

T1 = 700000000000000000
T2 = 700000001000000000
T4 = 700000003000000000

CHATS = {
    1: ('iMessage;-;+15551112222', '+15551112222', None),       # 1:1
    2: ('iMessage;+;chat999', 'chat999', 'Family Group'),       # group
}


def make_db(path):
    ab = b'\x00NSString\x01\x94\x84\x01+' + bytes([5]) + b'hello'   # decodes to "hello"
    msgs = [
        {'rowid': 1, 'guid': 'G1', 'date': T1, 'is_from_me': 0,
         'text': 'first message', 'handle': '+15551112222', 'chat_id': 1},
        {'rowid': 2, 'guid': 'G2', 'date': T2, 'is_from_me': 1,
         'text': '', 'ab': ab, 'chat_id': 1,
         'attachments': [('~/Library/Messages/Attachments/ab/12/GUID/IMG_1.HEIC',
                          'image/heic', 'IMG_1.HEIC')]},
        {'rowid': 3, 'guid': 'G3', 'date': T2, 'is_from_me': 0,
         'text': 'group hi', 'handle': '+15553334444', 'chat_id': 2},
    ]
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
    for cid, (guid, ident, disp) in CHATS.items():
        conn.execute('INSERT INTO chat(ROWID,guid,chat_identifier,display_name) VALUES(?,?,?,?)',
                     (cid, guid, ident, disp))
    handles, att = {}, 0
    for m in msgs:
        hid = None
        if m.get('handle'):
            hid = handles.setdefault(m['handle'], len(handles) + 1)
            conn.execute('INSERT OR IGNORE INTO handle(ROWID,id) VALUES(?,?)', (hid, m['handle']))
        conn.execute('INSERT INTO message(ROWID,guid,date,is_from_me,text,attributedBody,handle_id) '
                     'VALUES(?,?,?,?,?,?,?)', (m['rowid'], m['guid'], m['date'], m['is_from_me'],
                                              m.get('text'), m.get('ab'), hid))
        conn.execute('INSERT INTO chat_message_join(chat_id,message_id) VALUES(?,?)',
                     (m['chat_id'], m['rowid']))
        for (fname, mime, xfer) in m.get('attachments', []):
            att += 1
            conn.execute('INSERT INTO attachment(ROWID,filename,mime_type,transfer_name) '
                         'VALUES(?,?,?,?)', (att, fname, mime, xfer))
            conn.execute('INSERT INTO message_attachment_join(message_id,attachment_id) '
                         'VALUES(?,?)', (m['rowid'], att))
    conn.commit()
    conn.close()


def make_addressbook(sources_dir):
    """Synthetic AddressBook (realistic schema) with one rich contact for
    +15551112222: name parts, phone, email, postal address, birthday, note, photo."""
    d = Path(sources_dir) / 'SRC1'
    d.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(d / 'AddressBook-v22.abcddb'))
    conn.executescript("""
        CREATE TABLE ZABCDRECORD(Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT, ZFIRSTNAME TEXT,
            ZMIDDLENAME TEXT, ZLASTNAME TEXT, ZSUFFIX TEXT, ZMAIDENNAME TEXT,
            ZNICKNAME TEXT, ZPHONETICFIRSTNAME TEXT, ZPHONETICLASTNAME TEXT,
            ZORGANIZATION TEXT, ZDEPARTMENT TEXT, ZJOBTITLE TEXT, ZBIRTHDAY REAL,
            ZBIRTHDAYYEARLESS REAL, ZNOTE TEXT, ZCREATIONDATE REAL,
            ZMODIFICATIONDATE REAL, ZIMAGEDATA BLOB);
        CREATE TABLE ZABCDPHONENUMBER(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZLABEL TEXT, ZFULLNUMBER TEXT);
        CREATE TABLE ZABCDEMAILADDRESS(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZLABEL TEXT, ZADDRESS TEXT);
        CREATE TABLE ZABCDPOSTALADDRESS(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZLABEL TEXT,
            ZSTREET TEXT, ZCITY TEXT, ZSTATE TEXT, ZZIPCODE TEXT, ZCOUNTRYNAME TEXT);
        CREATE TABLE ZABCDURLADDRESS(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZLABEL TEXT, ZURL TEXT);
        CREATE TABLE ZABCDSOCIALPROFILE(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER,
            ZSERVICENAME TEXT, ZUSERNAME TEXT, ZURLSTRING TEXT);
        CREATE TABLE ZABCDMESSAGINGADDRESS(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZSERVICE TEXT, ZADDRESS TEXT);
        CREATE TABLE ZABCDRELATEDNAME(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZLABEL TEXT, ZNAME TEXT);
        CREATE TABLE ZABCDCONTACTDATE(Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZLABEL TEXT,
            ZDATE REAL, ZDATEYEARLESS REAL);
        CREATE TABLE ZABCDNOTE(Z_PK INTEGER PRIMARY KEY, ZCONTACT INTEGER, ZTEXT TEXT);
    """)
    conn.execute('INSERT INTO ZABCDRECORD(Z_PK,ZFIRSTNAME,ZLASTNAME,ZNICKNAME,'
                 'ZORGANIZATION,ZJOBTITLE,ZBIRTHDAY,ZIMAGEDATA) VALUES(1,?,?,?,?,?,?,?)',
                 ('Test', 'Person', 'Testy', 'Acme Inc', 'Engineer', 500000000.0,
                  b'\xff\xd8fakejpegphoto'))
    conn.execute("INSERT INTO ZABCDPHONENUMBER VALUES(1,1,'_$!<Mobile>!$_',?)", ('+1 (555) 111-2222',))
    conn.execute("INSERT INTO ZABCDEMAILADDRESS VALUES(1,1,'_$!<Home>!$_',?)", ('test@example.com',))
    conn.execute("INSERT INTO ZABCDPOSTALADDRESS VALUES(1,1,'_$!<Home>!$_','1 Main St','Buffalo','NY','14201','USA')")
    conn.execute("INSERT INTO ZABCDNOTE VALUES(1,1,'a note about Test')")
    conn.commit()
    conn.close()


class ArchiveMessagesTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = str(self.root / 'chat.db')
        self.archive = str(self.root / 'Archive')
        make_db(self.db)
        # Pre-place the raw attachment byte so per-convo media COPY happens.
        src = Path(self.archive) / 'attachments' / 'ab' / '12' / 'GUID' / 'IMG_1.HEIC'
        src.parent.mkdir(parents=True, exist_ok=True)
        src.write_bytes(b'\xff\xd8fakejpegbytes')

    def tearDown(self):
        self.tmp.cleanup()

    def _manifest(self):
        p = Path(self.archive) / 'manifest.jsonl'
        return [json.loads(l) for l in p.read_text().splitlines() if l.strip()] if p.exists() else []

    def test_backfill_all_chats(self):
        r = am.run_archive(self.db, self.archive, full=True)
        self.assertEqual(r['appended'], 3)
        self.assertEqual(r['conversations'], 2)
        self.assertEqual(len(self._manifest()), 3)
        convs = list((Path(self.archive) / 'conversations').glob('*/transcript.txt'))
        self.assertEqual(len(convs), 2)
        # HTML + CSV index generated.
        self.assertTrue(list((Path(self.archive) / 'conversations').glob('*/index.html')))
        self.assertTrue((Path(self.archive) / '_index.csv').exists())

    def test_attributedbody_decoded(self):
        am.run_archive(self.db, self.archive, full=True)
        g2 = next(e for e in self._manifest() if e['guid'] == 'G2')
        self.assertEqual(g2['text'], 'hello')
        self.assertEqual(g2['from_me'], 1)

    def test_attachment_path_mapping(self):
        am.run_archive(self.db, self.archive, full=True)
        g2 = next(e for e in self._manifest() if e['guid'] == 'G2')
        at = g2['attachments'][0]
        self.assertEqual(at['kind'], 'photo')
        self.assertEqual(at['path'], 'attachments/ab/12/GUID/IMG_1.HEIC')

    def test_media_copied_into_conversation(self):
        r = am.run_archive(self.db, self.archive, full=True)
        self.assertGreaterEqual(r['media_copied'], 1)
        copies = list((Path(self.archive) / 'conversations').glob('*/media/*_IMG_1.HEIC'))
        self.assertEqual(len(copies), 1)

    def test_contact_name_resolution(self):
        make_addressbook(self.root / 'AB')
        am.run_archive(self.db, self.archive, addressbook_dir=str(self.root / 'AB'), full=True)
        index = (Path(self.archive) / '_index.csv').read_text()
        self.assertIn('Test Person', index)                       # name in the index
        # The 1:1 conversation folder is named after the contact, not the number.
        self.assertTrue(list((Path(self.archive) / 'conversations').glob('Test Person__*')))
        # Transcript shows the resolved name.
        tx = '\n'.join(p.read_text() for p in
                       (Path(self.archive) / 'conversations').glob('Test Person__*/transcript.txt'))
        self.assertIn('Test Person:', tx)

    def test_contacts_html(self):
        make_addressbook(self.root / 'AB')
        am.run_archive(self.db, self.archive, addressbook_dir=str(self.root / 'AB'), full=True)
        ch = Path(self.archive) / 'contacts.html'
        self.assertTrue(ch.exists())
        doc = ch.read_text()
        self.assertIn('Test Person', doc)
        self.assertIn('Filter contacts', doc)            # the search box
        self.assertIn('→ conversation', doc)             # linked to their thread
        self.assertIn('Buffalo', doc)                    # postal address mapped
        self.assertIn('a note about Test', doc)          # note mapped

    def test_contacts_json_all_fields(self):
        make_addressbook(self.root / 'AB')
        am.run_archive(self.db, self.archive, addressbook_dir=str(self.root / 'AB'), full=True)
        recs = json.loads((Path(self.archive) / 'contacts.json').read_text())
        r = next(x for x in recs if x['name'] == 'Test Person')
        self.assertEqual(r['org'], 'Acme Inc')
        self.assertEqual(r['title'], 'Engineer')
        self.assertEqual(r['nickname'], 'Testy')
        self.assertEqual(r['phones'][0]['label'], 'Mobile')        # label unwrapped
        self.assertEqual(r['emails'][0]['value'], 'test@example.com')
        self.assertEqual(r['addresses'][0]['city'], 'Buffalo')
        self.assertTrue(r['birthday'])                              # core-data date parsed
        self.assertEqual(r['note'], 'a note about Test')
        self.assertTrue(r['photo'])                                 # photo exported + linked

    def test_contact_photo_exported(self):
        make_addressbook(self.root / 'AB')
        am.run_archive(self.db, self.archive, addressbook_dir=str(self.root / 'AB'), full=True)
        photos = list((Path(self.archive) / 'contacts' / 'photos').glob('*.jpg'))
        self.assertEqual(len(photos), 1)
        self.assertEqual(photos[0].read_bytes(), b'\xff\xd8fakejpegphoto')

    def test_idempotent_rerun(self):
        am.run_archive(self.db, self.archive, full=True)
        r2 = am.run_archive(self.db, self.archive)
        self.assertEqual(r2['appended'], 0)
        self.assertEqual(len(self._manifest()), 3)
        r3 = am.run_archive(self.db, self.archive, full=True)
        self.assertEqual(r3['appended'], 0)
        self.assertEqual(len(self._manifest()), 3)

    def test_incremental_watermark(self):
        am.run_archive(self.db, self.archive, full=True)
        conn = sqlite3.connect(self.db)
        conn.execute('INSERT INTO message(ROWID,guid,date,is_from_me,text,handle_id) '
                     'VALUES(?,?,?,?,?,?)', (4, 'G4', T4, 0, 'later message', 1))
        conn.execute('INSERT INTO chat_message_join(chat_id,message_id) VALUES(?,?)', (1, 4))
        conn.commit(); conn.close()
        r = am.run_archive(self.db, self.archive)
        self.assertEqual(r['appended'], 1)
        self.assertEqual(len(self._manifest()), 4)

    def test_imessage_and_sms_merge_into_one_folder(self):
        # A second 1:1 chat with the SAME handle but a different GUID (iMessage
        # vs SMS) must MERGE into one conversation folder, not collide/overwrite.
        conn = sqlite3.connect(self.db)
        conn.execute("INSERT INTO chat(ROWID,guid,chat_identifier,display_name) "
                     "VALUES(3,'SMS;-;+15551112222','+15551112222',NULL)")
        conn.execute('INSERT INTO message(ROWID,guid,date,is_from_me,text,handle_id) '
                     "VALUES(5,'G5',?,0,'sms msg',1)", (T4,))
        conn.execute('INSERT INTO chat_message_join(chat_id,message_id) VALUES(3,5)')
        conn.commit(); conn.close()
        am.run_archive(self.db, self.archive, full=True)
        # Exactly one folder holds BOTH the iMessage and the SMS text.
        hits = [p for p in (Path(self.archive) / 'conversations').glob('*/transcript.txt')
                if 'first message' in p.read_text() and 'sms msg' in p.read_text()]
        self.assertEqual(len(hits), 1)

    def test_html_has_text(self):
        am.run_archive(self.db, self.archive, full=True)
        htmls = '\n'.join(p.read_text() for p in
                          (Path(self.archive) / 'conversations').glob('*/index.html'))
        self.assertIn('first message', htmls)
        self.assertIn('hello', htmls)


if __name__ == '__main__':
    unittest.main(verbosity=2)
