"""Walk the configured review roots and upsert discovered media into the DB.

Decision-safe: re-scanning never clobbers an existing keep/skip/title/etc. (upsert_media only
touches size/mtime). Files that vanish are marked missing (their decisions are preserved). New
files appear as undecided.
"""
import os

from . import db, media


def scan_root(root: dict) -> int:
    path, label, kind = root["path"], root["label"], root["kind"]
    db.upsert_root(path, label, kind, root.get("order", 0))
    if not os.path.isdir(path):
        # root not mounted/present — leave existing rows intact, count 0 found this pass
        return 0
    seen = set()
    count = 0
    for dirpath, _dirs, files in os.walk(path):
        for fn in files:
            if fn.startswith("."):
                continue
            fp = os.path.join(dirpath, fn)
            if not media.is_media(fp):
                continue
            try:
                st = os.stat(fp)
            except OSError:
                continue
            mtime = _iso(st.st_mtime)
            db.upsert_media(path, fp, fn, media.classify(fp), st.st_size, mtime)
            seen.add(fp)
            count += 1
    _mark_missing(path, seen)
    db.set_root_scanned(path, count)
    return count


def scan_all(roots: list) -> dict:
    result = {}
    for i, r in enumerate(roots):
        r = dict(r); r["order"] = i
        result[r["path"]] = scan_root(r)
    return result


def _mark_missing(root_path: str, seen: set):
    """Mark rows whose file no longer exists (decisions preserved; cleared if file returns)."""
    with db.connect() as c:
        rows = c.execute("SELECT id,file_path FROM media_files WHERE scan_root=? AND deleted_at IS NULL",
                         (root_path,)).fetchall()
        gone = [r["id"] for r in rows if r["file_path"] not in seen]
        for mid in gone:
            c.execute("UPDATE media_files SET missing_at=? WHERE id=? AND missing_at IS NULL",
                      (db.now(), mid))


def _iso(epoch: float) -> str:
    import time
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))
