"""The HTTP server: web UI + JSON API + thumbnail/full-file serving.

Pure stdlib (ThreadingHTTPServer). Routes:
  GET  /                     → the web review UI
  GET  /static/<file>        → web assets (app.js, style.css)
  GET  /api/roots            → scan roots + decision counts
  GET  /api/items?root&decision&offset&limit → paginated media + decisions
  GET  /api/item/<id>        → one media record (with keywords/albums)
  GET  /thumb/<id>           → cached JPEG thumbnail (generated on first hit)
  GET  /full/<id>            → the original file (Range-aware, so video plays in-browser)
  POST /api/decision         → {id, keep?, is_favorite?, title?, caption?, is_hidden?, keywords?, albums?}
  POST /api/scan             → rescan all roots (background)
"""
import json
import os
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__, db, importer, media, migrate, scan

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "web")
_CFG = {}
_scanning = threading.Event()


def run(cfg: dict):
    global _CFG
    _CFG = cfg
    httpd = ThreadingHTTPServer((cfg["bind"], cfg["port"]), Handler)
    print(f"PeekServer {__version__} → http://{cfg['bind']}:{cfg['port']}  "
          f"(db={cfg['dbPath']}, {len(cfg['roots'])} root(s))")
    httpd.serve_forever()


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

    # ---- GET ----
    def do_GET(self):
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
        return self._notfound()

    # ---- POST ----
    def do_POST(self):
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
        path, ftype = db.path_for(mid)
        if not path or not os.path.isfile(path):
            return self._notfound()
        ctype = _ctype(path)
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
