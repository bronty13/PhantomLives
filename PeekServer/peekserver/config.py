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
    "roots": [],                             # [{path,label,kind}]
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
    cfg["dbPath"] = _expand(cfg["dbPath"])
    cfg["thumbCache"] = _expand(cfg["thumbCache"])
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
