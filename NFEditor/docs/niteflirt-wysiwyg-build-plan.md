# NiteFlirt WYSIWYG Editor — Build Plan

A targeted WYSIWYG editor for creating NiteFlirt Flirt Profiles and Listings, working within NiteFlirt's specific HTML dialect and sanitizer constraints.

Source spec: https://support.niteflirt.com/hc/en-us/articles/212831098-Using-HTML (auth-walled; captured via MHTML)

---

## Platform constraints

### Hard limits

- **Flirt Profile**: max 7,000 characters of HTML
- **Listing**: max 14,000 characters of HTML
- **Listing width**: max 820px
- **Profile width**: 800px recommended (fixed) for cross-device consistency
- **Responsive breakpoints to design against**: 375px (mobile) / 800px (tablet) / 1075px (desktop)

### What's NOT supported (gotchas)

- **No JavaScript** — all event handlers (`onclick`, etc.) stripped
- **No CSS** — no `<style>` blocks, no external stylesheets, no `class` attribute. The `style` attribute IS in the allowed-attribute list and works in practice, so **inline style is the only CSS channel**.
- **No `<iframe>`** — not in the allowlist. No YouTube/Vimeo iframe embeds. Video must use `<video src>` or `<embed>`.
- **No emoji** — DESTRUCTIVE FAILURE MODE: when an emoji is placed, the emoji and everything after it gets stripped on save. The editor MUST block emoji entry and warn loudly.
- **No `class`, `rel`, `download`, ARIA, or `data-*` attributes** — not in allowlist.

### What IS supported (highlights)

- Full HTML 4 tag set including legacy: `<font>`, `<center>`, `<marquee>`, `<blink>`, `<table>` layout with `cellpadding`/`bgcolor`
- HTML5 media: `<video>`, `<audio>`, `<source>`, `<track>` (self-hosted)
- `<details>`/`<summary>` for collapsibles
- `<map>`/`<area>` image maps (useful for clickable composite images)
- `<embed>`/`<object>` with Flash-era attributes (legacy artifact)

Full allowlist is captured in `niteflirt-allowlist.json` — drop directly into sanitizer config.

### NiteFlirt-specific embeds (first-class blocks in editor)

These come from NiteFlirt's Payment Mail Buttons screen as HTML snippets; the editor needs to treat them as structured components, not raw HTML:

- **Goody / Pay-to-View buttons** — `<a href><img></a>` linking to a PTV mail
- **Tribute / Payment Request buttons** — same shape, different mail type
- **Flirt (call) buttons** — link to a listing
- **Wishlist links**
- **Image links** — images wrapped in any of the above

### Image hosting notes

- Any external host is fine, as long as it doesn't require linking back. Use only the `<img src=...>` portion of any embed code.
- NiteFlirt File Manager URLs follow pattern `https://www.niteflirt.com/fm/f/{a}/{b}` (no file extension, but they work).
- Animated GIFs uploaded to NiteFlirt's file manager **don't animate** — animated GIFs need external hosting.

---

## Architecture decision

### Editor framework: Tiptap

Tiptap (ProseMirror underneath) is schema-first. Define nodes with explicit `parseHTML` / `renderHTML` rules; anything not in the schema can't exist in the document.

