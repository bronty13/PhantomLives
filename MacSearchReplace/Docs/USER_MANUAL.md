# MacSearchReplace — User Manual

A native macOS utility for finding and replacing text across many files, archives, and PDFs. Modeled on Funduc Software's *Search and Replace* for Windows.

## Quick tour

```
┌────────────────── Criteria ──────────────────┐
│  Find:        [____________________________] │
│  Replace:     [____________________________] │
│  Look in:     [/Users/me/Projects        ▾]  │
│  Include:     [*.swift; *.md             ]  │
│  Exclude:     [.build; *.lock            ]  │
│  ☐ Regex   ☐ Case-sensitive   ☐ Multiline    │
│  ▸ Filters   ▸ Sources                       │
│  [ Find ]   [ Replace All ]   [ Stop ]       │
└──────────────────────────────────────────────┘
┌── Results outline (click ▸ to expand a file)─┐
│  ▾ src/auth.swift                  12 hits   │
│      L42:  let token = …                     │
│      L88:  // TODO: auth                     │
│  ▸ src/api.swift                    3 hits   │
└──────────────────────────────────────────────┘
┌── Context preview (selected hit)  ────────────┐
│  40:  func login() {                         │
│  41:      log("attempt")                     │
│  42:      let token = makeToken()  ← match   │
│  43:      return token                       │
└──────────────────────────────────────────────┘
```

## Performing a search

1. Type a pattern in **Find**.
2. Pick a **Look in** folder (the **Open Recent Folder** menu remembers your last 10).
3. (Optional) Add include/exclude masks. Multiple masks are separated by `;` or `,` — e.g. `*.swift; *.m; *.h`.
4. Press **Find** or hit **Return** in any criteria field.
5. Press **Stop** (or `⌘.`) to abort a long search.

### Pattern modes

| Mode            | Behavior |
|-----------------|----------|
| Literal         | Exact text match (default) |
| Regex           | PCRE-style (Rust regex). `\b`, `^`, `$`, lookarounds where supported, `$1`/`${name}` backrefs in replacement |
| Multiline       | `.` matches `\n`; `^/$` anchor per line vs whole input |
| Case-insensitive| `aB` matches `Ab`, `AB`, etc. |
| Whole word      | Wraps the pattern in `\b…\b` automatically |

### Filters disclosure

Click **▸ Filters** to reveal:
- **Modified date** — `since` / `until` (drops files outside the window).
- **File size** — `min` / `max` bytes.
- **Honor `.gitignore`** — skip ignored files (default on).
- **Search inside ZIP / DOCX / TAR** (toggle).
- **Search inside PDF text** (toggle).

## Performing a replace

After a search:

1. Type the replacement in **Replace**.
2. Use one of:
   - **Replace All** — applies to every hit currently in the results.
   - **Replace with Prompt…** — walks each hit and asks **Yes / No / All / Skip File**.
   - **Multiple S/R Pairs…** — opens a sheet to apply N find/replace pairs in one pass.
3. Backups are automatic — see *Backups & undo* below.

### Counter replacement

In replace text, `\#{start,step,format}` becomes a running counter:

| Pattern              | Output |
|----------------------|--------|
| `\#{1,1,%d}`         | `1, 2, 3, …` |
| `\#{100,5,%04d}`     | `0100, 0105, 0110, …` |

### Path-token interpolation

In replace text, these tokens expand per file:

| Token   | Example               |
|---------|------------------------|
| `$FILE` | `notes.md`             |
| `$DIR`  | `/Users/me/Notes`      |
| `$EXT`  | `md`                   |
| `$STEM` | `notes`                |
| `$DATE` | `2026-04-27`           |

## Sources beyond plain text

| Source                               | Mode     |
|--------------------------------------|----------|
| Plain text (UTF-8/16, Latin-1, Shift-JIS)| read+write |
| ZIP archives                         | read+write (rewrites in place) |
| OOXML (`.docx`, `.xlsx`, `.pptx`)    | read+write |
| TAR / TGZ / TAZ                      | read+write |
| PDF                                  | read-only (text layer) |
| Binary / hex                         | length-preserving replace |

