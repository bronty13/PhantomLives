# MacSearchReplace — Faithful Parity Plan

**Goal:** Make MacSearchReplace look and feel as close to Funduc Software's Windows *Search and Replace* as practical on macOS, for personal nostalgic use.

**Date:** 2026-04-27
**Source of truth:** `~/Downloads/MacSearchReplace/sr_feature_catalog.md` (1,491 lines, derived from the original CHM help)
**Current state:** `~/Downloads/MacSearchReplace/codebase_assessment.md`

---

## TL;DR — the headline finding

The current codebase markets itself as "Phase 4 complete — Funduc parity achieved" but it isn't.
It is a competent, modern, ripgrep-powered Mac search-and-replace utility with *some* Funduc-shaped features grafted on. It will not feel like Funduc to anyone who used the Windows version, because:

1. **The regex engine is wrong.** Funduc has a custom, non-PCRE syntax (`*[0-9]` means "any digits", `.` is *not* supported, backreferences are `%1`, NOT `\1`, etc.). Current uses ripgrep/Oniguruma — PCRE-style. Typing the regex you remember will produce different results.
2. **Replacement-token syntax is wrong.** Funduc uses `%%srpath%%`, `%%srfile%%`, `%%srdate%%`, `%%envvar=VAR%%`, etc. Current uses `\#path`, `\#dir`, `\#{1,1,%d}`. Different language entirely.
3. **Several search modes are missing**: HTML mode, Ignore Whitespace mode, Boolean (`&`/`|`/`~`) mode, Clipboard search/replace.
4. **Several Funduc-defining features are missing**: file operations on results (Copy/Move/Delete), file reformatting, prepend/append, capitalization processing, capability to filter by file attribute, "Find in Results", "Search only current result files", iteration operator (`{n}` / `{*}`), linked scripts, Apply Script, boolean gating in scripts, print results.
5. **The UI is shaped differently.** Current is the modern Mac 3-pane (criteria → outline → context). Funduc is a tall single form: criteria block → toggle-button row → action-button row → flat tree of results below. The "feel" requires the second.
6. **The CLI is shaped differently.** Funduc uses `/s`, `/r`, `/p`, `/f`, `/d`, `/x`, `/i`, `/w`, `/c`, `/u`, `/q`, `/o`. Current `snr` uses a Git-style subcommand layout.
7. **Script format is wrong.** Funduc `.srs` is plain ASCII with `[Search]`/`[Replace]`/`[Paths]`/`[Options]` sections. Current `.snrscript` is JSON v1/v2.

None of this is a defect of the current code — it just wasn't built to the Funduc spec. The work below describes what fidelity actually requires.

---

## Decisions you should make before I touch code

These are the load-bearing choices. They change the size of the project by a lot, so I want your call before planning further.

### D1 — Regex engine

Funduc's regex is a non-PCRE bespoke language. Three options:

- **A. Custom Funduc engine in pure Swift.** Maximally faithful. Big build (probably ~1.5–2k LOC + tests). I'd write a parser, a small VM, and operator-by-operator behavior tests against examples in the help.
- **B. Funduc → ICU/NSRegularExpression *translator*.** A parser that converts `*[0-9]` to `[0-9]+`, `?` to `.`, `^^`/`$$` to file anchors, `%n` backrefs to `$n`, etc. Then run the translated pattern with ICU. ~600–900 LOC, gets ~95% right, edge cases in `+n` column specifier, `!` (NOT), and `*` semantics will diverge. Ripgrep stays as the fast path for *literal* search.
- **C. Keep PCRE syntax; only add Funduc replacement tokens.** Cheapest. Not faithful — typing the patterns you remember from Windows will not work. **I do not recommend this if your goal is nostalgia.**

**My recommendation: B**, with a "Funduc Regex" toggle that controls whether the translator is applied. Add tests pulled directly from the help-file examples. If we hit a translator edge case in real use, we can selectively upgrade specific operators to native Swift implementations later. (A is the right answer if we hit too many translator dead-ends.)

### D2 — UI shape

