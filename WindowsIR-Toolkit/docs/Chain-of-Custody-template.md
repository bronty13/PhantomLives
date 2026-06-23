# Chain of Custody / Evidence Log

Fill one of these per investigation. Keep it with the evidence. For anything that
may become legal or HR proceedings, follow your organization's formal evidence
policy — this is a working template, not legal advice.

---

## Case

| Field | Value |
|---|---|
| Case / ticket ID | |
| Investigator(s) | |
| Date/time opened (TZ) | |
| Authorized by (name/role) | |
| Authorization scope | (which hosts/accounts; what you may collect) |
| Reason / triggering alert | |

## System under examination

| Field | Value |
|---|---|
| Hostname | |
| Make / model / serial | |
| OS / build | |
| IP / MAC | |
| Physical location / owner | |
| State when found | (powered on/off; logged-in user; screen contents) |
| Network status | (online / isolated at HH:MM) |

## Evidence items

| # | Description | Source path | Acquired (UTC) | Tool + version | SHA-256 | Stored at |
|---|---|---|---|---|---|---|
| 1 | RAM image | physical memory | | WinPmem x.x | | E:\Evidence\...\.raw |
| 2 | Triage collection | live host | | Collect-Triage.ps1 | (see SHA256_MANIFEST.csv) | E:\Evidence\HOST_… |
| 3 | | | | | | |

> The toolkit auto-generates hashes: `Collect-Triage.ps1` → `SHA256_MANIFEST.csv`
> (+ collector self-hash); memory/Velociraptor wrappers write `.sha256` sidecars.
> Reference those rather than re-typing every hash.

## Custody transfers

| Date/time | Released by | Received by | Purpose | Notes |
|---|---|---|---|---|
| | | | | |

## Analyst action log (every state-changing action, timestamped)

| Time (UTC) | Analyst | Action | Host state changed? | Justification |
|---|---|---|---|---|
| | | Captured RAM | no (read) | volatility-order |
| | | Ran Collect-Triage.ps1 | no (read/copy) | triage |
| | | Isolated NIC | **yes** | contain active C2 |
| | | Killed PID #### | **yes** | confirmed malicious |

## Findings summary

- **Verdict:** (compromised / not / inconclusive)
- **Initial access:**
- **Execution / malware:** (names, hashes, paths)
- **Persistence mechanisms found:** (list ALL)
- **Accounts affected:**
- **Lateral movement / blast radius:**
- **Exfil / impact:**
- **Earliest evidence (dwell start):**
- **IOCs extracted →** `iocs\` (hashes, IPs, domains, filenames, mutexes)

## Integrity statement

> I attest that the evidence listed was collected and handled as recorded above,
> that hashes were computed at collection time, and that the evidence has not been
> altered since.

Signature: ____________________  Date: ____________
