"""Claude XRay — view/edit Claude Code config files with inline learning context.

Run:
    python app.py [--cwd PATH] [--port 8765]

Then open http://127.0.0.1:8765 in a browser.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import sys
import time
import webbrowser
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

HERE = Path(__file__).resolve().parent
DESCRIPTIONS = json.loads((HERE / "descriptions.json").read_text())

USER_ROOT = Path.home() / ".claude"
PROJECT_ROOT: Path | None = None  # set in main()

# Files that contain secrets or are not safe to hand-edit.
READONLY_PATTERNS = {
    "projects/",          # transcripts
    "shell-snapshots/",
    "statsig/",
    "ide/",
}
READONLY_FILES_AT_HOME = {
    ".claude.json",       # MCP OAuth tokens live here — viewable but read-only
}

MAX_EDIT_BYTES = 1_000_000  # 1 MB hard cap on save

app = FastAPI(title="Claude XRay")


# ---------- helpers ----------

def roots() -> dict[str, Path]:
    out = {"user": USER_ROOT}
    if PROJECT_ROOT and PROJECT_ROOT.exists():
        out["project"] = PROJECT_ROOT
    return out


def resolve_safe(root_name: str, rel: str) -> Path:
    """Resolve a path strictly inside the named root. Reject traversal & symlinks out."""
    rs = roots()
    if root_name not in rs:
        raise HTTPException(400, f"unknown root: {root_name}")
    root = rs[root_name].resolve()
    candidate = (root / rel).resolve() if rel else root
    try:
        candidate.relative_to(root)
    except ValueError:
        raise HTTPException(400, "path escapes root")
    return candidate


def description_for(rel: str, is_dir: bool) -> str | None:
    """Best-match description for a path (relative to root, no leading slash)."""
    if not rel:
        return "Root directory."
    key_dir = rel.rstrip("/") + "/"
    if is_dir and key_dir in DESCRIPTIONS:
        return DESCRIPTIONS[key_dir]
    if rel in DESCRIPTIONS:
        return DESCRIPTIONS[rel]
    name = Path(rel).name
    if name in DESCRIPTIONS:
        return DESCRIPTIONS[name]
    # Prefix matches (e.g. settings.json.backup-2026...)
    for k, v in DESCRIPTIONS.items():
        if k.endswith("-") and name.startswith(k):
            return v
    # Glob-ish: projects/*.jsonl
    if name.endswith(".jsonl") and rel.startswith("projects/"):
        return DESCRIPTIONS.get("projects/*.jsonl")
    return None


def is_readonly(root_name: str, rel: str) -> bool:
    if root_name == "user":
        if rel in READONLY_FILES_AT_HOME:
            return True
    for prefix in READONLY_PATTERNS:
        if rel == prefix.rstrip("/") or rel.startswith(prefix):
            return True
    return False


def detect_kind(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in {".json", ".jsonl"}:
        return "json"
    if suffix in {".md", ".markdown"}:
        return "markdown"
    if suffix in {".yml", ".yaml"}:
        return "yaml"
    if suffix in {".sh", ".bash", ".zsh"}:
        return "shell"
    if suffix in {".py"}:
        return "python"
    if suffix in {".js", ".mjs"}:
        return "javascript"
    if suffix in {".ts"}:
        return "typescript"
    return "text"


def build_tree(root: Path, root_name: str, max_depth: int = 6) -> dict:
    """Recursive tree of root. Skips noisy stuff like .DS_Store."""
    def walk(p: Path, depth: int) -> dict:
        rel = str(p.relative_to(root)) if p != root else ""
        node: dict = {
            "name": p.name or root_name,
            "path": rel,
            "isDir": p.is_dir(),
            "size": None if p.is_dir() else _safe_size(p),
            "mtime": _safe_mtime(p),
            "readonly": is_readonly(root_name, rel),
            "description": description_for(rel, p.is_dir()),
        }
        if p.is_dir() and depth < max_depth:
            children = []
            try:
                entries = sorted(p.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))
            except PermissionError:
                entries = []
            for child in entries:
                if child.name in {".DS_Store"}:
                    continue
                # Skip following symlinks that point outside root
                if child.is_symlink():
                    try:
                        child.resolve().relative_to(root.resolve())
                    except ValueError:
                        continue
                children.append(walk(child, depth + 1))
            node["children"] = children
        return node

    return walk(root, 0)


def _safe_size(p: Path) -> int | None:
    try:
        return p.stat().st_size
    except OSError:
        return None


def _safe_mtime(p: Path) -> float | None:
    try:
        return p.stat().st_mtime
    except OSError:
        return None


# ---------- API ----------

@app.get("/api/roots")
def api_roots():
    return {name: str(p) for name, p in roots().items()}


@app.get("/api/tree")
def api_tree(root: str = Query("user")):
    rs = roots()
    if root not in rs:
        raise HTTPException(404, f"root '{root}' not available")
    if not rs[root].exists():
        return JSONResponse({"name": root, "path": "", "isDir": True, "missing": True, "children": []})
    return build_tree(rs[root], root)


@app.get("/api/file")
def api_file_get(root: str = Query(...), path: str = Query("")):
    full = resolve_safe(root, path)
    if not full.exists():
        raise HTTPException(404, "not found")
    if full.is_dir():
        raise HTTPException(400, "is a directory")

    size = full.stat().st_size
    if size > 5_000_000:
        return {
            "path": path,
            "root": root,
            "tooLarge": True,
            "size": size,
            "readonly": True,
            "kind": detect_kind(full),
            "description": description_for(path, False),
            "content": "",
        }

    try:
        content = full.read_text(encoding="utf-8")
        binary = False
    except UnicodeDecodeError:
        content = ""
        binary = True

    return {
        "path": path,
        "root": root,
        "size": size,
        "mtime": full.stat().st_mtime,
        "readonly": is_readonly(root, path) or binary,
        "binary": binary,
        "kind": detect_kind(full),
        "description": description_for(path, False),
        "content": content,
    }


class FilePut(BaseModel):
    content: str


@app.put("/api/file")
def api_file_put(payload: FilePut, root: str = Query(...), path: str = Query(...)):
    if is_readonly(root, path):
        raise HTTPException(403, "read-only path")
    full = resolve_safe(root, path)
    if full.is_dir():
        raise HTTPException(400, "is a directory")
    data = payload.content.encode("utf-8")
    if len(data) > MAX_EDIT_BYTES:
        raise HTTPException(413, f"file too large to save (>{MAX_EDIT_BYTES} bytes)")

    full.parent.mkdir(parents=True, exist_ok=True)

    # Backup if it already exists
    if full.exists():
        bak = full.with_suffix(full.suffix + f".xraybak-{int(time.time())}")
        shutil.copy2(full, bak)

    # Atomic write via temp + rename
    tmp = full.with_suffix(full.suffix + ".xraytmp")
    tmp.write_bytes(data)
    os.replace(tmp, full)

    return {"ok": True, "size": len(data), "mtime": full.stat().st_mtime}


# ---------- static frontend ----------

app.mount("/static", StaticFiles(directory=str(HERE / "static")), name="static")


@app.get("/")
def index():
    return FileResponse(str(HERE / "static" / "index.html"))


# ---------- main ----------

def main():
    global PROJECT_ROOT
    parser = argparse.ArgumentParser(description="Claude XRay")
    parser.add_argument("--cwd", default=os.getcwd(), help="Project root to look for .claude/ in (default: cwd)")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--no-browser", action="store_true", help="Don't auto-open browser")
    args = parser.parse_args()

    project = Path(args.cwd).expanduser().resolve() / ".claude"
    PROJECT_ROOT = project

    print(f"  user root:    {USER_ROOT} {'(exists)' if USER_ROOT.exists() else '(MISSING)'}")
    print(f"  project root: {project} {'(exists)' if project.exists() else '(none)'}")
    url = f"http://{args.host}:{args.port}"
    print(f"  serving at:   {url}")

    if not args.no_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
