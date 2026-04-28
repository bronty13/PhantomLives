# Search and Replace for Windows - Comprehensive Feature Catalog
## Source: Funduc Software - Windows Edition (Decompiled HTML Help)
## Prepared for Mac Re-implementation

---

## TABLE OF CONTENTS

1. [Top-Level Feature Areas](#top-level-feature-areas)
2. [Main Window & UI Layout](#main-window--ui-layout)
3. [Search Modes & Expression Types](#search-modes--expression-types)
4. [Regular Expression Syntax](#regular-expression-syntax)
5. [File/Folder Targeting](#filefolder-targeting)
6. [Replacement & Batch Operations](#replacement--batch-operations)
7. [Special Operations & Operators](#special-operations--operators)
8. [Scripting & Automation](#scripting--automation)
9. [Menus & Menu Items](#menus--menu-items)
10. [Program Options/Preferences](#program-optionpreferences)
11. [UI/UX Conventions](#uiux-conventions)
12. [Keyboard Shortcuts](#keyboard-shortcuts)
13. [Command-Line Interface](#command-line-interface)
14. [File Format Support](#file-format-support)
15. [Edge Cases & Special Notes](#edge-cases--special-notes)
16. [Windows-Only Features (Not for Mac)](#windows-only-features-not-for-mac)

---

## TOP-LEVEL FEATURE AREAS

The application is organized around these core capability buckets:

### 1. **Basic Search & Replace**
   - Text search in single or multiple files
   - Whole-file or multi-line search/replace
   - Case-sensitive/insensitive matching
   - Whole-word matching
   - Literal string search
   - File finding (search by file mask without content search)

### 2. **Regular Expression Search**
   - GREP-style regular expressions
   - Search operators: `*`, `+`, `?`, `|`, `!`, `^`, `$`, `^^`, `$$`, `[]`, `()`
   - Backreferences via `%n` notation (up to 31 parameters)
   - Column specifier (`+n`)
   - Range matching
   - Sub-expressions and grouping

### 3. **Binary Mode / Special Characters**
   - Multi-line search/replace
   - Special character input (tabs, line feeds, carriage returns)
   - Line ending handling (CRLF, LF, CR)
   - Prepend/append file operations
   - File reformatting at column boundaries

### 4. **File/Folder Targeting**
   - Include/exclude file masks with wildcards (`*`, `?`)
   - Complex file mask expressions (directory-aware filtering)
   - Size filters (file size ranges)
   - Date/time filters (date range filters)
   - File attribute filters (Archive, Read-Only, Hidden, System)
   - Subdirectory recursion with depth limiting
   - ZIP archive searching (search-only, not replace)
   - Local hard drives or UNC network paths
   - Drag-and-drop file/folder selection

### 5. **Scripting & Automation**
   - Multi-step search/replace scripts
   - Saved search/replace templates
   - Script editor with visual interface
   - Advanced script settings (options, comments, expressions)
   - Boolean expression evaluator for conditional processing
   - Iteration operator (repeat N times or until condition)
   - Linked scripts (script chaining)
   - Command-line script execution

### 6. **Batch Operations**
   - Multi-file replacement with confirmation controls
   - Preview of replacements before execution
   - Backup file management
   - Undo via batch file (SRUNDO.BAT)
   - File operations (copy, move, delete) on results
   - Batch date/time modifications ("Touch" function)

### 7. **Replacement Features**
   - Simple string replacement
   - Regex-based replacement with backreferences
   - Incrementing counters (auto-numbering)
   - Case conversion (uppercase, lowercase)
   - Special operators (file path, date, time, size, environment variables)
   - Math operations on numeric strings
   - Capitalization processing
   - Multi-file context-aware replacement

### 8. **Results Management**
   - Expandable/collapsible tree view of results
   - Customizable output columns
   - Results export (text, HTML, print)
   - Copy results to clipboard
   - Filter/search within results
   - Context viewer (inline editor)
   - Results list sorting
   - View in external editor/application

### 9. **Configuration & Persistence**
   - Preferences/options dialog (6 tabs)
   - Saved search/replace history
   - Favorites (saved search configurations)
   - Font and color customization
   - External editor/application associations
   - Tree-view style toggle
   - Display font configuration

### 10. **HTML & Character Encoding**
   - HTML mode (special character code handling)
   - Unicode file detection and handling
   - UTF-8 XML file support
   - ANSI/ASCII text files
   - UTF-16 support
   - Character code transformation

### 11. **Advanced Features**
   - Ignore whitespace mode
   - Boolean expressions (AND, OR, NOT with `&`, `|`, `~`)
   - Clipboard search/replace
   - Find files mode (by mask without content)
   - Find within search results
   - Search/replace current files only
   - External context viewer integration
   - HexView binary file viewer integration
   - Minimized/headless mode

---

## MAIN WINDOW & UI LAYOUT

### Primary Input Fields (Top Section)

**Search String Field**
- Accepts plain text, regular expressions, or binary mode strings
- History dropdown (combo box)
- Binary mode button to create multi-line/special-character searches
- Read-only when binary mode is active
- Max history configurable in General Options

**Replace String Field**
- Accepts plain text, replacement operators, or binary mode strings
- History dropdown (combo box)
- Binary mode button
- Can include special operators (`%%srpath%%`, `%%srfile%%`, `%%srdate%%`, etc.)
- Read-only when binary mode is active

**File Mask Field**
- Single filename or multiple masks separated by semicolon
- Include masks: `*.txt;*.doc`
- Exclude masks: `~*.exe;~*.dll`
- Wildcards: `*` (any chars), `?` (single char)
- Drag-and-drop support for files
- Complex mask editor button for directory-aware filtering
- History dropdown
- Can reference specific files directly

**Search Path Field**
- Directory path or UNC path (`\\server\share`)
- Special value: `Local Hard Drives` (searches all local drives)
- Browse button for path selection dialog
- Drag-and-drop support for folders
- History dropdown

### Button Row (Below Input Fields)

**Action Buttons:**
- Search (execute search only)
- Search and Replace (execute both)
- Touch Files (modify date/time/attributes of found files)
- File Operations (copy, move, delete files)

**Toggle/Mode Buttons:**
- Case Sensitive (toggle)
- Search Subdirectories (toggle)
- Whole Word Mode (toggle)
- Regular Expression (toggle)
- Search Archives/ZIPs (toggle)
- Ignore Whitespace (toggle)
- HTML Mode (toggle)

**Function Buttons:**
- View Context (display file content around search hit)
- Copy Results (to clipboard)
- Print Results (to printer)
- Save as HTML (view in browser)
- Save Results (to text file)
- Options (program settings)
- Script (open script editor)
- About (program info)
- Help (context help)
- Customize Toolbar (modify visible buttons)
- File Mask Editor (complex masks dialog)

### Results Section (Bottom)

**Search Results List:**
- Tree-view hierarchical display (files with nested hits)
- Collapsible/expandable hits per file
- Columns:
  - File name (with path details if configured)
  - Line number of hit
  - Hit count per file
  - File size (optional)
  - File date (optional)
  - Matched text or matched line
- Sort order configurable in Search Options
- Double-click to open context viewer
- Right-click context menu for additional operations
- Keyboard navigation (F4/F5 for file movement, spacebar for expand/collapse)

### Menu Bar

- **Actions**: Search, Search/Replace, Touch, File Operations, Delete From Backup, Exit
- **Edit**: Copy, Find in Results
- **View**: View Results as HTML, View Results as Tree, Expand All, Collapse All
- **Flags**: Toggle Case Sensitive, Subdirs, Whole Word, RegExp, ZIPs, Ignore Whitespace, HTML Mode
- **Favorites**: Save/Load search configurations
- **Help**: Contents, Help on Help, Keyboard Shortcuts, About

---

## SEARCH MODES & EXPRESSION TYPES

### 1. Plain Text Search
- Literal character matching (unless Regular Expression mode enabled)
- Case sensitivity controlled by flag
- Whole-word matching optional

### 2. Whole-Word Search
- Match only complete words (word boundary detection)
- Ignores partial word matches
- Works with plain text and regular expressions
- Cannot be used with HTML Mode or Ignore Whitespace simultaneously

### 3. Regular Expression Search
- GREP-style subset of UNIX regular expressions
- Enabled via toolbar button or Flags menu
- Cannot be used with HTML Mode or Ignore Whitespace simultaneously
- Default maximum regex size: 32,767 bytes (configurable in Search Options)

### 4. Binary Mode Search
- Multi-line searches across line boundaries
- Special character input (tab, CR, LF, etc.)
- Escape sequences: `\t`, `\r`, `\n`, `\xHH` (hex)
- Literal backslash represented as `\\`
- Can span any character except structured by line boundaries
- Used for binary files or structured text formats

### 5. HTML Mode Search
- Automatic ISO character code transformation
- Find "Search & Replace" even if raw text is "Search &amp; Replace"
- Cannot be used with Regular Expressions
- Search string uses plain text equivalents; document contains code equivalents

### 6. Ignore Whitespace Mode
- Ignores extra spaces, tabs, CR, LF characters
- Treats multiple whitespace as single match
- Cannot be used with Regular Expressions or HTML Mode

### 7. Boolean Expression Search
- Simple AND/OR/NOT without regex
- Enabled in Whole Word mode only
- Operators: `&` (AND), `|` (OR), `~` (NOT)
- Example: `word1&word2` finds both words; `word1|word2` finds either
- Cannot be combined with other modes

### 8. Clipboard Search/Replace
- Search or replace content in Windows clipboard
- Access via Shift+Ctrl+H keyboard shortcut
- Processes clipboard content instead of files

---

## REGULAR EXPRESSION SYNTAX

### Search Operators (Match Operators)

#### Basic Operators

| Operator | Name | Behavior | Examples |
|----------|------|----------|----------|
| `*` | Zero or More | Matches 0+ of the expression in `()` or `[]`. Alone, matches start of line to end. Does NOT match characters under ASCII 32 (space). | `*(is)` matches "is", "Miss", "Mississippi"; `*[0-9]` matches any digits; `Windows*[]95` matches up to 32767 chars between Windows and 95 |
| `+` | One or More | Matches 1+ of the expression in `()` or `[]`. Must have at least one match. Does NOT match chars under ASCII 32. | `+(is)` matches "is", "Miss" but not empty; `w+e` matches "wide", "write" but not "we" |
| `?` | Exactly One | Matches exactly one character, or one occurrence of `()` or `[]`. | `?(is)` matches "is"; `Win?95` matches "Win 95", "Win-95", "Win/95" |
| `\|` | OR | Matches either expression before or after the pipe. Use with `()`. | `(01\|02)+[0-9](/95\|/98)` matches "01/15/95" or "02/12/98" |
| `!` | NOT | Match when positive hit AND negative components both exist. Both required. | `?at!((b\|c)at)` matches "mat" or "sat" but not "bat" or "cat"; `*file!(beg*file)` matches "a file" but not "beginning of file" |
| `^` | Start of Line | Anchors expression to line beginning. Only one per search. | `^the` matches "the" at line start (case-insensitive if flag off) |
| `$` | End of Line | Anchors expression to line ending. Only one per search. | `end$` matches "end" at line end; `the end$` matches entire line beginning with "the" and ending with "end" |
| `^^` | Start of File | Anchors to file beginning. Cannot use inside `()`. | `^^First` matches "First" if on first line of file |
| `$$` | End of File | Anchors to file end. Cannot use inside `()`. | `*$$` matches last line of file |

#### Sub-Expression Operators

| Operator | Name | Behavior | Examples |
|----------|------|----------|----------|
| `[]` | Range | Character or range list. `[gdo]` is single chars; `[d-o0-2]` is ranges. When empty, `[]` matches all chars and equals `?[]`. Combine with `*`, `+`, `?` to modify. | `t[]e` matches "the", "toe"; `*[0-9]` matches any digit sequence; `[a-z]` matches lowercase letter |
| `()` | Sub-Expression | Groups expressions, usually with `\|` operator. | `Win( 95\|dows 95)` matches "Win 95" or "Windows 95" |
| `+n` | Column Specifier | Match exactly n columns before/after, or n columns of range. | `w+2[a-z]` matches "Wor" in "World"; `[ ]+5-15[0-9.]` matches number in column range |

### Special Literal Characters

If you want to search for these literal characters in a regex, precede with backslash:
```
- + * ? ( ) [ ] \ | ^ $ !
```

Example: to find literal `\example\path`, use `\\example\\path` in regex mode.

### Important Regex Notes

- **`.` (dot) is NOT supported** — use `?` for single char wildcard instead
- **`*`, `+`, `?`, `!` must precede `()` or `[]`** — otherwise assumed to match line start to line end
- **`^` and `$` cannot both appear in same expression** — use literal line boundary `\r\n` if anchoring to both start and end
- **Operators count in %n numbering** — e.g., `^+[ ][a-zA-Z]` has `%1=^`, `%2=+[ ]`, `%3=[a-zA-Z]`
- **Maximum regex size configurable** — default 32,767 bytes; increase if using binary characters or complex patterns
- **Overlapping matches** — multiple `*` operators in sequence can cause unpredictable results

---

## REGULAR EXPRESSION REPLACEMENT OPERATORS

### Basic Replacement: %n Backreferences

| Operator | Function |
|----------|----------|
| `%1`, `%2`, ... `%9` | Backreference to 1st through 9th search component |
| `%:` through `%N` (9-31 params) | Extended parameters using ASCII table: `123456789:;<=>?@ABCDEFGHIJKLMN` for params 10-31 |
| `%n` alone omitted | Removes/deletes that matched component |
| `%n%m` | Concatenate multiple matched components |

### Case Conversion Operators

| Operator | Function | Example |
|----------|----------|---------|
| `%n<` | Convert matched component to lowercase | Search: `+[A-Z]`; Replace: `%1<`; "HELLO" → "hello" |
| `%n>` | Convert matched component to uppercase | Search: `w+[a-z]`; Replace: `W%1>`; "windows" → "WINDOWS" |

### Counter Operators (Incrementing/Decrementing)

| Operator | Function | Behavior |
|----------|----------|----------|
| `%n>>` | Plain counter increment | Starts at (first found number + 1). Example: "page5.htm" → "page6.htm" |
| `%n<<` | Plain counter decrement | Starts at (first found number - 1). Example: "Var19" → "Var18" |
| `%n>starting_value>` | Counter with start value up | Increments from starting value. `%1>100>` → 101, 102, 103... |
| `%n<starting_value<` | Counter with start value down | Decrements from starting value. `%1<100<` → 99, 98, 97... |
| Digit preservation | Zeros respected | `%1>000>` starts at 001 (3 digits); `%1>0>` starts at 1 (1 digit) |
| Multi-file reset | Reset per file | By default, counters reset with each new file (configurable) |

### Math/Number Operations

| Operator | Example | Function |
|----------|---------|----------|
| `%n<formatstring(mathexpr)>` | `%1<%d(E1-1)>` | Evaluate math expression on %1; E1 refers to value of %1 |
| Supported math | `+`, `-`, `*`, `/`, `%` (mod) | Arithmetic operations in parentheses |
| Format specifiers | `%d`, `%f`, `%0.2lf`, etc. | Integer, float, formatted decimal output |

**Math Examples:**
- `page*[0-9].htm` → `page%1<%d(E1-1)>.htm` decrements page numbers
- Support for printf-style formatting (see Number Formatting Overview in docs)

### Special Replacement Operators (Non-Regex)

These work in regular replace operations, scripts, and binary mode WITHOUT needing regex enabled:

| Operator | Returns | Notes |
|----------|---------|-------|
| `%%srfound%%` | Current matched search string | The literal text that was found |
| `%%srpath%%` | Path of current file | Directory containing the matched file |
| `%%srfile%%` | Current filename | Just the filename, not path |
| `%%srfiledate%%` | File's date stamp (pre-replace) | Format system-dependent |
| `%%srfiletime%%` | File's time stamp (pre-replace) | Format system-dependent |
| `%%srfilesize%%` | File size in bytes (pre-replace) | Size before replacement |
| `%%srdate%%` | Current machine date | System date at execution time |
| `%%srtime%%` | Current machine time | System time at execution time |
| `%%srprepend%%` | Prepend marker | For prepend operations in binary mode |
| `%%srappend%%` | Append marker | For append operations in binary mode |
| `%%srformat%%=nn` | File format at column nn | For file reformatting operations |
| `%%envvar=VARNAME%%` | Environment variable value | E.g., `%%envvar=WINBOOTDIR%%` |

**Special Literal Characters in Replacement:**
If you want literal `%`, `\`, `<`, or `>` characters in your replacement, precede with backslash:
```
\% \\ \< \>
```

Example: to replace with literal `\path\file`, use `\\path\\file`.

---

## FILE/FOLDER TARGETING

### File Mask Syntax

#### Include Masks
- Basic: `*.txt` (all .txt files)
- Multiple: `*.htm;*.html` (semicolon-separated)
- Wildcards:
  - `*` = any characters
  - `?` = single character
  - `*.*;*.txt` = all files plus .txt files
  - `*.??1` = files with 3-char extensions ending in "1"
- Specific file: `index.html;myfile.txt`

#### Exclude Masks
- Syntax: prefix with `~` character
- Example: `*.*;~*.exe;~*.dll` (all files except .exe and .dll)
- Literal tilde: `\~` (e.g., `\~*.txt` finds files like `~backup.txt`)
- Exclude exclusion: `~\~*.txt` (exclude files like `~backup.txt`)

#### Complex File Mask Expressions
- Directory-aware filtering (include files in some subdirs, exclude from others)
- Use Include/Exclude Files & Directories editor dialog
- Create mask expressions like: `c:\source\*.txt;~c:\source\temp\*`
- Supports both file and directory name filtering

### Search Path Specification

| Path Type | Example | Behavior |
|-----------|---------|----------|
| Absolute path | `c:\users\documents` | Searches specified directory |
| Relative path | `..\files` | Relative to current location |
| UNC path | `\\server\sharename` | Network shares (respects access rights) |
| Local Hard Drives | `Local Hard Drives` | Special value: searches all local hard drives |
| UNC server | `\\server10` | Server share enumeration (searches `\\server10\c\`, `\\server10\docs\`, etc.) |

### Subdirectory Options

- **Search Subdirectories toggle** — enable to recursively search below specified path
- **Subdirectory depth limiting** — specify max recursion depth
- **Folder structure preservation** — backup path can mirror original folder structure
- **Single vs. multiple masks** — multiple file mask/path combinations create sequential folders in backup (Path1, Path2, etc.)

### Filter Options (Advanced Targeting)

#### Date/Time Filters
- **Before Date** — exclude files older than specified date
- **After Date** — exclude files newer than specified date
- **Reverse Filter toggle** — inverts logic to "include only"
- **Combined range** — both Before and After can work together (e.g., files modified in November 2024)
- **Format** — system date format

#### Size Filters
- **Less Than** — exclude files larger than specified size (in bytes)
- **More Than** — exclude files smaller than specified size
- **Reverse Filter toggle** — inverts to "include only"
- **Combination** — both filters can work together for exact size range

#### File Attribute Filters
- **Archive** (set/unset/ignore)
- **Read-Only** (set/unset/ignore)
- **Hidden** (set/unset/ignore)
- **System** (set/unset/ignore)

### File Type Support

#### Text Files (Full Support)
- `.txt`, `.ini`, `.cfg`, `.conf`
- `.htm`, `.html`, `.xml`, `.xhtml`
- `.c`, `.cpp`, `.h`, `.java`, `.cs`, `.py`, `.rb`, `.pl`
- `.bat`, `.cmd`, `.sh`, `.vbs`
- `.log`, `.csv`
- Any text-based format

#### Binary Files (Search Only)
- `.doc`, `.xls`, `.ppt` (Word, Excel, PowerPoint)
- `.pdf` (not directly searchable; need text extraction)
- `.exe`, `.dll` (Windows binaries)
- Custom binary formats

#### Encoded Files
- **ANSI/ASCII** — standard text (default)
- **Unicode (UTF-16)** — auto-detected; seamless search/replace
- **UTF-8** — auto-detected for `.xml` files; seamless search/replace
- **UTF-8 XML** — special handling for XML files with UTF-8 encoding

#### ZIP Archives (Search Only)
- **PKZIP-compatible** archives (.zip files)
- **Extraction path** — configurable temp extraction location
- **File masks apply inside ZIPs** — if mask is `*.txt`, only .txt files inside ZIP are searched
- **Restrictions:**
  - No replacements inside ZIPs (extract, modify, re-archive manually)
  - Password-encrypted files not supported
  - Context viewer doesn't edit ZIPs (display only)
  - Performance impact due to extraction overhead

### Special Path Syntax

- **Local Hard Drives** — searches all fixed/hard drives (not floppies/network by default)
- **Drag-and-drop** — drag files/folders from Explorer into Path or File Mask fields
- **Path history** — previous paths saved in combo box dropdown
- **Path expansion** — environment variables not automatically expanded in UI (but supported in scripts via `%%envvar=VAR%%`)

---

## REPLACEMENT & BATCH OPERATIONS

### Replacement Confirmation & Preview

**Replacement Options Dialog Settings:**

| Option | Behavior |
|--------|----------|
| **Prompt on each string** | Confirm every single match before replacing |
| **Prompt on each file** | Confirm once per file (all matches in that file) |
| **Prompt on all** | Show all matches without confirming (review mode) |
| **Skip all in file** | Confirm first hit, then option to skip rest of file |
| **No prompts** | Replace all without confirmation (dangerous!) |
| **Capitalization Processing** | Options for: Match Case, First Letter Cap, All Caps, Sentence Case |

### Backup & Undo Management

**Backup Functionality:**
- **Backup path** — directory to store copies of modified files
- **Write to Backup** — toggle to enable backup creation
- **Folder structure** — mirrors original directory tree or creates sequential folders (Path1, Path2, etc.)
- **Automatic SRUNDO.BAT** — batch file for undoing last replacement
  - Location: `C:\Users\<username>\AppData\Local\Search and Replace`
  - Only created if Backup Path is configured
  - Manual execution required (not integrated into UI)
  - Only reverses LAST replacement in multi-step scripts

**Backup Behavior with Scripts:**
- Single file mask/path: folder structure matches original exactly
- Multiple file mask/path entries: separate Path1, Path2, Path3... folders created
- Subdirectories: automatically created under each Path folder as needed

### Preserving File Metadata

- **Preserve Date/Time** — option to keep original file timestamps during replace
- **Touch Function** — separate utility to modify file dates/times/attributes without searching

### Batch Replace Workflow

1. **Search** → View results in tree
2. **Preview** (optional) → Select confirmation method in Replace Options
3. **Search and Replace** → Execute with selected prompts
4. **Backup** (if configured) → Copies of modified files saved
5. **Undo** (if needed) → Run SRUNDO.BAT manually

### File Operations (Post-Search)

After a search, operate on result files:

| Operation | Function |
|-----------|----------|
| **Copy** | Copy selected or all files to new location |
| **Move** | Move files to new location |
| **Delete** | Delete selected or all files (with confirmation) |
| **Rename** | Not directly supported; use search/replace on file paths in scripts |

Access via:
- Actions menu → File Operations
- F2 keyboard shortcut (with or without highlighted files)
- Right-click context menu on results

---

## SPECIAL OPERATIONS & OPERATORS

### Incrementing Counters (Full Details)

**Search Component:** `?[0-9]`, `+[0-9]`, or `*[0-9]`
- These are ordinary range operators, NOT numeric evaluators
- Match digit characters, not numeric values
- For `$53.00` style searches, use: `\$+[0-9].+[0-9]` (match dollars and cents separately)

**Replacement:**
- `%n>>` — increment from (matched value + 1)
- `%n<<` — decrement from (matched value - 1)
- `%n>starting>` — increment from specified starting value
- `%n<starting<` — decrement from specified starting value

**Examples:**
- `page5.htm`, `page2.htm`, `page4.htm` + search `page*[0-9]` + replace `page%1>>` → `page6.htm`, `page7.htm`, `page8.htm`
- `Var19`, `Var82`, `Var8` + search `Var*[0-9]` + replace `Var%1<100<` → `Var99`, `Var98`, `Var97`

**Multi-Counter Support:**
- Single search: `cat*[0-9] dog*[0-9]`
- Replace with different counters: `cat%1>> dog%2>100>`
- Must maintain position order: use `%1`, `%2` in same order as search

**Per-File vs. Global Counters:**
- Default: counters reset with each file
- Advanced Script: can configure to continue across files

### File Reformatting

**Operation:** Reformat files at specified column width

**Access:** Binary Mode dialog
- Search string: `%%srformat%%=nn` (where nn is column number)
- Replace string: the reformatted content or line breaks
- Useful for: fixed-width text, CSV normalization

**Example:**
- Reformat file to 80-character lines
- Insert line breaks at column 80 using `%%srformat%%=80`

### Prepend/Append Operations

**Prepend:** Add content to beginning of file
- Binary mode search: `^^` (start of file marker) or empty
- Binary mode replace: content + `%%srprepend%%`
- Confirmation dialog appears per file

**Append:** Add content to end of file
- Binary mode search: `$$` (end of file marker) or empty
- Binary mode replace: `%%srappend%%` + content
- Confirmation dialog appears per file

**Use Cases:**
- Add header comments to code files
- Add footer signatures to documents
- Add XML declarations to files

### Capitalization Processing

**Replacement Options dialog:**
- **Match Case** — preserve original case patterns
- **First Letter Capital** — capitalize first letter only
- **All Caps** — convert to uppercase
- **Sentence Case** — capitalize first letter of sentence
- Applied during replacement when enabled

### Math Operations on Strings

**Syntax:** `%n<formatspec(expression)>`

**Components:**
- `%n` — backreference to matched component
- `formatspec` — printf-style format: `%d`, `%f`, `%0.2lf`, etc.
- `expression` — arithmetic using E1, E2, ... E31 for parameter values
- Supported operations: `+`, `-`, `*`, `/`, `%` (modulo)

**Examples:**
- `page5.htm` + search `page*[0-9]` + replace `page%1<%d(E1-1)>` → `page4.htm` (subtract 1, integer)
- `Price: 100` + search `Price: *[0-9]` + replace `Price: %1<%0.2lf(E1*1.1)>` → `Price: 110.00` (multiply by 1.1, format 2 decimals)

### Environment Variables in Replacements

**Syntax:** `%%envvar=VARIABLE_NAME%%`

**Examples:**
- `%%envvar=WINBOOTDIR%%` — Windows boot drive (e.g., C:\)
- `%%envvar=USERPROFILE%%` — user home directory
- `%%envvar=PATH%%` — system PATH
- Any Windows environment variable accessible to process

**Availability:** Works in regular replace, binary mode, and scripts

### Date/Time Replacement Operators

| Operator | Returns | Format |
|----------|---------|--------|
| `%%srdate%%` | Current system date | System-dependent |
| `%%srtime%%` | Current system time | System-dependent |
| `%%srfiledate%%` | File's date (pre-replace) | Same as srdate format |
| `%%srfiletime%%` | File's time (pre-replace) | Same as srtime format |

**Note:** "Pre-replace" means these capture the file's timestamp BEFORE modification, useful for logging.

### Boolean Expression Operators (Non-Regex)

**Availability:** Whole Word mode only, Regular Expressions disabled, HTML Mode disabled

| Operator | Meaning | Example |
|----------|---------|---------|
| `&` | AND | `word1&word2` finds both |
| `\|` | OR | `word1\|word2` finds either |
| `~` | NOT | `~word` finds lines without word |
| Combination | Complex logic | `(word1&word2)\|word3` |

---

## SCRIPTING & AUTOMATION

### Script Overview

**Purpose:** Encapsulate multiple search/replace combinations, file masks/paths, and options in reusable files

**Storage:** ASCII text files (editable with any text editor), typically `.srs` extension

**Components:**
- Search and Replace strings (multiple pairs)
- File masks and paths (multiple pairs)
- Options settings (regular expression, case sensitivity, etc.)
- Advanced settings (comments, boolean expressions, iteration, linked scripts)

### Script Editor Tabs

1. **Search and Replace Strings Tab**
   - List of search/replace pairs to execute sequentially
   - Add/remove/edit/reorder entries
   - Insert from main dialog (Ctrl+Insert)
   - Replace all (Ctrl+Remove All)

2. **File Masks and Paths Tab**
   - List of mask/path combinations to process
   - Each pair processes all search/replace combinations against it
   - Insert from main dialog (Ctrl+Insert)
   - Replace all (Ctrl+Remove All)

3. **Advanced Settings Tab**
   - Script-level options override main dialog
   - Toggle: Case Sensitive, Regular Expressions, Whole Word, HTML Mode, Ignore Whitespace, etc.
   - Comments (free-form notes)
   - Boolean expression evaluator (conditional file processing)
   - Iteration operator (repeat script N times)
   - Linked scripts (chain to another .srs file after completion)

### Script Format (Text File Structure)

**Simple Format:**
```
[Search]
Find This
Replace With This

[Replace]
Find Again
New Replacement

[Paths]
c:\source\*.txt
c:\data\*.htm
```

**Advanced Format with Options:**
```
[Options]
Case Sensitive=1
Regular Expressions=0
Whole Word=0
/d /s /i /x /w

[Search]
pattern1
replace1

[Paths]
c:\test\*.txt
```

**Options Keys:**
- Case Sensitive: 0 or 1
- Regular Expressions: 0 or 1
- Whole Word: 0 or 1
- `/d` = Search Subdirectories
- `/s` = Search ZIPs
- `/i` = Case Insensitive
- `/x` = Regular Expression
- `/w` = Whole Word
- `/h` = HTML Mode

### Iteration Operator

**Purpose:** Repeat a script N times or until condition is met

**Syntax (in Advanced Settings):**
- `{n}` — repeat exactly n times
- `{*}` — repeat until no more matches (useful for recursive replacements)

**Example:**
- Script that converts complex markup in multiple passes
- `{5}` repeats script 5 times
- `{*}` continues until replacements stabilize (no changes in last pass)

### Linked Scripts

**Purpose:** Chain multiple scripts in sequence

**Configuration (in Advanced Settings):**
- Specify path to next script file
- After current script completes, automatically launch next script
- Useful for complex multi-stage transformations

**Command-Line Notes:**
- When launched from command line with `/c` switch, linked scripts work but with specific behavior
- Last script in chain handles any `/u` (minimized) or `/q` (quiet) flags

### Boolean Expression Evaluator

**Purpose:** Conditional file processing in scripts

**Availability:** Advanced Script Settings tab

**Syntax:** Custom expression language with variable support
- Variables: `%%srfile%%`, `%%srpath%%`, `%%srfiledate%%`, `%%srfilesize%%`, etc.
- Comparison: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Logic: `AND`, `OR`, `NOT`
- Wildcards: `*`, `?`

**Example:**
- Process only files larger than 1MB: `%%srfilesize%% > 1048576`
- Process only .c files: `%%srfile%% == *.c`
- Process only files before 2024: `%%srfiledate%% < 01/01/2024`

### Apply Script Function

**Purpose:** Apply a script transformation to search or replace strings before execution

**Use Cases:**
- Convert HTML entity references to plain text
- RTF escape code transformation
- Reserved character handling

**Workflow:**
1. Create transformation script (simple search/replace pairs)
2. In main dialog, open Binary Mode for search or replace field
3. Click "Apply Script" button
4. Select script file
5. Script transformations applied; result inserted into field
6. Execute search/replace normally

### Script Keyboard Shortcuts

| Shortcut | Context | Effect |
|----------|---------|--------|
| Ctrl+Click Script Button | Main Dialog | Dump current settings to `srdump.srs` in program directory |
| Ctrl+Insert | Script Tabs | Insert current main dialog search/replace or mask/path into script |
| Ctrl+Remove All | Script Tabs | Clear script, insert all current main dialog entries |

### Running Scripts from Command Line

**Launch Script:**
```
SR32 /c"path\to\script.srs" /s
SR32 /c"path\to\script.srs" /r
SR32 /c"path\to\script.srs" /s /q
```

**Flags:**
- `/c` — script file path (required)
- `/s` — perform search (required if not `/r`)
- `/r` — perform search and replace (required if not `/s`)
- `/q` — quiet mode (no user prompts)
- `/u` — minimized/headless mode (no UI)

---

## MENUS & MENU ITEMS

### Actions Menu
- **Search** → Execute search (Ctrl+F)
- **Search and Replace** → Execute search and replace (Ctrl+H)
- **Touch** → Modify dates/times/attributes of found files
- **File Operations** → Copy, move, delete found files (F2)
- **Delete Files From Backup Path** → Clear backup directory
- **Exit** → Close application

### Edit Menu
- **Copy** → Copy selected results to clipboard (Ctrl+C)
- **Find in Search Results** → Search within current results (F3)

### View Menu
- **View Results as HTML** → Open results in browser
- **View Results as Tree** — toggle tree-view style (nested files)
- **Expand All** → Expand all file hits
- **Collapse All** → Collapse all file hits

### Flags Menu
- **Case Sensitive** → Toggle case-sensitive matching
- **Search Subdirectories** → Toggle recursive directory search
- **Whole Word** → Toggle whole-word matching
- **Regular Expressions** → Toggle regex mode
- **Search Archives** → Toggle ZIP file searching
- **Ignore Whitespace** → Toggle whitespace-insensitive mode
- **HTML Mode** → Toggle HTML special character handling

### Favorites Menu
- **Save Favorites** → Save current search/replace/mask/path as named configuration
- **Load Favorites** → Restore saved configuration
- **Manage Favorites** → List and select favorites to load

### Help Menu
- **Contents** → Open help documentation
- **Help on Help** → Help about the help system
- **Keyboard Shortcuts** → Display keyboard shortcut reference
- **About** → Application version and info

### Right-Click Context Menu (Search Results)

**On File Entry:**
- View File → Open in associated application
- View Context → Display file with search hits highlighted
- External Editor → Open in configured external editor
- Copy → Copy line to clipboard
- Touch Selected Files → Modify dates/attributes of selected files
- Copy File List → Copy filenames to clipboard
- Delete Files → Delete selected files (with confirmation)

**On Hit Entry:**
- View Context → Show surrounding file content
- Copy → Copy search result line

---

## PROGRAM OPTION/PREFERENCE SETTINGS

### Options Dialog Structure
- 6 tabs: General, Display, Search, Replace, Output, Filters
- OK/Cancel/Help buttons
- Settings persist in Windows registry (Windows-specific)

### General Options Tab

| Setting | Type | Options |
|---------|------|---------|
| **Lines to View in Context** | Numeric | Default 5; affects context viewer display |
| **Display Font** | Selection | Font dialog; affects all text display |
| **External Editor Association** | Path | Program to use if no file type association |
| **Binary Editor/Viewer** | Path | Program for viewing binary files (HexView, etc.) |
| **Favorite Paths** | Text list | Frequently-used search paths |
| **Double-Click Behavior** | Radio | Open file or view context |
| **Cache Size** | Numeric | History list size for search/replace/mask/path |
| **Combo Box History** | Numeric | Number of previous entries saved |

### Display Options Tab

| Setting | Type | Purpose |
|---------|------|---------|
| **Result Font Color** | Color picker | Color of matched text in results list |
| **Filename Font Color** | Color picker | Color of filenames in results |
| **Line Color** | Color picker | Highlight color for result lines |
| **Tree View Style** | Toggle | Display results as tree (nested) or flat list |

### Search Options Tab

| Setting | Type | Options |
|---------|------|---------|
| **Maximum Regular Expression Size** | Numeric | Bytes; default 32,767; increase for complex patterns |
| **Stop after First Hit** | Toggle | Useful for large files; report first match only |
| **ZIP Extraction Path** | Path | Temporary directory for ZIP file extraction |
| **Search Binary Files** | Toggle | Include or exclude binary files from search |

### Replace Options Tab

| Setting | Type | Options |
|---------|------|---------|
| **Backup File Path** | Path | Directory to store backup copies |
| **Write Files to Backup Path** | Toggle | Enable backup creation |
| **Prompt Behavior** | Radio Buttons | Each string / Each file / All at once / Skip all in file |
| **Capitalization Processing** | Radio Buttons | Match Case / First Cap / All Caps / Sentence Case |
| **Change Date/Time** | Toggle | Preserve original timestamps or update |

### Output Options Tab

| Setting | Type | Purpose |
|---------|------|---------|
| **Show File(s) with No Hits** | Toggle | Include in output |
| **Show First Hit Only** | Toggle | Report only first match per file |
| **Show Replace String** | Toggle | Display replacement preview |
| **Show Hit Number** | Toggle | Number each match |
| **Display File Size and Date** | Toggle | Include in results |
| **Write Results to File** | Path | Save results to text file |
| **Append to Output File** | Toggle | Append or overwrite existing file |

### Filter Options Tab

| Setting | Type | Options |
|---------|------|---------|
| **Before Date (exclude)** | Date picker | Files older than this date excluded |
| **After Date (exclude)** | Date picker | Files newer than this date excluded |
| **Less Than (size exclude)** | Numeric | Files larger than this excluded |
| **More Than (size exclude)** | Numeric | Files smaller than this excluded |
| **File Attributes** | Checkboxes | Archive, Read-Only, Hidden, System (set/unset/ignore) |
| **Reverse Filters** | Toggle | Invert logic to "include only" |
| **Reset** | Button | Clear all filter settings |

### Font and Color Customization

**Font Dialog:**
- Family (typeface selection)
- Style (regular, bold, italic)
- Size (point size)
- Preview pane
- Apply to all result display

**Color Dialog:**
- System color picker
- Custom colors
- Separate selections for: results, filenames, lines, backgrounds

---

## UI/UX CONVENTIONS

### Main Window Layout Principles

**Top-to-Bottom Flow:**
1. Menu bar (Actions, Edit, View, Flags, Favorites, Help)
2. Toolbar buttons (Search, Search/Replace, Touch, File Ops, View, Copy, Print, HTML, Save, Options, Script, About, Help, Customize)
3. Input section (Search string, Replace string, File mask, Path)
4. Mode toggles (Case, Subdirs, Whole Word, RegExp, ZIPs, Whitespace, HTML)
5. Results pane (expandable/collapsible tree)

**Visual Feedback:**
- Highlighted matched text in results
- File count and hit count per file
- Tree expand/collapse icons (+/-)
- Toolbar buttons enable/disable based on context

### Results Pane Interaction

**Tree Structure:**
```
Filename [3 hits]
  + Line 12: matched text
  + Line 45: matched text
  + Line 67: matched text
Filename2 [1 hit]
  + Line 8: matched text
```

**Navigation:**
- Spacebar: toggle expansion on file names
- F4/F5: move between files
- Double-click: open context viewer
- Enter: open context viewer
- Right-click: context menu

### Context Viewer

**Purpose:** Inline file editor (registered version) or view-only (all versions)

**Layout:**
- File content in scrollable text area
- Line numbers
- Buttons: Save, Cancel, Page Up, Page Down, Previous Hit, Next Hit
- Keyboard shortcuts: Ctrl+C (copy), Ctrl+V (paste), Ctrl+X (cut), Ctrl+Z (undo)

**Editing (Registered Version Only):**
- Full text editing capabilities
- Save button to persist changes
- Cancel button to discard edits
- Undo/Redo support

**Special Handling:**
- Binary files: auto-launch HexView (freeware companion)
- ZIP files: extracted to temp path; edits not saved back to ZIP automatically
- Unicode files: transparent handling

### Drag-and-Drop Support

**Drop Targets:**
- Search Path field: drop folders from Explorer
- File Mask field: drop files from Explorer
- Results: copy filenames to clipboard via Ctrl+C

**Behavior:**
- Single file drop in mask field: sets mask to that filename
- Multiple file drop: comma or semicolon-separated list
- Folder drop in path: sets search path to that folder

### History/Autocomplete

**Preserved History:**
- Search strings (combo box dropdown)
- Replace strings (combo box dropdown)
- File masks (combo box dropdown)
- Search paths (combo box dropdown)
- Favorites (named configurations)

**Combo Box Behavior:**
- Click dropdown arrow to see history
- Type to filter or add new entry
- Previous entries reused when matching text

### Keyboard Shortcuts (Comprehensive List)

**Aborting/Controlling Search:**
- ESC — abort current search or Ctrl+Mouse click Search button

**Search & Replace Actions:**
- Ctrl+F — Search
- Ctrl+H — Search/Replace
- Ctrl+Alt+F — Search only current result files
- Ctrl+Alt+H — Search/Replace only current result files
- Shift+Ctrl+H — Clipboard Search/Replace

**Results List:**
- F2 — File Operations dialog (F2)
- F3 — Find in Results
- Ctrl+C — Copy results to clipboard
- Ctrl+Keypad + — Expand all hits
- Ctrl+Keypad - — Collapse all hits
- Spacebar (on filename) — Expand/collapse that file's hits
- F4/F5 — Move between file names
- Ctrl+S — Save results to file

**Context Viewer:**
- Ctrl+PgUp — Previous search hit
- Ctrl+PgDown — Next search hit
- PgUp/PgDn — Page up/down through file

**Other:**
- Ctrl+W — Swap Search and Replace strings
- Ctrl+Mouse Click Binary Mode button — Insert main dialog strings into binary dialog
- Ctrl+Mouse Click Script button — Dump settings to srdump.srs
- Ctrl+Insert (Script tab) — Insert main dialog entries
- Ctrl+Remove All (Script tab) — Replace all script entries with main dialog entries

### Toolbar Customization

**Feature:** Customize Toolbar button (button with icon of toolbar)

**Capability:**
- Select visible buttons
- Reorder button sequence
- Show/hide labels
- Icon size adjustment
- Reset to defaults

**Access:** Customize Toolbar button or right-click toolbar

---

## KEYBOARD SHORTCUTS

(See above in UI/UX Conventions section for full list)

---

## COMMAND-LINE INTERFACE

### Basic Invocation

```bash
SR32 [options] [/s "search string"] [/r "replace string"] [/p "path"] [/f "file mask"]
```

### Command-Line Switches

| Switch | Argument | Function | Example |
|--------|----------|----------|---------|
| `/s` | "search string" | Specify search string; starts search automatically | `/s"Find This"` |
| `/r` | "replace string" | Specify replace string; starts search/replace if `/s` also present | `/r"Replace With"` |
| `/p` | "path" | Specify search path | `/pC:\data\` |
| `/f` | "file mask" | Specify file mask | `/f"*.txt"` |
| `/b` | "backup path" | Specify backup directory | `/bC:\backup\` |
| `/c` | "script path" | Load and execute script (must add `/s` or `/r`) | `/c"C:\scripts\main.srs" /s` |
| `/i` | — | Case insensitive (default is case sensitive) | `/i` |
| `/x` | — | Regular expressions enabled | `/x` |
| `/w` | — | Whole word matching | `/w` |
| `/d` | — | Search subdirectories | `/d` |
| `/u` | — | Minimized/headless mode (no UI) | `/u` |
| `/q` | — | Quiet mode (no prompts) | `/q` |
| `/o` | "output file" | Write results to file | `/oC:\results.txt` |

### Special Notes

- **No spaces between switch and path** — `/pC:\data\` not `/p C:\data\`
- **Paths with spaces** — surround with quotes: `/p"C:\My Documents\"`
- **Quote characters in strings** — escape with backslash: `/s"Say \"hello\""`
- **Case sensitivity default** — case sensitive if `/i` not specified (opposite of UI default)
- **Scripts require action** — `/c` switch must pair with `/s` or `/r`; otherwise script loads but waits for user
- **Linked scripts** — work correctly with command-line launch but last script in chain is executed
- **Multiple instances** — use Windows `start /w` command for batch launching

### Examples

```bash
# Simple search to file
SR32 /sWindows /pC:\source\ /fC:\ /oC:\results.txt

# Search and replace with case-insensitive, subdirectories
SR32 /i /d /s"old text" /r"new text" /pC:\data\ /f"*.txt"

# Run script with search
SR32 /c"C:\scripts\convert.srs" /s /d /q

# Minimized mode (no UI)
SR32 /u /c"C:\scripts\batch.srs" /r
```

### Minimized Mode (`/u` flag)

**Behavior:**
- No window displayed
- No user interaction possible
- Runs to completion silently
- Useful for scheduled tasks, batch files, automation
- Requires all parameters to be specified on command line or in script
- Exit code indicates success/failure

---

## FILE FORMAT SUPPORT

### Text Files (Full Support for Search & Replace)

- ANSI/ASCII — Standard text encoding
- UTF-8 (XML files) — Auto-detected for `.xml` extension
- Unicode UTF-16 — Auto-detected; seamless search/replace
- DOS line endings (CRLF) — `\r\n`
- Unix line endings (LF) — `\n`
- Old Mac line endings (CR) — `\r`

### Binary File Types (Search Only)

**Microsoft Office Documents:**
- `.doc`, `.docm`, `.docx` — Word (RTF format better for replace)
- `.xls`, `.xlsm`, `.xlsx` — Excel
- `.ppt`, `.pptm`, `.pptx` — PowerPoint
- Word Perfect documents

**Other Formats:**
- `.pdf` — searchable if text-extractable
- `.exe`, `.dll` — Windows executables
- Custom binary formats

**Important Notes:**
- Replacements in Office files may corrupt internal structures (counters, formatting)
- Convert `.doc` to `.rtf` before replacing if possible
- See "Word Document Notes" in help for detailed guidance

### ZIP Archives

**Support:** Search only (no replace)
- PKZIP-compatible format
- File masks apply to contents
- Extraction path configurable
- Password-protected files not supported
- Slower performance due to temporary extraction

### Special Text Formats

**HTML/XML:**
- HTML mode for character code transformation
- UTF-8 XML auto-detected
- Standard text processing if not using HTML mode

**Code Files:**
- `.c`, `.cpp`, `.h` — C/C++
- `.java` — Java
- `.cs` — C#
- `.py` — Python
- `.pl` — Perl
- `.rb` — Ruby
- `.vbs` — VBScript
- All treated as plain text

**Configuration Files:**
- `.ini`, `.cfg`, `.conf`
- `.bat`, `.cmd`
- `.sh` (Unix shell)
- Plain text processing

---

## EDGE CASES & SPECIAL NOTES

### Regular Expression Quirks

1. **Dot (`.`) not supported** — use `?` for single character instead
2. **Operators must precede `()` or `[]`** — otherwise assumed to match start-to-end of line
3. **`^` and `$` cannot both appear** — use literal `\r\n` for line anchors instead
4. **`*` does not match chars under ASCII 32** — use `*[]` or `*[\0x-00-\xFF]` to include control chars
5. **Overlapping matches** — multiple `*` operators can cause unpredictable results
6. **Operator counting** — `^`, `$`, `^^`, `$$` count as %n parameters in replacements

### File Encoding Gotchas

1. **Unicode auto-detection** — seamless but may be fooled by non-standard BOMs
2. **UTF-8 XML only for `.xml`** — other UTF-8 files treated as ANSI
3. **Binary files** — can corrupt if internal structure depends on exact byte counts
4. **Line ending conversion** — may occur during save; cross-platform compatibility risk

### Counter Operations Limits

1. **Not numeric evaluators** — `*[0-9]` matches digit characters, not numbers
2. **Per-file reset** — counters reset with each file by default (configurable in advanced script)
3. **Multiple counters** — must maintain search order in replacement: if search has `*[0-9]` then `*[0-9]`, replace must use `%1` then `%2`
4. **Starting value precision** — `%1>000>` vs. `%1>0>` affects digit count of output

### ZIP Archive Limitations

1. **Search only** — no replacements; extract/modify/re-archive manually
2. **No auto-update** — context viewer edits not saved back to ZIP
3. **No password support** — encrypted ZIP members skipped
4. **Extraction overhead** — slower than direct file search

### Script Edge Cases

1. **Linked script behavior** — if first script has `/r`, second script `/s`, the `/r` from first applies to results
2. **Multiple mask/path backup** — creates Path1, Path2, etc. folders (may not align with original structure)
3. **Boolean expression** — `%%srfilesize%%` captures pre-replacement size
4. **Iteration operator** — `{*}` repeats until stabilization; can infinite-loop on certain patterns

### Windows-Specific Behaviors

1. **Registry storage** — settings persist in Windows registry (not applicable to Mac)
2. **UNC paths** — network sharing works but may be affected by access rights
3. **Environment variables** — expanded in `%%envvar=VAR%%` only, not in UI fields directly
4. **File associations** — double-clicking files in results launches associated programs
5. **SRUNDO.BAT** — Windows batch file for undo; manual execution required

### Performance Considerations

1. **Regex complexity** — simple patterns faster; nested groups and alternation slower
2. **Large files** — use "Stop after First Hit" in Search Options to speed up
3. **ZIP extraction** — extraction to temp path adds latency
4. **Binary file search** — slower than text; may want to exclude via filters

### Prompt/Confirmation Behaviors

1. **"Skip All in File"** — applies to remaining matches in current file only
2. **No Prompts** — cannot be undone via normal UI; requires SRUNDO.BAT
3. **Backup requirement** — SRUNDO.BAT only created if Backup Path configured
4. **Script multi-step** — SRUNDO.BAT only reverses last replace step

---

## WINDOWS-ONLY FEATURES (NOT FOR MAC)

The following features are specific to the Windows platform and should be skipped or adapted for Mac:

### 1. **Windows Registry Access**
- All preference storage via Windows Registry
- Not applicable to macOS (use plist files or similar)
- Command: No direct registry editing support in Search and Replace itself

### 2. **Windows Shell Integration**
- Explorer context menu ("Launch Search and Replace from Explorer")
- File association with Windows file types
- Shell extension integration
- Windows "Find Menu" integration

### 3. **File Associations & Executables**
- Double-clicking results launches associated .exe programs
- Associated application opening on search results
- Specific to Windows file association system

### 4. **UNC Network Paths**
- While networking concepts exist on Mac, UNC paths (`\\server\share`) are Windows-specific
- Mac uses SMB/AFP paths: `smb://server/share` or mounted volumes
- Path syntax differs significantly

### 5. **Windows File Attributes**
- Archive, Read-Only, Hidden, System bits
- Mac equivalent: Finder labels, locked flag, hidden flag (different model)
- Date/time modification same concept but attribute set differs

### 6. **SRUNDO.BAT (Undo via Batch File)**
- Specific to Windows batch file system (.bat files)
- Mac equivalent: shell script (.sh)
- Auto-generation and format would differ

### 7. **Environment Variables**
- Windows-specific variables: `WINBOOTDIR`, `USERPROFILE`, `PATH`
- Mac equivalents: `HOME`, `PATH`, system environment variables
- Variable names and availability differ

### 8. **Application Paths**
- Windows paths: `C:\Program Files\...`
- Mac paths: `/Applications/...` or `/usr/local/...`
- File system hierarchy completely different

### 9. **HexView Integration**
- Funduc's freeware HexView binary viewer for Windows
- Equivalent: xxd, hex dump utilities, or native viewers on Mac

### 10. **External Editors/Applications**
- Windows program paths and invocation differ
- File association model different
- Launch behavior must adapt to Mac application bundle structure

### 11. **Drag-and-Drop from Explorer**
- Specific to Windows Explorer file browser
- Mac equivalent: Finder drag-and-drop (similar mechanics but different app)

### 12. **Help System (CHM files)**
- HTML Help (.chm) is Windows-specific format
- Mac equivalent: HTML documentation, online help, or Mac help system

### 13. **Minimized Mode (`/u` flag)**
- Windows window minimization concept
- Mac equivalent: no window displayed (headless mode works similarly)

### 14. **Start Menu / Program Shortcuts**
- Windows Start Menu shortcuts
- Mac equivalent: Applications folder, Dock, Launchpad
- Completely different model

---

## RECOMMENDED PRIORITIES FOR MAC RE-IMPLEMENTATION

Based on feature frequency and user value:

### TIER 1 (Essential - Core Features)
1. Basic search and replace (text)
2. Regular expressions (GREP-style)
3. File mask targeting (include/exclude)
4. Subdirectory recursion
5. Results display and navigation
6. Context viewer (view/edit around hits)
7. Backup and undo functionality
8. Command-line interface

### TIER 2 (Important - High-Value Features)
1. Scripts and automation
2. Filter options (size, date, attributes)
3. Replacement operators (%n backreferences, special operators)
4. Binary mode / special characters
5. Unicode/UTF-8 file handling
6. Results export (text, HTML)
7. Keyboard shortcuts
8. Options/preferences dialog

### TIER 3 (Valuable - Common Use Cases)
1. Counters (incrementing/decrementing)
2. Boolean expressions
3. HTML mode
4. Math operations on numbers
5. Clipboard search/replace
6. Touch function (file date/time modification)
7. File operations (copy, move, delete)
8. Favorites (saved configurations)

### TIER 4 (Nice-to-Have - Niche Features)
1. ZIP archive searching
2. Advanced script features (iteration, linked scripts, boolean evaluator)
3. Ignore whitespace mode
4. Environment variable substitution
5. Prepend/append operations
6. File reformatting
7. Customizable toolbar
8. Find within results

---

## IMPLEMENTATION NOTES FOR MAC DEVELOPER

### Key Architecture Points

1. **Event-Driven UI** — button clicks trigger search/replace operations with modal progress
2. **Persistent History** — maintain combo box history for search strings, masks, paths (in macOS defaults or plist)
3. **Asynchronous Search** — prevent UI freeze during multi-file searches (use background threads)
4. **Results Tree Model** — nested file/hit hierarchy with expand/collapse (use NSOutlineView or equivalent)
5. **Operator Parsing** — complex regex engine; consider leveraging Foundation regex or ICU library

### File Access Considerations

1. Replace system registry storage with macOS defaults (`UserDefaults`) or plist files
2. Use macOS file paths (`/Users/...` instead of `C:\...`)
3. Adapt drag-and-drop to work with macOS Finder
4. Handle file permissions (read-only files, access denied)
5. Implement equivalent of SRUNDO functionality using shell scripts or native undo mechanism

### Encoding & Line Endings

1. Auto-detect UTF-8, UTF-16, ANSI (use system text encoding APIs)
2. Handle CRLF, LF, CR line endings transparently
3. Preserve original encoding and line ending on save
4. BOM detection for Unicode files

### Regular Expression Engine

- Consider using `NSRegularExpression` (Foundation) or ICU for GREP-like syntax
- Must support custom operators: `*`, `+`, `?`, `!`, `^`, `$`, `^^`, `$$`, `[]`, `()`
- Implement backreference substitution (%n notation)
- Ensure % character replacement operators work correctly

### Script Format

- Keep ASCII text file format (`.srs` extension) for cross-platform compatibility
- Parse INI-like structure: `[Search]`, `[Replace]`, `[Paths]`, `[Options]`, `[Advanced]`
- Support comments with `#` or `;`

---

## CONCLUSION

This feature catalog comprehensively documents Search and Replace for Windows as of the version documented in the decompiled HTML Help files (approximately v6.5+). The application is a sophisticated, feature-rich text and binary search utility with advanced regular expression support, scripting capabilities, and extensive batch operation controls.

For a Mac re-implementation targeting feature parity with nostalgic fidelity:

1. **Start with Core** (Tier 1) features to achieve 80% of typical user workflows
2. **Add Scripting** (Tier 2) for advanced users and batch automation
3. **Polish UI** to match macOS conventions while preserving original layout and terminology
4. **Adapt OS-Specific** features (file associations, environment variables, undo mechanism)
5. **Test Regex** extensively given complexity and user reliance on specific operators

The codebase is well-documented in the help system; implementation should reference this catalog for each feature's exact behavior and expected output.

