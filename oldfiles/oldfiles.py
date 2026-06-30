#!/usr/bin/env python3
"""
oldfiles — list, and optionally purge, files older than a date threshold.

A scriptable, headless companion to PurpleTree's GUI. Its primary purpose in this
repo is the **post-backup reclamation step**: after PurpleAttic's `pattic` ad-hoc
B2 backup has run and you have *verified* the copies, run `oldfiles` against the
source folder to purge the aged local originals and reclaim disk space.

Safety model (this tool deletes files, so the defaults are conservative):

  * **Dry-run by default.** With no action flag it only *lists* matches — it
    never deletes. You see the full list and the reclaimable total first.
  * **--delete** moves matches to the Trash (recoverable; via Send2Trash). NOTE:
    the Trash still occupies disk until you empty it — so for *reclaiming space*
    after a verified backup, use --delete-permanent.
  * **--delete-permanent** removes matches with os.remove (irreversible — this is
    the one that actually frees space).
  * A **protected-path guard** refuses to scan/delete filesystem roots, OS system
    folders, the home root, and similar — even if you point the tool at them.
  * Deletion asks for confirmation unless --yes, and refuses to delete from a
    non-interactive shell without --yes (so a stray pipe can't purge silently).
  * Only **regular files** are ever deleted — directories and symlinks are left
    alone.

Created-date is the default age field (st_birthtime on macOS); use --by to switch
to modified/accessed time.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

__version__ = "1.1.0"

APP_NAME = "oldfiles"
# Per the repo's default-output rule: user-visible reports default here.
DEFAULT_REPORT_DIR = Path.home() / "Downloads" / APP_NAME


# ─────────────────────────────────────────────────────────────────────────────
# Pretty output helpers
# ─────────────────────────────────────────────────────────────────────────────

def _supports_color() -> bool:
    return sys.stderr.isatty() and os.environ.get("NO_COLOR") is None


_C = {
    "reset": "\033[0m", "bold": "\033[1m", "dim": "\033[2m",
    "green": "\033[32m", "yellow": "\033[33m", "red": "\033[31m", "cyan": "\033[36m",
} if _supports_color() else {k: "" for k in
                             ("reset", "bold", "dim", "green", "yellow", "red", "cyan")}


def info(msg: str) -> None:
    print(f"{_C['cyan']}→{_C['reset']} {msg}", file=sys.stderr)


def warn(msg: str) -> None:
    print(f"{_C['yellow']}⚠{_C['reset']} {msg}", file=sys.stderr)


def die(msg: str, code: int = 2) -> "NoReturn":  # type: ignore[name-defined]
    print(f"{_C['red']}✗ error:{_C['reset']} {msg}", file=sys.stderr)
    sys.exit(code)


# ─────────────────────────────────────────────────────────────────────────────
# Pure parsing / formatting helpers (unit-tested)
# ─────────────────────────────────────────────────────────────────────────────

# Approximate calendar units in days. Documented in README — "1y" means 365 days,
# not "this date last year". Good enough for an age-based purge, and dependency-free.
_DURATION_DAYS = {"y": 365.0, "mo": 30.0, "w": 7.0, "d": 1.0, "h": 1.0 / 24.0}
_DURATION_RE = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s*"
    r"(y|yr|yrs|year|years|mo|mon|month|months|w|wk|week|weeks|"
    r"d|day|days|h|hr|hrs|hour|hours)?\s*$",
    re.IGNORECASE,
)


def parse_duration(text: str) -> float:
    """Parse '1y' / '6mo' / '90d' / '2w' / '48h' (or a bare integer = days) → seconds."""
    m = _DURATION_RE.match(text)
    if not m:
        raise ValueError(
            f"invalid duration {text!r} — use forms like 1y, 6mo, 2w, 90d, 48h"
        )
    qty = float(m.group(1))
    unit = (m.group(2) or "d").lower()
    if unit.startswith("y"):
        key = "y"
    elif unit.startswith("mo") or unit.startswith("mon"):
        key = "mo"
    elif unit.startswith("w"):
        key = "w"
    elif unit.startswith("h"):
        key = "h"
    else:
        key = "d"
    return qty * _DURATION_DAYS[key] * 86400.0


_SIZE_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([kmgt]?)i?b?\s*$", re.IGNORECASE)
_SIZE_MULT = {"": 1, "k": 1024, "m": 1024 ** 2, "g": 1024 ** 3, "t": 1024 ** 4}


def parse_size(text: str) -> int:
    """Parse '100M' / '1G' / '500K' / '2048' (bytes) → an integer byte count (1024-based)."""
    m = _SIZE_RE.match(text)
    if not m:
        raise ValueError(f"invalid size {text!r} — use forms like 500K, 100M, 2G")
    return int(float(m.group(1)) * _SIZE_MULT[m.group(2).lower()])


def human_size(n: int) -> str:
    f = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if f < 1024 or unit == "TB":
            return f"{f:.0f} {unit}" if unit == "B" else f"{f:.1f} {unit}"
        f /= 1024
    return f"{f:.1f} TB"


def human_age(seconds: float) -> str:
    days = seconds / 86400.0
    if days >= 365:
        return f"{days / 365:.1f}y"
    if days >= 30:
        return f"{days / 30:.0f}mo"
    if days >= 1:
        return f"{days:.0f}d"
    return f"{seconds / 3600:.0f}h"


def file_time(st: os.stat_result, field: str) -> float:
    """Return the chosen timestamp (epoch seconds). 'created' uses st_birthtime
    where available (macOS), falling back to mtime on platforms without it."""
    if field == "modified":
        return st.st_mtime
    if field == "accessed":
        return st.st_atime
    # created
    return float(getattr(st, "st_birthtime", st.st_mtime))


# ─────────────────────────────────────────────────────────────────────────────
# Protected-path guard (unit-tested) — mirrors PurpleTree's philosophy
# ─────────────────────────────────────────────────────────────────────────────

# Structural locations we refuse to scan-as-source or delete. We protect the
# *roots* themselves; deleting aged files *inside* e.g. ~/Downloads is the whole
# point, so contents are fine — only the structural anchors are off-limits.
def _protected_roots() -> set:
    home = str(Path.home())
    roots = {
        "/", "/System", "/Library", "/usr", "/usr/local", "/bin", "/sbin",
        "/etc", "/var", "/private", "/private/var", "/Applications", "/cores",
        "/opt", "/dev", "/Volumes", "/Network", "/tmp", "/private/tmp",
        home,
        f"{home}/Library",
    }
    return {os.path.normpath(p) for p in roots}


def is_protected(path: str) -> tuple[bool, str]:
    """Return (blocked, reason). Resolves symlinks/.. first so traversal can't dodge it."""
    try:
        resolved = os.path.realpath(path)
    except OSError:
        resolved = os.path.normpath(path)
    norm = os.path.normpath(resolved)
    roots = _protected_roots()
    if norm in roots:
        return True, f"refusing to touch a protected location: {norm}"
    # A path with no real parent (directly under '/') is treated as system-level.
    parent = os.path.dirname(norm)
    if parent == "/" and norm != "/":
        # e.g. /Users, /opt — directly under root; treat as protected anchor.
        return True, f"refusing to touch a top-level system path: {norm}"
    return False, ""


