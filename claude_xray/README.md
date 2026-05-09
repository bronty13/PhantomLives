# Claude XRay

A quick-and-dirty local viewer/editor for Claude Code config files, with inline learning context for every path under `~/.claude/` and any project `.claude/` folder.

Tree on the left. Editor on the right. Hover any path for a one-line description; click to open and edit in CodeMirror.

## Documentation

- **[USER_GUIDE.md](USER_GUIDE.md)** — full user-facing guide (install, run, UI tour, troubleshooting)
- **[HANDOFF.md](HANDOFF.md)** — for whoever picks this up next: architecture, contracts, safety rails, common changes

## What it shows

- `~/.claude/` (user-level: settings, CLAUDE.md, agents, commands, skills, plugins, transcripts, …)
- `<cwd>/.claude/` (project-level, when present)

Sensitive or generated paths are loaded **read-only** by default:
- `~/.claude.json` (contains MCP OAuth tokens)
- `projects/*.jsonl` (session transcripts)
- `shell-snapshots/`, `statsig/`, `ide/`

## Install

```bash
cd ~/Documents/GitHub/PhantomLives/claude_xray
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
python app.py
# or, to scope the project tab to a specific repo:
python app.py --cwd ~/code/some-repo
```

By default it serves at `http://127.0.0.1:8765` and opens your browser. Use `--no-browser` to skip the auto-open, or `--port N` to change the port.

## Safety rails

- All file access is restricted to `~/.claude/` and `<cwd>/.claude/` — paths that try to escape via `..` are rejected.
- Symlinks pointing outside the root are skipped.
- Saves are **atomic**: a `.xraybak-<unix-ts>` backup is written first, then the new file is `os.replace`-d into place.
- 1 MB hard cap on saves; files over 5 MB won't load in the editor at all.
- Read-only paths cannot be saved (the API will reject `PUT`s).

## Adding descriptions

`descriptions.json` maps relative paths (under either root) to one-line human descriptions shown in the "About this file" panel. Keys can be:

- exact filenames: `"settings.json"`
- exact relative paths: `"agents/foo.md"`
- directory names with trailing slash: `"projects/"`
- prefix-with-trailing-dash for backups: `"settings.json.backup-"`
- a special glob entry: `"projects/*.jsonl"`

Restart the server (or just refresh the page after editing the file — descriptions are read once at startup, so for now: restart).

## Keyboard

- **Cmd/Ctrl-S** — save current file
- **Filter box** (top right) — substring filter on filename or path; auto-expands matching folders

## Layout

```
claude_xray/
├── app.py              # FastAPI server: /api/roots, /api/tree, /api/file
├── descriptions.json   # path → human description
├── requirements.txt
├── README.md
└── static/
    ├── index.html
    ├── app.js
    └── style.css
```

## Roadmap (won't build until asked)

- Diff view against `.xraybak-*` files
- Hook script editor with "test run" button
- JSON schema validation for `settings.json`
- Git status badges on `.claude/` files
- MCP server toggle UI
