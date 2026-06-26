---
title: "SEP & SEPOS deep dive"
part: "03 — Security Architecture"
lesson: 01
est_time: "50 min read + 20 min labs"
prerequisites: [secure-enclave-hardware, the-ios-security-model]
tags: [ios, sep, sepos, secure-enclave, keystore]
last_reviewed: 2026-06-26
---

# SEP & SEPOS deep dive

> **In one sentence:** Inside the Secure Enclave runs a real, Apple-customized L4 microkernel — sepOS — whose handful of isolated apps (the `sks` keystore, `sbio` biometrics, `sse` secure element, `scrd` credentials, the xART/anti-replay manager) answer the Application Processor's requests over a hardware mailbox and are the *only* code anywhere that actually wraps, unwraps, and derives your Data Protection keys — which is exactly why owning XNU (a jailbreak) does not own the keys.

## Why this matters

You finished [[secure-enclave-hardware]] knowing the *silicon*: the isolated SEP core, the Memory Protection Engine, the fused UID, the off-die Secure Storage Component. That lesson deliberately stopped at the hardware. This one is the **software/firmware** that runs on that silicon — and it is where the forensically decisive behavior actually lives. The hardware can keep the UID unreadable, but it is **sepOS** that decides which class keys to unwrap in which lock state, that loads and validates the keybag, that runs the passcode-attempt protocol against the Secure Storage Component, and that hands the AP a *yes/no* on a Face ID match.

For an examiner, "can a jailbreak get me the keys?" is the question this lesson answers, and the answer is a flat **no, not by itself** — and you need to know *why* at the level of the request/reply protocol, not as a slogan. A jailbreak is AP-kernel code execution. sepOS runs on a different core, in different memory, behind a mailbox that only carries *requests*, never secrets. The keys stay sealed across that wall. Internalize the software model here and you will correctly predict, for any acquisition scenario, exactly what a kernel-owned attacker can and cannot reach — which is the entire game in Part 07.

For the **builder and reverse-engineer** in you, the same model pays off from the other side. Every time you call a keychain API with `kSecAttrAccessibleWhenUnlocked`, declare a `.biometryCurrentSet` access control, or mint a `SecureEnclave.P256` key in CryptoKit, you are emitting an `aks_*`/`sks` request whose behavior is governed by exactly the protocol below — and when you later reverse an app's keychain usage ([[keychain-on-ios]]) or a DRM scheme, knowing *where the trust boundary actually is* tells you what is worth attacking on the AP and what is hopeless to chase into the SEP. The mailbox contract is the line between "reachable with a Frida hook" and "sealed in silicon," and you will spend Part 11 living on exactly that line.

## Concepts

### sepOS is a real operating system, not "firmware"

The word "firmware" undersells it. The SEP core boots **sepOS** (Secure Enclave Processor OS): a complete, if tiny, operating system with a microkernel, drivers, services, and userspace *apps* — Apple's own words, from the Platform Security guide, are that the SEP *"runs an Apple-customized version of the L4 microkernel."* The reverse-engineering lineage (Mandt & Solnik, Black Hat 2016 — see *Further reading*) traced that microkernel specifically to **Darbat**, an old academic Darwin-on-L4 port, so the design instincts are recognizably Mach-ish: small privileged kernel, capability-style IPC, everything else as separated tasks.

The L4 choice is the whole architectural point. L4 microkernels keep almost nothing in the privileged kernel — just scheduling, memory, and IPC — and push every *service* into mutually-isolated userspace tasks that can only talk through tightly-typed message passing. So a bug in the biometric matcher cannot directly read the keystore's memory; a bug in Apple Pay cannot reach the credential manager. This is **defense-in-depth inside an already-isolated coprocessor** — a second isolation boundary nested inside the first.

```
        Application Processor (AP)                 Secure Enclave (SEP core)
   ┌──────────────────────────────────┐      ┌────────────────────────────────────┐
   │  XNU kernel (untrusted from the   │      │            sepOS                    │
   │  SEP's point of view, even when    │      │  ┌──────────────────────────────┐  │
   │  jailbroken)                       │      │  │  L4 microkernel (Darbat-      │  │
   │                                    │      │  │  derived): sched, vm, IPC     │  │
   │  AppleSEPManager  ── owns the      │      │  └──────────────────────────────┘  │
   │     mailbox / IOP nub              │      │   isolated L4 tasks (the "apps"):   │
   │  AppleKeyStore / AppleSEPKeyStore  │ ───► │   ┌─────┐┌──────┐┌─────┐┌──────┐    │
   │     (the AP-side keystore proxy;   │ mbox │   │ sks ││ sbio ││ sse ││ scrd │    │
   │      exposes the aks_* API)        │ ◄─── │   │ key ││ bio  ││ s.e.││ cred │    │
   │                                    │      │   └─────┘└──────┘└─────┘└──────┘    │
   │  callers: securityd, biometricd,   │      │   ┌──────────────┐┌─────────────┐   │
   │  apsd, your app via keychain APIs  │      │   │ xART manager ││ control/boot │   │
   └──────────────────────────────────┘      │   └──────────────┘└─────────────┘   │
                                              └────────────────────────────────────┘
       requests cross the wall  ─────────────────►  secrets never do
```

> 🖥️ **macOS contrast:** This is *the same OS* on your Apple Silicon Mac. The Mac's SEP runs sepOS with the same L4 lineage, the same `sks` keystore app, the same mailbox driver (`AppleSEPManager`). What you learned about it for FileVault transfers almost verbatim. The one mobile difference that reorganizes everything downstream: on iOS, sepOS additionally **derives and gates the per-file Data Protection class keys** (`NSFileProtectionComplete`, `…CompleteUntilFirstUserAuthentication`, etc.), not just one volume key behind the login password. That single added responsibility is why the SEP sits at the center of *every* iOS acquisition question, where on the Mac it mostly guards one key.

### Why an L4 microkernel — the isolation guarantee

The L4 choice is not incidental, and it is worth stating precisely because it bounds what a *single bug* in the SEP can do. A monolithic OS (like XNU on the AP) puts drivers, services, and policy in one privileged address space, so one memory-corruption bug there is, in the worst case, total. L4's discipline is the opposite: the privileged kernel does almost nothing — scheduling, address spaces, and synchronous IPC — and every *service* is an unprivileged task that can touch only the memory and the capabilities it was explicitly granted. The **trusted computing base** of sepOS is therefore tiny, and the apps are mutually quarantined.

The consequence for an attacker is concrete: compromising `sbio` (biometrics) does **not** grant access to `sks`'s keybag memory, because they are separate L4 tasks with no shared mapping; reaching either requires a *fresh* bug, and reaching the keys requires defeating `sks` specifically. This is the design lineage of seL4 — the famously machine-verified member of the L4 family — though note carefully that Apple's sepOS is an L4-*embedded*/Darbat-derived kernel, **not seL4 itself**: you should credit it with the *architecture* of strong task isolation, not with seL4's formal proof. (The PKA's *arithmetic* is formally verified on A13+, per [[secure-enclave-hardware]]; the sepOS kernel is not — don't conflate the two.) The durable takeaway: the SEP is isolated from the AP by hardware, and the SEP's *own* services are isolated from each other by the microkernel — defense in depth, two layers down.

### The sepOS app set (the L4 task map)

sepOS is best understood by its tasks. The names are stable across years of research; their exact responsibilities and endpoint numbers drift per SoC and per OS, so treat the numbers below as *illustrative*, the *roles* as durable.

