---
title: "TrollStore & the CoreTrust bug"
part: "11 — Reverse Engineering & App Security"
lesson: 08
est_time: "40 min read + 15 min labs"
prerequisites: [code-signing-amfi-entitlements, the-jailbreak-landscape-2026]
tags: [ios, re, trollstore, coretrust, code-signing]
last_reviewed: 2026-06-26
---

# TrollStore & the CoreTrust bug

> **In one sentence:** TrollStore is the clearest case study of the **CoreTrust gate** in the iOS signing model — a *signature-validation* flaw class (not a kernel exploit, not a jailbreak) that tricked the kernel's "is this signer really Apple?" check into stamping an **ad-hoc binary carrying arbitrary entitlements** as App-Store-blessed, yielding *permanent, non-expiring* sideloads with root helpers on **any** device on a supported OS — and whose closure at iOS 17.0.1 is exactly why you must reason about install provenance, not just "is it signed."

## Why this matters

In [[code-signing-amfi-entitlements]] you learned the enforcement stack: AMFI checks every executable page against a Code Directory, **amfid** (userspace) validates third-party CMS signatures + provisioning profiles + entitlements, and **CoreTrust** (in-kernel) independently demands that the signature chain to a real Apple-issued certificate so a subverted amfid still can't approve arbitrary signers. That lesson named TrollStore in passing. This is the full treatment, and it matters on three axes:

- **As a reverse-engineer**, TrollStore is the most valuable RE-enablement tool of the iOS 14–17 era *on supported devices*. It installs your own tooling — debuggers, on-device Frida helpers, unsandboxed file managers, SSH — **permanently**, with the powerful entitlements those tools need, **without a jailbreak and without a Mac re-signing it every 7 days**. Understanding *why* it worked tells you exactly what it can and cannot give you (it is code-exec with arbitrary entitlements, **not** kernel compromise).
- **As a forensic examiner**, a TrollStore-installed app is a **distinct install-provenance category** — neither App Store, nor TestFlight, nor enterprise, nor developer sideload, nor jailbreak. It looks like a normal jailed app in the install databases, so distinguishing it is a signature-parsing skill, and "this device has run TrollStore" is a determinable, reportable fact.
- **As a student of the trust model**, the CoreTrust bug class is the single best illustration of the gate itself: it shows that the *cert-chain check* and the *entitlement check* are separate steps, that "App Store signed" is a **policy flag** the kernel sets, and that whoever controls that flag controls what entitlements a binary may carry. Break the flag and you break the whole edifice — without ever touching the kernel's code.

The reason this lesson is worth its length even though the bug is closed: TrollStore is the *proof* that lets you reason precisely about every adjacent topic. It is the clean dividing line between "code-signing bypass" and "jailbreak"; the reason `embedded.mobileprovision` presence is a provenance signal; the worked example FairPlay ([[fairplay-encryption-and-decrypting-app-store-apps]]) and Frida ([[dynamic-analysis-with-frida]]) lessons assume you understand. Hold the mechanism and the boundary, and the rest of Part 11 stops being a list of tools and becomes a single coherent model of *what the kernel trusts, and why*.

## Concepts

The CoreTrust bug class is best understood as an attack on **classification**, not on **cryptography**. Nothing below is a broken hash or a forged signature in the mathematical sense — every TrollStore binary's Code Directory genuinely matches its bytes, and the page hashes verify. What's forged is the kernel's *answer to the question "who signed this?"*. The subsections build that idea in order: where the classification happens and what flag it produces; why the check lives in the kernel at all; the two distinct flaws that subverted it; what the result looks like on disk; and what an attacker — and an examiner — does with it.

### Where CoreTrust sits, and the flag it sets

Recall the split from [[code-signing-amfi-entitlements]]. When AMFI faults in a third-party page it can't judge alone, it consults **CoreTrust**, a small in-kernel certificate validator (introduced ~iOS 12 precisely to stop the *fake-signing* jailbreak trick, where attackers ad-hoc-signed binaries and patched `_MISValidateSignatureAndCopyInfo` in a subverted amfid). CoreTrust's job is narrow but pivotal: parse the **CMS signature** (the `0xFADE0B01` sub-blob of the code-signature SuperBlob, [[the-code-signature-blob-and-entitlements-on-ios]]), walk its certificate chain, and decide *what kind* of signer this is.

The output that matters is a **policy flag**. CoreTrust classifies the signature and tells AMFI, in effect, one of: *Apple platform binary*, *App Store*, *TestFlight*, *developer/enterprise*, or *untrusted*. The **App Store** classification is the dangerous one, because of a design assumption baked into the whole model:

> **App Store apps are trusted to carry their own entitlements.** The App Store review process — not a per-device provisioning profile — is assumed to be the gate. So when CoreTrust sets the **App Store policy flag**, AMFI will honor *almost any entitlement the binary's Code Directory claims*, with no `embedded.mobileprovision` required and no UDID list to satisfy.

That is the keystone. A genuine App Store binary needs no profile because the flag *is* its authorization. So the entire attack reduces to one question: **can you get CoreTrust to set the App Store flag on a binary Apple never signed?** Do that, embed whatever entitlements you like in *your* Code Directory, and AMFI waves it through. You never need to defeat amfid, the sandbox, the kernel, or Data Protection — you only need to lie to CoreTrust about who signed you.

> 🖥️ **macOS contrast:** On macOS this whole problem is moot in the other direction — you can ad-hoc-sign a binary and run it straight from Terminal because signing is *policy, not physics* (the doorman, not the law). CoreTrust exists on Apple Silicon macOS too, sharing the same code; in fact **Linus Henze's original CoreTrust bug (CVE-2022-26766) was demonstrated to get root on macOS 12.3.1** as well as enabling TrollStore on iOS — same validator, same flaw, both platforms. The difference is leverage: on macOS the bug was a privilege escalation among many paths; on iOS, where the kernel refuses *all* non-Apple-rooted code, that same bug was the only door to permanent unsandboxed code-exec without a jailbreak.

### The two-gate model, and the arms race that produced CoreTrust

