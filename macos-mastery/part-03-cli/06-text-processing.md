---
title: "Text processing: grep, sed, awk, jq"
part: P03 CLI
est_time: 60 min read + 45 min labs
prerequisites: [02-shell-fundamentals, 03-essential-unix-commands, 05-defaults-and-plists]
tags: [macos, cli, grep, sed, awk, jq, regex, text-processing, forensics]
---

# Text processing: grep, sed, awk, jq

> **In one sentence:** macOS ships BSD-flavored grep, sed, and awk — subtly incompatible with GNU/Linux equivalents in ways that will silently break your scripts — so know the differences, reach for ripgrep and GNU tools from Homebrew when you need them, and add jq to complete the quartet for JSON-native analysis.

---

## Why this matters

Text processing is the connective tissue of command-line work. On macOS, these four tools are where Windows-to-Mac switchers and even experienced Linux users get burned, because the binaries you call by familiar names (`grep`, `sed`, `awk`) are BSD-lineage versions with different flags, different default behaviors, and missing features. The delta is small enough to be invisible in casual use and large enough to silently corrupt data in scripts.

For a forensics professional, every interesting artifact — log lines in `/var/log`, plist XML, JSON from `system_profiler`, structured output from `log show`, crash reports, network captures — arrives as text. Mastering these tools is the difference between manual inspection and pipeline automation across millions of records.

> 🪟 **Windows contrast:** PowerShell's `Select-String` (alias `sls`) provides grep-like matching with object output rather than raw text. `ConvertFrom-Json`, `ConvertTo-Json`, and `ForEach-Object` replace jq. The PowerShell pipeline passes .NET objects, not byte streams — powerful but fundamentally different. On macOS you pipe raw bytes and text; composability comes from POSIX conventions rather than a type system.

---

## Concepts

### The BSD vs. GNU fault line

macOS is built on Darwin, which inherits its userland tools from FreeBSD. The versions of `grep`, `sed`, and `awk` that ship with macOS are **BSD implementations**, not the GNU implementations that ship on Linux. Both families implement POSIX standards but diverge on extensions, flags, and edge-case behavior.

**The practical impact:**

| Tool | macOS ships | GNU equivalent via Homebrew | Install |
|------|------------|----------------------------|---------|
| grep | BSD grep (Apple-patched) | GNU grep → `ggrep` | `brew install grep` |
| sed  | BSD sed | GNU sed → `gsed` | `brew install gnu-sed` |
| awk  | nawk / one-true-awk | GNU awk → `gawk` | `brew install gawk` |
| find | BSD find | GNU findutils → `gfind` | `brew install findutils` |

The Homebrew packages install the GNU versions under `g`-prefixed names by default (`ggrep`, `gsed`, `gawk`, `gfind`). To shadow the stock commands, add Homebrew's `gnubin` paths to your `PATH` in `~/.zprofile`:

```zsh
# Add ALL gnu tool gnubin directories to PATH (before /usr/bin)
for d in /opt/homebrew/opt/*/libexec/gnubin; do
  export PATH="$d:$PATH"
done
```

This makes `grep` call GNU grep, `sed` call GNU sed, etc. **Understand what you're doing**: this changes behavior globally and may surprise macOS-native scripts (Apple's own install scripts use BSD idioms). Prefer the `g`-prefix approach in personal scripts until you understand the delta.

> 🔬 **Forensics note:** When running scripts on evidence machines or writing tooling that must work on stock macOS (no Homebrew), you must use BSD-compatible syntax. Your analysis workstation may have GNU tools, but the target system certainly won't.

---

### grep — find lines matching a pattern

#### The three regex modes

BSD grep and GNU grep both support three regex modes via flags:

| Flag | Mode | Notes |
|------|------|-------|
| (none) | BRE — Basic Regular Expressions | `\(`, `\+`, `\{n\}` — backslash before metacharacters |
| `-E` | ERE — Extended Regular Expressions | `(`, `+`, `{n}` — the natural syntax; **use this almost always** |
| `-P` | PCRE — Perl-Compatible RE | **Not available in BSD grep.** Requires GNU grep or `rg`. |

