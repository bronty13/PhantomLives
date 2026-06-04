# PurpleMind — User Manual 🧠💜

Hi! Welcome to PurpleMind, your cozy little studio for untangling ideas. This
guide walks through everything the app can do. No jargon, promise.

## Opening the app

Launch **PurpleMind** like any other app. The first time, you'll see a friendly
welcome screen — click **Create your first map** to begin. Everything you make
is saved automatically to your computer; there's no "Save" button to remember.

## The sidebar (your maps)

On the left you'll find all your maps, newest at the top.

- **＋ New map** — start a fresh canvas.
- **Click** a map's name to open it.
- **Double-click** a name (or the ✎ pencil) to rename it.
- **🗑** removes a map for good (it asks first).

## Building a map

A map is made of **nodes** (your ideas) joined by **connections**.

- **Add a node:** click **＋ Node** in the toolbar, or **double-click** any
  empty spot on the canvas to drop one right there.
- **Edit a node:** **double-click** it and type. Press **Enter** to save, or
  **Shift+Enter** for a line break. **Escape** cancels.
- **Add a connected child:** select a node, then click **＋ Child** — a new node
  appears already linked to it. The new child becomes selected automatically, so
  you can **keep clicking ＋ Child to go deeper** (child → grandchild → …) for as
  many levels as you want. Click a different node first to branch from there
  instead.
- **Connect two nodes:** drag from the little dot on the right edge of one node
  to another node. (Duplicate links are merged automatically.)
- **Move things:** just drag. Your layout is remembered.
- **Delete:** select a node or connection and press **Delete** (or
  **Backspace**). Deleting a node removes its connections too.
- **Collapse a branch:** any node with children shows a little circle on its
  right — click it to **fold** the branch away (the circle then shows how many
  children are hidden); click again to unfold.

### How a map looks (root, branches, items)

PurpleMind styles your map by its shape, automatically:

- The **central topic** is a big bordered card.
- Each **main branch** off the center gets its **own color**, and everything
  hanging off that branch — plus its connecting lines — shares that color.
- Deeper **items** appear as text on a colored underline.

So you don't have to color anything by hand — but you can: select a main branch
and pick a swatch to recolor that whole branch, or select a single deeper node
to recolor just it.

### Keyboard shortcuts (fast mindmapping)

With a node selected (and not currently typing in it):

| Key | Does |
|---|---|
| **Tab** | Add a **child** of the selected node |
| **Enter** | Add a **sibling** (a child of the same parent) |
| **Space** | **Edit** the selected node's text |
| **Esc** | Cancel editing |
| **← ↑ → ↓** | Move the selection (←parent · →first child · ↑/↓ siblings) |
| **Delete / Backspace** | Delete the selected node or link |
| **⌘/Ctrl+Shift+L** | Tidy (auto-arrange) |
| **⌘/Ctrl+F** | Jump to the search box |

### Getting around the canvas

- **Pan:** drag the empty background.
- **Zoom:** scroll / pinch, or use the **＋ / －** controls (bottom-left).
- **⤢ Fit** re-centres everything in view.
- The **minimap** (bottom-right) shows the whole map at a glance.

### Make it tidy & pretty

- **✨ Tidy** instantly fans your map out to both sides of the center —
  perfect when things get messy. (Shortcut: **⌘/Ctrl+Shift+L**.)
- **Re-parent by dragging:** drop a node *on top of* another node to make it
  the new parent. Then ✨ Tidy to re-flow.
- **Search (⌘/Ctrl+F):** type in the toolbar search box to highlight matching
  nodes and dim the rest; press **Enter** to jump to each match in turn.
- **Colours:** select one or more nodes, then click a colour swatch. The **∅**
  swatch returns a node to its automatic branch colour.
- **Icons (😀):** select a node and pick an emoji to show before its label.
- **Checkboxes (☑):** select a node and click ☑ to give it a checkbox; click the
  box on the node to mark it done (the text gets a strikethrough). Click ☑ again
  to remove the checkbox. Checked items export to Markdown as `- [x]`.
- **Notes (📝):** select a node and click 📝 to attach a longer note. Nodes with
  a note show a small 📝 so you know it's there.

## Saving a copy (Export)

Open the **⤓ Export / Import** menu (top-right of a map) and pick a format:

| Format | Great for |
|---|---|
| **Image (PNG)** | Pasting into docs, chats, slides. |
| **Vector (SVG)** | Crisp at any size; editing in design tools. |
| **Document (PDF)** | Printing or sharing a clean page. |
| **PurpleMind map (JSON)** | A perfect backup you can re-import later. |
| **Mindmap diagram (.md / Mermaid)** | A Markdown file that *renders as a mindmap* in GitHub, Obsidian, Notion, VS Code — anywhere Mermaid is supported. |
| **Outline (.md)** | A plain bullet list of your ideas for any text app. |

Exports are saved to a **PurpleMind** folder in your **Downloads** by default,
and the file pops open in Finder/Explorer so you can find it. You can change
where exports go in **Settings → Export location**.

**Copy to clipboard:** the same menu has a *Copy to clipboard* section — grab
your map as a **Mermaid mindmap** (paste it into a `mermaid` code block) or as a
plain **Markdown outline**, ready to paste anywhere.

## Bringing ideas in (Import)

From the same **Export / Import** menu:

- **PurpleMind map (JSON)…** — re-open a map you exported earlier (as a new map).
- **Outline (Markdown)…** — turn an indented bullet list into a map. Indent with
  spaces or tabs; each deeper level becomes a child. PurpleMind tidies it for
  you automatically.

Imports always create a *new* map, so your existing maps are never touched.

## Settings

Click **⚙ Settings** at the bottom of the sidebar.

### Export location
Choose where exported files are saved, or leave it on the default
(`~/Downloads/PurpleMind/`). The box shows exactly where files will land.

### Backup (your safety net)
PurpleMind quietly backs up all your maps **every time you open it**.

- Backups are zipped into a **PurpleMind backup** folder in your **Downloads**.
- They're kept for **14 days** by default (change it, or set **0** to keep them
  forever).
- If you opened the app a few minutes ago, it won't make a duplicate backup.
- **Run Backup Now** makes one on the spot.
- For any backup in the list: **Test** checks it's healthy, **Restore** rolls
  your maps back to that point (it makes a safety copy first!), and **Reveal**
  shows the file.

You can turn auto-backup off or move the folder, but leaving it on is the safe,
happy choice. 💜

## Light & dark

The 🌗 button (bottom-left) cycles **Auto → Light → Dark**. Auto follows your
system setting.

---

Questions or ideas? PurpleMind is part of the PhantomLives toolkit — see
`README.md` for the developer side. Happy mapping! 🧠💜
