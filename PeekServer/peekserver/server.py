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
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__, auth, db, importer, media, migrate, scan

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "web")
_CFG = {}
_scanning = threading.Event()


def run(cfg: dict):
    global _CFG
    _CFG = cfg
    swept = media.sweep_stale_artifacts(cfg["proxyCache"])
    if swept:
        print(f"proxy cache: swept {swept} stale transcode artifact(s)")
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


def ordered_warm_roots(roots: list, warm_order: list) -> list:
    """Order roots for proxy warming by `warmOrder` — a list of case-insensitive substrings matched
    against each root's path or label. Roots matching an earlier entry warm first; roots matching no
    entry keep their original order and warm last. Pure/testable.

    This lets a slow-drive backlog (e.g. the big 'My Photos' root on the SMR REDONE) wait until the
    active, fast-drive roots (Rachel's new-items-to-review on the SSD) are fully warmed."""
    def rank(r):
        hay = (r.get("path", "") + " " + r.get("label", "")).lower()
        for i, token in enumerate(warm_order):
            if token and token.lower() in hay:
                return i
        return len(warm_order)
    return [r for _, r in sorted(enumerate(roots), key=lambda t: (rank(t[1]), t[0]))]


def warm_proxies_async():
    """After a scan, background-generate streaming proxies for any videos lacking one, one at a time
    (transcoding is CPU-heavy) so review videos play instantly without a first-view transcode stall.
    Roots are warmed in `warmOrder` priority (active/fast roots before slow backlogs). Best-effort;
    a single pass at a time (guarded)."""
    if not _CFG.get("warmProxies", True) or _proxy_warming.is_set():
        return
    _proxy_warming.set()
    def work():
        try:
            cache = _CFG["proxyCache"]
            ff = _CFG.get("ffmpegBin", "ffmpeg")
            h, br = _CFG.get("proxyHeight", 720), _CFG.get("proxyMaxBitrateK", 4000)
            workers = max(1, int(_CFG.get("warmConcurrency", 3)))
            # Collect the videos that still need a proxy, in warmOrder priority.
            todo = []
            for root in ordered_warm_roots(_CFG.get("roots", []), _CFG.get("warmOrder", [])):
                off = 0
                while True:
                    _, batch = db.list_media(root=root["path"], decision="all", offset=off, limit=500)
                    if not batch:
                        break
                    off += len(batch)
                    for it in batch:
                        if it["file_type"] == "video" and not os.path.exists(media.proxy_path(cache, it["id"])):
                            todo.append(it)
            if not todo:
                return
            print(f"proxy warm: {len(todo)} videos to transcode ({workers} concurrent)")
            def one(it):
                return media.ensure_video_proxy(it["file_path"], media.proxy_path(cache, it["id"]), ff, h, br)
            made = 0
            with ThreadPoolExecutor(max_workers=workers) as ex:
                for ok in ex.map(one, todo):
                    if ok:
                        made += 1
            print(f"proxy warm: generated {made} video proxies")
        finally:
            _proxy_warming.clear()
    threading.Thread(target=work, daemon=True).start()


def parse_range(header, size: int):
    """Parse a single-range `Range` header against a resource of `size` bytes (pure/unit-tested).

    Returns `(start, end)` inclusive for a satisfiable range, `None` to serve the whole file
    (header absent / malformed / multi-range — RFC 9110 lets a server ignore those), or the
    string `"unsatisfiable"` (syntactically valid but no overlap → 416).

    Suffix ranges (`bytes=-N` = the LAST N bytes) matter here: players use them to find a
    trailing moov atom in .mov originals, and serving them as head-of-file (the old parser)
    produced a confidently wrong 206 that broke video seeking entirely.
    """
    if not header or not header.startswith("bytes=") or size <= 0:
        return None
    spec = header[6:].strip()
    if "," in spec:                          # multi-range: legal to ignore → full response
        return None
    start_s, sep, end_s = spec.partition("-")
    if not sep:
        return None
    start_s, end_s = start_s.strip(), end_s.strip()
    try:
        if not start_s:                      # suffix form: last N bytes
            n = int(end_s)
            return (max(0, size - n), size - 1) if n > 0 else None
        start = int(start_s)
        end = int(end_s) if end_s else size - 1
    except ValueError:
        return None
    if end_s and end < start:                # explicit last-pos < first-pos: invalid → ignore
        return None
    if start >= size:                        # valid syntax, no overlap → 416
        return "unsatisfiable"
    return (start, min(end, size - 1))


def file_etag(variant: str, size: int, mtime: float) -> str:
    """Validator for /full and /preview responses (pure/unit-tested). `variant` distinguishes the
    ORIGINAL from the transcoded PROXY at the same URL: /preview serves the original until the
    background transcode lands, then the proxy — without a validator a player could apply Range
    offsets from one file to the other mid-session."""
    return f'"{variant}-{size}-{int(mtime)}"'