```bash
# BRE: match lines with one or more digits (awkward syntax)
grep '[0-9]\+' file.txt

# ERE: same, readable syntax (use -E always for non-trivial patterns)
grep -E '[0-9]+' file.txt

# PCRE: lookahead, lookbehind, named groups — BSD grep cannot do this
ggrep -P '(?<=Error: )\w+' /var/log/system.log
# or: rg '(?<=Error: )\w+' /var/log/system.log
```

#### Essential flags

```bash
grep -r          # Recursive into subdirectories
grep -i          # Case-insensitive
grep -n          # Print line numbers
grep -v          # Invert: print non-matching lines
grep -o          # Print only the matched portion, one match per line
grep -l          # Print only filenames with a match (not the lines)
grep -c          # Print count of matching lines per file
grep -F          # Fixed string (no regex); faster for literal searches
grep -w          # Match whole words only
grep -A 3        # Print 3 lines After each match (context)
grep -B 2        # Print 2 lines Before each match
grep -C 2        # Print 2 lines of Context (before + after)
grep --include='*.log'  # Restrict recursive search to filename glob
grep --exclude-dir='.git'  # Skip a directory in recursive search
```

Real example — find all launchd plists that reference a suspicious binary:

```bash
grep -rEl 'LaunchAgents|LaunchDaemons' /Library/LaunchAgents/ /Library/LaunchDaemons/ \
  ~/Library/LaunchAgents/ 2>/dev/null | head -20

# Find plist files that contain a specific path
grep -rn '/tmp/' /Library/LaunchDaemons/ /Library/LaunchAgents/ 2>/dev/null
```

#### The case for ripgrep (`rg`) as your daily driver

`rg` (ripgrep) is a Rust-based grep replacement that is:
- **Faster** — typically 2–5× faster than GNU grep on large trees (SIMD-accelerated, uses the Rust `regex` crate)
- **Smarter defaults** — skips `.git/`, respects `.gitignore`, skips binary files automatically
- **PCRE2 built-in** — `rg -P` works everywhere; no BSD/GNU distinction
- **Unicode-aware** by default

```bash
brew install ripgrep   # installs as `rg`
brew install fd        # installs as `fd` — the modern `find` companion

# rg examples
rg 'panic'                       # recursive from cwd, gitignore-aware
rg -i 'error|warning' /var/log/  # case-insensitive, multi-pattern via alternation
rg -l 'AuthorizationDB'          # filenames only
rg -n --type py 'import os'      # line numbers, Python files only
rg -o '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' access.log \
   | sort -u                      # extract unique IPs

# fd — find replacement; fast, gitignore-aware
fd '\.log$' /var/log/            # find .log files
fd -t f -e plist ~/Library/      # find plist files
```

> 🔬 **Forensics note:** `rg` is exceptional for triage of large log archives. `rg --stats --count-matches 'Failed password'` across `/var/log/` gives you frequency histograms instantly. The `--json` flag emits structured JSON output — pipeable to `jq`.

---

### sed — the stream editor

`sed` reads input line-by-line, applies a script of editing commands, and writes to stdout. The canonical use is substitution.

#### Substitution and the #1 cross-platform footgun

```bash
# Basic substitution: replace first occurrence of 'foo' with 'bar'
sed 's/foo/bar/' file.txt

# Global (all occurrences on each line)
sed 's/foo/bar/g' file.txt

# Case-insensitive (GNU sed only; not in BSD sed)
gsed 's/foo/bar/gi' file.txt

# With ERE patterns (use -E on both BSD and GNU sed)
sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/DATE/g' file.txt

# Capture groups with ERE
sed -E 's/(error|warning): (.*)/[\1] \2/' syslog.txt
```

#### In-place editing: THE footgun

This is the single most common cross-platform failure:

```bash
# BSD sed (macOS default) — REQUIRES an argument after -i, even if empty string
sed -i '' 's/foo/bar/g' file.txt    # correct on macOS
sed -i 's/foo/bar/g' file.txt       # BROKEN on BSD sed — '' becomes the backup suffix

# GNU sed (Linux, or gsed on macOS) — -i with NO argument
gsed -i 's/foo/bar/g' file.txt      # correct on Linux/GNU
gsed -i '' 's/foo/bar/g' file.txt   # BROKEN on GNU sed — tries to use '' as suffix

# Portable approach: use a backup suffix (works on both)
sed -i.bak 's/foo/bar/g' file.txt   # creates file.txt.bak; works everywhere
```

