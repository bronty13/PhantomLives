---
title: "The iOS security model"
part: "03 — Security Architecture"
lesson: 00
est_time: "40 min read + 15 min labs"
prerequisites: [macos-to-ios-mental-model-reset, secure-enclave-hardware]
tags: [ios, security-model, platform-security]
last_reviewed: 2026-06-26
---

# The iOS security model

> **In one sentence:** iOS security is a six-layer stack — hardware root of trust → secure boot → OS integrity → Data Protection → app security → services — where every layer cryptographically trusts only the layer beneath it, the chain terminates in fused silicon the user can never reach, and for a forensic examiner each layer is a *wall*: the entire acquisition game is knowing which wall you hit and why.

## Why this matters

You just finished a course where macOS security was three named defenses you could reason about one at a time — **SIP** keeps root out of the system volume, **Gatekeeper** vets downloaded apps, **TCC** brokers privacy consent — and where, with enough privilege, you could lower any of them: `csrutil disable` in Recovery, `xattr -d com.apple.quarantine`, click "Allow" in the Privacy pane. iOS is built from the *same XNU kernel and the same frameworks*, but the defenses are no longer a menu of independent, lowerable speed bumps. They are a single **layered stack, rooted in hardware, with the downgrade switches welded shut**, and the layers are *load-bearing on each other*: secure boot exists only because the SEP attests it; Data Protection's class keys mean nothing without the SEP that derives them; the sandbox is enforceable only because the kernel it runs in was itself verified by the layer below.

For you this is two jobs at once. As a **builder**, the stack defines what your app can and cannot do, why an entitlement is a hardware-attested capability and not a config flag, and where the platform will silently refuse you. As a **forensic examiner**, the stack *is the map of the engagement*: every method in Part 07 — logical backup, full-file-system, cloud — succeeds or dies at a specific layer, and "is this data recoverable?" is never a yes/no but a coordinate `(which layer) × (device state)`. This lesson is the model you hang the rest of the module on: the whole stack in one view, the threat each layer answers, how it maps to the macOS pillars you already know, and which lesson drills each layer to the bottom.

## Concepts

This lesson is the *map*, not the territory — it walks the whole stack at the altitude where the layers' relationships are visible, and hands each layer off to a dedicated lesson for the mechanism depth. Three threads run through it: the **six-layer stack** (what each layer is and what it trusts beneath it), the **threat model** (which adversary each layer answers, and what it pointedly does not), and the **forensic lens** (every layer as a wall an examiner meets). Hold all three at once and the rest of Part 03 reads as a series of deep dives into a structure you already understand.

### The shape of the model: defense in depth, hardware-rooted, mandatory

Apple's own *Platform Security Guide* (current edition March 2026) organizes the platform into chapters — hardware security & biometrics, system security, encryption & data protection, app security, services security, network security. Collapse those into the **trust stack** that actually matters for engineering and forensics and you get six layers. Read the diagram bottom-up — that is the direction trust flows. The **Boot ROM and the fused keys at the base are immutable and unreachable**; everything above is verified by what sits below it before it is allowed to run:

```
┌──────────────────────────────────────────────────────────────────┐
│ SERVICES        iCloud · iMessage(BlastDoor) · Apple Pay/SE ·      │  what the user does
│                 Find My · iCloud Keychain(HSM) · ADP · APNs        │
├──────────────────────────────────────────────────────────────────┤
│ APP SECURITY    mandatory code signing (AMFI) · the sandbox ·      │  every app, no opt-out
│                 entitlements · TCC consent ledger                  │
├──────────────────────────────────────────────────────────────────┤
│ DATA PROTECTION per-file keys · class keys · system keybag ·       │  encryption at rest,
│                 BFU/AFU lock state                                 │  lock-state-aware
├──────────────────────────────────────────────────────────────────┤
│ OS INTEGRITY    Signed System Volume (Merkle seal) ·               │  the running kernel
│                 KTRR→PPL→SPTM/TXM→Exclaves→MIE · PAC               │  can't be rewritten
├──────────────────────────────────────────────────────────────────┤
│ SECURE BOOT     SecureROM → iBoot → kernelcache · IMG4 / SHSH      │  only Apple-signed
│                 personalization · APTicket anti-rollback           │  images boot
├──────────────────────────────────────────────────────────────────┤
│ HARDWARE ROOT   Secure Enclave (sepOS) · fused UID/GID keys ·      │  immutable anchor,
│                 AES engine · Boot ROM                              │  user-unreachable
└──────────────────────────────────────────────────────────────────┘
        each layer is verified by — and trusts only — the layer beneath it
```

Three properties distinguish this from anything on the Mac, and they recur in every layer below:

1. **Hardware-rooted.** The chain does not bottom out in a file, a flag, or an admin password — it bottoms out in keys *fused into the silicon* during manufacture (the per-device **UID**, the per-model **GID**) that the SEP can *use* but no software, on or off device, can ever *read*. There is no equivalent of "knowing the FileVault recovery key"; the root secret physically cannot leave the chip.
2. **Mandatory.** Each layer is on by default for every device and every app, with **no supported downgrade**. macOS gives you `csrutil disable`, `spctl --master-disable`, a per-machine **LocalPolicy** you lower in 1TR. iOS ships *Full Security only*; there is no "reduced security" boot, no developer toggle that disables AMFI, no way to opt an app out of the sandbox.
3. **Layered / load-bearing.** Compromising one layer does *not* hand you the ones below. A full kernel jailbreak (OS-integrity layer owned) still does not forge a signature the SEP rejects, still does not decrypt a **BFU** device whose class keys the SEP hasn't released, and still does not read the fused UID. The layers fail *independently*, which is exactly why the stack survives a kernel bug.

> 🖥️ **macOS contrast:** On the Mac the three pillars — SIP, Gatekeeper, TCC — are **peers you can disable one at a time**, and the human at the keyboard is the trust root: become root, lower the policy, and the machine obeys. iOS takes those same ideas, makes each one **mandatory and hardware-attested**, and stacks them so the trust root is *the silicon, not the user*. The mental conversion for this whole module: wherever macOS says "a privileged user may turn this off," iOS says "this is verified in hardware below the privileged user and there is no off."

The next six subsections walk the stack bottom-to-top — one paragraph of mechanism each, plus the lesson that drills it. The point here is the *shape*, not the depth; the depth is the rest of Part 03.

### Layer 0 — the hardware root of trust (SEP + fused keys)

