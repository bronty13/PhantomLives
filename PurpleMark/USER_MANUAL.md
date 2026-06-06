# PurpleMark — User Manual

PurpleMark is a native macOS Markdown editor and the default opener + Quick Look
previewer for `.md` files.

## The window at a glance

- **Sidebar toggle** (top-left) — show/hide the sidebar.
- **View switch** — the **eye** shows the rendered **Document**; **`</>`** shows
  the **Markdown** source. (⌘1 / ⌘2.)
- **Title** — the current file name; a dot appears when there are unsaved edits.
- **Formatting** — **B** bold (⌘B), *I* italic (⌘I), ~~S~~ strikethrough; the
  **AA** menu sets text size, theme, and reading width; then bulleted/numbered
  list, blockquote, code block (`{}`), and link (⌘K).
- **Share** menu — Export to PDF / HTML, Open File, Open Folder.
- **Status bar** — word / character / line counts and reading time.

## Tabs

Open several documents at once in one window. Press **⌘T** for a new tab (or the
**+** on the tab strip), and **⌘W** to close the current tab. Opening a file
that's already open just switches to its tab. Each tab remembers its own text,
file, view mode, and scroll position; a dot on a tab means unsaved changes.

## Editing

Type in **Markdown** view; flip to **Document** view to see it rendered, with:

- GitHub-flavored markdown (tables, task lists, fenced code…)
- **Mermaid** diagrams — fence a block with ` ```mermaid `
- **LaTeX** math — inline `$…$` or display `$$…$$` / `\[ … \]`

Everything renders offline — no internet needed.

## Find & Replace

In the **Markdown** view, press **⌘F** to find (or **⌘⌥F** to find & replace).
The bar offers a case-sensitivity toggle (**Aa**), a **regex** toggle (**.\***),
a live "N of M" match count, and **⌘G / ⇧⌘G** to step through matches. Type a
replacement and use **Replace** or **Replace All**. Press **Esc** (or **Done**)
to close. (Opening find automatically switches to the Markdown view.)

## Sidebar: Outline & Files

- **Outline** — a live table of contents of your document's headings (H1 blue,
  H2 magenta…). Click a heading to jump to it.
- **Files** — open a folder (the folder button, or File ▸ Open Folder…) to
  browse and switch between its `.md` files.

## Make PurpleMark your default Markdown editor

The first time you launch PurpleMark, it offers to become your default Markdown
editor — click **Set as Default**. (You can also do it later: **Settings** (⌘,)
→ **Default Application** → **Set as Default for .md**.)

Now double-clicking a `.md` file in Finder opens PurpleMark, pressing **spacebar**
on a `.md` file shows a PurpleMark-rendered **Quick Look** preview, and `.md`
files get a **content-aware thumbnail icon** (a little page preview) in Finder.

## Exporting

**Share ▸ Export to PDF…** or **Export to HTML…** (or File ▸ Export). Output goes
to `~/Downloads/PurpleMark/` by default (change it in Settings ▸ Export). Mermaid
diagrams and math are preserved in both formats; the HTML is fully self-contained.

## Settings

- **General** — Zen mode, word wrap, auto-save.
- **Appearance** — theme, default view, reading width, editor contrast. Pick from
  the four built-in themes (Default / Nord / Solarized / One Dark) or **make your
  own**: click **New Custom Theme…** to open the theme editor, set each color with
  a color picker (with a live preview), name it, and Save. Custom themes appear
  alongside the built-ins and can be edited or deleted; they apply to the Document
  view and to PDF/HTML exports.
- **Editor** — font size, editor font (including accessibility fonts), line
  numbers, sync scroll, auto-close brackets & continue lists, spell check, tab
  width.
- **Writing** — Focus mode (dim other paragraphs), Typewriter mode (center the
  caret line), Zen mode.
- **Backup** — on-launch backup of your PurpleMark settings & recent-files list
  to `~/Downloads/PurpleMark backup/` (your `.md` documents are your own files on
  disk and are not part of this backup). Retention, folder, and **Run Backup
  Now** are here, with a list of recent archives.

## Spotlight search

Your Markdown is searchable in Spotlight — search for a word that appears *inside*
a `.md` file and Spotlight finds the file. (This works because PurpleMark registers
the Markdown file type with macOS; files in excluded locations like `/tmp` aren't
indexed.)

## Saving

⌘S saves; ⌘⇧S is Save As. With **auto-save** on, edits to an already-saved file
are written automatically after a brief pause.
