# Claude XRay — User Guide

A local viewer/editor for Claude Code's config files, with inline descriptions of what every path is for. Built to double as a learning tool: hover anything, find out what it does.

---

## 1. Install

One-time setup:

```bash
cd ~/Documents/GitHub/PhantomLives/claude_xray
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

You only need to do this once. After that, just `source .venv/bin/activate` before each run.

---

## 2. Run

```bash
cd ~/Documents/GitHub/PhantomLives/claude_xray
source .venv/bin/activate
python app.py
```

The server boots on `http://127.0.0.1:8765` and auto-opens your browser.

### Useful flags

| Flag | What it does |
|---|---|
| `--cwd PATH` | Sets the project root that the **`.claude (project)`** tab will look in. Defaults to your current working directory. Example: `python app.py --cwd ~/Documents/GitHub/PhantomLives/PurpleIRC` |
| `--port N` | Use a different port (default 8765). |
| `--host H` | Bind to a different host (default `127.0.0.1` — local only). Don't bind publicly. |
| `--no-browser` | Don't auto-open the browser. |

To stop the server: `Ctrl-C` in the terminal where it's running.

---

## 3. Using the UI

```
┌─────────────────────┬──────────────────────────────────┐
│  ~/.claude  [tab]   │  filePath                        │
│  .claude    [tab]   │  size • mtime • read-only flags  │
│  [filter box]       │  ┌────────────────────────────┐  │
│                     │  │ CodeMirror editor          │  │
│  ▾ ~/.claude        │  │                            │  │
│    ▸ agents/        │  └────────────────────────────┘  │
│    ▸ commands/      │  [Save] [Revert]  status         │
│    ▾ projects/  🔒  │                                  │
│      foo.jsonl  🔒  │  ── About this file ──           │
│    settings.json    │  Description from descriptions.json │
└─────────────────────┴──────────────────────────────────┘
```

### Tabs (top of left pane)
- **`~/.claude`** — your global Claude Code config
- **`.claude (project)`** — the `.claude/` folder inside whatever you passed to `--cwd`. Hidden if it doesn't exist.

### Tree
- **▸ / ▾** — click a folder to expand/collapse
- **🔒** — file or folder is read-only by default (sensitive or generated content)
- **Hover** — tooltip with the path's description
- **Click a file** — opens it in the editor on the right

### Filter (top right)
Substring match on filename or full path. Auto-expands matching folders so the result is visible.

### Editor
- Syntax highlighting for JSON, Markdown, YAML, shell, Python, JavaScript
- **Cmd-S** (or **Ctrl-S**) saves
- The **Save** button enables only when content has changed and the file isn't read-only
- **Revert** discards in-flight changes and reloads from disk
- The status text on the right shows save/load/error state

### About panel (below the editor)
Shows the human description from `descriptions.json`. If a file has no description, you get a hint with the exact key to add.

---

## 4. Read-only files (and why)

These are loaded **read-only** by default — viewable but not editable through XRay:

| Path | Why |
|---|---|
| `~/.claude.json` | Contains MCP OAuth tokens — accidental edits could break authenticated MCP servers |
| `projects/*.jsonl` | Session transcripts — not designed to be hand-edited |
| `shell-snapshots/`, `statsig/`, `ide/` | Generated/ephemeral state |

If you genuinely need to edit one of these, do it directly in your terminal editor — don't loosen XRay.

---

## 5. Save behavior

When you save:

1. The current file is copied to `<file>.xraybak-<unix-ts>` first (so the previous version is recoverable)
2. The new content is written to a temp file, then atomically renamed into place
3. Files larger than **1 MB** are rejected (hard cap)
4. Files larger than **5 MB** won't even load in the editor

Backups accumulate; clean them up periodically with:

```bash
find ~/.claude -name "*.xraybak-*" -mtime +7 -delete
```

---

## 6. Adding descriptions for new paths

The "About this file" panel pulls from `descriptions.json`. Keys are matched against the path *relative to the root* (so `~/.claude/foo/bar.json` is keyed as `foo/bar.json`).

Supported key formats:

| Form | Example | Matches |
|---|---|---|
| Exact filename | `"settings.json"` | any file named `settings.json` |
| Exact path | `"agents/release-bot.md"` | only that one file |
| Directory | `"projects/"` (trailing slash) | the directory node |
| Backup prefix | `"settings.json.backup-"` | files starting with that prefix |
| Glob entry | `"projects/*.jsonl"` | special-cased for transcripts |

After editing `descriptions.json`, **restart the server** for the changes to take effect (descriptions are read once at startup).

---

## 7. Safety rails

- All file access is sandboxed to `~/.claude/` and `<cwd>/.claude/`. Paths containing `..` or symlinks pointing outside the root are rejected.
- The server binds to `127.0.0.1` by default — it is **not** reachable from the network.
- No auth, no TLS, no remote access. This tool is for **your machine only**.

---

## 8. Troubleshooting

| Symptom | Try |
|---|---|
| Browser doesn't auto-open | Open `http://127.0.0.1:8765` manually, or pass `--no-browser` and open it yourself |
| Port 8765 already in use | `python app.py --port 8800` |
| `.claude (project)` tab doesn't appear | Pass `--cwd PATH` pointing to a directory that *contains* a `.claude/` folder |
| "read-only path" error on save | The file is in the read-only list above; intentional |
| Editor shows "Binary file." | The file isn't UTF-8; XRay won't try to edit it |
| Saved file looks corrupted | Check for a sibling `.xraybak-*` and copy it back |

To stop the running server gracefully: `Ctrl-C`. To force-kill: `lsof -i :8765` to find the PID, then `kill <pid>`.
