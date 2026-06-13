---
title: Quick Look & Preview
part: P02 GUI
est_time: 50 min read + 40 min labs
prerequisites: [00-finder-mastery, 01-window-management]
tags: [macos, quick-look, preview, pdf, sips, qlmanage, forensics, productivity]
---

# Quick Look & Preview

> **In one sentence:** macOS ships two overlapping but distinct document-viewing systems — Quick Look (the spacebar instant previewer, extensible via app extensions) and Preview.app (a full-featured PDF/image editor that makes Adobe Acrobat unnecessary for 90% of tasks) — and understanding both at the mechanism level unlocks workflows that Windows users typically reach for expensive third-party software to achieve.

## Why this matters

Most switchers learn that spacebar opens a preview and stop there. That leaves enormous power untouched: Quick Look can render code, Markdown, 3D models, and custom file types via extension bundles; `qlmanage` lets you drive it from scripts and automation; Preview.app can merge, reorder, redact, sign, annotate, and format-convert documents with zero Adobe dependency. For a forensics professional, the Quick Look thumbnail cache is also one of the most reliably incriminating artifacts on a macOS volume — it preserves thumbnail renderings of files long after deletion, and even after those files lived in an encrypted container.

---

## Concepts

### How Quick Look works under the hood

Quick Look is not Preview.app. It is a separate subsystem: the `com.apple.quicklookd` daemon (visible in `ps aux | grep quicklookd`) handles preview generation and caches results. When you press Space in Finder, the Finder asks `quicklookd` for a preview via XPC, and the daemon invokes the appropriate *generator* for the file's UTI (Uniform Type Identifier).

The daemon spawns its work in a sandbox. It writes rendered thumbnails to a per-volume SQLite-backed thumbnail cache under `/private/var/folders/<hash>/<hash>/C/com.apple.QuickLook.thumbnailcache/`. This path is inside your per-user `$TMPDIR` tree — the exact location varies but `getconf DARWIN_USER_CACHE_DIR` prints it:

```
getconf DARWIN_USER_CACHE_DIR
# → /private/var/folders/xy/abc123.../C/
```

> 🔬 **Forensics note:** The thumbnail cache is an SQLite database (`index.sqlite`) alongside rendered image files. It persists thumbnails of every file you have previewed — including files since deleted, files that lived inside VeraCrypt/TrueCrypt volumes, and files on external drives that are no longer mounted. The database records the original file path, inode, volume UUID, and a rendered preview image. During an investigation, parsing this cache with a tool like `sqlite3` or Autopsy's Quick Look module can prove a user *saw* the contents of a file even if they subsequently deleted it. The cache is not cleared on logout.

To clear the cache manually:
```bash
qlmanage -r cache
```

### Generator architecture: old vs. new

**Before macOS 15 Sequoia:** Generators were `.qlgenerator` bundles — CFPlugIn-based dynamic libraries installed in:
- `/System/Library/QuickLook/` (system, SIP-protected)
- `/Library/QuickLook/` (admin-installed)
- `~/Library/QuickLook/` (per-user)

**macOS 15 Sequoia and later (including macOS 26 Tahoe):** The `.qlgenerator` format is fully deprecated and no longer loaded. Generators are now proper **App Extensions** (`.appex` bundles) of two declared extension points:
- `quicklook.preview` — provides the interactive preview panel
- `quicklook.thumbnail` — provides Finder thumbnail icons

These are managed by `com.apple.quicklook.ThumbnailsAgent` and the `PlugInKit` subsystem. Extensions live inside their parent app's bundle at `AppName.app/Contents/PlugIns/ExtensionName.appex/`, or under `/System/Library/ExtensionKit/Extensions/` for system-provided ones.

**Developer API:** A Quick Look preview extension subclasses `QLPreviewProvider` (data-based, no UI) or implements `QLPreviewingController` (view controller, interactive). The extension declares the UTIs it handles in its `Info.plist` under `NSExtension → NSExtensionAttributes → QLSupportedContentTypes`. At runtime, the system's `QLPreviewController` presents the extension's output in a sandbox. This is exactly how PurpleMark ships both a thumbnail provider (`PurpleMarkThumbnail`) and a Quick Look preview extension (`PurpleMarkQuickLook`) — see [[PurpleMark]] for a reference implementation of both extension points.

