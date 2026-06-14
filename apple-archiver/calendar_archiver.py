#!/usr/bin/env python3
# =============================================================================
#   APPLE CALENDAR ARCHIVER
#   File:     calendar_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only archive of Apple Calendar events from Calendar.sqlitedb
#   (modern schema: CalendarItem + Calendar + Location). Events are mutable
#   (reschedules/edits), so the manifest versions by (id, content-hash). Per
#   calendar it writes a Markdown agenda, a browsable HTML, AND a re-importable
#   `.ics` file, plus a CSV index.
#
#   Usage:  calendar_archiver.py --db <Calendar.sqlitedb> --archive <dir>
# =============================================================================
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, cd_dt, san, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.1.0'


def read_events(db):
    """Version-robust across two Calendar schemas:
      • modern (macOS 13+):  Calendar.sqlitedb — table CalendarItem (summary/
        start_date/end_date/all_day/calendar_id/location_id) + Calendar + Location.
      • legacy (macOS ≤12):  'Calendar Cache' — Core Data ZCALENDARITEM (ZTITLE/
        ZSTARTDATE/ZENDDATE/ZISALLDAY/ZNOTES/ZCALENDAR/ZSTRUCTUREDLOCATION)."""
    conn = open_ro(db)
    table = ('CalendarItem' if has_table(conn, 'CalendarItem')
             else 'ZCALENDARITEM' if has_table(conn, 'ZCALENDARITEM') else None)
    if not table:
        conn.close(); return []
    cols = {r[1] for r in rows(conn, f'PRAGMA table_info({table})')}
    pick = lambda cands: next((c for c in cands if c in cols), None)
    c_title = pick(['summary', 'ZTITLE'])
    c_notes = pick(['description', 'ZNOTES']) or 'NULL'
    c_start = pick(['start_date', 'ZSTARTDATE'])
    c_end = pick(['end_date', 'ZENDDATE']) or 'NULL'
    c_all = pick(['all_day', 'ZISALLDAY']) or '0'
    c_cal = pick(['calendar_id', 'ZCALENDAR']) or 'NULL'
    c_loc = pick(['location_id', 'ZSTRUCTUREDLOCATION']) or 'NULL'
    if not c_title or not c_start:
        conn.close(); return []

    cals = {}
    if has_table(conn, 'Calendar'):
        for rid, t in rows(conn, 'SELECT ROWID, title FROM Calendar'):
            cals[rid] = s(t)
    locs = {}
    if has_table(conn, 'Location'):
        for rid, t, a in rows(conn, 'SELECT ROWID, title, address FROM Location'):
            locs[rid] = s(t) or s(a)
    elif has_table(conn, 'ZSTRUCTUREDLOCATION'):
        lc = {r[1] for r in rows(conn, 'PRAGMA table_info(ZSTRUCTUREDLOCATION)')}
        lt = 'ZTITLE' if 'ZTITLE' in lc else 'NULL'
        la = 'ZADDRESS' if 'ZADDRESS' in lc else 'NULL'
        for rid, t, a in rows(conn, f'SELECT Z_PK, {lt}, {la} FROM ZSTRUCTUREDLOCATION'):
            locs[rid] = s(t) or s(a)

    out = []
    for sm, desc, start, end, allday, calid, locid in rows(conn,
            f'SELECT {c_title}, {c_notes}, {c_start}, {c_end}, {c_all}, {c_cal}, {c_loc} '
            f'FROM {table} WHERE {c_title} IS NOT NULL'):
        cal = cals.get(calid, 'Calendar')
        fmt = '%Y-%m-%d' if allday else '%Y-%m-%d %H:%M'
        out.append({
            'id': short_hash(cal, s(sm), str(start)),
            'calendar': cal, 'summary': s(sm), 'notes': s(desc),
            'location': locs.get(locid, ''), 'all_day': bool(allday),
            'start': cd_date(start, fmt), 'end': cd_date(end, fmt),
            'start_raw': start, 'end_raw': end,
        })
    conn.close()
    return out


def _ics_esc(t):
    return (s(t).replace('\\', '\\\\').replace(';', '\\;')
            .replace(',', '\\,').replace('\n', '\\n'))


