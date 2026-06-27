---
title: "OWASP MASTG & app-security testing"
part: "11 — Reverse Engineering & App Security"
lesson: 10
est_time: "45 min read + 20 min labs"
prerequisites: [static-analysis-class-dump-and-disassemblers, dynamic-analysis-with-frida]
tags: [ios, re, owasp, mastg, masvs, app-security]
last_reviewed: 2026-06-26
---

# OWASP MASTG & app-security testing

> **In one sentence:** Everything you have learned in this module — static dumping, Frida, traffic interception, resilience defeat — becomes a *defensible* engagement only when it hangs off a standard, and the OWASP Mobile Application Security project (MASVS, MASWE, MASTG) is that standard: a three-layer chain from "what the app must do" to "what can go wrong" to "exactly how you test it," with a known, downloadable, legal corpus to practice on.

## Why this matters

A pile of techniques is not an assessment. If you `class-dump` a binary, swizzle a method, and proxy the traffic, you have *findings* — but a client, a court, or a future you cannot tell whether you covered the attack surface or just poked the parts you happened to find interesting. The OWASP Mobile Application Security (MAS) project exists to turn the ad-hoc craft of mobile RE into a **repeatable, complete, comparable methodology**: a verification standard (MASVS) that says what "secure" means, a weakness enumeration (MASWE) that says what specifically goes wrong, and a testing guide (MASTG) that says — per platform, with copy-pasteable commands — how to check each weakness. For the **app-security tester** this is the difference between a credible report and a list of trophies. For the **forensic analyst** the MASTG technique catalog doubles as a map of *where an app stores what* — the same static/dynamic methods that prove a vuln also prove what data an app holds and leaks, which is exactly the question in a triage. And for the **developer** the standard is the spec you build to. This lesson is the framework that organizes the rest of Part 11.

> 🖥️ **macOS contrast:** There is no MAS analogue you met in the macOS course — desktop app-sec never got a single blessed standard, so you audited Mac apps ad hoc with `otool`/`codesign`/`dtrace` and judgment. The closest mental model is from the *web* side of OWASP: **MASVS is to mobile apps what ASVS is to web apps**, **MASTG is the WSTG**, and **MASWE plays the CWE-bridge role**. Mobile got the rigor desktop never standardized — use it.

## Concepts

### The three-layer model: MASVS → MASWE → MASTG

The whole project is one chain of increasing specificity. Internalize it; every artifact in the ecosystem is an ID in one of these layers.

```
  MASVS  ── control groups, platform-agnostic "what secure means"
   │        e.g. MASVS-STORAGE, MASVS-CRYPTO  (IDs: MASVS-STORAGE-1, -2 …)
   │        a handful of high-level controls per group (typically two)
   ▼
  MASWE  ── the WEAKNESS bridge: specific, mostly platform-agnostic
   │        things that go wrong, each mapped to a CWE
   │        e.g. MASWE-0027 "Improper Random Number Generation"
   ▼
  MASTG  ── the TESTING layer: concrete, PLATFORM-SPECIFIC procedures
            ├─ MASTG-TEST-####  a test that verifies a MASWE weakness (iOS or Android)
            ├─ MASTG-TECH-####  a reusable technique (e.g. "extract the IPA", "hook with Frida")
            ├─ MASTG-TOOL-####  a tool entry (frida, otool, mitmproxy, MobSF …)
            ├─ MASTG-APP-####   a reference/vulnerable app (iGoat-Swift = MASTG-APP-0028)
            ├─ MASTG-DEMO-####  a runnable demo proving a test fires
            └─ MASTG-BEST-####  a secure-coding best practice (the remediation side)
```

Read it top-down to *scope* ("which controls apply?"), bottom-up to *report* ("this finding is MASTG-TEST-X, which proves MASWE-Y, which violates MASVS-Z"). The MASWE layer is the hinge: weaknesses are platform-agnostic so they map cleanly to CWE and to both iOS and Android, while the MASTG tests below them are platform-specific — the iOS test for insecure storage is a different procedure from the Android one even though they verify the same MASWE.

If you know the web side of OWASP, the layers map cleanly — which is the fastest way to anchor them:

| MAS layer | Web/OWASP analogue | Role |
|---|---|---|
| MASVS | **ASVS** | The verification standard — "what secure means" |
| MASTG | **WSTG** | The testing guide — "how to verify it" |
| MASWE | **CWE** (bridge/subset) | The concrete weakness enumeration tying the two together |
| MAS Testing Profiles | ASVS levels (conceptually) | The scoped selection of controls for a class of app |

> **Version reality (current as of 2026-06-26; the corpus moves — re-verify before you cite a specific ID).** The MASVS was rewritten to **v2.0.0** in April 2023 — the rewrite that collapsed the old categories into the new control-group structure and dropped the numbered L1/L2/R *verification levels* in favor of *testing profiles*. **MASVS-PRIVACY** (the eighth control group) and CycloneDX support arrived in **v2.1.0 (2024-01-18)**, which is the **current MASVS release**. **MASWE** was introduced in **MASTG v1.8.0 (2024-06-24)**; **MASTG v1.9.0 (2025-06-24)** is the **current MASTG release** — it took the refactored "MASTG v2" structure out of beta, completed CWE mapping across all groups, dropped the legacy single-PDF format, and continued the v1→v2 test ports. Note the versioning quirk: the GitHub repo still tags releases **v1.x** while the *content* is branded "MASTG v2" — don't let that confuse you.

### The eight MASVS control groups

MASVS v2 organizes the entire mobile attack surface into eight control groups. Memorize them; they are the spine of every report.

| Group | Covers | The question it answers |
|---|---|---|
| **MASVS-STORAGE** | Data at rest on the device | Is sensitive data written somewhere it shouldn't be (plist, NSUserDefaults, unprotected file, logs, backups)? |
| **MASVS-CRYPTO** | Cryptographic functionality | Are keys, algorithms, and randomness sound — or is it hardcoded keys, ECB, MD5, predictable PRNG? |
| **MASVS-AUTH** | Authentication & authorization | Is auth enforced server-side, are local-auth (Face ID) gates real, are sessions/tokens handled correctly? |
| **MASVS-NETWORK** | Data in transit | TLS done right? Pinning present and not trivially bypassable? Cleartext anywhere? |
| **MASVS-PLATFORM** | Interaction with the OS & other apps | IPC, URL schemes, universal links, pasteboard, WebViews/JS bridges, screenshots, IInter-app data exposure |
| **MASVS-CODE** | Code quality & supply chain | Up-to-date dependencies, no injection-prone patterns, debug code removed, secure defaults |
| **MASVS-RESILIENCE** | Reverse-engineering & tamper resistance | Anti-debugging, jailbreak detection, integrity checks, obfuscation — defense in *depth*, not a boundary |
| **MASVS-PRIVACY** | User-data privacy | Data minimization, consent, transparency, no unnecessary identifiers/tracking (added in v2.1.0, Jan 2024) |

