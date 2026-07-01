"""The authoritative decisions database (SQLite, WAL).

Mirrors PurplePeek's schema closely so (a) the semantics match the app you already use and
(b) existing PurplePeek decisions can be migrated in. ONE database, server-side → every client
sees the same review state. Each function opens a short-lived WAL connection (safe under the
threaded HTTP server: many readers + one writer).
"""
import hashlib
import os
import sqlite3
import time
from contextlib import contextmanager

SCHEMA = """
CREATE TABLE IF NOT EXISTS scan_roots (
    path            TEXT PRIMARY KEY,
    label           TEXT,
    kind            TEXT,
    last_scanned_at TEXT,
    total_files     INTEGER NOT NULL DEFAULT 0,
    sort_order      INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS media_files (
    id               TEXT PRIMARY KEY,            -- sha1(file_path)[:16], stable per path
    scan_root        TEXT NOT NULL REFERENCES scan_roots(path) ON DELETE CASCADE,
    file_path        TEXT NOT NULL UNIQUE,
    file_name        TEXT NOT NULL,
    file_type        TEXT NOT NULL,               -- image|video|audio|other
    file_size        INTEGER,
    file_modified_at TEXT,
    keep             INTEGER,                     -- NULL=undecided, 1=keep, 0=skip
    is_favorite      INTEGER NOT NULL DEFAULT 0,
    title            TEXT,
    caption          TEXT,
    is_hidden        INTEGER NOT NULL DEFAULT 0,
    imported_at      TEXT,
    exported_at      TEXT,
    deleted_at       TEXT,
    missing_at       TEXT,
    photos_asset_id  TEXT,
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_media_scan_root ON media_files(scan_root);
CREATE INDEX IF NOT EXISTS idx_media_keep ON media_files(keep);
CREATE TABLE IF NOT EXISTS keywords (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL UNIQUE COLLATE NOCASE,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS file_keywords (
    file_id    TEXT NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
    keyword_id TEXT NOT NULL REFERENCES keywords(id) ON DELETE CASCADE,
    PRIMARY KEY (file_id, keyword_id)
);
CREATE TABLE IF NOT EXISTS file_albums (
    file_id    TEXT NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
    album_name TEXT NOT NULL,
    PRIMARY KEY (file_id, album_name)
);
"""

_DB_PATH = None


def init(db_path: str):
    """Set the DB path (creating parent dir) and apply the schema."""
    global _DB_PATH
    _DB_PATH = db_path
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    with connect() as conn:
        conn.executescript(SCHEMA)


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def file_id(path: str) -> str:
    return hashlib.sha1(path.encode("utf-8")).hexdigest()[:16]


