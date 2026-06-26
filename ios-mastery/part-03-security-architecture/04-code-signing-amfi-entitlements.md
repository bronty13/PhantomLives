---
title: "Code signing, AMFI & entitlements"
part: "03 — Security Architecture"
lesson: 04
est_time: "50 min read + 20 min labs"
prerequisites: [the-ios-security-model, dyld-shared-cache-and-amfi]
tags: [ios, code-signing, amfi, entitlements, coretrust, trust-cache]
last_reviewed: 2026-06-26
---

# Code signing, AMFI & entitlements

> **In one sentence:** on iOS, code signing is not a download-time courtesy check like macOS's Gatekeeper — it is a *kernel page-fault invariant* enforced by **AMFI**, where every executable page must hash to a signature whose certificate chain **CoreTrust** verifies back to Apple, and where what a program is *allowed to do* is decided not by a uid it can become but by the **entitlements** baked into that signature and authorized by a provisioning profile.

## Why this matters

You already met the headline in [[macos-to-ios-mental-model-reset]] (Reset 2: "signed-code-only") and saw AMFI named in [[dyld-shared-cache-and-amfi]]. This lesson is the mechanism in full, because three of the most consequential things you will ever reason about on iOS all reduce to it:

- **As a forensic examiner**, code signing is the **tamper-detection substrate**. "Is this device jailbroken?" and "did an implant run here?" largely become "is there a code-signing state that should be impossible on a stock device?" — a non-Apple loadable trust cache, AMFI enforcement flags cleared, an executable page that validates against no Apple-issued signature.
- **As a developer**, the entire confusing ritual of certificates, provisioning profiles, App IDs, and the seven-day free-provisioning clock is just the front-end of this one enforcement system. Once you see *why* the kernel refuses your build, the error messages stop being mysterious.
- **As a reverse-engineer (Part 11)**, the code signature is the first thing you parse on any Mach-O — it tells you the binary's identity (`cdhash`), what it was allowed to do (entitlements), and whether it is FairPlay-encrypted.

Get this layer right and the sandbox ([[the-sandbox-and-tcc]]), the jailbreak landscape ([[the-jailbreak-landscape-2026]]), and app distribution ([[distribution-testflight-appstore-enterprise]]) all click into place, because they all sit on top of it.

## Concepts

### What "mandatory code signing" actually means

On a stock iOS device, **the kernel will never grant execute permission to a memory page whose contents are not covered by a valid Apple-rooted code signature.** This is enforced at the moment a page is faulted in for execution (when the VM subsystem would set `VM_PROT_EXECUTE`), not at install time and not at first launch — page by page, lazily, for the life of the process. There is no `chmod +x`, no "run anyway" dialog, no quarantine xattr to strip. A process that somehow gets unsigned bytes into an executable mapping is killed with a code-signing fault (`CS_KILL`).

That single invariant is the foundation the rest of iOS security assumes. Data Protection, the sandbox, and the entitlement model are only meaningful if the kernel enforcing them is itself the kernel Apple signed (the boot chain, [[boot-chain-securerom-iboot]]) and if the userspace code making security decisions can't be swapped for an attacker's unsigned code. Mandatory code signing is what makes "trusted code" a coherent idea above the boot chain.

> 🖥️ **macOS contrast:** macOS has the *same machinery* — AMFI, the same `LC_CODE_SIGNATURE`/Code Directory format, the hardened runtime, `amfid`, even `CoreTrust` on Apple Silicon — but it is wired as **policy, not physics**. Gatekeeper/`spctl` only gate *quarantined, GUI-launched* apps; you can compile a binary, ad-hoc-sign it (or not sign it at all), and run it straight from Terminal. Notarization gates *distribution*, not *execution*. On iOS the kernel gates **execution itself**, and there is no shell, no `--no-sandbox`, and no supported way to lower the policy. The Mac's signing is a doorman; iOS's is a law of physics.

### The code signature: a SuperBlob bolted onto the Mach-O

A signed Mach-O carries an `LC_CODE_SIGNATURE` load command pointing into the `__LINKEDIT` segment at an **embedded signature SuperBlob** — a small container of typed sub-blobs:

