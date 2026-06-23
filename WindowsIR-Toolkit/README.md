# Windows IR Toolkit

A self-contained kit for **triaging a Windows endpoint for malware and forensic
artifacts** using open-source and free tools. Built for live-response *and*
dead-disk analysis. Ships scripts + documentation; a bootstrap downloader pulls
the third-party tools from their official sources (see **Why no bundled binaries**).

> ⚠️ \*\*Authorized use only.\*\* Triage systems you own or are explicitly authorized
> to investigate. Preserve evidence integrity. See `LICENSE-NOTES.md`.

\---

## What's in the box

```
WindowsIR-Toolkit/
├── README.md                  ← you are here
├── Run-Triage.ps1             ← ★★ ONE-SHOT orchestrator: memory → collect → hunt → summary
├── Get-Tools.ps1              ← bootstrap: download tools from official sources (+ provenance hashes)
├── tools.manifest.json        ← the tool list (names, URLs, licenses)
├── Collect-Triage.ps1         ← ★ dependency-free live collector (volatile + persistence + artifacts + report)
├── LICENSE-NOTES.md           ← licensing / redistribution rationale (MIT for our code)
├── scripts/
│   ├── Invoke-MemoryCapture.ps1      ← RAM acquisition, arch-aware (DumpIt x86/x64/ARM64; WinPmem x86/x64)
│   ├── Invoke-VelociraptorTriage.ps1 ← broad open-source collection
│   ├── Invoke-KapeTriage.ps1         ← KAPE !SANS\_Triage + !EZParser
│   ├── Run-Hayabusa.ps1              ← Sigma detections over EVTX
│   ├── Scan-Yara.ps1                 ← YARA over files / process memory
│   └── Parse-Artifacts.ps1           ← offline parse w/ Eric Zimmerman tools → CSV
├── docs/
│   ├── IR-Methodology.md             ← framework, order of volatility, decision tree
│   ├── Triage-Runbook.md             ← ★ step-by-step command sequence
│   ├── Artifact-Reference.md         ← every artifact: location / what it proves / how to parse
│   ├── Persistence-Locations.md      ← ASEP map (MITRE ATT\&CK)
│   ├── EventLog-Reference.md         ← IR-relevant event IDs
│   ├── Memory-Forensics.md           ← Volatility 3 playbook
│   ├── Tool-Cheatsheet.md            ← every tool's key commands
│   └── Chain-of-Custody-template.md  ← evidence log to fill in
├── iocs/
│   ├── README.md                     ← where to get curated YARA/Sigma/TI feeds
│   └── yara/ir\_starter.yar           ← starter heuristics (replace with YARA-Forge)
├── tools/                            ← (populated by Get-Tools.ps1)
└── output/                           ← default collection destination if no removable drive
```

\---

## Quick start

### 1\. On a CLEAN internet-connected workstation — fetch tools

```powershell
.\\Get-Tools.ps1
.\\tools\\EricZimmermanTools\\Get-ZimmermanTools.ps1 -Dest .\\tools\\EricZimmermanTools
```

(KAPE \& FTK Imager are registration-gated; `Get-Tools.ps1 -IncludeManualRegistration`
opens their pages. See `docs/Tool-Cheatsheet.md`.)

Copy the whole `WindowsIR-Toolkit\\` to **removable / read-only media** for the field.

### 2\. On the suspect endpoint (elevated PowerShell)

**Easiest — one command does memory → collect → hunt → summary:**

```powershell
.\\Run-Triage.ps1 -Output E:\\Evidence
```

If scripts are blocked: `powershell -ExecutionPolicy Bypass -File .\\Run-Triage.ps1 -Output E:\\Evidence`
Useful switches: `-Quick` (fast volatile-only, no memory/hunt), `-SkipMemory`,
`-IncludeVelociraptor`, `-Force` (no auth prompt). Everything lands under
`E:\\Evidence\\<HOST>\_TRIAGE\_<stamp>\\` with a `TRIAGE\_SUMMARY.txt` + master manifest.