The base of the stack is the **Secure Enclave** — a separate, isolated coprocessor on the SoC running its own OS (**sepOS**) off its own **Secure Enclave Boot ROM**, with its own AES engine and a **Memory Protection Engine** that encrypts/authenticates its DRAM (AES in an XEX-family mode with integrity tags) so the application processor — even a fully compromised one — cannot read SEP memory. Burned into the fuses are two keys the SEP can use but nothing can extract: the per-device **UID** and the per-model **GID**. *Every* secret above this layer ultimately ties back to the UID: the Data-Protection class keys are derived from the passcode **entangled with the UID**, so they can only be reconstructed on *this specific chip*, with the *user's secret*, at SEP-controlled rates. This is why there is no off-device brute force of a strong passcode and no cold-boot key recovery: the work is forced through one piece of silicon that counts attempts and rate-limits in hardware.

Two more structural facts make Layer 0 the linchpin. First, a **dedicated AES engine sits inline on the storage DMA path** between flash and main memory, so per-file keys encrypt/decrypt at line rate *and the raw keys never enter application-processor-readable memory* — the AP gets plaintext blocks, never the key that produced them. Second, the SEP is the **single gatekeeper for everything that proves user presence**: it owns the Face ID/Touch ID templates, evaluates a match internally, and only *then* releases the keys or signs the "secure intent" a payment needs — biometrics never leave the enclave as raw data. The AP asks; the SEP decides. → drilled in [[sep-sepos-deep-dive]], hardware in [[secure-enclave-hardware]], biometrics in [[biometrics-security-architecture]].

> 🔬 **Forensics note:** Layer 0 is *why* "just copy the NAND and decrypt offline" doesn't work. The encrypted blocks are readable; the keys are not, because they are wrapped to a value only the SEP can compute from the UID + passcode under its own attempt counter. A commercial extraction box that "brute-forces the passcode" is really *driving the SEP* to test guesses at whatever rate the SEP permits — which is why a 6-digit numeric code is a different forensic proposition from a long alphanumeric one even though both encrypt the same files.

### Layer 1 — secure boot (the chain of trust)

Power-on hands control to the **SecureROM** (mask-ROM, immutable, the hardware root of *boot* trust), which verifies and loads **iBoot**, which verifies and loads the **kernelcache** — each stage refusing to execute the next unless it is **Apple-signed**. Images are packaged as **IMG4** (an ASN.1/DER container of payload + manifest + signature) and **personalized**: at restore time Apple's signing server (TSS) issues an **APTicket/SHSH** blob binding the approved component hashes to *this device's* ECID and an anti-rollback nonce, so a blob signed for one device or one OS version can't be replayed onto another or rolled back to a vulnerable build. There is no LocalPolicy to lower and no Reduced-Security mode — the *only* way below a signature check is a **vulnerability** in the SecureROM itself (`checkm8`, A8–A11; the June-2026 `usbliter8` USB-DMA bug, A12–A13) or an iBoot/kernel chain. → drilled in [[boot-chain-securerom-iboot]] and [[image4-personalization-shsh]].

> 🔬 **Forensics note:** A SecureROM exploit is **code-execution below the signature check, not a decryption key**. It lets a tool boot its own ramdisk and reach the NAND and the SEP's front door — but it does not defeat Layer 0. With a *known or brute-forceable passcode* it enables a full-file-system extraction (because now the SEP can be driven to derive the class keys); without the passcode on a BFU device it still yields mostly ciphertext. The SoC generation therefore decides your entire acquisition tree before any other fact about the case. → [[the-acquisition-taxonomy]], [[full-file-system-acquisition]], [[the-jailbreak-landscape-2026]].

### Layer 2 — OS integrity at runtime (SSV + the kernel-hardening ladder)

Secure boot proves the kernel was *Apple's at load time*; Layer 2 keeps the system honest *while it runs*. Two mechanisms:

- **Signed System Volume (SSV).** Since iOS 15, the read-only system volume is sealed by a **Merkle tree**: every block's SHA-256 hash rolls up through the APFS metadata tree to a single root hash — the **seal** — that the bootloader checks against an Apple-signed value before starting the kernel, and that the kernel re-verifies on every read of system data. Tamper with one byte of the system volume and the seal breaks; the device won't boot the modified system. This is integrity by *continuous cryptographic verification*, not a permission bit.
- **The kernel-hardening ladder.** The kernel defends its own pages with an escalating set of hardware monitors, each added as the silicon gained the capability — every rung a direct answer to a class of memory-corruption exploit, so that owning the kernel's *logic* no longer means owning its *memory*:

| Rung | What it enforces | First silicon *(dated — verify)* |
|---|---|---|
| **KTRR / AMCC** | Locks kernel text + page tables read-only after boot via the memory controller | A10-era |
| **PAC** | Pointer authentication — signs pointers so a corrupted one fails auth | A12+ |
| **PPL** | Page Protection Layer — only PPL code may edit page tables / code-sign state | A12+ (software) |
| **SPTM / TXM** | Hypervisor-grade monitor *above* the kernel owning page-table retyping + code-signing/entitlement checks; a kernel write-primitive can't remap memory executable | A15 / M2+, iOS 17 |
| **Exclaves** | Isolated trust domains carving sensitive services out of the kernel's reach | A18 / M4-era |
| **MIE** | Memory Integrity Enforcement — always-on hardware memory tagging (EMTE) across kernel + userland | A19 / M5 (iPhone 17/Air/Pro) |

→ drilled in [[kernel-hardening-pac-sptm-txm-mie]].

> 🖥️ **macOS contrast:** SSV exists on the Mac too (same Merkle-sealed system volume since macOS 11) — but on the Mac you can *break the seal on purpose*: lower the LocalPolicy in 1TR, run `csrutil authenticated-root disable`, mount the system volume writable. On iOS there is no such command and no such mode; the seal is checked at boot with no toggle to skip it. SIP's "protect the system from root" intent survives, but it has graduated from a *flag root can clear* to a *cryptographic invariant the bootloader enforces*.

### Layer 3 — Data Protection (encryption at rest)

Above an intact OS sits the at-rest encryption you met in the mental-model reset: **every file gets its own random per-file key**, each wrapped by one of a handful of **class keys** (A/Complete, B/CompleteUnlessOpen, C/UntilFirstUserAuthentication — *the default* — D/None), the class keys living in the **system keybag** and themselves wrapped by the passcode-entangled-with-UID secret from Layer 0. The wrapped per-file key rides in the APFS `cprotect` extended field. Readability is therefore not "is the disk unlocked" but **`(file's class) × (BFU/AFU/unlocked state)`**: a freshly-booted **BFU** device exposes only Class D; once the passcode is entered (**AFU**) the Class C keys become resident and stay resident across screen-locks until reboot, lighting up the *majority* of user data. → drilled in [[data-protection-and-keybags]] and [[passcode-bfu-afu-and-inactivity]]; storage substrate in [[storage-nand-aes-effaceable]].

