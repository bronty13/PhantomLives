# Incident Response Methodology (Windows endpoint triage)

A short, practical framework for triaging a single Windows host. Based on
**NIST SP 800-61r2** (IR lifecycle) and **RFC 3227** (order of volatility).
This toolkit covers the **Identification / Containment / Collection** phases.

> ⚠️ **Authorization first.** Only triage systems you are authorized to examine.
> Record who authorized it, when, and the scope. For anything that may become
> legal/HR evidence, follow your org's evidence-handling policy and keep this
> toolkit's auto-generated SHA-256 manifests.

---

## The lifecycle (NIST 800-61)

1. **Preparation** — toolkit staged on read-only media, analysis workstation
   ready, baselines/known-good hashes available.
2. **Detection & Analysis** — confirm the alert is real; scope it.
3. **Containment, Eradication & Recovery** — isolate, remove, restore.
4. **Post-Incident** — lessons learned, detections improved.

You are usually called in at step 2. Triage's job: **answer "is this host
compromised, how, and how bad" fast enough to drive a containment decision.**

---

## Order of volatility (RFC 3227) — collect most-volatile first

| # | Evidence | Lost when… | Toolkit step |
|---|----------|-----------|--------------|
| 1 | CPU registers, cache | instantly | (not collected) |
| 2 | **RAM** (running malware, injected code, keys, network state) | power off | `scripts\Invoke-MemoryCapture.ps1` **← do this first** |
| 3 | **Network state** (connections, ARP, DNS cache) | seconds–minutes | `Collect-Triage.ps1` §01 |
| 4 | **Running processes / handles** | process exit | `Collect-Triage.ps1` §01 |
| 5 | **Disk artifacts** (registry, MFT, event logs, prefetch) | reimage/overwrite | `Collect-Triage.ps1` §03 / KAPE / Velociraptor |
| 6 | Backups, archives, physical config | long-lived | out of scope |

**Practical sequence for a live host you must keep running:**
1. Photograph the screen / note what's visible.
2. **Memory capture** (RAM) to external media.
3. **Live triage** (`Collect-Triage.ps1`) — volatile state + artifacts.
4. Only then consider containment actions that change state (isolate NIC, kill a
   process) — and **log every action with a timestamp**.

> If you can pull the host off the network without tipping off an attacker, do
> it **after** RAM + volatile capture (network isolation kills C2 but also kills
> live network evidence; capture it first).

---

## Don't contaminate the evidence

- **Run tools from read-only / removable media**, write output to *different*
  removable media — never install tools onto the suspect disk.
- Every byte you write to the suspect disk destroys slack/unallocated evidence
  and updates MFT/registry timestamps. The native collector here is read-only
  to the endpoint and copies *out*.
- Prefer **acquire-then-analyze**: pull artifacts off the host and do the heavy
  parsing (EZ tools, Hayabusa, Volatility) on your analysis workstation.
- Record the **collector's own hash** (the script does this) and **per-file
  SHA-256** (the manifest) so you can prove nothing changed after collection.

---

## Triage decision tree (fast path)

```
Alert on host
  │
  ├─ Capture RAM + volatile state (this toolkit)
  │
  ├─ Quick wins — look for the obvious:
  │     • process with no/odd parent, unsigned, in %TEMP%/%APPDATA%
  │     • outbound connection to unknown IP / known-bad
  │     • Run key / scheduled task / service pointing at a weird path
  │     • encoded PowerShell (`-enc`, `FromBase64String`, `IEX`)
  │     • new local admin / recently created account
  │
  ├─ Found something?  →  pivot: when (timeline), how (initial access),
  │                       what else (lateral movement, persistence count)
  │
  └─ Nothing obvious?  →  deeper parse: Hayabusa over EVTX, Amcache/Shimcache
                          for execution, Prefetch, browser history, Volatility
                          malfind/netscan on the RAM image.
```

See **Triage-Runbook.md** for the concrete command sequence, and
**Artifact-Reference.md** for what each artifact proves.

---

## Scoping questions to keep answering

- **Patient zero & dwell time** — when did it start? (timeline the artifacts)
- **Initial access** — phish attachment, exposed RDP, exploited service, USB?
- **Execution** — what ran? (Prefetch, Amcache, Shimcache, EVTX 4688/Sysmon 1)
- **Persistence** — how does it survive reboot? (count *every* mechanism)
- **Privilege/credential** — new accounts, LSASS access, token theft?
- **Lateral movement** — outbound SMB/RDP/WinRM, type-3 logons (EVTX 4624)?
- **Exfil/impact** — large transfers (SRUM), staged archives, ransomware notes?
- **Blast radius** — is this host unique, or one of many? (hunt the IOCs fleet-wide)

---

## When to stop and escalate

- Evidence of **hands-on-keyboard** attacker, **domain-admin** compromise, or
  **ransomware staging** → escalate to full IR / legal / management now.
- Don't tip off an active attacker with clumsy containment; coordinate.
- If it might go to **court/HR**, stop improvising — forensically image the disk
  (FTK Imager / `dd`) and preserve chain of custody before further analysis.
```
