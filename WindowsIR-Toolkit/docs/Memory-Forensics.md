# Memory Forensics Playbook (Volatility 3)

RAM holds what disk can't: running-but-fileless malware, injected/hollowed code,
decrypted strings, live network sockets, command history, cached credentials.
**Capture it first** (`scripts\Invoke-MemoryCapture.ps1` → WinPmem), analyze on
your workstation with **Volatility 3**.

```bash
pip install volatility3      # or use the wheel from Get-Tools.ps1
vol --help                   # 'vol' or 'python vol.py'
```

---

## Acquisition notes
- Acquire to **external media**; image ≈ size of physical RAM.
- **Architecture matters.** `Invoke-MemoryCapture.ps1` auto-selects the engine:
  - **Magnet DumpIt** (`DumpIt.exe /O <out.dmp> /Q`) — **preferred; the only free tool
    that covers x86, x64 AND ARM64**, each with a signed driver. Writes a Microsoft
    crash dump (WinDbg + Volatility 3 readable). Required on **ARM64** (Copilot+ PCs).
  - **WinPmem** (Go build: `go-winpmem_amd64_*_signed.exe acquire <out.raw>`) —
    fallback, **x86/x64 only** (no ARM64 driver). Do **not** use the legacy
    `winpmem_mini_x64_rc2.exe` — it writes a 0-byte image on modern Win10/11
    (Velocidex issue #55).
  - Other options: Magnet RAM Capture, Belkasoft Live RAM Capturer, FTK Imager (Capture Memory).
- Hash immediately; the wrapper writes a `.sha256` sidecar.
- Volatility 3 auto-detects the symbol profile — no more imageinfo guessing
  (though `windows.info` confirms the build).

---

## Triage plugin sequence (work top-down)

```bash
IMG=HOST_memory_<stamp>.raw

vol -f $IMG windows.info            # OS build, validate the image
vol -f $IMG windows.pstree          # process hierarchy — spot odd parents
vol -f $IMG windows.pslist          # active processes (EPROCESS walk)
vol -f $IMG windows.psscan          # carved processes — finds HIDDEN/terminated
                                    #   diff pslist vs psscan = unlinked (rootkit)
vol -f $IMG windows.cmdline         # full command lines (encoded PS, args)
vol -f $IMG windows.netscan         # network connections + owning PID (C2)
vol -f $IMG windows.netstat         # alt connection view
vol -f $IMG windows.malfind         # injected/unmapped exec memory (RWX, MZ in heap)
vol -f $IMG windows.dlllist         # loaded DLLs — suspicious paths/unsigned
vol -f $IMG windows.ldrmodules      # DLLs hidden from the 3 PEB lists (injection)
vol -f $IMG windows.handles         # handles — files/keys/mutexes a proc holds
vol -f $IMG windows.svcscan         # services from kernel memory
vol -f $IMG windows.modules         # kernel modules (drivers)
vol -f $IMG windows.modscan         # carved kernel modules (hidden drivers)
vol -f $IMG windows.callbacks       # kernel notification routines (rootkit hooks)
vol -f $IMG windows.ssdt            # SSDT hooks
```

## Credential / lateral-movement
```bash
vol -f $IMG windows.hashdump        # local NTLM hashes (SAM)
vol -f $IMG windows.lsadump         # LSA secrets
vol -f $IMG windows.cachedump       # domain cached creds
# (mimikatz-in-memory artifacts surface via malfind + lsass.exe handles/dlllist)
```

## Files & registry from RAM
```bash
vol -f $IMG windows.filescan        # file objects in memory (paths)
vol -f $IMG windows.dumpfiles --pid <PID>          # extract files a proc mapped
vol -f $IMG windows.registry.hivelist               # registry hives in RAM
vol -f $IMG windows.registry.printkey --key 'Software\Microsoft\Windows\CurrentVersion\Run'
```

## Extract a suspect process for offline analysis
```bash
vol -f $IMG windows.pslist --pid <PID> --dump        # dump the process image
vol -f $IMG windows.memmap  --pid <PID> --dump       # dump its full memory
# then: strings / yara / upload hash to TI
```

---

## What "bad" looks like in memory

| Signal | Plugin | Why it matters |
|---|---|---|
| Process in `psscan` but **not** `pslist` | psscan vs pslist | direct/unlinked process hiding (rootkit) |
| Parent mismatch (e.g. `lsass.exe` parent ≠ `wininit.exe`) | pstree | masquerading / injection host |
| RWX private memory containing `MZ`/shellcode | **malfind** | injected PE / shellcode (Cobalt Strike) |
| DLL in process but missing from PEB lists | ldrmodules | reflective/hidden DLL injection |
| Handle to **lsass.exe** from a non-system process | handles | credential dumping in progress |
| Connection to public IP from `svchost`/`lsass` | netscan | C2 over a trusted process |
| Unsigned / oddly-named kernel module | modscan/modules | malicious driver |
| Multiple `cmd.exe`/`powershell.exe` with encoded args | cmdline | fileless execution |

## Workflow
1. `pstree` + `psscan` → identify suspect PID(s).
2. `cmdline` + `netscan` + `dlllist`/`handles` on those PIDs → understand them.
3. `malfind` → confirm injection; dump the region.
4. `windows.pslist --pid <PID> --dump` → carve the binary; hash + YARA + TI.
5. Cross-reference RAM findings with the disk timeline (Triage-Runbook §5).

> **YARA over memory:** `vol -f $IMG windows.vadyarascan --yara-file rules.yar`
> (or `yarascan`) runs your `iocs\yara` rules against process memory directly.
