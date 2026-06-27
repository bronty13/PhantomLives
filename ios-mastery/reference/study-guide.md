---
title: Study Guide
type: reference-derived
description: Part-by-part "what to remember" synthesis with self-test questions, for review
last_reviewed: 2026-06-26
---

# iOS & iPadOS Mastery — Study Guide

**How to use this document:** Read one Part section after you finish the corresponding Part in the curriculum. Each Part opens with a *Big picture* line, then a **What to remember** list distilling that Part's highest-value facts — the ones most likely to decide a real acquisition, parse, or app-security call — and closes with a **Check yourself** callout. The bullets are the review layer, not a substitute for the lessons: if one doesn't click, open the linked lesson (the `[[slug]]` is a wikilink into the course vault). This is the iOS sibling of [`macos-mastery`](../../macos-mastery/reference/study-guide.md) and assumes it; where a fact is "the iOS version of a macOS thing," the contrast is called out.

A single thread runs the whole course — **the interlock**: what you can recover from an iPhone or iPad is a function of `(device model → SoC → BootROM foothold) × (iOS version + build) × (BFU/AFU lock state)`, decided before any tool runs. Almost every Part is a special case of it.

---

## Part 00 — Orientation

**Big picture:** The mental scaffolding — how a device-free course is structured, why iOS is macOS with the security policy inverted, and the one framework (the interlock) that governs every exam.

### What to remember

