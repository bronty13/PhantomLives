"""The HTTP server: web UI + JSON API + thumbnail/full-file serving.

Pure stdlib (ThreadingHTTPServer). Routes:
  GET  /                     → the web review UI
  GET  /static/<file>        → web assets (app.js, style.css)
  GET  /api/roots            → scan roots + decision counts
  GET  /api/items?root&decision&offset&limit → paginated media + decisions
  GET  /api/item/<id>        → one media record (with keywords/albums)
  GET  /thumb/<id>           → cached JPEG thumbnail (generated on first hit)
  GET  /full/<id>            → the original file (Range-aware, so video plays in-browser)
  GET  /preview/<id>         → video: a cached 720p faststart proxy (smooth LAN playback); else original
  POST /api/decision         → {id, keep?, is_favorite?, title?, caption?, is_hidden?, keywords?, albums?}
  POST /api/scan             → rescan all roots (background)
"""
import json
import os
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__, auth, db, importer, media, migrate, scan

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "web")
_CFG = {}
_scanning = threading.Event()


def run(cfg: dict):
    global _CFG
    _CFG = cfg
    start_periodic_scan(cfg)
    httpd = ThreadingHTTPServer((cfg["bind"], cfg["port"]), Handler)
    print(f"PeekServer {__version__} → http://{cfg['bind']}:{cfg['port']}  "
          f"(db={cfg['dbPath']}, {len(cfg['roots'])} root(s))")
    httpd.serve_forever()


def periodic_scan_interval(cfg: dict) -> int:
    """Seconds between auto-rescans (0 = disabled). Pure so it's unit-testable."""
    try:
        minutes = int(cfg.get("scanIntervalMinutes", 0))
    except (TypeError, ValueError):
        return 0
    return max(0, minutes) * 60


def start_periodic_scan(cfg: dict):
    """Rescan every root on an interval so files staged after startup (e.g. Rachel's hourly sync)
    show up in clients without anyone POSTing /api/scan. background_scan() self-guards against
    overlap, so a slow scan on a busy drive just skips the next tick rather than piling up."""
    interval = periodic_scan_interval(cfg)
    if interval <= 0:
        print("periodic rescan: disabled (scanIntervalMinutes=0)")
        return
    def loop():
        while True:
            time.sleep(interval)
            background_scan()
    threading.Thread(target=loop, daemon=True).start()
    print(f"periodic rescan: every {interval // 60} min")


def background_scan():
    if _scanning.is_set():
        return
    _scanning.set()
    def work():
        try:
            res = scan.scan_all(_CFG.get("roots", []))
            print("scan complete:", res)
        finally:
            _scanning.clear()
        warm_proxies_async()          # get new videos ready to stream
    threading.Thread(target=work, daemon=True).start()


_proxy_warming = threading.Event()


