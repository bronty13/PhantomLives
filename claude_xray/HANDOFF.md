# Claude XRay — Handoff Document

For whoever picks this up next (including future-you).

---

## What it is

A local web app (FastAPI + vanilla HTML/JS + CodeMirror) that browses, views, and edits files under `~/.claude/` and any project-local `.claude/` folder. The "About this file" panel shows a human description for each path so the tool doubles as a learning aid for Claude Code's filesystem layout.

**Status:** v0.1, MVP. Smoke-tested locally on macOS 25.4 with Python 3.11. Not intended for any non-local use.

---

## Why it exists

There is no official GUI from Anthropic for editing Claude Code configuration. Several community tools exist (claude-deck, claude-code-organizer, claude-panel, etc.) but they vary in quality and some touch sensitive files like `~/.claude.json` (MCP OAuth tokens). Building a small, auditable in-house tool was the safer call.

The intentional design constraints:
- **No external services**, no telemetry, no auth, no network exposure.
- **Read-only by default** for anything containing secrets or generated state.
- **Atomic writes with backups** — every save creates a `.xraybak-<ts>` first.
- **Sandboxed file access** — all reads/writes restricted to two roots; path traversal rejected.

---

## Architecture (one paragraph)

`app.py` is a FastAPI server with three endpoints (`/api/roots`, `/api/tree`, `/api/file`). Static frontend in `static/` — no build step, just HTML/JS/CSS loaded via `<script>` tags and CodeMirror 5 from a CDN. `descriptions.json` is loaded once at startup and looked up per request to populate the "About this file" panel. Two roots are exposed: `user` (`~/.claude/`) and optionally `project` (`<cwd>/.claude/`). Saves are atomic via `.xraytmp` + `os.replace`, with a `.xraybak-<unix-ts>` copy of the previous version.

Total LOC: ~600 across all files.

---

## File layout

```
claude_xray/
├── app.py              # FastAPI backend (~250 LOC)
├── descriptions.json   # path → human description (data, not code)
├── requirements.txt    # fastapi, uvicorn, pydantic
├── README.md           # short intro
├── USER_GUIDE.md       # full user-facing guide
├── HANDOFF.md          # this file
├── .gitignore
└── static/
    ├── index.html      # shell + CodeMirror script tags
    ├── app.js          # ~250 LOC of vanilla JS
    └── style.css       # Dracula-ish dark theme
```

---

## Endpoints (server contract)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/roots` | Returns `{user: "/abs/path", project?: "/abs/path"}` so the UI knows which tabs to show. |
| `GET` | `/api/tree?root=user\|project` | Recursive tree, max depth 6. Each node: `{name, path, isDir, size, mtime, readonly, description, children?}`. Returns `{missing: true}` if the root doesn't exist. |
| `GET` | `/api/file?root=...&path=...` | Reads a file. Returns content + metadata + description. Files >5 MB return `{tooLarge: true, content: ""}`. Binary files return `{binary: true, content: ""}`. |
| `PUT` | `/api/file?root=...&path=...` | Writes a file. Body: `{content: "..."}`. Refuses readonly paths (403) and oversized payloads >1 MB (413). |

---

## Safety rails (do not weaken without a very good reason)

1. **Allowed roots are hardcoded** — `~/.claude/` and `<cwd>/.claude/` only. `resolve_safe()` rejects anything that resolves outside.
2. **Symlinks pointing outside the root are skipped** during tree walk.
3. **Read-only patterns** in `app.py`:
   - `projects/`, `shell-snapshots/`, `statsig/`, `ide/`
   - `~/.claude.json` at the user root (OAuth tokens)
4. **Server binds to `127.0.0.1`** by default. Don't change to `0.0.0.0` — there is no auth.
5. **Backup before write**: `<file>.xraybak-<unix-ts>` is created before every save.
6. **Atomic rename**: write to `.xraytmp`, then `os.replace` over the destination.
7. **Hard size cap**: 1 MB on save (`MAX_EDIT_BYTES`), 5 MB on read.