The first five map almost 1:1 onto subsystems you've already studied: STORAGE → the app container and Data Protection ([[00-app-sandbox-and-filesystem-layout]], [[02-data-protection-and-keybags]]), CRYPTO → [[08-keychain-on-ios]], AUTH → [[07-biometrics-security-architecture]], NETWORK → [[03-certificate-pinning-and-bypass]], PLATFORM → [[05-the-sandbox-and-tcc]]. RESILIENCE is the whole back half of this module ([[11-anti-tamper-pinning-and-detection-both-sides]]). PRIVACY is the newest and the one auditors most often skip.

### Each group, in concrete iOS terms

The standard is platform-agnostic; your job is to translate each group into the iOS APIs, files, and `Info.plist` keys you actually inspect. This is the lookup you build instinct around:

- **STORAGE** — Is sensitive data in `NSUserDefaults`/`Library/Preferences/*.plist`, an unprotected file in `Documents`/`Library/Caches`/`tmp`, an `Info.plist`, a Core Data/SQLite store, or leaking into the **unified log** (`os_log` of secrets) or **app-switcher snapshots** (`Library/SplashBoard/Snapshots/` on modern iOS — classically `Library/Caches/Snapshots/` — KTX images grabbed on backgrounding)? Does it land in the **iTunes/Finder backup** because it wasn't excluded or marked `NSURLIsExcludedFromBackupKey`? The right home for secrets is the **Keychain** with an appropriate `kSecAttrAccessible` class, not files.
- **CRYPTO** — Hardcoded keys/IVs in the binary; ECB mode; static IVs; home-grown crypto; broken hashes (MD5/SHA-1) for security; **predictable randomness** (`rand()`/`random()`/`srand(time(NULL))`/`drand48()` where a CSPRNG — `SecRandomCopyBytes` or `arc4random_buf`, both cryptographically secure on Apple platforms — is required); keys derived without a KDF; keys not bound to the Secure Enclave when they could be.
- **AUTH** — Authorization decided on the *client*; local `LAContext`/Face ID treated as an auth *boundary* rather than a UX gate (the real secret must be Keychain-gated by biometry via a `kSecAttrAccessControl` access-control object built with `SecAccessControlCreateWithFlags`, not a boolean the app checks); tokens with no expiry/rotation; secrets in JWTs.
- **NETWORK** — Cleartext HTTP, **ATS exceptions** (`NSAppTransportSecurity`/`NSAllowsArbitraryLoads` in `Info.plist`), weak TLS config, **absent or trivially-bypassable certificate pinning**, accepting invalid certs in a custom `URLSession` delegate.
- **PLATFORM** — Unvalidated **custom URL schemes** / Universal Links, exported functionality, **WKWebView** with `javaScriptEnabled` + a native bridge over untrusted content, secrets on the **pasteboard** (`UIPasteboard.general`), missing `isSecureTextEntry`, data left visible in the app switcher snapshot, third-party-keyboard exposure.
- **CODE** — Outdated/vulnerable third-party SDKs and Swift packages, debug logging/symbols and dev endpoints shipped in release, missing binary hardening (PIE, stack canaries, ARC), format-string/injection-prone patterns.
- **RESILIENCE** — Jailbreak detection, anti-debugging (`ptrace(PT_DENY_ATTACH)`, `sysctl` `P_TRACED`), code-integrity/anti-tamper checks, obfuscation, anti-hooking (Frida/Cydia Substrate detection). All *cost-raising*, none a boundary — see [[11-anti-tamper-pinning-and-detection-both-sides]].
- **PRIVACY** — Collecting more than declared in the **Privacy Manifest** (`PrivacyInfo.xcprivacy`) / **App Privacy "nutrition label,"** using **required-reason APIs** without a declared reason, harvesting device identifiers/`IDFA` without consent, fingerprinting, third-party SDK exfiltration.

> 🔬 **Forensics note:** The **RESILIENCE** catalog is dual-use for the examiner. The same anti-debug / anti-hooking / jailbreak-detection patterns the tester *defeats* are exactly what a **stalkerware or spyware** sample uses to *hide* — recognizing `PT_DENY_ATTACH`, `sysctl` trace checks, Frida/Substrate detection, and integrity self-checks in a suspect binary is an indicator of an app built to resist analysis. And the **PRIVACY** group's required-reason-API and Privacy-Manifest checks are a fast triage lens for "what does this app secretly collect," complementing a behavioral run through `mvt` and the artifact stores in Part 08.

### MAS Testing Profiles — what replaced the verification levels

MASVS v1 had numbered verification levels (L1, L2, R). v2 replaced them with **testing profiles** — a profile is a *selection* of control groups appropriate to a class of app, chosen during scoping. Do **not** write "MASVS-L1" in a 2026 report; the correct terms are:

| Profile | Name | When it applies | Roughly covers |
|---|---|---|---|
| **MAS-L1** | Essential Security | Baseline for *any* app | The common, easily exploited issues across STORAGE/CRYPTO/AUTH/NETWORK/PLATFORM/CODE |
| **MAS-L2** | Advanced Security | Apps handling sensitive data (finance, health, gov) | L1 plus stricter, deeper "defense-in-depth" controls across the same groups |
| **MAS-R** | Resilient Security | Apps that must resist RE/tampering (DRM, anti-fraud, games, IP) | The **MASVS-RESILIENCE** group specifically |
| **MAS-P** | Baseline Privacy | Apps subject to privacy expectations/regulation | The **MASVS-PRIVACY** group (the privacy profile, added with v2.1.0) |

The critical design point: **MAS-R is orthogonal, not "harder than L2."** Resilience is *additive* — an L2-secure app with zero anti-tampering can still be perfectly secure against its threat model; resilience only matters when the *client itself* is the thing being attacked (a cracker lifting a paid feature, a fraudster repackaging the app). The MASTG is explicit that resilience controls **raise the cost of an attack, they are not a security boundary** — they buy time against a determined attacker with the binary in hand, nothing more. Selling MAS-R as "unbreakable" is the single most common way to misrepresent a mobile assessment.

### MASWE: the weakness bridge