- **A. Funduc-faithful "classic" form layout.** Single window: criteria block at top → toggle button row → action button row → flat results tree at bottom. Optional context viewer in a separate window or popover (matches the Funduc "View Context" modal).
- **B. Keep the modern 3-pane layout.** Easier on macOS but doesn't match nostalgia.
- **C. Provide both.** A "Classic" mode toggle in Preferences that swaps layouts. Doubles UI maintenance cost.

**My recommendation: A.** You explicitly said nostalgia. The 3-pane was designed for a different audience. If we keep one layout and it's the classic one, every interaction will feel right.

### D3 — Script format

- **A. Replace `.snrscript` JSON with Funduc-style `.srs` ASCII INI format.** Faithful — `.srs` files from old Windows installs would even load.
- **B. Support both.** `.srs` as canonical, `.snrscript` as legacy import.
- **C. Keep JSON, add `.srs` import only.**

**My recommendation: B.** Make `.srs` the primary, keep `.snrscript` import for any scripts you've already written.

### D4 — CLI shape

- **A. Replace `snr` subcommands with Funduc's `/s`, `/r`, `/p`, `/f`, etc. flags.** Faithful but un-Mac-like.
- **B. Keep current `snr` subcommands; add a separate Funduc-flag-compatible front-end (e.g., `sr` binary) that translates to the modern CLI.**
- **C. Keep modern CLI only.**

**My recommendation: B.** The Funduc flag style was a Windows convention; Mac users live in a Unix shell. Having both gives you the muscle-memory match without breaking modern shell expectations.

### D5 — Replacement tokens

- **A. Replace current `\#path`/`\#{counter}` with Funduc's `%%srpath%%`/`%n>>` syntax.**
- **B. Support both.**

**My recommendation: A.** Pure Funduc. No reason to keep the current tokens — nothing depends on them and they aren't in use.

### D6 — Scope of file-operations parity

Funduc has Touch (date/time/attributes), Copy, Move, Delete operating on selected results. Current has Touch only.

- **A. Implement Copy/Move/Delete with Mac-equivalent attribute model** (locked flag, hidden flag, mtime/atime). Yes/no?

**My recommendation: yes.** It's a Funduc-defining feature.

### D7 — Print Results

Funduc has a Print Results button. macOS supports printing easily via `NSPrintOperation`. **Include or skip?**

**My recommendation: include.** Cheap, instantly recognizable.

---

## Gap inventory (what's actually missing)

Organized by theme. Each item flagged with current state vs. Funduc behavior. **Bold** = Funduc-defining, would be felt by a returning user immediately.

### 1. Regex engine and pattern syntax

| Funduc | Current |
|---|---|
| **`*` works on `()`/`[]` groups** (e.g., `*[0-9]` = "any digits") | `*` is PCRE quantifier — different meaning |
| **`+` works on `()`/`[]` groups** | PCRE quantifier |
| **`?` matches one character** (no `.` operator) | PCRE: `?` = optional, `.` = any |
| **`!` = NOT** | Not supported |
| **`^^` = start of file, `$$` = end of file** | Not supported |
| **`+n` = column specifier** | Not supported |
| **`%1`...`%9`, `%:`...`%N` backreferences in replacement** | Uses `$1`/`\1` |
| **`%n<` lowercase, `%n>` uppercase replacement** | Not supported |
| **`%n>>`/`%n<<`/`%n>start>` counter operators** | Different syntax (`\#{...}`) |
| **`%n<format(expression)>` math operations** | Not supported |
| **`\` escapes for literals: `\+ \- \* \? \( \) \[ \] \\ \| \^ \$ \!`** | PCRE escaping |
| Default max regex size 32,767 bytes | N/A in NSRegex |

**Plan:** D1 above. Build a Funduc-syntax translator/engine and route all "Regex" toggle searches through it.

### 2. Replacement tokens (non-regex)

| Funduc | Current |
|---|---|
| **`%%srfound%%`** (matched text) | not supported |
| **`%%srpath%%`** | `\#dir` |
| **`%%srfile%%`** | `\#base` |
| **`%%srfiledate%%`**, **`%%srfiletime%%`**, **`%%srfilesize%%`** | not supported |
| **`%%srdate%%`**, **`%%srtime%%`** (system time) | not supported |
| **`%%srprepend%%`**, **`%%srappend%%`** (prepend/append markers) | not supported |
| **`%%srformat%%=nn`** (column reformat) | not supported |
| **`%%envvar=NAME%%`** | not supported |
| Escape literal `%`, `\`, `<`, `>` in replacement | n/a |

**Plan:** Implement a `FunducReplacement` evaluator that pre-processes the replacement string with the file/system/match context, then runs through the regex backref substitution. Drop the `\#` token system.