class Handler(BaseHTTPRequestHandler):
    server_version = f"PeekServer/{__version__}"
    # HTTP/1.1 → keep-alive. The default (HTTP/1.0) closed the TCP connection after EVERY
    # response, so each of the hundreds of small thumb/metadata/range requests a review client
    # fires paid a fresh Wi-Fi handshake — measured ~150 ms per cached thumb vs 3 ms on loopback.
    # Safe because every response path sets Content-Length (and _serve_file closes the connection
    # if it ever under-writes, so framing can't desync).
    protocol_version = "HTTP/1.1"
    timeout = 60          # idle keep-alive connections release their thread

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

    def _guarded(self, fn):
        """Route dispatch safety net. An unhandled exception used to drop the connection with no
        status line at all — the client saw a bare network error, and under keep-alive it would
        also desync the next request on the socket. Bad input now gets a 4xx JSON, surprises a 500."""
        try:
            fn()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True     # client went away (player scrub/abort) — not an error
        except ValueError as e:              # bad query param, malformed JSON body
            self._error_response(400, str(e))
        except Exception as e:
            self._error_response(500, f"{type(e).__name__}: {e}")

    def _error_response(self, code, msg):
        # Headers may already be on the wire; don't trust the connection's framing after this.
        self.close_connection = True
        try:
            self._json({"error": msg}, code)
        except Exception:
            pass

    # ---- GET ----
    def do_GET(self):
        self._guarded(self._get)

    def _get(self):
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
        self._guarded(self._post)

    def _post(self):
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
        path, ftype, mtime = db.serving_info(mid)
        if not path:
            return self._notfound()
        dst = media.thumb_path(_CFG["thumbCache"], mid)
        # Fast path: a cached thumb at least as new as the DB-recorded source mtime is served
        # WITHOUT touching the source volume. (Stat'ing the original per request meant every
        # cached thumb still hit the slow/possibly-spun-down drive — the module's whole purpose
        # defeated.) The original is only read when a (re)generation is actually needed.
        if not media.cache_is_fresh(dst, mtime):
            if not media.ensure_thumb(path, dst, ftype, _CFG.get("thumbSize", 512)):
                return self._notfound()  # audio / failed → UI shows a glyph
        with open(dst, "rb") as f:
            return self._bytes(f.read(), "image/jpeg")

    def _serve_full(self, mid):
        path, _, _ = db.serving_info(mid)
        if not path or not os.path.isfile(path):
            return self._notfound()
        self._serve_file(path, _ctype(path), variant="orig",
                         cache_control="public, max-age=86400")

    def _serve_preview(self, mid):
        """Stream a video via its lightweight 720p faststart proxy — but NEVER block the player.
        If the proxy is cached, serve it (instant start, smooth — and without stat'ing the
        original, so a spun-down source drive can't stall the request). If not, kick the
        transcode in the BACKGROUND and serve the original right now, so the inline player plays
        immediately (like /full); the next view gets the fast proxy. Non-video falls through to
        the original. The ETag variant + If-Range handling in _serve_file keep the original→proxy
        switch safe for clients holding Range state."""
        path, ftype, mtime = db.serving_info(mid)
        if not path:
            return self._notfound()
        if ftype == "video":
            dst = media.proxy_path(_CFG["proxyCache"], mid)
            if media.cache_is_fresh(dst, mtime):
                return self._serve_file(dst, "video/mp4", variant="proxy",
                                        cache_control="no-cache")
            if not os.path.isfile(path):
                return self._notfound()
            media.ensure_video_proxy_async(path, dst, _CFG.get("ffmpegBin", "ffmpeg"),
                                           _CFG.get("proxyHeight", 720), _CFG.get("proxyMaxBitrateK", 4000))
            return self._serve_file(path, _ctype(path), variant="orig",
                                    cache_control="no-cache")
        if not os.path.isfile(path):
            return self._notfound()
        return self._serve_file(path, _ctype(path), variant="orig", cache_control="no-cache")

    def _serve_file(self, path, ctype, variant="orig", cache_control="public, max-age=86400"):
        try:
            st = os.stat(path)
        except OSError:
            return self._notfound()
        size = st.st_size
        etag = file_etag(variant, size, st.st_mtime)

        def validators():
            self.send_header("ETag", etag)
            self.send_header("Cache-Control", cache_control)
            self.send_header("Accept-Ranges", "bytes")

        # Conditional GET → 304 (no body): lets clients revalidate a held copy for one cheap
        # round trip instead of re-downloading a multi-MB original on every overlay view.
        inm = self.headers.get("If-None-Match")
        if inm and (inm.strip() == "*" or etag in [t.strip() for t in inm.split(",")]):
            self.send_response(304)
            validators()
            self.end_headers()
            return

        rng = self.headers.get("Range")
        # If-Range: only honor Range when the client's validator still matches what we'd serve
        # NOW — otherwise (e.g. /preview switched original→proxy) send the full new body.
        if_range = self.headers.get("If-Range")
        if if_range and if_range.strip() != etag:
            rng = None
        r = parse_range(rng, size)
        if r == "unsatisfiable":
            self.send_response(416)
            validators()
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if r:
            start, end = r
            length = end - start + 1
            self.send_response(206)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            validators()
            self.send_header("Content-Length", str(length))
            self.end_headers()
            with open(path, "rb") as f:
                f.seek(start)
                written = _copy(f, self.wfile, length)
        else:
            length = size
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            validators()
            self.send_header("Content-Length", str(size))
            self.end_headers()
            with open(path, "rb") as f:
                written = _copy(f, self.wfile, size)
        if written != length:
            # File shrank mid-serve: we promised Content-Length bytes and can't deliver — drop
            # the connection rather than desync keep-alive framing for the next response.
            self.close_connection = True


def _copy(src, dst, length, chunk=1 << 16) -> int:
    remaining = length
    while remaining > 0:
        buf = src.read(min(chunk, remaining))
        if not buf:
            break
        dst.write(buf)
        remaining -= len(buf)
    return length - remaining


def _first(q, key, default=None):
    v = q.get(key)
    return v[0] if v else default


def _ctype(path):
    import mimetypes
    ext = os.path.splitext(path)[1].lower()
    extra = {".heic": "image/heic", ".heif": "image/heif", ".mov": "video/quicktime",
             ".m4v": "video/x-m4v", ".js": "application/javascript", ".css": "text/css"}
    return extra.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"
