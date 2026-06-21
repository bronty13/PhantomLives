#!/usr/bin/env python3
"""
authorize.py — one-time interactive minting of an Apple Music **Music User Token**.

The Music User Token cannot be obtained headless: Apple requires the user to sign
in interactively via MusicKit. This script signs a developer token, serves a tiny
local MusicKit-JS page, opens it in your browser, you click "Authorize" and sign
in to Apple Music, and the resulting Music User Token is captured back and saved
to `music_user_token.json` (gitignored). build_playlist.py then reuses it
(~6 months) until it needs re-minting.

Run:  python3 authorize.py    (then click Authorize in the browser tab)
"""

from __future__ import annotations

import http.server
import json
import os
import socket
import sys
import threading
import webbrowser

# --- venv bootstrap (re-exec self into the shared .venv) ------------------- #
_HERE = os.path.dirname(os.path.abspath(__file__))
_VENV_PY = os.path.join(_HERE, ".venv", "bin", "python")


def _ensure_venv() -> None:
    in_venv = os.path.abspath(sys.executable) == os.path.abspath(_VENV_PY)
    if not in_venv:
        if not os.path.exists(_VENV_PY):
            import venv

            print("Creating virtual environment (.venv)…", file=sys.stderr)
            venv.EnvBuilder(with_pip=True).create(os.path.join(_HERE, ".venv"))
        os.execv(_VENV_PY, [_VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])
    try:
        import jwt  # noqa: F401
    except ImportError:
        import subprocess

        print("Installing dependencies (PyJWT, cryptography)…", file=sys.stderr)
        subprocess.check_call([_VENV_PY, "-m", "pip", "install", "--quiet", "--upgrade", "pip"])
        subprocess.check_call([_VENV_PY, "-m", "pip", "install", "--quiet",
                               "PyJWT>=2.8", "cryptography>=42.0"])
        os.execv(_VENV_PY, [_VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])


_PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>Authorize Apple Music</title>
<style>body{{font-family:-apple-system,system-ui,sans-serif;max-width:40rem;margin:4rem auto;text-align:center;color:#222}}
button{{font-size:1.2rem;padding:.8rem 1.6rem;border-radius:.6rem;border:0;background:#fa2d48;color:#fff;cursor:pointer}}
.muted{{color:#888}}</style></head>
<body>
<h1>Complete Playlist Builder</h1>
<p>Click below, sign in to Apple Music, and allow access.<br>
<span class="muted">This grants a long-lived token so the tool can build your playlists.</span></p>
<button id="go">Authorize Apple Music</button>
<p id="status" class="muted"></p>
<script src="https://js-cdn.music.apple.com/musickit/v3/musickit.js" data-web-components async></script>
<script>
document.addEventListener('musickitloaded', async function () {{
  try {{
    await MusicKit.configure({{
      developerToken: "{DEV_TOKEN}",
      app: {{ name: 'Complete Playlist Builder', build: '1.0.0' }}
    }});
  }} catch (e) {{ document.getElementById('status').textContent = 'Configure failed: ' + e; return; }}
  const music = MusicKit.getInstance();
  document.getElementById('go').addEventListener('click', async function () {{
    document.getElementById('status').textContent = 'Opening Apple sign-in…';
    try {{
      const userToken = await music.authorize();
      const r = await fetch('/capture', {{
        method: 'POST', headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{ music_user_token: userToken }})
      }});
      document.body.innerHTML = r.ok
        ? '<h1>✅ Authorized</h1><p>Token saved. You can close this tab and return to the terminal.</p>'
        : '<h1>⚠️ Capture failed</h1><p>See the terminal.</p>';
    }} catch (e) {{
      document.getElementById('status').textContent = 'Authorization cancelled/failed: ' + e;
    }}
  }});
}});
</script>
</body></html>"""


def main() -> int:
    _ensure_venv()
    import build_playlist as bp  # noqa: E402  (after venv is ready)

    cfg = bp.load_config()
    dev_token = bp.sign_developer_token(cfg)
    page = _PAGE.replace("{DEV_TOKEN}", dev_token)

    captured: dict = {}
    stop = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):  # quiet
            pass

        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(page.encode("utf-8"))

        def do_POST(self):
            if self.path != "/capture":
                self.send_response(404)
                self.end_headers()
                return
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            token = body.get("music_user_token")
            if token:
                captured["token"] = token
            self.send_response(200 if token else 400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}' if token else b'{"ok":false}')
            stop.set()

    # Pick a free port (MusicKit JS works fine from http://127.0.0.1).
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    httpd = http.server.HTTPServer(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{port}/"
    print(f"\nOpening {url}\nIf it doesn't open automatically, paste that URL into your browser.")
    print("Click 'Authorize Apple Music', sign in, and allow access.\n")
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        webbrowser.open(url)
    except Exception:
        pass

    if not stop.wait(timeout=600):
        print("Timed out after 10 minutes without authorization.", file=sys.stderr)
        httpd.shutdown()
        return 1
    httpd.shutdown()

    if not captured.get("token"):
        print("No token captured.", file=sys.stderr)
        return 1
    with open(bp._USER_TOKEN_FILE, "w", encoding="utf-8") as fh:
        json.dump({"music_user_token": captured["token"]}, fh)
    os.chmod(bp._USER_TOKEN_FILE, 0o600)
    print(f"✅ Music User Token saved to {bp._USER_TOKEN_FILE}")
    print("You can now run:  python3 build_playlist.py --artist \"...\" --playlist-name \"...\"")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