The `-i ''` (BSD) vs `-i` (GNU) split silently corrupts scripts that are copy-pasted between macOS and Linux. Always test in-place edits on a copy first.

#### Addresses, deletion, multi-command

```bash
# Delete blank lines
sed '/^$/d' file.txt

# Delete lines 1–5
sed '1,5d' file.txt

# Delete lines matching a pattern
sed '/^#/d' file.txt     # remove comment lines

# Print only lines 10–20 (then quit)
sed -n '10,20p' file.txt

# Multiple commands with -e
sed -e 's/foo/bar/g' -e 's/baz/qux/g' file.txt

# Or semicolons (GNU and modern BSD)
sed 's/foo/bar/g; s/baz/qux/g' file.txt

# Insert a line before line 3 (GNU syntax)
gsed '3i\inserted line' file.txt

# Append text after pattern match
gsed '/^Host /a\  ServerAliveInterval 60' ~/.ssh/config
```

> 🔬 **Forensics note:** `sed` is ideal for normalizing timestamps and stripping PII from logs before sharing. Strip IPv4 addresses: `sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/g'`

---

### awk — the programmable data extractor

awk is a full programming language that processes text field-by-field. It is dramatically underused by people who know only `grep` and `sed`.

#### macOS awk = nawk (one-true-awk)

macOS ships `nawk` — the "new awk" / "one true awk" by Aho, Weinberger, and Kernighan (the AWK in awk). It is maintained by Brian Kernighan and is actively updated: recent versions added UTF-8 awareness and CSV input support. It covers POSIX awk fully. For advanced features (network I/O, a debugger, profiler, namespaces, user-defined functions with arrays-by-reference), install `gawk`:

```bash
brew install gawk   # installs as gawk; also replaces awk if you use gnubin path
```

For the vast majority of text processing, macOS `awk` is sufficient.

#### Mental model: pattern { action }

```
awk 'BEGIN { setup }  /pattern/ { action }  END { teardown }' file
```

- Every line is split into fields `$1 $2 ... $NF` by `FS` (default: whitespace).
- `$0` is the whole line. `NF` = number of fields. `NR` = current record number.
- `BEGIN` runs once before any input. `END` runs once after all input.
- Patterns can be regexes (`/foo/`), comparisons (`$3 > 100`), or ranges (`/start/,/end/`).

```bash
# Print second field of each line (e.g., extract PIDs from ps output)
ps aux | awk '{print $2}'

# Sum the 5th column (e.g., file sizes from ls -l)
ls -l | awk 'NR>1 {sum += $5} END {print sum, "bytes"}'

# Custom field separator: parse /etc/passwd
awk -F: '{print $1, $7}' /etc/passwd          # username → shell
awk -F: '$7 != "/usr/bin/false" {print $1}' /etc/passwd   # users with real shells

# OFS — output field separator
awk -F: 'BEGIN{OFS=","} {print $1,$3,$7}' /etc/passwd   # CSV out

# Pattern + action: print lines where 4th field > 1000
awk '$4 > 1000 {print NR": "$0}' data.txt

# Count occurrences of unique values in column 3
awk '{count[$3]++} END {for (k in count) print count[k], k}' access.log | sort -rn

# Reformat: swap columns 1 and 2
awk '{print $2, $1}' file.txt

# Range pattern: print everything between START and END markers
awk '/^BEGIN/,/^END/' logfile.txt

# Multi-line record processing with blank-line RS
awk 'BEGIN{RS=""; FS="\n"} /error/ {print NR": "$0"\n---"}' mail.log
```

#### Practical awk one-liners for macOS

```bash
# Summarize network connections by state (from netstat)
netstat -an | awk '/^tcp/ {state[$6]++} END {for(s in state) print state[s], s}' | sort -rn

# Parse system_profiler SPHardwareDataType for model and serial
system_profiler SPHardwareDataType | awk -F': ' '/Model Name|Serial Number/ {print $2}'

# Calculate average CPU usage from top snapshot
top -l 2 -n 0 | awk -F'[:,% ]+' '/CPU usage/ && NR>5 {print "user="$3"% sys="$5"% idle="$7"%"}'

# Deduplicate while preserving order (unlike sort -u)
awk '!seen[$0]++' file.txt
```

