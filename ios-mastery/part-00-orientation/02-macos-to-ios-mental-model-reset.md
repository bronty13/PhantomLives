---
title: "macOS → iOS: the mental-model reset"
part: "00 — Orientation"
lesson: 02
est_time: "45 min read + 20 min labs"
prerequisites: [ios-platform-landscape-and-history]
tags: [ios, security-model, sandbox, mental-model]
last_reviewed: 2026-06-26
---

# macOS → iOS: the mental-model reset

> **In one sentence:** every instinct that made you fast on a Mac — drop to a shell, `chmod +x` a binary, `sudo` past a permission, read another app's `~/Library`, trust one FileVault key to unlock the whole disk — is a trap on iOS, where there is no user shell, unsigned code cannot execute at all, every app lives in its own mandatory sandbox, files are encrypted per-class against the lock state, and the only privileged seat is a **tethered Mac** speaking a pairing-gated wire protocol.

## Why this matters

You just spent a course learning macOS as an *open* UNIX: a multi-user BSD with a root account, a writable home directory, `launchd` agents you author, a Terminal that is the seat of power, and FileVault as a single full-volume lock. iOS is built from the *same XNU kernel and the same frameworks*, and that shared DNA is exactly what makes it dangerous to reason about — the names are familiar (`launchd`, `Mach`, `dyld`, APFS, the Keychain) but the **policy layer wrapped around them is inverted**. iOS is a locked-down appliance where the defaults macOS treats as opt-in (sandboxing, mandatory code signing, fine-grained encryption) are *mandatory and inescapable*, and the affordances macOS gives you for free (a shell, arbitrary `exec`, a browsable filesystem) **simply do not exist**.

If you carry your macOS reflexes onto an iPhone — as an engineer *or* as a forensic examiner — you will reach for tools that aren't there, assume access you don't have, and misjudge what is even recoverable. The examiner who reboots a seized phone "to be safe" just destroyed most of the evidence; the developer who expects to `ssh` in and tail a log is looking for a door that was never built; the reverse-engineer who studies the Simulator binary is analyzing the wrong artifact. Each of those is a *macOS habit firing in the wrong environment*. This lesson is the reflex-breaker: six hard resets, each at mechanism depth, plus the single principle they all descend from, so the rest of the course lands on rebuilt foundations.

## Concepts

Six resets. Each is a place where a macOS habit fails, *why* it fails (the daemon, the kernel check, the on-disk structure), and a forward pointer to the lesson that drills it. First, though, anchor what you *keep*.

### What carries over, what's inverted, what's gone

The trap is assuming iOS is "a different OS." It isn't — it's the **same kernel and frameworks under an inverted policy layer**. Knowing which of your macOS knowledge transfers verbatim, which transfers but flips, and which evaporates is the whole game:

| Carries over **unchanged** | Carries over but **inverted/restricted** | **Gone entirely** |
|---|---|---|
| XNU (Mach + BSD), Mach ports & IPC | `launchd` (system **LaunchDaemons** only — no user agents) | A user shell / Terminal |
| `dyld` + the dyld shared cache | Code signing & AMFI (mandatory, in-kernel, no override) | `sudo` / interactive root / login |
| APFS, the volume/container model | The sandbox (universal, not opt-in) | Browsable `~` and `/` for the user |
| Mach-O, the code-signature format | `TCC.db`/`tccd` (entitlement-gated, not just prompts) | Arbitrary `fork`/`exec` of your binaries |
| Foundation / Obj-C & Swift runtime, GCD | Keychain (hardware-bound, per-app access groups) | User `cron` / `LaunchAgents` |
| Unified logging (`os_log`, `.tracev3`) | FileVault → Data Protection (per-file, lock-state-aware) | A supported "lower the security policy" mode |
| The Keychain *API* surface | Secure boot (no `1TR`/LocalPolicy downgrade) | SSH, a package manager, `/usr/local` |

Everything in column one you already know cold — reuse it. Everything in column two is where this lesson lives. Column three is the set of reflexes to amputate.

### Reset 0 — the frame: a single-user appliance, not a multi-user computer

macOS is a multi-user BSD: `/etc/passwd`, `uid 0`, login windows, `su`/`sudo`, per-user homes under `/Users/`. iOS keeps the BSD *machinery* (XNU is still a Mach/BSD hybrid; there is still a `root` uid and a `mobile` uid) but presents as a **single-user appliance**. There is exactly one human, there is no login, and the uids that matter are a fixed cast — `root` (uid 0, system daemons), `mobile` (uid 501, where SpringBoard and all third-party apps run), and a handful of service uids (`_securityd`, `wireless`, `mDNSResponder`, …). You never log in as `root`; nothing you touch as a user runs as `root`. The whole "elevate to admin" mental model is gone — privilege on iOS is expressed through **entitlements** baked into a code signature, not through a uid you can escalate to. Hold that thought; it recurs in every reset below.

> 🖥️ **macOS contrast:** On the Mac, the power gradient is `user → admin → root → root-with-SIP-disabled`, and you climb it with `sudo`, an admin password, or a Recovery-mode `csrutil disable`. On iOS there is no ladder to climb from inside the device at all. The closest analogue to "disable SIP" is *jailbreaking* — and unlike `csrutil`, that is not a supported toggle but a chain of memory-corruption exploits against a hardened kernel (see [[07-the-jailbreak-landscape-2026]]).

### Reset 1 — no user shell, no Terminal, no browsable POSIX home

There is **no shell on iOS**. No Terminal.app, no `/bin/zsh` you can reach, no SSH server, no `bash_history` to dump. A stock device exposes no command interpreter to the user *or* to apps. The POSIX layer exists — XNU still has `fork`/`execve`/`posix_spawn`, `/bin/sh` is even present in the dyld shared cache's worldview — but nothing user-facing can invoke it, and (Reset 2) nothing you could drop there would be allowed to execute anyway.

There is also **no browsable home**. macOS gives every user a `~` they own and can roam with Finder or `cd`. On iOS, the filesystem *exists* (APFS, the same `/`, `/var`, `/private` layout you know) but the user is never given a view of it. The Files app shows you a curated set of document providers — iCloud Drive, On My iPhone, app containers that opted in — not `/`. From an app's perspective its *entire* visible universe is its own sandbox container (Reset 3). From the *human's* perspective there is no filesystem at all; there are apps.

There is no **user automation layer**, either. macOS lets *you* author `~/Library/LaunchAgents` plists and `cron` jobs that run as your uid on your schedule. iOS keeps `launchd` as PID 1 but exposes **no user-writable agent directory and no `cron`** — every persistent job is a system **LaunchDaemon** Apple ships, and an app's only sanctioned "background execution" is the tightly-budgeted, OS-arbitrated background-task APIs (BGTaskScheduler, background URLSession, etc.), not a daemon you register. The user-facing automation surface that *does* exist — Shortcuts — is a sandboxed, brokered app, not a shell (Part 06). So "I'll just add a launchd job / cron line" is two reflexes gone at once.

The consequence for you, the operator: **privileged work happens off-device, on a tethered Mac.** Want to enumerate installed apps, pull a log archive, read a crash report, install a debug build, list the filesystem of an app you own? None of that is typed into the phone. It is driven from a Mac over USB/Wi-Fi through the lockdown service stack (Reset 5). Internalize this now: *the iPhone is not where you do the work; it is the thing the work is done **to**, from a Mac.*

