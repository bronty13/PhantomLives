"""Phase 2 — the keep→Photos import worker.

Mirrors PurplePeek's pipeline, delegating the heavy lifting to proven tools (runs on the host with
the Photos library — Vortex now, airy later):
  • keep (photo/video) → `osxphotos import` with title/description/keyword/album set on the asset.
      Favorites are staged (a copy with XMP:Rating embedded via exiftool) and imported with
      `--favorite-rating`, since osxphotos has no direct "favorite" flag.
  • keep (audio)        → Photos can't hold audio → keep-export the file to keptAudioDir.
  • skip               → move the file to the Trash (recoverable).

SAFETY: process_pending defaults to DRY-RUN. Nothing imports/trashes unless execute=True. The argv
builder is pure (unit-tested); only run_* touch Photos/disk.
"""
import os
import shutil
import subprocess

from . import db


def build_import_argv(osx, src, title, caption, keywords, albums, report, favorite):
    """PURE: the osxphotos import command for one keeper. Favorites add --exiftool/--favorite-rating
    (the staged copy carries an embedded XMP:Rating)."""
    argv = [osx, "import", src, "--skip-dups", "--verbose", "--report", report]
    if title:
        argv += ["--title", title]
    if caption:
        argv += ["--description", caption]
    for k in (keywords or []):
        argv += ["--keyword", k]
    for a in (albums or []):
        argv += ["--album", a]
    if favorite:
        argv += ["--exiftool", "--favorite-rating", "1"]
    return argv


def _stage_favorite(src, staging_dir, exiftool):
    os.makedirs(staging_dir, exist_ok=True)
    dst = os.path.join(staging_dir, os.path.basename(src))
    shutil.copy2(src, dst)
    subprocess.run([exiftool, "-overwrite_original", "-XMP:Rating=5", dst],
                   capture_output=True, timeout=120)
    return dst


def run_import(item, cfg, execute=False):
    rec = db.get_media(item["id"]) or item
    fav = bool(rec.get("is_favorite"))
    os.makedirs(cfg["stagingDir"], exist_ok=True)
    report = os.path.join(cfg["stagingDir"], f"report_{item['id']}.json")
    staged = None
    src = rec["file_path"]
    if not execute:
        argv = build_import_argv(cfg["osxphotosBin"], src, rec.get("title"), rec.get("caption"),
                                 rec.get("keywords", []), rec.get("albums", []), report, fav)
        return {"id": item["id"], "name": rec["file_name"], "action": "import", "dry_run": True, "argv": argv}
    try:
        if fav:
            staged = _stage_favorite(src, cfg["stagingDir"], cfg["exiftoolBin"])
            src = staged
        argv = build_import_argv(cfg["osxphotosBin"], src, rec.get("title"), rec.get("caption"),
                                 rec.get("keywords", []), rec.get("albums", []), report, fav)
        r = subprocess.run(argv, capture_output=True, timeout=600, text=True)
        ok = r.returncode == 0
        if ok:
            db.mark_imported(item["id"], _uuid_from_report(report))
        return {"id": item["id"], "name": rec["file_name"], "action": "import",
                "ok": ok, "rc": r.returncode, "err": (r.stderr or "")[-300:] if not ok else ""}
    finally:
        if staged and os.path.exists(staged):
            os.remove(staged)


def run_export_audio(item, cfg, execute=False):
    rec = db.get_media(item["id"]) or item
    dst_dir = cfg["keptAudioDir"]
    dst = os.path.join(dst_dir, rec["file_name"])
    if not execute:
        return {"id": item["id"], "name": rec["file_name"], "action": "export_audio", "dry_run": True, "to": dst}
    os.makedirs(dst_dir, exist_ok=True)
    dst = _unique(dst)
    shutil.copy2(rec["file_path"], dst)
    db.mark_exported(item["id"])
    return {"id": item["id"], "name": rec["file_name"], "action": "export_audio", "ok": True, "to": dst}


def run_skip(item, execute=False):
    rec = db.get_media(item["id"]) or item
    if not execute:
        return {"id": item["id"], "name": rec["file_name"], "action": "trash", "dry_run": True}
    ok = _trash(rec["file_path"])
    if ok:
        db.mark_deleted(item["id"])
    return {"id": item["id"], "name": rec["file_name"], "action": "trash", "ok": ok}


def process_pending(cfg, execute=False, limit=None) -> dict:
    """Run the worker over all pending decisions. DEFAULT dry-run. Returns a summary + per-item log."""
    imports = db.pending_imports()
    audio = db.pending_audio()
    skips = db.pending_skips()
    if limit:
        imports, audio, skips = imports[:limit], audio[:limit], skips[:limit]
    log = []
    for it in imports:
        log.append(run_import(it, cfg, execute))
    for it in audio:
        log.append(run_export_audio(it, cfg, execute))
    for it in skips:
        log.append(run_skip(it, execute))
    summary = {
        "execute": execute,
        "to_import": len(imports), "to_export_audio": len(audio), "to_trash": len(skips),
        "imported_ok": sum(1 for x in log if x.get("action") == "import" and x.get("ok")),
        "failed": sum(1 for x in log if x.get("ok") is False),
    }
    return {"summary": summary, "log": log}


def _trash(path):
    """Move to Trash via Finder (recoverable). Needs Finder Automation permission on the host."""
    if not os.path.exists(path):
        return True
    script = f'tell application "Finder" to delete POSIX file {_osa_quote(path)}'
    r = subprocess.run(["osascript", "-e", script], capture_output=True, timeout=60)
    return r.returncode == 0


def _osa_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _unique(path):
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    i = 2
    while os.path.exists(f"{base} {i}{ext}"):
        i += 1
    return f"{base} {i}{ext}"


def _uuid_from_report(report):
    """Best-effort: pull the imported asset UUID from osxphotos' JSON report (not required)."""
    try:
        import json
        data = json.loads(open(report, encoding="utf-8").read())
        rows = data if isinstance(data, list) else data.get("imported", [])
        for row in rows:
            uid = (row.get("uuid") if isinstance(row, dict) else None)
            if uid:
                return uid
    except Exception:
        pass
    return None