> 🔬 **Forensics note:** awk excels at structured log analysis. The pattern `{array[$field]++}` + `END` report idiom produces frequency tables from gigabyte-scale logs in seconds — useful for finding anomalous source IPs, rare User-Agent strings, or unusual process names in `log show` output.

---

### jq — JSON at the command line

`jq` is the de facto standard for processing JSON on the command line. On macOS it is essential because:
- `defaults export` emits plist XML, but `plutil -convert json` converts it to jq-processable JSON
- `system_profiler -json` outputs rich structured JSON
- Every modern API, `curl` response, and log aggregator speaks JSON
- `log show --style json` emits structured unified log entries

```bash
brew install jq
```

#### Filter syntax

```bash
# Identity — pretty-print JSON
jq '.' file.json

# Extract a field
jq '.name' file.json

# Nested field
jq '.hardware.cpu' file.json

# Array index
jq '.[0]' array.json
jq '.[-1]'           # last element

# Iterate array
jq '.[]' array.json

# Extract field from every element of an array
jq '.[].name' users.json

# Raw string output (no JSON quotes) — critical for shell use
jq -r '.[].email' users.json

# select() — filter array elements
jq '.[] | select(.age > 30)' users.json
jq '.[] | select(.type == "error")' events.json

# map() — transform each element
jq 'map(.name)' users.json
jq 'map(select(.active == true))' users.json

# Multiple fields with object construction
jq '.[] | {name: .name, email: .email}' users.json

# Pipe within jq
jq '.results | .[] | .id' response.json

# keys, length, type
jq 'keys' object.json
jq '.items | length' file.json

# has() and in
jq '.[] | select(has("error"))' events.json

# String interpolation
jq -r '.[] | "\(.name): \(.score)"' scores.json

# @csv, @tsv — output formatters
jq -r '.[] | [.name, .score] | @csv' scores.json

# --arg to pass shell variables safely
jq --arg host "$HOSTNAME" '.[] | select(.host == $arg)' events.json
# (note: use $arg not $host inside jq; --arg name value)
jq --arg h "$HOSTNAME" '.[] | select(.host == $h)' events.json
```

#### jq with macOS-specific tools

```bash
# Parse system_profiler JSON — list all installed apps with version
system_profiler SPApplicationsDataType -json \
  | jq -r '.SPApplicationsDataType[] | "\(.path)\t\(.version)"' \
  | sort

# Find apps NOT from Mac App Store (no bundle ID prefix)
system_profiler SPApplicationsDataType -json \
  | jq -r '.SPApplicationsDataType[]
    | select(.obtained_from != "mac_app_store")
    | "\(.path)\t\(.obtained_from)"'

# Extract hardware info
system_profiler SPHardwareDataType -json \
  | jq -r '.SPHardwareDataType[0] | "Model: \(.machine_model)\nSerial: \(.serial_number)\nCPU: \(.cpu_type)"'

# Parse unified log JSON output
log show --last 1h --style json 2>/dev/null \
  | jq -r '.[] | select(.messageType == "fault") | "\(.timestamp) \(.process): \(.eventMessage)"' \
  | head -20

# defaults → JSON (plutil bridges plist to JSON)
defaults export com.apple.finder - \
  | plutil -convert json -o - - \
  | jq '.AppleShowAllFiles'

# Convert a plist file to JSON
plutil -convert json -o - /path/to/file.plist | jq '.'
```

> 🔬 **Forensics note:** `system_profiler -json` is your first-pass triage tool for unknown Macs. Pipe to jq to extract installed software, hardware IDs, network interfaces, and startup items in seconds. The `SPStartupItemDataType` and `SPLoginItemDataType` types are directly relevant to persistence analysis. See [[09-spotlight-metadata-and-xattrs]] and [[10-unified-logging-and-diagnostics]] for more artifact sources.

---

### The supporting cast

These tools are often overlooked but fill in the gaps that grep/sed/awk/jq leave:

#### cut — extract columns from delimited text

```bash
cut -d: -f1,3    # delimiter colon, fields 1 and 3
cut -d, -f2-4    # CSV, fields 2 through 4
cut -c1-80       # character positions 1–80

# Extract process names from ps
ps aux | cut -c66-   # characters 66 onward (the COMMAND column)
```

#### tr — character-level translation and deletion