```
 Mach-O (arm64e)
 ├─ LC_CODE_SIGNATURE ─────────────▶ offset/size in __LINKEDIT
 └─ __LINKEDIT: Code Signing SuperBlob (magic 0xFADE0CC0)
      ├─ CodeDirectory        (0xFADE0C02)  the heart — see below
      ├─ CodeDirectory (alt)  (0xFADE0C02)  often a 2nd, SHA-256 vs SHA-1 legacy
      ├─ Requirements         (0xFADE0C01)  "who must have signed this"
      ├─ Entitlements (XML)   (0xFADE7171)  the requested privileges (plist)
      ├─ Entitlements (DER)   (0xFADE7172)  same, DER-encoded (modern, canonical)
      └─ CMS signature        (0xFADE0B01)  PKCS#7/CMS over the CodeDirectory hash
```

The **Code Directory** is the object everything else refers to. It contains:

- A **code-hash array**: one cryptographic hash (SHA-256 on modern iOS) **per memory page** (typically 4 KB) of the signed `__TEXT`/executable regions. This is what the kernel checks at fault-in time.
- A set of **special slots** (negative-indexed) hashing the things *outside* the code pages that must also be pinned: the `Info.plist`, the internal Requirements, the **Entitlements** blob, the DER entitlements, and the `_CodeResources` bundle-resource manifest.
- Identifiers: the **bundle identifier**, a **team identifier** (the signer's Apple Developer Team ID), the hash type, page size, and flags (`adhoc`, `hard`, `kill`, `restrict`, `runtime`, …).

The hash of the Code Directory itself is the **`cdhash`** — a ~20-byte fingerprint that *is* the canonical identity of this exact binary. When anything in iOS says "this code is trusted," it means "this `cdhash` is trusted." Trust caches are lists of `cdhash`es; an entitlement grant is tied to a `cdhash`; a forensic "is this the stock binary?" check compares `cdhash`es.

> 🔬 **Forensics note:** Because the Code Directory pins the `Info.plist`, the entitlements, *and* every code page, you cannot alter a signed binary's identity, claimed permissions, or behavior without breaking the signature — and on iOS a broken signature means it won't execute. So a binary recovered from an image that *does* run on a stock device necessarily has an intact, Apple-rooted signature; its `cdhash`, team ID, and entitlements are reliable provenance. Conversely, a binary present on disk whose `cdhash` matches no Apple-shipped trust cache and no known developer signature is either dead weight or evidence of tampering. Inspect with `codesign -dvvv`, `ldid -h`, or `ipsw macho info --sig`.

### AMFI and amfid: the two halves of enforcement

**AMFI — AppleMobileFileIntegrity — is split across the kernel and userspace**, and understanding the split is the whole point:

- **`AppleMobileFileIntegrity.kext`** lives *in the kernel*. It hooks the MAC (Mandatory Access Control) policy points the VM and exec paths call. When a page is about to become executable, the kernel asks: does this page's hash match the signed Code Directory, and is that signature trusted?
- For **platform binaries** — Apple's own code, whose `cdhash`es are in the **trust cache** (next section) — the kernel answers *yes* immediately, with no userspace round-trip. This is the fast path for everything in the dyld shared cache and every system daemon.
- For **third-party code**, the kernel cannot judge the signer on its own, so AMFI calls **up to `amfid`** (the AppleMobileFileIntegrity userspace daemon) over a host special port. `amfid` validates the CMS signature, checks the certificate chain, evaluates the embedded **provisioning profile**, and reconciles the requested **entitlements** against what the profile authorizes — then hands a verdict (and the entitlement set) back down to the kernel.
- A page whose signature does not verify is **never made executable**. With the `CS_KILL` flag (set for all third-party apps), the process is terminated outright.

```
   exec / mmap(PROT_EXEC) ─▶ VM fault ─▶ AMFI.kext: page hash vs CodeDirectory?
                                              │
                 ┌────────────────────────────┴───────────────────────────┐
        cdhash in trust cache?                          third-party signature
        (platform binary)                                       │
                 │ yes → trust, no userspace call        up-call to amfid (userspace)
                 ▼                                                │
            page executes                          CMS sig valid? cert chains to Apple?
                                                   provisioning profile authorizes it?
                                                   entitlements ⊆ profile's?
                                                          │ yes ▼        │ no ▼
                                                    grant + entitlements   CS_KILL
```

> 🔬 **Forensics note:** This architecture is *why* certain device states are tamper indicators. A `palera1n`/usbliter8-class jailbreak (BootROM-exploit devices — checkm8 A8–A11, usbliter8 A12–A13; see [[boot-chain-securerom-iboot]]) defeats this by **patching `AMFI.kext`'s decision in kernel memory** (so the checks always pass) or by **injecting a loadable trust cache** of the attacker's own `cdhash`es so their unsigned tools run as "platform binaries." Both leave detectable traces: a non-Apple loadable trust cache resident in kernel memory, cleared AMFI enforcement flags, or a running process whose `cdhash` appears in no Apple-shipped trust cache and no developer signature. On a modern A14+ device with no public BootROM exploit, *any* of these is a strong tamper signal, not a normal condition.

### CoreTrust: moving the cert check below amfid

There is a subtlety that matters historically and forensically. `amfid` runs in **userspace**, which means that on a jailbroken device (kernel compromised) an attacker could simply patch `amfid` to approve anything — and early jailbreaks did exactly that. Apple's answer (around iOS 12) was **CoreTrust**, a small **in-kernel** module that independently validates that a binary's CMS signature **chains to a real Apple-issued certificate**. Even if `amfid` is subverted, CoreTrust in the kernel still demands an Apple-rooted leaf — so you cannot get arbitrary code signed by a non-Apple CA to run, no matter what userspace says.

CoreTrust is also the component at the center of **TrollStore**: a **signature-validation flaw in CoreTrust** (the way it handled certain multiply-signed binaries) let an **ad-hoc-signed binary carry arbitrary entitlements** and still pass kernel validation — a *permanent*, install-once sideload with full entitlements, no jailbreak required. Apple patched that CoreTrust bug class, and **TrollStore's supported window is frozen at iOS ≤ 17.0** (closed in 17.0.1). The lesson for you: CoreTrust is the kernel's "the signer is really Apple/a real developer" gate, and its history is a reminder that the *cert-chain* check and the *entitlement* check are distinct steps that have been attacked independently. (Full RE treatment in [[trollstore-and-the-coretrust-bug]].)

### The trust cache: how platform binaries skip the round-trip

A **trust cache** is simply an in-kernel list of approved `cdhash`es. There are three flavors:

| Trust cache | Where it lives | Holds |
|---|---|---|
| **Static** | baked into the `kernelcache` | the `cdhash`es of every binary in the boot image / dyld shared cache — the OS's own code |
| **Loadable** (`ltrs`) | loaded at runtime by a privileged, signed loader | `cdhash`es for the personalized Developer Disk Image, some on-demand system content |
| **Engineering / dev** | dev-fused devices only | broader sets for internal Apple use |

When AMFI sees a `cdhash` in a trust cache, the binary is a **platform binary**: trusted immediately, granted **platform entitlements**, and exempt from the `amfid` round-trip. This is the mechanism a jailbreak abuses (inject a loadable trust cache of your own `cdhash`es) and the mechanism a forensic tamper check keys on (a loadable trust cache present on a device should correspond only to Apple-signed content like the DDI; an arbitrary one is anomalous). It is also why the dyld shared cache and the kernelcache are the *first* things a reverser symbolicates — the static trust cache is right there.

### Entitlements: privilege as a property of the signature

This is the deepest conceptual shift from the Mac, and it ties back to Reset 0 of [[macos-to-ios-mental-model-reset]]: **on iOS there is no uid you escalate to; a program's privileges are the entitlements embedded in its code signature.** "Can this process do X?" is answered at sign-and-verify time by its entitlement set, not at runtime by `sudo`.

Entitlements are a property-list of keys the binary claims, pinned by the Code Directory (so they can't be edited post-signing) and *authorized* by the provisioning profile (so a developer can't claim whatever they like). Categories worth knowing:

- **Capability entitlements** a normal developer can request via a profile: `application-identifier` (the App ID), `keychain-access-groups`, `com.apple.security.application-groups` (App Groups), `com.apple.developer.*` (push, HealthKit, Network Extension, associated domains, …). These map to the "Capabilities" you toggle in Xcode.
- **Restricted entitlements** only **Apple** can grant (held by platform binaries, never issuable to third parties): `platform-application`, `com.apple.private.*` (thousands of private SPI gates), `task_for_pid-allow` (debug arbitrary processes), and the like. A third-party app claiming one of these is refused.
- **Special developer entitlements** with security weight: **`get-task-allow`** (lets a debugger attach to this process — present in development builds, *absent* in App Store builds, which is why you can't `lldb`-attach to a shipping app); **`dynamic-codesigning`** (the `MAP_JIT` W^X exception for JIT, held by WebKit's JIT processes and essentially no third-party app — the reason on-device interpreters historically ran interpreter-only and why Frida injection is hard, [[dynamic-analysis-with-frida]]).

> 🖥️ **macOS contrast:** macOS entitlements exist and matter (the hardened runtime, `com.apple.security.cs.allow-jit`, the App Sandbox entitlement), but a Mac developer can **self-sign** most of them and run; the system trusts the developer at the keyboard. On iOS the same entitlement is inert unless a **provisioning profile signed by Apple** authorizes it — privilege is delegated from Apple, not asserted by the owner.

### Provisioning profiles: Apple's authorization to run non-Store code

An App Store binary is signed by Apple's distribution process and trusted device-wide. *Every other* way of running third-party code — development, ad-hoc, TestFlight, enterprise — carries an **`embedded.mobileprovision`** inside the `.app`: a **CMS-signed plist** that ties together, and which `amfid` validates at launch:

- the **signing certificate(s)** allowed (Apple Development / Apple Distribution / Enterprise);
- the **App ID** and **Team ID** (explicit, e.g. `com.acme.app`, or wildcard `com.acme.*`);
- the list of **device UDIDs** the build may run on (development/ad-hoc; absent for App Store/enterprise wildcard);
- the **entitlements** the binary is permitted to claim (its actual entitlements must be a subset);
- an **expiry** (development/distribution profiles last up to 12 months; **free "personal team" provisioning expires in 7 days**, which is exactly why a self-signed sideload stops launching after a week).

So the launch-time question the kernel+`amfid` answer for a non-Store app is: *is this binary signed by a cert the profile names, is this device in the profile's UDID list, and are its entitlements within what the profile grants?* Fail any and the app won't launch — `amfid` denies, `CS_KILL`. This is the machinery behind every "Unable to install / this app cannot be installed because its integrity could not be verified" message a developer ever curses at.

> 🔬 **Forensics note:** `embedded.mobileprovision` is a useful artifact in its own right. As a CMS-signed plist it carries the **Team ID**, team name, the developer/enterprise **certificate**, creation/expiry dates, the **provisioned device UDIDs**, and the **full entitlement set** the app was authorized for. For an unknown or sideloaded app pulled from an image, decode it (`security cms -D -i embedded.mobileprovision | plutil -p -`) to attribute it to a developer/enterprise account and to see what it was allowed to do — including whether it carried `get-task-allow` (a development build) or unusual capabilities.

## Hands-on

Everything runs on the Mac. There is no on-device shell; you inspect signatures of Simulator binaries, of `.ipa`s, and of firmware Mach-Os pulled from an IPSW.

### Read a Mach-O's signature, identity, and entitlements

```bash
# A Simulator-built app binary, or any Mach-O. -dvvv dumps the signature detail.
codesign -dvvv /path/to/Foo.app/Foo
#   Identifier=com.acme.Foo
#   TeamIdentifier=ABCDE12345        (or "not set" for ad-hoc)
#   CodeDirectory v=20400 size=... flags=0x0(none) hashes=...+5 location=embedded
#   CDHash=3a7bd3e2360a... (sha256)      ← the binary's identity
#   Sealed Resources ...; Internal requirements ...

# The entitlements blob (the privilege claims), printed as a plist:
codesign -d --entitlements :- /path/to/Foo.app/Foo

# ldid (Procursus) is the lightweight cross-platform alternative:
ldid -e /path/to/Foo.app/Foo        # print entitlements
ldid -h /path/to/Foo.app/Foo        # print cdhash(es)

# jtool2 / blacktop ipsw give the raw SuperBlob structure:
jtool2 --sig -v /path/to/Foo
ipsw macho info --sig /path/to/Foo
```

Expected output described: `flags=0x0(none)` on a normal app; an **ad-hoc** signature shows `flags=0x2(adhoc)` and `TeamIdentifier=not set`; a development build's entitlements include `<key>get-task-allow</key><true/>`; an App Store build does not.

### Decode an embedded provisioning profile

```bash
# From inside an .ipa's Payload/App.app/
security cms -D -i embedded.mobileprovision | plutil -p -
#   "AppIDName" => "Acme App"
#   "TeamIdentifier" => [ "ABCDE12345" ]
#   "Entitlements" => { application-identifier, keychain-access-groups, get-task-allow, ... }
#   "ProvisionedDevices" => [ "00008110-001A...", ... ]   (development/ad-hoc only)
#   "CreationDate"/"ExpirationDate" => ...
#   "DeveloperCertificates" => [ <CMS cert blobs> ]
```

### Find a binary's cdhash in (or absent from) a trust cache

```bash
# Pull the kernelcache from an IPSW and dump its static trust cache cdhashes:
ipsw download ipsw --device iPhone16,1 --latest        # (downloads the signed IPSW)
ipsw kernel extract <ipsw>                              # decompress the kernelcache
ipsw kernel ctr/trustcache <kernelcache>               # list trust-cache cdhashes
# Then compare a recovered binary's cdhash (ldid -h) against that set:
#   present  → a platform binary that belongs to this build
#   absent   → not Apple-shipped; expected for third-party, suspicious for "system" paths
```

## 🧪 Labs

> All labs are **device-free**: Simulator binaries, downloadable `.ipa`s, and IPSW firmware on the Mac. **Fidelity caveat:** the Simulator does **not** enforce AMFI/code-signing (it runs macOS frameworks), so it teaches the *structure* of signatures and entitlements but never the *enforcement*. The "what the kernel does with this" half is reasoning, not observation.

### Lab 1 — Anatomy of a signature (Simulator binary)

**Substrate:** Simulator-built app. **Caveat:** Simulator binaries are typically ad-hoc-signed and unenforced.

1. Build any SwiftUI app to the Simulator, locate its `.app`, and run `codesign -dvvv` on the main Mach-O. Record the `Identifier`, `TeamIdentifier`, `CDHash`, and `flags`.
2. `codesign -d --entitlements :-` and `ldid -e` on the same binary. Compare their output — note the entitlement keys present (or that it's a near-empty Simulator entitlement set).
3. Modify one byte of the binary (`cp` it first), re-run `codesign -dvvv`, and observe the signature is now invalid. State, in one sentence, what would happen to this byte-edited binary on a *real* device at exec time (answer: `CS_KILL` — the page hash no longer matches the Code Directory).

### Lab 2 — Attribute and audit an `.ipa` (downloaded app)

**Substrate:** any free `.ipa` (or one you exported via Xcode → Archive → ad-hoc).

1. `unzip` the `.ipa`; in `Payload/App.app/`, decode `embedded.mobileprovision` with `security cms -D … | plutil -p -`.
2. Record: Team ID, the certificate type (Development vs Distribution vs Enterprise), the entitlement set, expiry, and whether `ProvisionedDevices` is present (development/ad-hoc) or absent (App Store/enterprise).
3. Cross-check: run `codesign -d --entitlements :-` on the app binary and confirm its claimed entitlements are a **subset** of the profile's authorized entitlements. Explain why the kernel would refuse the app if they weren't.

### Lab 3 — Trust cache membership (IPSW, read-only)

**Substrate:** one downloaded IPSW; Mac-side `ipsw`/`ldid`.

1. Extract the kernelcache from an IPSW and list its static trust-cache `cdhash`es.
2. Take a system binary you also extracted from the same IPSW (`ipsw extract`), compute its `cdhash` with `ldid -h`, and find it in the trust-cache list — proving it is a platform binary that loads without an `amfid` call.
3. Now compute the `cdhash` of your Lab 1 Simulator app and confirm it is **absent** from the trust cache. Write the two-sentence forensic rule: a `cdhash` in the device's trust cache is trusted platform code; an unexpected loadable trust cache, or a "system-path" binary whose `cdhash` is in no Apple trust cache, is a tamper indicator.

## Pitfalls & gotchas

- **Signing on iOS is execution control, not download control.** Don't carry the macOS mental model where "signing only matters for distribution." On iOS the kernel checks *every executable page*; there is no path that skips it on a stock device.
- **`get-task-allow` is why you can't debug App Store apps.** Development builds carry it (debuggers can attach); App Store builds don't. If `lldb`/Frida "can't attach," check whether the target even has `get-task-allow` — on a non-jailbroken device, a Store binary never will.
- **Entitlements must be a *subset* of the profile.** A build can *claim* fewer entitlements than the profile grants, never more. "Provisioning profile doesn't include the X entitlement" means the profile (App ID capabilities), not the code, is what to fix.
- **Free provisioning is a 7-day clock.** A personal-team (free) signed sideload stops launching after 7 days because the profile/cert expires — not a bug, the design. Paid distribution profiles last ~12 months.
- **`cdhash` is the identity, not the path.** Two binaries at the same path with different bytes have different `cdhash`es; the same bytes anywhere have the same `cdhash`. Trust, entitlement grants, and tamper checks key on the `cdhash`, never the filename.
- **CoreTrust ≠ amfid.** The cert-chain check (CoreTrust, in-kernel) and the entitlement/profile check (amfid, userspace) are separate steps. Historically attacked separately (CoreTrust → TrollStore; amfid patching → early jailbreaks). Don't conflate "the signature chains to Apple" with "the entitlements are authorized."
- **Ad-hoc signed ≠ unsigned.** An ad-hoc signature (`flags=0x2(adhoc)`, no Team ID) still has a valid Code Directory and `cdhash` — it just isn't chained to an issuer. On iOS it still won't run unless its `cdhash` is in a trust cache (the TrollStore trick) or a profile vouches for it.
- **Simulator proves nothing about enforcement.** The Simulator happily runs byte-edited, ad-hoc, entitlement-stripped binaries because it doesn't enforce AMFI. Validate signing *structure* there; never conclude anything about device *enforcement* from it.

## Key takeaways

- iOS code signing is a **kernel page-fault invariant**: every executable page must hash to a valid, Apple-rooted signature, enforced by **AMFI** at fault-in time. There is no override, no `chmod +x`, no shell.
- The signature is a **SuperBlob** whose **Code Directory** holds per-page hashes + special slots (Info.plist, entitlements, resources); its hash is the **`cdhash`** — the canonical identity that trust caches, entitlement grants, and tamper checks all key on.
- Enforcement is split: **`AMFI.kext`** (kernel) trusts **platform binaries** via the **trust cache** with no round-trip; for third-party code it calls up to **`amfid`** (userspace) to validate the CMS signature, profile, and entitlements. **CoreTrust** (kernel) independently demands an Apple-rooted cert so a subverted `amfid` still can't approve arbitrary signers.
- **Entitlements are the privilege currency** — there is no uid to escalate to. Restricted entitlements are Apple-only; `get-task-allow` (debug) and `dynamic-codesigning` (JIT) are the security-relevant developer ones.
- A **provisioning profile** is Apple's signed authorization for non-Store code: it binds cert + App ID + device UDIDs + permitted entitlements + expiry, and `amfid` checks the binary against it at launch (free provisioning = 7-day clock).
- **Forensically**, signing state is tamper detection: a non-Apple loadable trust cache, cleared AMFI enforcement, or a "system" binary whose `cdhash` is in no Apple trust cache are jailbreak/implant indicators — and `embedded.mobileprovision` attributes a sideloaded app to a developer/enterprise account.

## Terms introduced

| Term | Definition |
|---|---|
| AMFI | Apple Mobile File Integrity — `AppleMobileFileIntegrity.kext` (kernel) + `amfid` (userspace) enforcing mandatory code signing at page-fault time. |
| `amfid` | The userspace daemon AMFI calls to validate third-party CMS signatures, provisioning profiles, and entitlements. |
| Code signature SuperBlob | The container (in `__LINKEDIT`, pointed to by `LC_CODE_SIGNATURE`) holding the Code Directory, Requirements, entitlements, and CMS signature sub-blobs. |
| Code Directory | The core sub-blob: per-memory-page hashes + special slots (Info.plist, entitlements, resources) + bundle/team identifiers and flags. |
| `cdhash` | The hash of the Code Directory — the canonical, tamper-evident identity of a specific binary; what trust caches and entitlement grants key on. |
| Special slots | Negative-indexed Code Directory hashes pinning the Info.plist, internal requirements, entitlements, and `_CodeResources`. |
| Trust cache | An in-kernel list of approved `cdhash`es: static (in the kernelcache), loadable (`ltrs`, e.g. the DDI), or engineering. A `cdhash` in it = platform binary, trusted without an `amfid` call. |
| Platform binary | Apple's own code whose `cdhash` is trust-cached: trusted immediately and granted platform entitlements. |
| CoreTrust | The in-kernel validator that a binary's CMS signature chains to an Apple-issued certificate — independent of (and below) `amfid`. Its historical signature-validation bug enabled TrollStore. |
| Entitlements | Key/value privilege claims embedded in the signature (pinned by the Code Directory, authorized by the profile); on iOS they *are* the privilege model — there is no uid to escalate to. |
| Restricted entitlement | An entitlement only Apple can grant (`platform-application`, `com.apple.private.*`, `task_for_pid-allow`, …); a third-party claim is refused. |
| `get-task-allow` | The entitlement permitting a debugger to attach; present in development builds, absent in App Store builds. |
| `dynamic-codesigning` | The entitlement permitting a `MAP_JIT` W^X region (JIT); held by WebKit JIT processes, essentially never by third-party apps. |
| Provisioning profile (`embedded.mobileprovision`) | A CMS-signed plist binding allowed cert(s) + App ID/Team + device UDIDs + permitted entitlements + expiry; `amfid` checks a non-Store binary against it at launch. |
| Free (personal-team) provisioning | The 7-day-expiry signing path for personal-device development; the reason a self-signed sideload stops launching after a week. |

## Further reading

- **Apple Platform Security guide** (security.apple.com) — "Code signing," "Mandatory code signing," and the trust-cache / system-integrity sections. The primary source; cite the current edition.
- **Apple Developer** — *Technote TN3125: Inside Code Signing* (Mach-O signature format, requirements), the "Provisioning" and "Code Signing" Help, and the Entitlements reference.
- **Jonathan Levin**, *MacOS and iOS Internals* vols I & III + newosxbook.com — `amfid`, AMFI, CoreTrust, the trust cache, and `jtool2 --sig` internals.
- **theapplewiki.com** — `AMFI`, `Trust Cache`, `CoreTrust`, and the per-version `TrollStore` pages (the CoreTrust bug history).
- **`codesign(1)`, `ldid`, `security cms`, `ipsw macho`** man/usage pages — exact flags for inspecting signatures and profiles.
- **OWASP MASTG** (mas.owasp.org) — "iOS Code Signing" and "Testing Code Quality" sections for the app-security-testing view.

---
*Related lessons: [[the-ios-security-model]] | [[dyld-shared-cache-and-amfi]] | [[macos-to-ios-mental-model-reset]] | [[the-sandbox-and-tcc]] | [[boot-chain-securerom-iboot]] | [[code-signing-and-provisioning-in-depth]] | [[trollstore-and-the-coretrust-bug]] | [[the-jailbreak-landscape-2026]] | [[the-app-bundle-and-ipa-structure]]*