> 🔬 **Forensics note:** This layer is the one most examiners misjudge by importing the FileVault model. FileVault is *one* volume key — unlock once, read everything. Data Protection re-locks per-class on every screen-lock for Class A and snaps the *whole* device back to near-opaque on reboot (BFU). Two SOP reflexes fall straight out and define the first minutes of a seizure: **never reboot the device**, and **keep it powered, awake, and radio-isolated** to beat the ~72 h **inactivity reboot** (since iOS 18.1) that the SEP uses to force AFU→BFU on its own.

### Layer 4 — app security (mandatory code signing + sandbox + TCC)

Given a verified kernel and encrypted data, Layer 4 governs *what code runs and what it can touch*. Three mandatory mechanisms, none of them opt-in:

- **Mandatory code signing (AMFI).** Every executable page must hash-match a signed **Code Directory**, checked **in-kernel at fault-in time**; platform binaries clear via the in-kernel **trust cache**, third-party apps via `amfid` validating the CMS signature + provisioning profile + entitlements. Unsigned pages are never made executable — `chmod +x` is meaningless and there is no JIT without the rare `dynamic-codesigning` entitlement.
- **The sandbox.** Every app is confined at launch to its **Bundle** (signed, read-only code) and **Data** (read-write) containers by a per-app Seatbelt profile; cross-app data flows only through brokered channels (share sheet, App Groups, pasteboard), never raw paths.
- **TCC + entitlements.** Privacy-sensitive resources (camera, mic, photos, location, contacts) are gated by an **entitlement plus a purpose string**; consent is recorded per-app in `TCC.db`. Privilege on iOS *is* the entitlement set baked into the signature — there is no uid to escalate to. → drilled in [[code-signing-amfi-entitlements]] and [[the-sandbox-and-tcc]]; the loader side in [[dyld-shared-cache-and-amfi]].

> 🖥️ **macOS contrast:** All three exist on the Mac and all three are *escapable*: Gatekeeper only gates quarantined GUI launches (run from the shell and it never fires); the App Sandbox is an opt-in entitlement most non-App-Store software ignores; TCC is a consent prompt a user (or, historically, a clever bug) can satisfy. iOS makes the identical machinery a **wall with no shell behind it** — AMFI is a kernel page-fault check, the sandbox is universal, and the entitlement gate trips *before* the consent prompt even appears.

### Layer 5 — services security (iCloud, Apple Pay, iMessage, escrow)

The top layer extends the on-device trust model *off the device*, so that cloud features don't reintroduce the weaknesses the lower layers removed:

- **Apple Pay / Secure Element.** Payment credentials live in a separate **Secure Element** (a certified SE, distinct from the SEP); the **SEP** handles user authentication and "secure intent," and during a tap the **NFC controller → SE** path carries the transaction over a dedicated bus so card data **never reaches the application processor or the OS**. On iOS 18.1+ third-party wallet/access credentials can be provisioned into the SE via the NFC & SE Platform.
- **iCloud Keychain / escrow.** Synced secrets are end-to-end encrypted and recoverable only through **HSM-backed escrow** clusters that enforce a hard attempt limit on the recovery passcode, then destroy the escrow record — Apple itself cannot read the data.
- **iMessage / BlastDoor.** Inbound message parsing runs in the tightly-sandboxed **BlastDoor** service, a direct structural answer to zero-click parser exploits.
- **Find My / Activation Lock.** Activation Lock binds the device to its **Apple Account** in Apple's activation servers, so a wiped-and-reset device still demands the original account's credentials before it can be set up — turning the lower layers' crypto-erase into a *theft deterrent* (the thief gets a working brick, not a resellable phone). Find My's offline location uses a rotating-key BLE beacon design that even nearby Apple devices relay without learning the owner.
- **ADP.** **Advanced Data Protection** extends end-to-end encryption to most iCloud categories (backups, Photos, Notes), removing Apple's ability to hand over readable data — and, for you, removing the cloud as an acquisition path. → services drilled across [[apple-account-icloud-and-apns]], [[keychain-on-ios]], [[biometrics-security-architecture]], [[advanced-protections-lockdown-sdp-adp]].

> 🔬 **Forensics note:** Layer 5 is where the *cloud* acquisition path lives, and **ADP closes it**: with ADP on, the iCloud server side holds only ciphertext it cannot decrypt, so a legal-process return that used to yield readable iCloud backups now yields blobs. ADP status is therefore a case-shaping fact — it determines whether the cloud is even a productive target before you serve anything. → [[advanced-protections-lockdown-sdp-adp]].

One concern runs *across* all six rather than sitting in a single layer: **network security** — TLS with App Transport Security defaults, per-app and system VPN via NetworkExtension, MAC-address randomization, and the privacy-preserving designs behind Wi-Fi/Bluetooth/Find My. It is a cross-cutting band the *Platform Security Guide* treats as its own chapter; this course gives it a whole module (Part 04) rather than folding it into the on-device stack, because for both a builder and an examiner the wire is a distinct surface with its own tools (interception, pinning, the lockdown relay). Mentally, picture it wrapping the right edge of the stack diagram, touching every layer that talks to the outside.

### How the layers attest each other (the trust handoff)

The six layers are not parallel walls — they are a *chain*, where each layer is permitted to run only because the layer below cryptographically measured it first, and where a key released at one layer is conditioned on the integrity of every layer beneath. Walk one cold boot through the stack and the "load-bearing" property stops being abstract:

```
SecureROM          measures + verifies iBoot's IMG4 signature ───┐  (fails → DFU, no boot)
   │                                                             │
iBoot              verifies kernelcache signature AND the SSV ───┤  (seal broken → won't start kernel)
   │               seal against the Apple-signed root hash       │
   │                                                             │
kernel boots       with the static trust cache pre-loaded;  ─────┤  (SPTM/TXM now owns page tables;
   │               AMFI live; sandbox profiles ready             │   a later kernel bug can't remap exec)
   │                                                             │
SEP (parallel)     booted its own sepOS from its own Boot ROM; ──┤  (independent root; AP compromise
   │               holds UID; will derive class keys ONLY        │   cannot read SEP memory)
   │               after a valid passcode entangles with UID     │
   │                                                             │
first unlock       passcode → SEP → class keys resident ─────────┤  (BFU→AFU; Layer 3 "opens")
   │                                                             │
app launch         AMFI verifies signature → sandbox confines ───┘  (Layer 4 gates what runs/reads)
```

Two consequences the chain forces, both of which surface constantly in forensics and RE:

- **A layer's protection is only as available as the layers below permit.** Data Protection class keys (Layer 3) do not exist in memory until the SEP (Layer 0) derives them from a passcode — which is why a BootROM exploit (Layer 1) yields *code execution but not plaintext*. The exploit jumps the boot-signature wall; it does not conjure the keys the SEP still gatekeeps.
- **The SEP is a parallel root, not a step in the AP's chain.** It boots from its *own* ROM and holds the UID independently, so owning the application-processor kernel (a jailbreak) does not own the SEP. That structural separation is precisely why Data Protection survives a kernel compromise on a BFU device, and why "I have root on the phone" is *not* "I have the keys."