### 3. Search modes

| Funduc | Current |
|---|---|
| Plain literal search | ✓ |
| Whole-word | ✓ |
| Case sensitive/insensitive | ✓ |
| Regex (Funduc-syntax) | ✗ (uses PCRE) |
| **Binary mode** (multi-line + `\t \r \n \xHH` escapes) | partial — hex literals only, no `\t/\r/\n` outside regex |
| **HTML mode** (entity-aware matching, e.g., `&` matches `&amp;`) | ✗ |
| **Ignore Whitespace mode** | ✗ |
| **Boolean expression mode** (`&`, `|`, `~` in whole-word mode) | ✗ |
| **Clipboard Search/Replace** (Shift+Cmd+H) | ✗ |
| ZIP archive search | ✓ |
| Inside OOXML | ✓ (but no fixture tests) |
| Inside PDF | ✓ |

**Plan:**
- HTML mode: maintain entity table + transparent normalization at search time.
- Ignore-whitespace mode: replace runs of `\s+` with `\s+` in pattern (regex) or normalize on the fly (literal).
- Boolean mode: pre-parse `a & b`, `a | b`, `~a` and run as multiple sub-searches with set operations on hit positions.
- Clipboard mode: read `NSPasteboard.general`, run search/replace, write back.
- Binary mode: extend escape parser to handle `\t \r \n \xHH \\` in addition to current hex.

### 4. File targeting

| Funduc | Current |
|---|---|
| Include masks (`*.txt;*.htm`) | ✓ |
| Exclude masks (`~*.exe`) | ✓ (uses ripgrep `!` glob) |
| Complex include/exclude editor (directory-aware) | ✗ |
| Subdir recursion toggle | ✓ |
| Subdir depth limit | ✗ |
| Date filter (before/after) | ✓ |
| Size filter (min/max) | ✓ |
| **Reverse filter toggle** | ✗ |
| **File attribute filter** (Archive/RO/Hidden/System) | ✗ — needs Mac equivalent (locked, hidden, etc.) |
| **"Local Hard Drives"** special path | ✗ — Mac equivalent: enumerate volumes |
| Drag/drop folder/file into path/mask | ✓ (probably; needs verifying) |
| History dropdowns on Search/Replace/Mask/Path | ✗ — only "recent roots" |

**Plan:** Add depth limit, reverse-filter checkbox, attribute filter (mapped to chflags-style on Mac), per-field combobox history.

### 5. Replacement & batch behavior

| Funduc | Current |
|---|---|
| Prompt on each string | ✓ |
| Prompt on each file | ✗ (only per-hit) |
| **Skip rest of file** | ✓ (Skip File) |
| Replace all | ✓ |
| **Capitalization processing** (Match Case / First Cap / All Caps / Sentence Case) on replace | ✗ |
| Backups | ✓ (APFS clonefile) |
| Preserve original date | ✓ (option) |
| Undo last replacement | ✓ (`snr restore`) |
| **`SRUNDO.BAT` style script generation** | ✗ — Mac equivalent: `srundo.sh` |
| **File operations on results: Copy/Move/Delete** | ✗ (only Touch) |
| Touch (mtime) | ✓ |
| **Touch attributes (RO/hidden/etc.)** | ✗ |

**Plan:** Add per-file prompt, capitalization-processing menu in replace, Copy/Move/Delete on selection, attribute-Touch via chflags.

### 6. Special operations