def warm_proxies_async():
    """After a scan, background-generate streaming proxies for any videos lacking one, one at a time
    (transcoding is CPU-heavy) so review videos play instantly without a first-view transcode stall.
    Best-effort; a single pass at a time (guarded)."""
    if not _CFG.get("warmProxies", True) or _proxy_warming.is_set():
        return
    _proxy_warming.set()
    def work():
        try:
            cache = _CFG["proxyCache"]
            ff = _CFG.get("ffmpegBin", "ffmpeg")
            h, br = _CFG.get("proxyHeight", 720), _CFG.get("proxyMaxBitrateK", 4000)
            made = 0
            for root in _CFG.get("roots", []):
                off = 0
                while True:
                    _, batch = db.list_media(root=root["path"], decision="all", offset=off, limit=500)
                    if not batch:
                        break
                    off += len(batch)
                    for it in batch:
                        if it["file_type"] != "video":
                            continue
                        dst = media.proxy_path(cache, it["id"])
                        if os.path.exists(dst):
                            continue
                        if media.ensure_video_proxy(it["file_path"], dst, ff, h, br):
                            made += 1
            if made:
                print(f"proxy warm: generated {made} video proxies")
        finally:
            _proxy_warming.clear()
    threading.Thread(target=work, daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    server_version = f"PeekServer/{__version__}"

    def log_message(self, *a):  # quieter than default
        pass

    # ---- helpers ----
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _bytes(self, body: bytes, ctype: str, code=200, cache=True):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if cache:
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        self.end_headers()
        self.wfile.write(body)

    def _notfound(self):
        self._json({"error": "not found"}, 404)

    def _authorized(self) -> bool:
        if auth.check_basic(self.headers.get("Authorization", ""),
                            _CFG.get("authUser", ""), _CFG.get("authPasswordSHA256", "")):
            return True
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="PeekServer"')
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "13")
        self.end_headers()
        self.wfile.write(b"Auth required")
        return False

    # ---- GET ----
    def do_GET(self):
        if not self._authorized():
            return
        u = urllib.parse.urlparse(self.path)
        path, q = u.path, urllib.parse.parse_qs(u.query)
        if path == "/" or path == "/index.html":
            return self._serve_web("index.html", "text/html; charset=utf-8")
        if path.startswith("/static/"):
            return self._serve_web(os.path.basename(path), _ctype(path))
        if path == "/api/roots":
            return self._json({"roots": db.roots_with_counts(), "scanning": _scanning.is_set()})
        if path == "/api/items":
            total, items = db.list_media(
                root=_first(q, "root"),
                decision=_first(q, "decision", "all"),
                offset=int(_first(q, "offset", "0")),
                limit=min(int(_first(q, "limit", "200")), 500),
            )
            return self._json({"total": total, "items": items})
        if path.startswith("/api/item/"):
            rec = db.get_media(path.rsplit("/", 1)[-1])
            return self._json(rec) if rec else self._notfound()
        if path.startswith("/thumb/"):
            return self._serve_thumb(path.rsplit("/", 1)[-1])
        if path.startswith("/full/"):
            return self._serve_full(path.rsplit("/", 1)[-1])
        if path.startswith("/preview/"):
            return self._serve_preview(path.rsplit("/", 1)[-1])
        return self._notfound()

    # ---- POST ----
    def do_POST(self):
        if not self._authorized():
            return
        u = urllib.parse.urlparse(self.path)
        if u.path == "/api/scan":
            background_scan()
            return self._json({"ok": True, "scanning": True})
        if u.path == "/api/decision":
            data = self._read_json()
            mid = data.pop("id", None)
            if not mid:
                return self._json({"error": "missing id"}, 400)
            rec = db.update_decision(mid, data)
            return self._json(rec) if rec else self._notfound()
        if u.path == "/api/migrate":
            return self._json(migrate.migrate_from_purplepeek(_CFG["purplePeekDb"]))
        if u.path == "/api/process":
            data = self._read_json()
            # destructive (import/trash) only when execute is explicitly true; default dry-run
            res = importer.process_pending(_CFG, execute=bool(data.get("execute")),
                                           limit=data.get("limit"))
            return self._json(res["summary"])
        if u.path == "/api/mark-imported":
            # A CLIENT imported this file to ITS OWN Photos (client-side import model); just record
            # it so the item leaves the pending queue and isn't re-offered. No server-side Photos work.
            data = self._read_json()
            mid = data.get("id")
            if not mid:
                return self._json({"error": "missing id"}, 400)
            db.mark_imported(mid, data.get("asset_id"))
            return self._json({"ok": True})
        if u.path == "/api/mark-exported":
            # A client keep-exported this audio file to its own machine; record it.
            data = self._read_json()
            mid = data.get("id")
            if not mid:
                return self._json({"error": "missing id"}, 400)
            db.mark_exported(mid)
            return self._json({"ok": True})
        if u.path == "/api/trash":
            # Trash ONE rejected review file, headless + recoverable (no Finder automation). Only
            # marks it deleted if the file actually reached the Trash.
            data = self._read_json()
            mid = data.get("id")
            if not mid:
                return self._json({"error": "missing id"}, 400)
            path, _ = db.path_for(mid)
            if path and importer.move_to_trash(path):
                db.mark_deleted(mid)
                return self._json({"ok": True})
            return self._json({"ok": False, "error": "trash failed"}, 500)
        return self._notfound()

    def _read_json(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n) or b"{}")

    # ---- static / media ----
    def _serve_web(self, name, ctype):
        fp = os.path.join(WEB_DIR, name)
        if not os.path.isfile(fp):
            return self._notfound()
        with open(fp, "rb") as f:
            self._bytes(f.read(), ctype, cache=False)

    def _serve_thumb(self, mid):
        path, ftype = db.path_for(mid)
        if not path:
            return self._notfound()
        dst = media.thumb_path(_CFG["thumbCache"], mid)
        if media.ensure_thumb(path, dst, ftype, _CFG.get("thumbSize", 512)):
            with open(dst, "rb") as f:
                return self._bytes(f.read(), "image/jpeg")
        return self._notfound()  # audio / failed → UI shows a glyph

    def _serve_full(self, mid):
        path, _ = db.path_for(mid)
        if not path or not os.path.isfile(path):
            return self._notfound()
        self._serve_file(path, _ctype(path))

    def _serve_preview(self, mid):
        """Stream a video via its lightweight 720p faststart proxy (generated + cached on first
        hit). Non-video (or transcode failure) falls back to the original. Photos never use this."""
        path, ftype = db.path_for(mid)
        if not path or not os.path.isfile(path):
            return self._notfound()
        if ftype == "video":
            dst = media.proxy_path(_CFG["proxyCache"], mid)
            if media.ensure_video_proxy(path, dst, _CFG.get("ffmpegBin", "ffmpeg"),
                                        _CFG.get("proxyHeight", 720), _CFG.get("proxyMaxBitrateK", 4000)):
                return self._serve_file(dst, "video/mp4")
        return self._serve_file(path, _ctype(path))   # non-video or transcode failed → original

    def _serve_file(self, path, ctype):
        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            start_s, _, end_s = rng[6:].partition("-")
            start = int(start_s) if start_s else 0
            end = int(end_s) if end_s else size - 1
            end = min(end, size - 1)
            length = end - start + 1
            self.send_response(206)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(length))
            self.end_headers()
            with open(path, "rb") as f:
                f.seek(start)
                _copy(f, self.wfile, length)
        else:
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(size))
            self.end_headers()
            with open(path, "rb") as f:
                _copy(f, self.wfile, size)


def _copy(src, dst, length, chunk=1 << 16):
    remaining = length
    while remaining > 0:
        buf = src.read(min(chunk, remaining))
        if not buf:
            break
        dst.write(buf)
        remaining -= len(buf)


def _first(q, key, default=None):
    v = q.get(key)
    return v[0] if v else default


def _ctype(path):
    import mimetypes
    ext = os.path.splitext(path)[1].lower()
    extra = {".heic": "image/heic", ".heif": "image/heif", ".mov": "video/quicktime",
             ".m4v": "video/x-m4v", ".js": "application/javascript", ".css": "text/css"}
    return extra.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"