@contextmanager
def connect():
    conn = sqlite3.connect(_DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


# ---- scan roots -------------------------------------------------------------

def upsert_root(path: str, label: str, kind: str, order: int):
    with connect() as c:
        c.execute(
            """INSERT INTO scan_roots(path,label,kind,sort_order,last_scanned_at)
               VALUES(?,?,?,?,?)
               ON CONFLICT(path) DO UPDATE SET label=excluded.label, kind=excluded.kind,
                 sort_order=excluded.sort_order""",
            (path, label, kind, order, None),
        )


def set_root_scanned(path: str, total: int):
    with connect() as c:
        c.execute("UPDATE scan_roots SET last_scanned_at=?, total_files=? WHERE path=?",
                  (now(), total, path))


def roots_with_counts() -> list:
    with connect() as c:
        rows = c.execute("""
            SELECT r.path, r.label, r.kind, r.last_scanned_at, r.sort_order,
                   COUNT(m.id) AS total,
                   SUM(m.keep IS NULL AND m.deleted_at IS NULL) AS undecided,
                   SUM(m.keep=1) AS kept, SUM(m.keep=0) AS skipped
            FROM scan_roots r LEFT JOIN media_files m ON m.scan_root=r.path
            GROUP BY r.path ORDER BY r.sort_order, r.label
        """).fetchall()
        return [dict(r) for r in rows]


# ---- media files ------------------------------------------------------------

def upsert_media(scan_root: str, path: str, name: str, ftype: str, size: int, mtime: str):
    """Insert a discovered file; PRESERVE any existing decision on re-scan (decision-safe)."""
    mid = file_id(path)
    n = now()
    with connect() as c:
        c.execute(
            """INSERT INTO media_files
                 (id,scan_root,file_path,file_name,file_type,file_size,file_modified_at,
                  created_at,updated_at)
               VALUES(?,?,?,?,?,?,?,?,?)
               ON CONFLICT(file_path) DO UPDATE SET
                 file_size=excluded.file_size, file_modified_at=excluded.file_modified_at,
                 missing_at=NULL, updated_at=excluded.updated_at""",
            (mid, scan_root, path, name, ftype, size, mtime, n, n),
        )
    return mid


def list_media(root: str = None, decision: str = "all", offset: int = 0, limit: int = 200):
    where, args = ["deleted_at IS NULL"], []
    if root:
        where.append("scan_root = ?"); args.append(root)
    if decision == "undecided":
        where.append("keep IS NULL")
    elif decision == "kept":
        where.append("keep = 1")
    elif decision == "skipped":
        where.append("keep = 0")
    elif decision == "favorite":
        where.append("is_favorite = 1")
    clause = " AND ".join(where)
    with connect() as c:
        total = c.execute(f"SELECT COUNT(*) FROM media_files WHERE {clause}", args).fetchone()[0]
        rows = c.execute(
            f"""SELECT id,scan_root,file_path,file_name,file_type,file_size,keep,is_favorite,
                       title,caption,is_hidden,imported_at,photos_asset_id
                FROM media_files WHERE {clause}
                ORDER BY file_name LIMIT ? OFFSET ?""",
            args + [limit, offset],
        ).fetchall()
        return total, [dict(r) for r in rows]


def get_media(mid: str):
    with connect() as c:
        row = c.execute("SELECT * FROM media_files WHERE id=?", (mid,)).fetchone()
        if not row:
            return None
        d = dict(row)
        d["keywords"] = [r[0] for r in c.execute(
            "SELECT k.name FROM file_keywords fk JOIN keywords k ON k.id=fk.keyword_id "
            "WHERE fk.file_id=? ORDER BY k.name", (mid,)).fetchall()]
        d["albums"] = [r[0] for r in c.execute(
            "SELECT album_name FROM file_albums WHERE file_id=? ORDER BY album_name", (mid,)).fetchall()]
        return d


def path_for(mid: str):
    with connect() as c:
        row = c.execute("SELECT file_path, file_type FROM media_files WHERE id=?", (mid,)).fetchone()
        return (row["file_path"], row["file_type"]) if row else (None, None)


def serving_info(mid: str):
    """(file_path, file_type, file_modified_at) in one lookup — what /thumb, /full and /preview
    need to serve a request. Includes the DB-recorded mtime so cache freshness can be decided
    without stat'ing the original on the (slow, possibly spun-down) source volume."""
    with connect() as c:
        row = c.execute("SELECT file_path, file_type, file_modified_at FROM media_files WHERE id=?",
                        (mid,)).fetchone()
        return (row["file_path"], row["file_type"], row["file_modified_at"]) if row else (None, None, None)


_DECISION_FIELDS = {"keep", "is_favorite", "title", "caption", "is_hidden"}


def update_decision(mid: str, fields: dict):
    """Update scalar decision fields and (optionally) keywords/albums. Returns the fresh record."""
    sets, args = [], []
    for k, v in fields.items():
        if k in _DECISION_FIELDS:
            sets.append(f"{k}=?"); args.append(v)
    with connect() as c:
        if sets:
            sets.append("updated_at=?"); args.append(now()); args.append(mid)
            c.execute(f"UPDATE media_files SET {', '.join(sets)} WHERE id=?", args)
        if "keywords" in fields:
            _set_keywords(c, mid, fields["keywords"])
        if "albums" in fields:
            c.execute("DELETE FROM file_albums WHERE file_id=?", (mid,))
            for a in fields["albums"]:
                c.execute("INSERT OR IGNORE INTO file_albums(file_id,album_name) VALUES(?,?)", (mid, a))
    return get_media(mid)


# ---- import-worker state (Phase 2) -----------------------------------------

def mark_imported(mid: str, asset_id: str = None):
    with connect() as c:
        c.execute("UPDATE media_files SET imported_at=?, photos_asset_id=?, updated_at=? WHERE id=?",
                  (now(), asset_id, now(), mid))


def mark_exported(mid: str):
    with connect() as c:
        c.execute("UPDATE media_files SET exported_at=?, updated_at=? WHERE id=?", (now(), now(), mid))


def mark_deleted(mid: str):
    with connect() as c:
        c.execute("UPDATE media_files SET deleted_at=?, updated_at=? WHERE id=?", (now(), now(), mid))


def pending_imports() -> list:
    """Kept, not yet imported, not audio, not deleted/missing → import to Photos."""
    with connect() as c:
        return [dict(r) for r in c.execute(
            """SELECT * FROM media_files WHERE keep=1 AND imported_at IS NULL
               AND file_type<>'audio' AND deleted_at IS NULL AND missing_at IS NULL
               ORDER BY file_name""").fetchall()]


def pending_audio() -> list:
    """Kept audio, not yet keep-exported (Photos can't hold audio)."""
    with connect() as c:
        return [dict(r) for r in c.execute(
            """SELECT * FROM media_files WHERE keep=1 AND file_type='audio'
               AND exported_at IS NULL AND deleted_at IS NULL AND missing_at IS NULL""").fetchall()]


def pending_skips() -> list:
    """Skipped, not yet trashed."""
    with connect() as c:
        return [dict(r) for r in c.execute(
            """SELECT * FROM media_files WHERE keep=0 AND deleted_at IS NULL
               AND missing_at IS NULL""").fetchall()]


def _set_keywords(c, mid: str, names: list):
    c.execute("DELETE FROM file_keywords WHERE file_id=?", (mid,))
    for name in names:
        kid = file_id("kw:" + name.lower())
        c.execute("INSERT OR IGNORE INTO keywords(id,name,created_at) VALUES(?,?,?)", (kid, name, now()))
        row = c.execute("SELECT id FROM keywords WHERE name=? COLLATE NOCASE", (name,)).fetchone()
        c.execute("INSERT OR IGNORE INTO file_keywords(file_id,keyword_id) VALUES(?,?)", (mid, row["id"]))
