# License & redistribution notes

## This toolkit's own code
The scripts and docs in this directory (`*.sh`, `docs/*`, `iocs/yara/ir_starter.yar`,
`tools.manifest.json`) are MIT-licensed, like the rest of PhantomLives unless noted.

## The optional external tools (NOT bundled)
`get-tools.sh` downloads these from their official sources at setup time; this repo does
not re-host any binary. Verify each vendor's signature/hash before evidentiary use.

| Tool | License | Source |
|---|---|---|
| **Aftermath** (Jamf) | MIT | <https://github.com/jamf/aftermath> |
| **YARA** | BSD-3-Clause | <https://github.com/VirusTotal/yara> / `brew install yara` |
| **osquery** | Apache-2.0 / GPLv2 | <https://www.osquery.io> |
| **Volatility 3** | Volatility Software License (BSD-like) | <https://github.com/volatilityfoundation/volatility3> |

## Built-in macOS tools
`sysdiagnose`, `log`, `lldb`, `sfltool`, `profiles`, `dscl`, `lsof`, `kmutil`,
`systemextensionsctl`, `plutil`, `sqlite3`, `perl`, etc. ship with macOS and are used
under Apple's OS license as part of normal system administration.

## Evidence handling
This toolkit reads and copies; it does not modify the endpoint beyond the unavoidable
footprint of running (which the chain-of-custody log should record). Always collect to
separate media and preserve hashes.
