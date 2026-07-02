#!/usr/bin/env python3
"""Emit shell variable assignments for one external source from external-sources.json.

Usage:  eval "$(python3 source-vars.py <source-id>)"
Exit 2 if the id is unknown. Also supports: source-vars.py --list  (prints enabled ids).
"""
import json
import os
import shlex
import sys
from pathlib import Path

CONFIG = Path(__file__).resolve().parent / 'external-sources.json'


def load():
    return json.loads(CONFIG.read_text(encoding='utf-8')).get('sources', [])


def expand(p):
    return os.path.expanduser(p) if p else ''


def main():
    args = sys.argv[1:]
    if args and args[0] == '--list':
        for s in load():
            if s.get('enabled', True):
                print(s['id'])
        return
    if not args:
        sys.stderr.write('usage: source-vars.py <source-id> | --list\n'); sys.exit(2)
    sid = args[0]
    src = next((s for s in load() if s.get('id') == sid), None)
    if not src:
        sys.stderr.write(f'unknown source id: {sid}\n'); sys.exit(2)
    ph = src.get('photos', {}) or {}
    msg = src.get('messages', {}) or {}
    notes = src.get('notes', {}) or {}
    rem = src.get('reminders', {}) or {}
    safari = src.get('safari', {}) or {}
    vm = src.get('voicememos', {}) or {}
    calls = src.get('calls', {}) or {}
    calendar = src.get('calendar', {}) or {}
    books = src.get('books', {}) or {}
    podcasts = src.get('podcasts', {}) or {}
    stickies = src.get('stickies', {}) or {}
    mail = src.get('mail', {}) or {}
    out = {
        'SRC_ID': src.get('id', ''),
        'SRC_NAME': src.get('name', src.get('id', '')),
        'SRC_ARCHIVE_BASE': src.get('archiveBase', ''),
        'SRC_ENABLED': '1' if src.get('enabled', True) else '0',
        'SRC_HOST': src.get('host', ''),
        'SRC_USER': src.get('user', ''),
        'SRC_KEY': expand(src.get('identityFile', '')),
        'SRC_PHOTOS_ENABLED': '1' if ph.get('enabled', True) else '0',
        'SRC_REMOTE_LIBRARY': ph.get('remoteLibrary', ''),
        'SRC_REMOTE_EXPORT_ROOT': ph.get('remoteExportRoot', ''),
        'SRC_OSXPHOTOS_BIN': ph.get('osxphotosBin', ''),
        'SRC_PHOTOS_REVIEW_BASE': ph.get('reviewBase', ''),
        'SRC_PHOTOS_WINDOW_DAYS': str(int(ph.get('windowDays', 0) or 0)),
        'SRC_MESSAGES_ENABLED': '1' if msg.get('enabled', True) else '0',
        'SRC_NOTES_ENABLED': '1' if notes.get('enabled', False) else '0',
        'SRC_REMINDERS_ENABLED': '1' if rem.get('enabled', False) else '0',
        'SRC_SAFARI_ENABLED': '1' if safari.get('enabled', False) else '0',
        'SRC_VOICEMEMOS_ENABLED': '1' if vm.get('enabled', False) else '0',
        'SRC_CALLS_ENABLED': '1' if calls.get('enabled', False) else '0',
        'SRC_CALLS_DECRYPT_ENABLED': '1' if calls.get('decrypt', False) else '0',
        'SRC_CALENDAR_ENABLED': '1' if calendar.get('enabled', False) else '0',
        'SRC_BOOKS_ENABLED': '1' if books.get('enabled', False) else '0',
        'SRC_PODCASTS_ENABLED': '1' if podcasts.get('enabled', False) else '0',
        'SRC_STICKIES_ENABLED': '1' if stickies.get('enabled', False) else '0',
        'SRC_MAIL_ENABLED': '1' if mail.get('enabled', False) else '0',
    }
    for k, v in out.items():
        print(f'{k}={shlex.quote(str(v))}')


if __name__ == '__main__':
    main()