**Or run the stages by hand:**

```powershell
.\\scripts\\Invoke-MemoryCapture.ps1 -Output E:\\Evidence   # RAM first (most volatile)
.\\Collect-Triage.ps1 -Output E:\\Evidence                 # volatile + persistence + artifacts + report
```

### 3\. Hunt \& analyze (back on the workstation)

```powershell
.\\scripts\\Run-Hayabusa.ps1 -LogDir E:\\Evidence\\HOST\_…\\03\_artifacts\\EventLogs
.\\scripts\\Parse-Artifacts.ps1 -ArtifactDir E:\\Evidence\\HOST\_…\\03\_artifacts
.\\scripts\\Scan-Yara.ps1 -Path C:\\Users
# RAM:  vol -f E:\\Evidence\\HOST\_memory\_\*.raw windows.pstree  (see docs/Memory-Forensics.md)
```

Read **`docs/Triage-Runbook.md`** next — it's the full operational sequence.

\---

## The native collector (`Collect-Triage.ps1`) at a glance

Zero external dependencies — runs on a locked-down host immediately. Read-only to
the endpoint; writes a timestamped, **SHA-256-manifested** evidence folder:

* **01\_volatile** — processes (hash + signature + cmdline + parent), network
connections/listeners, DNS cache, ARP, routes, SMB sessions, logged-on users.
* **02\_persistence** — Run keys, startup folders, scheduled tasks, services,
drivers, **WMI event subscriptions**, IFEO/AppInit/LSA/Winlogon, local admins.
* **03\_artifacts** — raw copies (locked-file capable) of `.evtx`, Prefetch,
Amcache, SRUM, registry hives, per-user NTUSER/UsrClass + PowerShell history.
* **REPORT.html** + **SHA256\_MANIFEST.csv** + chain-of-custody metadata.

\---

## Why no bundled binaries?

The best Windows IR tools split into "open-source" and "free-but-can't-redistribute"
(Sysinternals, KAPE, FTK Imager). Re-hosting the latter violates their EULAs, and
baking *any* binary into a zip ships stale, unverifiable copies. So this kit
downloads each tool from its **official source** at setup time and records a
**provenance manifest with SHA-256 hashes**. Full rationale + per-tool licenses:
`LICENSE-NOTES.md` and `tools.manifest.json`.

\---

## Requirements

* **Endpoint:** Windows 10/11 or Server 2016+; PowerShell 5.1+ (built in). Run
elevated for complete collection.
* **Workstation (analysis):** Python 3.8+ for Volatility 3; .NET for EZ tools.
* Removable media sized for a RAM image (≈ physical RAM) + artifacts.

## Order of operations (don't skip)

1. Authorize \& document. 2. Photograph screen. 3. **RAM.** 4. Volatile state.
2. Artifacts. 6. *Then* contain. — Every state-changing action gets logged
(`docs/Chain-of-Custody-template.md`).



---

## Enabling PowerShell script execution

By default Windows blocks running `.ps1` files (`Restricted`, or `RemoteSigned`
which still blocks scripts copied from removable media because they carry the
"Mark of the Web"). Pick one of these — listed least- to most-persistent:

**1. Per-invocation (no state change — best for a suspect host):**

```powershell
powershell -ExecutionPolicy Bypass -File .\Run-Triage.ps1 -Output E:\Evidence
```

**2. Per-session (affects only the current window; no admin, nothing persisted):**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Run-Triage.ps1 -Output E:\Evidence
```

**3. Persistent for your user (analysis workstation only — do NOT persist policy
changes on evidence machines):**

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# If scripts came off a USB/zip and are blocked by Mark-of-the-Web, clear it:
Get-ChildItem -Recurse -Path . | Unblock-File
```

> **IR note:** prefer option 1 or 2 on a host under investigation. `-Scope Process`
> and `-ExecutionPolicy Bypass -File` change no persistent machine state, so they
> keep your footprint minimal and forensically defensible. Save the persistent
> `Set-ExecutionPolicy` (option 3) for your own analysis workstation.

