# IOCs — YARA rules & threat-intel for macOS

`run-yara.sh` scans with every `*.yar` / `*.yara` file under `iocs/yara/`. The shipped
`ir_starter.yar` is a tiny set of **triage heuristics** (expect false positives) — replace
or augment it with curated, macOS-relevant feeds before a real hunt.

## Where to get good macOS rules

- **Neo23x0 / signature-base** — Florian Roth's broad YARA set (incl. macOS/Unix):
  <https://github.com/Neo23x0/signature-base>
- **YARAify (abuse.ch)** — community rules + lookups: <https://yaraify.abuse.ch/>
- **Objective-See** — macOS malware corpus & write-ups to derive rules from:
  <https://objective-see.org/malware.html>
- **ReversingLabs / Elastic protections** — Elastic publishes macOS YARA:
  <https://github.com/elastic/protections-artifacts>

## Using them

```bash
git clone https://github.com/Neo23x0/signature-base
cp signature-base/yara/*.yar iocs/yara/
./scripts/run-yara.sh -p /Users -p /Applications
```

Keep rule files that `import "macho"` / `import "hash"` — `run-yara.sh` invokes a
yara build that supports those modules (Homebrew's does).

## Other IOC types

For hash/domain/IP IOCs, pair the collected artifacts (unified log, quarantine events,
shell history) with your TI platform. The toolkit deliberately doesn't bundle a TI feed —
point it at your own.