| sepOS app | Role | Notes |
|---|---|---|
| **`sks`** (SEP KeyStore) | The vault. Performs the actual **wrap/unwrap of class keys**, holds the device keybag, tracks lock state, and runs the Data Protection key hierarchy. | The single most important app for forensics — the thing that decides what is decryptable. FIPS/CC-certified as the "Apple SEP Secure Key Store Cryptographic Module." |
| **`sbio`** (SEP Biometrics) | Face ID / Touch ID **template storage and matching**. Runs the match against templates it alone holds; drives the Secure Neural Engine on Face ID devices. | Returns only a *match / no-match* decision to the AP. Templates never leave the SEP. |
| **`sse`** (SEP Secure Element manager) | Mediates the **embedded Secure Element** used by Apple Pay / contactless; gates SE transactions on a biometric/passcode result from `sbio`/`sks`. | The "wallet" path; distinct from the keystore. |
| **`scrd`** (SEP Credential manager) | Manages credential material and protocols layered above the keystore. | |
| **xART manager** | Manages **xART** (eXtended Anti-Replay Token), "gigalockers," and keybag anti-rollback state against the Secure Storage Component. | Older A6/A7-era SoCs used a predecessor named **ARTM** (Anti-Replay Token Manager). |
| **control / boot** | The bootstrap and discovery endpoint: brings sepOS up from the loaded Image4, answers pings, manages the SEP nonce. | Endpoint `255` on iOS 9, `0xFE` ("Boot254") on Apple Silicon; not a key-handling app. |

> 🔬 **Forensics note:** When you reason about an acquisition, you are almost always reasoning about **`sks`**. "Is this file's class key available right now?" is a question about what `sks` has unwrapped and is holding in SEP memory in the current lock state. "Can biometrics unlock it?" is a question about whether `sbio` will return a match *and* whether `sks` will release the corresponding key. Map every "can I read X?" to "has `sks` unwrapped X's class key, and will it, given this device's state?" — that is the correct mental model, and it is a property of sepOS software state, not of the file on disk.

### The AP↔SEP request/reply protocol (the software view of the mailbox)

