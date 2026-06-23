# IOCs & detection rules

Drop your indicators and rules here; the scanning scripts read from this folder.

```
iocs/
├── yara/        ← .yar / .yara rules  (Scan-Yara.ps1 + Volatility vadyarascan read these)
├── sigma/       ← .yml Sigma rules    (Chainsaw; Hayabusa ships its own too)
├── hashes.txt   ← known-bad SHA-256 (one per line) — grep collected manifests against these
├── ips.txt      ← known-bad IPs/CIDRs — grep netstat_connections.csv
└── domains.txt  ← known-bad domains   — grep dns_cache.csv
```

A tiny starter rule ships in `yara/ir_starter.yar`. Replace/extend with curated
sets — **don't rely on the starter alone.**

## Where to get curated, free rule sets

| Source | What | URL |
|---|---|---|
| **YARA-Forge** | merged, deduped community YARA (best single download) | https://github.com/YARAHQ/yara-forge/releases |
| Florian Roth `signature-base` | the rules behind Loki/THOR | https://github.com/Neo23x0/signature-base |
| Elastic protections | YARA + behavior | https://github.com/elastic/protections-artifacts |
| ReversingLabs | curated YARA | https://github.com/reversinglabs/reversinglabs-yara-rules |
| **SigmaHQ** | the canonical Sigma rule repo | https://github.com/SigmaHQ/sigma |
| Hayabusa rules | Sigma curated for EVTX (auto-updates) | bundled; `hayabusa update-rules` |

## Threat-intel feeds for hashes/IPs/domains (free)

- abuse.ch — **MalwareBazaar** (hashes), **URLhaus** (URLs), **Feodo/ThreatFox** (C2 IPs/IOCs)
- CISA known-exploited & advisories
- AlienVault OTX (free pulses), your own prior cases

## Quick matching against a collection

```powershell
# Hashes: flag any collected file matching known-bad
$bad = Get-Content iocs\hashes.txt
Import-Csv 'E:\Evidence\HOST_…\SHA256_MANIFEST.csv' | ? { $bad -contains $_.SHA256 }

# IPs: flag connections to known-bad
$badip = Get-Content iocs\ips.txt
Import-Csv 'E:\Evidence\HOST_…\01_volatile\netstat_connections.csv' |
  ? { $badip -contains $_.RemoteAddress }

# Domains: against the DNS cache
$baddom = Get-Content iocs\domains.txt
Import-Csv 'E:\Evidence\HOST_…\01_volatile\dns_cache.csv' |
  ? { $d=$_.Name; $baddom | ? { $d -like "*$_*" } }
```