Why does CoreTrust exist as a *separate* in-kernel gate at all, when amfid already validates signatures? Because amfid runs in **userspace**, and the history of iOS jailbreaks is largely the history of subverting it. The recap from [[code-signing-amfi-entitlements]], drawn as two gates:

```
 third-party page faulted executable
        │
   ┌────▼─────────────────────┐   GATE 1 (in-kernel, below userspace)
   │ CoreTrust                 │   "does the CMS chain to a real Apple cert,
   │  parse CMS → classify     │    and what CLASS of signer is it?"
   │  set policy flag          │   → App Store / developer / platform / untrusted
   └────┬─────────────────────┘
        │ flag
   ┌────▼─────────────────────┐   GATE 2 (amfid, userspace)
   │ amfid                     │   "is the provisioning profile valid, and are the
   │  validate profile +       │    entitlements ⊆ what the profile authorizes?"
   │  reconcile entitlements   │   (App Store flag ⇒ this profile step is skipped)
   └────┬─────────────────────┘
        │ verdict + entitlement set
   ┌────▼─────────────────────┐
   │ AMFI.kext → grant / deny  │
   └──────────────────────────┘
```

The order is the whole story. Early jailbreaks attacked **Gate 2**: they ad-hoc/"fake"-signed binaries (valid Code Directory, no real issuer) and, having already compromised the kernel, hooked `_MISValidateSignatureAndCopyInfo` inside a patched amfid to return "valid" for anything. Apple's countermove was to move the **identity** decision *below* userspace into **Gate 1 — CoreTrust** — so that even a fully subverted amfid could no longer make a non-Apple-rooted binary pass, because the kernel itself now demanded the Apple chain. That closed fake-signing as a standalone primitive.

TrollStore is the **mirror image** of the old attack. Instead of *patching* the gate (which needs a jailbreak), it **lies to Gate 1 itself** with a forged-but-internally-valid signature, so CoreTrust *voluntarily* sets the App Store flag — and once that flag is set, Gate 2's profile/entitlement reconciliation is *skipped* (App Store apps carry their own entitlements by design). One forged classification at Gate 1 collapses both gates, on a completely stock kernel. That is why the bug class was so prized, and why its closure was decisive: there is no userspace fallback when the thing you fooled is the *kernel's own* validator.

### CoreTrust bug #1 — the Root Certificate Validation flaw (CVE-2022-26766)

This is the bug TrollStore **1.x** rode, found by **Linus Henze**.

CoreTrust's whole purpose is to confirm a signature's certificate chain terminates at a **real Apple root CA**. The flaw: it *didn't actually check the root*. CoreTrust inspected the **leaf certificate** for the OID extension that marks an "App Store" cert and, if present, set the App Store policy flag — **without verifying that the chain above that leaf rooted in Apple's CA at all.** The signature merely had to *match the binary* (the Code Directory hashes had to be valid for the bytes), which is trivial to satisfy with your own cert.

So the recipe was: mint your own certificate, give it the App Store extension OID, sign your binary with it, ad-hoc/fake-sign the Code Directory so the page hashes are valid, and embed arbitrary entitlements. CoreTrust saw the App Store OID on the leaf, never checked the (fake) root, set the flag, and AMFI granted the entitlements. **Code signing, for the purpose of *who* signed, became optional.**

Apple closed CVE-2022-26766 (the fix landed in the iOS 15.6 / macOS 12.5 wave, 2022). That should have ended TrollStore — except the bug class had a second member.

### CoreTrust bug #2 — the Multiple Signer Validation flaw

This is what TrollStore **2.x** switched to, and it is the more elegant of the two. It extended support all the way through **iOS 16.6.1, the 16.7 RC build, and iOS 17.0**.

A CMS `SignedData` structure can contain **multiple `SignerInfo` entries** — more than one signer over the same content. CoreTrust mishandled the multiply-signed case by **using different signers for different decisions**:

- It used the certificates from **signer[0]** to decide *whether the binary was Apple/App-Store signed* (→ set the policy flag).
- But it used the Code Directory referenced by a **later signer** to validate that the signature actually *matched the binary's bytes*.

The two checks were never tied to the *same* signer. So you construct a CMS blob with **two signers**:

```
 Code-signature SuperBlob (0xFADE0CC0)
 ├─ CodeDirectory (yours)        ← real per-page hashes of YOUR binary; YOUR entitlements
 ├─ Entitlements (yours)         ← whatever you want: platform-application, get-task-allow, …
 └─ CMS wrapper (0xFADE0B01)  =  SignedData {
        SignerInfo[0]  ── certs: a GENUINE Apple App Store signer
                          (lifted verbatim from any real App Store .ipa)
                          → CoreTrust: "chains to Apple, App Store" → SET App Store flag
        SignerInfo[1]  ── messageDigest over YOUR CodeDirectory
                          → CoreTrust: "the bytes match the signature" → VALID
    }

   CoreTrust verdict: App-Store-signed AND signature-valid  ✔
   AMFI: honor the Code Directory's entitlements  →  arbitrary privilege
```