PDFs and archives are off by default — enable in the **▸ Sources** disclosure.

## Backups & undo

Every replace session writes APFS clones of touched files to:

```
~/Library/Application Support/MacSearchReplace/Backups/<ISO-timestamp>/
```

Each session has a `manifest.json` mapping originals → clones. To roll back:

```bash
snr restore "~/Library/Application Support/MacSearchReplace/Backups/2026-04-27T19-30-15"
```

Or in the UI: **Search → Open Backup Folder** then drag a session file back over the original.

## Favorites

- **⌥⌘S** — Save current criteria as a favorite.
- **Favorites menu** — load any saved favorite by clicking it.
- Stored in `~/Library/Application Support/MacSearchReplace/favorites.json`.

## Drag, export, external editors

- **Drag a result row** to the Finder, Mail, BBEdit, etc.
- **File → Export Results** — CSV, JSON, HTML, or plain text.
- **Right-click a hit → Open in External Editor** — uses the editor configured in **Preferences → Editors** (BBEdit, VS Code, Xcode, etc., auto-detected).

## Touch (set modification time)

**Search → Touch Files in Results** sets `mtime` of every file currently in the results to "now". Useful for forcing rebuilds.

## Saved scripts (`.snrscript`)

JSON files describing a multi-step pipeline. Two versions are supported:

- **v1** — single global search scope, ordered list of steps.
- **v2** — same, but each step may override `roots`, `include`, `exclude`, `honorGitignore`, `maxFileBytes`.

Run from the GUI (**File → Open Script…**) or the CLI:

```bash
snr run rename-imports.snrscript
```

See [`Docs/snrscript-format.md`](snrscript-format.md) for the full schema.

## Companion CLI (`snr`)

```
snr search <pattern> <path...>   # search only
snr replace <pattern> <repl> <path...>   # replace + backup
snr run <script.snrscript>       # multi-step pipeline (v1 or v2)
snr touch <path...>              # set mtime to now
snr pdf <pattern> <path...>      # PDF text search (read-only)
snr restore <backup-session>     # roll back a backup session
```

Common flags: `-r` (regex), `-i` (case-insensitive), `-w` (whole word), `-m` (multiline), `--include 'glob'`, `--exclude 'glob'`, `--dry-run`, `--no-backup`.

## Preferences

**MacSearchReplace → Settings…** (`⌘,`) — five tabs:

1. **General** — default roots, max file size, default backup behavior.
2. **Editors** — preferred external editor; binary-file editor.
3. **Archives** — search-inside toggles per archive type.
4. **Display** — context lines, font size, dark-mode preview theme.
5. **Performance** — concurrency cap, ripgrep thread count, result-buffer limit.

## Keyboard shortcuts

| Shortcut    | Action |
|-------------|--------|
| `⌘N`        | New search (clear) |
| `⌘O`        | Open script… |
| `⌘Return`   | Find |
| `⇧⌘Return`  | Replace All |
| `⌘.`        | Stop |
| `⌘,`        | Preferences |
| `⌥⌘S`       | Save favorite |
| `⌘Q`        | Quit |

## Troubleshooting

**Search returns no results in a folder you know contains matches** — check the **Filters** disclosure: maybe `.gitignore` is excluding them, or your include mask doesn't cover the extension.

**App won't launch ("damaged" warning)** — the app is ad-hoc signed. Run:
```bash
xattr -dr com.apple.quarantine /Applications/MacSearchReplace.app
```

**Replace was wrong / too aggressive** — every replace creates a backup session. Use `snr restore` (above) to roll back.

**Slow on huge folders** — disable PDF/archive scanning, lower the concurrency cap in **Preferences → Performance**, or narrow your include masks.