```bash
tr 'a-z' 'A-Z'           # uppercase
tr -d '\r'               # strip Windows carriage returns (critical for cross-platform files)
tr -s ' '                # squeeze repeated spaces to one
tr -d '[:punct:]'        # delete all punctuation
echo "hello" | tr 'a-z' 'A-Z'   # → HELLO
```

> 🔬 **Forensics note:** `tr -d '\r'` is essential when analyzing files that originated on Windows — the `\r\n` line endings cause grep to silently fail to match patterns that would otherwise match.

#### sort — sort lines

```bash
sort -n              # numeric sort
sort -rn             # reverse numeric
sort -k2,2n          # sort by field 2, numeric
sort -t: -k3,3n      # delimiter colon, field 3 numeric (e.g., sort passwd by UID)
sort -u              # sort and deduplicate
sort -R              # shuffle (random order)
```

#### uniq — deduplicate and count (requires sorted input)

```bash
sort file | uniq -c   # count occurrences of each unique line
sort file | uniq -d   # print only lines that appear more than once (duplicates)
sort file | uniq -u   # print only lines that appear exactly once (unique)
```

#### wc — word/line/character/byte counts

```bash
wc -l file.txt    # line count
wc -w             # word count
wc -c             # byte count
wc -m             # character count (multibyte-aware)
ls /usr/bin | wc -l    # how many commands in /usr/bin?
```

#### paste — join files side-by-side

```bash
paste file1.txt file2.txt          # join columns with tab
paste -d, file1.txt file2.txt      # join with comma delimiter
paste -s file.txt                  # serialize one file to one line
```

#### column — align output in columns

```bash
column -t -s,  file.csv          # render CSV as aligned table
mount | column -t                # align mount output
```

#### fold — wrap long lines

```bash
fold -w 72 -s longfile.txt      # wrap at 72 chars, break at word boundaries
```

#### rev — reverse characters in each line

```bash
echo "hello" | rev    # → olleh
# Use with cut to extract the last field of a path:
echo "/usr/local/bin/grep" | rev | cut -d/ -f1 | rev   # → grep
```

#### comm — compare sorted files

```bash
comm -13 sorted1.txt sorted2.txt   # lines only in file2 (not in file1)
comm -23 sorted1.txt sorted2.txt   # lines only in file1
comm -12 sorted1.txt sorted2.txt   # lines in both files
```

> 🔬 **Forensics note:** `comm` is excellent for diffing software manifests. `comm -13 baseline_apps.txt current_apps.txt` shows applications installed since a known-good snapshot.

---

### Regex flavors summary

| Flavor | Used by | Key metacharacters |
|--------|---------|--------------------|
| BRE (POSIX Basic) | `grep`, `sed` default | `\+`, `\?`, `\(`, `\{n\}` |
| ERE (POSIX Extended) | `grep -E`, `sed -E`, `awk` | `+`, `?`, `(`, `{n}` |
| PCRE | `ggrep -P`, `rg` | `(?:...)`, `(?<=...)`, `\b`, `\d`, `\w`, named groups |
| RE2 | `rg` default | Like PCRE minus backtracking (unbounded RE2 has linear-time guarantee) |

Key differences from PCRE that trip up macOS users:
- `\d`, `\w`, `\s` **are not valid** in BRE/ERE — use `[0-9]`, `[a-zA-Z0-9_]`, `[[:space:]]`
- POSIX character classes: `[[:alpha:]]`, `[[:digit:]]`, `[[:alnum:]]`, `[[:space:]]`, `[[:punct:]]`
- Lookahead/lookbehind requires PCRE — use `ggrep -P` or `rg`

---

## Hands-on (CLI & GUI)

### BSD vs. GNU behavior check

Run these to confirm which versions you have:

```bash
grep --version 2>&1 | head -1        # "grep (BSD grep) ..." or "grep (GNU grep) ..."
sed --version 2>&1 | head -1         # "sed (GNU sed) ..." or just "usage: sed ..."
awk --version 2>&1 | head -1         # "awk version ..." (nawk) or "GNU Awk ..."

# Check if gtools are installed
which ggrep gsed gawk 2>/dev/null
```

### The `-i` trap in practice