This is the engineering meaning of "layered/load-bearing": breach any single layer and you get exactly that layer's authority — never the chain.

### The threat model: what each layer is actually defending against

A security model is only meaningful against named adversaries. iOS is explicitly engineered against a spectrum, and each layer answers a different point on it. Knowing *which threat a layer was built to stop* tells you both where it's strong and where the **residual gap** is — which, for an examiner, is exactly where the recoverable evidence (or the live infection) tends to be:

| Adversary | Primary defending layer(s) | Residual gap / examiner angle |
|---|---|---|
| **Opportunistic theft** (lost/stolen device) | Data Protection + passcode + Activation Lock + Stolen Device Protection | Whatever the thief's state captures: a grabbed **AFU/unlocked** device leaks Class C; **BFU** is near-opaque |
| **Commodity malware / trojan apps** | App security (AMFI + sandbox + App Review) | Confined to one sandbox; can't drop unsigned code or read other apps — but *its own* container is a rich artifact source |
| **Forensic / lawful extraction** (GrayKey, Cellebrite) | Hardware root (SEP rate-limit) + Data Protection (BFU) + secure boot | Bounded by SoC generation (BootROM-exploit reach **A8–A13**), passcode strength, and BFU/AFU at seizure |
| **Nation-state / mercenary spyware** (NSO-class, zero-click) | OS-integrity ladder (PAC→PPL→SPTM/TXM→Exclaves→MIE) + BlastDoor + **Lockdown Mode** | Memory-resident, no on-disk binary (AMFI forbids one) — hunt the *side-effects* in signed stores (mvt, Part 09) |
| **Evil-maid / supply-chain tamper** | Secure boot chain + SSV seal | Tamper breaks the seal → won't boot; physical-implant detection is hardware-level |
| **Cloud / server-side compromise** | Services (E2EE, HSM escrow, **ADP**) | ADP removes the cloud as a readable target entirely |

Two observations to carry forward. First, the **mercenary-spyware row is why Layer 2 keeps escalating** — PAC, PPL, SPTM/TXM, Exclaves, and now MIE on A19 are each a direct response to memory-corruption exploit chains, and **Lockdown Mode** (Part 06) is the user-selectable extreme: it deliberately disables attack surface (JIT, some message parsing, wired connections) that the spyware ecosystem relies on. Second, the **forensic-extraction row is the one this course's Part 07 lives in**, and it is bounded almost entirely by *Layer 0 and Layer 3 facts* — SoC generation, passcode strength, BFU/AFU state — none of which any tool can talk past.

### What the model deliberately does *not* protect against

A security model is defined as much by its **non-goals** as its defenses, and naming them precisely is where an examiner finds the productive seams — the model is brutal at *confidentiality against a thief or a kernel bug* and intentionally silent elsewhere:

- **A cooperating or compelled user.** The entire keystore opens the instant the *correct passcode* is entered, by design — Data Protection protects against someone *without* the secret, not against lawful compulsion or a shoulder-surfed code. A known passcode collapses Layers 0 and 3 outright; this is why "consent / known PIN" is the single most valuable fact in an acquisition and why the legal question of compelled passcode disclosure matters so much.
- **Data the user chose to expose.** Anything an app put in iCloud *without* ADP, shared to a third party, or backed up unencrypted is reachable by the path that holds it — the on-device stack can't retroactively protect data that left the device in the clear. The cloud and the recipient are separate trust domains.
- **Availability / anti-wipe.** The model optimizes **confidentiality**, not survival of the data. Effaceable-storage wipe (remote or local) is *engineered* to destroy keys instantly — the same crypto-erase that protects a lost phone also lets a suspect (or a remote command) brick the evidence in seconds. Radio isolation on seizure is the countermeasure, and it's a confidentiality-vs-availability tradeoff Apple resolved in the user's favor.
- **Metadata and behavioral residue.** Encryption hides *contents*, not *patterns*. The pattern-of-life stores (Biome/SEGB, `knowledgeC` legacy, PowerLog, `routined`) record that activity happened even when the payload is protected — much of Part 08's value lives in this gap between "the message is encrypted" and "the system logged that a message arrived."
- **Apple itself, and the supply chain.** The model trusts Apple's signing infrastructure and silicon fabrication as axioms. It does not (cannot) defend against a compromise *at* Apple or a malicious component inserted before the device reaches the user — those are outside the threat model, mitigated administratively, not cryptographically.

> 🔬 **Forensics note:** Read the non-goals as a *target list*. The model's silence on metadata is why a BFU device whose contents are ciphertext can still yield a behavioral timeline from the lower-protection-class system stores; its silence on a known passcode is why the first SOP question is always "do we have the code or lawful means to compel it"; its silence on un-ADP'd cloud data is why the cloud path stays alive exactly when the user *didn't* turn ADP on. Where the model declines to protect, the evidence accumulates.

### The macOS pillars, mapped

You arrived knowing three macOS defenses. Here is the precise conversion — same intent, made mandatory and hardware-rooted:

| macOS pillar (you know this) | iOS realization | The upgrade |
|---|---|---|
| **SIP** — protects system files/procs from root; toggle in 1TR (`csrutil`) | **SSV** (Merkle-sealed system volume) + **SPTM/TXM** page-table monitor + universal sandbox | A *flag root can clear* → a *cryptographic seal the bootloader enforces*, with no toggle |
| **Gatekeeper / notarization** — gates quarantined GUI downloads; shell bypasses it | **AMFI mandatory code signing**, enforced in-kernel per page; App Store review for distribution | *Distribution gate you can sidestep* → *execution gate with no escape* |
| **TCC** — per-app privacy consent prompts | **TCC** (same `tccd`/`TCC.db`) but **entitlement + purpose-string gated** | Consent *prompt* → consent gated by a *hardware-attested capability* the app must already hold |
| **FileVault** — one volume key, unlock-once | **Data Protection** — per-file keys × class keys × BFU/AFU | One boolean lock → a *lock-state matrix* per file |
| **Secure boot + LocalPolicy/1TR** — lowerable | **SecureROM → iBoot → kernel**, IMG4/SHSH, **no downgrade** | Same chain with the *escape hatch deleted* |

The single sentence to keep: **iOS is the macOS security model with the user demoted from trust-root to subject, and every "off" switch removed and replaced by a hardware attestation.** (The mechanism-by-mechanism version of this table, with the daemon and kext names, is the whole of [[macos-to-ios-mental-model-reset]] — this is the security-architecture framing of the same truth.)

### The forensic lens: every layer is a wall

Re-read the stack as an examiner and it stops being a defense diagram and becomes a **decision tree of walls**. Each layer is a place an acquisition attempt can stop dead, and competence is knowing *which wall you are standing at and why* — because the wall dictates the only moves that exist:

```
Want the data?  ──▶  which wall stops you?
   │
   ├─ Layer 1 (secure boot): SoC ≥ A14?  → no BootROM exploit → logical/cloud/0-day box only
   │                          SoC A8–A13? → BootROM exploit possible → FFS *if* passcode
   │
   ├─ Layer 0 + 3 (SEP + Data Protection):
   │        BFU?            → only Class D decrypts; you imaged ciphertext
   │        AFU/unlocked?   → Class C resident → most user data in reach
   │        passcode strong?→ SEP rate-limit makes brute force infeasible
   │
   ├─ Layer 4 (sandbox): on-device, no app reads another's data —
   │                     so you must go *below* it: FFS / backup reads APFS directly
   │
   └─ Layer 5 (services): ADP on? → cloud returns ciphertext → cloud path dead
```

Nothing in Part 07 escapes this picture. A logical backup stops at Layer 4/5 (what the backup protocol and Data Protection expose). A full-file-system pull needs a Layer-1 foothold *and* a Layer-0/3 key state. A cloud warrant lives or dies at Layer 5 (ADP). The examiner who can name the wall in the first five minutes of a seizure — *what SoC, what state, ADP or not* — has already scoped the entire engagement.

> ⚖️ **Authorization:** Naming the wall is a technical act; *going through it* is a legal one. Every method that defeats a layer here — booting a `checkm8`/`usbliter8` ramdisk, driving the SEP to test passcode guesses, serving legal process for an iCloud return — requires specific, documented lawful authority and a chain of custody recorded before you connect, because several of these steps **mutate device state** (a reboot alone can knock AFU→BFU and destroy evidence). The model tells you what is *possible*; your authorization defines what is *permitted*. → [[ios-forensics-landscape-and-authorization]].

### A map of the rest of this module

This lesson is the table of contents for the stack. Each layer above gets a dedicated lesson that drills it to mechanism depth:

| Lesson | Layer it drills | One-line focus |
|---|---|---|
| **00 — the-ios-security-model** *(here)* | the whole stack | the layered map + threat model + the wall lens |
| **01 — [[sep-sepos-deep-dive]]** | Layer 0 | sepOS, the UID/GID fuses, the keystore, secure boot of the SEP itself |
| **02 — [[data-protection-and-keybags]]** | Layer 3 | per-file/class keys, the keybag types, `cprotect`, crypto-erase |
| **03 — [[passcode-bfu-afu-and-inactivity]]** | Layer 0↔3 | passcode entanglement, BFU/AFU, SEP rate-limiting, inactivity reboot |
| **04 — [[code-signing-amfi-entitlements]]** | Layer 4 | AMFI, Code Directory, trust cache, provisioning, the entitlement system |
| **05 — [[the-sandbox-and-tcc]]** | Layer 4 | container profiles, brokered IPC, the TCC consent ledger |
| **06 — [[kernel-hardening-pac-sptm-txm-mie]]** | Layer 2 | the PAC→PPL→SPTM/TXM→Exclaves→MIE ladder |
| **07 — [[biometrics-security-architecture]]** | Layers 0/4 | Face ID/Touch ID enrollment, the SEP biometric pipeline, presence checks |
| **08 — [[keychain-on-ios]]** | Layers 0/3/5 | keychain protection classes, access groups, `securityd`, iCloud escrow |
| **09 — [[advanced-protections-lockdown-sdp-adp]]** | Layers 2/5 | Lockdown Mode, Stolen Device Protection, Advanced Data Protection |

Read them in order and the stack assembles bottom-up. Read any one in isolation and anchor it back to this map: *which layer am I in, what does it trust beneath it, and what wall is it for an examiner?*

### The stack at a glance

One reference table for the whole model — keep it within reach as you work the rest of Part 03 and Part 07:

| Layer | Core mechanism | Primarily defends against | The examiner's wall | Drilled in |
|---|---|---|---|---|
| **5 — Services** | E2EE, HSM escrow, SE, BlastDoor, **ADP** | cloud/server compromise, zero-click | ADP → cloud returns ciphertext | [[advanced-protections-lockdown-sdp-adp]] |
| **4 — App security** | AMFI signing, sandbox, entitlements/TCC | malware, trojan apps, cross-app theft | no app reads another → go below via FFS/backup | [[code-signing-amfi-entitlements]], [[the-sandbox-and-tcc]] |
| **3 — Data Protection** | per-file × class keys, keybag, BFU/AFU | device theft, dead-box extraction | BFU → only Class D; reboot re-locks | [[data-protection-and-keybags]] |
| **2 — OS integrity** | SSV Merkle seal, PAC→…→MIE ladder | runtime tamper, kernel exploit chains | sealed/hardened kernel — needs an exploit | [[kernel-hardening-pac-sptm-txm-mie]] |
| **1 — Secure boot** | SecureROM→iBoot→kernel, IMG4/SHSH | unsigned firmware, rollback, evil-maid | SoC ≥ A14 → no BootROM exploit | [[boot-chain-securerom-iboot]] |
| **0 — Hardware root** | SEP, fused UID/GID, inline AES, rate-limit | key extraction, offline brute force | keys never leave the chip; SEP throttles | [[sep-sepos-deep-dive]] |

The column that matters most on seizure is **the examiner's wall**: it is the same six facts, restated as the questions you ask in order — *ADP? sandbox-or-below? BFU/AFU? sealed kernel? SoC generation? passcode strength?* Answer those and the engagement is scoped.

## Hands-on

There is no device and no on-device shell. Everything here runs **on your Mac** and lets you *see the layers as shipped artifacts* — a firmware image is literally the boot-and-OS-integrity layers on disk, and the Simulator is iOS with the bottom layers *removed*, which makes their absence visible.

### See the layers in a real firmware (public IPSW, on the Mac)

`ipsw` (blacktop/ipsw) parses Apple firmware without any device. A `BuildManifest` is, in effect, the **secure-boot + OS-integrity layers enumerated**:

```bash
brew install blacktop/tap/ipsw

# Download a current public IPSW for a model you don't own (read-only research):
ipsw download ipsw --device iPhone18,1 --version 26.5      # or grab a URL from ipsw.me

# Enumerate the signed component set — these ARE Layer 1/2 on disk:
ipsw info iPhone18,1_26.5_*.ipsw
#   prints Version/Build/Device and the firmware component list:
#   LLB, iBoot, iBEC, iBSS, kernelcache, SEP firmware (sepi/sepf),
#   the APFS/root-fs DMG, the static trust cache, Ap,RestoreSEP, ...
#   Each line is an IMG4 payload that must be Apple-signed to boot.

# Look at the boot chain specifically:
ipsw img4 ... # extract/inspect an IMG4: payload tag, manifest, signature props

# And the Layer-4 root: list the static trust cache baked into the firmware —
# the in-kernel allow-list of platform-binary cdhashes AMFI honors without amfid:
ipsw kernel kexts <extracted-kernelcache>     # kext inventory of the verified kernel
ipsw fw tc <file>.ipsw                        # `fw tc` = dump TrustCache entries (cdhashes)
```