If you add a new sensitive path to Claude Code that XRay should never write, add it to `READONLY_PATTERNS` or `READONLY_FILES_AT_HOME` in `app.py`.

---

## How to run / verify

```bash
cd ~/Documents/GitHub/PhantomLives/claude_xray
source .venv/bin/activate           # or recreate: python3 -m venv .venv && pip install -r requirements.txt
python app.py
# → http://127.0.0.1:8765
```

Quick health checks:

```bash
curl -s http://127.0.0.1:8765/api/roots
curl -s 'http://127.0.0.1:8765/api/file?root=user&path=settings.json' | python3 -m json.tool | head -20

# Safety rails should still hold:
curl -s -o /dev/null -w "%{http_code}\n" 'http://127.0.0.1:8765/api/file?root=user&path=../etc/passwd'           # → 400
curl -s -o /dev/null -w "%{http_code}\n" 'http://127.0.0.1:8765/api/file?root=user&path=does-not-exist.txt'      # → 404
curl -s -o /dev/null -w "%{http_code}\n" -X PUT -H 'Content-Type: application/json' \
  -d '{"content":"x"}' 'http://127.0.0.1:8765/api/file?root=user&path=projects/foo.jsonl'                        # → 403
```

If any of those returns a different code, **do not ship**.

---

## Common changes you might want to make

### Add a description for a new Claude Code path

Edit `descriptions.json`. Keys are relative to the root (no leading slash). Use trailing slash for directories. Restart the server.

### Add a new editor language mode

In `static/app.js`, extend `modeFor()`. In `static/index.html`, add the matching CodeMirror mode `<script>`. Update `detect_kind()` in `app.py` if the file extension isn't already mapped.

### Lift the 1 MB save cap

Change `MAX_EDIT_BYTES` in `app.py`. Think hard before doing this — you generally don't want to be hand-editing megabyte-sized JSON.

### Run on a different port

`python app.py --port 9000`. The frontend is same-origin so no other change needed.

---

## Known limitations / not done

- No diff view against `.xraybak-*` files
- No JSON schema validation for `settings.json` (you can break it; the editor won't warn you until Claude Code complains)
- No git status badges on `.claude/` files
- No hook script "test run" button
- Descriptions are read **once at startup** — no live reload of `descriptions.json`
- Tree depth capped at 6 levels (hardcoded in `build_tree`)
- No pagination on the tree — if `~/.claude/projects/` has thousands of session subdirs, the initial load could be slow

---

## If something breaks

| Symptom | First place to look |
|---|---|
| Server won't start | Wrong Python (need 3.11+); deps not installed; port 8765 busy |
| Tree shows nothing | `~/.claude/` doesn't exist on this machine — Claude Code never run? |
| Save fails with 403 | Path is in the read-only list (intentional) |
| Save fails with 413 | File is >1 MB; bump `MAX_EDIT_BYTES` only if you really need to |
| File looks wrong after save | Check for sibling `.xraybak-*`, copy it back |
| Tree never refreshes | Hard-refresh the browser; the tree is fetched once per tab switch |

---

## Roadmap (only build when asked)

- Diff view: select two `.xraybak-*` snapshots and show a side-by-side diff.
- Schema validation: ship a JSON Schema for `settings.json`, validate on save.
- Hook script test runner: invoke a hook script with mocked event JSON, show output.
- MCP server toggle UI: read/write `~/.claude.json` server entries (carefully — tokens live there).
- Live reload of `descriptions.json` so docs work doesn't require a restart.

---

## Provenance

Built 2026-05-08 as a "quick and dirty" alternative to the third-party Claude Code dashboards (claude-deck, claude-code-organizer, claude-panel). The descriptions in `descriptions.json` were sourced from a Claude Code filesystem reference compiled the same day; they reflect Claude Code's layout as of that date and may drift as Claude Code evolves.