```bash
# Demonstrate BSD vs GNU -i behavior safely
echo "hello world" > /tmp/test_sed.txt
sed -i '' 's/world/macOS/' /tmp/test_sed.txt   # BSD — correct
cat /tmp/test_sed.txt                            # → hello macOS

# See what BSD sed creates with a suffix
echo "hello macOS" > /tmp/test_sed.txt
sed -i.bak 's/macOS/again/' /tmp/test_sed.txt
ls /tmp/test_sed*   # both .txt and .txt.bak exist
```

### Field extraction with awk

```bash
# Parse system network config
ifconfig | awk '/^[a-z]/ {iface=$1} /inet / {print iface, $2}'

# Top 10 most common processes right now
ps aux | awk 'NR>1 {print $11}' | sort | uniq -c | sort -rn | head -10

# Disk usage report: top 5 directories under /usr
du -sh /usr/*/ 2>/dev/null | sort -rh | head -5
```

### jq workflow with system_profiler

```bash
# Get model info compactly
system_profiler SPHardwareDataType -json | jq '.SPHardwareDataType[0] | {
  model: .machine_model,
  chip: .chip_type,
  memory: .physical_memory,
  serial: .serial_number
}'

# Count apps by where they were obtained from
system_profiler SPApplicationsDataType -json \
  | jq '[.SPApplicationsDataType[].obtained_from] | group_by(.) | map({(.[0]): length}) | add'
```

---

## Labs

### Lab 1 — Reformat a CSV with awk

**Goal:** Transform a raw CSV with inconsistent quoting into a clean TSV with a computed column.

```bash
# Create sample data
cat > /tmp/sales.csv << 'EOF'
Alice,Engineering,95000,2019
Bob,Marketing,72000,2021
Carol,Engineering,110000,2018
Dave,Design,68000,2022
Eve,Engineering,125000,2016
EOF

# Task 1: Print name and department, tab-separated
awk -F, '{print $1 "\t" $2}' /tmp/sales.csv

# Task 2: Calculate years of tenure (assuming current year 2026) and add as column
awk -F, 'BEGIN{OFS=","} {tenure=2026-$4; print $1,$2,$3,tenure}' /tmp/sales.csv

# Task 3: Average salary by department
awk -F, '{
  dept_sum[$2] += $3
  dept_count[$2]++
} END {
  for (d in dept_sum)
    printf "%s: avg $%.0f\n", d, dept_sum[d]/dept_count[d]
}' /tmp/sales.csv | sort

# Task 4: Filter Engineering, sort by salary descending, emit CSV
awk -F, '$2 == "Engineering" {print $3, $1}' /tmp/sales.csv | sort -rn \
  | awk '{print $2","$1}'
```

Expected output of Task 3 (approximate):
```
Design: avg $68000
Engineering: avg $110000
Marketing: avg $72000
```

---

### Lab 2 — Mass-rename with sed (safe pattern)

> ⚠️ **ADVANCED / DESTRUCTIVE:** This lab modifies filenames in place. Run in `/tmp/` only. Back up any real files before adapting this pattern. To roll back: `mv` the files back using the `.bak` log or re-run with the substitution reversed.

```bash
# Create test files
mkdir -p /tmp/rename_lab
cd /tmp/rename_lab
touch "Report 2024-01-15.txt" "Report 2024-02-20.txt" "Report 2024-03-05.txt" \
      "Notes 2024-01-15.txt" "Notes 2024-02-20.txt"

# Preview: generate rename commands (dry run — don't execute yet)
ls *.txt | sed -E "s/(.+) ([0-9]{4})-([0-9]{2})-([0-9]{2})\.txt/mv '& ' '\1_\2\3\4.txt'/"

# Execute (pipe to sh only after verifying preview output)
ls *.txt | sed -E "s/(.+) ([0-9]{4})-([0-9]{2})-([0-9]{2})\.txt/mv '& ' '\1_\2\3\4.txt'/" | sh
ls /tmp/rename_lab/   # → Report_20240115.txt, Notes_20240120.txt, etc.

# Alternative with a for loop (more readable, safer for complex cases)
for f in /tmp/rename_lab/*.txt; do
  newname=$(echo "$f" | sed -E 's/ ([0-9]{4})-([0-9]{2})-([0-9]{2})\.txt/_\1\2\3.txt/')
  echo "mv '$f' '$newname'"   # preview
  # mv "$f" "$newname"        # uncomment to execute
done
```

---