| Funduc | Current |
|---|---|
| **Prepend** content to file (binary mode + `%%srprepend%%`) | ✗ |
| **Append** content to file (binary mode + `%%srappend%%`) | ✗ |
| **File reformatting** (`%%srformat%%=nn` column wrap) | ✗ |
| **Math operations** in replacements (`%n<%d(E1-1)>`) | ✗ |
| **Environment variables** in replacements | ✗ |

**Plan:** All implementable as part of the replacement-token evaluator (item 2) plus a reformatter routine.

### 7. Scripts

| Funduc | Current |
|---|---|
| `.srs` ASCII INI format | `.snrscript` JSON |
| Multi-pair search/replace | ✓ |
| Multi-pair masks/paths | ✓ |
| Per-script options override | ✓ (v2) |
| **Iteration operator `{n}` and `{*}` (until stable)** | ✗ |
| **Linked scripts** (chain to next `.srs`) | ✗ |
| **Boolean gating** (per-file conditional execution) | ✗ |
| **Apply Script** (transform search/replace strings before run) | ✗ |
| Comments in script | partial |
| `srdump.srs` (Ctrl+click Script button) | ✗ |

**Plan:** Add `.srs` reader/writer (canonical), keep `.snrscript` import, implement iteration/linked/gating in the script runner.

### 8. UI / UX

| Funduc | Current |
|---|---|
| Single-window form layout (top criteria → toggle row → action row → flat tree) | 3-pane modern Mac layout |
| **Mode toggle row buttons** with depressed-state visuals | flags in disclosure |
| **Action button row** (Search, Search/Replace, Touch, File Ops, View Context, Copy, Print, HTML, Save, Options, Script, About, Help, Customize) | menu items / commands |
| **Customize Toolbar** | ✗ |
| Combo-box history per field (Search/Replace/Mask/Path) | ✗ |
| Tree view with expand/collapse + spacebar/F4/F5 navigation | partial |
| **Context Viewer as separate modal/inline window** with Save/Cancel/Prev Hit/Next Hit | inline preview pane only |
| **Editable context viewer** (so user can fix things in-place) | read-only |
| **Find in Results (F3)** | ✗ |
| **Search only current result files (Ctrl+Alt+F / Ctrl+Alt+H)** | ✗ |
| Right-click on result: View File / View Context / External Editor / Copy / Touch / Copy File List / Delete | partial |
| **View Results as HTML** (open in browser) | Export only |
| **Print Results** | ✗ |
| **Save Results** to text file | partial (Export) |
| Font customization | ✗ |
| Color customization (result text / filename / line) | ✗ |
| Tree-view-style toggle (tree vs flat) | ✗ |
| Drop folder onto path field, file onto mask field | needs verification |
| Cmd-W swap Search ↔ Replace | ✗ (Funduc: Ctrl+W) |
| Esc to abort search | ✓ via Cmd-. — should also accept Esc |
| Cmd-F = Search, Cmd-H = Search/Replace | ✗ — current uses standard Mac semantics |

**Plan:** Big rebuild of `ContentView` to the classic shape (Decision D2). Context Viewer becomes its own window. Add Find-in-Results, Search-current-files, Print, View-as-HTML in browser, font/color prefs.

### 9. CLI

| Funduc | Current |
|---|---|
| `/s "string"` search | `snr search` |
| `/r "string"` replace | `snr replace` |
| `/p "path"` path | `--root` |
| `/f "mask"` mask | `--include` |
| `/b "backup"` | `--backup` |
| `/c "script"` | `snr run` |
| `/i` case-insens, `/x` regex, `/w` whole word, `/d` subdirs | various flags |
| `/u` minimized/headless, `/q` quiet | n/a |
| `/o "outfile"` | `--output` (probably) |

**Plan:** D4 — keep `snr`, add a `sr` front-end that accepts Funduc flags and shells out to the same library.

### 10. Preferences / persistence

Mostly OK conceptually. Adapt registry → UserDefaults; add Font and Color groups; add Tree vs Flat toggle, Stop-after-first-hit, ZIP extraction path, double-click behavior, history-cache size.

### 11. Edge cases and quirks the catalog calls out

These are the kind of details a returning user will notice within 30 seconds:

