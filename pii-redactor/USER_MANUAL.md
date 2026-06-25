# PII Redactor — User Manual

PII Redactor finds and removes **personally identifiable information** (PII) from
a document — names, emails, phone numbers, Social Security numbers, addresses,
credit cards, bank routing numbers, dates of birth, and more — and gives you a
clean, redacted copy you can safely share.

Everything happens **on your own machine**. The tool is a single web page with no
server and no network access; your document never leaves your computer.

## Quick start

1. **Open** the page (double-click `pii-redactor.html`). The top-right status
   line should turn green and report the reference data it loaded.
2. **Load your text** — click **Load file…**, drag a file onto the left panel, or
   just paste into the box. Try **Load sample** to see it work immediately.
3. **Review** — detected PII is highlighted in the left panel and listed on the
   right. Each color is a different type.
4. **Choose a redaction style** (top toolbar) — labeled, numbered, or full mask.
5. **Copy** or **Download** the redacted result.

## Loading documents

You can get text into PII Redactor three ways:

- **Load file…** — opens a file picker.
- **Drag and drop** — drop a file anywhere on the left (Source) panel.
- **Paste** — click into the left box and paste.

### Supported file types

| Type | Examples | Notes |
| --- | --- | --- |
| Plain text | `.txt .csv .tsv .log .md .json .xml .yaml .html` | Read directly as text |
| PDF | `.pdf` | Text is extracted automatically |
| Word | `.docx` | Text is extracted automatically |
| Legacy Word | `.doc` | **Not supported** — save as `.docx` first |

> For PDF and Word files, the tool extracts the **text** and scrubs that. The
> download is a redacted **text** file (`yourfile.redacted.txt`), not a rebuilt
> PDF or Word document.

## Reading the results

The **left panel (Source)** shows your original document with every piece of
detected PII highlighted in a type-specific color.

The **right panel** has two tabs:

- **Redacted** — your document with each PII value replaced by a token.
- **Detected PII** — a grouped list of every value found, by type, with counts.

The number next to "Source" tells you how many items were found in total.

## Redaction styles

Pick a style from the **Redaction style** menu in the toolbar. You can switch at
any time and the output updates instantly.

- **Labeled** — each value becomes a bracketed type label, e.g. `[NAME]`,
  `[EMAIL]`, `[SSN]`. Simple and readable.
- **Numbered** — like labeled, but each distinct value gets a number that stays
  consistent, e.g. `[NAME_1]`, `[NAME_2]`. The **same** person stays `[NAME_1]`
  everywhere they appear, so relationships in the text are preserved while the
  real identity is removed. Useful when the structure of the document matters.
- **Full mask** — each value is replaced by a block of `████`, hiding even the
  type. Use this when you don't want to reveal what kind of data was there.

## Choosing which types to redact

Below the Source panel is a row of **type chips** — one per PII category, each
with its color and a live count. Click a chip to turn that type **off**; click
again to turn it back **on**. Turning a type off removes it from both the
highlights and the redacted output, so you can, for example, keep cities and
states visible while removing everything else.

## Copying and saving

- **Copy redacted** — copies the redacted text to your clipboard.
- **Download** — saves the redacted text to a file. The name keeps your original
  base name (`report.csv` becomes `report.redacted.csv`; PDFs and Word files
  become `report.redacted.txt`).

## What gets detected

| Type | What it finds |
| --- | --- |
| Name | First + last names (and `Dr./Mr./Mrs.` + surname) |
| Email | Email addresses |
| Phone | US phone numbers in many formats |
| SSN | Social Security numbers (`123-45-6789`) |
| Address / City / State / ZIP | Street addresses, suites, and US city/state/ZIP |
| VIN | 17-character vehicle identification numbers |
| Credit Card | Card numbers (checksum + brand validated) |
| Account | Long account-style numbers |
| Routing | Bank ABA routing numbers (checksum validated) |
| DOB | Dates of birth |
| IP Address | IPv4 and IPv6 addresses |
| Driver's License / Passport | License and passport numbers |

### Important: detection is careful, not perfect

To avoid flagging everyday numbers and dates in business documents, several
types are only detected when a **trigger word** appears nearby:

- **Dates of birth** need a label like *date of birth*, *DOB*, *born*, or *birth
  date* near the date. A plain due-date or invoice date is **not** flagged.
- **Bank routing numbers** need *routing*, *ABA*, *RTN*, or *transit* nearby, and
  must pass the official routing checksum.
- **Driver's license** and **passport** numbers need *driver's license* or
  *passport* labels next to them.

This keeps false alarms low, but it means some PII can be missed if it appears
without context. **Always review the results** before sharing — treat the tool as
a strong first pass, not a guarantee of complete coverage.

> One known trade-off: a lone 5-digit number next to a city/state is treated as a
> ZIP code. A genuine 5-digit *account* number would therefore be labeled `[ZIP]`.
> Either way it is redacted.

## Large files

Detection always runs, even on very large files. To keep the page responsive,
the **live highlighting** in the left panel automatically switches off above
roughly 600 KB of text (a note appears to tell you). The detected-PII list and
the redacted output remain fully active, so you still get complete, correct
results — you just won't see every item highlighted in place.

## Privacy

PII Redactor is designed so that your data **cannot** leave your machine:

- It is a single, self-contained web page — no server, no account, no cloud.
- A strict **Content-Security-Policy** blocks all outbound network connections
  (`connect-src 'none'`). Even if something tried to phone home, the browser
  would refuse.
- There is no analytics, no tracking, and no external fonts or libraries loaded
  at runtime — everything is built into the one file.

You can verify this yourself: open your browser's developer tools, go to the
Network tab, and confirm there are zero outbound requests after the page loads.

## Command-line use

For automation or batch jobs, the same detection engine is available as a
command-line tool. From the project folder:

```
node cli.mjs report.txt > report.redacted.txt
node cli.mjs --style numbered --types Name,Email,SSN report.txt
node cli.mjs --json report.txt        # list detections as JSON
cat notes.txt | node cli.mjs --stats  # read stdin, print counts
```

The CLI works on text input (and stdin). For PDF and Word files, use the app.

## Troubleshooting

- **The status line is red / says data is missing.** The reference data didn't
  load. Use the single built `pii-redactor.html` from `dist/` rather than the
  source template.
- **Copy didn't work.** Some browsers restrict clipboard access on local files.
  The tool falls back automatically, but if it still fails, switch to the
  **Redacted** tab and select the text manually.
- **A PDF produced little or no text.** Scanned PDFs are images, not text — there
  is nothing to extract. Use a PDF that contains real (selectable) text.
- **Something wasn't detected.** Detection is context-aware and conservative (see
  *detection is careful, not perfect* above). Review and redact manually if
  needed.