Each entry is a layer made concrete: `LLB`/`iBoot` (Layer 1), `kernelcache` + the static **trust cache** (Layers 2/4), the **SEP firmware** image (Layer 0), the sealed system **root filesystem** DMG (SSV, Layer 2). You are looking at the stack as bytes.

### Confirm the Simulator has *no* bottom layers (Simulator)

The Simulator is macOS frameworks in a folder — Layers 0–3 are simply absent, which is why its containers are plaintext:

```bash
xcrun simctl list devices available
xcrun simctl boot "iPhone 17 Pro"

# An app's data container is just an unencrypted directory on your Mac:
xcrun simctl get_app_container booted com.apple.MobileSMS data
#   /Users/you/Library/Developer/CoreSimulator/Devices/<UDID>/data/
#       Containers/Data/Application/<APP-UUID>
ls -la "$(xcrun simctl get_app_container booted com.apple.MobileSMS data)"
#   readable, no cprotect, no class key, no AMFI — the exact opposite of a device
```

There is no SEP to ask for a class key, no AMFI rejecting an unsigned page, no SSV seal — so the Simulator teaches *structure and schema* (Part 08 will lean on this hard) and *nothing at all* about encryption or lock state.

### Inspect a code signature — Layer 4 on the Mac (Simulator binary)

The app-security layer's verification is opaque on a device (it happens in-kernel), but the *signature it checks* is an ordinary Mach-O structure you can read on the Mac with `codesign`. A Simulator binary is a useful stand-in for the *shape* of the signature, even though its contents (ad-hoc, x86_64/arm64-macOS) differ from a shipped device binary:

```bash
APP="$(xcrun simctl get_app_container booted com.apple.MobileSMS app)"
BIN="$APP/$(defaults read "$APP/Info.plist" CFBundleExecutable)"

# The Code Directory + signature AMFI would verify page-by-page on a device:
codesign -dvvv "$BIN" 2>&1 | sed -n '1,20p'
#   Identifier=com.apple.MobileSMS ... CodeDirectory v=...  hashType=sha256
#   CDHash=...   (this is the cdhash a device's trust cache would list)
#   Signature=adhoc            ← Simulator/dev artifact; a device app is Apple/Team-signed

# The entitlements blob — the privilege currency of Layer 4:
codesign -d --entitlements :- "$BIN" 2>/dev/null | plutil -p - 2>/dev/null | head -30
```

The point is to *see* the three things AMFI cares about — the **cdhash** (what the trust cache or `amfid` checks), the **signer** (ad-hoc here, Apple/Team on a device), and the **entitlements** (the capabilities the app is allowed to claim). On a device these are enforced in-kernel with no override; here they are just readable structure. → [[code-signing-amfi-entitlements]].

### Read the model from the primary source (on the Mac)

```bash
# Fetch Apple's own layering and keep it open beside this lesson:
curl -L -o apple-platform-security-2026.pdf \
  https://help.apple.com/pdf/security/en_US/apple-platform-security-guide.pdf
# Its chapter order (hardware → system → encryption/Data Protection → app →
# services → network) is the same stack this lesson collapses into six layers.
```

> ⚠️ **ADVANCED:** Everything above is inert Mac-side research — parsing a firmware file, listing a Simulator folder, reading a PDF. The *device-side* counterparts (booting a `checkm8`/`usbliter8` ramdisk to reach Layer 0/1, driving the SEP to test passcodes) mutate or attack a real device, require lawful authority, and live behind ⚠️/⚖️ blocks in Part 07. Recognize the firmware components now; touch a device only under the SOP.

## 🧪 Labs