### Lab 3 — Parse system_profiler JSON with jq

```bash
# Step 1: Extract a software manifest — all apps, version, path
system_profiler SPApplicationsDataType -json \
  | jq -r '.SPApplicationsDataType[]
    | [.path, (.version // "unknown"), .obtained_from]
    | @tsv' \
  | sort > /tmp/apps_manifest_$(date +%Y%m%d).tsv

wc -l /tmp/apps_manifest_*.tsv   # how many apps?

# Step 2: Find apps with no version (possible unsigned/old binaries)
system_profiler SPApplicationsDataType -json \
  | jq -r '.SPApplicationsDataType[]
    | select(.version == null or .version == "")
    | .path'

# Step 3: Apps obtained from "identified_developer" or "unknown"
system_profiler SPApplicationsDataType -json \
  | jq -r '.SPApplicationsDataType[]
    | select(.obtained_from == "unknown" or .obtained_from == "identified_developer")
    | "\(.obtained_from)\t\(.path)"' \
  | sort | column -t

# Step 4: Network interfaces as structured data
system_profiler SPNetworkDataType -json \
  | jq -r '.SPNetworkDataType[]
    | "\(.interface)\t\(._name)\t\(.ip_address // ["n/a"] | .[0])"'
```

> 🔬 **Forensics note:** Step 3 is a first-pass for triage on an unknown Mac. Apps with `obtained_from == "unknown"` were not signed by an identified developer — flag these for deeper inspection. Compare the manifest from Step 1 against a known-good baseline using `comm`.

---

### Lab 4 — Log analysis pipeline

```bash
# Combine grep, awk, sort, uniq, jq in a forensics pipeline

# Find all unique process names that logged faults in the last hour
log show --last 1h --style json 2>/dev/null \
  | jq -r '.[] | select(.messageType == "fault") | .process' \
  | sort | uniq -c | sort -rn | head -20

# Alternative: use log show text output with grep+awk
log show --last 1h --predicate 'messageType == 16' --info 2>/dev/null \
  | grep -E '^\d{4}-' \
  | awk '{print $5}' \
  | sort | uniq -c | sort -rn | head -20

# Find all sudo invocations from today
log show --last 24h --predicate 'process == "sudo"' 2>/dev/null \
  | grep -v '^Filtering' \
  | grep -E 'TTY|USER|COMMAND'
```

---

## Pitfalls & gotchas

**1. The `-i ''` vs `-i` trap (most common failure)**
BSD `sed -i ''` and GNU `sed -i` are incompatible. Use `-i.bak` for portability or know which sed you're calling. The error message from getting this wrong is misleading — BSD sed with no argument after `-i` interprets the next argument as the backup suffix, silently producing an empty output file or a renamed original.

**2. `\d` and `\w` don't work in ERE**
`grep -E '\d+'` silently matches nothing (or the literal `d`) on BSD grep. Use `[0-9]+` or `[[:digit:]]+` in POSIX regex. Only PCRE (`ggrep -P` or `rg`) supports `\d`, `\w`, `\s`.

**3. BSD grep has no `-P` flag**
`grep -P` on stock macOS prints an error. If your script uses `-P`, it requires `ggrep` or `rg`. This silently breaks on clean macOS systems where only Homebrew-prefixed tools are in `/opt/homebrew/`.

**4. awk field splitting on empty fields**
`awk -F,` with an empty field (`,,,`) gives empty `$2`, `$3`, `$4` — correct. But whitespace FS (default) collapses consecutive spaces and never produces empty fields. When parsing CSVs with awk, always use `-F,` explicitly.

**5. jq and null propagation**
`jq '.foo.bar'` returns `null` when `.foo` is null rather than erroring. Pipe through `| select(. != null)` or use `//` (alternative operator): `.foo.bar // "default"`. The raw output flag `-r` is essential when using jq output in shell — without it, strings are JSON-quoted and the quotes break subsequent commands.

**6. NUL bytes in files break all four tools**
grep, sed, awk, and jq are line-oriented text processors. Binary files containing NUL bytes (`\0`) truncate processing at the first NUL or produce garbled output. For binary artifact analysis, use `xxd`, `hexdump`, or `strings` first.

**7. Locale and encoding affect sort**
`sort` behavior differs between `LC_ALL=C` (byte-order) and `LC_ALL=en_US.UTF-8` (locale-aware). For reproducible sorts in scripts, prefix with `LC_ALL=C sort`.

