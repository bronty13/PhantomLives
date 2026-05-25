# PDF → Markdown conversion (Marker)

Reference for converting books, manuals, and other PDFs to Markdown for archival
and search. Uses [Marker](https://github.com/VikParuchuri/marker) — ML-based,
preserves headings, tables, lists, criteria sections, and ICD code blocks far
better than Pandoc or basic `pdftotext`.

## One-time install

```bash
# Marker needs Python 3.11 (PyTorch / transformers lag on newer Pythons).
# Use uv to install into an isolated tool environment.
uv tool install --python 3.11 marker-pdf
```

This drops six commands onto your PATH (`~/.local/bin/`):

| Command | Purpose |
|---|---|
| `marker_single` | Convert one PDF |
| `marker` | Batch-convert a folder of PDFs |
| `marker_chunk_convert` | Chunked batch processing for huge runs |
| `marker_extract` | Extract specific elements (tables, etc.) |
| `marker_gui` | Web GUI |
| `marker_server` | REST API server |

**First run downloads ~3–5 GB of ML models** to `~/Library/Caches/datalab/`.
Subsequent runs are fast.

## Convert a single PDF

```bash
marker_single ~/Downloads/Some-Book.pdf --output_dir ~/Documents/marker-output
```

Output lands in `~/Documents/marker-output/Some-Book/`:
- `Some-Book.md` — the markdown
- `Some-Book_meta.json` — per-page structure, table-of-contents, block stats
- Extracted images as `_page_N_Picture_M.jpeg`

## Convert a folder of PDFs

```bash
marker ~/Downloads/pdfs/ --output_dir ~/Documents/marker-output --workers 4
```

`--workers` controls parallelism. M-series Macs handle 4–6 fine.

## Useful flags

| Flag | Use case |
|---|---|
| `--page_range 0-9` | Convert a small sample first to spot-check quality |
| `--output_format markdown` | Default; also supports `json`, `html`, `chunks` |
| `--disable_image_extraction` | Skip images if you only want text |
| `--disable_ocr` | Skip OCR (faster, but breaks on scanned PDFs) |
| `--use_llm --llm_service ...` | Optional LLM pass to clean tables/equations (needs API key) |

## Performance notes (Apple Silicon)

- Marker uses MPS (Metal) acceleration automatically on Apple Silicon
- M4 Max + text-layer PDF (e.g., DSM-5 970 pages): **~56 minutes**
- M4 Max + Internet Archive scan reflow (DSM-5-TR IA version, 2091 pages): **~28 minutes**
  (sparse pages, less work per page)
- Process holds ~9 GB RAM with models loaded
- **Output is NOT written incrementally** — marker buffers everything in memory
  and writes the markdown atomically at the end. Empty output dir mid-run is normal.

## Backgrounding long runs

```bash
nohup marker_single ~/Downloads/Big-Book.pdf --output_dir ~/Documents/marker-output > /tmp/marker.log 2>&1 &
```

Then check progress in `/tmp/marker.log`. **Don't** pipe through `tail` — it
buffers and you'll see nothing until completion. Either redirect to a log file
(progress lines flush) or let it run plain.

## Verifying output quality

Always spot-check:
1. **Page count vs. line count.** If a 1000-page book yields only 4000 lines of
   markdown, the source is sparse or broken.
2. **Read the first 80 lines.** If you see "produced in EPUB format by the
   Internet Archive" or similar, your source PDF is a degraded re-render and
   quality is capped by IA's OCR — find a better source if possible.
3. **Spot-check the middle.** Pull a chunk from around line N/2 and look for:
   - Correct preservation of structural elements (criteria lists, tables)
   - Names spelled correctly (most reliable signal: contributor lists)
   - Clean ICD codes, drug names, technical terminology

## Source PDF quality matters MORE than marker settings

- **Real publisher PDF with embedded text layer**: near-perfect output, fast
  (marker uses `pdftext` for most pages, only OCRs images/scanned pages)
- **OCR'd scan of a physical book**: decent text, OCR errors baked in
- **Internet Archive automated EPUB → PDF**: lots of artifacts; names mangled
  ("Carlos Blanco" → "Carros Bianco", "Ph.D." → "Pa.D."), page boundaries weird
- **Image-only scan with no text layer**: marker will OCR via Surya — works but
  slow and error-prone

If output looks bad, suspect the input PDF before tweaking marker flags.

## Common gotchas

- **Disk space**: model cache is ~3–5 GB; conversions of large PDFs produce
  multi-MB markdown plus extracted images. Check free space first.
- **Wrong Python**: PyTorch wheels lag behind new Python releases. Force 3.11
  with `uv tool install --python 3.11 marker-pdf`.
- **`Recognizing Text` progress count**: this is per text-block, not per page.
  Don't use it to estimate completion percentage.
- **First page often image-only** (book cover); marker OCRs it but text is usually
  decorative — not a problem.

## Reinstall / upgrade

```bash
uv tool upgrade marker-pdf
# or fully:
uv tool uninstall marker-pdf && uv tool install --python 3.11 marker-pdf
```

Models in `~/Library/Caches/datalab/` persist across reinstalls.
