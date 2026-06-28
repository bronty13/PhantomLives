"""Migrate existing PurplePeek decisions into PeekServer's DB.

PurplePeek's schema is mirrored here, so this is a straight per-file copy of keep/favorite/title/
caption/hidden + keywords + albums, matched by `file_path`. Run AFTER a PeekServer scan (so the
rows exist). Only files PeekServer also indexes (the review subfolders) match — PurplePeek
decisions for the rest of the archive are simply unmatched (expected). Idempotent: re-running
re-applies the same decisions.
"""
import os
import sqlite3

from . import db


def decisions_from_purplepeek(pp_conn) -> list:
    """Pure-ish: read PurplePeek → list of (file_path, fields). `fields` matches db.update_decision."""
    pp_conn.row_factory = sqlite3.Row
    rows = pp_conn.execute("""
        SELECT id, file_path, keep, is_favorite, title, caption, is_hidden
        FROM media_files
        WHERE keep IS NOT NULL OR is_favorite=1
           OR (title IS NOT NULL AND title<>'') OR (caption IS NOT NULL AND caption<>'')
    """).fetchall()
    out = []
    for r in rows:
        fields = {
            "keep": r["keep"],
            "is_favorite": r["is_favorite"],
            "title": r["title"],
            "caption": r["caption"],
            "is_hidden": r["is_hidden"],
            "keywords": _keywords(pp_conn, r["id"]),
            "albums": _albums(pp_conn, r["id"]),
        }
        out.append((r["file_path"], fields))
    return out


def _keywords(c, fid):
    try:
        return [x[0] for x in c.execute(
            "SELECT k.name FROM file_keywords fk JOIN keywords k ON k.id=fk.keyword_id WHERE fk.file_id=?",
            (fid,)).fetchall()]
    except sqlite3.OperationalError:
        return []


def _albums(c, fid):
    try:
        return [x[0] for x in c.execute(
            "SELECT album_name FROM file_albums WHERE file_id=?", (fid,)).fetchall()]
    except sqlite3.OperationalError:
        return []


def migrate_from_purplepeek(pp_path: str) -> dict:
    if not os.path.exists(pp_path):
        return {"error": f"PurplePeek DB not found: {pp_path}"}
    pp = sqlite3.connect(f"file:{pp_path}?mode=ro", uri=True)
    try:
        decided = decisions_from_purplepeek(pp)
    finally:
        pp.close()
    matched = unmatched = 0
    for path, fields in decided:
        mid = db.file_id(path)
        if db.get_media(mid):                 # only if PeekServer indexes this file
            db.update_decision(mid, fields)
            matched += 1
        else:
            unmatched += 1
    return {"decided_in_purplepeek": len(decided), "applied": matched, "unmatched": unmatched}