> All labs are **device-free**. Lab 1 uses a **public IPSW** (static firmware on your Mac — you see the signed component set, not a running SEP/keybag). Labs 2 and 5 use the **Simulator** (no SEP / no Data Protection / no AMFI / no SSV — they prove the bottom layers' *absence* and show Layer-4 signature *structure*, not enforcement). Labs 3–4 are **read-only / paper** (the Apple guide and a reasoning exercise). Where a substrate diverges from real hardware, the caveat says so.

### Lab 1 — Enumerate the boot-and-integrity layers in a real IPSW (public firmware)

**Substrate:** public IPSW + `ipsw`. **Fidelity caveat:** a firmware file is the *static, signed image set* — you can see Layer 1/2/0 *components*, but there is no running SEP, no keybag, and no lock state to observe.

1. `brew install blacktop/tap/ipsw`, then obtain a current public IPSW for a device you don't own (e.g. from ipsw.me).
2. Run `ipsw info <file>.ipsw` and list every firmware component. For each, label which layer of the stack it belongs to: `LLB`/`iBoot`/`iBEC` (Layer 1), `kernelcache` + trust cache (Layers 2/4), `sep`-firmware (Layer 0), the root-fs DMG (Layer 2 / SSV).
3. Note the **personalization** dimension: explain in one sentence why this same IPSW will *not* restore unless Apple's TSS issues a SHSH blob bound to a specific device's ECID — i.e. why Layer 1 is per-device, not per-build. → [[image4-personalization-shsh]].

### Lab 2 — Prove the bottom layers are absent on the Simulator (Simulator)

**Substrate:** Simulator. **Fidelity caveat:** the Simulator runs macOS frameworks — there is *no* SEP, Data Protection, AMFI, or SSV; this lab demonstrates the layers by their **absence**, never their behavior.

1. Boot a Simulator, run a stock app so a Data container exists, and `cat` a file straight out of its container with no key and no permission dance. State which two layers (0 + 3) make the identical read *impossible* on a device.
2. Note that you could drop and run an unsigned Mach-O slice here that a device's **AMFI** (Layer 4) would refuse in-kernel. Write the one-sentence reason the Simulator is useless for validating any code-signing or encryption claim.
3. Conclude: list the three things the Simulator *is* good for (schema, layout, parsing logic) and the three it can *never* show you (encryption at rest, lock-state/BFU-AFU, AMFI/sandbox enforcement).

### Lab 3 — Reconcile Apple's chapters to the six-layer stack (read-only walkthrough)

**Substrate:** the Apple *Platform Security Guide* PDF. **Fidelity caveat:** none — a documentation-mapping exercise.

1. Download the guide (Hands-on command). Open the table of contents.
2. For each of this lesson's six layers, find the matching Apple chapter(s) and write the section title next to it (e.g. *Hardware security → "Secure Enclave"*; *Encryption and Data Protection → the class table*).
3. Find one mechanism Apple documents that this lesson *didn't* name (candidates: secure intent, the Memory Protection Engine, Sealed Key Protection, recovery/escrow). Note which layer it belongs to — building the instinct to slot any new Apple security feature into the stack.

### Lab 4 — Name the wall (paper exercise, no substrate)

**Substrate:** none — a field-readiness drill on the forensic lens. For each scenario, name the **layer that stops you** and the single move it leaves open:

| Scenario | Wall (which layer) | Only move left |
|---|---|---|
| iPhone 17 Pro (A19), seized **BFU**, strong alphanumeric passcode | ? | ? |
| iPhone with A12, seized **AFU/unlocked**, passcode unknown | ? | ? |
| Suspect's iCloud, **ADP enabled**, valid legal process in hand | ? | ? |
| App-data-only question: "what did app X store?", device imaged | ? | ? |

Then answer: (a) For the A19-BFU row, why does the **SoC generation** (Layer 1) decide the outcome before the passcode (Layer 0) even matters? (b) For the AFU/unlocked A12 row, why is the **device state** worth more than the BootROM exploit? (c) For the ADP row, which single user setting turned a productive cloud target into ciphertext, and what does that tell you to verify *first* next time? (Check yourself against the wall diagram and the threat-model table — every answer is there.)

### Lab 5 — Read the Layer-4 signature an app carries (Simulator)

**Substrate:** Simulator binary + `codesign`. **Fidelity caveat:** a Simulator binary is **ad-hoc-signed macOS-arch code** — its cdhash, signer, and entitlements have the right *shape* but not a device app's *contents* (no FairPlay, no Apple/Team signature, fewer entitlements). You are reading structure, not watching AMFI enforce.

1. Resolve a stock app's executable (Hands-on block) and run `codesign -dvvv` on it. Record the **CDHash** and the **Signature** field. Explain what a device's **trust cache** would do with that cdhash for a *platform* binary vs. what `amfid` would do for a *third-party* one.
2. Dump the entitlements with `codesign -d --entitlements :- … | plutil -p -`. Pick two entitlements and state, in privilege terms, what each *authorizes* — and why on iOS that authority is the entire substitute for "becoming root."
3. Conclude: explain why `codesign` can only *show* you this signature on the Mac, but on a device the same blob is the thing checked **in-kernel, per executable page, with no override** — i.e. why reading the signature here is not the same as defeating Layer 4 there.

## Pitfalls & gotchas

- **Reasoning about iOS defenses as independent, lowerable toggles.** That is the macOS SIP/Gatekeeper/TCC mental model and it is wrong here: the layers are *stacked and load-bearing*, each verified by the one below, and **none has a supported off switch**. "I'll just disable X" has no iOS equivalent for any X in the stack.
- **Assuming a kernel compromise (jailbreak) collapses the whole stack.** It owns Layer 2 only. It does **not** forge a signature the SEP rejects, decrypt a **BFU** device, or read the fused UID — the layers fail independently *by design*. This is why even a jailbroken-but-BFU device is still mostly ciphertext.
- **Treating "the disk is imaged" as "the data is recovered."** Imaging captures ciphertext at Layer 3; recovery needs the keys, which live behind Layer 0 and depend on BFU/AFU state. The FileVault reflex ("unlocked once → all readable") is the single most common macOS-examiner error on iOS.
- **Forgetting the cloud is a separate wall.** Even with a perfect on-device picture, **ADP** (Layer 5) independently decides whether the iCloud path returns plaintext or blobs. Check ADP status *before* scoping a cloud effort.
- **Conflating the SEP with the Secure Element.** Two different chips: the **SEP** (sepOS, keys, Data Protection, biometrics) and the **SE** (Apple Pay/transit credentials, certified payment chip). Apple Pay's card data lives in the **SE** and never reaches the OS — a distinct trust domain from the SEP. → [[secure-enclave-hardware]].
- **Expecting to "just remount the system volume writable" like on a Mac.** The macOS SSV escape (`csrutil authenticated-root disable`) has no iOS analogue. Even on a jailbroken device the system volume is **SSV-sealed**; modern tooling works around it with an overlay/shadow mount or by rebuilding the seal, not by flipping a flag — persistence on the system volume is *hard by construction*, which is why so much implant/tweak machinery lives in memory or in writable data paths instead.
- **Validating any lower-layer claim on the Simulator.** The Simulator *has no* Layers 0–3. It is authoritative for schema and layout and worthless for encryption, lock state, or signing. Never "confirm" a Data-Protection or AMFI behavior there.
- **Mistaking "code execution" for "the keys."** A BootROM exploit, a kernel jailbreak, even root on the device all stop at Layer 0: they buy you *authority at their own layer*, not the SEP-held keys. The phrase "I got code execution" answers a different question than "I got the data," and conflating them is how acquisition timelines slip — you still need the passcode (or escrow bag, and only for AFU) to make the SEP release class keys.
- **Forgetting the model has deliberate non-goals.** It is silent on a known/compelled passcode, on data the user pushed to the cloud un-ADP'd, on instant anti-forensic crypto-erase, and on behavioral metadata. Treating the stack as if it protects *those* leads you to write off recoverable evidence that lives precisely in the seams it never promised to cover.
- **Writing the perishable facts as if durable.** The *layering* is stable; the catalog facts on top of it are not — SoC-to-mitigation mapping (SPTM/TXM = A15/M2+, MIE = A19/M5), the BootROM-exploit reach (A8–A13 as of June 2026), the ~72 h inactivity threshold, ADP availability, the SSV-since-iOS-15 line. Re-verify each against the current Platform Security Guide before relying on it in a report.

## Key takeaways

- iOS security is a **six-layer stack** — hardware root (SEP + fused keys) → secure boot → OS integrity → Data Protection → app security → services — where **each layer trusts only the one beneath it** and the chain terminates in silicon the user can never reach.
- Three properties separate it from macOS: it is **hardware-rooted** (the trust anchor is the fused UID, not an admin password), **mandatory** (no supported downgrade for any layer), and **layered/load-bearing** (compromising one layer does not collapse the others).
- The macOS pillars map directly but *upgraded*: **SIP → SSV + SPTM/TXM**, **Gatekeeper → AMFI in-kernel signing**, **TCC → entitlement-gated TCC**, **FileVault → per-file Data Protection** — same intent, made mandatory and hardware-attested, with every "off" switch removed.
- The model is engineered against a **named threat spectrum** — opportunistic theft, commodity malware, forensic extraction, nation-state/mercenary spyware, evil-maid, cloud compromise — and the **OS-integrity ladder (PAC→PPL→SPTM/TXM→Exclaves→MIE)** plus Lockdown Mode is the explicit answer to the zero-click-spyware end of it.
- For an examiner, **every layer is a wall**, and the engagement is scoped by naming the wall: **SoC generation** (Layer 1 — BootROM reach A8–A13), **passcode strength + BFU/AFU state** (Layers 0/3), and **ADP** (Layer 5) decide what is recoverable before any tool runs.
- Two SOP reflexes fall straight out of the lower layers: **never reboot a seized device** (it drops AFU→BFU) and **identify the SoC first** (it decides the whole acquisition tree).
- The **Simulator** shows the upper-layer *structure* but **none of the bottom four layers** (no SEP, Data Protection, AMFI, or SSV) — use it for schema, never for encryption, lock-state, or signing claims.
- This lesson is the **module map**: each later Part 03 lesson drills one layer to mechanism depth; anchor each one back here by asking *which layer, what does it trust below, what wall is it for an examiner*.

## Terms introduced

| Term | Definition |
|---|---|
| Apple Platform Security Guide | Apple's canonical security documentation (current edition March 2026); its chapter order mirrors the six-layer trust stack. |
| Trust stack | The six-layer model: hardware root → secure boot → OS integrity → Data Protection → app security → services, each verified by the layer beneath. |
| Hardware root of trust | The fused, immutable base of the chain — the SEP, Boot ROM, and the UID/GID keys burned into the SoC that no software can read. |
| UID / GID (fused keys) | Per-device (UID) and per-model (GID) keys fused in silicon; usable by the SEP's AES engine but never extractable, anchoring all higher-layer secrets. |
| Secure Enclave (SEP) | Isolated coprocessor running sepOS; derives Data-Protection class keys, guards biometrics/keys, rate-limits passcode attempts in hardware. |
| Secure Element (SE) | A separate certified chip holding Apple Pay/transit/access credentials; communicates NFC↔SE over a dedicated bus so card data never reaches the OS. |
| Memory Protection Engine | SEP DRAM protection that encrypts + integrity-tags Secure Enclave memory so a compromised application processor cannot read it. |
| Secure boot chain | SecureROM → iBoot → kernelcache, each stage executing the next only if Apple-signed; no LocalPolicy/downgrade exists on iOS. |
| IMG4 / SHSH / APTicket | The signed firmware container (IMG4) and the per-device personalization/anti-rollback blob (SHSH/APTicket) binding approved hashes to a device's ECID. |
| Signed System Volume (SSV) | Merkle-tree-sealed read-only system volume (since iOS 15); the root-hash **seal** is verified at boot and on every read, replacing SIP's mutable flag. |
| Seal (SSV root hash) | The single hash at the top of the SSV Merkle tree that cryptographically covers every byte of the system volume. |
| Kernel-hardening ladder | The escalating runtime memory defenses: KTRR → PAC → PPL → SPTM/TXM (A15/M2+) → Exclaves (A18/M4-era) → MIE (A19/M5). |
| SPTM / TXM | Secure Page Table Monitor + Trusted Execution Monitor — a hypervisor-grade layer above the kernel owning page-table changes and code-signing/entitlement checks. |
| MIE | Memory Integrity Enforcement — always-on hardware memory-tagging across kernel and userland on A19/M5 (iPhone 17/Air/Pro). |
| Data Protection class | One of A/Complete, B/CompleteUnlessOpen, C/UntilFirstUserAuthentication (default), D/None — governs when a file's key is available vs. lock state. |
| BFU / AFU | Before/After First Unlock — whether the passcode has been entered since boot; determines which class keys are resident and thus what decrypts. |
| AMFI | Apple Mobile File Integrity — kernel + `amfid` mandatory code-signing enforcement; verifies each executable page against the signed Code Directory in-kernel. |
| Trust cache / cdhash | The in-kernel list of approved code-directory hashes (**cdhash**es) for platform binaries; lets Apple's code load without an `amfid` round-trip. |
| Advanced Data Protection (ADP) | Opt-in extension of iCloud end-to-end encryption to most categories; removes Apple's (and an examiner's) ability to read a cloud return. |
| Lockdown Mode | User-selectable extreme posture that disables high-risk attack surface (JIT, some message parsing, wired connections) against mercenary spyware. |
| BlastDoor | Tightly-sandboxed iMessage parsing service, a structural defense against zero-click message-parser exploits. |
| Wall (forensic lens) | A layer at which an acquisition attempt stops; competence is naming which wall a given device/state presents and the only move it leaves. |

