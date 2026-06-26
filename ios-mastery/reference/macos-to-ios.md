---
title: macOS → iOS translation
type: reference
last_reviewed: 2026-06-26
---

# "The X of iOS" — a translation table for a macOS power user

You finished `macos-mastery`. This spine maps what you learned there to its iOS equivalent.
Populated as lessons land. Seed rows:

| macOS | iOS/iPadOS | Note |
|---|---|---|
| FileVault (volume encryption) | Data Protection (per-file class keys) | iOS is finer-grained; AFU/BFU matters |
| Terminal / a shell | *(none on-device)* | Privileged work happens on a tethered Mac |
| `launchd` + LaunchAgents | `launchd` (system LaunchDaemons only) | No user agents, no cron |
| TCC.db privacy DB | entitlements + privacy prompts | Different enforcement model |
| `~/Library` | per-app Bundle/Data containers | Sandbox-everywhere by default |
| `mac_apt` | iLEAPP / APOLLO | The artifact-parsing toolchain |
| Gatekeeper / notarization | AMFI / mandatory code signing | "All exec pages signed," in-kernel |
