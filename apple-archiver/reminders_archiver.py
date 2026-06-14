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


# Core Data column names drift across macOS versions; COALESCE the known variants
# and only reference columns that actually exist in the given table.
TITLE_COLS = ['ZTITLE', 'ZTITLE1']
NOTES_COLS = ['ZNOTES', 'ZNOTES1', 'ZNOTES2']
DUE_COLS = ['ZDUEDATE', 'ZDUEDATE1']
CREATED_COLS = ['ZCREATIONDATE', 'ZCREATIONDATE1']
LISTNAME_COLS = ['ZNAME', 'ZNAME2', 'ZNAME1']


def _cols(conn, table):
    return {r[1] for r in rows(conn, f'PRAGMA table_info({table})')}


def _expr(present, candidates, default='NULL'):
    cols = [c for c in candidates if c in present]
    if not cols:
        return default
    return cols[0] if len(cols) == 1 else 'COALESCE(' + ','.join(cols) + ')'


def read_reminders(path):
    """Read reminders from each store, version-robustly. Supports:
      • modern (macOS 13+):  reminders in ZREMCDREMINDER, lists in ZREMCDBASELIST,
                             title ZTITLE / created ZCREATIONDATE / list-name ZNAME
      • legacy (macOS ≤12):  reminders + lists share ZREMCDOBJECT,
                             title ZTITLE1 / created ZCREATIONDATE1 / list-name ZNAME2
    Column variants are detected per-table and COALESCEd."""
    out = []
    for db in reminder_dbs(path):
        conn = open_ro(db)
        # List-name map from whichever list source(s) exist.
        lists = {}
        for src in ('ZREMCDBASELIST', 'ZREMCDOBJECT'):
            if not has_table(conn, src):
                continue
            nexpr = _expr(_cols(conn, src), LISTNAME_COLS)
            if nexpr == 'NULL':
                continue
            for pk, nm in rows(conn, f'SELECT Z_PK, {nexpr} AS nm FROM {src} WHERE {nexpr} IS NOT NULL'):
                lists.setdefault(pk, s(nm))

        for table in ('ZREMCDREMINDER', 'ZREMCDOBJECT'):
            if not has_table(conn, table):
                continue
            p = _cols(conn, table)
            te = _expr(p, TITLE_COLS); ne = _expr(p, NOTES_COLS)
            de = _expr(p, DUE_COLS); ce = _expr(p, CREATED_COLS)
            if te == 'NULL':
                continue
            sel = (f'SELECT {te} AS t, {ne} AS n, {de} AS due, '
                   f'{"ZCOMPLETED" if "ZCOMPLETED" in p else "0"} AS done, '
                   f'{"ZCOMPLETIONDATE" if "ZCOMPLETIONDATE" in p else "NULL"} AS cd, '
                   f'{"ZFLAGGED" if "ZFLAGGED" in p else "0"} AS fl, '
                   f'{"ZPRIORITY" if "ZPRIORITY" in p else "0"} AS pr, '
                   f'{ce} AS cr, {"ZLIST" if "ZLIST" in p else "NULL"} AS lst '
                   f'FROM {table} WHERE {te} IS NOT NULL')
            rs = rows(conn, sel)
            if not rs:
                continue
            for title, notes, due, done, compdate, flagged, prio, created, listpk in rs:
                lst = lists.get(listpk, 'Reminders')
                out.append({
                    'id': short_hash(lst, s(title), s(created)),
                    'title': s(title), 'notes': s(notes), 'list': lst,
                    'due': cd_date(due), 'completed': bool(done),
                    'completion_date': cd_date(compdate),
                    'flagged': bool(flagged), 'priority': PRIORITY.get(int(prio or 0), ''),
                    'created': cd_date(created),
                })
            break       # first populated table wins
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