```
   macOS (your seat of power)                 iOS (the appliance)
 ┌──────────────────────────┐             ┌────────────────────────┐
 │ Terminal → zsh           │             │  (no shell)            │
 │ Finder → ~/ , /          │   USB/      │  SpringBoard → apps    │
 │ sudo / root              │ ──Wi-Fi──▶  │  uid mobile, sandboxed │
 │ libimobiledevice / Xcode │  lockdownd  │  lockdownd :62078      │
 └──────────────────────────┘             └────────────────────────┘
        the operator                          the subject
```

> 🔬 **Forensics note:** "No shell" reshapes the whole acquisition model. You cannot live-respond on the box — there is no `lsof`, no `dd`, no `ps` you can run *on the phone*. Every byte you extract crosses the USB tether through Apple's own services (AFC, `mobilebackup2`, the diagnostics relay), which means what you can collect is bounded by what those services expose and by the device's **lock state** (Reset 4). The artifacts are rich (Part 08) but the *path to them* is the tethered protocol, not a terminal. → [[04-logical-acquisition-with-libimobiledevice]].

### Reset 2 — signed-code-only: AMFI rejects unsigned pages in-kernel

This is the single biggest break. On macOS you can compile a binary, `chmod +x`, and run it; Gatekeeper/notarization only gate *quarantined, GUI-launched* apps, and you can always `xattr -d com.apple.quarantine` or run from Terminal to sidestep them. **On iOS there is no such escape, because the enforcement is not a userspace policy check — it is a kernel page-fault check that every executable page must pass.**

The enforcer is **AMFI — Apple Mobile File Integrity** — split across `AppleMobileFileIntegrity.kext` (in-kernel) and the `amfid` userspace daemon. The mechanism:

- Every Mach-O on iOS carries an embedded **code signature** with a **Code Directory**: a table of SHA-256 hashes, *one per memory page* of the executable.
- When the kernel maps a page executable (sets `VM_PROT_EXECUTE`), the VM subsystem demands that page's hash match the signed Code Directory. The check happens lazily, at fault-in time, page by page.
- For **platform binaries** (Apple's own code), the expected hashes are pre-loaded in the **trust cache** — an in-kernel list of approved cdhashes — so no userspace round-trip is needed.
- For **third-party apps**, the kernel can't judge the signer, so AMFI calls up to `amfid`, which validates the CMS signature, the embedded **provisioning profile**, and the entitlements, then hands the verdict back down.
- A page whose hash doesn't verify is **never made executable.** There is no warning dialog and no override: the mapping fails, and a process that tries to run unsigned code is killed (`CS_KILL`).

What dies with this model, concretely:

| macOS habit | Why it fails on iOS |
|---|---|
| `chmod +x ./tool && ./tool` | `+x` is meaningless — the page still has no valid signature; the exec fault fails. |
| `cc -o evil evil.c && ./evil` | No compiler on device, and even a cross-compiled binary has no signature the trust cache or `amfid` will accept. |
| `fork()` + `exec()` an arbitrary binary from an app | The spawned image must be signed and entitled; arbitrary binaries are refused. Apps don't get to launch helper executables. |
| Generate machine code and jump to it (JIT) | Writable-and-executable (W^X) memory is forbidden by default. You cannot mark a page `RWX`. |

That last row is the subtle one. JIT — JavaScript engines, emulators, some Frida modes — needs to *write* code at runtime and then *execute* it, which is exactly the W→X transition AMFI forbids. iOS allows it only for a process holding the **`dynamic-codesigning`** entitlement (held by WebKit's JIT-bearing processes and almost nothing else), which lets the kernel grant a single `MAP_JIT` region under tight rules. A normal third-party app can never get this entitlement from Apple, which is why on-device interpreters historically shipped in slow interpreter-only mode. This is *the* reason dynamic instrumentation on iOS is hard and why so much RE tooling needs a jailbreak to inject at all (Part 11).

**How a third-party app gets to run at all**, then, is the inverse of the Mac. There is no `chmod`; there is a *chain of trust attached to the signature*. An App Store binary is **App-Store-signed** by Apple and its cdhashes are honored device-wide. A development or ad-hoc build is signed with your certificate and must carry an embedded **provisioning profile** — a CMS-signed blob, validated by `amfid`, that ties together (a) the signing certificate, (b) the **App ID** and team, (c) the list of **device UDIDs** the build may run on, and (d) the **entitlements** the app is allowed to claim. AMFI cross-checks the binary's requested entitlements against what the profile authorizes; ask for an entitlement the profile doesn't grant and the app won't launch. That is the deep point of Reset 0 made concrete: on iOS, **privilege is a property of your signed entitlements, not of a uid you can become.** "Can this code do X?" is answered at sign/verify time by the entitlement set, not at runtime by `sudo`. Free (personal-team) provisioning is the seven-day, device-pinned version of the same machinery — the reason a self-signed dev build expires and stops launching after a week. → [[06-code-signing-and-provisioning-in-depth]].

> 🖥️ **macOS contrast:** macOS has the *same machinery* — AMFI, code signing, the hardened runtime — but as **opt-in policy**, not a wall. Notarization gates download-quarantined apps; the hardened runtime's JIT restriction is unlocked by the `com.apple.security.cs.allow-jit` entitlement, which any developer can self-sign. Crucially, macOS lets you run **unsigned and ad-hoc-signed** code freely from the shell; only *distribution* is gated. iOS gates *execution itself*: "all executable pages are signed and verified in-kernel" is the default and there is no `--no-sandbox`-style backdoor. The Mac's `spctl`/Gatekeeper is a doorman; iOS's AMFI is a law of physics. → [[04-code-signing-amfi-entitlements]], [[07-dyld-shared-cache-and-amfi]].

> 🔬 **Forensics note:** Because *all* legitimately running code is signed and (for platform binaries) trust-cached, the appearance of a process whose binary is **not** in the trust cache, **not** App Store / TestFlight / enterprise-signed, or running from an unusual path, is itself a strong tampering signal — the substrate of jailbreak/implant detection. Pegasus-class implants historically had to live entirely in *already-signed-and-running* processes (memory-only, no new binary on disk) precisely because dropping an unsigned executable would never run. mvt's job (Part 09) is partly to find the side-effects such memory-resident code leaves in *signed* stores.

### Reset 3 — the sandbox is everywhere and mandatory (not opt-in)

On macOS, the App Sandbox is something a developer *chooses* (the `com.apple.security.app-sandbox` entitlement, required for the Mac App Store but optional otherwise). Plenty of Mac software — Homebrew, your dev tools, anything from a `.pkg` — runs **unsandboxed** with the full reach of your uid across `~/Library`, `/usr/local`, other apps' data, the lot.

**On iOS, the sandbox is universal and non-negotiable.** Every third-party app — and most system apps — runs inside a per-app **container** enforced by the same Sandbox kernel extension (the `Seatbelt`/`sandbox.kext` machinery you met on the Mac) plus a per-app profile applied at launch by `launchd`/`amfid`. There is no entitlement to turn it off. An app cannot see the filesystem outside its container, cannot enumerate other apps' data, cannot read `/var/mobile` at large. Inter-app data flows only through *brokered* channels — share sheets, `UIDocumentPicker`, pasteboard, App Groups, URL schemes — never raw file paths.

The on-disk shape every iOS examiner and developer must know cold: each app is split into **two** containers with different lifetimes and trust:

```
/private/var/containers/Bundle/Application/<UUID-A>/
        MyApp.app/                ← the BUNDLE container (code, signed, read-only)
            MyApp                  (the Mach-O, signed)
            Info.plist, assets, _CodeSignature/

/private/var/mobile/Containers/Data/Application/<UUID-B>/
        Documents/                ← the DATA container (user data, read-write)
        Library/                     Preferences/, Caches/, Application Support/
        tmp/
        .com.apple.mobile_container_manager.metadata.plist   ← maps UUID → bundle ID
```

Two separate random UUIDs, in two separate trees:

- The **Bundle container** holds the `.app` — the signed, **read-only** code and resources. It is re-randomized and the code re-validated on install/update.
- The **Data container** holds everything the app writes: `Documents/`, `Library/Preferences/` (the per-app plist), `Library/Caches/`, `tmp/`. This is the forensic motherlode.
- The two UUIDs are *not* the bundle ID and are *not* stable across reinstalls. The mapping back to a human-readable bundle ID lives in the `.com.apple.mobile_container_manager.metadata.plist` (key `MCMMetadataIdentifier`) inside each container — that's how `iLEAPP` and friends label the anonymous UUID directories.

Apps that genuinely need to share *do* have channels, but every one is **brokered and entitlement-gated**, never a raw path:

- **App Groups** (`com.apple.security.application-groups`) — a *third* shared container under `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/`, writable only by apps signed into the same group (e.g. an app and its widget/extension). Forensically valuable precisely because it's where an app and its extensions stash *shared* state.
- **Keychain access groups** — credentials shared across an app's own family, mediated by `securityd`, not the filesystem (→ [[08-keychain-on-ios]]).
- **`UIDocumentPicker` / share sheet / pasteboard / custom URL schemes / Universal Links** — user- or system-mediated hand-offs of *specific* items, not directory access.

There is no "an app reads another app's files" primitive anywhere in that list. The only thing that sees *all* containers at once is something operating **below** the sandbox: the filesystem itself.

The privacy layer also differs in shape from the Mac. macOS funnels consent through **TCC** (`TCC.db`, the `tccd` daemon, the Privacy pane). iOS uses the same `tccd`/`TCC.db` plumbing for the *consent ledger*, but the **gate is the entitlement-plus-purpose-string**: an app that wants the camera, photos, contacts, or location must (a) carry the matching capability and (b) declare a `NS…UsageDescription` purpose string in its `Info.plist`, or the API traps at call time before any prompt even appears. Consent you grant is recorded per-app in `TCC.db`, a juicy artifact for "did this app ever have location/mic/camera access, and when."

> 🖥️ **macOS contrast:** The Mac *has* the same container concept — sandboxed Mac apps store data under `~/Library/Containers/<bundle-id>/Data/` — but (a) it's **opt-in**, so vast swathes of Mac software ignore it and write straight into `~/Library`, and (b) the directory is named by **bundle ID**, human-readable. iOS makes containers **mandatory** and names them by **opaque UUID**, so step one of any iOS app analysis is resolving UUID→bundle-ID via the metadata plist. Your Mac instinct of "just look in `~/Library/Application Support/<App>`" becomes "find the right UUID under `Containers/Data/Application/`." → [[00-app-sandbox-and-filesystem-layout]], [[05-the-sandbox-and-tcc]], [[05-the-app-sandbox-from-the-developer-side]].

> 🔬 **Forensics note:** Because the sandbox forbids cross-app reads *on the device*, almost nothing on a live phone can hoover up "all apps' data" — but a **filesystem-level acquisition** (full file system / backup) sidesteps the sandbox entirely: you're reading APFS from outside, so every Data container is laid bare at once, subject only to Data-Protection key availability (Reset 4). The sandbox protects apps **from each other at runtime**; it does **not** encrypt their data against an examiner who has the volume and the keys. → [[08-filesystem-layout-and-containers]], [[05-full-file-system-acquisition]].

### Reset 4 — Data Protection ≠ FileVault: per-file keys, class keys, a keybag, and the lock state

You know FileVault: **one** volume, encrypted with **one** key (the VEK), unwrapped once at login by your password (entangled with the Secure Enclave on Apple Silicon). After that single unlock, the entire volume is transparently readable for the whole session. It is *binary* — locked, or unlocked-and-all-readable.

iOS **Data Protection** is a different and far finer-grained design, and getting this wrong is the number-one way macOS examiners misjudge what's recoverable. Instead of one volume key:

- **Every file gets its own random per-file key**, generated at creation, used to AES-encrypt that file's contents.
- Each per-file key is itself **wrapped (encrypted) by a class key**, chosen from a small set of **Data Protection classes**. The wrapped per-file key is stored in the file's metadata (the APFS `cprotect` extended field).
- The **class keys** live in the **system keybag**, and *they* are wrapped by keys derived from the **passcode entangled with the SEP's hardware UID** (so the wrap can only be undone on *this* device, *with* the passcode).

The wrap chain — read it bottom-up; this is the structure FileVault flattens into a single link:

```
   passcode  ──entangled with──▶  SEP hardware UID key  (this device only)
        │                              │
        └────────── derive ────────────┘
                       │
                       ▼
              class key (one per Data-Protection class, in the system keybag)
                       │  wraps
                       ▼
              per-file key (random, one per file)
                       │  AES-encrypts
                       ▼
              file contents on NAND
```

Break any link and the file is ciphertext: no passcode → no class key derivation (that's BFU); class key evicted on lock → Class A unreadable; destroy the keybag-wrapping blob in effaceable storage → *every* per-file key is gone at once (crypto-erase). There are also distinct **keybag types** — the **system** keybag (above), plus **backup**, **escrow** (the pairing-record bag of Reset 5), and **iCloud** keybags — each re-wrapping the class keys for a different unlock path. The classes — memorize these, they govern *everything* downstream in forensics:

| Class | API constant | Key available when… | Typical contents |
|---|---|---|---|
| A — Complete | `NSFileProtectionComplete` | only while **unlocked**; evicted on lock | the most sensitive app data |
| B — Complete Unless Open | `NSFileProtectionCompleteUnlessOpen` | open files stay usable when locked (asymmetric/Curve25519) | downloads that finish while locked |
| C — Until First Unlock | `NSFileProtectionCompleteUntilFirstUserAuthentication` | from **first unlock after boot until shutdown** | **the default for most files** |
| D — None | `NSFileProtectionNone` | always (key wrapped only by hardware UID) | data needed before unlock |

Now the two lock states that fall straight out of this design — and that have no macOS equivalent:

- **BFU — Before First Unlock:** the device has booted but no one has entered the passcode *even once*. The class A/B/C keys are still **wrapped by the passcode** and absent from memory; only Class D (UID-only) data is readable. A BFU device is a near-brick to an examiner: you can image the encrypted blocks, but almost nothing decrypts.
- **AFU — After First Unlock:** the passcode has been entered at least once since boot. Class C keys (and A/B while unlocked) are now **derived and resident in the SEP/kernel keystore**, and they stay resident across subsequent screen-locks until reboot. Since Class C is the *default*, an AFU device exposes the **vast majority** of user data to a capable acquisition — even with the screen currently locked.

The whole BFU↔AFU distinction is why iOS forensics is obsessed with **device state on seizure**: an AFU phone is a goldmine; the same phone after a reboot is BFU and most of it goes dark. And it's why Apple added the **inactivity reboot** — since iOS 18.1, the SEP tracks time-since-last-unlock, and after **~72 hours** idle the `AppleSEPKeyStore` kernel module (driven by the SEP and surfaced via the `keybagd` daemon) forces a reboot, deliberately knocking the device **AFU → BFU** to shrink the window an examiner has. *(Mechanism is durable; the exact 72 h threshold is the perishable bit — verify against the current release.)*

```
   BOOT ──▶  BFU  ──(passcode entered once)──▶  AFU  ──(stays AFU across screen-locks)──┐
              │  only Class D readable          │  Class C resident → most data readable │
              │                                 └──(reboot, or ~72h inactivity reboot)───┘
              └──────────────────  back to BFU on every reboot  ◀──────────────────────
```

> 🖥️ **macOS contrast:** FileVault is the *coarse* cousin — one VEK, one unlock, all-or-nothing, and once unlocked it stays unlocked for the whole session with no per-file classes and no "re-lock on screen-lock." iOS Data Protection takes the same SEP-rooted key-derivation idea and shatters it into per-file keys under a handful of lock-state-aware class keys, so "is it readable?" depends not on one boolean but on (file's class) × (current BFU/AFU/unlocked state). The macOS reflex "if I can unlock the disk I can read everything" is *wrong* on iOS: even with the volume mounted, a Class A file on a locked device is ciphertext. → [[02-data-protection-and-keybags]], [[03-passcode-bfu-afu-and-inactivity]], [[02-bfu-vs-afu-and-data-protection-classes]], [[03-storage-nand-aes-effaceable]].

> 🔬 **Forensics note:** Two operational rules follow directly. (1) **Never reboot a seized device** — a reboot throws away every resident Class C key and drops you to BFU. (2) **Keep it powered and from going idle** (and ideally radio-isolated to block remote wipe) to beat the inactivity-reboot timer. The keys you're racing against don't live on disk to be copied — they're derived in the SEP and exist only in volatile keystore memory while AFU. Wiping the device's **effaceable storage** (where the keybag-wrapping `BAG1`/`EMF` blobs live) is also how a remote wipe achieves *instant* crypto-erase: destroy those few hundred bytes and every per-file key on the NAND is permanently unrecoverable. → [[03-storage-nand-aes-effaceable]], [[01-sep-sepos-deep-dive]].

### Reset 5 — the tethered Mac is the only privileged interface (usbmuxd / lockdownd / AFC / pairing)

Because there's no on-device shell (Reset 1) and no way to drop your own tooling (Reset 2), **all privileged interaction funnels through one channel: a paired, tethered Mac talking to the on-device lockdown daemon.** This is the protocol stack every Mac forensics/dev tool — Finder, Xcode, `libimobiledevice`, `pymobiledevice3`, Cellebrite, GrayKey's logical path — sits on top of. Learn its layers:

```
 Mac side                                      Device side
 ┌─────────────────────────────┐               ┌──────────────────────────────┐
 │ Xcode / libimobiledevice /  │   TCP-over-   │ lockdownd  (TLS, port 62078) │
 │ pymobiledevice3 / Finder    │   USB or      │   ├─ com.apple.afc           │
 │            │                │   Wi-Fi       │   ├─ com.apple.mobilebackup2 │
 │        usbmuxd  ◀───────────┼───────────────┤   ├─ com.apple.crashreport…  │
 │  (/var/run/usbmuxd socket)  │  multiplexed  │   ├─ com.apple.os_trace_relay│
 │            │                │  numbered     │   ├─ com.apple.mobile.       │
 │   pairing record ───────────┼──── ports ────┤   │     installation_proxy   │
 │  /var/db/lockdown/<UDID>.   │               │   └─ com.apple.springboard…  │
 │  plist (host+device certs,  │               │                              │
 │  escrow bag)                │               │                              │
 └─────────────────────────────┘               └──────────────────────────────┘
```

The pieces:

- **`usbmuxd`** ("USB multiplexing daemon") runs *on the Mac* (`/var/run/usbmuxd`). The device exposes a single USB endpoint; `usbmuxd` multiplexes many logical TCP connections — one per service — over it, and also handles Wi-Fi-sync discovery. Every higher tool dials `usbmuxd`, not the USB bus directly.
- **`lockdownd`** runs *on the device* (TLS-protected, port **62078**). It's the front desk: after a TLS handshake it *starts services on demand* and hands back a port for each. You don't talk to services directly; you ask `lockdownd` to start one.
- **The pairing record** is the trust anchor. The first time a Mac connects, the user must tap **"Trust This Computer"** and enter the passcode; the device and host exchange certificates and the host stores a **pairing record** at **`/var/db/lockdown/<UDID>.plist`** (SIP-protected — reading it needs root/Full Disk Access). That plist holds the host certificate, the device certificate/keys, and crucially an **escrow bag**.
- **The escrow bag** is the forensic crown jewel: it lets a trusted host **unlock the keybag of an AFU device without the passcode**, enabling logical extraction from a locked-but-AFU phone. Seizing a suspect's *computer* and lifting its pairing records can therefore be as valuable as seizing the phone — the record is a passcode-free key to that specific device while it stays AFU.
- **The services** are the actual capabilities `lockdownd` brokers, each a reversed Apple protocol:
  - **`com.apple.afc`** (Apple File Conduit) — a *jailed* file interface to the **media partition only** (`/var/mobile/Media`: camera roll, recordings, books). Not the whole filesystem.
  - **`com.apple.mobile.house_arrest`** — AFC into a *specific app's* Documents container, but only for apps that set `UIFileSharingEnabled`.
  - **`com.apple.mobilebackup2`** — drives the iTunes/Finder backup (the basis of logical acquisition).
  - **`com.apple.crashreportcopymobile`**, **`com.apple.os_trace_relay`**, **`com.apple.pcapd`**, **`com.apple.mobile.installation_proxy`**, **`com.apple.springboardservices`**, **`com.apple.mobile.diagnostics_relay`** — crash logs, the unified-log live stream, packet capture, app inventory, icon state, diagnostics.

**The 2026 wrinkle — RemoteXPC.** Since **iOS 17**, the picture above is only half the story: Apple moved most *developer* and many *diagnostic* services off the classic lockdownd port and behind a new **RemoteXPC** transport. On plug-in, the device now brings up an **Ethernet-over-USB (NCM) interface with an IPv6 address** — it joins your Mac's link-local network like a tiny host. A daemon called **`remoted`** advertises services; a host reaches the **RemoteServiceDiscovery (RSD)** endpoint on a hard-coded port (**58783**) to enumerate them, and **RemoteXPC** carries XPC dictionaries serialized over **HTTP/2**. Reaching these newer services requires first establishing a **trusted tunnel** (a TUN interface) — `pymobiledevice3` does this via `sudo python3 -m pymobiledevice3 remote tunneld`, and pairing for it runs an **SRP** exchange (the infamous dummy password `000000`) plus X25519/Ed25519 key agreement. Practically: classic services (AFC, `mobilebackup2`, install-proxy) still answer over `lockdownd`/usbmux, but anything touching the modern developer surface (the **personalized Developer Disk Image** mount, on-device process control, low-level diagnostics) goes through the tunnel — and a tool that only knows the pre-17 stack will silently come up empty against a current device. *(The RemoteXPC layering is durable from iOS 17 on; the exact port and pairing constants are the perishable detail to re-verify with `pymobiledevice3`'s docs.)*

> 🖥️ **macOS contrast:** On the Mac you don't *need* a second computer to administer the first — Terminal + root *is* the privileged interface, sitting right on the box. iOS externalizes that seat entirely: the privileged interface is a **different machine** speaking a pairing-gated, TLS-wrapped, service-brokered protocol. The Mac's `launchd`-on-demand service model is even mirrored here (`lockdownd` starts services on request the way `launchd` does), but you reach it across a wire, authenticated by a stored pairing record rather than by being `root` locally. → [[10-device-services-and-backups]], [[04-logical-acquisition-with-libimobiledevice]], [[03-the-itunes-finder-backup-format]].

> ⚖️ **Authorization:** A pairing record is a **device-specific credential**. Using one lifted from a suspect's seized Mac to reach into their phone is a search whose scope and lawful authority you must establish *before* you connect — possessing the record is not the same as being authorized to use it, and connecting **mutates device state** (starts services, can flip BFU→AFU expectations, writes lockdown logs). Document the pairing-record provenance and the connection in your chain of custody. → [[00-ios-forensics-landscape-and-authorization]], [[08-acquisition-sop-and-chain-of-custody]].

### Reset 6 — secure boot & the SEP: close to the Apple-Silicon Mac, but with the escape hatches welded shut

Your macOS course covered Apple-Silicon secure boot: the SoC boot ROM → **LLB** → **iBoot** → kernel, each stage verifying the next, with a per-machine **LocalPolicy** you can *downgrade* via **1TR** (One True Recovery) to **Reduced** or **Permissive** security so you can run an unsigned kernel, a third-party OS (Asahi), or kexts. The **Secure Enclave** runs its own **sepOS** off the same boot ROM and guards your keys.

iOS uses the **same architecture** — and that's the point of recognizing it — but with the user-facing flexibility **removed**:

| | Apple-Silicon Mac | iPhone / iPad |
|---|---|---|
| Boot chain | Boot ROM → LLB → iBoot → kernel | **SecureROM → iBoot → kernel** (same shape) |
| Image format | IMG4 / personalized | **IMG4 / personalized** (same) |
| Anti-rollback / personalization | APTicket / SHSH per-boot | **APTicket / SHSH per-boot** (same) |
| Security downgrade | **LocalPolicy via 1TR** → Reduced / Permissive | **none** — Full Security only, no policy to lower |
| Run an unsigned kernel | Supported (Permissive) | **Impossible by design** (only exploits get there) |
| Third-party OS | Supported (Asahi Linux) | Not possible |
| Secure Enclave | sepOS, guards keys | **sepOS, guards keys + drives Data-Protection class keys + inactivity reboot** |

The crucial reset: on the Mac, "I want to run unsigned code in the kernel" is a **supported, documented downgrade** — boot to 1TR, lower the policy, accept the warnings. On iOS **there is no such policy and no such mode**. The only way past secure boot is a **vulnerability**: a **SecureROM** bug like **checkm8** (unpatchable, **A8–A11**) or the June-2026 **usbliter8** SecureROM/USB-DMA bug (**A12–A13**) — so the low-level foothold now spans **A8–A13**, while **A14+ has no public BootROM exploit** — or an iBoot/kernel exploit chain (`palera1n` covers the checkm8 generations on iOS 15.0–18.7.x; a BootROM exploit is code-exec, not a jailbreak, and **there is no public kernel jailbreak for A12+ on iOS 18/26**). The SEP's role is also *larger* than on the Mac: beyond guarding keys, it is the thing that **derives the Data-Protection class keys from the passcode** (Reset 4) and that **counts inactivity to force the BFU reboot**. SEP compromise is correspondingly harder and rarer than kernel compromise — which is exactly why Data Protection holds up even against a jailbroken (kernel-owned) device that's still BFU.

> 🖥️ **macOS contrast:** The mental shortcut: *iOS secure boot is Apple-Silicon-Mac secure boot with `1TR`/LocalPolicy deleted.* Same boot ROM lineage, same IMG4/SHSH personalization, same SEP — but the deliberately-provided "lower the drawbridge" path that lets you run Asahi or an unsigned kernel on a Mac is simply not present on an iPhone. Where the Mac says "hold the power button for Recovery and `csrutil`/`bputil` your way to freedom," iOS says "there is no door; find a crack." → [[01-boot-chain-securerom-iboot]], [[02-image4-personalization-shsh]], [[01-sep-sepos-deep-dive]], [[02-secure-enclave-hardware]], [[07-the-jailbreak-landscape-2026]].

> 🔬 **Forensics note:** The BootROM-exploit boundary is the single most consequential line in iOS acquisition. A **SecureROM** bug lets a tool boot a custom ramdisk and, *if the passcode is known or brute-forceable*, perform a **full-file-system** extraction independent of the OS — historically **checkm8 (A8–A11)**, and since June 2026 **usbliter8 (A12–A13)**, so the low-level foothold now spans **A8–A13**. **A14+ has no public BootROM exploit**: there you are confined to logical/backup acquisition (or a commercial 0-day box), and the BFU/AFU state of the device (Reset 4) decides how much of even *that* decrypts. (A BootROM exploit is code-exec, not a full jailbreak, and does not by itself defeat the SEP or the passcode.) Identify the SoC generation first; it determines your entire acquisition tree. → [[01-the-acquisition-taxonomy]], [[05-full-file-system-acquisition]], [[07-the-jailbreak-landscape-2026]].

### The one principle underneath all six

Step back and the six resets are one idea wearing six hats: **the root of trust moved off the user and onto hardware-attested signatures.**

On macOS, *you* are the authority. Become `root` and the machine does what you say — run unsigned code, read any file, load a kext (with a downgrade), inspect any process. Security is a set of *speed bumps* (Gatekeeper, SIP, the opt-in sandbox) that a sufficiently privileged *user* can lower. The trust anchor is **the human at the keyboard**.

On iOS, the authority is **the chain that starts in immutable SecureROM, is enforced by the SEP and AMFI, and is expressed as signatures and entitlements.** The human — even a human who somehow gets code execution as `root` — is *not* trusted to run unsigned code (AMFI is in-kernel, below root), *not* trusted to read across sandboxes (the kernel confines every process), and *not* trusted to decrypt files whose class keys the SEP hasn't released (Data Protection is rooted in hardware the kernel can't bypass). That is why a **jailbreak** — full kernel compromise, the macOS equivalent of `root` + SIP-off — *still* does not, by itself, decrypt a **BFU** device or forge a code signature the SEP rejects: the kernel was never the trust root to begin with.

Read every later lesson through that lens. "Where does the trust come from, and is it the user or the hardware?" is the question that explains code signing, the sandbox, Data Protection, the pairing model, and secure boot all at once.

### The reset, in one table

| # | macOS reflex | iOS reality | Enforcer / mechanism | Drilled in |
|---|---|---|---|---|
| 1 | Drop to a shell, browse `~`/`/` | No shell, no browsable home; work from a Mac | (absence by design) | [[03-forensics-and-dev-workstation-setup]] |
| 2 | `chmod +x` and run | Unsigned exec pages refused in-kernel | **AMFI** + trust cache + `amfid` | [[04-code-signing-amfi-entitlements]] |
| 3 | App can roam your whole uid | Every app jailed to Bundle + Data containers | Sandbox kext + per-app profile | [[05-the-sandbox-and-tcc]] |
| 4 | One FileVault key unlocks all | Per-file keys × class keys × BFU/AFU state | Data Protection + system keybag + SEP | [[02-data-protection-and-keybags]] |
| 5 | `sudo`/root *on the box* | Privilege only via a tethered, paired Mac | `usbmuxd`/`lockdownd`/AFC + pairing record | [[10-device-services-and-backups]] |
| 6 | `1TR` to lower boot policy | No downgrade; only exploits bypass secure boot | SecureROM/iBoot/IMG4 + SEP | [[01-boot-chain-securerom-iboot]] |

## Hands-on

There is **no physical device** in this course and **no on-device shell** ever. Everything below runs **on the Mac** — either against the **Simulator** (which has no SEP, no Data Protection, no AMFI enforcement, and no lockdown stack — it's macOS frameworks in a directory) or as a **read-only walkthrough** of the device-side commands so you recognize them when you meet a real device under proper authority.

### See that the Simulator is "iOS without the locks" (Simulator)

The Simulator is the cleanest way to *feel* Reset 1–4 by their **absence**. Its app containers sit **unencrypted, fully browsable** on your Mac — the opposite of a device — which is precisely why it teaches *structure* but not *encryption*.

```bash
# What devices/runtimes exist
xcrun simctl list devices available

# Boot one (replace with a name/UDID from the list)
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator

# THE reveal: an app's data container is just a folder on your Mac.
# (Install/run an app first so a container exists.)
xcrun simctl get_app_container booted com.apple.MobileSMS data
#   /Users/you/Library/Developer/CoreSimulator/Devices/<UDID>/data/
#       Containers/Data/Application/<APP-UUID>

# And the bundle container (the signed .app on a real device; here just a folder):
xcrun simctl get_app_container booted com.apple.MobileSMS app
```

`simctl list devices available` prints runtimes as headers with devices and UDIDs beneath, e.g.:

```
-- iOS 26.5 --
    iPhone 17 Pro (1A2B3C4D-…-9F0E) (Shutdown)
    iPad Pro 13-inch (M5) (5E6F…-A1B2) (Booted)
```

and `get_app_container … data` returns a single absolute path like
`…/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APP-UUID>`. Note what you can do here that you could **never** do on a device: `cd` straight into another app's Data container and read its SQLite with no sandbox, no Data-Protection key, no AFC. That gap *is* the lesson. → [[01-simulator-internals-and-on-disk-filesystem]].

### Recognize the tethered-Mac toolchain (read-only walkthrough — no device)

Install the stack so the commands are real even without a phone to point them at:

```bash
brew install libimobiledevice ideviceinstaller ios-deploy
pipx install pymobiledevice3        # the modern, actively-maintained Python stack
```

What you'd run against a *trusted, lawfully-acquired* device — narrated, not executed:

```bash
# Pairing & trust (Reset 5). 'pair' writes /var/db/lockdown/<UDID>.plist on the Mac.
idevicepair pair          # device shows "Trust This Computer?"; user taps + enters passcode
idevicepair validate      # confirm the pairing record is still honored

# Device facts over lockdownd — described output:
#   ideviceinfo (no args) dumps the lockdownd domain: UniqueDeviceID (UDID),
#   ProductType (e.g. iPhone18,1 = iPhone 17 Pro), ProductVersion (e.g. 26.5),
#   HardwareModel, PasswordProtected, ActivationState, plus the pairing certs.
# -k takes ONE key (last one wins), so query each separately:
ideviceinfo -k ProductType        # → "iPhone18,1"
ideviceinfo -k ProductVersion     # → "26.5"

# App inventory via com.apple.mobile.installation_proxy
ideviceinstaller list --user

# Pull crash reports (com.apple.crashreportcopymobile) and the live log (os_trace_relay)
idevicecrashreport -e ./crashes/
idevicesyslog

# App inventory described output: installation_proxy returns one line per app —
#   CFBundleIdentifier, CFBundleShortVersionString, app type (User/System), Path.

# Logical acquisition = a backup over com.apple.mobilebackup2
idevicebackup2 backup --full ./acq/
#   produces ./acq/<UDID>/ containing:
#     Manifest.db     — SQLite mapping every backed-up file → its hashed name + domain
#     Manifest.plist  — backup metadata, IsEncrypted flag, app list
#     Status.plist / Info.plist — snapshot state + device info
#     Keychain in a protected domain (only with an encrypted backup)
#     00/ 01/ … fa/   — files renamed to SHA1(domain-relativePath), 2-hex-sharded
#   That hashed layout is why you parse Manifest.db, not the directory tree, to
#   recover real filenames. → see the Finder-backup-format lesson.

# The modern equivalents, same protocols underneath:
pymobiledevice3 lockdown info
pymobiledevice3 apps list
pymobiledevice3 backup2 backup --full ./acq/

# iOS 17+ only: bring up the RemoteXPC tunnel before touching modern dev services.
sudo python3 -m pymobiledevice3 remote tunneld     # establishes the TUN tunnel; needs root
pymobiledevice3 developer dvt ls /                 # now reachable via RSD over the tunnel
```

> ⚠️ **ADVANCED:** Every one of those commands **mutates the device** — `lockdownd` starts services, writes its own logs, and `pair` creates a credential. None of it is read-only the way `cp`-then-`sqlite3` is on a dead-box image. Against evidence, you image first and work from the copy where the acquisition method allows; you never treat a live device as inert. The destructive end of this stack (a checkm8 ramdisk boot, an exploit chain) gets its own ⚠️ blocks in Part 07.

### Prove "no JIT" to yourself (concept check)

You can't run this on a device, but hold the shape in mind: a third-party app calling `mmap(..., PROT_READ|PROT_WRITE|PROT_EXEC, MAP_ANON, ...)` and then writing instructions into that page will be **killed** when it faults the page in for execution — unless it carries `dynamic-codesigning`. WebKit's content/JIT processes carry it; your app never will. That single entitlement gap is why Frida's "no-jailbreak" injection path is so constrained and why interpreters on the App Store ran interpreter-only for years. → [[05-dynamic-analysis-with-frida]].

## 🧪 Labs

> All labs are **device-free**. Lab 1–2 use the **Simulator** (no SEP / no Data Protection / no AMFI / no lockdownd — it teaches *layout*, never *encryption* or *lock-state*). Lab 3 is a **read-only walkthrough** (you install the tools and read their help; no device is touched). Where a step would behave differently on real hardware, the caveat says so.

### Lab 1 — Find the two containers and resolve the UUID→bundle map (Simulator)

**Substrate:** Simulator. **Fidelity caveat:** on a real device these directories are under `/private/var/...`, are **encrypted per Data-Protection class**, and are reachable only via AFC/backup — here they're plaintext folders on your Mac.

1. Boot a Simulator and run a stock app (e.g. open Messages or Notes inside it) so a Data container exists.
2. Resolve both containers:
   ```bash
   xcrun simctl get_app_container booted com.apple.mobilenotes app    # Bundle (read-only on device)
   xcrun simctl get_app_container booted com.apple.mobilenotes data   # Data
   ```
3. `cd` into the **Data** container and list it. Identify `Documents/`, `Library/Preferences/`, `Library/Caches/`, `tmp/`. Note that on a real device this is the part Data Protection encrypts and AFC/backup exposes.
4. Find and read the container-identity plist that maps the opaque UUID back to a bundle ID:
   ```bash
   plutil -p "$(xcrun simctl get_app_container booted com.apple.mobilenotes data)/../.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null \
     || find "$(xcrun simctl get_app_container booted com.apple.mobilenotes data)/.." -maxdepth 2 -name '*metadata.plist' -exec plutil -p {} \;
   ```
   Write down the `MCMMetadataIdentifier`. **This UUID→bundle-ID step is exactly what `iLEAPP` does first** on a real extraction, because device containers are named by UUID, not by app.

### Lab 2 — Watch the sandbox boundary (Simulator)

**Substrate:** Simulator. **Fidelity caveat:** the Simulator does **not** enforce the sandbox — so this lab demonstrates the boundary by *reasoning*, not by getting denied.

1. From inside one app's Data container, note its absolute path. Now `cat` a file from a *different* app's Data container. On the Simulator this **succeeds** — there's no sandbox kext stopping you.
2. State explicitly why the identical cross-container read would **fail on a device**: the sandbox profile applied at launch confines each process to its own container; there is no path from app A's process to app B's files at runtime.
3. Conclude the operational rule: cross-app data on a *device* is obtainable only by stepping **outside** the sandbox — a full-file-system or backup acquisition reading APFS directly — never by one app reaching another. This is the Reset 3 forensics note made concrete.

### Lab 3 — Map the tethered-Mac protocol stack (read-only walkthrough)

**Substrate:** read-only — install tools, read their interfaces; **no device connected.**

1. `brew install libimobiledevice` and run `idevice_id -l` (returns nothing with no device — that's expected). Read `man ideviceinfo`, `man idevicebackup2`, `man idevicepair`.
2. For each of these services, write one sentence on what it brokers and which Reset it embodies: `com.apple.afc`, `com.apple.mobilebackup2`, `com.apple.crashreportcopymobile`, `com.apple.os_trace_relay`, `com.apple.mobile.installation_proxy`.
3. Explain, in your own words, why a **pairing record at `/var/db/lockdown/<UDID>.plist` with its escrow bag** could let an examiner extract an **AFU-but-screen-locked** device *without the passcode* — and why it would still fail against a **BFU** device. (Answer hinges on Reset 4: the escrow bag can unwrap the keybag whose class keys are only *resident* in AFU.)

### Lab 4 — Reason out the readability matrix (paper exercise, no substrate)

**Substrate:** none — a pencil-and-paper check that you've internalized Resets 2–4. There is nothing to run; the point is to be able to *answer instantly* in the field.

For each cell, state **readable / ciphertext / impossible** and one sentence why:

| Scenario | Class C (default) file | Class A file | Class D file |
|---|---|---|---|
| Device **BFU** (booted, never unlocked) | ? | ? | ? |
| Device **AFU**, currently screen-locked | ? | ? | ? |
| Device **AFU**, currently unlocked | ? | ? | ? |

Then answer three follow-ups: (a) Which row does the **inactivity reboot** push a seized device *back* to, and what does that cost you? (b) If you hold a valid **pairing record + escrow bag** but the device is **BFU**, can you extract Class C data? (c) Why does a **checkm8 + known-passcode** full-file-system extraction recover *more* than any AFU logical pull — what does knowing the passcode let the SEP do that the escrow bag alone cannot? (Check yourself against Resets 4 and 6; the answers are all there.)

## Pitfalls & gotchas

- **"I'll just SSH in / drop a binary."** No. There is no SSH server, no shell, and (Reset 2) AMFI would refuse your binary's unsigned pages in-kernel even if you could place it. Everything privileged is the tethered Mac.
- **Treating the Simulator as a phone.** The Simulator is **macOS frameworks in a folder** — no SEP, no Data Protection at rest, no AMFI enforcement, no baseband, no lockdownd, and the device-only pattern-of-life daemons (`knowledged`/Biome, `biomed`, `powerd`/PowerLog, `routined`) **do not populate** their stores. It is faithful for *schema and layout*, useless for *encryption, lock-state, and pattern-of-life*. Never validate a Data-Protection or BFU/AFU claim on the Simulator.
- **Assuming one unlock means "all readable."** That's the FileVault model. On iOS, readability is `(file's Data-Protection class) × (BFU/AFU/unlocked)`. A Class A file on a locked AFU device is still ciphertext; a Class D file is readable even BFU. Don't generalize from "the volume is mounted."
- **Rebooting a seized device "to be safe."** A reboot destroys every resident Class C key and drops AFU→BFU, often turning a recoverable phone into a near-brick. Power-management discipline (keep powered, keep awake, isolate radios, beat the ~72 h inactivity timer) is part of the SOP, not an afterthought. → [[03-passcode-bfu-afu-and-inactivity]].
- **Looking for app data by bundle ID on disk.** Device containers are named by **opaque UUID**, not bundle ID. Resolve UUID→bundle via `.com.apple.mobile_container_manager.metadata.plist` first; skipping it leaves you staring at anonymous directories.
- **Forgetting the live commands mutate the device.** `idevicepair`, `idevicebackup2`, `idevicesyslog` all start services and write logs on the target. None is the inert `cp`-then-`sqlite3` read you do on a dead-box image. Image first where the method allows; log every connection.
- **Confusing AFC with "the filesystem."** `com.apple.afc` is jailed to the **media partition** (`/var/mobile/Media`); it is *not* a window onto `/`. Full-filesystem access needs a different (often exploit-based, checkm8-bounded) path.
- **Expecting a `1TR`/`csrutil` equivalent on the phone.** There is no supported security-downgrade mode on iOS. If your plan depends on "lowering the policy to run unsigned code," it depends on an exploit and a specific SoC/OS window — not a toggle.
- **Treating a Finder/iTunes backup as a full image.** A `mobilebackup2` backup is *not* a filesystem image — it deliberately omits a great deal (most caches, many app data classes, system files, some Keychain items unless the backup is encrypted), and an *unencrypted* backup notably excludes Health and Keychain secrets that an *encrypted* one includes. "I made a backup, so I have everything" is false twice over: bounded by what the protocol copies *and* by Data-Protection availability. → [[03-the-itunes-finder-backup-format]].
- **Drawing RE conclusions from the Simulator binary.** A Simulator app is an **x86-64/arm64 macOS** build, **not FairPlay-encrypted**, often **ad-hoc signed**, and missing the device entitlements. It's perfect for layout and SQLite schema work and useless for studying the *shipped* binary's signing, encryption, or anti-tamper. For real Mach-O/code-signature/FairPlay analysis you need a device-class `.ipa`, not the Simulator slice. → [[03-fairplay-encryption-and-decrypting-app-store-apps]].
- **Assuming iOS 17+ "just works" with your old tooling.** If a modern device shows up but half your services return nothing, you've hit the **RemoteXPC** split (Reset 5) — the service you want moved behind the tunnel and you never started one. Bring up `remote tunneld` (root) before concluding the device is uncooperative.

## Key takeaways

- iOS is the same XNU/Mach/framework DNA as macOS with the **policy layer inverted**: what macOS makes opt-in (sandbox, code signing, fine-grained encryption) iOS makes **mandatory and inescapable**, and what macOS gives free (shell, arbitrary `exec`, browsable home) iOS **does not provide at all**.
- **No shell, no browsable home** — privileged work is done *to* the device *from* a tethered Mac, never typed on the phone.
- **AMFI enforces signed-code-only at the kernel page-fault level.** `chmod +x` is meaningless, arbitrary `exec` fails, and JIT needs the rare `dynamic-codesigning` entitlement. This is a law of physics, not a doorman you can talk past.
- **The sandbox is universal**: every app lives in a **Bundle** (signed, read-only code) + **Data** (read-write user data) container, named by opaque UUID. Cross-app reads happen only *outside* the sandbox, via filesystem-level acquisition.
- **Data Protection ≠ FileVault:** per-file keys wrapped by a few **class keys** in a SEP-rooted **keybag**, gated by **BFU/AFU** lock state. Readability = class × lock-state; the default class (C) makes an **AFU** device a goldmine and a rebooted **BFU** device near-opaque.
- **The tethered stack** is `usbmuxd` (Mac) → `lockdownd` (device, :62078) → brokered services (**AFC**, `mobilebackup2`, …), gated by a **pairing record** in `/var/db/lockdown/` whose **escrow bag** is a passcode-free key to an AFU device.
- **iOS secure boot is Apple-Silicon-Mac secure boot with the `1TR`/LocalPolicy escape welded shut** — same SecureROM→iBoot→kernel/IMG4/SHSH/SEP lineage, no downgrade mode, bypassable only by exploit (**checkm8 = A8–A11 only**).
- **Two SOP reflexes** fall straight out: never reboot a seized device, and identify the **SoC generation** first — it (via checkm8) decides your whole acquisition tree.

## Terms introduced

| Term | Definition |
|---|---|
| AMFI | Apple Mobile File Integrity — kernel extension (`AppleMobileFileIntegrity.kext`) + `amfid` daemon enforcing mandatory code signing; verifies each executable page's hash against the signed Code Directory in-kernel. |
| Code Directory | The per-page hash table inside a Mach-O code signature that AMFI checks pages against. |
| Trust cache | In-kernel list of approved cdhashes for platform (Apple) binaries, letting them load without an `amfid` round-trip. |
| `amfid` | Userspace daemon AMFI consults to validate third-party signatures, provisioning profiles, and entitlements. |
| `dynamic-codesigning` | The rare iOS entitlement permitting W^X JIT (`MAP_JIT`) regions; held by WebKit JIT processes, essentially never by third-party apps. |
| Provisioning profile | CMS-signed blob embedded in non-App-Store builds binding signing cert + App ID/team + allowed device UDIDs + entitlements; `amfid` validates it at launch. |
| Entitlements | Key/value capabilities baked into a code signature; on iOS they *are* the privilege currency (there is no uid to escalate to). |
| App Group | A shared container (`/var/mobile/Containers/Shared/AppGroup/<UUID>/`) writable only by apps signed into the same `application-groups` entitlement (app + its extensions). |
| Bundle container | Per-app directory holding the signed, read-only `.app` (code + resources), under `/var/containers/Bundle/Application/<UUID>/`. |
| Data container | Per-app read-write directory (`Documents/`, `Library/`, `tmp/`) under `/var/mobile/Containers/Data/Application/<UUID>/`; the primary forensic target. |
| `MCMMetadataIdentifier` | Key in `.com.apple.mobile_container_manager.metadata.plist` mapping a container's opaque UUID back to its bundle ID. |
| `mobile` (uid 501) | The single unprivileged user iOS runs SpringBoard and all third-party apps as; there is no login and no escalation to it or past it. |
| SpringBoard | The iOS "shell" in the windowing-server sense (home screen / app launcher / lifecycle owner) — not a command shell; it gracefully tears down apps on the inactivity reboot. |
| Data Protection | iOS's per-file encryption scheme: each file has its own key, wrapped by a class key in the keybag. |
| `cprotect` | The APFS per-file extended field storing a file's wrapped per-file key and its Data-Protection class. |
| Data Protection class | One of A/Complete, B/CompleteUnlessOpen, C/UntilFirstUserAuthentication (default), D/None — governs when a file's key is available. |
| System keybag | The on-device store of class keys, wrapped by keys derived from the passcode entangled with the SEP UID. |
| BFU / AFU | Before First Unlock / After First Unlock — whether the passcode has been entered since boot; determines which class keys are resident and thus what decrypts. |
| Inactivity reboot | SEP-driven forced reboot (~72 h idle since iOS 18.1) that knocks a device AFU→BFU to shrink the examiner's window. |
| Effaceable storage | Small dedicated NAND region holding keybag-wrapping blobs (`BAG1`/`EMF`); wiping it crypto-erases the device instantly. |
| `usbmuxd` | Mac-side daemon multiplexing many logical TCP service connections over the device's single USB/Wi-Fi endpoint. |
| `lockdownd` | On-device daemon (TLS, port 62078) that authenticates the host and starts brokered services on demand. |
| Pairing record | Per-device plist at `/var/db/lockdown/<UDID>.plist` (host+device certs, escrow bag) establishing host trust. |
| Escrow bag | The part of a pairing record that can unlock an AFU device's keybag without the passcode — the forensic crown jewel. |
| AFC | Apple File Conduit (`com.apple.afc`) — a jailed file interface to the media partition only, not the whole filesystem. |
| `house_arrest` | The `com.apple.mobile.house_arrest` service — AFC scoped into a single app's Documents container (only for apps setting `UIFileSharingEnabled`). |
| `Manifest.db` | SQLite index inside a `mobilebackup2` backup mapping each backed-up file's domain + relative path to its hashed on-disk name; the key to recovering real filenames. |
| Personalized DDI | The Developer Disk Image (debug tools, on-device process control) — since iOS 17 a per-device, signed/personalized image mounted over the RemoteXPC tunnel rather than a static DMG. |
| RemoteXPC / RSD | iOS 17+ transport: device exposes IPv6-over-USB; `remoted` advertises services discovered via RemoteServiceDiscovery (port 58783), carried as XPC dicts over HTTP/2, reached through a trusted TUN tunnel. |
| LocalPolicy / 1TR | Apple-Silicon-Mac per-machine boot policy and the One True Recovery mode used to lower it — the escape hatch iOS deliberately lacks. |
| checkm8 | Unpatchable SecureROM exploit, **A8–A11 only**; the dividing line of iOS full-filesystem acquisition. |

## Further reading

- **Apple Platform Security guide** (security.apple.com) — Data Protection classes, the keybag hierarchy, AMFI/code-signing, secure boot, the SEP, and the inactivity-reboot behavior. The primary source; cite the current edition.
- **Apple Developer** — *Encrypting Your App's Files* / `NSFileProtection*` (the four class constants), App Sandbox & container documentation, TN3125 (in-process code signing).
- **Jonathan Levin**, *MacOS and iOS Internals* vols I–III + newosxbook.com — AMFI, `amfid`, the trust cache, the sandbox profile machinery, lockdownd internals.
- **libimobiledevice** (libimobiledevice.org) + **`pymobiledevice3`** (doronz88/pymobiledevice3) — the open implementations of usbmux/lockdownd/AFC; read the source to see the protocol, not just the CLI. Its `misc/RemoteXPC.md` and `docs/guides/ios17-tunnels.md` document the iOS 17+ RemoteXPC/RSD tunnel in detail.
- **Tihmstar / theapplewiki** — checkm8, IMG4/SHSH personalization, the jailbreak/TrollStore version state.
- **naehrdine (Tihmstar)** & **Magnet/Hexordia** write-ups on the iOS 18 inactivity reboot — the `keybagd`/`AppleSEPKeyStore`/SEP mechanism and its forensic impact.
- **Forensic Focus**, "Forensic Implications of iOS Lockdown (Pairing) Records" — escrow-bag-driven AFU extraction and pairing-record provenance.
- **Sarah Edwards** (mac4n6.com) & **Alexis Brignoni** (iLEAPP) — how the UUID→bundle resolution and container layout drive real artifact parsing.
- **OWASP MASTG / MASVS** (mas.owasp.org) — the structured methodology for iOS app security testing, much of which is the Simulator/sample-image, device-free discipline this course adopts.
- **The iPhone Wiki** — `Usbmux`, `lockdownd`, and pairing-record pages — the community reference for the wire protocols behind the Mac-side tools.
- **Elcomsoft / Magnet / Cellebrite blogs** — the commercial-forensics view of BFU/AFU, escrow-bag (pairing-record) extraction, and the iOS-version acquisition matrix; read critically and re-verify the version claims.
- `man simctl` · `man ideviceinfo` · `man idevicebackup2` · `man idevicepair` — exact flag semantics for the Mac-side tools.

---
*Related lessons: [[01-ios-platform-landscape-and-history]] | [[03-forensics-and-dev-workstation-setup]] | [[04-code-signing-amfi-entitlements]] | [[05-the-sandbox-and-tcc]] | [[02-data-protection-and-keybags]] | [[03-passcode-bfu-afu-and-inactivity]] | [[10-device-services-and-backups]] | [[01-boot-chain-securerom-iboot]] | [[01-the-acquisition-taxonomy]]*
