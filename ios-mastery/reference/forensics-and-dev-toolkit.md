---
title: Forensics & dev toolkit
type: reference
last_reviewed: 2026-06-26
---

# The curated iOS forensics + dev stack — what to install and why

Opinionated, with rationale, split **open-source** (the hands-on lab spine) vs **commercial**
(concept/workflow a working examiner must know). Populated as lessons land. Seed split:

## Open-source
- **libimobiledevice / pymobiledevice3** — device services, logical acquisition.
- **iLEAPP / APOLLO / ccl-segb / mvt** — artifact parsing, pattern of life, Biome/SEGB, spyware.
- **blacktop/ipsw, img4tool, ldid, jtool2** — firmware / Mach-O / dyld cache / IMG4.
- **Frida / objection** — dynamic instrumentation.
- **mitmproxy** — TLS interception.
- **checkra1n / palera1n** — checkm8 jailbreak (A8–A11), studied conceptually.

## Commercial
- **Cellebrite** UFED / Inseyets / Premium; **Magnet** GrayKey / AXIOM; **Elcomsoft** iOS
  Forensic Toolkit / Phone Breaker; **MSAB** XRY; **Belkasoft**; **Oxygen**.