# ─────────────────────────────────────────────────────────────────────────────
# Walk + match
# ─────────────────────────────────────────────────────────────────────────────

class Match:
    __slots__ = ("path", "size", "ts", "field")

    def __init__(self, path: str, size: int, ts: float, field: str):
        self.path = path
        self.size = size
        self.ts = ts
        self.field = field


def walk_files(
    source: str,
    *,
    max_depth,          # int or None (None = unlimited)
    include_hidden: bool,
    follow_symlinks: bool,
    exts,               # set[str] (lowercase, no dot) or None
    glob,               # str or None
    min_size: int,
):
    """Yield absolute paths of regular files under *source* honoring the filters.

    Depth: a file directly in *source* is depth 0; one level down is depth 1; etc.
    max_depth=0 means source's own files only (no descent); None means unlimited.
    """
    source = os.path.abspath(source)
    sep_count_base = source.rstrip(os.sep).count(os.sep)

    for dirpath, dirnames, filenames in os.walk(source, followlinks=follow_symlinks):
        depth = dirpath.rstrip(os.sep).count(os.sep) - sep_count_base

        # Prune hidden directories (and, when at the depth limit, stop descending).
        if not include_hidden:
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        if max_depth is not None and depth >= max_depth:
            dirnames[:] = []

        for name in filenames:
            if not include_hidden and name.startswith("."):
                continue
            full = os.path.join(dirpath, name)
            # Only regular files; never traverse-delete through symlinks unless asked.
            if os.path.islink(full) and not follow_symlinks:
                continue
            if not os.path.isfile(full):
                continue
            if exts is not None:
                ext = os.path.splitext(name)[1].lstrip(".").lower()
                if ext not in exts:
                    continue
            if glob is not None and not _fnmatch(name, glob):
                continue
            try:
                st = os.stat(full)
            except OSError:
                continue
            if st.st_size < min_size:
                continue
            yield full, st


