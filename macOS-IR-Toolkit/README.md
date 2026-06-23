# macOS IR Toolkit

A self-contained kit for **triaging a macOS endpoint for malware and forensic
artifacts** using built-in OS tools plus a few optional open-source ones. The sibling
of this repo's `WindowsIR-Toolkit/`, rebuilt around macOS realities (SIP, Apple
Silicon, launchd, the unified log, TCC).

> ⚠️ **Authorized use only.** Triage systems you own or are explicitly authorized to
> investigate. Preserve evidence integrity. See `LICENSE-NOTES.md`.

---

## What's in the box

```
macOS-IR-Toolkit/
├── README.md                 ← you are here
├── run-triage.sh             ← ★★ ONE-SHOT orchestrator: memory → collect → hunt → summary
├── collect-triage.sh         ← ★ dependency-free live collector (pure bash + built-in tools)
├── get-tools.sh              ← fetch optional tools (YARA, Aftermath, osquery) + provenance
├── tools.manifest.json       ← the optional-tool list (names, URLs, licenses)
├── scripts/
│   ├── capture-memory.sh     ← sysdiagnose + optional lldb per-PID process cores
│   ├── run-yara.sh           ← YARA scan over files
│   └── run-aftermath.sh      ← wrapper for Jamf Aftermath (heavy collector)
├── docs/
│   ├── IR-Methodology.md         ← framework, order of volatility, decision flow
│   ├── Triage-Runbook.md         ← ★ step-by-step sequence
│   ├── Artifact-Reference.md     ← every artifact: location / what it proves / how to parse
│   ├── Persistence-Locations.md  ← launchd / login items / profiles / cron map
│   ├── Memory-Forensics.md       ← the honest state of macOS memory acquisition
│   ├── Tool-Cheatsheet.md        ← key commands for each tool
│   └── Chain-of-Custody-template.md
├── iocs/
│   ├── README.md             ← where to get curated YARA / TI
│   └── yara/ir_starter.yar   ← starter heuristics (replace with real feeds)
└── tools/                    ← (populated by get-tools.sh; git-ignored)
```

---

## The two macOS gotchas you MUST know first

1. **Run as root AND with Full Disk Access.** On macOS even `root` cannot read
   TCC-protected data (Safari/Mail/Messages, the TCC databases, parts of `~/Library`,
   the unified log) unless the *running process* has **Full Disk Access**. Grant FDA to
   your terminal: **System Settings → Privacy & Security → Full Disk Access → add
   Terminal/iTerm**. Then `sudo ./run-triage.sh`. The orchestrator probes for FDA and
   warns if it looks absent.

2. **There is no real RAM dump on Apple Silicon.** SIP blocks memory-reading kernel
   drivers and Apple Silicon removed the old tricks — no free WinPmem/DumpIt equivalent
   exists. The "memory" stage captures `sysdiagnose` (broad volatile state) + optional
   `lldb` process cores instead. See `docs/Memory-Forensics.md`. This is by design.

---

## Quick start

### 1. (optional) On a clean analysis Mac — fetch the extra tools

```bash
./get-tools.sh                 # YARA + Aftermath + osquery (needs Homebrew for YARA/osquery)
```

The dependency-free collector needs none of these. Copy the toolkit to
removable/read-only media for the field.

### 2. On the suspect Mac (root + Full Disk Access)

```bash
sudo ./run-triage.sh -o /Volumes/Evidence
```

One command does memory → collect → hunt → summary into
`/Volumes/Evidence/<HOST>_TRIAGE_<stamp>/` with a `TRIAGE_SUMMARY.txt` + manifest.

Useful switches: `--quick` (fast, no memory/hunt), `--skip-memory`, `--skip-hunt`,
`--include-aftermath`, `--pid <N>` (lldb-core a suspicious PID), `--max-log-days N`,
`--force` (no auth prompt).

**Or run stages by hand:**

```bash
sudo ./scripts/capture-memory.sh -o /Volumes/Evidence            # sysdiagnose first
sudo ./collect-triage.sh -o /Volumes/Evidence                    # volatile + persistence + artifacts
./scripts/run-yara.sh -p /Users -p /Applications                 # hunt
```

Read **`docs/Triage-Runbook.md`** next.

---

## The native collector (`collect-triage.sh`) at a glance

Zero external dependencies — pure bash + built-in macOS utilities, so it runs on a
locked-down Mac immediately. Read-only to the endpoint; writes a timestamped,
**SHA-256-manifested** evidence folder:

* **01_volatile** — processes (+ a cycle-safe tree), network (`lsof`/`netstat`/`arp`/DNS),
  loaded kexts + system extensions, running launchd services, logged-on users, mounts.
* **02_persistence** — LaunchAgents/Daemons (parsed), login items (BTM), cron/periodic/at,
  login hooks, configuration profiles, TCC grants, sudoers, ssh, third-party kexts.
* **03_artifacts** — unified log archive, TCC.db, quarantine events, browser & shell
  history, install history, `/var/log`, FSEvents, knowledgeC.
* **REPORT.html** + **SHA256_MANIFEST.csv** + chain-of-custody metadata.

Every step has a hard timeout (some macOS tools, e.g. `sfltool dumpbtm`, can hang) — a
slow command is killed and logged `TO`, never stalls the run.

---

## Requirements

* **Endpoint:** macOS 12+ (tested on macOS 26 / Apple Silicon); bash + perl (built in).
  Run as **root** with **Full Disk Access** for a complete collection.
* **Optional tools:** Homebrew for YARA/osquery; `aftermath` from Jamf's releases.
* Removable media for the evidence folder (a sysdiagnose alone can be 200MB–1GB+).

## Order of operations (don't skip)

1. Authorize & document. 2. Photograph screen. 3. **sysdiagnose** (volatile). 4. Collect.
5. Hunt. 6. *Then* contain. Every state-changing action gets logged
(`docs/Chain-of-Custody-template.md`).