> 🔬 **Forensics note:** To enumerate all Quick Look extensions active on a system:
> ```bash
> pluginkit -m -A -p com.apple.quicklook-ui-appearance  # preview extensions
> pluginkit -m -A -p com.apple.quicklook-thumbnail-ui    # thumbnail extensions
> ```
> The output shows bundle ID, version, and path for each registered extension. This is useful for identifying suspicious third-party extensions that might intercept document previews.

### What Quick Look can preview out of the box

On a stock macOS 26 Tahoe system, `quicklookd` handles:
- Images: HEIC, HEIF, JPEG, PNG, WebP, GIF, TIFF, RAW (via CoreImage)
- Video/audio: MOV, MP4, M4V, M4A, AAC, AIFF, MP3 (via AVFoundation)
- Documents: PDF, RTF, RTFD
- iWork: Pages, Numbers, Keynote (via iWork app extensions)
- Office: .docx, .xlsx, .pptx (via installed extensions; system provides basic support)
- Archives: .zip (shows file listing)
- Fonts: shows character specimen
- Code/text: plain text only (no syntax highlighting without third-party extension)
- 3D: .usdz, .reality (SceneKit-rendered, rotatable in the preview panel)
- AR Quick Look packages

Common types *not* handled without third-party extensions: Markdown (raw text only), EPUB, PSD, WebP animation sequences, binary plists.