def _fnmatch(name: str, pattern: str) -> bool:
    import fnmatch
    return fnmatch.fnmatch(name, pattern)


def collect_matches(source: str, cutoff_epoch: float, field: str, **walk_kw):
    """Return Match objects for files whose chosen timestamp is older than cutoff."""
    out = []
    for full, st in walk_files(source, **walk_kw):
        ts = file_time(st, field)
        if ts < cutoff_epoch:
            out.append(Match(full, st.st_size, ts, field))
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Trash bootstrap (lazy — only when --delete is actually used)
# ─────────────────────────────────────────────────────────────────────────────

def _venv_python() -> str:
    venv = Path(__file__).resolve().parent / ".venv"
    py = venv / "bin" / "python3"
    if not py.exists():
        info("setting up Trash support (one-time)…")
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        subprocess.run([str(py), "-m", "pip", "install", "-q", "--upgrade", "pip"],
                       check=True)
        subprocess.run([str(py), "-m", "pip", "install", "-q", "Send2Trash>=1.8.2"],
                       check=True)
    return str(py)


def _ensure_send2trash():
    """Import send2trash, bootstrapping a local .venv + re-exec if needed."""
    try:
        from send2trash import send2trash  # type: ignore
        return send2trash
    except ImportError:
        pass
    if os.environ.get("OLDFILES_BOOTSTRAPPED") == "1":
        die("Send2Trash is unavailable even after venv setup. "
            "Install it manually (pip install Send2Trash) or use --delete-permanent.")
    venv_py = _venv_python()
    os.environ["OLDFILES_BOOTSTRAPPED"] = "1"
    os.execv(venv_py, [venv_py, os.path.abspath(__file__), *sys.argv[1:]])


# ─────────────────────────────────────────────────────────────────────────────
# Deletion
# ─────────────────────────────────────────────────────────────────────────────

def _on_separate_volume(path: str) -> bool:
    """True if `path` lives on a different mounted volume than the user's home
    directory (where ~/.Trash is reliable). macOS Trash on a separate/external
    volume is slow, its `.Trashes` is usually TCC-protected (so progress is
    invisible) and it doesn't free space until emptied — so we steer those to
    --delete-permanent rather than appear to hang. Best-effort: returns False if
    either path can't be stat'd."""
    try:
        return os.stat(path).st_dev != os.stat(os.path.expanduser("~")).st_dev
    except OSError:
        return False


def do_delete(matches, permanent: bool, progress_every: int = 1000):
    """Delete matched files. Returns (removed_paths, failures[(path, reason)]).
    Emits a progress line every `progress_every` files so a long run is never
    silent (set 0 to disable)."""
    removed, failed = [], []
    send2trash = None if permanent else _ensure_send2trash()
    total = len(matches)
    for i, m in enumerate(matches, 1):
        blocked, reason = is_protected(m.path)
        if blocked:
            failed.append((m.path, reason))
            continue
        try:
            if permanent:
                os.remove(m.path)
            else:
                send2trash(m.path)
            removed.append(m.path)
        except Exception as e:  # noqa: BLE001 — surface any FS error per-file
            failed.append((m.path, str(e)))
        if progress_every and i % progress_every == 0:
            info(f"  …{i}/{total} processed ({len(removed)} removed)")
    return removed, failed


# ─────────────────────────────────────────────────────────────────────────────
# Reporting / printing
# ─────────────────────────────────────────────────────────────────────────────

def print_table(matches, now: float) -> None:
    if not matches:
        return
    width_path = min(max((len(m.path) for m in matches), default=4), 100)
    header = f"{'AGE':>6}  {'SIZE':>9}  {'DATE':<16}  PATH"
    print(f"{_C['bold']}{header}{_C['reset']}")
    for m in matches:
        age = human_age(now - m.ts)
        date = datetime.fromtimestamp(m.ts).strftime("%Y-%m-%d %H:%M")
        print(f"{age:>6}  {human_size(m.size):>9}  {date:<16}  {m.path}")


