#!/usr/bin/env python3
# =============================================================================
#   APPLE REMINDERS ARCHIVER
#   File:     reminders_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only, browsable archive of Apple Reminders from the
#   Reminders Core Data store(s) (the per-account Data-*.sqlite under
#   group.com.apple.reminders/Container_v1/Stores — a pulled snapshot is fine).
#   Reads ZREMCDREMINDER (title/notes/due/completed/flagged/priority) joined to
#   ZREMCDBASELIST (list name).
#
#   Reminders are MUTABLE, so the manifest appends a new version when a reminder
#   changes (keyed by id + content-hash) — completions, edits, and deletions are
#   preserved. Views (text + HTML + index) are regenerated each run.
#
#   Usage:  reminders_archiver.py --db <Stores dir or Data-*.sqlite> --archive <dir>
# =============================================================================
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, san, slug, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.0.0'

PRIORITY = {1: 'High', 5: 'Medium', 9: 'Low'}


def reminder_dbs(path):
    p = Path(path)
    if p.is_dir():
        return sorted(p.glob('**/Data-*.sqlite'))
    return [p] if p.exists() else []


def read_reminders(path):
    out = []
    for db in reminder_dbs(path):
        conn = open_ro(db)
        if not has_table(conn, 'ZREMCDREMINDER'):
            conn.close(); continue
        lists = {pk: s(nm) for pk, nm in rows(conn,
                 'SELECT Z_PK, ZNAME FROM ZREMCDBASELIST WHERE ZNAME IS NOT NULL')}
        for r in rows(conn,
                'SELECT ZTITLE, ZNOTES, ZDUEDATE, ZCOMPLETED, ZCOMPLETIONDATE, '
                '       ZFLAGGED, ZPRIORITY, ZCREATIONDATE, ZLIST '
                'FROM ZREMCDREMINDER'):
            title, notes, due, completed, compdate, flagged, prio, created, listpk = r
            if not s(title) and not s(notes):
                continue
            lst = lists.get(listpk, 'Reminders')
            rid = short_hash(lst, s(title), s(created))
            out.append({
                'id': rid, 'title': s(title), 'notes': s(notes), 'list': lst,
                'due': cd_date(due), 'completed': bool(completed),
                'completion_date': cd_date(compdate),
                'flagged': bool(flagged), 'priority': PRIORITY.get(int(prio or 0), ''),
                'created': cd_date(created),
            })
        conn.close()
    return out


def _fmt_line(e, md=True):
    box = '[x]' if e['completed'] else '[ ]'
    bits = [f"{box} {e['title'] or '(untitled)'}"]
    extras = []
    if e['due']:
        extras.append(f"due {e['due']}")
    if e['priority']:
        extras.append(e['priority'].lower())
    if e['flagged']:
        extras.append('🚩')
    if e['completed'] and e['completion_date']:
        extras.append(f"done {e['completion_date']}")
    if extras:
        bits.append('— ' + ', '.join(extras))
    line = ' '.join(bits)
    if e['notes']:
        line += '\n      ' + e['notes'].replace('\n', '\n      ')
    return line


def build_views(archive, entries):
    archive = Path(archive)
    rem_root = archive / 'reminders'
    rem_root.mkdir(parents=True, exist_ok=True)

    current = latest_per_id(entries)
    by_list = {}
    for e in current:
        by_list.setdefault(e['list'], []).append(e)

    index_rows, sections = [], []
    for lst in sorted(by_list):
        items = by_list[lst]
        opn = [e for e in items if not e['completed']]
        done = [e for e in items if e['completed']]
        opn.sort(key=lambda e: e.get('due') or '~')      # dated first
        done.sort(key=lambda e: e.get('completion_date') or '', reverse=True)

        lines = [f"# {lst}", f"_{len(opn)} open · {len(done)} completed_", '']
        if opn:
            lines.append('## Open')
            lines += [_fmt_line(e) for e in opn]
            lines.append('')
        if done:
            lines.append('## Completed')
            lines += [_fmt_line(e) for e in done]
        (rem_root / f'{san(lst)}.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')

        index_rows.append({'list': lst, 'open': len(opn), 'completed': len(done),
                           'total': len(items)})

        cards = []
        for e in opn + done:
            cls = 't done' if e['completed'] else 't'
            meta = ' · '.join(x for x in [e['due'] and f"due {e['due']}", e['priority'],
                                          '🚩' if e['flagged'] else '',
                                          e['completed'] and 'completed'] if x)
            notes_html = f'<div class="body">{esc(e["notes"])}</div>' if e['notes'] else ''
            cards.append(f'<div class="item"><div class="{cls}">'
                         f'{"☑ " if e["completed"] else "☐ "}{esc(e["title"]) or "(untitled)"}</div>'
                         f'<div class="meta">{esc(meta)}</div>{notes_html}</div>')
        sections.append(f'<h2 style="max-width:760px">{esc(lst)} '
                        f'<span style="color:#999;font-size:13px">({len(opn)} open · {len(done)} done)</span></h2>'
                        + '\n'.join(cards))

    (archive / 'reminders.html').write_text(
        html_page(f'Reminders ({len(current)})', '\n'.join(sections)), encoding='utf-8')
    write_csv(archive / '_index.csv', ['list', 'open', 'completed', 'total'], index_rows)
    return len(current), len(by_list)


def run_archive(db, archive):
    archive = Path(archive)
    archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    existing = load_manifest(mpath)
    seen = manifest_keys(existing)

    new = []
    for e in read_reminders(db):
        key = (e['id'], content_hash(e['title'], e['notes'], e['due'],
                                     e['completed'], e['flagged'], e['priority']))
        if key in seen:
            continue
        seen.add(key)
        rec = dict(e); rec['hash'] = key[1]
        new.append(rec)
    append_manifest(mpath, new)

    rem, lists = build_views(archive, load_manifest(mpath))
    return {'new_versions': len(new), 'reminders': rem, 'lists': lists}


def main():
    ap = argparse.ArgumentParser(prog='reminders_archiver',
        description='Append-only, browsable Apple Reminders archiver.')
    ap.add_argument('--db', required=True,
                    help='Reminders Stores directory or a single Data-*.sqlite')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'reminders store not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Reminders archive: +{r["new_versions"]} new version(s); '
          f'{r["reminders"]} reminders across {r["lists"]} list(s).')


if __name__ == '__main__':
    main()