**8. `column` output is for humans, not machines**
`column -t` pads output for display. Never pipe `column` output to further text processing — the padding breaks field extraction. Use `column` only as the last step before human eyes.

---

## Key takeaways

- macOS ships BSD grep, sed, awk — subtly different from GNU counterparts. Learn the differences; don't assume Linux scripts work unchanged.
- The `-i ''` (BSD) vs `-i` (GNU) sed flag is the single most common macOS-to-Linux portability failure. Use `-i.bak` for scripts that must run on both.
- BSD grep lacks `-P` (PCRE); use `ggrep -P` or `rg` when you need lookaheads, `\d`, `\w`, or named groups.
- `rg` (ripgrep) should be your default for interactive searching: faster, gitignore-aware, Unicode-safe, PCRE2 built-in.
- awk's `{array[$field]++} END {for (k in a) print a[k], k}` idiom is the fastest path from raw logs to frequency tables.
- `jq` is not optional on macOS — plist-to-JSON via `plutil`, `system_profiler -json`, and `log show --style json` all produce JSON that jq can dissect in a single pipeline.
- `comm`, `sort -u`, and `uniq -d/-u` are the right tools for manifest diffing and duplicate detection — not grep.
- Always use `LC_ALL=C sort` in scripts for reproducible ordering.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| BRE | Basic Regular Expressions (POSIX) — backslash before metacharacters `\(`, `\+` |
| ERE | Extended Regular Expressions (POSIX) — natural syntax; enabled by `-E` in grep/sed |
| PCRE | Perl-Compatible Regular Expressions — lookahead/lookbehind, `\d`/`\w`; not in BSD grep |
| RE2 | Google's regex engine (used by ripgrep) — linear-time guarantee, no catastrophic backtracking |
| BSD grep/sed/awk | The FreeBSD-derived versions shipped with macOS; POSIX-compliant but missing GNU extensions |
| GNU grep/sed/gawk | GNU Project implementations; dominant on Linux; installable via Homebrew on macOS |
| ripgrep (`rg`) | Rust-based grep replacement; PCRE2, gitignore-aware, SIMD-accelerated |
| `fd` | Rust-based `find` replacement; gitignore-aware, human-friendly syntax |
| jq | Command-line JSON processor; filter language with `.`, `.[]`, `select()`, `map()` |
| `nawk` | "New awk" / one-true-awk — the AWK implementation by Aho, Weinberger & Kernighan; macOS default |
| `gawk` | GNU awk — adds network I/O, debugger, profiler, namespaces; install via `brew install gawk` |
| FS / OFS | awk's input Field Separator and Output Field Separator |
| NR / NF | awk's Number of Records (lines seen) and Number of Fields in current line |
| in-place edit | `sed -i` modifies a file directly rather than writing to stdout |
| `plutil` | macOS tool to convert between plist formats (XML, binary, JSON) |

---

## Further reading

- `man grep`, `man sed`, `man awk` — always start here; BSD man pages document macOS behavior
- `man re_format` — comprehensive POSIX BRE/ERE reference on macOS
- [ripgrep GitHub](https://github.com/BurntSushi/ripgrep) — README contains the definitive benchmark methodology and feature comparison
- [The AWK Programming Language (2nd ed., 2023)](https://awk.dev/) — Aho, Weinberger, Kernighan; the language spec from its creators
- [jq Manual](https://jqlang.github.io/jq/manual/) — complete filter reference; bookmark the "select", "map", "@format" sections
- [GNU sed manual](https://www.gnu.org/software/sed/manual/sed.html) — documents all GNU extensions; compare against BSD behavior
- Howard Oakley's Eclectic Light Company — search for "grep" and "awk" for macOS-specific coverage
- [[05-defaults-and-plists]] — `defaults export` + `plutil -convert json` pipeline connects directly to jq
- [[10-unified-logging-and-diagnostics]] — `log show --style json` is the primary jq feed for system event analysis
- [[09-spotlight-metadata-and-xattrs]] — `mdls` and `xattr` output pipeable through grep/awk
- [[04-macos-specific-cli-tools]] — `system_profiler`, `plutil`, `dscl` — the macOS-native tools that produce the data you process here
