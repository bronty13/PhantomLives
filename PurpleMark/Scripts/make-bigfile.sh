#!/usr/bin/env bash
# Generates a mixed-content markdown fixture for large-file testing.
#   Usage: ./Scripts/make-bigfile.sh [size-mb] [output-path]
# Default: 100MB at /tmp/pm-bigfile-<size>mb.md
set -euo pipefail

SIZE_MB="${1:-100}"
OUT="${2:-/tmp/pm-bigfile-${SIZE_MB}mb.md}"

python3 - "$SIZE_MB" "$OUT" <<'PY'
import sys

size_mb, out = int(sys.argv[1]), sys.argv[2]
target = size_mb * 1_000_000

lorem = ("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do "
         "eiusmod tempor incididunt ut labore et dolore magna aliqua. ")

with open(out, "w", encoding="utf-8") as f:
    written = 0
    section = 0
    while written < target:
        section += 1
        block = []
        block.append(f"# Chapter {section}\n\n")
        block.append(f"Intro paragraph for chapter {section}. " + lorem * 3 + "\n\n")
        block.append(f"## Section {section}.1\n\n")
        block.append("- first item with **bold** text\n- second item with _italic_\n"
                     "- third item with `inline code`\n\n")
        block.append("```swift\n// fenced code block\nlet answer = 42\n"
                     "# not a heading inside a fence\nfunc demo() {}\n```\n\n")
        block.append(f"### Subsection {section}.1.1\n\n")
        block.append("| Col A | Col B | Col C |\n|---|---|---|\n"
                     "| one | two | three |\n| four | five | six |\n\n")
        block.append("> A blockquote with a [link](https://example.com) inside.\n\n")
        if section % 50 == 0:
            block.append("Some display math:\n\n$$\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}$$\n\n")
        if section % 200 == 0:
            block.append("```mermaid\ngraph TD; A-->B; B-->C; C-->A;\n```\n\n")
        block.append(lorem * 8 + "\n\n")
        text = "".join(block)
        f.write(text)
        written += len(text)

print(f"wrote {written/1_000_000:.1f} MB to {out}")
PY