This is the right shape because:
- Schema IS the allowlist — disallowed elements can't be represented
- `renderHTML` per node = full control over output (no fighting the editor's HTML normalization)
- `parseHTML` per node = round-trip import of existing NiteFlirt listings for free
- Headless — own the UI completely

### Why not the alternatives

- **TinyMCE / CKEditor 5** — feature-rich but aggressively normalize to modern semantic HTML. Will fight you on `<font>`, `<center>`, table layouts.
- **Quill** — too opinionated, mangles paste, hard to make output legacy-flavored.
- **Editor.js** — viable alternative (JSON-first, block-based). Choose this if you prefer assembling listings from pre-built blocks vs. document-style editing.

### Stack

- **Frontend**: React + Tiptap (Vue + Tiptap also fine)
- **Sanitizer**: DOMPurify with custom NiteFlirt allowlist config
- **Pretty-printer for "view source" mode**: `prettier` (html parser) or `js-beautify`
- **Storage**: client-side (localStorage / IndexedDB) — no backend strictly required; users paste output into NiteFlirt
- **Optional packaging**: Tauri or Electron for a native desktop app

---

## Block / node set to build

Map 1:1 to NiteFlirt's vocabulary:

| Node | Output |
|---|---|
| **TextBlock** | Paragraph with `<font face/size/color>` wrapping; bold/italic/underline as `<b>/<i>/<u>` (matching platform's own examples) |
| **Heading** | `<h1>`–`<h6>` + inline `style` for color |
| **Image** | `<img src width height alt>`, optionally wrapped in link |
| **Link** | `<a href target>` — wraps inline or block content |
| **Goody / PTV Button** | Structured: paste the NiteFlirt-generated snippet → parse to `{ptvUrl, label, imageUrl}` → render editing UI → export as original `<a href><img></a>` shape |
| **Tribute Button** | Same pattern as Goody, different snippet shape |
| **Flirt Call Button** | Link to listing / call-now page; image-based |
| **Section / Container** | Two modes: `<div style="width:...">` (compact) or `<table>` (legacy compatibility) |
| **Image Map** | Power-user: composite image with clickable hotspots via `<map>`/`<area>` |
| **Video** | `<video src controls>` — self-hosted only (no iframe) |
| **Marquee / Details/Summary / HR** | Cheap to support, all in allowlist |

---

## Serializer (the real work)

Two output modes sharing the same schema. User toggles without changing content.

### Mode 1: Compact

Minimum HTML, inline `style` for layout, modern-ish where possible. Burns fewer of the 14K characters.

### Mode 2: Legacy table

Nested `<table>` with `cellpadding`, `bgcolor`, `<font>` tags. Matches community template style; renders most consistently across older mobile browsers viewing NiteFlirt. Eats more characters.

Font size mapping (per official spec):
| Attribute | Display |
|---|---|
| `size="1"` | 8pt |
| `size="2"` | 10pt |
| `size="3"` | 12pt |
| `size="4"` | 14pt |
| `size="5"` | 18pt |
| `size="6"` | 24pt |
| `size="7"` | 36pt |

---

## Validator / safety layer

Run serialized output through DOMPurify (configured with the allowlist JSON) and **diff** against original. Three checks:

1. **Tag/attr stripping diff** — show "you used `<div class=...>` — the `class` will be stripped on save."
2. **Emoji scan** — block emoji on input, scan pasted content, refuse save if emoji present. *Most important single check* because of the silent-truncation failure mode.
3. **Live character counter** — 7K/14K thresholds based on mode (Profile vs Listing), color-coded as user approaches limit.

---

## Preview pane

Three-up responsive preview matching official breakpoints: **375 / 800 / 1075**.

- Render in an iframe with neutral chrome
- Desktop preview cuts off at 820px max width for listings (not full 1075)
- Approximate NiteFlirt's default font stack (Arial fallback)

---

## Nice-to-have: round-trip import

Existing NiteFlirt users have listings. A "paste my current listing here" import parses legacy HTML back into the block model, letting users migrate without rebuilding.

Tiptap's `parseHTML` hooks handle this directly — define matchers like "`<font color>` → TextBlock with `color` attribute" per node and import works automatically.

---

## Build order (MVP-first)

Validate the approach cheaply before committing to full scope:

1. **Set up Tiptap** with a minimal schema: TextBlock, Image, Goody Button only
2. **Build the legacy-HTML serializer** for those three nodes
3. **Build the validator/safety layer**: sanitizer diff + emoji blocker + char counter
4. **Round-trip-test** against 3–5 real existing listings — export to NF, view live, compare to original
5. If round-trip rendering matches: add remaining node types incrementally
6. If it doesn't match: debug serializer before expanding scope

---

## Open questions to resolve before building

1. **Single-user local app, or multi-user web app?** Affects storage / auth / hosting decisions.
2. **Desktop-native via Tauri/Electron, or pure web?** Pure web is simpler; native gets you file system access for image asset management.
3. **Is round-trip import important enough to be MVP, or can it wait?** Affects whether the parser side of the schema gets built in phase 1.
4. **Template library?** A handful of starter templates (matching the community-template aesthetic) would significantly reduce time-to-first-listing for new users.

---

## Reference files

- `niteflirt-allowlist.json` — structured allowlist (tags, attributes, limits, font mapping) ready for sanitizer config
