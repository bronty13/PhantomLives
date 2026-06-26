---
title: Mac-side toolkit cheat-sheet
type: reference
last_reviewed: 2026-06-26
---

# Mac-side iOS toolkit — fast reference

There is no on-device shell; iOS work is driven from the Mac. Every tool/command introduced
across the course lands here, grouped. Populated as lessons land. Seed groups:

- **Device services (libimobiledevice):** `ideviceinfo`, `idevicebackup2`, `ideviceinstaller`,
  `idevicesyslog`, `idevicecrashreport`, `afcclient`, `pymobiledevice3`.
- **Apple tooling:** `xcrun simctl …`, `cfgutil` (Apple Configurator), `sysdiagnose`,
  `codesign`, `security cms`, `plutil`.
- **Firmware/RE:** `blacktop/ipsw`, `img4tool`, `ldid`, `jtool2`, `otool`, `nm`, `class-dump`,
  `dsdump`.
- **Dynamic analysis:** `frida`, `frida-trace`, `objection`, `mitmproxy`/`mitmweb`.
- **Forensics:** `iLEAPP`, `APOLLO`, `mvt-ios`, `ccl-segb`, `sqlite3`, `hashcat`.
