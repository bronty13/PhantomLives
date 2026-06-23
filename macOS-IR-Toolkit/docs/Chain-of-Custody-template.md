# Chain of Custody — macOS Triage

Fill this in contemporaneously. One row per action that touches the endpoint or evidence.

## Case header

| Field | Value |
|---|---|
| Case ID | |
| Date / time zone | |
| Investigator | |
| Authorization (who/when/scope) | |
| Subject host (name / serial) | |
| macOS version / chip | |
| SIP / FileVault state | |
| Evidence media (model / serial) | |

## Acquisition log

| # | UTC time | Action | Command / tool | Operator | Output path | SHA-256 (if file) | Notes |
|---|---|---|---|---|---|---|---|
| 1 | | Photographed screen | — | | — | — | |
| 2 | | sysdiagnose | `capture-memory.sh` | | | | |
| 3 | | Live collection | `collect-triage.sh` | | | (see manifest) | |
| 4 | | YARA hunt | `run-yara.sh` | | | | |
| 5 | | | | | | | |

## Integrity verification

| Artifact | Manifest SHA-256 | Re-verified SHA-256 | Match? | Verified by / when |
|---|---|---|---|---|
| CASE_SHA256_MANIFEST.csv | | | | |
| sysdiagnose tarball | | | | |

## Handling / transfer

| UTC time | From | To | Reason | Media | Signature |
|---|---|---|---|---|---|
| | | | | | |

> Store evidence on write-protected media. Re-compute and compare hashes after every
> transfer. Note any TCC/permission gaps that made an artifact incomplete.