MASWE (Mobile Application Security **Weakness** Enumeration) is a flat list of concrete weaknesses, each with an ID like **MASWE-0027** ("Improper Random Number Generation"), each tied to (a) the MASVS control it violates, and (b) one or more **CWE** entries so it slots into the wider vulnerability-taxonomy world (NVD, scanners, SAST). It is deliberately platform-agnostic — the same MASWE applies to iOS and Android — which is why the *tests* below it are split per platform. When you write a finding, the MASWE ID is the durable, tool-portable identifier; the MASVS group is the business-facing "which pillar," and the CWE is the cross-industry lingua franca.

#### One weakness, end to end

To see the whole chain in motion, trace a single weakness — predictable randomness — from standard to evidence:

```
MASVS-CRYPTO            ← "Cryptography is sound"                      (the pillar)
   └─ MASWE-0027        ← "Improper Random Number Generation"         (the weakness)
        └─ CWE-338      ← "Cryptographically Weak PRNG" (also 332/337) (cross-industry)
             └─ MASTG-TEST (iOS)  ← the iOS procedure that verifies it (the test)
                  ├─ MASTG-TECH  static: find rand()/random()/srand()/drand48() in the binary
                  │              dynamic: hook the call, observe the seed/output
                  └─ MASTG-TOOL  class-dump · otool · Ghidra · frida
```

On iOS the *vulnerable* pattern is using `rand()`, `random()`, `drand48()`, or seeding `srand(time(NULL))` to produce a token/key/IV; the *secure* pattern (the MASTG-BEST) is `SecRandomCopyBytes(kSecRandomDefault, …)` — or `arc4random_buf()`/`arc4random()` (a CSPRNG on Apple platforms) or Swift's `SystemRandomNumberGenerator` (also cryptographically secure). The static test greps the disassembly for the weak symbols; the dynamic test hooks the call with Frida and watches whether the seed is low-entropy (e.g. time-derived) and the output predictable. The finding you write cites all four IDs — that's what makes it auditable. Every other weakness in the corpus follows this same MASVS → MASWE → CWE → MASTG-TEST → TECH/TOOL shape.

### The MASTG component catalog

The old MASTG was one giant book; the refactored MASTG is a database of small, individually-IDed, cross-linked Markdown pages. The families you will cite:

- **MASTG-TEST-####** — a single test verifying one MASWE on one platform. This is the unit of work in an engagement. Each test page states the weakness, the steps, expected vs. vulnerable output, and links to the techniques and tools it uses.
- **MASTG-TECH-####** — reusable techniques ("Obtaining the App Binary," "Bypassing Jailbreak Detection," "Intercepting Network Traffic"). The technique catalog is, for a forensic analyst, **a map of where things live and how to reach them** — independent of any single test.
- **MASTG-TOOL-####** — canonical tool entries (frida, objection, otool, `class-dump`, MobSF, mitmproxy, Burp, r2/Ghidra). Citing the tool ID pins exactly what you used.
- **MASTG-APP-####** — the reference apps, including the vulnerable ones you practice on. **iGoat-Swift is MASTG-APP-0028.**
- **MASTG-DEMO-####** — runnable demos (often with a Frida script and a sample) that *prove* a test triggers, so a reviewer can reproduce.
- **MASTG-BEST-####** — the remediation half: secure-coding best practices a developer applies to close a finding.

#### Navigating the catalog in practice

The refactor means you no longer read the MASTG cover to cover — you *query* it. The workflow when a concrete worry arises ("does this app log secrets?"):

1. Start at the **MASVS group** that owns the concern (logging secrets → STORAGE).
2. Drill to the **MASWE(s)** under it (insecure/sensitive-data logging).
3. Open the **iOS MASTG-TEST(s)** linked from that MASWE — the test page has the steps, the expected-vs-vulnerable output, and links to the **MASTG-TECH** it relies on and the **MASTG-TOOL** it uses.
4. Cross-check the **MASTG-DEMO** for a reproducible example, and grab the **MASTG-BEST** for the remediation you'll write up.

Working the other direction (you *found* something and need to file it) you walk the same links in reverse: tool/technique you used → the test → its MASWE → the MASVS group + CWE. Either way the IDs are the index — learn to navigate by ID, not by page title.

### The MAS Checklist — coverage as a deliverable

The project ships a **MAS Checklist** (a spreadsheet, regenerated each release; also browsable on the MAS site) that pre-joins the three layers: every MASVS control, the MASWEs under it, and the MASTG-TEST IDs that verify them, with columns for status and notes. In a real engagement this is your **coverage ledger** — you scope by deleting the rows for profiles/groups out of scope, then drive testing row by row, marking pass/fail/NA. The filled checklist *is* the audit trail: it proves what you tested, not just what you found, which is precisely the documentation discipline that survives scrutiny.

> 🔬 **Forensics note:** The MASTG-TECH catalog and the MASVS-STORAGE/PRIVACY tests are a ready-made **artifact-location index**. "Where does this app cache auth tokens / write PII / log secrets?" is the same question whether you're a tester finding a vuln or an examiner triaging a suspect app — and the MASTG already enumerates the candidate locations (the app container layers from [[00-app-sandbox-and-filesystem-layout]], the Keychain, `NSUserDefaults`/`Library/Preferences`, the `tmp`/`Caches` dirs, the unified log, the iTunes/Finder backup set). Run the storage tests against an evidentiary copy and you get a structured inventory of what the app holds. The crackmes below also give you **ground-truth samples** to validate your parsers and Frida scripts *before* you run them on real evidence.

### Building a device-free iOS test rig

You have no physical device, so map each MAS activity onto the three substrates from this course's doctrine and know exactly where each one lies to you:

| MAS activity | Substrate (no device) | Fidelity caveat |
|---|---|---|
| **Static analysis** (binary triage, `class-dump`, decompile, MobSF, secret/cred hunting) | Public sample IPA (OWASP crackmes) **or** a self-built `.app` | Full fidelity for *structure*. A device-built `.ipa` won't *run* on the Simulator (it's a signed iOS-device binary), so static is all you get from a crackme IPA. |
| **Dynamic analysis** (Frida hooking, runtime exploration, method tracing) | **iGoat-Swift / DVIA-v2 built to the Simulator** from source | Simulator app = arm64 **macOS** process: **no AMFI, no app sandbox, no SEP, no Data Protection at rest, no FairPlay**, and the device-only daemons (`knowledged`, `biomed`, `powerlogHelperd`, `routined`) never run. Teaches the *method* (Interceptor/ObjC bridge/swizzle), not at-rest crypto or anti-jailbreak realism. |
| **Network interception** (TLS inspection, pinning checks) | **mitmproxy / Burp + the Simulator** | The Simulator trusts the host Mac's installed CA, so cleartext-after-TLS inspection is faithful. **Pinning *bypass* on the Simulator** is unrealistic for App Store apps (no FairPlay-encrypted binary to start from, and you usually patch/Frida it) — bypass *technique* transfers, the *adversarial realism* doesn't. |
| **Resilience (MAS-R)** — jailbreak detection, anti-debug, integrity | **Read-only walkthrough** + the crackme **statically** | The whole point of resilience is *on a real device under attack*; the Simulator has nothing to detect. Study the defeat techniques statically and narrate the device workflow. |