[[secure-enclave-hardware]] described the mailbox as *hardware* — inbox/outbox registers, a doorbell IRQ, shared buffers. Here is the **software protocol** that rides on it. Open-source reverse engineering (the Asahi Linux SEP driver, which talks to this exact interface to boot the Mac's SEP under Linux) documents the message as a **64-bit word** with typed fields:

```
 63                                   32 31      25 24            16 15       8 7         0
┌────────────────────────────────────────┬──────────┬────────────────┬──────────┬──────────┐
│            data  (32 bits)              │  params  │   type/opcode  │   tag    │ endpoint │
│  a pointer (into an OOL buffer) OR an   │  (often  │ (the requested │ (request │  (which  │
│        inline configuration value       │  target  │    action)     │ correl-  │  sepOS   │
│                                          │ endpoint)│                │  ation)  │   app)   │
└────────────────────────────────────────┴──────────┴────────────────┴──────────┴──────────┘
```

The **endpoint** byte selects the sepOS app; the **type/opcode** selects the operation; the **tag** correlates a reply to its request; the upper 32 bits carry either a small inline value or a pointer into an **OOL ("out-of-line") shared buffer** for bulk payloads. (`AppleSEPManager` on the AP allocates those OOL buffers; the term is right there in the driver.)

Endpoint numbering is *not* stable — it is assigned per SoC and per OS. Two snapshots, a decade apart, make the point:

| Era / source | `sks` keystore | `sbio` | `sse` | `scrd` | xART mgr | control/boot |
|---|---|---|---|---|---|---|
| iOS 9, A-series (Mandt 2016) | endpoint **7** | 8 | 12 | 10 | — | **255** (bootstrap) |
| Apple Silicon Mac, ~2024 (Asahi, T8112) | endpoint **0x12** | (SNE path) | — | — | **0x13** (xART) | **0xFE** (Boot254), `0xFD` debug |

Do not hard-code these. The durable facts are: (1) there is one endpoint per app; (2) the keystore is its own endpoint; (3) there is a dedicated **boot/control** endpoint and a **debug/discovery** endpoint that returns the live endpoint list; (4) the message is typed `endpoint|tag|opcode|params|data`. The control endpoint typically acks a successful op with a reply of type `0x1`.

The security invariant of the whole protocol, restated at the software level: **the request crosses the wall; the secret never does.** The AP sends `sks` a request — "unwrap class key 3 for this file" — by writing a typed message and ringing the doorbell. `sks` copies the request out of the shared OOL buffer into its own protected memory, does the unwrap *inside the SEP*, and writes back only a *result* — a usable-but-still-controlled key handle, or a wrapped blob, or `match=true`. The plaintext UID, the keybag master key, the passcode entropy: none of those is ever placed in a buffer the AP can read. A jailbroken AP can send any request it likes; it cannot make `sks` *answer with a secret it is not supposed to release in the current lock state*.

> 🖥️ **macOS contrast:** On the Mac you can watch the AP *side* of this conversation directly. `AppleSEPManager`, `AppleKeyStore`, and `AppleSEPKeyStore` are all visible in `ioreg`, and the keystore traffic shows up in the unified log under the `AppleKeyStore`/`aks` subsystems (Lab 3). You see request/result events — never key bytes — which is precisely the shape of the wall. The Mac models the *protocol* faithfully; what it doesn't model is the iOS *consequence* (per-file class keys, Secure Storage attempt metering).

### The request lifecycle: one unwrap, end to end

Trace a single, concrete operation — opening an `NSFileProtectionComplete` file while the device is unlocked — all the way across the wall, because the *shape* of this round trip is the shape of every SEP operation:

```
1. App calls open()/read(); the file's metadata names its protection class (A)
2. The kernel's Data Protection layer needs the class-A key → aks_unwrap_key()
3. libAppleKeyStore → AppleSEPKeyStore (kext): builds a mailbox message
      endpoint = sks, opcode = UNWRAP, tag = N,
      data = pointer to an OOL buffer holding the wrapped key blob
4. AppleSEPManager writes the message + rings the SEP doorbell
5. sepOS kernel delivers the message to the sks task (L4 IPC)
6. sks copies the wrapped blob OUT of the OOL buffer into SEP-private memory,
      checks: is the keybag unlocked for class A in the current lock state?
        ├─ yes → unwrap using the class-A key (itself derived under the keybag
        │         master, unwrapped at passcode entry) → produce a key HANDLE
        └─ no  → return error (locked); the AP gets nothing
7. sks writes only the result (handle, or error) back to the OOL buffer,
      replies with tag = N
8. AppleSEPKeyStore returns the handle to the kernel; the AES path decrypts
      the file with a key the AP can USE but whose raw class bytes never left
```

Two properties to carry forward. First, **step 6 is the entire ballgame**: the same request, byte-for-byte, returns the handle when unlocked and an error when locked — the *decision* lives in `sks`, keyed off lock state, not in the caller. A jailbroken AP reaches step 5 trivially; it cannot change the answer at step 6. Second, what crosses back at step 7 is a *handle the AP can use for the operation*, not necessarily raw class-key bytes — and for the most sensitive operations (`.biometryCurrentSet` keychain items, OS-bound keys) the usable material never leaves the SEP at all; the SEP performs the crypto and returns only the *output*.

> 🔬 **Forensics note:** This is why "dump the AP's memory and grep for keys" yields exactly the keys `sks` released for the lock state at capture, and not one byte more. In an **AFU** capture you find handles/keys for first-unlock (class-C) and always-available (class-D) data — `sks` unwrapped them once and keeps them while unlocked-since-boot; you do **not** find class-A keys if the screen was locked at seizure, because step 6 refused them. The memory image is a snapshot of `sks`'s *releases*, never of `sks`'s *vault*.

### The AP-side keystore: `AppleKeyStore`, `AppleSEPKeyStore`, and the `aks_*` API

On the AP, no application talks to the SEP directly. The path is layered, and knowing the layers tells you exactly where the attack surface is — and where it *isn't*:

```
 your app: SecItemAdd / SecItemCopyMatching, kSecAttrAccessible…   (keychain)
        │                  Data Protection: open()/read() on a protected file
        ▼
 securityd / securitykeychaind            biometricd / coreauthd     apsd, backupd, …
        │   userspace clients
        ▼
 libAppleKeyStore  ───  the aks_* C API  (aks_unwrap_key, aks_load_bag,
        │                                  aks_get_lock_state, aks_ref_key …)
        ▼
 AppleKeyStore / AppleSEPKeyStore  (KEXT, IOKit)   ← AppleKeyStoreUserClient
        │   builds the typed mailbox message, manages OOL buffers
        ▼
 AppleSEPManager  →  hardware mailbox  →  sepOS  `sks`
```

`AppleKeyStore` (and on modern devices `AppleSEPKeyStore`, the SEP-backed variant) is a **kernel extension** — a *proxy*. It marshals userspace requests into mailbox messages and shuttles them to `sks`. The `aks_*` functions in `libAppleKeyStore` are the userspace face of it: `aks_load_bag` (load a keybag), `aks_unwrap_key` (ask the SEP to unwrap a class key), `aks_get_lock_state`, `aks_ref_key` (get a handle without exposing material). On iOS the private `MobileKeyBag` framework and the `keystorectl` tool sit on top of these.

The forensically crucial distinction: **`AppleKeyStore` is on the AP; `sks` is in the SEP.** A bug in the AP-side kext gets you *AP kernel* — and AP-side keystore bugs are a recurring kernel attack surface. In the 2026 cycle, researchers landed an `AppleSEPKeyStore` use-after-free — **CVE-2026-20637**, an `IOCommandGate`/`IOServiceClose` race in the keystore user client (threads hammering `IOConnectCallMethod` selectors against a concurrent `IOServiceClose`, so the command gate is touched after it is freed), which Apple fixed in **iOS/iPadOS 26.3** (the bug is listed under "AppleKeyStore" in Apple's 26.3 security advisory; the public PoC repo labels it "26.4," but Apple's advisory governs the patch point). It is a real, panic-grade kernel bug, and it typifies a recurring class of AP-side keystore user-client UAFs. **It does not touch sepOS.** It corrupts the *proxy*, not the *vault*. That is the entire lesson in one example: the keystore the AP exposes is attackable; the keystore that holds the keys is on the other side of the mailbox, and a UAF in the proxy does not reach across it.

> 🔬 **Forensics note:** This layering is why a full-file-system acquisition that relies on an AP kernel exploit ([[full-file-system-acquisition]]) recovers the files whose class keys `sks` has *already* released into AP-reachable state, and nothing else. The exploit gives you the proxy and the AP's memory; it gives you the keys `sks` chose to hand up for the current lock state — class-D always, class-C after first unlock — never the UID, never the keybag master, never a class-A key while locked. The lock state at seizure decides the loot, and the lock state is a fact about sepOS, not about your exploit's power.

### What sepOS actually does for the AP (the service catalog)

Pulling the apps and the protocol together, here is the full set of services the AP can request — and, for each, the secret that stays behind the wall:

| Service (requesting app/daemon) | sepOS app | What sepOS does inside the wall | What the AP gets back |
|---|---|---|---|
| **Wrap / unwrap a class key** (keychain, file Data Protection) | `sks` | Derives/unwraps the per-class key from the keybag, gated by lock state | A controlled key *handle* or wrapped blob — never the class key plaintext for a locked class |
| **Verify a passcode attempt** | `sks` + xART | Tangles the candidate with the UID in the AES engine; runs the **counter-lockbox protocol** against the Secure Storage Component | success/fail; on success, the keybag unlocks inside the SEP |
| **Match a biometric** | `sbio` | Matches the live template against stored templates (Secure Neural Engine on Face ID) | `match` / `no-match` — never the template |
| **Release a biometric-gated key** | `sbio` → `sks` | On a fresh match, authorizes `sks` to use a `.biometryCurrentSet` key | use of the key for one operation; no key material |
| **Secure Element transaction** (Apple Pay) | `sse` | Gates the SE on a `sbio`/`sks` auth result | transaction proceeds; payment keys stay in the SE/SEP |
| **Generate / sign with an OS-bound key** | `sks` (PKA) | Uses a UID-+-sepOS-hash-derived PKA key | a signature / wrapped key — bound to *this* device-and-OS |
| **Boot & attest sepOS** | control/boot | Validates the loaded Image4, (A13+) measures it into the boot hash | a trust anchor for OS-bound keys; the SEP nonce |

Every row has the same shape: a *request* in, a *result or a decision* out, the secret never on the bus. This table is the SEP's entire externally-visible contract. Anything not on it — "read me the UID," "dump the keybag master," "give me a class-A key while the device is locked" — is not a request sepOS will honor, because the protocol has no opcode for it and the apps have no code path to it.

> ⚖️ **Authorization:** Brief stakeholders on this contract honestly. The seductive ask — "we got a kernel exploit / a jailbreak, so we have everything" — is wrong at the protocol level, and overpromising it in a report or affidavit is a credibility risk. The accurate statement is: AP compromise yields AP memory and whatever class keys `sks` had already released for the lock state at seizure; it does not yield the UID, the keybag master, biometric templates, or any key sealed to a class the SEP has not unlocked. Scope your representations to the service catalog above and to the device's lock state, and document the basis.

### What sepOS does *not* do (bounding the contract)

It is as important to know the SEP's non-capabilities, because attackers and over-eager vendors both blur them. sepOS is **not a general Trusted Execution Environment** in the Arm TrustZone / GlobalPlatform sense: you cannot load a third-party "trusted app" into it, there is no developer SDK for running your code inside the SEP, and Apple ships a *fixed* set of apps (`sks`/`sbio`/`sse`/`scrd`/xART). When a CryptoKit `SecureEnclave.P256` key "runs in the Secure Enclave," your code does **not** run there — the *key operation* runs in `sks`/the PKA; your app stays on the AP and merely holds an opaque handle. This is a deliberate attack-surface decision: no third-party code in the SEP means no third-party bug class in the SEP.

sepOS also does **not** see most of the system: it does not mount the filesystem, does not have a network stack, does not parse rich untrusted formats, and does not run a shell. Its entire external interface is the typed mailbox and a small set of opcodes per app. That minimal interface is *why* the public defeats have been so hard-won — there is very little to attack, and what there is must be reached through the AP-side proxy and the narrow message protocol. The contract in the service catalog above is, quite literally, the whole of what you can ask the SEP to do; everything else is out of scope by construction.

### The keybags `sks` holds (and why they decide acquisition)

`sks` does not manage one key — it manages **keybags**, and the *type* of keybag decides who can unlock what. Apple defines five, all maintained inside the SEP:

| Keybag | Holds | Unlock factor | Acquisition relevance |
|---|---|---|---|
| **User keybag** | Wrapped class keys for normal device operation | The passcode (tangled with the UID) | The one that matters at seizure — behind the passcode; gates class-A/B/C |
| **Device keybag** | Class keys for *device-bound* data not tied to a user passcode | Device/UID only | Backs data that must survive without the passcode (some system state) |
| **Backup keybag** | Class keys re-wrapped for an encrypted iTunes/Finder backup | The backup password (PBKDF2) | Why an *encrypted* local backup is brute-forceable **off-device** — password-wrapped, not UID-bound ([[the-itunes-finder-backup-format]]) |
| **Escrow keybag** | Class keys for a trusted host / MDM to unlock without the passcode | An escrow record held by the paired host/MDM | The basis of "trust this computer"; an escrow record on a seized laptop can unlock a paired phone |
| **iCloud Backup keybag** | Class keys re-wrapped for iCloud Backup | iCloud key hierarchy (asymmetric) | What ADP re-keys end-to-end, breaking cloud acquisition ([[icloud-acquisition-and-advanced-data-protection]]) |

The load-bearing line is the **backup keybag**: unlike the user keybag, it is wrapped with a key derived from the *backup password*, **not** the fused UID — which is precisely why an encrypted iTunes/Finder backup is the one Data-Protection artifact you *can* attack off-device on a GPU cluster ([[decrypting-backups-and-images]]). The on-device user keybag is UID-bound and unattackable off-device; the backup keybag is password-bound and portable. Same `sks`, two completely different feasibility stories — and confusing them is a classic acquisition-planning error.

> 🔬 **Forensics note:** When triaging, ask *which keybag* protects the data you want. On-device class keys → user keybag → UID-bound → on-device-only, lock-state-gated. Encrypted backup → backup keybag → password-bound → off-device attack viable. Paired-host trust → escrow keybag → hunt for the escrow record on the seized computer. iCloud → iCloud Backup keybag → check for ADP. The keybag taxonomy *is* the acquisition decision tree ([[the-acquisition-taxonomy]]).

### Passcode verification, in software

[[secure-enclave-hardware]] covered the Secure Storage Component's counter lockbox. Here is the **software** flow `sks` runs on top of it — because the escalating delays and "Erase after 10 attempts" are sepOS *policy* sitting above the hardware metering:

```
passcode attempt (entered on the AP, never trusted by the SEP):
  1. AP sends the candidate passcode entropy to sks (mailbox)
  2. sks tangles candidate + UID in the AES engine (the slow ~80ms KDF)
  3. sks asks the Secure Storage Component to verify (authenticated protocol):
       ├─ the component INCREMENTS its hardware counter FIRST
       ├─ compares the verifier
       ├─ match → returns the lockbox entropy, resets counter to 0
       └─ miss  → returns failure;  counter > max → component ERASES lockbox
  4. on success, sks unwraps the USER KEYBAG master → class keys available
  5. sks applies SOFTWARE policy: escalating delay (1→5→15→60 min …) and,
       if configured, signals "erase all content" past the threshold
```

The split to remember: **step 3 is hardware** (un-resettable, self-erasing, on the separate IC); **steps 2/4/5 are sepOS software**. The escalating delays are *policy* `sks` enforces; the un-bypassable *counting* underneath is the Secure Storage Component. An attacker who patched the delay policy (sepOS code-exec) still hits the hardware counter at step 3 — which is why even legacy blackbird SEP code-exec does **not** become unlimited guessing on a device that *has* a Secure Storage Component, and why the checkm8/A8–A11 devices (which have **none**) were the ones susceptible to GrayKey-era attempt-racing. (Precision, per Apple's Platform Security guide: the dedicated Secure Storage Component is paired with the Secure Enclave from **A12** onward; the specific *counter-lockbox* drawn above — a 128-bit salt, a 128-bit passcode verifier, an 8-bit counter, and an 8-bit max-attempt value, which the component auto-erases once the counter exceeds the max — is the **2nd-generation** Secure Storage Component, in devices first released **Fall 2020 or later**. Earlier A12/A13 devices have the 1st-generation component.) (Full schedule + BFU/AFU interaction: [[passcode-bfu-afu-and-inactivity]].)

### How sepOS boots: SEPROM, the `sepi` payload, and personalization

sepOS does not live in the SEP Boot ROM — only the immutable **SEPROM** does (the silicon root from [[secure-enclave-hardware]]). sepOS itself ships as an **Image4 payload** in the IPSW, alongside the rest of the firmware, and is loaded *by the AP* at every boot. The boot dance:

```
1. iBoot (AP) reads  Firmware/all_flash/sep-firmware.<board>.RELEASE.im4p
      └─ an Image4 payload (IM4P) whose four-cc tag is  'sepi'  (the SEP image)
2. iBoot copies the sepi payload into a DRAM region and rings the SEP's
      control/boot endpoint  (Boot254 / endpoint 255):  "boot this IMG4"
3. SEPROM (immutable SEP boot ROM) parses the Image4 container and:
      ├─ verifies the IM4M manifest signature against the Apple Root CA
      │    public key embedded in SEPROM   (RSA, hardcoded cert)
      ├─ checks personalization: the manifest's ECID == this chip, board id,
      │    and the SEP anti-rollback nonce  (so an old signed sepOS won't load)
      └─ on A12+, decrypts the payload body with a GID-derived key
           (the decryption key is itself a SEP-held secret — that is why
            you cannot statically decrypt a modern sepi)
4. (A13+) the Boot Monitor measures the loaded sepOS into the boot hash,
      sets SCIP execute permissions, and feeds the hash to the PKA for
      OS-bound keys   (detailed in secure-enclave-hardware)
5. sepOS kernel starts, launches its apps (sks, sbio, sse, scrd, xART);
      sks loads the device keybag.  TZ0 (the SEP's protected DRAM) is locked.
```

Two parts of this are the chain-of-trust crux. First, **the `sepi` Image4 is personalized per device** — its IM4M manifest is the same SHSH the device requested at restore, naming *this* ECID and board, so a sepi blob for one phone will not boot on another ([[image4-personalization-shsh]]). Second, the **SEP anti-rollback nonce**: the manifest is bound to a SEP-side nonce, so a *validly-signed but old* sepOS (one with a known bug) cannot be replayed onto a current device. The combination — per-device signature, current-nonce binding, GID-encrypted body on A12+, and (A13+) a measured boot hash that changes the OS-bound keys if anything differs — is what makes the sepOS you are running provably the one Apple shipped for this device, this OS, right now.

> 🔬 **Forensics note:** This is the firmware-level reason a **downgrade attack on sepOS is the holy grail and is foreclosed on modern devices**. If you could boot an *older, buggy* sepOS, you might exploit a patched flaw to weaken the keystore. The SEP nonce + per-device personalization block exactly that on A12+ — there is no signed-and-current path to old sepOS. The only devices where this fell was the checkm8/blackbird era (next section), where a SEPROM bug let attackers *set the SEP nonce themselves* and load unsigned sepOS. On A14+ there is no public SEPROM exploit at all, so even that door is shut.

### Updating sepOS: lockstep with iOS, never alone

sepOS is **not** independently updatable — there is no "SEP firmware update" the user or an attacker can apply on its own. The `sepi` payload ships *inside the same IPSW* as iBoot, the kernelcache, and the rest, and is re-personalized at **restore/OTA** time: the device requests a new SHSH (IM4M) from Apple's TSS server, the manifest covers the new `sepi` digest **and the current SEP nonce**, and only then will SEPROM accept the new image. The on-device helper that drives the SEP side of restore is **`seputil`**. The security consequence is that sepOS and iOS advance *together* — you cannot mix a current iOS with an old, buggy sepOS, and you cannot quietly downgrade the SEP while leaving the AP current. (This lockstep is also why a patched sepOS bug is genuinely gone on updated devices: there is no path to re-introduce the vulnerable image without the TSS signing it against the live nonce, which Apple stops doing once the window closes — the same anti-rollback logic as the AP chain in [[image4-personalization-shsh]].)

> 🔬 **Forensics note:** When you record a device's iOS version, you have *also* recorded its sepOS version — they cannot diverge on a normally-restored device. That single version number tells you which published sepOS/keystore issues are patched and therefore whether any sepOS-level avenue (always a long shot) is even theoretically open. Note the exact build in your triage; it is a sepOS fact as much as an iOS one.

### The published SEP-research lineage (defensive, conceptual)

You should know this history not to reproduce it, but because it precisely delimits *what has ever been publicly defeated* — and therefore what a defensible report can and cannot claim. Every durable SEP defeat in the literature is **software** (sepOS/keystore logic) or **below the AP** (a SEPROM bug); none is "read the UID off the die," and none of the modern ones (A12+) hands over user keys.

- **Mandt & Solnik — "Demystifying the Secure Enclave Processor" (Black Hat US 2016).** The foundational reverse engineering: identified sepOS as L4/Darbat-derived, mapped the apps (`sks`/`sbio`/`sse`/`scrd`), and documented the mailbox endpoints and message format. Defensive value: it is the public map you are reading a 2026 distillation of.
- **xerub — SEP firmware decryption key (2017).** Published the GID-derived key that decrypts the **A7** (iPhone 5s) `sepi` image, letting researchers *read* sepOS for that generation. Critically: this decrypts the **firmware for study**; it does **not** extract any user's UID, keybag, or passcode. It is a microscope, not a skeleton key — and Apple's later GID-encryption + Boot Monitor changes make later generations far harder to image this way.
- **blackbird — Pangu, MOSEC 2020 (see next).** A **SEPROM** code-execution bug. The SEP analogue of checkm8.
- **AP-side keystore bugs (continuous, incl. 2026).** The `AppleKeyStore`/`AppleSEPKeyStore` user clients are a perennial *AP-kernel* attack surface (the 2026 `AppleSEPKeyStore` UAF, CVE-2026-20637, among them). These matter for jailbreaks and LPE — and they prove the boundary by *not* crossing it: they corrupt the proxy, sepOS is untouched.

The synthesis a forensicator carries: **there is no public, reliable path to extract keys from an A12+ SEP.** The research either reads old firmware, runs unsigned code on old SEPROMs, or corrupts the AP-side proxy. None reaches into a current `sks` and walks out with the keybag.

> ⚠️ **ADVANCED — blackbird and SEP downgrade (checkm8-era only):** **blackbird** (Pangu, 2020) is a **SEPROM** vulnerability affecting devices with **A8, A9, A10, and T2** SoCs (and variants) — **A11 and the iPhone 8/X are *not* affected, and A12+ has no public equivalent.** It is unpatchable for the same reason checkm8 is: the bug is in mask ROM. It cannot be triggered alone — you first need code execution on another core before **TZ0** (the SEP's protected-memory region) is locked, i.e. via an AP BootROM exploit like **checkm8** or an iBoot bug. What it buys you is the ability to **set the SEP nonce and load *unsigned* / downgraded sepOS** — defeating the anti-rollback that normally forecloses sepOS downgrade. (On A10/T2 it degrades to a *replay-only* primitive because the relevant key is randomized per boot, so you need valid SEP firmware each restart.) Understand what this does and does not give you: it is *SEP code execution and downgrade on legacy silicon*, the substrate for research and for chaining toward keystore attacks on those old devices — it is **not** a one-shot "dump the keys" button, and it is irrelevant to the A12+ devices that dominate modern casework. Do not attempt anything in this paragraph against evidence; it is here to bound feasibility, not as a procedure.

### Why the SEP is the acquisition wall — the synthesis

Now assemble the argument you will lean on for the rest of the forensics modules. A **jailbreak is XNU/AP compromise**. sepOS is a *different OS on a different core in different memory*, reachable only through a mailbox that carries typed requests. Therefore:

1. **A jailbroken AP can ask, but cannot take.** It can issue any `aks_*`/`sks` request, but `sks` answers from its own policy and lock state. The keystore is not a data structure in AP memory to be read; it is a service behind the wall.
2. **The keys for locked classes are not in AP memory to steal.** At BFU, `sks` has only unwrapped the class-D (UID-only) key; the passcode-derived keys do not *exist* in any reachable memory until the passcode is entered and `sks` re-derives them on this SEP. There is nothing for the kernel exploit to scrape.
3. **Downgrading sepOS to a weaker version is blocked** by per-device personalization + the SEP nonce (A12+), and even SEP code-exec on the legacy blackbird devices does not by itself hand over a current device's keys.
4. **The boot hash binds the keys to this exact sepOS** (A13+ OS-bound keys), so booting your own SEP code changes the derived keys and unwraps nothing sealed by the genuine OS.

```
        JAILBREAK (owns XNU / AP kernel)            SEPOS (untouched)
   ┌───────────────────────────────────┐     ┌──────────────────────────────┐
   │  arbitrary AP kernel R/W           │     │  sks holds: keybag master,    │
   │  can patch AMFI, spawn unsigned,   │     │  class keys (only those       │
   │  read every file whose class key   │ ──► │  unwrapped for current lock   │
   │  sks has ALREADY released          │ ✗   │  state), UID-derived keys     │
   │                                    │     │                              │
   │  CANNOT cross the mailbox to read   │     │  releases ONLY results,       │
   │  sks's memory or the UID            │     │  never secrets                │
   └───────────────────────────────────┘     └──────────────────────────────┘
            this is the acquisition wall  ───────────────┘
```

This is the precise, defensible reason a **BFU device holds even against a kernel-owned (jailbroken) attacker**: the attacker owns the AP completely and it does not matter, because the keys that protect the interesting data were never derived into AP-reachable memory, and the only thing that can derive them — `sks` running on the SEP, fed the passcode, metered by the Secure Storage Component — will not, absent the passcode. The wall is not a stronger lock on the same door; it is a *different door on a different building*, and the jailbreak only ever had keys to the first one.

### macOS vs iOS: the same sepOS, a different job

Because you met this SEP first on the Mac, fix the divergence so you don't carry a Mac assumption into an iPhone case (or vice-versa). The *software* is the same family — same L4-derived sepOS, same `sks`, same mailbox driver — but the **job** differs in three ways that change everything downstream:

| | Apple Silicon Mac | iPhone / iPad |
|---|---|---|
| What `sks` chiefly protects | Largely **one volume key** (FileVault), behind the login password | **Per-file Data Protection class keys** (A/B/C/D) behind the passcode |
| Attempt metering | No standalone Secure Storage Component on older Macs; SEP-internal | **Secure Storage Component** meters every passcode attempt, self-erases (the component is paired since **A12**; the auto-erasing *counter-lockbox* is the **Fall-2020 2nd-generation**) |
| Boot policy / ownership | **LocalPolicy** + owner roles (`bputil`), Sealed Key Protection ties the volume key to a measured boot ([[boot-chain-securerom-iboot]]) | Per-device `sepi` personalization + SEP nonce; OS-bound keys via the Boot Monitor hash |
| Partial-access granularity | Coarse — unlocked or not | **Fine, lock-state-dependent** — class-D always, class-C after first unlock, class-A only while unlocked |

The net for a forensicator: the iPhone gives you *more* partial access than the Mac (you can reach class-D/class-C data in states where a FileVault Mac gives you nothing) but a *harder wall* on the rest (the Secure Storage attempt limit the Mac lacks). The Mac's analogue of the iOS "downgrade-resistance" story is **Sealed Key Protection** — the volume key won't release if the measured boot doesn't match — which is the same *idea* the Boot Monitor's OS-bound keys implement on iOS. Same engine, same OS, deliberately different policy; reason from the policy, not from a half-remembered Mac reflex.

> 🖥️ **macOS contrast:** The one Mac-only escape hatch with no iPhone equivalent is the **owner/recovery** path: an Apple Silicon Mac's LocalPolicy supports owner roles and a recovery key, and a logged-in admin can change Secure Boot policy with `bputil`/`csrutil` from recoveryOS. iOS has no such on-device policy console — there is no "downgrade SEP policy" button, no recoveryOS shell, and the only sanctioned unlock factor is the passcode/biometric through `sks`. When an examiner asks "is there an admin override like on the Mac?", the answer for iOS is *no*, and that absence is itself a security property.

## Hands-on

There is no shell on the iPhone, and the iOS **Simulator has no SEP and no sepOS at all** (it is macOS frameworks on your Mac). So the faithful hands-on is: inspect the **AP-side keystore surface on your own Apple Silicon Mac** (same sepOS, same `sks`, same drivers), watch the **keystore↔SEP conversation in the unified log**, and dissect the **`sepi` payload statically** out of an IPSW. None needs an iPhone.

### Inspect the AP-side keystore drivers (host SEP)

```bash
# The mailbox owner (the IOP nub that carries every SEP message):
ioreg -rc AppleSEPManager

# The keystore proxy — the AP-side door to sks. Name varies by OS
# (AppleKeyStore on older, AppleSEPKeyStore on current Apple Silicon):
ioreg -l | grep -iE "AppleKeyStore|AppleSEPKeyStore|KeyStoreUserClient"
```

Described output (Apple Silicon Mac): you will see an `AppleSEPManager` nub matched at boot, and a keystore object (`AppleKeyStore`/`AppleSEPKeyStore`) with an `IOUserClientClass` of `AppleKeyStoreUserClient` — the IOKit user client that userspace `aks_*` calls land on. This is the *entire* AP-visible surface of the keystore: a proxy and a user client. There is, by design, no node here that exposes a class key, the keybag, or the UID — that opacity is the wall.

### Watch the keystore talk to sepOS (host SEP, unified log)

```bash
# Stream keystore / Data-Protection events as they cross to the SEP:
log stream --predicate 'subsystem == "com.apple.kernel.AppleKeyStore" OR subsystem CONTAINS[c] "aks"' \
           --level debug &
# Now lock and unlock the screen (forces class-key eviction + re-derivation
# through sks), then:
kill %1
```

Described result: you will see request/result events corresponding to keybag load, lock-state changes, and key unwrap/ref operations — the AP side of the mailbox conversation. You will **never** see key bytes. Tie each line back to an `aks_*` call and to the service catalog: the AP asked, `sks` answered with a decision or a handle, the secret stayed behind the wall. (This is the literal, observable shape of the acquisition wall, on hardware you own.)

### Pull and dissect the `sepi` payload from an IPSW (static, device-free)

`ipsw` (blacktop) reads the same Image4 firmware your device runs — `brew install blacktop/tap/ipsw`:

```bash
# Locate the SEP firmware payload and confirm its Image4 tag is 'sepi':
unzip -l UniversalMac_*.ipsw | grep -i sep
#   Firmware/all_flash/sep-firmware.<board>.RELEASE.im4p
ipsw img4 extract --img4 Firmware/all_flash/sep-firmware.*.RELEASE.im4p
ipsw img4 info     Firmware/all_flash/sep-firmware.*.RELEASE.im4p
#   IM4P  type: 'sepi'   (the SEP image)   compression: lzss/lzfse
#   ... PAYP (payload properties, since iOS 15) ...

# Inspect the personalization manifest (IM4M) — the SHSH that binds this
# sepi to ONE device (ECID + board) and the current SEP nonce:
ipsw img4 manifest info BuildManifest.plist 2>/dev/null | grep -iA2 sep
```

Described boundary: on **A12+** the `sepi` body is **GID-encrypted**, so you can confirm *that it exists, that it is Image4-wrapped, signed, per-device personalized, and (post-iOS 15) carries `PAYP` properties* — and you **cannot** decrypt or run it, because the decryption key is a SEP-held GID-derived secret. That boundary *is* the chain-of-trust story. (For the historical A7 generation, xerub's published key + tools like `img4` / `sepsplit` will decrypt the body — useful only for *reading old sepOS*, never for user keys. Treat that as a research walkthrough, not casework.)

### Confirm the certified module identity (paperwork that matters in court)

```bash
# Apple publishes the keystore as a certified cryptographic module.
# Cross-reference the device's SEP Secure Key Store certification when you
# need to assert, in a report, WHAT performed the crypto:
open "https://support.apple.com/en-us/103688"   # Apple SEP Secure Key Store Cryptographic Module
```

The forensic point of the citation: when you write "the class keys were unwrapped by the device's Secure Enclave," you are naming a **FIPS/Common-Criteria-certified module** (`sks`), not a hand-wave — which is exactly the kind of provenance a careful affidavit wants.

### Enumerate the keystore's exposed surface (and confirm the wall)

```bash
# Inspect the keystore user client object — the AP-side dispatch surface,
# i.e. the COMPLETE set of operations userspace can even ASK sks for:
ioreg -l -w0 | grep -iA20 "AppleSEPKeyStore"

# On iOS this path is driven by `keystorectl` + the private MobileKeyBag
# framework, which DO expose lock-state queries (e.g. AppleKeyStore lock
# state) — but those are iOS-only, still funnel through the SAME mailbox to
# sks, and there is no on-device shell to run them. The Mac surface is the
# faithful stand-in for the protocol.
```

Described point: the `externalMethod` surface of the keystore user client is *small and fixed* — load bag, unwrap, ref key, get lock state, and a handful more. That bounded request surface **is the wall expressed as an API**: there is no method that returns the UID, the keybag master, or a class key for a locked class, because sepOS exposes no such opcode. You are looking at the complete menu, and the dangerous dishes are simply not on it. An exploit can call any method here it wants; none of them is "give me the secret."

## 🧪 Labs

> All labs are device-free. Labs 1–3 run on **your Apple Silicon Mac's real SEP** (it runs the same sepOS / `sks` / mailbox driver as an iPhone, so the *protocol* behavior is faithful). Lab 4 is a static IPSW dissection. Lab 5 is a read-only walkthrough. **Fidelity caveat:** the iOS **Simulator has no SEP, no sepOS, no `sks`, and no Data-Protection-at-rest** — keychain/keystore APIs fall back to software and model *none* of the lock-state key eviction or attempt metering. The device-only daemons (`knowledged`, `biomed`, `routined`, PowerLog) likewise do not populate Simulator stores. Use the host SEP for protocol behavior; never validate a key-protection claim on the Simulator.

### Lab 1 — Map the AP-side keystore surface (host SEP)

1. `ioreg -rc AppleSEPManager` — confirm the mailbox nub matched at boot.
2. `ioreg -l | grep -iE "AppleKeyStore|AppleSEPKeyStore|KeyStoreUserClient"` — find the keystore proxy and its `AppleKeyStoreUserClient`.
3. Write one paragraph: of the seven sepOS apps in this lesson, which are *visible at all* from the AP side, and why the rest cannot be. (Answer: you see only the *proxy* and the *user client*; `sks`/`sbio`/`sse`/`scrd`/xART are all behind the mailbox and expose nothing — that is the design.)

### Lab 2 — Observe the wall in the unified log (host SEP)

1. Start the `log stream` from Hands-on with the `AppleKeyStore`/`aks` predicate.
2. Lock and unlock the screen a few times; trigger a Touch-ID/password prompt if your Mac has it.
3. In the captured lines, identify (a) a keybag/lock-state event and (b) a key unwrap or `ref_key` event. Confirm you see *no* key material anywhere.
4. Map three of the events to rows in the **service catalog** table. State, for each, what stayed behind the wall.

### Lab 3 — Lock-state and the keystore (host SEP, conceptual mapping)

1. While streaming the log, lock the screen and wait; then unlock.
2. Note the eviction-then-re-derivation pattern around lock/unlock — this is `sks` dropping and re-deriving class keys.
3. Write the iOS mapping by analogy: at **BFU** only the class-D key exists; **AFU** keeps class-C; lock evicts class-A. Which of those transitions does your Mac's lock/unlock most resemble, and which iOS behavior has *no* Mac analogue? (Answer: the Mac has no per-file class hierarchy and no Secure Storage attempt metering — it guards one volume key. Cross-check [[passcode-bfu-afu-and-inactivity]] and [[bfu-vs-afu-and-data-protection-classes]].)

### Lab 4 — Dissect the `sepi` payload (static IPSW)

1. Obtain any IPSW (or macOS IPSW) and run the `ipsw img4 info` / `extract` commands from Hands-on against `sep-firmware.*.im4p`.
2. Record: the IM4P tag (`sepi`), the compression, the presence of `PAYP` (iOS 15+), and that the IM4M manifest binds it to a specific ECID/board.
3. State plainly what you *can* learn statically on an A12+ payload (existence, signing, per-device personalization, encryption) and what you *cannot* (decrypt/run sepOS). That boundary is the SEP boot chain.
4. *(Optional, historical)* For an **A7** `sepi`, apply xerub's published key with `img4`/`sepsplit` to decrypt the body. Note that you can now *read* sepOS — and that this still yields **zero** user key material. Write down why decrypting the firmware ≠ extracting the keys.

### Lab 5 — blackbird / SEP downgrade (read-only walkthrough; device-only)

> ⚠️ **ADVANCED / device-only — do not attempt against evidence.** There is no Mac substrate for a SEPROM exploit; this is a paper exercise.

On paper, trace a blackbird-class SEP defeat on a checkm8 **A10** device: (1) checkm8 gives AP BootROM code-exec *before TZ0 lock*; (2) blackbird (SEPROM bug) lets you **set the SEP nonce** and load **unsigned/downgraded sepOS**; (3) you now have SEP code execution on legacy silicon. Then answer: (a) why this is impossible on an **A11** device (blackbird doesn't affect it) and on **A12+** (no public SEPROM exploit, and the Secure Storage Component meters attempts regardless); (b) why even SEP code-exec here is *not* a turnkey key dump — what additional work and what device state would still be required; (c) why none of this transfers to the iPhone 17 (A19) on your desk-research list. Cross-check [[the-jailbreak-landscape-2026]], [[boot-chain-securerom-iboot]], and [[the-acquisition-taxonomy]].

### Lab 6 — Keybag triage on a backup (public sample image)

> Substrate: a **public sample iOS backup** (Josh Hickman / Digital Corpora reference images) or any `idevicebackup2` output you are authorized to use. **Fidelity caveat:** this exercises the *backup* keybag, not the on-device user keybag — by design, to feel the feasibility difference.

1. In the backup folder, open `Manifest.plist` and locate the `BackupKeyBag` blob and the `IsEncrypted` boolean.
2. If `IsEncrypted` is true, the `BackupKeyBag`'s class keys are wrapped with a key derived (PBKDF2) from the *backup password* — the off-device-attackable case (e.g. an `iphone-dataprotection`/hashcat-mode-style attack). If false, the keys are wrapped with a device-bound key.
3. Write the decision: for *this* artifact, is an off-device password attack viable (encrypted backup → yes) or foreclosed (on-device user keybag → no)? Tie your answer explicitly to the keybag table and to the UID-vs-password distinction. Cross-check [[the-itunes-finder-backup-format]] and [[decrypting-backups-and-images]].

## Pitfalls & gotchas

- **"A jailbreak gets the keys." It does not.** A jailbreak is AP/XNU compromise. It yields whatever class keys `sks` had *already released* for the lock state at seizure — never the UID, the keybag master, or a locked class's key. Conflating "I own the kernel" with "I have the keys" is the single most common — and most report-damaging — error. The wall is the mailbox, and it carries requests, not secrets.
- **`AppleKeyStore` (AP kext) ≠ `sks` (sepOS app).** The kext is a *proxy* on the AP; `sks` is the *vault* in the SEP. An `AppleKeyStore`/`AppleSEPKeyStore` use-after-free (e.g. the 2026 CVE) corrupts the proxy and gets you AP kernel — it does **not** breach sepOS. Don't cite an AP-side keystore bug as a "Secure Enclave compromise."
- **Endpoint numbers are not stable — don't hard-code them.** `sks` was endpoint 7 on iOS 9 A-series and 0x12 on a recent Apple Silicon Mac. The *app set* and the *message format* are durable; the numbering is per-SoC/per-OS. Read the live endpoint list from the debug/discovery endpoint rather than assuming. (Flagged in `versionFlags`.)
- **The Simulator has no sepOS.** No SEP, no `sks`, no Data-Protection-at-rest, no attempt metering. Keychain there is software-backed. Never validate a key-protection or lock-state claim on the Simulator — use the host Mac SEP for protocol behavior and sample images for at-rest behavior.
- **Decrypting sepOS firmware ≠ extracting keys.** xerub's A7 key (and any future firmware decryption) lets you *read sepOS code*. It reveals nothing about a given device's UID, keybag, or passcode. Reverse-engineering the OS and breaking a device's data protection are different problems; don't let a "SEP firmware decrypted" headline imply the latter.
- **blackbird is a legacy-silicon, SEPROM-level story.** It affects A8/A9/A10/T2 only (not A11, not A12+), needs an AP foothold before TZ0 lock, and grants *SEP code-exec / sepOS downgrade* — not a key dump. Reasoning about a modern A19 device with blackbird-era assumptions will badly mislead a feasibility assessment.
- **SEP downgrade is blocked by the SEP nonce + personalization on A12+.** "Just boot an old, buggy sepOS" is foreclosed: the `sepi` is per-device personalized and bound to a current SEP nonce, so old signed images won't load. Only the checkm8/blackbird devices ever allowed setting the nonce to bypass this.
- **OS-bound keys change if you boot your own SEP code (A13+).** The Boot Monitor's measured hash feeds the PKA; a different sepOS derives different OS-bound keys, so anything sealed under the genuine OS won't unwrap. "We booted custom SEP code" does not imply "we can read the sealed items."
- **Biometric lockout ≠ passcode lockout.** `sbio` disabling Face ID/Touch ID after failed matches is a *different* SEP-enforced counter than the `sks`/Secure-Storage passcode lockbox. A device with biometrics locked out may still accept the passcode normally. Don't conflate the two when assessing a seizure.
- **The mailbox is the only channel — there is no side door.** sepOS does not mount the filesystem, does not have a debug shell on production fuses, and does not expose memory to the AP. If a workflow claims to "read SEP memory directly," it is reading *AP* memory (ciphertext for the SEP region) or it is wrong.
- **FIPS/CC-certified ≠ unbreakable.** The "Apple SEP Secure Key Store" certification attests that the module meets its *claimed* security policy under defined conditions — it is excellent provenance for a report, but it is not a proof that no sepOS bug exists. Cite the certification for *what performed the crypto*, not as a guarantee of invulnerability.
- **TZ0 is the SEP's memory region, not "TrustZone."** Despite the name, TZ0 (and TZ1) are Apple's protected DRAM carve-outs for the SEP and related secure agents — not Arm TrustZone secure-world. Apple's SEP is a *separate core*, precisely *unlike* the time-shared TrustZone model. Don't import TrustZone assumptions when you see "TZ0."
- **"sepOS is verified like seL4" — no.** sepOS is L4-*embedded*/Darbat-derived; only the PKA's arithmetic (A13+) carries a formal-verification claim, and that is hardware. Don't overstate sepOS's assurance by borrowing seL4's proof.

## Key takeaways

- **sepOS is a real OS** — an Apple-customized **L4 microkernel** (Darbat-derived) running isolated *apps* on the SEP core: `sks` (keystore/vault), `sbio` (biometrics), `sse` (secure element), `scrd` (credentials), the xART/anti-replay manager, and a control/boot endpoint. L4 isolation is a *second* boundary nested inside the SEP's hardware isolation.
- **`sks` is the thing that actually wraps/unwraps keys.** Every "can I decrypt X?" maps to "has `sks` unwrapped X's class key for the current lock state, and will it release a result?" — a property of sepOS software state, not of the file on disk.
- **The AP↔SEP protocol carries typed requests, never secrets.** A 64-bit `endpoint|tag|opcode|params|data` message over the mailbox, with bulk data in OOL shared buffers; sepOS copies the request in, operates inside the SEP, and returns only a *result or decision*.
- **The AP-side keystore is a proxy, and it is attackable — without breaching the SEP.** `AppleKeyStore`/`AppleSEPKeyStore` kexts and their `aks_*`/`AppleKeyStoreUserClient` surface are a recurring AP-*kernel* attack surface (e.g. the 2026 `AppleSEPKeyStore` UAF). Corrupting the proxy yields AP kernel, not `sks`.
- **sepOS boots from a personalized `sepi` Image4**, verified by the immutable SEPROM against the Apple Root CA, bound to this device's ECID and a **SEP anti-rollback nonce**, GID-encrypted on A12+, and (A13+) measured by the Boot Monitor into the OS-bound-key hash — which is why **sepOS downgrade is foreclosed on modern devices**.
- **Every public SEP defeat is software or below-the-AP** — Mandt/Solnik's reverse engineering, xerub's A7 firmware-decryption key, blackbird's A8–A10/T2 SEPROM bug, the AP-side keystore kext UAFs. **None reads the UID; none of the A12+ ones hands over user keys.**
- **The SEP is the acquisition wall because a jailbreak is AP-only.** Owning XNU does not own sepOS: the keys for locked classes are *not in AP memory to steal*, the protocol has no opcode to exfiltrate them, and the mailbox carries requests, not secrets. This is the firmware-level reason a **BFU device holds even against a kernel-owned attacker**.

## Terms introduced

| Term | Definition |
|---|---|
| sepOS | The Secure Enclave Processor OS: an Apple-customized L4 microkernel (Darbat-derived) running on the SEP core, with its own kernel, drivers, and isolated apps |
| L4 microkernel | Minimal-kernel design (scheduling/memory/IPC only) that pushes services into isolated, message-passing userspace tasks; the basis of sepOS |
| `sks` (SEP KeyStore) | The sepOS app that performs the actual wrap/unwrap of Data Protection class keys, holds the keybag, and enforces lock state; the FIPS/CC-certified "Apple SEP Secure Key Store" module |
| `sbio` | The sepOS biometrics app: stores Face ID/Touch ID templates and performs matching (Secure Neural Engine on Face ID); returns only match/no-match |
| `sse` | The sepOS Secure Element manager: gates Apple Pay / contactless SE transactions on a biometric/passcode result |
| `scrd` | The sepOS credential manager, layered above the keystore |
| xART manager | The sepOS app managing eXtended Anti-Replay Tokens, "gigalockers," and keybag anti-rollback against the Secure Storage Component (predecessor: ARTM on early SoCs) |
| Mailbox message (SEP) | A 64-bit `endpoint|tag|opcode/type|params|data` word over the AP↔SEP mailbox; bulk payloads ride in OOL (out-of-line) shared buffers |
| OOL buffer | Out-of-line shared-memory buffer allocated by `AppleSEPManager` for bulk request/reply data across the mailbox |
| `AppleKeyStore` / `AppleSEPKeyStore` | The AP-side IOKit kernel extension that proxies keystore requests to sepOS `sks`; exposes `AppleKeyStoreUserClient` and the `aks_*` API |
| `aks_*` API | The userspace C interface (in `libAppleKeyStore`) for keystore operations: `aks_load_bag`, `aks_unwrap_key`, `aks_get_lock_state`, `aks_ref_key`, etc. |
| Keybag | A collection of wrapped class keys managed by `sks`; iOS uses user, device, backup, escrow, and iCloud Backup keybags, each with a different unlock factor |
| User keybag | The keybag holding the wrapped class keys for normal operation, unlocked by the passcode tangled with the UID — on-device-only, lock-state-gated |
| Backup keybag | A keybag whose class keys are re-wrapped under a key derived (PBKDF2) from the *backup password*, not the UID — the reason encrypted local backups are attackable off-device |
| `sepi` | The Image4 payload four-cc tag for the SEP firmware (`sep-firmware.<board>.RELEASE.im4p`); GID-encrypted on A12+ |
| SEPROM | The immutable SEP boot ROM (mask ROM) that verifies and boots the `sepi` payload; the SEP analogue of the AP's SecureROM |
| SEP nonce | The SEP-side anti-rollback nonce bound into the `sepi` personalization manifest, preventing replay/downgrade of old signed sepOS |
| TZ0 | The SEP's protected DRAM region; locked during SEP boot. blackbird-class attacks require AP code-exec *before* TZ0 is locked |
| blackbird | Pangu's 2020 SEPROM code-execution exploit for A8/A9/A10/T2 SoCs (not A11, not A12+); enables setting the SEP nonce and loading unsigned/downgraded sepOS |
| OS-bound key | A PKA key derived from the UID + the Boot Monitor's measured sepOS hash; binds sealed data to a specific device-and-OS (A13+) |
| `seputil` | The on-device helper that drives the SEP side of restore/OTA, applying the re-personalized `sepi` image |
| TZ0 lock | The point in SEP boot at which the protected memory region is locked; SEPROM exploits (blackbird) must land *before* it |
| Acquisition wall | The principle that AP/XNU compromise (a jailbreak) cannot cross the mailbox into sepOS, so the keys for locked classes stay sealed |

## Further reading

- **Apple Platform Security Guide** (current edition) — "Secure Enclave," "Hardware microkernel services," "Encryption and Data Protection," "Keybags for Data Protection": help.apple.com/pdf/security/en_US/apple-platform-security-guide.pdf — the authoritative primary source for sepOS services and the L4 statement.
- **Apple Support — "Apple SEP Secure Key Store Cryptographic Module"**: support.apple.com/en-us/103688 — the certified-module identity of `sks` for report citations.
- **Apple Support — "Keybags for Data Protection"**: support.apple.com/guide/security/sec6483d5760/web — the keybag types `sks` manages (user, device, backup, escrow, iCloud).
- **Tarjei Mandt, Mathew Solnik, David Wang — "Demystifying the Secure Enclave Processor"** (Black Hat US 2016): blackhat.com/docs/us-16/materials/us-16-Mandt-Demystifying-The-Secure-Enclave-Processor.pdf — the foundational reverse engineering: sepOS apps, mailbox endpoints, message format.
- **Asahi Linux — Secure Enclave Processor docs**: asahilinux.org/docs/hw/soc/sep/ — the open-source, current AP↔SEP mailbox protocol (message fields, endpoints, OOL buffers) from a driver that actually boots the SEP.
- **xerub — SEP firmware decryption (2017)** + **github.com/mwpcheung/AppleSEPFirmware** — the A7 `sepi` decryption key and tooling; helpnetsecurity.com coverage. Reads old sepOS; extracts no user keys.
- **theapplewiki.com / theiphonewiki.com** — `Secure_Enclave_Processor`, `Blackbird_Exploit`, `sepOS`, `seputil`, `sep-firmware` — device scope, SEPROM, `sepi` payloads, SEP nonce.
- **blacktop/ipsw** (github.com/blacktop/ipsw) — `ipsw img4` for extracting/inspecting the `sepi` payload and the IM4M personalization manifest; man pages via `ipsw <cmd> --help`.
- **Jonathan Levin, *\*OS Internals* Vol. III (Security & Insecurity)** + newosxbook.com — SEP boot, the IOP/mailbox framework, sepOS structure; the deepest non-Apple treatment.
- **Hexacon 2025 — "Inside Apple Secure Enclave Processor in 2025" (Quentin Salingue)** — the current research snapshot on the SEP boot process, the Trusted Boot Monitor, PAC in the SEP, and recent SEP patches (slides at 2025.hexacon.fr).
- **matteyeux — "À propos de SEPOS"** + the `sepsplit`/`sephelper` tooling — practical notes on splitting and reading decrypted sepOS images.
- **Pangu Team — MOSEC 2020 talk (blackbird)** + theapplewiki "Blackbird Exploit" — the SEPROM-exploit device scope (A8/A9/A10/T2), TZ0-lock timing, and the SEP-nonce/downgrade mechanism.
- **L4 microkernel family / seL4** (sel4.systems, Wikipedia "L4 microkernel family") — the design lineage and TCB philosophy sepOS inherits (and the verified member it is *not*).
- **Project Zero / Quarkslab / Synacktiv** SEP and keystore write-ups — for the AP-side attack-surface view carried into [[the-jailbreak-landscape-2026]] and Part 11.

---
*Related lessons: [[secure-enclave-hardware]] | [[the-ios-security-model]] | [[data-protection-and-keybags]] | [[passcode-bfu-afu-and-inactivity]] | [[keychain-on-ios]] | [[biometrics-security-architecture]] | [[image4-personalization-shsh]] | [[full-file-system-acquisition]] | [[the-jailbreak-landscape-2026]]*