Popular modern `.appex`-based extensions (compatible with Sequoia/Tahoe): **QLMarkdown** (Markdown with GFM syntax), **Syntax Highlight** (code with syntax coloring), **QuickLookASE** (Adobe Swatch Exchange), **WWDC for macOS** Quick Look (session videos). Check [github.com/Oil3/List-of-modern-Quick-Look-extensions](https://github.com/Oil3/List-of-modern-Quick-Look-extensions) for a curated list of `.appex`-based generators — do not install old `.qlgenerator` bundles on Sequoia or later, they will be silently ignored.

### Quick Look keyboard mechanics

| Action | Key / gesture |
|---|---|
| Open preview | Space |
| Close preview | Space or Esc |
| Full screen | Opt+Space (or click the expand icon) |
| Multi-select slideshow | Select multiple → Space, then arrow keys |
| Open in default app | Return (while preview is open) |
| Open in Preview.app | Cmd+Return |
| Markup from preview | Click the pencil toolbar button |
| Share from preview | Click the share button |

Multi-select slideshow mode deserves emphasis: select a folder of images with Cmd+A, press Space, and you get a navigable slideshow. This is the fastest way to triage photo sets without opening any app.

---

### Preview.app: mechanism and power

Preview.app is a full Cocoa application that uses Apple's PDF Kit (`PDFKit.framework`) for document rendering and `ImageIO.framework` for image I/O. It is emphatically not a viewer — it is a lightweight editor, and understanding its editing model unlocks a lot.

**PDF editing model:** PDFKit represents a PDF as a mutable document graph. Preview keeps the document open in memory and writes changes back on save. The on-disk format is always valid PDF — there is no proprietary project file. This is both a strength (the output is always a real PDF) and a source of confusion (every Save overwrites the original unless you use Duplicate or Export As).

#### PDF operations

**Page management (the killer feature most people don't know about):**

The Sidebar (View → Thumbnails, or Cmd+Opt+2) turns into a full drag-and-drop reorder interface. You can:
- Drag pages within a document to reorder them
- Drag pages *from one Preview window to another* to merge documents — drop a page thumbnail between two existing pages and it inserts there
- Select page thumbnails and press Delete to remove pages
- Insert a blank page: Edit → Insert → Blank Page
- Insert a page from another file: Edit → Insert → Page from File...

**Merging PDFs by drag in the sidebar** is the technique most people don't know:
1. Open both PDFs in Preview (they each get a window)
2. Show thumbnails (Cmd+Opt+2) in both
3. Drag a thumbnail from one sidebar and drop it into the other sidebar at the desired position

This is lossless — no re-encoding, no quality loss. PDFKit stitches the page streams.

**Splitting:** open a multi-page PDF, select the pages you *don't* want in one document, delete them, then File → Duplicate to produce the second half before deleting the other set from the original. Alternatively, drag individual page thumbnails out of the sidebar and drop them on the Desktop to extract them as standalone PDFs.

#### Redaction — and the critical gotcha

Preview.app has a proper Redaction tool (Tools → Redact, or the pencil toolbar's redact icon — it places a black box that, unlike a drawing rectangle, is *semantically* a redaction). The gotcha is significant:

> ⚠️ **ADVANCED:** Preview's redaction removes text *visually* and applies it as a PDF annotation, but **the underlying text stream may remain extractable until you flatten the document**. To guarantee the redacted text is gone:
> 1. Apply redactions with Tools → Redact
> 2. Use **File → Export as PDF** (NOT File → Save, NOT Cmd+S) — the Export path forces PDFKit to render each page as a flattened image, baking the redaction in and discarding all annotation/text layers
> 3. Verify: open the exported PDF, try selecting text in the redacted region — it should fail entirely
>
> Secondary: Preview does not run a metadata scrub. If the source document contains author info, document metadata, embedded attachments, or XMP data, those survive export. For court-ready redaction, use Acrobat's Sanitize function or strip metadata with `exiftool -all= output.pdf` afterward.

> 🔬 **Forensics note:** A PDF where the redaction is annotation-only (not flattened) is recoverable. If you receive a "redacted" PDF, immediately attempt text extraction with `pdftotext input.pdf -` or `strings input.pdf | grep -i <target>` before assuming the redaction holds. Many government agencies have accidentally leaked document text this way.

#### Form filling and signatures

Preview can fill PDF forms natively — click any form field and type. It uses PDFKit's `PDFAnnotationWidget` layer, so it works on any properly tagged AcroForm PDF.

**Digital signatures:** Preview lets you capture a signature three ways:
- Trackpad: Tools → Annotate → Signature → Manage Signatures → Create Signature → Trackpad (sign with your finger)
- Camera: hold a paper signature up to the FaceTime camera — it extracts the ink
- iPhone/iPad (Continuity): uses an iOS device's Apple Pencil or finger

Captured signatures are stored in Keychain (`/Library/Application Support/com.apple.Preview/Signatures/`) as data blobs, so they persist across app updates and appear in all Apple apps that integrate markup.

> 🪟 **Windows contrast:** On Windows, signing a PDF typically requires Adobe Acrobat (paid), a separate DocuSign/Adobe Sign account, or a browser-based tool. Preview captures, stores, and applies signatures with zero account requirements. For internal/personal use, this eliminates an entire SaaS category.

#### Image editing and format conversion

Preview opens essentially any image format `ImageIO.framework` understands, which is most of them: HEIC, HEIF, JPEG, PNG, TIFF, WebP, GIF, PDF, PSD (flattened), BMP, ICO, and RAW from most camera vendors (via CoreImage RAW). It can write back to JPEG, PNG, TIFF, PDF, and a handful of others via File → Export.

The Export dialog includes:
- Format picker
- Quality slider (for JPEG)
- Resolution override
- Color profile selection (you can force sRGB, P3, convert from ProPhoto RGB, etc.)

To **view color profile and metadata** on an open image: Tools → Show Inspector (Cmd+I) → Color Profile tab. This shows the embedded ICC profile name, color space primaries, bit depth, and whether the profile is device-specific. The EXIF/metadata tab shows camera model, lens, GPS coordinates, exposure data — useful for provenance checks.

**Instant Alpha / background removal:** With an image open, use the Instant Alpha tool (Tools → Annotate → Instant Alpha, or the magic wand in the toolbar). Click and drag over a background area; the selection grows as you drag. Hit Delete. This produces a PNG with transparency. For a forensics workflow: this is fast triage for isolating document scans from background noise.

---

### `qlmanage`: Quick Look from the command line

`qlmanage` is the Quick Look server diagnostic and management tool. Key flags:

```bash
# Preview a file in a Quick Look window (as if you pressed Space)
qlmanage -p file.pdf

# Preview multiple files
qlmanage -p *.jpg

# Generate a thumbnail PNG at 512px and write to ./out/
qlmanage -t -s 512 -o ./out/ document.pdf

# Generate a preview image (full render, not thumbnail) to disk
qlmanage -p -o ./out/ document.pdf

# List all registered Quick Look generators/extensions
qlmanage -m

# Show generator that would handle a specific file
qlmanage -m generators | grep -i markdown

# Reset Quick Look server (clears cache, forces generator re-discovery)
qlmanage -r

# Reset thumbnail cache only
qlmanage -r cache
```

`qlmanage -m` output is a structured list showing UTI → generator bundle ID → path. It is the definitive way to answer "what handles this file type?"

> 🔬 **Forensics note:** `qlmanage -t -s 256 -o /tmp/thumbs/ suspect-file.docx` generates a Quick Look thumbnail of a file *without opening any app*, useful for triage of unknown files in a sandboxed analysis. The rendered image can be examined without executing the document. Combine with `file`, `strings`, and `exiftool` for initial triage.

On macOS 26 Tahoe, `qlmanage` continues to work even though `.qlgenerator` bundles are gone — it drives the `.appex` extension pipeline transparently through the same XPC mechanism.

---

### `sips`: Scriptable Image Processing System

`sips` is a command-line image processor that ships with every macOS installation. It operates in-place by default (destructive!) unless you use `--out`:

```bash
# Inspect image properties (non-destructive)
sips -g all photo.jpg

# Get just dimensions
sips -g pixelWidth -g pixelHeight photo.jpg

# Convert format (WRITE to new file, keep original)
sips -s format png photo.jpg --out photo.png

# Convert entire folder of HEICs to JPEG
for f in *.HEIC; do
    sips -s format jpeg "$f" --out "${f%.HEIC}.jpg"
done

# Resize to max dimension 1200px, preserving aspect ratio
sips -Z 1200 photo.jpg --out resized.jpg

# Resize to exact dimensions (may distort)
sips -z 800 600 photo.jpg --out thumbnail.jpg

# Batch resize all JPEGs to max 800px wide, in-place (DESTRUCTIVE)
sips -Z 800 *.jpg

# Change DPI metadata (does NOT resample pixels)
sips -s dpiWidth 72 -s dpiHeight 72 photo.jpg

# Embed a color profile
sips --embedProfile /System/Library/ColorSync/Profiles/sRGB\ Profile.icc photo.jpg

# Strip all color profile
sips --deleteColorManagementProperties all photo.jpg
```

Supported output formats: `jpeg`, `png`, `gif`, `bmp`, `tiff`, `jp2`, `pict`, `heic`.

> ⚠️ **ADVANCED / DESTRUCTIVE:** `sips` without `--out` overwrites the original file immediately. There is no undo. Always test your command with `--out ./test_output/` before running on originals. For bulk operations, work on a copy: `cp -r originals/ working/ && cd working/ && sips ...`

> 🪟 **Windows contrast:** Windows has no built-in CLI image processor with this breadth. Typical Windows workflows require installing ImageMagick (open source), IrfanView, or using PowerShell with .NET imaging APIs. `sips` covers format conversion, resizing, profile manipulation, and metadata inspection with no installation.

---

## Hands-on (CLI & GUI)

### Quick Look in Finder

Open a Finder window with some mixed files. Select a HEIC photo and press Space — the preview panel appears with pixel dimensions, file size, and color profile shown at the bottom. Now select multiple JPEGs and press Space — arrow keys navigate the slideshow, up/down arrow changes the displayed file.

With a preview open, click the pencil icon to enter Markup mode: you can annotate, highlight text in PDFs, draw shapes, and crop images — all without opening Preview.app. The changes are saved back to the file when you close the markup toolbar.

### Checking your Quick Look extensions

```bash
# List all active Quick Look extensions
pluginkit -m -A -p com.apple.quicklook-ui-appearance

# Check what generator handles .md files
qlmanage -m | grep -i markdown

# Preview a file and watch the console output for debugging
qlmanage -p README.md 2>&1
```

### Generating thumbnails via script

```bash
mkdir /tmp/ql_thumbs
# Render 512px thumbnails for all PDFs in ~/Documents
qlmanage -t -s 512 -o /tmp/ql_thumbs/ ~/Documents/*.pdf
ls /tmp/ql_thumbs/
# Output: filename.pdf.png files
```

### Examining the thumbnail cache

```bash
# Find your Quick Look cache directory
QLCACHE="$(getconf DARWIN_USER_CACHE_DIR)com.apple.QuickLook.thumbnailcache"
echo "$QLCACHE"
ls "$QLCACHE"

# Inspect the SQLite index
sqlite3 "$QLCACHE/index.sqlite" ".tables"
sqlite3 "$QLCACHE/index.sqlite" "SELECT file_path, last_hit_date FROM thumbnails ORDER BY last_hit_date DESC LIMIT 20;"
```

---

## 🧪 Labs

### Lab 1: Merge, reorder, and extract pages from a PDF

**Goal:** Take two PDFs, combine them, reorder pages, then extract a subset.

**Setup:**
```bash
# Create two simple test PDFs from text files using Preview
echo "Page 1 content: Alpha" > /tmp/doc_a.txt
echo "Page 2 content: Beta" > /tmp/doc_b.txt
# Open each in TextEdit, print to PDF: File → Print → Save as PDF
# Or use any two PDFs you have on hand
```

**Steps:**
1. Open `doc_a.pdf` in Preview (double-click).
2. Open `doc_b.pdf` in Preview — both get separate windows.
3. Show thumbnails in both: Cmd+Opt+2.
4. In `doc_b`'s thumbnail sidebar, click the page thumbnail and drag it into `doc_a`'s sidebar — drop it after the last page of `doc_a`.
5. `doc_a` now has 2+ pages. Drag the thumbnails within the sidebar to reorder them.
6. Select the last page thumbnail, press Delete to remove it.
7. File → Export as PDF → save as `merged.pdf`.
8. Verify: `qlmanage -p /path/to/merged.pdf`

### Lab 2: Sign and annotate a document, then flatten

**Goal:** Practice the signature workflow and confirm export flattens annotations.

> ⚠️ **Precaution:** Use a throwaway document. The export step creates a new file; your original is safe unless you use Save in Place.

1. Open any multi-page PDF.
2. Tools → Annotate → Signature → Manage Signatures.
3. Create a signature from the Trackpad (draw with your finger) or Camera.
4. Place the signature on page 1 by clicking the Signature button in the toolbar and clicking a spot on the page.
5. Add a text annotation (Tools → Annotate → Text) in the margin.
6. File → Export as PDF → save as `signed_flat.pdf`.
7. Verify flattening: open `signed_flat.pdf` in Preview, try to click the signature — it should be inert/unselectable. Then try `strings signed_flat.pdf | grep -i annotation` — ideally returns nothing meaningful.

### Lab 3: Redaction with verification

> ⚠️ **Security-sensitive:** This lab is about confirming redaction works correctly. Do NOT use real sensitive documents for practice — use a dummy PDF.

1. Create a test PDF with `echo "SSN: 123-45-6789 is secret" | textutil -stdin -convert pdf -output /tmp/test_redact.pdf` — or open TextEdit, type a "secret" phrase, print to PDF.
2. Open the PDF in Preview.
3. Use Tools → Redact — draw over the secret text.
4. Save with Cmd+S. Now do **File → Export as PDF** and save as `test_redacted_flat.pdf`.
5. Attempt text extraction on both:
   ```bash
   # If pdftotext is installed (brew install poppler):
   pdftotext /tmp/test_redacted_flat.pdf - | grep -i secret
   # Should return empty — confirming flattened redaction removed the text stream

   # Raw string check:
   strings /tmp/test_redacted_flat.pdf | grep -i "SSN\|secret\|123"
   ```
6. If text is still recoverable, you saved with Cmd+S instead of Export as PDF — redo with Export.

### Lab 4: Batch image conversion and resize with sips

> ⚠️ **Destructive if run without --out.** All commands below use `--out` to a separate directory.

**Goal:** Convert a folder of HEIC photos to JPEG at 1500px max dimension, then strip GPS metadata.

```bash
# Create test directory structure
mkdir -p /tmp/sips_lab/originals /tmp/sips_lab/output

# Copy some HEIC/JPG images to originals/ (or use any images you have)
# cp ~/Pictures/some_photos/*.HEIC /tmp/sips_lab/originals/

# Inspect one image first
sips -g all /tmp/sips_lab/originals/photo.HEIC

# Batch convert HEIC → JPEG at max 1500px
for f in /tmp/sips_lab/originals/*.HEIC; do
    base=$(basename "$f" .HEIC)
    sips -s format jpeg -Z 1500 "$f" --out "/tmp/sips_lab/output/${base}.jpg"
done

# Verify output
sips -g pixelWidth -g pixelHeight /tmp/sips_lab/output/*.jpg

# Strip GPS/EXIF metadata from converted files (requires exiftool)
# brew install exiftool
exiftool -gps:all= -overwrite_original /tmp/sips_lab/output/*.jpg
exiftool -gps:GPSLatitude /tmp/sips_lab/output/*.jpg  # Should show no value
```

### Lab 5: Forensic Quick Look cache analysis

**Goal:** Observe what Quick Look caches after previewing files.

```bash
# Record current cache state
QLCACHE="$(getconf DARWIN_USER_CACHE_DIR)com.apple.QuickLook.thumbnailcache"
sqlite3 "$QLCACHE/index.sqlite" "SELECT COUNT(*) FROM thumbnails;" 

# Preview a specific file in Finder (spacebar), then run:
sqlite3 "$QLCACHE/index.sqlite" \
  "SELECT file_path, datetime(last_hit_date + 978307200, 'unixepoch', 'localtime') AS last_viewed 
   FROM thumbnails 
   ORDER BY last_hit_date DESC 
   LIMIT 5;"
# The file you just previewed should appear at the top

# Clear the cache
qlmanage -r cache
sqlite3 "$QLCACHE/index.sqlite" "SELECT COUNT(*) FROM thumbnails;"
# Count should drop to 0
```

> 🔬 **Forensics note:** The `last_hit_date` column uses Mac absolute time (seconds since 2001-01-01). The offset `978307200` converts it to Unix time for `datetime()`. A forensic examiner can cross-correlate these timestamps against browser history, file system timestamps, and Spotlight metadata to reconstruct a file-access timeline without relying on potentially-tampered file system timestamps.

---

## Pitfalls & gotchas

**1. Preview always modifies the original on Save.** Cmd+S in Preview overwrites the source file in-place. For PDFs you want to keep unmodified, use File → Duplicate before editing, or File → Export as PDF to produce a new file. There is no "Save As" — Export As is the replacement.

**2. Annotation vs. editing in PDFs.** Preview's markup tools (highlight, underline, note, drawing) produce PDF annotations that can be edited or deleted later, even after saving. This is intentional but unexpected: if you send a "highlighted" PDF to someone with Acrobat, they can delete your highlights. To permanently bake them in: File → Export as PDF flattens annotations (for most annotation types) into the page content. Signatures and redactions: same rule.

**3. Quick Look refuses to preview certain files.** If spacebar shows only a generic icon for a known file type, check: (a) the UTI declaration in the file's extension (use `mdls -name kMDItemContentType filename`); (b) whether the responsible extension is installed and registered (`qlmanage -m | grep UTI`); (c) sandboxing — Quick Look extensions run sandboxed and cannot access arbitrary paths unless granted entitlements.

**4. `.qlgenerator` bundles are dead on macOS 15+.** If you find old blog posts recommending installing `.qlgenerator` bundles into `~/Library/QuickLook/` for Markdown or code previews, those will not work on Sequoia or Tahoe. The replacement is `.appex`-based extensions delivered through apps.

**5. Merging PDFs resets form field interactivity.** When you drag pages between Preview windows to combine PDFs that both contain AcroForm fields, the resulting document may have conflicting field names. Form filling may break. For form-heavy PDFs, merge only in Acrobat or use `pdfunite` (from poppler) which is more conservative about the field namespace.

**6. sips format `heic` output requires macOS 11+ and Apple Silicon or a T2 Mac for hardware encode.** On Intel Macs without T2, `sips -s format heic` may fail or produce software-encoded files that are significantly slower to generate. Use `jpeg` or `png` as safe universal targets in scripts.

**7. Quick Look caches persist across reboots, deletions, and unmounts.** This is a privacy consideration as much as a forensics tool: previewing a sensitive file with Space caches a thumbnail that outlives the file. High-security workflows should disable Quick Look thumbnail generation via MDM profile (`com.apple.quicklook.source.app-allowed = false`), or manually run `qlmanage -r cache` before handing a machine over. FileVault encryption protects the cache from offline attacks, but not from in-session access by other processes running as the same user.

**8. Preview's "Instant Alpha" is single-channel and imprecise.** It flood-fills based on color similarity from the click point. For multi-color backgrounds or anti-aliased edges, use a dedicated tool. It is excellent for high-contrast document scans and solid-color web graphics, not for hair or complex natural images.

---

## Key takeaways

- Quick Look is a daemon (`quicklookd`) + XPC + extension architecture, not just a Finder feature. Extensions are now `.appex` bundles (not `.qlgenerator`) on macOS 15+.
- The Quick Look thumbnail cache at `$(getconf DARWIN_USER_CACHE_DIR)com.apple.QuickLook.thumbnailcache/index.sqlite` is a first-class forensic artifact: it records previewed file paths with timestamps, persisting after deletion.
- `qlmanage -p` previews files from the CLI; `qlmanage -t` generates thumbnails; `qlmanage -m` enumerates generators; `qlmanage -r cache` clears the cache.
- Preview.app can merge, split, reorder, annotate, sign, fill, and redact PDFs — covering the majority of Acrobat use cases, for free, without an account.
- **Redaction gotcha:** Cmd+S does not flatten redactions. You must use File → Export as PDF. Verify with `strings` or `pdftotext`.
- `sips` is a built-in lossless/lossy image processor: format conversion (`-s format`), resizing (`-Z` for aspect-preserved, `-z` for exact), metadata query (`-g all`), profile embedding — always use `--out` to avoid destroying originals.
- Preview's signature capture (Trackpad/Camera/Continuity) stores credentials in Keychain and persists across updates; no SaaS required for personal signing.

---

## Terms introduced

| Term | Definition |
|---|---|
| `quicklookd` | The Quick Look daemon; handles preview generation and caching via XPC |
| `.qlgenerator` | Legacy CFPlugIn-based Quick Look bundle format; deprecated in macOS 12, unsupported from macOS 15 |
| `QLPreviewProvider` | Modern Swift/ObjC protocol for data-based Quick Look preview extensions (`.appex`) |
| `QLPreviewingController` | Protocol for view-controller-based interactive Quick Look extensions |
| `PlugInKit` | Apple's extension management subsystem; manages discovery and lifecycle of `.appex` extensions |
| Quick Look thumbnail cache | SQLite + image files at `$TMPDIR/../C/com.apple.QuickLook.thumbnailcache/`; persists previewed file history |
| PDFKit | Apple framework (`PDFKit.framework`) underpinning Preview.app's PDF editing capabilities |
| AcroForm | Adobe's PDF form specification; PDF form fields that Preview can fill interactively |
| `sips` | Scriptable Image Processing System; macOS built-in CLI tool for image format conversion, resizing, and metadata manipulation |
| Mac absolute time | Seconds since 2001-01-01 00:00:00 UTC; used in Apple databases including the Quick Look cache (`unix_time = mac_time + 978307200`) |
| Flatten (PDF) | Rendering PDF annotations, redactions, and markup into the page content stream, making them permanent and non-editable |
| UTI | Uniform Type Identifier; reverse-DNS string (e.g. `public.jpeg`) that macOS uses to route files to appropriate apps and generators |

---

## Further reading

- **Apple Developer Documentation — Quick Look:** `developer.apple.com/documentation/quicklookui` — `QLPreviewProvider`, `QLPreviewingController`, and thumbnail API reference
- **Howard Oakley, The Eclectic Light Company** — "An overview of app extensions and plugins in macOS Sequoia" (April 2025) — authoritative breakdown of the extension migration from `.qlgenerator` to `.appex`
- **Oil3/List-of-modern-Quick-Look-extensions** (GitHub) — curated index of `.appex`-compatible Quick Look extensions for Sequoia and later; the replacement for the old Awesome-Quick-Look lists
- **`man qlmanage`** — full flag reference including the `-g` flag for per-generator debug output
- **`man sips`** — complete property key list for `-g`/`-s` and all supported format identifiers
- **Apple Platform Security Guide** (APSG) — chapter on sandboxing and extension isolation; explains why Quick Look extensions run in a hardened sandbox
- **EnCase Guidance Software: "Examination of the Mac OS X Quick Look Thumbnail Cache"** (2014) — still accurate regarding the SQLite schema; the cache format has been stable across macOS versions even as the generator architecture changed
- **macOS related lessons:** [[00-finder-mastery]] (UTIs and file metadata), [[01-window-management]] (Finder window model), and the upcoming [[08-spotlight-and-metadata]] (cross-correlating Spotlight timestamps with Quick Look cache for timeline reconstruction)