def write_report(matches, fmt: str, path: Path, now: float, field: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = [{
        "path": m.path,
        "size_bytes": m.size,
        "size_human": human_size(m.size),
        f"{field}_time": datetime.fromtimestamp(m.ts).isoformat(),
        "age": human_age(now - m.ts),
    } for m in matches]
    if fmt == "json":
        path.write_text(json.dumps(rows, indent=2))
    elif fmt == "csv":
        with path.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else
                               ["path", "size_bytes", "size_human", f"{field}_time", "age"])
            w.writeheader()
            w.writerows(rows)
    else:  # txt
        with path.open("w") as f:
            for m in matches:
                f.write(f"{m.path}\n")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog=APP_NAME,
        description="List (and optionally purge) files older than a date threshold. "
                    "Dry-run by default — nothing is deleted unless you pass --delete "
                    "or --delete-permanent.",
        epilog="Examples:\n"
               "  oldfiles ~/Downloads --older-than 1y\n"
               "  oldfiles ~/Logs --older-than 90d --by modified --max-depth 2\n"
               "  oldfiles ~/StagedForB2 --older-than 1y --delete-permanent --yes\n"
               "\nReclaim-space note: --delete moves files to the Trash (still on disk\n"
               "until emptied). To actually free space after a verified backup, use\n"
               "--delete-permanent.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("source", help="directory to scan")

    g_age = p.add_argument_group("age criteria")
    g_age.add_argument("--older-than", default="1y", metavar="DURATION",
                       help="match files older than this (default: 1y). "
                            "Units: y, mo, w, d, h — e.g. 6mo, 90d, 48h.")
    g_age.add_argument("--before", metavar="YYYY-MM-DD",
                       help="match files older than this absolute date "
                            "(overrides --older-than).")
    g_age.add_argument("--by", choices=("created", "modified", "accessed"),
                       default="created",
                       help="which timestamp to age by (default: created).")

    g_rec = p.add_argument_group("recursion")
    g_rec.add_argument("--max-depth", type=int, default=None, metavar="N",
                       help="descend at most N levels below SOURCE. "
                            "0 = SOURCE's own files only; default: unlimited (all levels).")
    g_rec.add_argument("--follow-symlinks", action="store_true",
                       help="follow symlinked directories (default: off).")
    g_rec.add_argument("--include-hidden", action="store_true",
                       help="include dotfiles and dot-directories (default: skip).")

    g_filt = p.add_argument_group("filters")
    g_filt.add_argument("--ext", metavar="EXT[,EXT...]",
                        help="only files with these extensions, e.g. log,tmp,zip")
    g_filt.add_argument("--glob", metavar="PATTERN",
                        help="only files whose name matches this glob, e.g. '*.log'")
    g_filt.add_argument("--min-size", default="0", metavar="SIZE",
                        help="only files at least this big, e.g. 100M, 1G (default: 0).")

    g_act = p.add_argument_group("actions (default: list only / dry-run)")
    g_act.add_argument("--delete", action="store_true",
                       help="move matches to the Trash (recoverable; still uses disk "
                            "until the Trash is emptied).")
    g_act.add_argument("--delete-permanent", action="store_true",
                       help="permanently delete matches (irreversible; frees space now).")
    g_act.add_argument("-y", "--yes", action="store_true",
                       help="skip the confirmation prompt before deleting.")

    g_out = p.add_argument_group("output")
    g_out.add_argument("--sort", choices=("age", "size", "name"), default="age",
                       help="sort order (default: age — oldest first).")
    g_out.add_argument("--reverse", action="store_true", help="reverse the sort order.")
    g_out.add_argument("--report", choices=("csv", "json", "txt"), metavar="FORMAT",
                       help="also write a report to ~/Downloads/oldfiles/ (or --output).")
    g_out.add_argument("--output", metavar="PATH", help="explicit report file path.")
    g_out.add_argument("--json", action="store_true",
                       help="print results as JSON to stdout (implies no table).")
    g_out.add_argument("-0", "--print0", action="store_true",
                       help="print NUL-separated paths to stdout (xargs -0 friendly).")
    g_out.add_argument("-q", "--quiet", action="store_true",
                       help="suppress the human table/summary (errors still shown).")

    p.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return p


