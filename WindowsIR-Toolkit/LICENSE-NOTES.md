# License & redistribution notes

This toolkit ships **only original scripts/docs** (MIT-licensed, below) plus a
**downloader** that fetches third-party tools from their official sources. It
**does not bundle any third-party binaries**, deliberately:

1. **Several best-in-class IR tools are free but forbid redistribution.** Their
   EULAs let you download and use them, not re-host them:
   - **Microsoft Sysinternals** (Autoruns, Procmon, etc.) — Sysinternals EULA.
   - **KAPE** (Kroll) — free with registration; redistribution restricted.
   - **FTK Imager** (Exterro) — free with registration; redistribution restricted.
2. **Eric Zimmerman tools** are free and effectively open, but the maintainer
   distributes them via his own updater (`Get-ZimmermanTools`), which we invoke
   rather than mirror, so you always get current, authentic builds.
3. Downloading at run time means you get **current versions with vendor
   signatures**, not stale copies of unknown provenance baked into a zip.

The open-source tools the downloader pulls (Velociraptor, WinPmem, Volatility 3,
Hayabusa, Chainsaw, Loki, YARA, RegRipper, CyberChef, DB Browser, Autopsy) carry
their **own licenses** (Apache-2.0 / GPL-3.0 / BSD / MPL — see
`tools.manifest.json`). Review each before use, especially GPL terms if you
redistribute a derived kit.

`Get-Tools.ps1` records a **provenance manifest** (`tools/_manifest_downloaded.json`)
with the URL + SHA-256 of everything it fetched. For evidentiary work, **verify
vendor-published hashes/signatures** independently.

---

## This toolkit's own license (scripts + docs)

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## Use responsibly

These tools are for **authorized** incident response, defensive security, and
education only. Only examine systems you own or are explicitly authorized to
investigate. Preserve evidence integrity; follow your jurisdiction's and
organization's legal/privacy requirements.
