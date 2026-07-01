"""Config loading. Real config lives in config.json (gitignored — may carry machine paths);
config.example.json is the committed template. Falls back to sensible defaults.
"""
import json
import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

DEFAULTS = {
    "port": 8788,
    "bind": "0.0.0.0",                       # LAN-reachable; any Mac/iPad can connect
    "dbPath": "~/Library/Application Support/PeekServer/peekserver.sqlite",
    "thumbCache": "~/Library/Caches/PeekServer/thumbs",
    "thumbSize": 512,                        # max thumbnail dimension (px)
    "scanIntervalMinutes": 15,               # auto-rescan every N min so newly-staged files appear
                                             # without a manual scan (0 = disable, scan only at startup)
    # --- Video streaming proxies (smooth review playback over LAN; needs ffmpeg) ---
    "proxyCache": "~/Library/Caches/PeekServer/proxies",  # cached 720p faststart MP4s
    "ffmpegBin": "ffmpeg",                   # PATH name or absolute path to ffmpeg
    "proxyHeight": 720,                      # proxy max height (px); never upscaled
    "proxyMaxBitrateK": 4000,                # hard video-bitrate cap (kbps) so it always fits the pipe
    "warmProxies": True,                     # background-generate proxies for videos after each scan
    "roots": [],                             # [{path,label,kind}]
    # --- Basic Auth (both empty = open). Password stored only as a SHA-256 hash. ---
    "authUser": "",
    "authPasswordSHA256": "",
    # --- Phase 2: keep→Photos import worker (runs on the host with the Photos library) ---
    "osxphotosBin": "osxphotos",             # PATH or absolute; delegates the PhotoKit import
    "exiftoolBin": "exiftool",               # used to embed XMP:Rating for favorites
    "keptAudioDir": "~/Downloads/PeekServer/Kept Audio",   # Photos can't hold audio → keep-export here
    "stagingDir": "~/Library/Caches/PeekServer/staging",   # favorites staged here (rating embedded)
    "purplePeekDb": "~/Library/Application Support/PurplePeek/purplepeek.sqlite",  # decision migration source
}


def _expand(p: str) -> str:
    return str(Path(os.path.expanduser(p)))


def config_path() -> Path:
    """Where the real config.json is: $PEEKSERVER_CONFIG, else project root, else App Support."""
    env = os.environ.get("PEEKSERVER_CONFIG")
    if env:
        return Path(env)
    root_cfg = PROJECT_ROOT / "config.json"
    if root_cfg.exists():
        return root_cfg
    return Path(_expand("~/Library/Application Support/PeekServer/config.json"))


def load() -> dict:
    cfg = dict(DEFAULTS)
    p = config_path()
    if p.exists():
        cfg.update(json.loads(p.read_text(encoding="utf-8")))
    for k in ("dbPath", "thumbCache", "proxyCache", "keptAudioDir", "stagingDir", "purplePeekDb"):
        cfg[k] = _expand(cfg[k])
    for k in ("osxphotosBin", "exiftoolBin", "ffmpegBin"):   # expand ~ but leave bare PATH names alone
        if cfg[k].startswith("~") or cfg[k].startswith("/"):
            cfg[k] = _expand(cfg[k])
    # Normalize roots: expand paths, default label to basename, default kind.
    norm = []
    for r in cfg.get("roots", []):
        path = _expand(r["path"])
        norm.append({
            "path": path,
            "label": r.get("label") or os.path.basename(path.rstrip("/")),
            "kind": r.get("kind", "photos"),
        })
    cfg["roots"] = norm
    return cfg
