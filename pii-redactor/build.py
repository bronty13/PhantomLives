#!/usr/bin/env python3
"""
build.py — assemble the self-contained PII Redactor.

Reads src/template.html and replaces each placeholder marker with an inlined
payload (reference data, vendor libraries, fonts, version), emitting one
fully-offline file at dist/pii-redactor.html.

Markers:
  <!--INLINE:version-->   project version string
  /*INLINE:fontface*/     @font-face rules with base64-embedded Inter woff2
  /*INLINE:data*/         the three pii-data/*.js files concatenated
  /*INLINE:pdfjs*/        vendor/pdf.min.js
  /*INLINE:mammoth*/      vendor/mammoth.browser.min.js
  /*INLINE:pdfworker*/    vendor/pdf.worker.min.js

No network access at build time beyond the one-time vendor fetch (already done).
"""

import base64
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
VERSION = (ROOT / "VERSION").read_text().strip() if (ROOT / "VERSION").exists() else "0.1.0"

SRC = ROOT / "src" / "template.html"
DATA = ROOT / "data"
VENDOR = ROOT / "vendor"
OUT = ROOT / "dist" / "pii-redactor.html"


def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8")


def js_safe(s: str) -> str:
    """Neutralize any literal </script that would otherwise close the host tag.
    Safe inside JS strings/regex (same value); cannot legally appear elsewhere."""
    return s.replace("</script", "<\\/script")


def strip_exports(s: str) -> str:
    """Turn an ES module into a plain inline script: drop import lines and the
    `export ` keyword so `export function f` becomes `function f` (a global in
    the inlined <script>). Node imports the same files unmodified."""
    out = []
    for line in s.splitlines():
        if re.match(r"^\s*import\s", line):
            continue
        out.append(re.sub(r"^(\s*)export\s+", r"\1", line))
    return js_safe("\n".join(out))


def b64(p: pathlib.Path) -> str:
    return base64.b64encode(p.read_bytes()).decode("ascii")


def fontface() -> str:
    reg = b64(VENDOR / "inter-400.woff2")
    semi = b64(VENDOR / "inter-600.woff2")
    return (
        "@font-face{font-family:'Inter';font-style:normal;font-weight:400;font-display:swap;"
        f"src:url(data:font/woff2;base64,{reg}) format('woff2');}}\n"
        "@font-face{font-family:'Inter';font-style:normal;font-weight:600;font-display:swap;"
        f"src:url(data:font/woff2;base64,{semi}) format('woff2');}}\n"
        "@font-face{font-family:'Inter';font-style:normal;font-weight:700;font-display:swap;"
        f"src:url(data:font/woff2;base64,{semi}) format('woff2');}}"
    )


def data_block() -> str:
    parts = []
    for name in ("first-names.js", "last-names.js", "places.js"):
        parts.append(js_safe(read(DATA / name)))
    return "\n".join(parts)


def main() -> int:
    if not SRC.exists():
        print(f"ERROR: missing template {SRC}", file=sys.stderr)
        return 1
    for f in ("pdf.min.js", "pdf.worker.min.js", "mammoth.browser.min.js",
              "inter-400.woff2", "inter-600.woff2"):
        if not (VENDOR / f).exists():
            print(f"ERROR: missing vendor file {f} (run the vendor fetch first)", file=sys.stderr)
            return 1

    manual_path = ROOT / "USER_MANUAL.md"
    manual_md = read(manual_path) if manual_path.exists() else "# User Manual\n\n_Not found at build time._"

    html = read(SRC)
    replacements = {
        "<!--INLINE:version-->": VERSION,
        "/*INLINE:fontface*/": fontface(),
        "/*INLINE:engine*/": strip_exports(read(ROOT / "src" / "engine.js")),
        "/*INLINE:redact*/": strip_exports(read(ROOT / "src" / "redact.js")),
        "/*INLINE:markdown*/": strip_exports(read(ROOT / "src" / "markdown.js")),
        "/*INLINE:data*/": data_block(),
        "/*INLINE:manual*/": js_safe(manual_md),
        "/*INLINE:pdfjs*/": js_safe(read(VENDOR / "pdf.min.js")),
        "/*INLINE:mammoth*/": js_safe(read(VENDOR / "mammoth.browser.min.js")),
        "/*INLINE:pdfworker*/": js_safe(read(VENDOR / "pdf.worker.min.js")),
    }
    for marker, payload in replacements.items():
        if marker not in html:
            print(f"WARNING: marker {marker} not found in template", file=sys.stderr)
        html = html.replace(marker, payload)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html, encoding="utf-8")
    size_mb = OUT.stat().st_size / (1024 * 1024)
    print(f"Built {OUT.relative_to(ROOT)}  ({size_mb:.2f} MB, v{VERSION})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
