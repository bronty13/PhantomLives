# macOS IR Methodology

A lightweight framework for the toolkit. Not a substitute for a full IR plan (PICERL /
NIST 800-61) — it's the *acquisition & triage* slice.

## Order of volatility (RFC 3227, macOS flavor)

1. **CPU/RAM state** → not directly imageable on Apple Silicon; capture `sysdiagnose`
   (process list, open files, sockets) as the closest proxy.
2. **Running state** → processes, network connections, loaded kexts/sysexts, launchd.
3. **Persistence** → launchd, login items, profiles, cron — survives reboot, so less
   volatile, but capture before remediation changes it.
4. **On-disk artifacts** → unified log, quarantine, histories, FSEvents — least volatile.

Capture top-down. The dependency-free collector already orders sections this way.

## Decision flow

```
Authorized? ──no──► STOP.
   │yes
Volatile state needed? ──► sysdiagnose + collect (BEFORE containment)
   │
Suspected process? ──► --pid N  (lldb core)   +  yara over its on-disk image
   │
Need depth/parsing? ──► Aftermath (--include-aftermath) ; osquery for live questions
   │
Triage findings ──► persistence + quarantine + unified log  ──►  contain ──► document
```

## macOS-specific mindset shifts (vs Windows)

- **No registry, no Event Log.** Persistence = launchd/profiles/login-items; logs = the
  unified log (`log`), `/var/log`, and per-app SQLite stores.
- **SIP + TCC gate your own access.** Root is necessary but not sufficient — Full Disk
  Access is the other half. Assume "permission denied / empty" means a TCC gap, not absence.
- **Signing tells you a lot fast.** `codesign -dv --verbose=4 <app>`, `spctl -a -vv <app>`,
  and notarization status quickly separate Apple/known-vendor from suspect binaries.
- **Memory is not your friend here.** Lean on disk artifacts; see `Memory-Forensics.md`.

## Evidence integrity

- Collect to **separate, ideally write-once** media. Never write to the suspect volume.
- Every output folder ships a **SHA-256 manifest**; re-verify after transport.
- The collector hashes itself (`collector_self_hash.txt`) so you can prove which version ran.
- Keep a contemporaneous action log (`Chain-of-Custody-template.md`).