- `^` and `$` cannot both appear in same expression (it's a Funduc constraint, not PCRE)
- `*` does not match chars under ASCII 32 (space)
- Counter starting-value zero-padding: `%1>000>` vs `%1>0>` differs in output digit count
- `^`, `$`, `^^`, `$$` count as `%n` parameters in replacements
- "Skip All in File" applies to *current file only*, not future files
- Iteration `{*}` continues until pass produces no changes (idempotent test, can infinite-loop on certain pathological patterns — needs a hard cap)

**Plan:** These get encoded as test cases against the engine.

### 12. Out of scope (Windows-only — adapt or skip)

- Windows Registry → already adapted (UserDefaults)
- Shell extension / Explorer context menu → skip; Mac equivalent (Finder Services) optional
- File associations → use `NSWorkspace.open(_:withApplicationAt:)`
- UNC paths → mounted SMB volumes appear as normal paths
- File attributes (Archive/RO/Hidden/System) → map to Mac flags (UF_HIDDEN, UF_IMMUTABLE)
- HexView → use Hex Fiend (already configured)
- CHM help → ship the catalog as Help bundle or HTML

---

## Phasing proposal

Each phase is a coherent slice that leaves the app in a working state.

### Phase A — Engine (the foundational decisions)

Prerequisite: D1 (regex engine), D5 (replacement tokens) decided.

1. New module `SnRFunducRegex`: parser + (translator OR custom engine, per D1) + tests covering every operator example in the help.
2. New module `SnRFunducReplace`: replacement-token evaluator (`%n`, `%n<`, `%n>`, counters, math, `%%sr*%%`, `%%envvar=*%%`, prepend/append markers).
3. Wire both modules into `SearchReplaceViewModel` behind a "Funduc Regex" toggle. Old PCRE path remains as a non-Funduc fallback for now.
4. Unit tests: every example from §3 and §4 of the catalog.

**Estimate:** ~2–3 weeks of focused work. This is the load-bearing phase.

### Phase B — Search modes and replace behavior

5. HTML mode (entity normalization).
6. Ignore Whitespace mode.
7. Boolean expression mode (`&`/`|`/`~`).
8. Clipboard Search/Replace.
9. Binary mode escape parser (`\t \r \n \xHH \\`).
10. Capitalization processing on replace.
11. Per-file prompt (in addition to per-hit).

### Phase C — Files & filters

12. File operations on results: Copy / Move / Delete.
13. Touch with attributes (locked, hidden).
14. Reverse filter toggle.
15. Mac-attribute filter.
16. Subdir depth limit.
17. "Local Hard Drives" → enumerate `/Volumes/*`.
18. Per-field combobox history (Search / Replace / Mask / Path).

### Phase D — UI rebuild (D2 = A or C)

19. New classic single-window layout in a new SwiftUI view (`ClassicContentView`).
20. Mode-toggle button row.
21. Action button row.
22. Flat results tree with spacebar/F4/F5/Enter behavior.
23. Context Viewer as a separate window with editing.
24. Find in Results.
25. Search only current result files.
26. Print Results (NSPrintOperation).
27. View Results as HTML (open in browser).
28. Font/color preferences pane.
29. Drop folder onto path, file onto mask — verify and patch.

### Phase E — Scripts and CLI parity

30. `.srs` reader/writer (D3).
31. Iteration operator (`{n}`, `{*}` with hard cap).
32. Linked scripts.
33. Boolean gating in scripts.
34. Apply Script.
35. Funduc-flag-compatible front-end binary `sr` (D4).

### Phase F — Polish / out-of-scope decisions

36. Help bundle from the catalog.
37. About box matching the Funduc style.
38. Keyboard shortcuts: Cmd-W swap, Cmd-F/Cmd-H semantics under "classic" mode (overriding Mac default for nostalgia).
39. Mac equivalent of `SRUNDO.BAT` — shell script generated alongside backups.

---

## What I'd like from you next

Pick decisions D1 through D7. Once those are settled, I'll rewrite Phase A as a concrete implementation plan with specific file paths and tests, and we can start there. If anything in the gap inventory is *not* worth chasing — say so now and I'll cut it from the plan.