def _ics_dt(raw, all_day):
    dt = cd_dt(raw)
    if not dt:
        return None
    return (f';VALUE=DATE:{dt.strftime("%Y%m%d")}' if all_day
            else f':{dt.strftime("%Y%m%dT%H%M%S")}')


def write_ics(path, events):
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//PhantomLives//apple-archiver//EN']
    for e in events:
        ds = _ics_dt(e['start_raw'], e['all_day'])
        if not ds:
            continue
        lines.append('BEGIN:VEVENT')
        lines.append(f'UID:{e["id"]}@apple-archiver')
        lines.append('DTSTART' + ds)
        de = _ics_dt(e['end_raw'], e['all_day'])
        if de:
            lines.append('DTEND' + de)
        lines.append('SUMMARY:' + _ics_esc(e['summary']))
        if e['location']:
            lines.append('LOCATION:' + _ics_esc(e['location']))
        if e['notes']:
            lines.append('DESCRIPTION:' + _ics_esc(e['notes']))
        lines.append('END:VEVENT')
    lines.append('END:VCALENDAR')
    Path(path).write_text('\r\n'.join(lines) + '\r\n', encoding='utf-8')


def build_views(archive, entries):
    archive = Path(archive)
    (archive / 'ics').mkdir(parents=True, exist_ok=True)
    cal_root = archive / 'calendars'; cal_root.mkdir(parents=True, exist_ok=True)

    current = latest_per_id(entries)
    by_cal = {}
    for e in current:
        by_cal.setdefault(e['calendar'], []).append(e)

    index_rows, sections = [], []
    for cal in sorted(by_cal):
        evs = sorted(by_cal[cal], key=lambda e: e.get('start_raw') or 0)
        # Markdown agenda.
        md = [f'# {cal}', f'_{len(evs)} events_', '']
        for e in evs:
            line = f'- {e["start"]}'
            if e['end'] and not e['all_day']:
                line += f'–{e["end"][11:]}'
            line += f'  {e["summary"]}'
            if e['location']:
                line += f'  @ {e["location"]}'
            md.append(line)
            if e['notes']:
                md.append(f'    {e["notes"]}')
        (cal_root / f'{san(cal)}.md').write_text('\n'.join(md) + '\n', encoding='utf-8')
        write_ics(archive / 'ics' / f'{san(cal)}.ics', evs)

        cards = []
        for e in evs:
            meta = ' · '.join(x for x in [e['start'], e['location']] if x)
            notes = f'<div class="sub">{esc(e["notes"])}</div>' if e['notes'] else ''
            cards.append(f'<div class="item"><div class="t">{esc(e["summary"])}</div>'
                         f'<div class="meta">{esc(meta)}</div>{notes}</div>')
        sections.append(f'<h2 style="max-width:760px">{esc(cal)} '
                        f'<span style="color:#999;font-size:13px">({len(evs)})</span></h2>'
                        + '\n'.join(cards))
        rng = f'{evs[0]["start"][:10]} → {evs[-1]["start"][:10]}' if evs else ''
        index_rows.append({'calendar': cal, 'events': len(evs), 'range': rng})

    (archive / 'calendar.html').write_text(
        html_page(f'Calendar ({len(current)} events)', '\n'.join(sections)), encoding='utf-8')
    write_csv(archive / '_index.csv', ['calendar', 'events', 'range'], index_rows)
    return len(current), len(by_cal)


def run_archive(db, archive):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []
    for e in read_events(db):
        key = (e['id'], content_hash(e['summary'], e['start'], e['end'], e['location'], e['notes']))
        if key in seen:
            continue
        seen.add(key); rec = dict(e); rec['hash'] = key[1]; new.append(rec)
    append_manifest(mpath, new)
    evs, cals = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'events': evs, 'calendars': cals}


def main():
    ap = argparse.ArgumentParser(prog='calendar_archiver',
        description='Append-only Apple Calendar archiver (Markdown + HTML + .ics).')
    ap.add_argument('--db', required=True, help='path to Calendar.sqlitedb')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'Calendar.sqlitedb not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Calendar: +{r["new"]} new version(s); {r["events"]} events across {r["calendars"]} calendar(s).')


if __name__ == '__main__':
    main()