**MobSF** (Mobile Security Framework, `MASTG-TOOL` for automated static analysis) is the one piece that gives you a MASVS-mapped report from an IPA with zero device — it's the natural first pass before manual work.

Translating that into how much of each control group you can honestly cover without a phone:

| Group | Device-free coverage | What still needs a real device |
|---|---|---|
| STORAGE | **High** — read the unencrypted Simulator container, decompiled paths, backup exclusions | Data-Protection **class** behavior at rest (keybag gating in BFU/AFU) |
| CRYPTO | **High** — static API misuse, hardcoded keys, weak algs; dynamic hooks in the Simulator | SEP-bound keys, biometric-gated Keychain at rest |
| AUTH | **Medium** — token handling, server-side checks via MITM, client-side logic flaws | Real `LAContext`/Face ID + `kSecAccessControl` enforcement |
| NETWORK | **High** — TLS/ATS config, cleartext, pinning *presence* via MITM | Pinning *bypass realism* on a hardened device app |
| PLATFORM | **High** — URL schemes, WebView/JS-bridge, pasteboard, snapshot, entitlements (static + Simulator) | A few IPC/system-integration behaviors that differ on-device |
| CODE | **High** — dependency/SDK audit, binary hardening, debug-leftover, `Info.plist` review | (little — mostly static) |
| RESILIENCE | **Low** — study defeats *statically*; the Simulator has nothing to detect | Everything dynamic — jailbreak/anti-debug/integrity only meaningful on-device |
| PRIVACY | **Medium-High** — Privacy Manifest, required-reason APIs, declared-vs-actual via MITM | At-rest behaviors and some SDK runtime exfiltration realism |

### Scope boundaries: what MAS does *not* cover

A standard is as useful for what it excludes as for what it includes. MASVS/MASTG is an **app-side** standard — know its edges so you don't over-claim:

- **It is not the server.** The backend, its APIs, and server-side authorization are out of MASVS scope — that's web/API testing (OWASP ASVS/WSTG, API Top 10). A "the app sends the token correctly" pass says nothing about whether the server validates it. Most real breaches live on the server side of a mobile finding.
- **It is not a business-logic review.** MASTG verifies *known weakness patterns*. Logic flaws, broken workflows, and abuse cases need a human reviewing intent, not a checklist.
- **It is not a threat model.** You bring the threat model *to* scoping; MAS doesn't generate one. The profile you pick (and therefore the controls in scope) is only as good as that model.
- **It is not a compliance certificate by itself.** "MASVS-verified" is a claim a tester makes; there's an optional independent verification/badging path, but the standard doesn't self-certify.
- **It is platform-app-centric.** App Clips, extensions, widgets, and the WatchKit/companion surfaces each carry their own attack surface ([[08-extensions-app-clips-widgets-and-widgetkit]]); make sure scoping enumerates them rather than testing "the app" as a monolith.

### The professional assessment process

The whole engagement is one loop, and every phase produces an artifact the next phase consumes:

```
  THREAT MODEL + data classification
        │
        ▼
  SCOPE ───► choose profiles (L1/L2/R/P) ──► trimmed MAS CHECKLIST
        │
        ▼
  TEST  ───► per checklist row: static → dynamic → network
        │     record evidence, mark pass/fail/NA
        ▼
  REPORT ──► findings (MASTG-TEST→MASWE→MASVS→CWE→sev→remediation)
        │     + filled checklist as the COVERAGE APPENDIX
        ▼
  RETEST ──► re-run failed rows after fixes ──► back to TEST if needed
```

The standard exists to be *run*, in three phases:

1. **Scope.** Choose the **profile(s)** (L1? +L2? +R? +P?), the platform (iOS), the in-scope features and backends, a **data-classification** of what the app handles, and a **threat model** (who's the attacker — network MITM? a thief with the phone? a cracker with the binary?). Profile selection is what makes RESILIENCE testing in- or out-of-scope. Output: a tailored **MAS Checklist** (rows trimmed to scope).
2. **Test.** Walk the checklist. For each in-scope MASTG-TEST: run the procedure (static/dynamic/network), record evidence (commands, screenshots, captured output), and mark pass/fail/NA. Combine static (cheap, broad — do it first) and dynamic (expensive, deep — confirm and exploit), exactly the pipeline from [[04-static-analysis-class-dump-and-disassemblers]] → [[05-dynamic-analysis-with-frida]].
3. **Report.** Each finding carries: the **MASTG-TEST** that found it → the **MASWE** it proves → the **MASVS** group it violates → a **CWE** → a severity → reproduction steps → a **MASTG-BEST** remediation → a retest result. The filled checklist goes in as the coverage appendix. That four-ID spine is what makes a mobile report comparable across testers, tools, and time.

A single finding, written to that shape, looks like:

```
Title:        Session token generated with a non-CSPRNG
Severity:     High  (data-class: auth token; threat model: network + lost-device)
MASVS:        MASVS-CRYPTO
MASWE:        MASWE-0027  (improper random number generation)
CWE:          CWE-338     (cryptographically weak PRNG; also 332/337)
MASTG-TEST:   <iOS test id>   Tools: class-dump, otool, frida (MASTG-TOOL)
Evidence:     rand() feeds the token, seeded srand(time(NULL)); no SecRandomCopyBytes/
              arc4random_buf; hooked seed is time-derived, output predictable (Frida log).
Remediation:  MASTG-BEST — SecRandomCopyBytes(kSecRandomDefault, …) or arc4random_buf().
Retest:       PASS — token now CSPRNG-derived (re-run 2026-06-26).
```

> ⚖️ **Authorization:** MASTG techniques are penetration-testing techniques — run them only against targets you own or are contracted to test. The lab corpus below (UnCrackable L1–L2, iGoat-Swift, DVIA-v2) is **explicitly licensed for exactly this practice**, which is why it's the right place to build muscle. Pointing a resilience-bypass or traffic-interception workflow at an App Store app you don't own can breach the App Store EULA, the developer's terms, the CFAA, and — where DRM is touched — DMCA §1201. Scope is the gate.

#### Severity, and "fail" is not binary

A MASTG test result is `pass / fail / NA`, but the *finding* needs a severity, and on mobile that is **context times data-classification times exploitability-under-the-threat-model**. The same MASWE is a different severity in different apps: a hardcoded API key for a public read-only endpoint is low; a hardcoded key that decrypts user PII at rest is critical. Use your house scale (CVSS-style, or client-defined) but anchor it to the **scoped threat model** — a network-MITM finding is moot if the threat model excludes a hostile network, and a STORAGE-at-rest finding's severity hinges entirely on the **Data-Protection class** and lock-state (BFU/AFU) from [[02-bfu-vs-afu-and-data-protection-classes]]. Report the reasoning, not just the rating.

### Where MAS fits the 2026 iOS landscape

MASVS/MASTG is no longer just a pentester's checklist; in 2026 it's load-bearing in three places you should know about:

- **Regulatory & compliance uptake.** MASVS is referenced or required by mobile-relevant standards (PCI's mobile payment standards, various national/sector app-security baselines). "MASVS-L2 verified" is increasingly a contractual line item, which is precisely why the *profile vocabulary* matters.
- **App Store & marketplace vetting.** Apple's App Review and notarization apply their own automated and manual checks; they are **not** a MASVS audit, but they overlap (ATS, privacy manifests, required-reason APIs, entitlement sanity). Under the **EU DMA**, alternative marketplaces and notarized sideloading ([[10-eu-dma-sideloading-and-alternative-marketplaces]]) shift some vetting burden onto marketplace operators — MASVS is the natural framework they reach for. Tie this to your distribution mental model in [[09-distribution-testflight-appstore-enterprise]].
- **The contributor model.** The v1→v2 refactor exists to *scale contribution* — atomic, individually-IDed test pages that vendors (Guardsquare, NowSecure) and the community port and extend. Practically: the corpus moves fast, so **cite the live edition and pin versions in a report** rather than quoting a number from memory.

### The legal lab corpus

The MAS project ships its own vulnerable apps so you never have to practice on something you don't own:

- **OWASP UnCrackable iOS — Level 1 / 2** (`Crackmes/iOS/Level_0N/` in the MASTG repo, also at `mas.owasp.org/crackmes/`). A graded pair of **MASVS-RESILIENCE** challenges — **iOS stops at Level 2** (only the Android ladder goes to Level 4):
  - **Level 1** — **jailbreak detection** plus a hidden secret string; the goal is to recover the secret. Bypass the detection (or sidestep it statically) and lift the flag — the friendly intro: the secret yields to `strings`/`class-dump` + basic Frida hooking.
  - **Level 2** — the full resilience gauntlet on one binary: **jailbreak detection** (file-existence checks for `Cydia.app`/`MobileSubstrate.dylib`/`/bin/bash`/`sshd`/`/etc/apt`) **plus anti-debugging** (`ptrace(PT_DENY_ATTACH)` and a `sysctl` `P_TRACED` check) **plus an anti-tamper integrity check** (an MD5 over the `__TEXT` code section to detect patching) guarding an **AES-encrypted flag**. You must defeat the detections before you can decrypt the secret — the canonical target for the both-sides material in [[11-anti-tamper-pinning-and-detection-both-sides]].
  > These ship as signed **iOS-device `.ipa`s** — they run on a (jailbroken) device, not the Simulator. Device-free, you study them **statically**; the dynamic defeats are read-only walkthroughs here.
- **OWASP iGoat-Swift** (**MASTG-APP-0028**, `github.com/OWASP/iGoat-Swift`) — "a Damn Vulnerable Swift Application," a learn-by-exploiting workbench with discrete lessons spanning STORAGE, CRYPTO, NETWORK, PLATFORM. **It builds from source in Xcode to the Simulator** (no signing, no device) — making it the best *dynamic* substrate you have.
- **DVIA-v2** (Damn Vulnerable iOS App v2) — a third widely-used, self-built target covering a similar surface; also Simulator-buildable from source.

## Hands-on

> All commands run on the **Mac** — there is no on-device shell. These assume the tooling from earlier lessons (`brew install frida ipsw radare2 mitmproxy`, `pip install frida-tools objection`, Xcode + `xcrun simctl`, Docker for MobSF).

### Pull the official crackmes and reference app

```bash
# The crackmes live inside the MASTG repo (also at mas.owasp.org/crackmes)
git clone --depth 1 https://github.com/OWASP/mastg.git
ls mastg/Crackmes/iOS/
# Level_01/  Level_02/   ← each has UnCrackable-LevelN.ipa  (iOS stops at 2; Android goes to 4)

# iGoat-Swift — build-from-source dynamic target (MASTG-APP-0028).
# The project is nested one level down and uses CocoaPods (Pods/ is not vendored):
git clone https://github.com/OWASP/iGoat-Swift.git
cd iGoat-Swift/iGoat-Swift           # .xcworkspace/.xcodeproj + Podfile live here
pod install                           # resolve the shipped Podfile
open iGoat-Swift.xcworkspace          # open the WORKSPACE (not .xcodeproj); ⌘R to a booted Simulator
```

### Static triage of an UnCrackable IPA (no device needed)

```bash
cd mastg/Crackmes/iOS/Level_01
unzip -q UnCrackable-Level1.ipa -d L1 && ls L1/Payload/*.app

APP="$(ls -d L1/Payload/*.app)"        # the .app name has spaces — let the glob find it
BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"

# Is it FairPlay-encrypted? (crackmes are NOT — cryptid 0)
otool -l "$BIN" | grep -A4 LC_ENCRYPTION_INFO    # cryptid 0  → plaintext, dump away

# MASVS-RESILIENCE / hardcoded-secret pass: cheapest possible first move
strings -a "$BIN" | grep -iE 'secret|flag|key|password'

# Recover the ObjC class graph → which method does the check?
class-dump "$BIN" | grep -iE 'verify|secret|check|password'
```

Described output: `cryptid 0` confirms you may analyze the binary directly (a real App Store binary would read `cryptid 1` and need [[03-fairplay-encryption-and-decrypting-app-store-apps]] first). On Level 1 the secret often falls straight out of `strings`/`class-dump`; on Level 2 it won't — the flag is AES-encrypted and guarded by anti-debug + anti-tamper, by design — pushing you to the dynamic walkthroughs.

### Automated MASVS-mapped static scan with MobSF

```bash
# MobSF analyzes an IPA fully statically — no device, no jailbreak
docker run -it --rm -p 8000:8000 \
  opensecurity/mobile-security-framework-mobsf:latest
# → open http://localhost:8000 , upload UnCrackable-Level1.ipa (or any in-scope IPA)
```

The report buckets findings by MASVS group (insecure storage flags, weak crypto, ATS/cleartext exceptions from the `Info.plist`, binary-protection/PIE/stack-canary status, hardcoded strings, granted entitlements). Treat it as the *first* pass that tells manual analysis where to dig — not as the assessment.

### Dynamic pass against iGoat-Swift in the Simulator

```bash
xcrun simctl list devices booted                 # confirm a booted sim
frida-ps -U | grep -i igoat                       # -U = "USB", routes to the sim too
objection -g iGoat-Swift explore                  # objection's MASTG-aligned toolbox
# inside objection:
#   ios keychain dump                 ← MASVS-STORAGE / -CRYPTO
#   ios nsuserdefaults get            ← MASVS-STORAGE
#   ios cookies get                   ← MASVS-NETWORK / -PLATFORM
#   ios plist cat <path>              ← MASVS-STORAGE
```

(The Simulator has no Data-Protection-at-rest, so a "secret" found in `NSUserDefaults` here is a true positive *for the storage location* but tells you nothing about the device keybag class — note that caveat in the finding.)

### Verify a single weakness (MASWE-0027, predictable PRNG)

```bash
# Static half: is a non-CSPRNG used where randomness must be unpredictable?
otool -Iv "$BIN" | grep -iE '\b(rand|random|srand|srandom|drand48)\b'  # weak symbols present?
nm -u "$BIN"      | grep -iE 'SecRandomCopyBytes|arc4random'           # both secure symbols absent?

# Dynamic half (Simulator): hook the weak PRNG + its seed and watch for low entropy
frida -U -n iGoat-Swift -q -e '
Interceptor.attach(Module.getGlobalExportByName("srand"), {
  onEnter(a){ console.log("srand(seed) =", a[0].toInt32() >>> 0); }    // time-derived seed?
});
Interceptor.attach(Module.getGlobalExportByName("rand"), {
  onLeave(r){ console.log("rand() ->", r.toInt32() >>> 0); }
});'
```

Described output: weak symbols present **and** neither `SecRandomCopyBytes` nor `arc4random_buf` present is the static tell; if the dynamic hook shows a low-entropy (e.g. time-derived) seed feeding a token/key/IV, you have the finding — write it as `MASTG-TEST → MASWE-0027 → MASVS-CRYPTO → CWE-338`.

### Network interception of the Simulator

```bash
mitmproxy --listen-port 8080           # or Burp; the sim trusts the host CA
# Sim → Settings → Wi-Fi → HTTP Proxy → Manual → 127.0.0.1:8080, then trust the mitm CA
# Now exercise iGoat's network lessons and read cleartext-after-TLS in mitmproxy.
```

### Inspect the unencrypted Simulator container directly

```bash
# CoreSimulator stores app containers UNENCRYPTED on the Mac — read the real schemas.
# Resolve iGoat's bundle id first (a source build ships it, typo and all, as OWASP.iGoat-Swifth):
xcrun simctl listapps booted | grep -i igoat        # find the exact CFBundleIdentifier
xcrun simctl get_app_container booted OWASP.iGoat-Swifth data
# → ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<GUID>
# cp before sqlite3 (a SELECT still write-locks + spawns -wal/-shm)
```

## 🧪 Labs

> These labs are **device-free**. Lab 1 uses a **public sample IPA** (static only — the crackme is a device binary that won't run on the Simulator); Lab 5 adds **MobSF** over a sample IPA. Labs 2, 3, and 6 use a **self-built Simulator app** (iGoat-Swift). Lab 4 is a **read-only methodology walkthrough**. The recurring fidelity caveat: a Simulator app is an **arm64 macOS process with no SEP, no Data Protection at rest, no AMFI/sandbox, no FairPlay**, and the device-only daemons (`knowledged`, `biomed`, `powerlogHelperd`, `routined`) never populate their stores — so resilience and at-rest-crypto results are *not* representative of a real device.

### Lab 1 — Static-only crack of UnCrackable Level 1, mapped to MAS *(substrate: public sample IPA)*

1. `unzip` `UnCrackable-Level1.ipa`, find the main executable via `CFBundleExecutable`, confirm `cryptid 0` with `otool -l`.
2. Recover the secret with the cheapest tool that works: `strings -a`, then `class-dump` to find the verifying method, then load the binary into Ghidra/Hopper if needed.
3. **Map your finding to the standard:** which MASVS group (RESILIENCE — and arguably STORAGE/CRYPTO for the hardcoded secret)? Which MASWE family (hardcoded sensitive data / weak resilience)? Which MASTG-TECH did you use (binary triage, ObjC metadata recovery)?
4. **Deliverable:** the recovered secret, the exact command that revealed it, and a one-line finding written in report form: `MASTG-TEST → MASWE-#### → MASVS-RESILIENCE → CWE`. Note in your log why you could *not* dynamically run this IPA without a device.

### Lab 2 — Storage finding in iGoat-Swift, end to end *(substrate: Simulator, self-built)*

1. Build iGoat-Swift to a booted Simulator from Xcode. Exercise an insecure-storage lesson (e.g. write a "password" via a vulnerable storage path in the app).
2. Locate it two ways: (a) `objection` → `ios nsuserdefaults get` / `ios plist cat`; (b) directly on disk via `xcrun simctl get_app_container booted OWASP.iGoat-Swifth data` (confirm the id with `simctl listapps booted | grep -i igoat`) then `find … -name '*.plist'` and `plutil -p`.
3. **Deliverable:** the on-disk path of the leaked value and its contents. Then write the **fidelity caveat** that belongs in the report: on a *device* this file would carry a Data-Protection class (NSFileProtection…) and the keybag would gate it at rest — the Simulator shows the location but not the protection, so this proves *placement*, not *exposure at rest*.

### Lab 3 — Network finding via interception *(substrate: Simulator + mitmproxy)*

1. Start `mitmproxy`, point the Simulator's HTTP proxy at it, trust the mitm CA in the Simulator.
2. Trigger an iGoat network lesson; capture a request/response that reveals sensitive data in cleartext (after TLS termination) or a missing-TLS call.
3. **Deliverable:** the captured flow (host, path, the sensitive field) and the MAS mapping (**MASVS-NETWORK**, the matching MASWE/CWE). State the caveat: you trivially intercepted because *you* installed the CA on a substrate with no pinning — on a pinned, device-resident app you'd be in [[03-certificate-pinning-and-bypass]] territory.

### Lab 4 — Scope and build a MAS Checklist for a hypothetical engagement *(substrate: read-only walkthrough)*

1. Invent a target: "a consumer banking app, iOS, handles credentials + financial data, has a paid tier with anti-fraud." Pick profiles: **MAS-L1 + MAS-L2** (sensitive data) **+ MAS-R** (anti-fraud client) — justify each in one sentence; decide if **MAS-P** is in scope.
2. Download the current **MAS Checklist** (from the MASTG release / `mas.owasp.org`). Trim it to your scope.
3. For each control group in scope, mark which MASTG-TEST rows you could execute **device-free** (most STORAGE/CRYPTO/NETWORK/PLATFORM/CODE static + Simulator/MITM tests) vs. which **require a real device** (Data-Protection-at-rest behavior, jailbreak-detection/anti-debug realism, SEP/biometric-gated keychain, FairPlay-encrypted-binary acquisition).
4. **Deliverable:** the trimmed checklist with a "device-free? / device-required?" column filled in — i.e. an honest **coverage and limitations statement**, the part of a real report that says what you *couldn't* test and why.

### Lab 5 — Automated triage with MobSF, then map it to MASVS *(substrate: public sample IPA + MobSF)*

1. Run MobSF in Docker (`docker run -it --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf:latest`) and upload an in-scope IPA (UnCrackable-Level1, or any app you own).
2. Read the report and **re-bucket every flag into a MASVS group** by hand: ATS exceptions → NETWORK, hardcoded strings/keys → CRYPTO/STORAGE, binary-protection (PIE/canary/ARC) → CODE/RESILIENCE, entitlements/URL schemes → PLATFORM, declared trackers → PRIVACY.
3. **Deliverable:** a table of MobSF findings → MASVS group → "confirmed manually? (Y/N/TODO)". The point of the lab is the discipline that **automated output is a lead, not a finding** — pick two flags and confirm or refute each with `otool`/`strings`/`class-dump` before you'd ever report them.

### Lab 6 — Verify MASWE-0027 (improper random number generation) dynamically *(substrate: Simulator, self-built)*

1. In iGoat-Swift (or your own test app), find a code path that generates a "random" token/key with a non-CSPRNG (`rand()`/`random()`/`srand(time(NULL))`).
2. Static-confirm with `otool -Iv "$BIN" | grep -iE 'rand|random|srand|drand48'` and check that neither `SecRandomCopyBytes` nor `arc4random_buf` is present.
3. Dynamic-confirm: attach Frida (`frida -U -n iGoat-Swift`) and hook the PRNG call + its seed (see Hands-on) to observe a low-entropy (time-derived) seed and predictable output feeding the secret.
4. **Deliverable:** the finding written with the full spine — `MASTG-TEST → MASWE-0027 → MASVS-CRYPTO → CWE-338` — plus the **MASTG-BEST** remediation (`SecRandomCopyBytes` or `arc4random_buf`). This is your template for every other weakness in the corpus.

## Pitfalls & gotchas

- **"MASVS-L1" is dead vocabulary.** v2 dropped numbered verification levels for **testing profiles** (MAS-L1/L2/R/P). Writing "MASVS-L1 compliant" in a 2026 report dates you and is technically wrong — profiles select *control groups*, they aren't levels of one ladder.
- **The repo says v1.x, the content says v2.** GitHub release tags are `v1.9.0`-style; the refactored structure is "MASTG v2." Don't waste an afternoon hunting for a "v2.0.0 release tag" that the content branding implies but the repo doesn't carry.
- **MASWE is platform-agnostic; MASTG-TEST is not.** Never apply an Android MASTG test verbatim to iOS. Match on the *MASWE* (the weakness), then pick the **iOS** MASTG-TEST under it.
- **Crackme `.ipa`s don't run on the Simulator.** They're signed iOS-device binaries. Device-free you get **static** analysis of Levels 1–2; the dynamic defeats (jailbreak-detection bypass, anti-debug, and the anti-tamper/AES-decrypt chain on L2) are device or walkthrough work. iGoat-Swift/DVIA-v2 are the *buildable* dynamic substrates because you compile *them* to the Simulator from source.
- **The Simulator silently passes resilience and at-rest-crypto tests.** No SEP, no Data Protection, no jailbreak to detect, no FairPlay — so MAS-R tests and "is this encrypted at rest?" come back green meaninglessly. Always stamp the fidelity caveat on Simulator-derived findings.
- **A passing MASTG test is necessary, not sufficient.** The standard is a *baseline*. "Passed all in-scope tests" ≠ "secure" — it means no *known-pattern* weakness was found within the chosen profile and the test corpus. Don't let a green checklist become a security guarantee in the executive summary.
- **MAS-R is not a boundary — don't oversell it.** Resilience raises attacker cost; it does not stop a determined attacker with the binary. The MASTG says so explicitly. Promising "tamper-proof" off a passing MAS-R is the classic misrepresentation.
- **MobSF is a starting pin, not the assessment.** Automated scanners flag patterns and miss logic/auth/context. Treat the MobSF report as a map for manual work, not as a substitute for it.
- **CoreSimulator SQLite still needs copy-before-query.** Even though the container is unencrypted, a `SELECT` write-locks the DB and spawns `-wal`/`-shm`. `cp` first — the forensic reflex applies to your lab data too.
- **MobSF's *static* analyzer is device-free; its *dynamic* analyzer is not.** MobSF iOS dynamic analysis needs a jailbroken device — don't promise dynamic coverage from a MobSF run on the Mac alone. Static (the IPA upload) is the device-free part.
- **MASWE IDs are stable; MASTG-TEST IDs are still churning.** The v1→v2 port keeps renaming, merging, and adding test pages. Anchor a finding to the **MASWE** (durable) and pin the **MASTG release** you used; a bare MASTG-TEST number can dangle a year later.
- **MAS-R ≠ obfuscation.** Obfuscation is *one* resilience control. A "we obfuscate" answer does not satisfy MAS-R, which also wants anti-debugging, integrity checks, root/jailbreak detection, and anti-hooking — and even all of it together is cost-raising, not a guarantee.
- **Don't skip MASVS-PRIVACY because it's new.** The Privacy Manifest / required-reason-API surface is a real, testable group in 2026 and increasingly a regulatory and App-Review concern — treating it as optional is a coverage gap, not a simplification.

## Key takeaways

- The OWASP MAS project is the **methodology** that turns the individual techniques of this module into a defensible, repeatable, comparable assessment — the mobile counterpart to OWASP's web ASVS/WSTG.
- Internalize the **three-layer chain**: **MASVS** (control groups, what secure means) → **MASWE** (specific CWE-mapped weaknesses) → **MASTG** (platform-specific TEST/TECH/TOOL/APP/DEMO/BEST). Findings are reported bottom-up along that spine.
- **Eight MASVS groups**: STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE, PRIVACY. The first five map onto iOS subsystems you already know; RESILIENCE is the rest of this module; PRIVACY is newest.
- **Testing profiles replaced verification levels**: MAS-L1 (essential), MAS-L2 (defense-in-depth), MAS-R (resilience — orthogonal, cost-raising not a boundary), MAS-P (privacy). Profile choice during scoping decides what's in scope.
- The **MAS Checklist** is the coverage ledger and the audit trail — it proves *what you tested*, not just what you found.
- **Practice legally** on the OWASP corpus: UnCrackable iOS L1/L2 (graded resilience, static-only without a device — iOS stops at Level 2) and iGoat-Swift (MASTG-APP-0028) / DVIA-v2 (Simulator-buildable dynamic targets).
- Device-free, you can do most STORAGE/CRYPTO/NETWORK/PLATFORM/CODE testing (static + Simulator + MITM + MobSF); **stamp the fidelity caveat** — the Simulator has no SEP/Data-Protection/AMFI/FairPlay and gives false-green on resilience and at-rest crypto.
- For the forensic analyst, the **MASTG technique catalog is an artifact-location map** and the crackmes are **ground-truth samples** to validate tooling before touching evidence.

## Terms introduced

| Term | Definition |
|---|---|
| OWASP MAS | The Mobile Application Security flagship project: the umbrella over MASVS, MASWE, and MASTG. |
| MASVS | Mobile Application Security **Verification Standard** — the platform-agnostic control standard, organized into eight control groups. |
| MASWE | Mobile Application Security **Weakness Enumeration** — CWE-mapped list of specific weaknesses; the bridge from MASVS controls to MASTG tests (e.g. MASWE-0027). |
| MASTG | Mobile Application Security **Testing Guide** — the concrete, platform-specific testing manual; a database of TEST/TECH/TOOL/APP/DEMO/BEST pages. |
| MASVS control groups | STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE, PRIVACY — the eight pillars of the mobile attack surface. |
| MAS Testing Profiles | MAS-L1 (Essential Security), MAS-L2 (Advanced Security), MAS-R (Resilient Security), MAS-P (Baseline Privacy); v2's replacement for the old numbered verification levels. |
| MASTG-TEST / -TECH / -TOOL / -APP / -DEMO / -BEST | The MASTG component ID families: a test, a reusable technique, a tool entry, a reference app, a runnable demo, a secure-coding best practice. |
| MAS Checklist | The spreadsheet joining MASVS→MASWE→MASTG-TEST IDs; used to scope an engagement and track/prove coverage. |
| iGoat-Swift | OWASP's "Damn Vulnerable Swift Application" (MASTG-APP-0028); learn-by-exploiting target, Simulator-buildable from source. |
| UnCrackable (iOS) Level 1/2 | OWASP's two graded MASVS-RESILIENCE crackmes — L1: jailbreak detection + a hidden secret; L2: + anti-debug (`ptrace`/`sysctl`), an MD5 `__TEXT` integrity check, and an AES-encrypted flag. Shipped as device IPAs (iOS stops at 2; Android goes to 4). |
| DVIA-v2 | Damn Vulnerable iOS App v2 — a third widely-used, self-built vulnerable practice target. |
| MobSF | Mobile Security Framework — automated static (and dynamic) analysis tool producing MASVS-mapped reports from an IPA (static analysis is device-free; dynamic needs a jailbroken device). |
| ATS | App Transport Security — iOS's default TLS policy; exceptions are declared via `NSAppTransportSecurity` in `Info.plist` and are a MASVS-NETWORK red flag. |
| Privacy Manifest | `PrivacyInfo.xcprivacy` — Apple's per-bundle declaration of collected data types and required-reason API usage; the testable surface for MASVS-PRIVACY. |
| `SecRandomCopyBytes` | iOS's CSPRNG (Security framework); the secure remediation for MASWE-0027 — alongside `arc4random_buf` (also a CSPRNG on Apple platforms) — versus weak PRNGs like `rand()`/`random()`/`srand()`. |
| MASTG-APP-0028 | The MASTG reference-app ID for iGoat-Swift. |

## Further reading

- **OWASP MAS** — `mas.owasp.org` (MASVS, MASWE, MASTG, the crackmes, MAS Checklist, Testing Profiles); `github.com/OWASP/mastg`, `github.com/OWASP/masvs`, `github.com/OWASP/maswe`.
- **MASTG releases** — `github.com/OWASP/mastg/releases` (v1.8.0 introduced MASWE; v1.9.0 took "MASTG v2" out of beta — read the changelogs for the current state).
- **Reference apps & crackmes** — `mas.owasp.org/crackmes/iOS/`, `mas.owasp.org/MASTG/apps/`, `github.com/OWASP/iGoat-Swift`, DVIA-v2 (`github.com/prateek147/DVIA-v2`).
- **Tooling** — MobSF (`github.com/MobSF/Mobile-Security-Framework-MobSF`); Frida + objection (`frida.re`, `github.com/sensepost/objection`); mitmproxy (`mitmproxy.org`); the MASTG-TOOL pages for the canonical command set.
- **Vendors aligned to MAS** — NowSecure ("OWASP Mobile Application Security Explained: How to Put MASVS, MASTG and MASWE Into Practice") and Guardsquare blogs (the latter drives much of the v1→v2 port work); useful for "how to operationalize MASVS/MASTG/MASWE."
- **MAS Checklist** — the spreadsheet/generator that joins the three layers per release; grab the current one from the MASTG release assets or `mas.owasp.org`.
- **Cross-reference (web side)** — OWASP ASVS and WSTG, to see the desktop/web standards the mobile project parallels (and where the API/server scope lives that MAS deliberately excludes).
- **Book** — David Thiel, *iOS Application Security* (No Starch) — the long-form companion to the storage/crypto/network/platform groups.
- `man otool`, `man codesign`, `man strings`, `man nm`; `frida --help`, `objection --help`, `mitmproxy --help`.

---
*Related lessons: [[04-static-analysis-class-dump-and-disassemblers]] | [[05-dynamic-analysis-with-frida]] | [[06-objection-swizzling-and-runtime-exploration]] | [[11-anti-tamper-pinning-and-detection-both-sides]] | [[03-certificate-pinning-and-bypass]] | [[03-fairplay-encryption-and-decrypting-app-store-apps]] | [[00-app-sandbox-and-filesystem-layout]]*