def _sort_matches(matches, key: str, reverse: bool):
    if key == "size":
        matches.sort(key=lambda m: m.size, reverse=not reverse)  # largest first by default
    elif key == "name":
        matches.sort(key=lambda m: m.path.lower(), reverse=reverse)
    else:  # age — oldest first by default
        matches.sort(key=lambda m: m.ts, reverse=reverse)
    return matches


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    if args.delete and args.delete_permanent:
        die("choose only one of --delete (Trash) or --delete-permanent.")

    source = os.path.abspath(os.path.expanduser(args.source))
    if not os.path.isdir(source):
        die(f"source is not a directory: {source}")
    blocked, reason = is_protected(source)
    if blocked:
        die(reason)

    # Trash is unreliable on a separate/external volume: it's slow, its `.Trashes` is
    # usually TCC-protected (so progress is invisible), and it doesn't free space until
    # emptied. Refuse rather than appear to hang, and point at --delete-permanent.
    # (Incident: a 90d Trash purge of an external archive looked "stuck" for minutes
    # because its .Trashes was unreadable — it was actually trashing, just invisibly.)
    if args.delete and not args.delete_permanent and _on_separate_volume(source):
        die("--delete (Trash) isn't reliable on the external/separate volume holding:\n"
            f"    {source}\n"
            "  Its Trash is slow, usually unreadable (so progress is invisible), and doesn't\n"
            "  free space until emptied. Use --delete-permanent to delete and reclaim now.",
            code=1)

    # Resolve the cutoff.
    now = time.time()
    if args.before:
        try:
            cutoff = datetime.strptime(args.before, "%Y-%m-%d").timestamp()
        except ValueError:
            die(f"invalid --before date {args.before!r} — use YYYY-MM-DD")
    else:
        try:
            cutoff = now - parse_duration(args.older_than)
        except ValueError as e:
            die(str(e))

    try:
        min_size = parse_size(args.min_size)
    except ValueError as e:
        die(str(e))

    exts = None
    if args.ext:
        exts = {e.strip().lstrip(".").lower() for e in args.ext.split(",") if e.strip()}

    if args.max_depth is not None and args.max_depth < 0:
        die("--max-depth must be 0 or greater (omit it for unlimited).")

    # If we'll move to Trash, ensure Send2Trash is importable *before* scanning, so
    # a one-time venv bootstrap + re-exec doesn't print the file list twice.
    if args.delete and not args.delete_permanent:
        _ensure_send2trash()

    matches = collect_matches(
        source, cutoff, args.by,
        max_depth=args.max_depth,
        include_hidden=args.include_hidden,
        follow_symlinks=args.follow_symlinks,
        exts=exts,
        glob=args.glob,
        min_size=min_size,
    )
    _sort_matches(matches, args.sort, args.reverse)
    total_bytes = sum(m.size for m in matches)

    # ── Output the list ──────────────────────────────────────────────────────
    if args.json:
        print(json.dumps([{
            "path": m.path, "size_bytes": m.size,
            f"{args.by}_time": datetime.fromtimestamp(m.ts).isoformat(),
        } for m in matches], indent=2))
    elif args.print0:
        sys.stdout.write("".join(m.path + "\0" for m in matches))
    elif not args.quiet:
        print_table(matches, now)
    sys.stdout.flush()  # keep the list above the stderr summary in interactive use

    if args.report:
        out = Path(args.output) if args.output else (
            DEFAULT_REPORT_DIR /
            f"{APP_NAME}_{datetime.fromtimestamp(now).strftime('%Y%m%d_%H%M%S')}.{args.report}"
        )
        write_report(matches, args.report, out, now, args.by)
        info(f"report written: {out}")

    crit = (f"before {args.before}" if args.before
            else f"older than {args.older_than}")
    if not args.quiet and not args.json and not args.print0:
        info(f"{len(matches)} file(s) {crit} by {args.by} time · "
             f"{human_size(total_bytes)} total")

    if not matches:
        return 0

    # ── Optional deletion ────────────────────────────────────────────────────
    permanent = args.delete_permanent
    if not (args.delete or permanent):
        if not args.quiet and not args.json and not args.print0:
            info("dry run — nothing deleted. Re-run with --delete (Trash) or "
                 "--delete-permanent to act.")
        return 0

    dest = "PERMANENTLY DELETE" if permanent else "move to Trash"
    if not args.yes:
        if not sys.stdin.isatty():
            die("refusing to delete without --yes in a non-interactive shell.", code=1)
        verb = (f"{_C['red']}{_C['bold']}{dest}{_C['reset']}" if permanent
                else f"{_C['bold']}{dest}{_C['reset']}")
        prompt = (f"About to {verb} {len(matches)} file(s) "
                  f"({human_size(total_bytes)}). Continue? [y/N] ")
        try:
            if input(prompt).strip().lower() not in ("y", "yes"):
                info("aborted — nothing deleted.")
                return 0
        except (EOFError, KeyboardInterrupt):
            print(file=sys.stderr)
            info("aborted — nothing deleted.")
            return 0

    removed, failed = do_delete(matches, permanent)
    action = "Permanently deleted" if permanent else "Moved to Trash"
    print(f"{_C['green']}✓{_C['reset']} {action} {len(removed)} file(s) "
          f"({human_size(total_bytes)}{'' if permanent else ' — empty the Trash to reclaim space'}).",
          file=sys.stderr)
    if failed:
        warn(f"{len(failed)} file(s) could not be removed:")
        for path, why in failed[:20]:
            print(f"    {path} — {why}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(file=sys.stderr)
        sys.exit(130)