`signer[0]`'s certificate chain is genuinely Apple's (copied from a real store app, where it's public), so the App Store flag is set legitimately. `signer[1]`'s digest genuinely matches *your* Code Directory — the one carrying *your* arbitrary entitlements — so the "does the signature match the binary?" check passes too. CoreTrust conflated the two signers; AMFI trusted the verdict; your unsigned-by-Apple binary ran as if blessed by the store, carrying entitlements no third-party app could ever legitimately hold.

There are **only two public CoreTrust bypasses of this nature**, and these are them. Both were closed by **iOS 17.0.1**. There is no public CoreTrust bug for iOS 17.0.1+ — and therefore **no iOS 18 or iOS 26 TrollStore**, and barring a third such flaw (unlikely), there never will be.

### Reading the forged signature on disk

Put the two bugs together and you can predict *exactly* what a TrollStore-signed Mach-O looks like when you parse its `__LINKEDIT` SuperBlob ([[the-code-signature-blob-and-entitlements-on-ios]]) — which is what makes detection deterministic rather than heuristic:

```
 SuperBlob (0xFADE0CC0) of a TrollStore-installed binary
 ├─ CodeDirectory (0xFADE0C02)    page hashes of THIS binary; flags include adhoc;
 │                                Team ID = (none); identifier = the app's real bundle ID
 ├─ Entitlements XML (0xFADE7171) ← arbitrary: platform-application, com.apple.private.*, …
 ├─ DER entitlements (0xFADE7172) ← same, DER-encoded
 └─ CMS wrapper (0xFADE0B01)      SignedData with the tell:
        • TrollStore 1.x → ONE signer, leaf carries the App Store OID,
                           chain does NOT terminate at a real Apple Root CA
        • TrollStore 2.x → TWO signers (a genuine Apple App Store signer +
                           an arbitrary one over this binary's CodeDirectory)
```

Contrast that with the three legitimate shapes: an **App Store** binary has one Apple-rooted signer and an entitlement set bounded by review; a **developer/enterprise** binary has one Apple-rooted signer *plus* an `embedded.mobileprovision`; an honest **ad-hoc** binary has no issuer at all and (on a stock device) simply won't run. The TrollStore binary is the only one that pairs an *adhoc-flagged Code Directory carrying Apple-only entitlements* with a *CMS that claims the store but can't prove the root* — and the absence of `embedded.mobileprovision` seals it. Those are bytes you can grep for, not vibes.

### What TrollStore builds on top of the bug

The CoreTrust flaw is the *engine*. TrollStore is the *vehicle* — the userspace machinery that turns one signature trick into a permanent app installer:

1. **Re-sign with the fake root, preserving entitlements.** You can `ldid`-fakesign the binaries inside any `.ipa` with whatever entitlements you want; on install, **TrollStore re-signs them with its fake (CoreTrust-bypassing) certificate and *preserves* those arbitrary entitlements**. The store-review entitlement ceiling simply doesn't apply.
2. **No provisioning profile → no expiry clock.** A normal free sideload dies after 7 days because its `embedded.mobileprovision` expires ([[code-signing-amfi-entitlements]]). A TrollStore app **has no provisioning profile at all** — it authorizes via the (forever-valid) App Store policy flag, not a profile. Nothing to expire. **Permanent.**
3. **Device-independent.** Because this is a *code-signing* bug, not a BootROM or kernel exploit, it has **nothing to do with the checkm8/usbliter8 A8–A13 boundary** ([[the-jailbreak-landscape-2026]]). TrollStore works on **arm64 (A8–A11) *and* arm64e (A12–A17, M1/M2)** alike — including devices with *no* public jailbreak — as long as the OS is in the supported window. This is the crucial mental separation: **TrollStore is orthogonal to jailbreaks.**
4. **Unsandboxed + root helpers.** A TrollStore app can be installed **unsandboxed**, so it can `posix_spawn` other binaries, and via the `spawnRoot` helper (in TrollStore's `TSUtil.m`) **spawn them as root**. This is what powers Filza-style whole-filesystem file managers, on-device package tooling, and persistent daemons — *without* a kernel patch.
5. **The persistence helper.** New apps installed to `/var` revert from "System" to "User" state whenever the system **rebuilds the icon cache**, which un-registers them. TrollStore's *persistence helper* **replaces a stock system app** (which stays registered as "System" across icon-cache reloads) and uses that foothold to **re-register the TrollStore apps** back to System state so they keep launching. On jailbroken iOS 14, `TrollHelper` in `/Applications` serves the same role.

Because the engine is a *signing* flaw rather than anything iPhone-specific, the same permasigning trick reached the rest of Apple's CoreTrust-gated platforms: community ports demonstrated **permasigned apps on the Apple Watch** (the same CoreTrust bug) and a **TrollStore-tvOS** for Apple TV. The lesson generalizes — *any* device whose code-signing identity decision flows through CoreTrust inherited both the gate and, on the affected OS versions, the bypass.

> ⚠️ **ADVANCED — this is a real privilege primitive, not a toy.** "Arbitrary entitlements + root helper, no jailbreak" means a TrollStore app can do things a sandboxed App Store app never could: read across containers, talk to private SPI, attach a debugger to itself. It is *userspace* power, scoped by what entitlements you embed — but on a supported device it is genuine, persistent, root-capable code execution. Treat any TrollStore-capable device in an investigation as one where arbitrary unsandboxed tooling *may already have run*.

### Bootstrapping: getting the first forged app onto the device

There is a chicken-and-egg problem the signature bug alone doesn't solve: to *install* an app with a forged signature you need something already running that can drive the install pipeline. TrollStore's install methods are all ways to get that first foothold, and they evolved as Apple tightened `installd`:

- **iOS 14.0 – 15.6.1 — the `installd` bypass.** A flaw in `installd`'s handling let a helper app (`TrollHelper`) drive the install of TrollStore directly. On iOS 14, `TrollHelperOTA` could even be served from **Safari** (an `itms-services`-style OTA install), so the entire bootstrap was on-device, no Mac required. On jailbroken iOS 14, the `TrollHelper` in `/Applications` doubles as the persistence helper.
- **Later versions (15.x – 17.0) — sideload-then-install.** With the `installd` path closed, you first **sideload a small installer** (`TrollInstallerX`, `TrollInstallerMDC`, or `TrollMisaka`) with an ordinary free/Sideloadly signature, then run it once to perform the CoreTrust-forged install of TrollStore proper. The installer is disposable (it can expire in 7 days); **TrollStore, once installed, is permanent** because *it* now carries the forged App Store flag.

The conceptual point: the **CoreTrust bug is what makes the result permanent and arbitrarily entitled**, but a *separate* bootstrap primitive (an `installd` quirk, or a one-shot sideload) is what gets the forged bundle written in the first place. Conflating the two — "TrollStore *is* the CoreTrust bug" — misses that the bug is the *engine*, not the *ignition*.

### What permanent ad-hoc-with-entitlements signing unlocks for RE

For a reverse-engineer with a *supported* (≤17.0) device, this one capability — install your own binary, **permanently**, with **whatever entitlements it needs**, on a **stock kernel** — is transformative. It's worth enumerating exactly what it buys:

- **An on-device debug stack.** Embed `get-task-allow` (so a debugger may attach) plus the debug-server entitlements and you can run a permanent `debugserver`/`lldb` server and attach to *your own* TrollStore-installed targets — no Xcode 7-day re-sign, no developer-account gymnastics ([[debugging-instruments-and-lldb-for-ios]]). You still can't attach to arbitrary *system* processes you lack the entitlements for; this is not `task_for_pid` over the whole device.
- **Persistent instrumentation.** A **frida-server**, or a Gadget-injected app, installed via TrollStore survives reboots and never expires — turning the on-device half of [[dynamic-analysis-with-frida]] from a fragile, re-signed-weekly affair into a permanent fixture, *on supported devices only*.
- **Whole-filesystem access for triage.** With the unsandboxed + `spawnRoot` primitive, Filza-class file managers and shells (NewTerm / SSH) read across containers and system paths — letting you pull other apps' bundles, inspect `installd` state, and stage artifacts. Userspace root, without a kernel jailbreak.
- **Your own RE harness, permanently.** The real escape is from the free-provisioning treadmill: a tool you'd otherwise re-sign and re-deploy every 7 days ([[code-signing-amfi-entitlements]]) installs **once, forever**, carrying the entitlements it actually needs rather than the near-empty set a free profile grants.

Set against the alternatives, the shape to memorize is that **TrollStore sits between a free sideload and a jailbreak**:

| For RE work | Free dev sideload | TrollStore (≤17.0) | Jailbreak |
|---|---|---|---|
| Persistence | 7-day expiry | **permanent** | permanent (semi-untethered: re-run after reboot) |
| Entitlements | profile-limited | **arbitrary** | arbitrary |
| Sandbox | enforced | **optional (unsandboxed)** | none |
| Root | no | **root helper (userspace)** | **full (kernel)** |
| Tweak injection into *other* apps | no | no | **yes** (ElleKit/Substrate) |
| Kernel R/W · AMFI patch · SEP/DP defeat | no | no | **yes** |
| Device requirement | any | **any, on a supported OS** | BootROM/kernel-exploitable only |

Far more capable than a free sideload (permanent, arbitrary entitlements, root helper), strictly weaker than a jailbreak (no kernel, no tweak injection into other processes, no Data-Protection defeat), and uniquely **device-agnostic within its OS window** — that triangulation is the entire practical value of understanding the bug.

### What it is *not*: the hard ceiling

TrollStore is repeatedly miscalled a jailbreak. It is not, and the boundary is exactly what an RE/forensics practitioner must hold:

| TrollStore gives you | TrollStore does **not** give you |
|---|---|
| Permanent install of *your* binaries | Kernel code execution / arbitrary kernel R/W |
| Arbitrary **entitlements** on those binaries | A patched AMFI / disabled code-signing system-wide |
| **Unsandboxed** userspace + root **helper** | A defeat of **SEP / Data Protection / the passcode** |
| Private-SPI access (where entitlements permit) | Decryption of other apps' Data-Protection-class files at rest |
| No 7-day expiry; survives reboot | Tweak **injection** into other processes (that needs a jailbreak/ElleKit) |

It runs *within* the existing kernel and SEP. It cannot read what Data Protection keeps encrypted while locked, cannot dump another process it lacks the entitlements to touch, and does not weaken the boot chain. For the forensic boundary that *does* defeat Data Protection, see [[bfu-vs-afu-and-data-protection-classes]]; for kernel-level compromise see [[the-jailbreak-landscape-2026]].

### The supported window, precisely

> **Dated facts (verify at author time — 2026-06-26).** TrollStore's supported window is **iOS/iPadOS 14.0 beta 2 – 16.6.1**, the **16.7 RC (build 20H18)**, and **17.0**. Explicitly **never supported**: 16.7.x (except that one RC build) and **17.0.1 and later** — the line where Apple closed both CoreTrust bug classes. There is **no iOS 18.x and no iOS 26.x support**, and none is expected. Installation onto a supported device (a Mac-side or one-time step, depending on version/arch) used helpers such as `TrollHelperOTA` (Safari install on iOS 14), `TrollInstallerX`/`TrollInstallerMDC`/`TrollMisaka` (sideload-then-install via Sideloadly on later versions); the exact path varied by iOS version and arm64-vs-arm64e. Maintained by **opa334**.

The durable takeaway under the dates: **a device's *current* OS tells you whether TrollStore *could* be installed now, but not whether it *was* installed earlier.** A device updated from 16.5 to 26.x can still carry a TrollStore app and its persistence helper from when it was on 16.5 — the apps keep running across the update even though you could no longer *install* TrollStore. Provenance is historical, not just current-state.

The whole arc, as a reference:

| TrollStore | CoreTrust flaw it rode | Engine mechanic | Approx. window |
|---|---|---|---|
| **1.x** | Root Certificate Validation (CVE-2022-26766, Henze) | leaf's App Store OID accepted **without verifying the chain rooted in Apple** | iOS 14.0–15.x, until 26766 was patched (~15.6) |
| **2.x** | Multiple Signer Validation | `signer[0]`'s certs set the flag; a **later signer's** Code Directory validates the bytes | iOS 14.0 b2–16.6.1, 16.7 RC (20H18), 17.0 |
| **—** | both closed | — | **17.0.1 and later: never supported** |

> ⚖️ **Authorization:** installing TrollStore-class tooling, and analyzing a device *for* it, are both scoped acts. Forge and inspect signatures only on **hardware you own or are authorized to examine** — an `ldid`-fakesigned binary carrying `task_for_pid-allow` is a real privilege artifact, not a thought experiment. When a provenance finding ("this app was TrollStore-installed; it carried `com.apple.private.*`") enters a report it carries evidentiary weight about *capability and intent*, so document the exact bytes that support it — `cdhash`, CMS signer count, the missing `embedded.mobileprovision`, the entitlement keys — and the tool + version that produced them, the same way you log any artifact in chain of custody.

### Why there is no iOS 18 / 26 TrollStore — and what it would take

Three things must fail together for a future TrollStore, and on modern builds none is cheap. **First**, you need a *new* CoreTrust signature-validation flaw — and note the specificity: a kernel jailbreak would **not** resurrect TrollStore, because TrollStore never needed kernel R/W; it needed CoreTrust to *misclassify a signer*. Both known flaws are patched, and only two have ever been public, so this is the binding constraint. **Second**, you need a **bootstrap** to write the forged bundle (the `installd`/sideload ignition above), which Apple has hardened independently of CoreTrust. **Third**, the whole thing sits atop the modern mitigation ladder — PAC → PPL → SPTM/TXM → Exclaves → MIE ([[the-jailbreak-landscape-2026]]) — which doesn't *touch* the signing-classification logic but does mean any *kernel* foothold you might otherwise lean on is far harder to obtain.

The net: TrollStore's absence on iOS 18/26 is not "no one has built the app yet," it's "the specific bug class that powered it is closed, and re-opening it requires a *third* public CoreTrust validation flaw that may simply not exist." That is why the grounded answer is **frozen ≤ 17.0**, not *coming soon* — and why, for any device on a current OS, your analytical posture is detection of a *past* install, not anticipation of a new one.

> 🔬 **Forensics note — TrollStore apps are a distinct provenance class.** Installed TrollStore apps live in the **normal** locations — bundle in `/private/var/containers/Bundle/Application/<UUID>/`, data in `/private/var/mobile/Containers/Data/Application/<UUID>/`, registered in `installd`/`/private/var/mobile/Library/FrontBoard/applicationState.db` like any jailed app — so a glance at the app list won't flag them. The tells are in the **signature and the metadata**: (1) the code-signature CMS carries the **multiply-signed structure** (>1 `SignerInfo`) or a leaf with the App Store OID over a chain that **does not validate to a real Apple root**; (2) there is **no `embedded.mobileprovision`** in the bundle (a legitimately distributed dev/enterprise/ad-hoc app always has one); (3) the **entitlements include keys impossible for a real third-party app** — `platform-application`, `task_for_pid-allow`, `com.apple.private.*`, or `get-task-allow` on a "shipping" app; and (4) **TrollStore itself + its persistence helper** are present — a stock system app whose bundle has been *replaced* with one whose signature/entitlements don't match Apple's shipped binary. `MobileInstallation` logs under `/private/var/mobile/Library/Logs/MobileInstallation/` may record the install events. Any one of these establishes the install-provenance category; together they let you assert *which* apps were TrollStore-installed and that the device was TrollStore-capable. (Exact persistence-helper target app and TrollStore's own bundle identifier vary by version — confirm against the build, don't assume.)

> 🔬 **Forensics note — provenance vs. integrity.** This is the practical upshot of the CoreTrust lesson for casework: a binary that *runs* on a stock device proves its signature is *internally valid* (the page hashes match), but, on a TrollStore-capable build, **does not prove it was signed by Apple or any real developer**. The cert-chain check (CoreTrust) and the "bytes match" check (Code Directory) are separable, and TrollStore is the existence proof. So "is this app legitimate?" is two questions — *does the signature match the binary?* and *does the chain root in Apple?* — and you must answer the second explicitly (`ipsw macho info --sig` / `security cms -D`), never infer it from the app merely launching.

> 🔬 **Forensics note — the persistence helper is a tamper artifact in its own right.** Because TrollStore's persistence relies on **replacing a stock system app** with a re-signed impersonator, that system app's bundle no longer matches Apple's shipped binary: its `cdhash` is absent from the device's trust caches ([[code-signing-amfi-entitlements]]), its signature shows the CoreTrust-forgery anomaly, and its `Info.plist`/entitlements may differ from the pristine version. **Diffing a suspect "system" app against the same path extracted from the device's exact IPSW build** (`ipsw extract`, then compare `cdhash`es) cleanly surfaces a hijacked persistence helper — a stronger, harder-to-explain-away indicator than the user-app installs it supports, because a stock device should *never* have a system app whose `cdhash` diverges from the signed firmware image.

## Hands-on

Everything is Mac-side — there is no on-device shell, and on a supported real device the *enforcement* half happens in-kernel where you can't watch it. What you *can* do on the Mac is **build the forgery's structure** and **detect it**, which is the whole RE/forensic skill. (On the Simulator nothing here is *enforced* — AMFI/CoreTrust don't run — so these commands teach the signature *structure*, not the device verdict.)

### Forge the structure: fakesign with arbitrary entitlements

```bash
# Author an entitlement plist a real third-party app could NEVER carry:
cat > ent.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>platform-application</key><true/>
  <key>com.apple.private.security.no-container</key><true/>
  <key>get-task-allow</key><true/>
</dict></dict></plist>
EOF

# ldid (Procursus) ad-hoc/fake-signs AND embeds the entitlements in the Code Directory:
ldid -Sent.plist ./mytool          # -S<file> = sign + apply entitlements

# Read them back — the Code Directory now claims Apple-only privileges:
ldid -e ./mytool
codesign -d --entitlements :- ./mytool 2>/dev/null
#   → platform-application=true, com.apple.private.security.no-container=true, …
```

On a stock ≥17.0.1 device this binary is **inert** — CoreTrust refuses it because the (ad-hoc) chain doesn't root in Apple. On a supported ≤17.0 device, this is precisely the artifact TrollStore would have re-signed and CoreTrust would have waved through. The *bytes you just produced* are the thing the bug honored.

### Detect the forgery: read who really signed it

```bash
# The full SuperBlob, including the CMS signer count and cert chain:
ipsw macho info --sig /path/to/suspect.app/suspect
jtool2 --sig -v /path/to/suspect              # alternative; shows blob layout

# Pull and dump the CMS — count SignerInfo entries and inspect the chain:
codesign -d --extract-certificates=cert /path/to/suspect 2>/dev/null
# or, from a bundle that has a detached/embedded CMS:
security cms -D -i embedded.mobileprovision 2>/dev/null   # (TrollStore apps WON'T have this file)

# The triage tells, in order of confidence:
#   1. No embedded.mobileprovision in the .app                → not a normal sideload
#   2. >1 signer in the CMS, OR App Store leaf over a non-Apple root  → CoreTrust forgery
#   3. Entitlements include platform-application / com.apple.private.* / task_for_pid-allow
#      on a "third-party" bundle                              → impossible for a legit app
ldid -e /path/to/suspect
codesign -dvvv /path/to/suspect 2>&1 | grep -E 'flags=|TeamIdentifier=|CDHash='
#   adhoc flag set + TeamIdentifier=not set + powerful entitlements = the signature of a forgery
```

The forensic decision procedure: **absence of a provisioning profile + impossible entitlements + an anomalous CMS (multiple signers or a non-Apple root carrying the App Store OID) = TrollStore-installed.** No single check is sufficient; the conjunction is conclusive.

**Described output:** on a TrollStore-2-style binary, `ipsw macho info --sig` reports the CMS with **two `SignerInfo` entries** (one whose cert chain resolves to Apple, one that does not), while `codesign -dvvv` shows `flags=0x2(adhoc)`, `TeamIdentifier=not set`, and an `Authority=` chain that **stops short of `Apple Root CA`** — yet `ldid -e` lists `platform-application`/`com.apple.private.*`. A genuine App Store binary, by contrast, shows exactly **one** signer and an `Authority=` that climbs cleanly to `Apple Root CA`.

### Confirm a genuine App Store chain (the control)

```bash
# For comparison, a real App Store / dev binary's chain DOES root in Apple:
codesign -dvvv /path/to/legit.app/legit 2>&1 | grep -A6 'Authority='
#   Authority=Apple iPhone OS Application Signing      (App Store)
#   Authority=Apple Worldwide Developer Relations …    (dev/enterprise)
#   Authority=Apple Root CA
# A TrollStore binary breaks this chain at the root while still claiming the store OID.
```

### Sweep an extracted filesystem for TrollStore provenance

```bash
# Over an extracted/mounted app-bundle tree, flag bundles that look TrollStore-installed:
ROOT=/path/to/extracted/var/containers/Bundle/Application
for app in "$ROOT"/*/*.app; do
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" 2>/dev/null)
  bin="$app/$exe"; [ -f "$bin" ] || continue
  prof="present"; [ -f "$app/embedded.mobileprovision" ] || prof="ABSENT"
  ents=$(ldid -e "$bin" 2>/dev/null | grep -cE 'platform-application|com\.apple\.private|task_for_pid')
  signers=$(ipsw macho info --sig "$bin" 2>/dev/null | grep -ci 'signer')   # >1 ⇒ multiply-signed
  printf '%-38s profile=%-7s priv-ents=%s signers=%s\n' "$(basename "$app")" "$prof" "$ents" "$signers"
done
# Rows with profile=ABSENT AND priv-ents>0 (and/or signers>1) are TrollStore-installed candidates.
```

This is the decision procedure made mechanical: the conjunction *(no profile) ∧ (Apple-only entitlements) ∧ (anomalous CMS)* is what separates a TrollStore install from every legitimate provenance class, in one sweep.

## 🧪 Labs

> All labs are **device-free**. **Substrate + fidelity caveat:** the Mac and the Simulator can build and parse the *structures* CoreTrust judges, but **neither enforces CoreTrust/AMFI** — the Simulator runs macOS frameworks with no on-device signing enforcement, and the Mac runs its own policy. So these labs teach you to *recognize and construct* the signature artifacts; the "and then the kernel waved it through" step is reasoning about a supported ≤17.0 device you do not have, not an observation.

### Lab 1 — Build the impossible entitlement set (Mac / `ldid`)

**Substrate:** any small Mach-O (a Simulator-built binary, or a Hello-World you `clang` on the Mac). **Caveat:** ad-hoc signing here is unenforced; you are producing the *bytes* TrollStore relied on, not running them on a device.

1. Write `ent.plist` claiming `platform-application` and one `com.apple.private.*` key (see Hands-on).
2. `ldid -Sent.plist ./bin`, then `ldid -e ./bin` and `codesign -d --entitlements :- ./bin` to confirm the Code Directory now carries them.
3. State, in one sentence each: (a) why a stock iOS 17.0.1+ device refuses this binary at exec time, and (b) what CoreTrust bug would have made a ≤17.0 device honor those exact entitlements.

### Lab 2 — Walk a real certificate chain to its root (Mac)

**Substrate:** a free `.ipa` (App Store export or any signed app) on the Mac. **Caveat:** you are validating a *genuine* chain so you can recognize a *broken* one by contrast.

1. `unzip` the `.ipa`; on `Payload/App.app/App` run `codesign -dvvv … | grep Authority=` and record the full chain up to `Apple Root CA`.
2. `ipsw macho info --sig` the same binary and locate the **CMS** sub-blob; note it has a **single** signer.
3. Decode `embedded.mobileprovision` (`security cms -D -i … | plutil -p -`) and note the profile is present and names a Team ID. Write the two contrasts a TrollStore app would show instead: **(i)** no `embedded.mobileprovision`, **(ii)** a CMS with multiple signers or an App Store leaf whose chain does *not* reach `Apple Root CA`.

### Lab 3 — Read-only walkthrough: classify an install's provenance (sample image)

**Substrate:** a public iOS reference image / extracted app bundles (Josh Hickman, mvt/iLEAPP test data), or the artifacts of an app you exported. **Caveat:** device-only stores (SEP, Data-Protection state) aren't in scope here; this is pure bundle/signature triage.

1. For each `.app` under `…/Bundle/Application/<UUID>/`, apply the decision procedure: is there an `embedded.mobileprovision`? Parse the signature (`ipsw macho info --sig`) — one signer rooting in Apple, or an anomaly? Dump entitlements (`ldid -e`) — any Apple-only keys?
2. Sort each app into a provenance bucket: **App Store**, **dev/enterprise sideload** (has a profile, real chain), or **TrollStore-installed** (no profile, anomalous CMS, impossible entitlements).
3. Cross-reference `applicationState.db` (`/private/var/mobile/Library/FrontBoard/applicationState.db`) for the bundle IDs and `MobileInstallation` logs for install timing. Write a one-paragraph provenance finding for the most suspicious app: *what category, on what evidence, and what it was authorized to do.*

### Lab 4 — Tabulate the three legitimate classes vs. the forgery (Mac)

**Substrate:** three or four Mach-Os on the Mac — an App Store `.ipa` binary, a developer/ad-hoc-signed binary (Xcode archive), an honest ad-hoc binary, and your `ldid`-fakesigned binary from Lab 1. **Caveat:** none are *enforced* here; you are building the exact comparison table an examiner applies to real bundles.

1. For each binary record four columns: **CMS signer count** (`ipsw macho info --sig`), **chain root** (`codesign -dvvv … | grep Authority=` — does it reach `Apple Root CA`?), **`embedded.mobileprovision`** present/absent, and **most-privileged entitlement** (`ldid -e`).
2. Confirm the pattern: App Store = 1 signer, Apple root, no profile, review-bounded entitlements; developer = 1 signer, Apple root, *has* a profile; honest ad-hoc = no issuer, no profile, would not run on a device.
3. Write the single-line rule that flags a *TrollStore* binary using only these four columns (answer in spirit: *no profile + Apple-only entitlements + a CMS that is either multiply-signed or App-Store-OID-over-non-Apple-root*).

### Lab 5 — Read-only walkthrough: catch a hijacked persistence helper (IPSW + sample)

**Substrate:** an extracted/sample `/Applications/*.app` (a stock system app) plus the matching device's **IPSW** on the Mac. **Caveat:** entirely Mac-side `cdhash` comparison — no device, no enforcement; you're proving the *divergence*, which on a real device is what the trust cache would reject.

1. From the device's exact IPSW build, `ipsw extract` the **pristine** copy of a candidate stock system app and compute its `cdhash` (`ldid -h`).
2. Compute the `cdhash` of the **same-path** app in the sample/extracted filesystem.
3. If they diverge — *and* the suspect's signature shows the CoreTrust-forgery anomaly with Apple-only entitlements — you've found a hijacked persistence helper. State the one-sentence rule: a stock device should **never** carry a system-path binary whose `cdhash` is absent from the firmware's trust cache, so any such divergence is a tamper finding independent of the user apps it supports.

## Pitfalls & gotchas

- **TrollStore is not a jailbreak — stop reasoning about it as one.** It is a code-signing forgery. It does **not** patch the kernel, does **not** disable AMFI system-wide, and does **not** defeat SEP/Data-Protection/the passcode. The single most common analytical error is assuming a TrollStore-capable device is "rooted" in the jailbreak sense — it isn't; the kernel and SEP are intact.
- **It is orthogonal to checkm8/usbliter8.** Because it's a signing bug, not a BootROM/kernel exploit, the **A8–A13 BootROM boundary is irrelevant** to it. TrollStore ran on A14/A15/A16 (arm64e) just fine — *on a supported OS*. Don't conflate "no public jailbreak for this chip" with "TrollStore couldn't run here."
- **Current OS ≠ install history.** A device on iOS 26 today may still carry working TrollStore apps installed when it was on ≤17.0; they keep launching across updates. "17.0.1+ can't *install* TrollStore" does not mean "this 17.0.1+ device never had it." Check for the apps and the persistence helper, not just the OS version.
- **"It runs, therefore it's signed by Apple" is false on supported builds.** That's the entire point of the bug: an internally-valid signature whose chain *doesn't* root in Apple. Always check the chain (`Authority=…Apple Root CA`), never infer legitimacy from the app merely launching.
- **No `embedded.mobileprovision` is a signal, not noise.** Examiners used to dev/enterprise sideloads expect a profile. Its *absence* on a non-App-Store-looking app is one of the strongest TrollStore tells — the app authorized via the App Store *flag*, not a profile.
- **Two CoreTrust bugs, not one.** Don't write "the CoreTrust bug" as if singular: the **Root Certificate Validation** flaw (CVE-2022-26766, TrollStore 1.x) and the **Multiple Signer Validation** flaw (TrollStore 2.x) are distinct members of the class, with different mechanics and different support windows. Both closed by 17.0.1.
- **Simulator/Mac prove structure, never the device verdict.** You can build and read the forged signature locally, but neither platform enforces CoreTrust the way a stock iPhone does. Never conclude "this would run on a device" from the fact that your Mac didn't stop it.
- **Re-signing preserves entitlements *because* the bug bypasses the ceiling.** On a patched device, even if TrollStore's installer re-signed your binary, CoreTrust would reject the chain and the entitlements would be moot. The entitlement-preservation behavior is downstream of the flag forgery, not a separate capability.
- **The bug is closed; its *artifacts* are forever.** Apps installed before 17.0.1 persist and keep running across updates, so TrollStore devices remain abundant in the field and will be for years. The skill of recognizing a TrollStore install does not expire with the bug — don't deprioritize it as "old news."
- **`com.apple.private.*` is a family, not one key.** There are thousands of private entitlements; your detector should match the *prefix* (plus `platform-application` and `task_for_pid-allow`), not an exact key. A grep for `com\.apple\.private` on a third-party bundle's entitlements is the right test, not a lookup of a single name.
- **The engine and the ignition are different bugs.** Installing TrollStore needed a *separate* bootstrap primitive (an `installd` quirk on 14–15.6.1, a one-shot sideload later); the CoreTrust flaw only makes the *result* permanent and entitled. A patch to either the bootstrap path or CoreTrust changes what's possible — don't model TrollStore as one monolithic exploit.

## Key takeaways

- **CoreTrust is the in-kernel "is the signer really Apple?" gate**; its job is to set a **policy flag** (App Store / developer / platform / untrusted) that AMFI then trusts. The **App Store flag** authorizes a binary to carry its own arbitrary entitlements with no provisioning profile — so forging that flag is the whole game.
- TrollStore is **not a jailbreak**: it's a **signature-validation forgery** that makes CoreTrust set the App Store flag on a binary Apple never signed, yielding **permanent, non-expiring, unsandboxed, root-helper-capable** installs — but it never touches the kernel, SEP, or Data Protection.
- There are **two** public CoreTrust bugs of this class: the **Root Certificate Validation** flaw (CVE-2022-26766, Linus Henze, TrollStore 1.x — CoreTrust never checked the chain rooted in Apple) and the **Multiple Signer Validation** flaw (TrollStore 2.x — CoreTrust used one signer's certs for the *verdict* and another's Code Directory for the *match*).
- It is **device-independent** (arm64 *and* arm64e, A8–A17/M1–M2) because it's a code-signing bug, **orthogonal to the checkm8/usbliter8 BootROM boundary**.
- **Supported window: iOS 14.0 beta 2 – 16.6.1, the 16.7 RC, and 17.0; closed at 17.0.1; no iOS 18/26 support** and none expected.
- **Forensically, TrollStore-installed apps are a distinct provenance category** that *looks* normal in the install databases; the tells are **no `embedded.mobileprovision`**, an **anomalous CMS** (multiple signers / App Store OID over a non-Apple root), and **impossible entitlements** — plus the TrollStore app and its persistence helper. The conjunction is conclusive; current OS proves capability *now*, not install *history*.
- The bug class is the cleanest proof that **"signature matches the binary" and "signer chains to Apple" are separable checks** — answer the second explicitly, never infer it from launch.
- The **engine** (the CoreTrust flaw → permanent, entitled result) and the **ignition** (an `installd`/sideload bootstrap → writing the forged bundle) are *separate* primitives; don't model TrollStore as one monolithic exploit.
- A future TrollStore would need a **third public CoreTrust validation flaw** specifically — *not* a kernel jailbreak, which wouldn't help, since TrollStore never needed kernel R/W. That, plus a hardened bootstrap path and the modern mitigation ladder, is why the honest answer is **frozen ≤ 17.0**, not "coming soon."

## Terms introduced

| Term | Definition |
|---|---|
| TrollStore | A jailed (non-jailbreak) iOS app installer that exploited the CoreTrust bug class to install IPAs **permanently** with **arbitrary entitlements** and **root helpers**; supported iOS 14.0–17.0, closed at 17.0.1. Maintained by opa334. |
| CoreTrust | The in-kernel certificate validator that classifies a code signature (Apple/App Store/developer/untrusted) and sets the **policy flag** AMFI trusts; introduced ~iOS 12 to stop the fake-signing jailbreak trick. |
| App Store policy flag | The CoreTrust classification that tells AMFI a binary is App-Store-signed and may therefore carry its **own arbitrary entitlements without a provisioning profile**. Forging it is the core of the TrollStore exploit. |
| Root Certificate Validation Vulnerability | CVE-2022-26766 (Linus Henze): CoreTrust set the App Store flag from the **leaf's** App Store OID without verifying the chain **rooted in Apple** — TrollStore 1.x's engine. |
| Multiple Signer Validation Vulnerability | The flaw where CoreTrust used **signer[0]'s certs** to set the App Store flag but a **later signer's Code Directory** to validate the bytes, letting a genuine Apple signer + an arbitrary signer coexist — TrollStore 2.x's engine. |
| Fake-signing | Ad-hoc/`ldid`-signing a binary (valid Code Directory, no real issuer) and relying on a downstream bypass (subverted amfid historically; CoreTrust forgery for TrollStore) to make it run. |
| Persistence helper | TrollStore's mechanism to survive icon-cache rebuilds: it replaces a **stock system app** (which stays "System"-registered) and uses it to re-register TrollStore apps back to System state. |
| `spawnRoot` / root helper | TrollStore's primitive (in `TSUtil.m`) to `posix_spawn` a helper binary **as root** from an unsandboxed app — userspace root, *not* kernel compromise. |
| Install provenance | The origin category of an installed app (App Store / TestFlight / enterprise / developer sideload / TrollStore / jailbreak), determined from signature, profile, and entitlements — a core forensic attribution. |
| Permasigning | Permanently signing an app so it never expires and carries arbitrary entitlements, via the CoreTrust forgery — the property that distinguishes a TrollStore install from a 7-day free sideload; the same trick reached Apple Watch and tvOS. |

## Further reading

- **The Apple Wiki** (theapplewiki.com) — *CoreTrust*, *CoreTrust Root Certificate Validation Vulnerability*, *CoreTrust Multiple Signer Validation Vulnerability*, and *TrollStore* (the authoritative version-support table). Cite the live pages.
- **opa334 / TrollStore** (github.com/opa334/TrollStore) — the `README.md` is the primary source on the bug, the persistence helper, root helpers, and the exact supported-version list; `TSUtil.m` for `spawnRoot`.
- **Linus Henze** — the CVE-2022-26766 discoverer; **"Get root on macOS 12.3.1: PoCs for Linus Henze's CoreTrust and DriverKit bugs"** (worthdoingbadly.com) for the cross-platform mechanics of the root-cert flaw.
- **Alfie CG** (alfiecg.uk) — *"An in-depth look at the code-signing process: ad-hoc signing"* and *"Getting untethered code execution on iOS 14.8"* — the clearest write-ups of fake-signing and the CoreTrust-to-code-exec chain.
- **Apple Platform Security guide** (security.apple.com) — "Code signing," "Mandatory code signing," and the trust-model sections; **Apple TN3125: Inside Code Signing** for the SuperBlob/CMS structure CoreTrust parses.
- **Jonathan Levin**, *MacOS and iOS Internals* vols I & III + newosxbook.com — AMFI, CoreTrust, the trust cache, and `jtool2 --sig` internals.
- **`ldid`, `codesign(1)`, `security cms`, `ipsw macho info --sig`, `jtool2 --sig`** — the exact tools for forging and detecting the signature artifacts in this lesson.
- **OWASP MASTG** (mas.owasp.org) — the iOS code-signing and "reverse engineering / tampering" chapters, for the app-security-testing framing of signature and entitlement inspection.
- **mvt** (Mobile Verification Toolkit, github.com/mvt-project/mvt) — for the at-scale detection mindset: programmatic checks over a logical/full-filesystem acquisition for installed-app and signing anomalies that complement the manual triage here.
- **iDownloadBlog**, *"Developer shows off perma-signed apps on Apple Watch using same CoreTrust bug as TrollStore"* (2024) — evidence the bug class reached beyond iPhone.

---
*Related lessons: [[code-signing-amfi-entitlements]] | [[the-jailbreak-landscape-2026]] | [[the-code-signature-blob-and-entitlements-on-ios]] | [[fairplay-encryption-and-decrypting-app-store-apps]] | [[dynamic-analysis-with-frida]] | [[bfu-vs-afu-and-data-protection-classes]] | [[app-sandbox-and-filesystem-layout]] | [[distribution-testflight-appstore-enterprise]]*