## Further reading

- **Apple Platform Security Guide** (security.apple.com / help.apple.com/pdf/security) — the primary source; its chapter order *is* this stack. Read "Intro to Apple platform security," "Secure Enclave," "Signed System Volume security," "Data Protection classes," "NFC & SE platform security."
- **Apple Security Research** (security.apple.com/blog) — "Memory Integrity Enforcement: A complete vision for memory safety in Apple devices" — MIE on A19/M5, the EMTE/tagging design.
- **arXiv:2510.09272**, *Modern iOS Security Features — A Deep Dive into SPTM, TXM, and Exclaves* — the authoritative academic treatment of the Layer-2 ladder (SPTM/TXM A15/M2+, Exclaves A18/M4-era).
- **8ksec.io**, "MIE Deep Dive (kernel)" and **antid0te.com** SPTM/TXM/SK/Exclaves training notes — practitioner-grade detail on the OS-integrity layer.
- **Jonathan Levin**, *MacOS and iOS Internals* vols I–III + newosxbook.com — AMFI/trust-cache, the SEP, the sandbox machinery, lockdownd internals across the whole stack.
- **theapplewiki.com** — IMG4/SHSH personalization, `checkm8`/`usbliter8`, the boot-chain component names you saw in `ipsw info`.
- **blacktop/ipsw** (github.com/blacktop/ipsw) — the Mac-side firmware parser used in the labs; `ipsw info`, `ipsw img4`, trust-cache and kernelcache tooling.
- **Elcomsoft / Magnet / Cellebrite** blogs — the commercial-forensics view of the BFU/AFU wall, SoC-bounded acquisition, and ADP's impact; read critically and re-verify version claims.
- **Sarah Edwards** (mac4n6.com) & **SANS FOR585** — the practitioner discipline for turning the lower layers' constraints into an acquisition plan, and the metadata/behavioral seams the model leaves open.
- **Apple Support** — "Activation Lock," "Stolen Device Protection," and "Advanced Data Protection for iCloud" articles — the user-facing settings that, for you, decide the anti-theft and cloud-acquisition outcomes named in Layer 5.
- `man simctl` · `ipsw --help` · `man codesign` — exact flags for the device-free Mac-side tooling.

---
*Related lessons: [[macos-to-ios-mental-model-reset]] | [[secure-enclave-hardware]] | [[sep-sepos-deep-dive]] | [[data-protection-and-keybags]] | [[passcode-bfu-afu-and-inactivity]] | [[code-signing-amfi-entitlements]] | [[the-sandbox-and-tcc]] | [[kernel-hardening-pac-sptm-txm-mie]] | [[advanced-protections-lockdown-sdp-adp]] | [[the-acquisition-taxonomy]]*