- **Step zero of every iOS exam is "the interlock"**: `(device model → SoC → BootROM foothold) × (iOS version + build) × (BFU/AFU lock state)`. Pin all three before parsing a single artifact — the entire acquisition course is special cases of it. [[01-ios-platform-landscape-and-history]]
- **The SoC generation, not the marketing OS number, is the decisive axis.** `checkm8` (A8–A11) + `usbliter8` (A12–A13) give an unpatchable hardware foothold; A14+ has none and is confined to software/commercial methods Apple patches build-by-build. [[01-ios-platform-landscape-and-history]]
- **iOS is the same XNU/Darwin core as macOS with the policy layer inverted** — no user shell, mandatory in-kernel code signing (AMFI), a universal sandbox, and per-file Data Protection keyed to lock state. The root of trust moved off the user and onto hardware-attested signatures, so even a jailbreak can't decrypt a BFU device. [[02-macos-to-ios-mental-model-reset]]
- **The Mac is the instrument.** With no on-device shell, every acquisition/parse/instrumentation step runs from the Mac via device-services (usbmuxd → lockdownd, plus a root RemoteXPC tunnel for iOS 17+ developer services) or against a copy already pulled to disk. [[03-forensics-and-dev-workstation-setup]]
- **The course is device-free by construction — three substrates**: the Simulator (plaintext schema/layout only, no security stack), public sample images (the real-but-frozen device-only stores like knowledgeC/Biome/PowerLog), and read-only walkthroughs for device-bound steps. Every lab declares its substrate and fidelity caveat. [[00-how-to-use-this-course]]
- **Evidence discipline starts at lesson one**: authority before access, image-then-examine, copy-before-query (a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`), a captured tool-version manifest, and **never reboot a seized device** (a reboot drops AFU → BFU and evicts the resident Class C keys). [[02-macos-to-ios-mental-model-reset]]

> **Check yourself:**
> 1. What are the three axes of "the interlock," and when do you resolve them?
> 2. Why is the SoC generation, not the iOS version, the decisive axis for acquisition?
> 3. In what sense is iOS "macOS with the policy layer inverted"?
> 4. Why does "copy-before-query" matter for SQLite evidence?
> 5. What happens to the evidence if you reboot a seized iPhone?
> 6. What are the three substrates the course uses in place of a physical device, and what does each faithfully represent?

> [!success]- Answers
> 1. `(device model → SoC → BootROM foothold) × (iOS version + build) × (BFU/AFU lock state)`. You resolve all three at step zero, before parsing any artifact — the whole exam is scoped by them.
> 2. A hardware BootROM foothold (`checkm8` A8–A11, `usbliter8` A12–A13) is unpatchable by software; A14+ has no public hole, so it's limited to software/commercial methods Apple patches per build. The chip sets the ceiling.
> 3. Same XNU/Darwin kernel and subsystems, but no user shell, mandatory in-kernel AMFI code signing, a universal (non-opt-in) sandbox, and per-file Data Protection tied to lock state; the root of trust is hardware-attested signatures, not the logged-in user.
> 4. A plain `SELECT` write-locks the database and creates `-wal`/`-shm` sidecars, mutating the evidence. Always copy the `.db` + `-wal` + `-shm` trio and query the copy.
> 5. A reboot drops AFU → BFU, evicting the resident Class C keys (the default class), so the bulk of user data becomes undecryptable until the passcode is re-entered. Never reboot a seized device.
> 6. The **Simulator** (plaintext schema/layout only, no SEP/Data Protection/AMFI); **public sample images** (real but frozen device-only stores like knowledgeC/Biome/PowerLog); **read-only walkthroughs** for device-bound steps. Each lab states its substrate and fidelity caveat.

---

## Part 01 — Hardware & Silicon

**Big picture:** The physical machine that makes iOS forensics hardware-bound — the SoC federation of trust domains, the SEP/UID that forecloses off-device attacks, inline NAND encryption, the baseband/radio/sensor subsystems, and the two seizure clocks.

### What to remember

- **Identification is forensic step zero.** Resolve the chain DOWN — `marketing → ProductType → DeviceClass/board → BDID → CPID → ECID → SoC` — to place the device on the BootROM-exploit ladder (checkm8 A8–A11, usbliter8 A12–A13, sealed A14+) and the SPTM/TXM (A15+) and MIE (A19) mitigation tiers, before touching any user data. [[00-soc-lineup-and-device-matrix]]
- **Off-device passcode attack is foreclosed by hardware.** The per-die UID is fused, software-unreadable, and brute force must run on *this* SEP — every guess metered by the separate Secure Storage Component (a counter lockbox that self-erases on overflow). Crypto-shred (destroying the UID-rooted effaceable/media keys) is information-theoretically irreversible. [[02-secure-enclave-hardware]]
- **iOS evidence is a live-decryption service, not a disk image.** Every NAND byte is inline AES-XTS ciphertext behind the ANS FTL, so chip-off/physical acquisition is dead on SEP devices; modern acquisition = making the live, AFU, cooperating device decrypt files in place. The deliverable is "what the device could read," not a bit-for-bit image. [[03-storage-nand-aes-effaceable]]
- **The SoC is a federation of separately-signed trust domains** (AP, SEP, Secure Neural Engine, baseband, eSE), so "we got kernel code execution" never means "we got everything" — the SEP keybag, the biometric template, the eSE card secrets, and the baseband all stay behind their own walls. [[02-secure-enclave-hardware]]
- **Lock state plus two hardware clocks decide reachability.** ~1 h **USB Restricted Mode** turns the port charge-only to untrusted hosts; the ~72 h **SEP inactivity reboot** drops AFU→BFU and cools the data — both start at last unlock, making seizure a stopwatch race. A trusting Mac's `/var/db/lockdown` escrow record can rescue an AFU phone. [[07-connectivity-power-sensors-dfu]]
- **The radios and sensors are passive forensic ledgers.** Bluetooth pairings = a relationship graph; Wi-Fi known-networks BSSIDs = a geolocatable place-history; Wallet `passesNN.sqlite` = an FFS-only Apple Pay record deeper than the UI shows; PowerLog + Health = pattern-of-life. Secrets stay in the eSE/SEP, but this metadata persists and is rarely cleaned. [[05-radios-wifi-bt-nfc-uwb]]

> **Check yourself:**
> 1. What is the full identification chain you resolve before touching user data, and what ladders does it place the device on?
> 2. Why can't an iPhone passcode be brute-forced off-device?
> 3. Why is chip-off / NAND mirroring dead on modern iPhones?
> 4. Why doesn't kernel code execution give you "everything"?
> 5. What are the two hardware clocks that shrink the readable set from the moment of seizure?
> 6. Name three radio/sensor artifacts that act as passive forensic ledgers and what each proves.

> [!success]- Answers
> 1. `marketing → ProductType → DeviceClass/board → BDID → CPID → ECID → SoC`. It places the device on the BootROM-exploit ladder (checkm8 A8–A11, usbliter8 A12–A13, sealed A14+) and the SPTM/TXM (A15+) and MIE (A19) mitigation tiers.
> 2. The per-die UID is fused and software-unreadable, so guessing must run on that exact SEP; the separate Secure Storage Component meters every attempt with a counter lockbox that self-erases on overflow (and Erase-after-10 may wipe the device).
> 3. Every NAND byte is inline AES-XTS ciphertext keyed only by the SEP, behind the ANS flash-translation layer; a physical clone yields ciphertext. Acquisition is a live-decryption service, not a disk image.
> 4. The SoC is a federation of separately-signed trust domains (AP, SEP, Secure Neural Engine, baseband, eSE). Owning XNU leaves the SEP keybag, the biometric template, the eSE card secrets, and the baseband behind their own walls.
> 5. **USB Restricted Mode** (~1 h → port goes charge-only to untrusted hosts) and the **SEP inactivity reboot** (~72 h → drops AFU→BFU). Both count from last unlock; a trusting Mac's `/var/db/lockdown` escrow record can still rescue an AFU phone.
> 6. Bluetooth pairings (`com.apple.MobileBluetooth.*`) = a relationship graph; Wi-Fi known-networks BSSIDs = a geolocatable place-history; Wallet `passesNN.sqlite` = an FFS-only Apple Pay transaction record; PowerLog + Health = pattern-of-life.

---

## Part 02 — System Architecture & Internals

**Big picture:** The Darwin substrate as iOS reshapes it — the same kernel machinery with affordances removed, the signed boot relay, the encrypted Data volume and opaque containers, the daemon-behind-every-artifact model, and the pairing-gated acquisition envelope.

### What to remember

- **iOS is the same XNU/Mach/BSD/IOKit/launchd/XPC/APFS/Unified-Logging machinery as macOS** — the reset is almost entirely *removed affordances*: no runtime kexts, no DTrace, no arbitrary `task_for_pid`/`fork`+`exec`, mandatory in-kernel AMFI/CoreTrust signing, no LaunchAgents/cron, no swap (jetsam instead), no on-device shell, and no owner-settable security policy (no LocalPolicy/Reduced Security). [[00-xnu-on-mobile]]
- **An unbroken Image4-signed boot relay** (SecureROM → LLB/iBoot → kernelcache → launchd) plus per-device TSS personalization (ECID + boot nonce, nonce-entangled on A13+) means acquisition reach is dictated by SoC × lock state, with the 72 h inactivity reboot a clock silently dragging AFU→BFU. [[01-boot-chain-securerom-iboot]]
- **All user evidence lives on the per-file-encrypted Data volume under `/private/var`**; the sealed System volume holds none (its only value is the SSV seal as a build-provenance/tamper oracle). iOS keeps no rolling user-data snapshots (deleted-data recovery = SQLite WAL/freelist carving, not snapshot mounting), and every app's data hides behind opaque per-install UUID containers resolved via `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`) — often in an **App Group**, not the Data container. [[03-apfs-on-ios-volumes]]
- **There is a named, signed daemon behind every artifact** (coreduetd/knowledgeC, biomed/Biome, routined, powerlogHelperd, imagent/sms.db, locationd, containermanagerd, installd), so the forensic move is "who wrote this, pinned to the examined build." The dyld shared cache (one AEA/Cryptex blob, no standalone framework binaries) + the trust cache (a cdhash allowlist letting cached code skip `amfid`) is the substrate for all iOS RE and the place tampering shows. [[04-launchd-and-system-daemons]]
- **The no-jailbreak acquisition envelope is one pairing-gated stack** (usbmuxd → lockdownd → brokered `com.apple.*` services). `mobilebackup2`'s output (a `Manifest.db` index + a `SHA1(domain-relativePath)` blob tree) IS logical acquisition; an *encrypted* backup paradoxically yields MORE (Health + a decryptable, PBKDF2-wrapped, off-device-crackable Keychain); the escrow bag in a seized paired computer unlocks an AFU phone passcode-free; and no stock service vends `/` — the ceiling is Data-Protection × service scope. [[10-device-services-and-backups]]
- **sysdiagnose + the Unified Log are the gold-standard live-triage artifact** (process-exec/USB/lock-unlock/biometric/AMFI timelines, plus `shutdown.log` and `JetsamEvent`/crash `.ips` as cheap spyware tripwires), but the rolling window is hours-to-days (collect early), `<private>` redaction is unliftable after the fact, and timestamps are Mach-continuous-time — never cross-wired with the Apple-2001 (+978307200) epoch used by knowledgeC/chat.db. [[09-unified-logging-and-sysdiagnose]]

> **Check yourself:**
> 1. iOS runs the same kernel machinery as macOS — what exactly is the "engineering reset"?
> 2. Where does all user evidence live, and what is the sealed System volume's only forensic value?
> 3. How do you map an opaque app-container UUID back to a bundle ID, and where is the real data often found?
> 4. Why does an encrypted iTunes/Finder backup paradoxically contain MORE than an unencrypted one?
> 5. What is the no-jailbreak acquisition envelope, and what's its ceiling?
> 6. Why must Unified Log / sysdiagnose timestamps never be mixed with knowledgeC/chat.db timestamps?

> [!success]- Answers
> 1. Removed affordances: no runtime kexts, no DTrace, no arbitrary `task_for_pid`/`fork`+`exec`, mandatory in-kernel AMFI/CoreTrust signing, no LaunchAgents/cron, no swap (jetsam instead), no on-device shell, and no owner-settable security policy.
> 2. On the per-file-encrypted Data volume under `/private/var`. The System volume holds no user data — its SSV seal is only a build-provenance/tamper oracle.
> 3. Read `MCMMetadataIdentifier` in `.com.apple.mobile_container_manager.metadata.plist`. The real DB is frequently in the `Shared/AppGroup` container, not the Data container.
> 4. It re-wraps Health and the device Keychain under the user's backup password (PBKDF2), making them present and off-device crackable; an unencrypted backup omits them entirely.
> 5. One pairing-gated stack: usbmuxd → lockdownd → brokered `com.apple.*` services; `mobilebackup2` IS logical acquisition. No stock service vends `/`; the ceiling is Data-Protection class × service scope.
> 6. Log timestamps are Mach-continuous-time (timesync-resolved); knowledgeC/chat.db use the Apple-2001 epoch (+978307200). Cross-wiring them throws the timeline off — and collect early, because the rolling window is hours-to-days and `<private>` redaction is unliftable.

---

## Part 03 — Security Architecture

**Big picture:** The defense-in-depth stack as a set of walls — the SEP as the true acquisition boundary, Data Protection classes tied to lock state, the entitlement-as-privilege model, the kernel-hardening ladder, and the opt-in protections that subtract attack surface.

### What to remember

- **Every layer of the stack is a wall, and an iPhone exam is scoped by naming it**: SoC generation (public BootROM reach is A8–A13 — checkm8 A8–A11, usbliter8 A12–A13, nothing public on A14+), passcode strength + BFU/AFU lock state, and ADP status decide what is recoverable before any tool runs. [[00-the-ios-security-model]]
- **The SEP is the true acquisition wall**: a jailbreak owns the AP/XNU only, the mailbox carries requests not secrets, and the keys for locked classes are never derived into AP-reachable memory — so a BFU device holds even against a fully kernel-owned attacker. [[01-sep-sepos-deep-dive]]
- **Lock state at seizure is the single evidence-defining variable.** Class C (the default) and most Keychain `ck` items are resident only AFU, and the iOS 18 inactivity reboot (~72 h, counted from last unlock) silently demotes AFU→BFU in the evidence locker — so keep seized devices powered, network-isolated (Faraday), and never reboot or guess passcodes (Erase-after-10). [[03-passcode-bfu-afu-and-inactivity]]
- **Privilege on iOS is the entitlement set baked into an Apple-rooted signature** (there is no uid to escalate to), and the kernel-hardening ladder (PAC → PPL → SPTM/TXM → Exclaves → MIE) — not any single missing exploit — is why exploitation-based full-file-system acquisition is dead on A14+: kernel R/W no longer forges signatures or remaps code. [[06-kernel-hardening-pac-sptm-txm-mie]]
- **Recoverability of any file or secret = Data Protection class × acquisition method × lock state** (× backup encryption for the offline path). `persistent_class`/`pdmn` is readable metadata that sets the ceiling before you decrypt a byte, and the file alone (keychain-2.db, an FFS image) is inert without a live SEP/AppleKeyStore unwrap. [[08-keychain-on-ios]]
- **The opt-in layer is subtractive**: Lockdown Mode shrinks the remote zero-click surface, Stolen Device Protection demotes the passcode and breaks fresh pairing off-site, and ADP deletes Apple's iCloud decryption keys. Crucially, ADP is cloud-only and never changes on-device acquisition, while iCloud Mail/Contacts/Calendar stay warrantable even under ADP. [[09-advanced-protections-lockdown-sdp-adp]]

> **Check yourself:**
> 1. What three facts scope what is recoverable before any tool runs?
> 2. Why does a BFU device hold even against an attacker with full kernel code execution?
> 3. Why is lock state at seizure the single most important variable?
> 4. What does "privilege" mean on iOS, and why is exploitation-based FFS dead on A14+?
> 5. Write the formula for whether a given file/secret is recoverable.
> 6. What does ADP change, and what does it NOT change?

> [!success]- Answers
> 1. SoC generation (public BootROM reach A8–A13), passcode strength + BFU/AFU lock state, and ADP status.
> 2. The SEP is the real wall: a jailbreak owns only the AP/XNU, the SEP mailbox carries requests not secrets, and the keys for locked Data-Protection classes are never derived into AP-reachable memory.
> 3. Class C (the default) and most Keychain `ck` items are resident only AFU; the iOS 18 inactivity reboot (~72 h from last unlock) silently demotes AFU→BFU. So keep the device powered, Faraday-isolated, and never reboot or guess (Erase-after-10).
> 4. Privilege is the entitlement set baked into an Apple-rooted code signature — there is no uid to escalate to. The kernel-hardening ladder (PAC → PPL → SPTM/TXM → Exclaves → MIE) means kernel R/W no longer forges signatures or remaps code.
> 5. Data Protection class × acquisition method × lock state (× backup-encryption for the offline path). `persistent_class`/`pdmn` is readable metadata that sets the ceiling before you decrypt a byte.
> 6. ADP deletes Apple's iCloud decryption keys (cloud-only); it never changes on-device acquisition, and iCloud Mail/Contacts/Calendar stay warrantable even under ADP.

---

## Part 04 — Networking & Connectivity

**Big picture:** The network stack as a forensic surface — the per-flow NECP policy engine and its usage stores, NetworkExtension as the only steering path, the TLS/pinning trust-store problem, Wi-Fi/Bluetooth as a non-GPS location engine, Find My's open crypto, and the cellular identifier zoo.

### What to remember

- **iOS keeps the same XNU BSD / mDNSResponder / configd stack as macOS but removes the entire CLI introspection layer.** The inserted **NECP** policy engine binds every flow to its owning process — which is exactly why per-app usage stores (`netusage.sqlite`, `DataUsage.sqlite`) exist, attribute bytes per-bundle in the Apple-2001 epoch, and can outlive a deleted app. [[00-the-ios-networking-stack]]
- **NetworkExtension is the only sanctioned traffic-steering path.** VPN/relay/filter/DNS configs split between the personal NE preferences plist and the configuration-profiles store (most excluded from backups → need FFS); the provider-family entitlement proves capability; and per-app VPN + on-demand rules leak MDM posture, trusted SSIDs, and internal hostnames. [[01-networkextension-and-vpn]]
- **Reading an iOS app's HTTPS is a trust-store problem.** iOS's two-step CA trust (install *then* "Enable Full Trust") is the universal silent failure; a trusted-CA proxy beats ATS but not pinning; and pinning's four mechanisms all ride SecTrust/BoringSSL — so the bypass ladder is **objection → targeted Frida (`SSL_set_custom_verify`/`SecTrustEvaluateWithError`) → SSL Kill Switch → static patch**. [[03-certificate-pinning-and-bypass]]
- **Wi-Fi and Bluetooth artifacts are a non-GPS location-and-association engine.** Known-networks BSSIDs resolve to street addresses via WiGLE; BLE bonds give resolved identity + LastSeenTime (cars/AirPods) while keychain IRKs retroactively de-anonymize captured RPAs; and the whole set is Data-Protection-gated (BFU yields nothing until the passcode is recovered). [[04-wifi-bluetooth-and-proximity]]
- **Find My is open cryptography but access-controlled evidence.** `searchpartyd` holds owned/shared beacons (the P-224 master keys), the volatile SEE-encrypted `Observations.db` relay trail (grab the WAL, copy before query), and the WildModeAssociationRecord anti-stalking log — and computing a `SHA-256(p_i)` index is not fetching a location (Anisette-gated), while Activation Lock is a policy block distinct from encryption. [[05-find-my-and-the-ble-mesh]]
- **Cellular is the no-macOS-analogue subsystem binding device↔SIM↔subscriber.** Keep the identifier zoo straight (IMEI hides in a `_nobackup` plist, MSISDN is operator-writable and not authoritative, `CellularUsage.db` preserves ICCID succession), and the Apple Account (DSID) + GrandSlam tokens/anisette are the bridge to tokenized cloud acquisition whose scope is set by ADP and the E2EE coverage map — where default-config iMessage is usually cloud-producible via the backup-embedded Messages key. [[07-apple-account-icloud-and-apns]]

> **Check yourself:**
> 1. What is the NECP policy engine, and which forensic artifacts does it produce?
> 2. Why is reading an iOS app's HTTPS fundamentally a trust-store problem, and what's the universal silent failure?
> 3. What is the cert-pinning bypass ladder, in order?
> 4. How do Wi-Fi and Bluetooth artifacts locate and identify a device without GPS?
> 5. What does computing a `SHA-256(p_i)` Find My index get you, and what does it not?
> 6. Where does the IMEI hide, and why isn't the MSISDN authoritative?

> [!success]- Answers
> 1. The inserted per-flow policy engine that binds every network flow to its owning process; that's why per-app usage stores (`netusage.sqlite`, `DataUsage.sqlite`) attribute bytes per-bundle (Apple-2001 epoch) and can outlive a deleted app.
> 2. A proxy CA must be both installed *and* have "Enable Full Trust" turned on in Settings; forgetting the second step is the universal silent failure. A trusted-CA proxy beats ATS but not pinning.
> 3. objection → targeted Frida (`SSL_set_custom_verify` / `SecTrustEvaluateWithError`) → SSL Kill Switch → static binary patch; all four pinning mechanisms ride SecTrust/BoringSSL.
> 4. Known-networks BSSIDs resolve to street addresses (e.g. via WiGLE); BLE bonds give resolved identity + LastSeenTime; keychain IRKs retroactively de-anonymize captured rotating RPAs. The whole set is Data-Protection-gated, so BFU yields nothing until the passcode is recovered.
> 5. It is not the same as fetching a location — retrieval is Anisette-gated. `searchpartyd` holds the owned/shared beacon master keys; the relay trail in `Observations.db` is volatile and SEE-encrypted (copy before query, grab the WAL). Activation Lock is a policy block, distinct from encryption.
> 6. The IMEI lives in a `com.apple.commcenter…_nobackup` plist (FFS-only). The MSISDN (phone number) is operator-writable and not authoritative; `CellularUsage.db` preserves ICCID succession instead.

---

## Part 05 — iPadOS as a Computer

**Big picture:** iPadOS is iOS plus extra evidence surfaces, not a different OS — every iPhone method transfers, the additions are strictly additive, "in Files" ≠ "on device," and the silicon tier (A-series vs M-series) sets behavior. The iPad is an acquisition *target*, never the console.

### What to remember

- **iPadOS is iOS from the kernel up** — identical XNU, sandbox, Data Protection, containers, artifact-DB schemas, backup format, and timestamp epochs — so every iPhone artifact, query, and acquisition method transfers verbatim. Treat an iPad as "iOS + an extra evidence surface," never as a different OS. [[00-how-ipados-diverges-from-ios]]
- **The new surfaces are strictly additive**: multi-window/scene state (`applicationState.db`, KTX snapshots, `IconState.plist`), external/cloud storage via the File Provider mesh (On My iPad, CloudDocs `client.db`, third-party BASE64 caches), Apple Pencil `PKDrawing` handwriting with per-stroke timing, M-series swap (`/private/var/vm/`, FFS-only), and per-platform EU-DMA install provenance. [[01-windowing-multitasking-and-external-display]]
- **Files is a brokered federation (`fileproviderd` + sandboxed providers), not a filesystem.** "In Files" ≠ "on the device" — separate *enumerated/dataless* items (placeholders prove existence + size, not content) from *materialized* bytes, and image any attached USB/SMB drive as its own exhibit with its own legal scope. [[02-files-external-storage-and-document-providers]]
- **The silicon split, not the OS, sets device behavior.** A-series base iPad/mini behave like phones (no swap, frequent Jetsam kills); M-series Air/Pro get Virtual Memory Swap, extended external desktops, and a softer jetsam cadence — resolve the personality from `ProductType`/`iPadN,N` before reading any artifact. [[00-how-ipados-diverges-from-ios]]
- **Continuity's durable payoff is device-association, not content.** A shared DSID (`Accounts3.sqlite`) plus migration lineage, Bluetooth/USB pairings, and unified-log peer GUIDs tie an iPad to its owner's Mac+iPhone fleet even after messages are deleted — and **iPhone Mirroring inverts the model**, leaving iPhone-usage records on the *Mac* (`~/Library/Daemon Containers/`). [[04-continuity-with-the-mac]]
- **The iPad builds and automates but is never the analysis console.** AMFI's W^X + the Apple-only `dynamic-codesigning`/`MAP_JIT` grant forbid JIT, structurally foreclosing full Xcode, the Simulator, emulators, and the Frida/libimobiledevice/iLEAPP toolchain on-device — so the iPad is an acquisition *target* and an authored-artifact source (`.swiftpm`, Shortcuts), and version-perishable paths/schemas must be verified against the target image. [[05-pro-and-developer-workflows-on-ipad]]

> **Check yourself:**
> 1. Do iPhone artifacts and acquisition methods transfer to an iPad?
> 2. Why does "in Files" not mean "on the device"?
> 3. How does the silicon tier change an iPad's runtime behavior?
> 4. What does Continuity reliably prove, and what artifact inverts the model?
> 5. Why can't you run the forensic toolchain (Frida, iLEAPP, Simulator) on the iPad itself?
> 6. Name three additive evidence surfaces unique to iPadOS.

> [!success]- Answers
> 1. Yes, verbatim. iPadOS is iOS from the kernel up — identical XNU, sandbox, Data Protection, containers, DB schemas, backup format, and timestamp epochs. Treat an iPad as "iOS + extra evidence surfaces."
> 2. Files is a brokered federation (`fileproviderd` + sandboxed providers). Items can be enumerated/dataless — placeholders that prove existence and size but not content — versus materialized bytes actually present. An attached USB/SMB drive is its own exhibit with its own legal scope.
> 3. A-series base iPad/mini behave like phones (no swap, frequent Jetsam kills); M-series Air/Pro get Virtual Memory Swap (`/private/var/vm/`, FFS-only), extended external desktops, and a softer jetsam cadence. Resolve the tier from `ProductType`/`iPadN,N` first.
> 4. Device-association, not content: a shared DSID (`Accounts3.sqlite`), migration lineage, BT/USB pairings, and unified-log peer GUIDs tie an iPad to the owner's Mac+iPhone fleet even after deletions. iPhone Mirroring inverts it, leaving iPhone-usage records on the Mac (`~/Library/Daemon Containers/`).
> 5. AMFI's W^X plus the Apple-only `dynamic-codesigning`/`MAP_JIT` grant forbid JIT, structurally foreclosing Xcode, the Simulator, emulators, and the Frida/libimobiledevice/iLEAPP stack. The iPad is an acquisition target and authored-artifact source (`.swiftpm`, Shortcuts), not the console.
> 6. Multi-window/scene state (`applicationState.db`, KTX snapshots, `IconState.plist`); the File Provider mesh (On My iPad, CloudDocs `client.db`); Apple Pencil `PKDrawing` per-stroke handwriting; plus M-series swap (`/private/var/vm/`, FFS-only).

---

## Part 06 — Automation & Operations

**Big picture:** The management and automation surface — Shortcuts as a brokered action graph (and an anti-forensic tripwire), Screen Time over CoreDuet, `.mobileconfig` as a consent-based compromise primitive, MDM/supervision/DDM rewriting the forensic picture, the backup-password master switch, and the ordered hardening stack.

### What to remember

- **iOS automation is one brokered, sandboxed action graph** (Shortcuts/WorkflowKit, executed headless by `siriactionsd`) with **no shell/AppleScript/JXA underneath**. Workflows persist as a binary-plist action array in `ZSHORTCUTACTIONS` (recoverable on-device with no signature to defeat), and configured automations + triggers are both behavior-as-evidence (geofences, SSIDs, NFC UIDs, app-open hooks) and, when hands-free, anti-forensic tripwires — acquire first, Faraday/Airplane before hands-on. [[00-shortcuts-and-the-automation-surface]]
- **Screen Time is a UI skin over the CoreDuet pipeline**: a pre-aggregated, redundant pattern-of-life source (`RMAdminStore-Local`/`-Cloud`, Mac Absolute Time, FFS-only, always include the `-wal`) plus a record of enforcement posture and the controlling account — and its passcode is a **distinct** credential from the device passcode with coercive-control/acquisition-frustration significance. [[01-screen-time-and-content-privacy-restrictions]]
- **The configuration profile (`.mobileconfig`) is THE single external configuration channel on iOS** and a no-exploit compromise primitive (rogue root CA → TLS interception, global proxy/VPN, weakened passcode, phishing web clip, MDM enrollment) — defeated by nothing in the PAC/SPTM/MIE ladder because it rides on consent. The installed-profile inventory is tier-one triage, and each payload is self-documenting: read it, don't guess. [[04-configuration-profiles-and-mobileconfig]]
- **Management rewrites the forensic picture.** MDM is queue-and-poll (APNs is only a doorbell carrying PushMagic); supervision via ABM/ASM+ADE is the sticky max-authority bit enabling remote wipe/lock/clear-passcode (RF-isolate first) and host-pairing prohibition that breaks USB logical acquisition; DDM (the 2026 standard, on the same enrollment) inverts the model into device-held JSON declarations + a self-reported status ledger. Management state is FFS-only and increasingly **not** restored from backup (OS 27 re-runs ADE) — so never infer managed/unmanaged from a backup. [[02-mdm-supervision-and-abm]]
- **The encrypted-backup password is the master switch** — it unlocks the device-bound keychain and ADDS Health/Safari/Wi-Fi/call-history/Watch — and is mathematically unrecoverable if lost (double-PBKDF2, no escrow). The encrypted host backup is the no-jailbreak acquisition workhorse on A14+; the host carries its own pairing-record/lockdown evidence (an AFU acquisition primitive); and migration leaves provenance (EXIF/source-device strings/UUIDs/account device list). [[05-backup-restore-migration-and-transfer]]
- **Hardening is a composed, ordered stack** (supervision → restriction profiles + DDM SU enforcement → Lockdown Mode/ADP/SDP/strong alphanumeric passcode → power-off-to-BFU at seizure risk), where each posture forecloses a SPECIFIC acquisition avenue and the seizure timers (inactivity reboot→BFU, USB Restricted Mode) are deployable defenses — but vendor tools (Cellebrite Safeguard Mode, Magnet GrayKey Preserve) now freeze AFU before the timers fire, so the only robust owner countermeasure is creating BFU yourself. Triage the posture before you touch the wire. [[06-lockdown-mode-and-enterprise-posture]]

> **Check yourself:**
> 1. How does iOS automation differ structurally from macOS, and where do shortcuts persist?
> 2. Why are hands-free Shortcuts automations an anti-forensic concern?
> 3. Why is a `.mobileconfig` profile a no-exploit compromise primitive immune to the PAC/SPTM/MIE ladder?
> 4. Why must you never infer managed/unmanaged status from a backup?
> 5. What does the encrypted-backup password unlock, and what happens if it's lost?
> 6. Why is "create BFU yourself" the only robust owner countermeasure against modern extraction?

> [!success]- Answers
> 1. There is no shell/AppleScript/JXA underneath — it's one brokered, sandboxed action graph (Shortcuts/WorkflowKit, run headless by `siriactionsd`). Workflows persist as a binary-plist action array in `ZSHORTCUTACTIONS`, recoverable on-device with no signature to defeat.
> 2. Triggers (geofences, SSIDs, NFC UIDs, app-open hooks) can fire wipe/alert actions when the device connects or moves. Acquire first and Faraday/Airplane the device before any hands-on.
> 3. It is the single external configuration channel and rides entirely on user consent, not a memory bug — a rogue root CA, global proxy/VPN, weakened passcode, phishing web clip, or MDM enrollment all install legitimately. The installed-profile inventory is tier-one triage; each payload is self-documenting.
> 4. Management state (MDM/supervision/DDM) is FFS-only and increasingly not restored from backup (OS 27 re-runs ADE). MDM is queue-and-poll with APNs only a doorbell (PushMagic); supervised devices can be remotely wiped/locked — RF-isolate first.
> 5. It is the master switch: it unlocks the device-bound keychain and adds Health, Safari, Wi-Fi, call history, and Watch data. It is mathematically unrecoverable if lost (double-PBKDF2, no escrow). The encrypted host backup is the no-jailbreak acquisition workhorse on A14+.
> 6. The seizure timers (inactivity reboot→BFU, USB Restricted Mode) are deployable defenses, but vendor tools (Cellebrite Safeguard Mode, Magnet GrayKey Preserve) now freeze AFU state before the timers fire. Powering off to BFU is the only state that reliably forecloses AFU acquisition.

---

## Part 07 — Forensic Acquisition & Imaging

**Big picture:** Acquisition as the inverse of disk forensics — a five-rung ladder gated by SoC × build × lock state, the backup format, the one off-device-solvable unwrap, the perishable 2026 frontier, ADP as the cloud master-switch, and procedural (not structural) integrity.

### What to remember

- **iOS forensics inverts disk forensics on all four axes** — no write-blocker, encrypted-by-default, every action mutates state, and **lock state (BFU/AFU/unlocked) × Data-Protection class (A/B/C/D) bounds recoverability**; "the volume is mounted" tells you almost nothing. [[02-bfu-vs-afu-and-data-protection-classes]]
- **Acquisition is a five-rung ladder** (logical → advanced logical → full file system → physical → cloud) where the available rung is set by **SoC × iOS build × lock state before you touch user data**; the chip sets the ceiling, the lock state the floor, and the least-mutating method that satisfies the warrant goes first. [[01-the-acquisition-taxonomy]]
- **A `mobilebackup2` backup is domain-keyed and hash-named** (`fileID = SHA1(domain-relativePath)`), meaningless without `Manifest.db`, and an **encrypted backup paradoxically contains MORE** (keychain/Health/Safari/passwords re-wrapped under the crackable backup password) than an unencrypted one. [[03-the-itunes-finder-backup-format]]
- **Only one unwrap problem is solvable off-device**: the user-chosen **backup password** (PBKDF2, GPU-attackable, hashcat `-m 14800` — never `14900`/Skip32). The **device passcode is welded to the SEP UID** (~80 ms/guess, wipe counter), and a BootROM exploit (checkm8 A8–A11, usbliter8 A12–A13) is code-exec, never a passcode/SEP defeat. [[07-decrypting-backups-and-images]]
- **The 2026 frontier is perishable and counterintuitive**: BootROM FFS reaches **A8–A13**, the agent reaches A14–A18, but **A19/M5 MIE blocks the agent — the newest silicon regressed to an advanced-logical ceiling**; meanwhile the inactivity reboot (~72 h) and USB Restricted Mode (~1 h) silently shrink the readable set from seizure. [[05-full-file-system-acquisition]]
- **ADP is the cloud master-switch**: it forecloses **both** third-party token extraction and the warrant-to-Apple content route (Mail/Contacts/Calendars + all metadata stay reachable), and **jurisdiction now gates it** (UK ADP withdrawn 2025), relocating evidence back onto the endpoint. [[06-icloud-acquisition-and-advanced-data-protection]]
- **Because the device is live and self-mutating with no static original, integrity is procedural, not structural**: hash the output (dual SHA-256 + MD5), validate the tool, keep a contemporaneous UTC action log, record your own examiner footprint, and document authority — that package, not a write-blocker, is what makes the data admissible. [[08-acquisition-sop-and-chain-of-custody]]

> **Check yourself:**
> 1. On which four axes does iOS forensics invert traditional disk forensics?
> 2. List the five-rung acquisition ladder and what sets the available rung.
> 3. Which unwrap problem is solvable off-device and which is not?
> 4. What is the counterintuitive 2026 silicon regression in FFS reach?
> 5. What does ADP foreclose, what stays reachable, and what now gates it?
> 6. With no static original to hash, how is evidence integrity established on iOS?

> [!success]- Answers
> 1. No write-blocker, encrypted-by-default, every action mutates state, and lock state (BFU/AFU/unlocked) × Data-Protection class bounds recoverability. "The volume is mounted" tells you almost nothing.
> 2. logical → advanced logical → full file system → physical → cloud; the available rung is set by SoC × iOS build × lock state. The chip sets the ceiling, the lock state the floor; pick the least-mutating method that satisfies the warrant.
> 3. The user-chosen backup password is GPU-attackable (PBKDF2; hashcat `-m 14800`, never `14900`/Skip32). The device passcode is welded to the SEP UID (~80 ms/guess, wipe counter) — a BootROM exploit is code execution, never a passcode/SEP defeat.
> 4. BootROM FFS reaches A8–A13; the agent reaches A14–A18; but A19/M5 MIE blocks the agent — so the newest silicon regressed to an advanced-logical ceiling. The inactivity reboot (~72 h) and USB Restricted Mode (~1 h) further shrink the readable set from seizure.
> 5. It forecloses both third-party token extraction and the warrant-to-Apple content route; Mail/Contacts/Calendars plus all metadata stay reachable. Jurisdiction now gates it (UK ADP withdrawn 2025), relocating evidence back onto the endpoint.
> 6. Procedurally, not structurally: hash the output (dual SHA-256 + MD5), validate the tool, keep a contemporaneous UTC action log, record your own examiner footprint, and document authority. That package — not a write-blocker — makes the data admissible.

---

## Part 08 — Forensic Artifacts & Pattern of Life

**Big picture:** The artifact ecosystem and the loop that handles any of it — start at the container skeleton, treat the rolling pattern-of-life corpus as multi-witness, handle WAL-mode SQLite safely, treat "deleted" as a question, and let acquisition method × lock state gate everything.

### What to remember

- **Every iOS app exam starts at the container skeleton**: resolve UUID→bundle via `MCMMetadataIdentifier` and triangulate the install/uninstall chain (`iTunesMetadata.plist` + `applicationState.db` `_UninstallDate`/`compatibilityInfo` + MobileInstallation logs) before parsing — a missing container is never proof of absence, and the real DB is often in the App Group, not the Data container. [[00-app-sandbox-and-filesystem-layout]]
- **The pattern-of-life corpus is FFS-only, rolling-window (~7 days to ~4 weeks), and increasingly drained from `knowledgeC.db` into Biome/SEGB since iOS 16.** Build presence from the **inFocus + backlight + lock triad** and corroborate the same event across knowledgeC, Biome, PowerLog, and the Aggregate Dictionary; disagreement is a tamper/clock flag (PowerLog's monotonic `TIMESTAMP + SYSTEM` arbitrates). [[02-biome-and-segb-streams]]
- **Almost every user store is WAL-mode SQLite on Apple's 2001 Mac-Absolute epoch**: copy the `.db` + `-wal` + `-shm` trio, query the copy only, run `.schema`/`PRAGMA table_info` before trusting any column name, and **pin the epoch per file** — nanoseconds (sms.db), Unix-1970 (Mail Envelope Index, voicemail.date, PowerLog), and 1601 µs (Chromium) are the traps that throw timelines 31 years or 1000× off. [[14-deleted-data-recovery]]
- **"Deleted" is a question, not a conclusion**: soft-delete flags / Recently-Deleted joins (Plane 1), pre-checkpoint WAL frames (Plane 2), freelist/freeblock carving (Plane 3), and OS-displaced copies (notification bodies, keyboard lexicon, Biome, Spotlight) recover content the app no longer shows — only crypto-erase via effaceable storage is genuinely final. [[13-notifications-keyboard-and-misc-stores]]
- **Acquisition method and lock state gate everything**: an FFS + AFU extraction reaches Biome/PowerLog/location/Health/Keychain; backups omit `Caches/`/`tmp/`/Biome/knowledgeC (but DO carry DataUsage and Health-with-a-backup-password); Class-B Health samples shed their key ~10 min after lock; and for encrypted third-party apps the Keychain key's protection class — not the DB — decides recoverability. [[10-health-and-fitness]]
- **The transferable skill is a loop, not memorized schemas**: resolve → inventory → fingerprint by magic bytes (not extension) → find the key (almost always the Keychain) → parse the payload (container format and payload format are two separate problems) → pin the epoch, then corroborate across independent stores and document provenance per item to make the finding court-defensible. [[11-third-party-app-methodology]]

> **Check yourself:**
> 1. What's the first step of every app exam, and why is a missing container not proof of absence?
> 2. How do you build a user-presence timeline, and what arbitrates when stores disagree?
> 3. What is the safe SQLite handling rule, and why pin the epoch per file?
> 4. What are the planes of "deleted"-data recovery, and what is genuinely final?
> 5. What does an FFS+AFU extraction reach that a backup does not?
> 6. State the transferable third-party-app methodology loop.

> [!success]- Answers
> 1. Resolve UUID→bundle via `MCMMetadataIdentifier` and triangulate the install/uninstall chain (`iTunesMetadata.plist` + `applicationState.db` `_UninstallDate`/`compatibilityInfo` + MobileInstallation logs). Uninstall leaves traces, so a missing container only means the data isn't there now — and the real DB is often in the App Group anyway.
> 2. Build presence from the inFocus + backlight + lock triad and corroborate the same event across knowledgeC, Biome/SEGB, PowerLog, and the Aggregate Dictionary. Disagreement is a tamper/clock flag; PowerLog's monotonic `TIMESTAMP + SYSTEM` offset arbitrates.
> 3. Copy the `.db` + `-wal` + `-shm` trio and query only the copy; run `.schema` / `PRAGMA table_info` before trusting any column name. Epochs vary per file — Apple-2001 seconds, nanosecond variants (sms.db), Unix-1970 (Mail Envelope Index, voicemail.date, PowerLog), 1601 µs (Chromium) — and mixing them throws timelines 31 years or 1000× off.
> 4. Plane 1: soft-delete flags / Recently-Deleted joins; Plane 2: pre-checkpoint WAL frames; Plane 3: freelist/freeblock carving; plus OS-displaced copies (notification bodies, keyboard lexicon, Biome, Spotlight). Only crypto-erase via effaceable storage is genuinely final.
> 5. Biome/PowerLog/location/Health/Keychain. Backups omit `Caches/`, `tmp/`, Biome, and knowledgeC (but do carry DataUsage and Health if a backup password is set). Class-B Health samples shed their key ~10 min after lock.
> 6. resolve → inventory → fingerprint by magic bytes (not extension) → find the key (almost always the Keychain) → parse the payload (container format and payload format are two separate problems) → pin the epoch, then corroborate across independent stores and document provenance per item.

---

## Part 09 — Timeline, Analysis & Anti-Forensics

**Big picture:** Turning artifacts into a defensible super-timeline — normalize every epoch to UTC seconds, use the device's own timezone, demand genuinely independent corroboration, and use the monotonic clock to catch tampering and prove deletion.

### What to remember

- **The exam deliverable is one fused super-timeline** — every dated event from every independent store normalized to UTC seconds, every GUID resolved to a bundle id, and every row tagged with its source store. [[01-building-a-unified-timeline]]
- **Convert every epoch to Unix seconds first.** The two constants to know cold are **978307200** (2001→1970) and **11644473600** (1601→1970), and you can name a botched conversion by its offset signature (~31 yr, ~369 yr, ×10⁹/×10⁶). [[00-the-ios-timestamp-zoo]]
- **Use the device's own `ZSECONDSFROMGMT`** (or the SEGB offset varint) for device-local time, never the analysis host's `'localtime'`; sort the spine only on UTC. [[00-the-ios-timestamp-zoo]]
- **Corroboration requires genuinely independent witnesses** (different daemon/epoch/store/format) — same-event doubles (knowledgeC + Biome of one donation) count once, and convergent provenance / merged tool views are *false* corroboration. [[02-correlation-and-anti-forensics]]
- **The monotonic clock is the anti-tamper backbone**: PowerLog's `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` turns a manual backdate into a visible offset step, the RTC in `.tracev3` "does not lie," and deletion is proven by a cross-witness gap (PowerLog screen-on with no knowledgeC focus). [[02-correlation-and-anti-forensics]]
- **Acquisition class bounds the timeline** (FFS = full pattern-of-life spine; backup = sms.db/Safari/Photos/Calls), and the report must separate observation from inference with an explicit confidence level and ruled-out alternatives. [[01-building-a-unified-timeline]]

> **Check yourself:**
> 1. What is the exam deliverable in timeline analysis?
> 2. What two epoch constants must you know cold, and how do you spot a botched conversion?
> 3. Whose timezone do you use for device-local time, and what do you sort on?
> 4. What makes two events genuine corroboration versus false corroboration?
> 5. Why is the monotonic clock the anti-tamper backbone?
> 6. How does acquisition class bound the timeline, and how must the report frame findings?

> [!success]- Answers
> 1. One fused super-timeline: every dated event from every independent store normalized to UTC seconds, every GUID resolved to a bundle id, and every row tagged with its source store.
> 2. **978307200** (2001→1970) and **11644473600** (1601→1970). A botched conversion is named by its offset signature: ~31 years, ~369 years, or a ×10⁹/×10⁶ scale error.
> 3. The device's own `ZSECONDSFROMGMT` (or the SEGB offset varint), never the analysis host's `'localtime'`. Sort the spine only on UTC.
> 4. Genuine corroboration needs independent witnesses — different daemon, epoch, store, and format. Same-event doubles (knowledgeC + Biome of one donation) count once; convergent provenance or merged tool views are false corroboration.
> 5. A manual backdate shows up as a visible offset step in PowerLog's `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`; the RTC in `.tracev3` "does not lie." Deletion is proven by a cross-witness gap (e.g. PowerLog screen-on with no matching knowledgeC focus).
> 6. FFS yields the full pattern-of-life spine; a backup gives only sms.db/Safari/Photos/Calls. The report must separate observation from inference with an explicit confidence level and ruled-out alternatives.

---

## Part 10 — iOS App Engineering

**Big picture:** How an app is built, signed, packaged, and run — the device/Simulator split plus mandatory signing, provenance readable off the bundle, process boundaries as evidence boundaries, the Simulator's faithful-but-security-blind nature, and the lifecycle's dated residue.

### What to remember

- **The iOS build/distribution pipeline is the macOS compile→link→sign→package flow plus two structural axes** — a hard device/Simulator SDK split (Mach-O `PLATFORM_IOS`=2 vs `PLATFORM_IOSSIMULATOR`=7) and mandatory, Apple-authorized code-signing — and every property of a shipped binary (arch, platform tag, FairPlay `cryptid`, embedded profile) is a direct consequence you can read off disk. [[00-ios-xcode-and-the-build-system]]
- **Provenance is readable from the bundle**: FairPlay `cryptid`, the presence/shape of `embedded.mobileprovision`, the signing leaf, and `iTunesMetadata.plist` together pin the distribution channel — and notarization splits the world into Apple-attributable (App Store / marketplace / Web Distribution / TestFlight) vs non-notarized (dev / ad-hoc / enterprise / exploit), with an **enterprise-signed app on a non-MDM device a top red flag**. [[09-distribution-testflight-appstore-enterprise]]
- **Process boundaries are evidence boundaries**: one "app" is a constellation of independently-signed, independently-sandboxed containers (host + each `.appex` under `Data/PluginKitPlugin/<UUID>` + the `Shared/AppGroup/<UUID>` + the shared keychain group + an App Clip), so `ls PlugIns/` + one `codesign -d` per extension is the map — skipping it is the standard way to under-count an app's footprint. [[08-extensions-app-clips-widgets-and-widgetkit]]
- **The Simulator is the no-device workhorse** for schema/structure/Mach-O fingerprinting (cleartext, native arm64, faithful `__swift5_*`/Obj-C metadata) but **lies exactly at the security stack**: no SEP, no Data Protection, no AMFI enforcement, no jetsam/watchdog, and no knowledgeC/Biome/PowerLog/location stores (their daemons don't run) — author SQL there, then port it unchanged to a decrypted device image. [[01-simulator-internals-and-on-disk-filesystem]]
- **`codesign -d --entitlements -` plus the `Info.plist`** (UIBackgroundModes, NSExtensionPointIdentifier, NS…UsageDescription) is a capability inventory of what an app *could* do before you run it; on device the subset rule (binary entitlements ⊆ Apple-signed profile allowlist) is enforced by AMFI, and a `com.apple.private.*` key or a signature/profile mismatch is a tamper/sideload tell. [[05-the-app-sandbox-from-the-developer-side]]
- **The lifecycle leaves dated, sandbox-surviving evidence** (`JetsamEvent-*.ips` process lists, `.ktx` switcher snapshots, watchdog/`0x8badf00d` codes, MetricKit `MXAppExitMetric`), and the `get-task-allow` / `task_for_pid-allow` gate is the hinge of the whole debug toolchain — your dev build is debuggable, a shipping app is not without a re-sign or jailbreak. [[11-debugging-instruments-and-lldb-for-ios]]

> **Check yourself:**
> 1. What two structural axes distinguish the iOS pipeline from the macOS one?
> 2. How do you read an app's distribution channel off the bundle, and what's a top red flag?
> 3. Why are process boundaries evidence boundaries, and how do you map them?
> 4. What does the Simulator faithfully represent, and where does it lie?
> 5. What is the capability inventory you can read before running an app, and what's the AMFI subset rule?
> 6. What dated, sandbox-surviving evidence does the app lifecycle leave, and what gate controls debuggability?

> [!success]- Answers
> 1. A hard device/Simulator SDK split (Mach-O `PLATFORM_IOS`=2 vs `PLATFORM_IOSSIMULATOR`=7) and mandatory, Apple-authorized code-signing. Every shipped-binary property (arch, platform tag, FairPlay `cryptid`, embedded profile) is a readable consequence.
> 2. FairPlay `cryptid`, the presence/shape of `embedded.mobileprovision`, the signing leaf, and `iTunesMetadata.plist` together pin the channel. An enterprise-signed app on a non-MDM device is a top red flag.
> 3. One "app" is a constellation of independently-signed, independently-sandboxed containers: the host, each `.appex` under `Data/PluginKitPlugin/<UUID>`, the `Shared/AppGroup/<UUID>`, the shared keychain group, and any App Clip. Run `ls PlugIns/` + one `codesign -d` per extension; skipping it under-counts the footprint.
> 4. Faithful for schema/structure/Mach-O fingerprinting (cleartext, native arm64, real `__swift5_*`/Obj-C metadata). It lies at the security stack: no SEP, Data Protection, AMFI, jetsam/watchdog, and no knowledgeC/Biome/PowerLog/location stores. Author SQL there, then port it unchanged to a decrypted device image.
> 5. `codesign -d --entitlements -` plus the `Info.plist` (UIBackgroundModes, NSExtensionPointIdentifier, NS…UsageDescription). On device, binary entitlements must be a subset of the Apple-signed profile allowlist; a `com.apple.private.*` key or a signature/profile mismatch is a tamper/sideload tell.
> 6. `JetsamEvent-*.ips` process lists, `.ktx` switcher snapshots, watchdog/`0x8badf00d` exit codes, MetricKit `MXAppExitMetric`. The `get-task-allow` / `task_for_pid-allow` entitlement is the hinge: a dev build is debuggable, a shipping app is not without a re-sign or jailbreak.

---

## Part 11 — Reverse Engineering & App Security

**Big picture:** Defeating the two iOS-only walls before any analysis, reading the code-signature SuperBlob, the single hooking primitive behind every tool, the decisive 2026 device boundary, and why every on-device control is a speed bump — the only real wall is server-side attestation.

### What to remember

- **Decryption/extraction is step zero, not the goal.** FairPlay (`cryptid 1`) and the dyld shared cache are the two iOS-only walls — you must dump decrypted `__TEXT` pages from a live process and extract framework dylibs from a UUID-matched cache before any static or dynamic technique downstream operates on real bytes rather than noise. [[03-fairplay-encryption-and-decrypting-app-store-apps]]
- **The code-signature SuperBlob fuses identity (`cdhash`/Team ID), capability (XML+DER entitlements), and tamper-evidence (per-page hashes) into one `__LINKEDIT` blob** — parse it first to establish who built a binary, what it could do, and whether a byte changed, before any disassembly. [[01-the-code-signature-blob-and-entitlements-on-ios]]
- **Hooking is one mechanism pointed many ways**: Frida's Interceptor/ObjC bridge, objection's commands, Cycript's ghost, and every Theos tweak all bottom out in rewriting the ObjC selector→IMP table (swizzling) or patching a C-function prologue — and detection and bypass are the *same* primitive aimed in opposite directions. [[06-objection-swizzling-and-runtime-exploration]]
- **The 2026 device boundary is decisive**: BootROM jailbreaks reach only A8–A13 (checkm8/usbliter8), kernel jailbreaks stop at iOS 16.6.x, and TrollStore froze at iOS 17.0 (CoreTrust patched) — so A14+ on iOS 18/26 has no public on-device tooling path. Fall back to the Simulator + frida-gadget + IPSW-sourced caches. [[07-the-jailbreak-landscape-2026]]
- **Every on-device resilience control (jailbreak detection, anti-debug, pinning, obfuscation) runs on hardware the attacker owns, so each is a defeatable speed bump**; the only real wall is "measure on device, decide on server" — App Attest's Secure-Enclave attestation verified server-side. OWASP now advises against cert pinning in almost all cases. [[11-anti-tamper-pinning-and-detection-both-sides]]
- **The Simulator faithfully teaches structure and the instrumentation API** (Mach-O layout, class-dump, the Frida/objection method) but is an arm64 macOS process with no AMFI/sandbox/SEP/Data-Protection/FairPlay — so **always stamp the fidelity caveat**: it proves placement and technique, never device enforcement or at-rest crypto/anti-jailbreak realism. [[10-owasp-mastg-and-app-security-testing]]

> **Check yourself:**
> 1. What are the two iOS-only walls you must defeat before any RE technique works?
> 2. What three things does the code-signature SuperBlob fuse, and why parse it first?
> 3. What single primitive underlies all hooking, and how does it relate to detection?
> 4. What is the decisive 2026 device boundary for on-device tooling?
> 5. Why is every on-device resilience control only a speed bump, and what is the only real wall?
> 6. What does the Simulator faithfully teach in RE, and what caveat must you always stamp?

> [!success]- Answers
> 1. FairPlay encryption (`cryptid 1`) and the dyld shared cache. You must dump decrypted `__TEXT` pages from a live process and extract framework dylibs from a UUID-matched cache first, or every downstream technique operates on noise.
> 2. Identity (`cdhash`/Team ID), capability (XML + DER entitlements), and tamper-evidence (per-page hashes), all in one `__LINKEDIT` blob. Parsing it first tells you who built the binary, what it could do, and whether a byte changed.
> 3. Rewriting the ObjC selector→IMP table (swizzling) or patching a C-function prologue. Frida, objection, Cycript, and Theos tweaks all bottom out there; detection and bypass are the same primitive aimed in opposite directions.
> 4. BootROM jailbreaks reach only A8–A13 (checkm8/usbliter8), kernel jailbreaks stop at iOS 16.6.x, and TrollStore froze at iOS 17.0 (CoreTrust patched). A14+ on iOS 18/26 has no public on-device path — fall back to the Simulator + frida-gadget + IPSW-sourced caches.
> 5. They all run on hardware the attacker owns, so each is defeatable. The only real wall is "measure on device, decide on server" — App Attest's Secure-Enclave attestation verified server-side. OWASP now advises against cert pinning in almost all cases.
> 6. It faithfully teaches structure and the instrumentation API (Mach-O layout, class-dump, the Frida/objection method), but it's an arm64 macOS process with no AMFI/sandbox/SEP/Data-Protection/FairPlay. Stamp the fidelity caveat: it proves placement and technique, never device enforcement or at-rest crypto/anti-jailbreak realism.

---

## See also

- [[CURRICULUM]] — the full lesson map (all 105 lessons across 12 parts)
- [[glossary]] · [[acronyms]] — every term and acronym, defined
- [[acquisition-methods-matrix]] — method × SoC × iOS × AFU/BFU × yield × tooling
- [[forensic-artifacts-index]] — every artifact, format, what-it-proves, acquisition tier
- [[timestamps-and-epochs]] — every epoch + a conversion recipe each
- [[macos-to-ios]] — "the X of iOS" lookup for a macOS power user
