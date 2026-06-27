---
title: Acronyms & Abbreviations
type: reference-derived
last_reviewed: 2026-06-26
tags: [ios, reference, acronyms, glossary]
---

# Acronyms & Abbreviations

iOS is acronym-dense — this is the marquee reference spine. Every acronym used across the
course, decoded, one per row. Sorted alphabetically (case-insensitive). Built by combing the
lesson corpus, so it stays in sync with what the lessons actually use.

> **How to use this table:** The **Related lesson** column uses Obsidian wikilinks — click in
> Obsidian or navigate manually. Where an acronym recurs across many lessons, the link points
> at the lesson that defines or deep-dives it. A handful of acronyms collide (same letters, two
> meanings) — those rows carry both expansions; see also the [Collisions](#collisions--dual-meanings) note below.

> 🔬 **Forensics note:** Most of these turn up in plist keys, SQLite column names, daemon names
> in the unified log, IM4P/IM4M four-cc tags, keybag TLV fields, and crash/`.ips` reports.
> Knowing the expansion is half of recognizing what an artifact is telling you.

---

## The Table

| Acronym | Expansion | Related lesson |
|---------|-----------|----------------|
| **1TR** | One True Recovery (Apple-Silicon-Mac mode; the escape hatch iOS lacks) | [[02-macos-to-ios-mental-model-reset]] |
| **A2DP** | Advanced Audio Distribution Profile (Bluetooth) | [[04-wifi-bluetooth-and-proximity]] |
| **AAGUID** | Authenticator Attestation GUID (App Attest) | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **AASA** | apple-app-site-association (Universal Links file) | [[05-the-app-sandbox-from-the-developer-side]] |
| **ABI** | Application Binary Interface | [[00-ios-xcode-and-the-build-system]] |
| **ABM** | Apple Business Manager | [[02-mdm-supervision-and-abm]] |
| **ACL** | Access Control List (keychain `accc`) | [[08-keychain-on-ios]] |
| **ACME** | Automatic Certificate Management Environment | [[02-mdm-supervision-and-abm]] |
| **ADE** | Automated Device Enrollment (formerly DEP) | [[02-mdm-supervision-and-abm]] |
| **ADEP** | Apple Developer Enterprise Program | [[09-distribution-testflight-appstore-enterprise]] |
| **ADI** | Apple Device Identity (library); the anisette/OTP provisioning seed | [[06-icloud-acquisition-and-advanced-data-protection]] |
| **ADN** | Abbreviated Dialing Numbers (SIM phonebook, `EF_ADN`) | [[06-cellular-baseband-esim-and-identifiers]] |
| **ADP** | Advanced Data Protection (iCloud E2EE); also Alternative Distribution Packet (EU off-store package) | [[03-the-itunes-finder-backup-format]] / [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **AEA** | Apple Encrypted Archive (AEA1; `.shortcut`, IPSW root DMG) | [[02-the-dyld-shared-cache]] |
| **AES** | Advanced Encryption Standard | [[03-storage-nand-aes-effaceable]] |
| **AES-CCM** | AES Counter with CBC-MAC mode (sensor pairing channel) | [[06-biometrics-hardware-faceid-touchid]] |
| **AES-GCM** | AES Galois/Counter Mode | [[04-continuity-with-the-mac]] |
| **AES-KW** | AES Key Wrap (RFC 3394) | [[02-data-protection-and-keybags]] |
| **AES-XTS** | AES XEX-based Tweaked-codebook with Ciphertext Stealing (at-rest content cipher) | [[02-data-protection-and-keybags]] |
| **AFC** | Apple File Conduit (`com.apple.afc`; media-partition file interface) | [[01-the-acquisition-taxonomy]] |
| **AFIS** | Automated Fingerprint Identification System | [[06-biometrics-hardware-faceid-touchid]] |
| **AFU** | After First Unlock (passcode entered since boot; Class C keys resident) | [[00-ios-forensics-landscape-and-authorization]] |
| **AKS** | AppleKeyStore (AP-side keystore kext / API) | [[02-data-protection-and-keybags]] |
| **AMCC** | Apple Memory Cache Controller (enforces KTRR range) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **AMFI** | Apple Mobile File Integrity (mandatory code-signing enforcement) | [[00-xnu-on-mobile]] |
| **AMR / AMR-NB** | Adaptive Multi-Rate (Narrowband) audio codec (voicemail) | [[05-call-history-voicemail-contacts-interactions]] |
| **AMSS** | Advanced Mobile Subscriber Software (Qualcomm baseband RTOS) | [[04-baseband-and-cellular]] |
| **AMX** | Apple Matrix eXtension (undocumented per-cluster matrix coprocessor) | [[01-cpu-gpu-npu-microarchitecture]] |
| **ANE** | Apple Neural Engine | [[01-cpu-gpu-npu-microarchitecture]] |
| **ANS** | Apple NAND Storage (in-SoC NVMe-class controller) | [[03-storage-nand-aes-effaceable]] |
| **AoA** | Angle of Arrival (UWB) | [[05-radios-wifi-bt-nfc-uwb]] |
| **AOD** | Always-On Display | [[07-connectivity-power-sensors-dfu]] |
| **AOP** | Always-On Processor (low-power sensor/pedometer coprocessor) | [[07-connectivity-power-sensors-dfu]] |
| **AOT** | Ahead-Of-Time (compilation; how Swift Playground avoids JIT) | [[05-pro-and-developer-workflows-on-ipad]] |
| **AP** | Application Processor (the A-series SoC running XNU/iOS) | [[01-cpu-gpu-npu-microarchitecture]] |
| **APFS** | Apple File System | [[03-apfs-on-ios-volumes]] |
| **API** | Application Programming Interface | [[01-knowledgec-db-deep-dive]] |
| **APN** | Access Point Name (carrier data config) | [[06-cellular-baseband-esim-and-identifiers]] |
| **APNs** | Apple Push Notification service | [[07-apple-account-icloud-and-apns]] |
| **APRR** | Access Permission Remapping Register (Apple-silicon page-permission feature) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **APT** | Advanced Persistent Threat | [[04-configuration-profiles-and-mobileconfig]] |
| **APTicket** | the jailbreaker name for the IM4M / SHSH personalized boot manifest | [[02-image4-personalization-shsh]] |
| **ARC** | Automatic Reference Counting | [[10-owasp-mastg-and-app-security-testing]] |
| **ARI** | Apple Remote Invocation (closed AP↔baseband protocol, Intel modems) | [[06-cellular-baseband-esim-and-identifiers]] |
| **arm64e** | Apple's ARMv8.3 Pointer-Authentication ABI / CPU subtype | [[01-cpu-gpu-npu-microarchitecture]] |
| **ARTM** | Anti-Replay Token Manager (xART predecessor) | [[01-sep-sepos-deep-dive]] |
| **ASLR** | Address Space Layout Randomization | [[00-mach-o-arm64-deep-dive]] |
| **ASM** | Apple School Manager | [[02-mdm-supervision-and-abm]] |
| **ASN.1** | Abstract Syntax Notation One | [[00-xnu-on-mobile]] |
| **ASVS** | Application Security Verification Standard (OWASP, web) | [[10-owasp-mastg-and-app-security-testing]] |
| **ATS** | App Transport Security (CFNetwork cleartext/weak-TLS policy) | [[00-the-ios-networking-stack]] |
| **ATT** | App Tracking Transparency | [[06-cellular-baseband-esim-and-identifiers]] |
| **AV** | Audio/Video (Continuity streams); also Antivirus | [[04-continuity-with-the-mac]] / [[06-lockdown-mode-and-enterprise-posture]] |
| **AWDL** | Apple Wireless Direct Link (P2P 802.11; AirDrop/AirPlay/Sidecar) | [[00-the-ios-networking-stack]] |
| **BBTicket** | Baseband (personalization) Ticket (binds modem firmware) | [[02-image4-personalization-shsh]] |
| **BDID** | Board ID (`ApBoardID`) | [[00-soc-lineup-and-device-matrix]] |
| **BFU** | Before First Unlock (never unlocked since boot; A/B/C keys not derivable) | [[00-ios-forensics-landscape-and-authorization]] |
| **BLE** | Bluetooth Low Energy | [[04-wifi-bluetooth-and-proximity]] |
| **BNCH** | Boot Nonce Hash (ApNonce, in the manifest) | [[02-image4-personalization-shsh]] |
| **BNCN** | Boot Nonce (raw generator, in IM4R) | [[02-image4-personalization-shsh]] |
| **BP** | Baseband Processor (the modem chip) | [[06-cellular-baseband-esim-and-identifiers]] |
| **BPP** | Bound Profile Package (eSIM profile install unit) | [[06-cellular-baseband-esim-and-identifiers]] |
| **BR/EDR** | Basic Rate / Enhanced Data Rate (Classic Bluetooth) | [[04-wifi-bluetooth-and-proximity]] |
| **BSD** | Berkeley Software Distribution (the Unix personality of XNU) | [[00-xnu-on-mobile]] |
| **BSSID** | Basic Service Set Identifier (Wi-Fi access-point MAC) | [[04-wifi-bluetooth-and-proximity]] |
| **BTI** | Branch Target Identification | [[01-cpu-gpu-npu-microarchitecture]] |
| **BYOD** | Bring Your Own Device | [[02-mdm-supervision-and-abm]] |
| **C2** | Command and Control | [[06-lockdown-mode-and-enterprise-posture]] |
| **CA** | Certificate Authority | [[02-traffic-interception-and-tls]] |
| **CAA** | Certification Authority Authorization | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **CBC** | Cipher Block Chaining (AES-CBC, legacy at-rest mode) | [[02-data-protection-and-keybags]] |
| **CBOR** | Concise Binary Object Representation (App Attest) | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **CC** | Common Criteria | [[01-sep-sepos-deep-dive]] |
| **CCC** | Car Connectivity Consortium (digital car keys) | [[05-radios-wifi-bt-nfc-uwb]] |
| **CD** | CodeDirectory (core code-signature sub-blob) | [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **CDHash / cdhash** | Code Directory Hash (the canonical binary identity) | [[06-code-signing-and-provisioning-in-depth]] |
| **CDR** | Call Detail Record (carrier-side) | [[05-call-history-voicemail-contacts-interactions]] |
| **CEPO** | Certificate Epoch (anti-rollback on signing certs) | [[02-image4-personalization-shsh]] |
| **CFAA** | Computer Fraud and Abuse Act (US) | [[00-ios-forensics-landscape-and-authorization]] |
| **CFReDS** | Computer Forensic Reference Data Sets (NIST) | [[00-how-to-use-this-course]] |
| **CI** | Certificate Issuer (GSMA eSIM root); also Cell ID; also Continuous Integration | [[06-cellular-baseband-esim-and-identifiers]] / [[07-location-history]] / [[05-pro-and-developer-workflows-on-ipad]] |
| **CKKS** | CloudKit Keychain Syncing (iCloud Keychain transport) | [[08-keychain-on-ios]] |
| **CKV** | Contact Key Verification (iMessage key transparency) | [[07-apple-account-icloud-and-apns]] |
| **CLPC** | Closed-Loop Performance Controller (XNU P/E core scheduler) | [[01-cpu-gpu-npu-microarchitecture]] |
| **CMAC** | Cipher-based Message Authentication Code (SEP DRAM integrity) | [[02-secure-enclave-hardware]] |
| **CMS** | Cryptographic Message Syntax (PKCS#7 SignedData) | [[04-code-signing-amfi-entitlements]] |
| **CoC** | Chain of Custody | [[08-acquisition-sop-and-chain-of-custody]] |
| **COSE** | CBOR Object Signing and Encryption | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **COW** | Copy-On-Write (APFS) | [[03-apfs-on-ios-volumes]] |
| **CPID** | Chip ID (`ApChipID`; the SoC die identifier) | [[00-soc-lineup-and-device-matrix]] |
| **CPRV** | Chip Revision (base vs Pro part sharing a CPID) | [[00-soc-lineup-and-device-matrix]] |
| **CPS** | Core Platform Service (EU DMA designation) | [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **CPU** | Central Processing Unit | [[01-cpu-gpu-npu-microarchitecture]] |
| **CRC32** | Cyclic Redundancy Check (32-bit; SEGB record integrity) | [[02-biome-and-segb-streams]] |
| **CRL** | Certificate Revocation List | [[03-certificate-pinning-and-bypass]] |
| **CSPRNG** | Cryptographically Secure Pseudo-Random Number Generator | [[10-owasp-mastg-and-app-security-testing]] |
| **CSR** | Certificate Signing Request | [[06-code-signing-and-provisioning-in-depth]] |
| **CT** | Certificate Transparency | [[02-traffic-interception-and-tls]] |
| **CTC** | Core Technology Commission (EU DMA) | [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **CTF** | Core Technology Fee (EU DMA) | [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **CTR_DRBG** | Counter-mode Deterministic Random Bit Generator (TRNG conditioning) | [[02-secure-enclave-hardware]] |
| **CTRR** | Configurable Text Read-only Region (KTRR successor) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **CVE** | Common Vulnerabilities and Exposures | [[02-bfu-vs-afu-and-data-protection-classes]] |
| **CWE** | Common Weakness Enumeration | [[10-owasp-mastg-and-app-security-testing]] |
| **DART** | Device Address Resolution Table (Apple IOMMU; modem/USB DMA confinement) | [[04-baseband-and-cellular]] |
| **DDI** | Developer Disk Image (ships `debugserver`; personalized on iOS 17+) | [[11-debugging-instruments-and-lldb-for-ios]] |
| **DDM** | Declarative Device Management | [[03-declarative-device-management]] |
| **DEP** | Device Enrollment Program (former name of ADE) | [[02-mdm-supervision-and-abm]] |
| **DER** | Distinguished Encoding Rules (ASN.1; DER entitlements since iOS 15) | [[00-xnu-on-mobile]] |
| **DF** | Dedicated File (SIM filesystem) | [[06-cellular-baseband-esim-and-identifiers]] |
| **DFIR** | Digital Forensics & Incident Response | [[00-app-sandbox-and-filesystem-layout]] |
| **DFRWS** | Digital Forensic Research Workshop | [[03-forensics-and-dev-workstation-setup]] |
| **DFU** | Device Firmware Update (SecureROM-only USB mode below iBoot) | [[01-boot-chain-securerom-iboot]] |
| **DGST** | Digest (per-component SHA-384 in the IM4M) | [[02-image4-personalization-shsh]] |
| **DL** | DeviceLink (the `mobilebackup2` message protocol) | [[10-device-services-and-backups]] |
| **DMA** | Digital Markets Act (EU); also Direct Memory Access (e.g. USB-DMA exploit) | [[10-eu-dma-sideloading-and-alternative-marketplaces]] / [[05-full-file-system-acquisition]] |
| **DMCA** | Digital Millennium Copyright Act | [[03-certificate-pinning-and-bypass]] |
| **DMS** | Device Management Service (QMI service) | [[06-cellular-baseband-esim-and-identifiers]] |
| **DNI** | Director of National Intelligence (US) | [[09-advanced-protections-lockdown-sdp-adp]] |
| **DNS** | Domain Name System | [[00-the-ios-networking-stack]] |
| **DoH** | DNS over HTTPS | [[00-the-ios-networking-stack]] |
| **DoT** | DNS over TLS | [[00-the-ios-networking-stack]] |
| **DOS** | Disk Operating System (DOS/FAT packed time) | [[00-the-ios-timestamp-zoo]] |
| **DP** | Data Protection (iOS per-file class-keyed encryption) | [[00-how-to-use-this-course]] |
| **DPA** | Differential Power Analysis (side-channel; SEP AES is hardened) | [[02-secure-enclave-hardware]] |
| **DPAN** | Device (Primary) Account Number (eSE payment token) | [[05-radios-wifi-bt-nfc-uwb]] |
| **DPIC** | Data Protection Iteration Count (iOS 10.2+ outer backup-KDF rounds) | [[07-decrypting-backups-and-images]] |
| **DPSL** | Data Protection Salt (the outer backup-KDF salt) | [[07-decrypting-backups-and-images]] |
| **DR** | Designated Requirement (code-signing identity predicate) | [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **DRM** | Digital Rights Management | [[00-mach-o-arm64-deep-dive]] |
| **DSC** | dyld Shared Cache | [[02-the-dyld-shared-cache]] |
| **DSCU** | Dyld Shared Cache Utils (IDA plugin) | [[04-static-analysis-class-dump-and-disassemblers]] |
| **DSDS** | Dual SIM Dual Standby | [[04-baseband-and-cellular]] |
| **DSID** | Directory/Destination Services Identifier (numeric Apple-Account key) | [[04-continuity-with-the-mac]] |
| **DST** | Daylight Saving Time | [[00-the-ios-timestamp-zoo]] |
| **dToF** | direct Time-of-Flight (LiDAR depth) | [[07-connectivity-power-sensors-dfu]] |
| **DULT** | Detecting Unwanted Location Trackers (Apple/Google anti-stalking spec) | [[05-find-my-and-the-ble-mesh]] |
| **DVFS** | Dynamic Voltage and Frequency Scaling | [[01-cpu-gpu-npu-microarchitecture]] |
| **DVT** | (Instruments) Developer Tools service (over RSD) | [[10-device-services-and-backups]] |
| **DWARF** | the debug-info format inside a dSYM | [[00-ios-xcode-and-the-build-system]] |
| **E2EE / E2E** | End-to-End Encryption / Encrypted | [[09-advanced-protections-lockdown-sdp-adp]] |
| **EACS** | Erase All Content and Settings (crypto-shred wipe) | [[03-storage-nand-aes-effaceable]] |
| **EAP** | Extensible Authentication Protocol (enterprise Wi-Fi) | [[04-configuration-profiles-and-mobileconfig]] |
| **ECB** | Electronic Codebook (weak block-cipher mode) | [[10-owasp-mastg-and-app-security-testing]] |
| **ECC** | Elliptic Curve Cryptography | [[02-secure-enclave-hardware]] |
| **ECDH** | Elliptic Curve Diffie-Hellman | [[02-data-protection-and-keybags]] |
| **ECDSA** | Elliptic Curve Digital Signature Algorithm | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **ECG** | Electrocardiogram (HealthKit) | [[10-health-and-fitness]] |
| **ECID** | Exclusive Chip ID (`UniqueChipID`; 64-bit per-die value) | [[00-soc-lineup-and-device-matrix]] |
| **ECIES** | Elliptic Curve Integrated Encryption Scheme (Find My report encryption) | [[05-find-my-and-the-ble-mesh]] |
| **EF** | Elementary File (SIM filesystem, e.g. `EF_ICCID`) | [[06-cellular-baseband-esim-and-identifiers]] |
| **EFF** | Electronic Frontier Foundation | [[09-advanced-protections-lockdown-sdp-adp]] |
| **EID** | eUICC Identifier (32-digit eSIM hardware id) | [[04-baseband-and-cellular]] |
| **EIFT** | Elcomsoft iOS Forensic Toolkit | [[05-full-file-system-acquisition]] |
| **EL** | Exception Level (EL0–EL3, ARM privilege levels) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **EMTE** | Enhanced Memory Tagging Extension (Apple always-synchronous MTE) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **EMVCo** | Europay-Mastercard-Visa consortium (payment-card standards) | [[05-radios-wifi-bt-nfc-uwb]] |
| **EPB** | Elcomsoft Phone Breaker (commercial cloud/backup tool) | [[06-icloud-acquisition-and-advanced-data-protection]] |
| **eSE** | embedded Secure Element (payment/transit/key applets) | [[05-radios-wifi-bt-nfc-uwb]] |
| **eSIM** | embedded SIM | [[05-backup-restore-migration-and-transfer]] |
| **eUICC** | embedded Universal Integrated Circuit Card (the soldered eSIM SE) | [[04-baseband-and-cellular]] |
| **EU** | European Union | [[00-how-ipados-diverges-from-ios]] |
| **EXIF** | Exchangeable Image File Format (media metadata) | [[03-trackpad-keyboard-and-apple-pencil]] |
| **exFAT** | Extended File Allocation Table | [[02-files-external-storage-and-document-providers]] |
| **FAR** | False Accept Rate (biometrics) | [[07-biometrics-security-architecture]] |
| **FAT** | File Allocation Table | [[00-the-ios-timestamp-zoo]] |
| **FCS** | Firmware Content Store (ipsw's term for the per-build AEA key) | [[02-the-dyld-shared-cache]] |
| **FFS** | Full File System (acquisition class; the decrypted Data volume) | [[01-the-acquisition-taxonomy]] |
| **FIPS** | Federal Information Processing Standard | [[01-sep-sepos-deep-dive]] |
| **FLAC** | Free Lossless Audio Codec | [[00-how-ipados-diverges-from-ios]] |
| **FMR** | False Match Rate (biometrics) | [[06-biometrics-hardware-faceid-touchid]] |
| **FPAC** | Faulting PAC (`FEAT_FPAC`; fault on a failed AUT*) | [[01-cpu-gpu-npu-microarchitecture]] |
| **FTL** | Flash-Translation Layer (controller wear-leveling/GC) | [[03-storage-nand-aes-effaceable]] |
| **GATT** | Generic Attribute Profile (BLE) | [[04-wifi-bluetooth-and-proximity]] |
| **GCM** | Galois/Counter Mode (AES authenticated encryption) | [[08-keychain-on-ios]] |
| **GDPR** | General Data Protection Regulation | [[00-ios-forensics-landscape-and-authorization]] |
| **GID** | Group ID (per-SoC-model fused AES key) | [[02-image4-personalization-shsh]] |
| **GL** | Guarded Level (GL0–GL2; Apple GXF lateral levels) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **GMT** | Greenwich Mean Time | [[00-the-ios-timestamp-zoo]] |
| **GNSS** | Global Navigation Satellite System | [[05-radios-wifi-bt-nfc-uwb]] |
| **GOT** | Global Offset Table | [[00-mach-o-arm64-deep-dive]] |
| **GPS** | Global Positioning System | [[03-trackpad-keyboard-and-apple-pencil]] |
| **GPT** | GUID Partition Table | [[03-storage-nand-aes-effaceable]] |
| **GPU** | Graphics Processing Unit | [[01-cpu-gpu-npu-microarchitecture]] |
| **GSA** | Grand Slam Authentication (Apple account-auth protocol) | [[07-apple-account-icloud-and-apns]] |
| **GSMA** | GSM Association | [[04-baseband-and-cellular]] |
| **GUID** | Globally Unique Identifier | [[04-continuity-with-the-mac]] |
| **GUTI** | Globally Unique Temporary Identifier (LTE/5G) | [[04-baseband-and-cellular]] |
| **GXF** | Guarded eXecution Feature (Apple-proprietary guarded levels) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **HEVC** | High Efficiency Video Coding (H.265) | [[00-how-ipados-diverges-from-ios]] |
| **HFP** | Hands-Free Profile (Bluetooth) | [[04-wifi-bluetooth-and-proximity]] |
| **HFS+** | Hierarchical File System Plus (Mac OS Extended; legacy iOS ≤ 10) | [[03-storage-nand-aes-effaceable]] |
| **HID** | Human Interface Device | [[03-trackpad-keyboard-and-apple-pencil]] |
| **HIPAA** | Health Insurance Portability and Accountability Act | [[10-health-and-fitness]] |
| **HMAC** | Hash-based Message Authentication Code | [[01-screen-time-and-content-privacy-restrictions]] |
| **HPKE** | Hybrid Public Key Encryption (backs AEA) | [[02-the-dyld-shared-cache]] |
| **HPKP** | HTTP Public Key Pinning (deprecated web mechanism) | [[03-certificate-pinning-and-bypass]] |
| **HRV** | Heart Rate Variability (HealthKit) | [[10-health-and-fitness]] |
| **HSA2** | Apple's current two-factor / trusted-device scheme | [[07-apple-account-icloud-and-apns]] |
| **HSM** | Hardware Security Module (Cloud Key Vault) | [[08-keychain-on-ios]] |
| **HSTS** | HTTP Strict Transport Security | [[02-traffic-interception-and-tls]] |
| **HTTP** | HyperText Transfer Protocol | [[00-the-ios-timestamp-zoo]] |
| **HUD** | Heads-Up Display (⌘-hold shortcut overlay) | [[03-trackpad-keyboard-and-apple-pencil]] |
| **iAP2** | interface Accessory Protocol 2 (MFi accessories) | [[04-wifi-bluetooth-and-proximity]] |
| **IAP** | In-App Purchase | [[06-code-signing-and-provisioning-in-depth]] |
| **ICCID** | Integrated Circuit Card Identifier (SIM/profile serial; ITU-T E.118) | [[06-cellular-baseband-esim-and-identifiers]] |
| **IDFA** | Identifier for Advertisers (cross-app, ATT-gated) | [[06-cellular-baseband-esim-and-identifiers]] |
| **IDFV** | Identifier for Vendor (one developer's apps) | [[06-cellular-baseband-esim-and-identifiers]] |
| **IDS** | Identity Services (`identityservicesd`; iMessage/FaceTime routing) | [[07-apple-account-icloud-and-apns]] |
| **IEEE** | Institute of Electrical and Electronics Engineers | [[00-the-ios-timestamp-zoo]] |
| **IKEv2** | Internet Key Exchange version 2 (VPN) | [[04-configuration-profiles-and-mobileconfig]] |
| **iLEAPP** | iOS Logs, Events, And Plist Parser (Brignoni) | [[01-building-a-unified-timeline]] |
| **IM4M** | Image4 Manifest (the Apple-signed authorization; the SHSH "blob") | [[01-boot-chain-securerom-iboot]] |
| **IM4P** | Image4 Payload (one firmware component) | [[00-xnu-on-mobile]] |
| **IM4R** | Image4 Restore Info (carries the raw boot nonce) | [[01-boot-chain-securerom-iboot]] |
| **IMEI** | International Mobile Equipment Identity (TAC+serial+Luhn) | [[04-baseband-and-cellular]] |
| **IMEISV** | IMEI Software Version | [[06-cellular-baseband-esim-and-identifiers]] |
| **IMG4 / Image4** | Apple's DER-encoded ASN.1 secure-boot container format | [[00-xnu-on-mobile]] |
| **IMP** | (Objective-C) method Implementation pointer | [[06-objection-swizzling-and-runtime-exploration]] |
| **IMS** | IP Multimedia Subsystem (SIP voice/SMS-over-IP) | [[04-baseband-and-cellular]] |
| **IMSI** | International Mobile Subscriber Identity (MCC+MNC+MSIN) | [[04-baseband-and-cellular]] |
| **IMU** | Inertial Measurement Unit (accelerometer + gyro) | [[07-connectivity-power-sensors-dfu]] |
| **IOC** | Indicator of Compromise | [[03-forensics-and-dev-workstation-setup]] |
| **IOMMU** | Input-Output Memory Management Unit (Apple's is DART) | [[04-baseband-and-cellular]] |
| **IOP** | I/O Processor (the SEP mailbox nub) | [[01-sep-sepos-deep-dive]] |
| **IPA** | iOS App Store Package (`.ipa`); also Investigatory Powers Act 2016 (UK) | [[04-the-app-bundle-and-ipa-structure]] / [[06-icloud-acquisition-and-advanced-data-protection]] |
| **IPC** | Inter-Process Communication | [[00-xnu-on-mobile]] |
| **IPS** | Incident Reporting System (the crash/panic/jetsam report format) | [[09-unified-logging-and-sysdiagnose]] |
| **IPsec** | Internet Protocol Security (VPN) | [[04-configuration-profiles-and-mobileconfig]] |
| **IPSW** | iPhone/iPad Software (Apple firmware restore bundle) | [[00-xnu-on-mobile]] |
| **IR** | Infrared (Face ID); also Incident Response | [[06-biometrics-hardware-faceid-touchid]] / [[02-correlation-and-anti-forensics]] |
| **IRK** | Identity Resolving Key (resolves BLE RPAs; in keychain) | [[04-wifi-bluetooth-and-proximity]] |
| **ISA** | Instruction Set Architecture | [[05-pro-and-developer-workflows-on-ipad]] |
| **JID** | Jabber ID (WhatsApp peer identifier) | [[11-third-party-app-methodology]] |
| **JIT** | Just-In-Time (compilation; the W^X exception) | [[02-macos-to-ios-mental-model-reset]] |
| **JOP** | Jump-Oriented Programming | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **JSON** | JavaScript Object Notation | [[03-declarative-device-management]] |
| **JSONL** | JSON Lines | [[01-building-a-unified-timeline]] |
| **JTAG** | Joint Test Action Group (boundary-scan debug interface) | [[02-secure-enclave-hardware]] |
| **JWT** | JSON Web Token | [[07-apple-account-icloud-and-apns]] |
| **KASLR** | Kernel Address Space Layout Randomization | [[00-xnu-on-mobile]] |
| **KBAG** | Keybag (`{type, IV, wrapped-key}` set inside an encrypted IM4P) | [[02-image4-personalization-shsh]] |
| **KDF** | Key Derivation Function | [[03-storage-nand-aes-effaceable]] |
| **KDK** | Kernel Development Kit (per-build kernel + symbols) | [[00-xnu-on-mobile]] |
| **KEK** | Key Encryption Key | [[03-storage-nand-aes-effaceable]] |
| **KEM** | Key Encapsulation Mechanism | [[07-apple-account-icloud-and-apns]] |
| **KEXT / kext** | Kernel Extension (all prelinked into the kernelcache on iOS) | [[00-mach-o-arm64-deep-dive]] |
| **KFD** | Kernel File Descriptor (PUAF primitive family) | [[07-the-jailbreak-landscape-2026]] |
| **KIP** | Kernel Integrity Protection (umbrella for KTRR/CTRR) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KPP** | Kernel Patch Protection ("watchtower"; A8–A9) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KTRR** | Kernel Text Read-only Region (hardware kernel-text immutability) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KTX** | Khronos TeXture (GPU-compressed snapshot image format) | [[01-windowing-multitasking-and-external-display]] |
| **KVS** | Key-Value Store (`applicationState.db` blobs) | [[00-app-sandbox-and-filesystem-layout]] |
| **LAC** | Location Area Code | [[06-cellular-baseband-esim-and-identifiers]] |
| **LAI** | Location Area Identity (`EF_LOCI`) | [[06-cellular-baseband-esim-and-identifiers]] |
| **LAVA** | LEAPP Artifact Viewer App | [[01-building-a-unified-timeline]] |
| **LDM** | Lockdown Mode (opt-in attack-surface reduction) | [[09-advanced-protections-lockdown-sdp-adp]] |
| **LEAPP** | Logs, Events, And Plist Parser (the parser family) | [[01-building-a-unified-timeline]] |
| **LLB** | Low-Level Bootloader (`illb`; folded into iBoot on A10+) | [[01-boot-chain-securerom-iboot]] |
| **LLM** | Large Language Model | [[00-shortcuts-and-the-automation-surface]] |
| **LLW** | Low-Latency Wi-Fi (`llw0`; Continuity AV) | [[04-continuity-with-the-mac]] |
| **LOI** | Location of Interest | [[07-location-history]] |
| **LPA** | Local Profile Assistant (on-device eSIM agent) | [[04-baseband-and-cellular]] |
| **LPDDR5X** | Low-Power Double Data Rate 5X (memory) | [[00-how-ipados-diverges-from-ios]] |
| **LPE** | Local Privilege Escalation | [[01-sep-sepos-deep-dive]] |
| **LRU** | Least Recently Used | [[06-memory-jetsam-app-lifecycle]] |
| **LTK** | Long-Term Key (BLE bond) | [[04-wifi-bluetooth-and-proximity]] |
| **LTPO** | Low-Temperature Polycrystalline Oxide (variable-refresh OLED) | [[07-connectivity-power-sensors-dfu]] |
| **LWCR** | Lightweight Code Requirement (DER launch constraints, iOS 16+) | [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **LZFSE** | Lempel-Ziv Finite State Entropy (compression; iOS 14+ kernelcache) | [[00-xnu-on-mobile]] |
| **LZSS** | Lempel-Ziv-Storer-Szymanski (older kernelcache compression) | [[00-xnu-on-mobile]] |
| **MAC** | Media Access Control (address); also Mandatory Access Control (TrustedBSD) | [[05-radios-wifi-bt-nfc-uwb]] / [[05-the-sandbox-and-tcc]] |
| **MACF** | Mandatory Access Control Framework | [[00-xnu-on-mobile]] |
| **MAS** | Mobile Application Security (OWASP project umbrella) | [[10-owasp-mastg-and-app-security-testing]] |
| **MASQUE** | Multiplexed Application Substrate over QUIC Encryption | [[01-networkextension-and-vpn]] |
| **MASTG** | Mobile Application Security Testing Guide (OWASP) | [[10-owasp-mastg-and-app-security-testing]] |
| **MASVS** | Mobile Application Security Verification Standard (OWASP) | [[03-certificate-pinning-and-bypass]] |
| **MASWE** | Mobile Application Security Weakness Enumeration (OWASP) | [[10-owasp-mastg-and-app-security-testing]] |
| **MCC** | Mobile Country Code (IMSI field) | [[06-cellular-baseband-esim-and-identifiers]] |
| **MCM** | Mobile Container Manager (`containermanagerd`) | [[08-filesystem-layout-and-containers]] |
| **MDM** | Mobile Device Management | [[02-mdm-supervision-and-abm]] |
| **MEID** | Mobile Equipment Identifier (14-hex, CDMA legacy) | [[04-baseband-and-cellular]] |
| **MF** | Master File (SIM filesystem root) | [[06-cellular-baseband-esim-and-identifiers]] |
| **MFi** | Made for iPhone (accessory authentication) | [[07-connectivity-power-sensors-dfu]] |
| **MID** | Machine ID (anisette identifier) | [[07-apple-account-icloud-and-apns]] |
| **MIE** | Memory Integrity Enforcement (always-on HW memory tagging; A19/M5) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **MIG** | Mach Interface Generator (type-safe Mach IPC stubs) | [[05-processes-mach-xpc]] |
| **MII** | Major Industry Identifier (ICCID leading digits, `89`) | [[06-cellular-baseband-esim-and-identifiers]] |
| **MIME** | Multipurpose Internet Mail Extensions | [[09-mail-notes-calendar-reminders]] |
| **MITM** | Man-in-the-Middle | [[02-traffic-interception-and-tls]] |
| **ML** | Machine Learning | [[01-screen-time-and-content-privacy-restrictions]] |
| **ML-KEM** | Module-Lattice Key Encapsulation Mechanism (Kyber; PQ3) | [[07-apple-account-icloud-and-apns]] |
| **MLAT** | Mutual Legal Assistance Treaty | [[06-icloud-acquisition-and-advanced-data-protection]] |
| **MLO** | Multi-Link Operation (Wi-Fi 7 key feature) | [[05-radios-wifi-bt-nfc-uwb]] |
| **MLS** | Messaging Layer Security | [[04-communications-imessage-and-sms]] |
| **MMS** | Multimedia Messaging Service | [[04-communications-imessage-and-sms]] |
| **MMSC** | Multimedia Messaging Service Center (carrier) | [[04-baseband-and-cellular]] |
| **MNC** | Mobile Network Code (IMSI field) | [[06-cellular-baseband-esim-and-identifiers]] |
| **MPE** | Memory Protection Engine (SEP DRAM encrypt + authenticate) | [[02-secure-enclave-hardware]] |
| **MSIN** | Mobile Subscriber Identification Number (IMSI tail) | [[04-baseband-and-cellular]] |
| **MSISDN** | Mobile Station ISDN Number (the dialable phone number, E.164) | [[06-cellular-baseband-esim-and-identifiers]] |
| **MSL** | Malloc Stack Logging | [[11-debugging-instruments-and-lldb-for-ios]] |
| **mTLS** | mutual TLS | [[04-logical-acquisition-with-libimobiledevice]] |
| **MTE** | Memory Tagging Extension (Arm `FEAT_MTE`) | [[01-cpu-gpu-npu-microarchitecture]] |
| **MVT** | Mobile Verification Toolkit (Amnesty; `mvt-ios`) | [[09-advanced-protections-lockdown-sdp-adp]] |
| **MVVM** | Model-View-ViewModel | [[02-swift-swiftui-uikit-and-app-architecture]] |
| **mDNS** | multicast DNS (Bonjour) | [[04-continuity-with-the-mac]] |
| **NAN** | Neighbor Awareness Networking (Wi-Fi Aware) | [[04-wifi-bluetooth-and-proximity]] |
| **NAND** | (Not-AND) flash storage | [[03-storage-nand-aes-effaceable]] |
| **NAS** | Non-Access Stratum (cellular L3 mobility/session) | [[04-baseband-and-cellular]] |
| **NCM** | Network Control Model (Ethernet-over-USB) | [[10-device-services-and-backups]] |
| **NDJSON** | Newline-Delimited JSON (`.ips` body format) | [[12-unified-logs-sysdiagnose-crash-network]] |
| **NE** | NetworkExtension (the only sanctioned filter/proxy/tunnel surface) | [[01-networkextension-and-vpn]] |
| **NECP** | Network Extension Control Policy (XNU per-flow→process engine) | [[00-the-ios-networking-stack]] |
| **NFC** | Near-Field Communication | [[05-radios-wifi-bt-nfc-uwb]] |
| **NIST** | National Institute of Standards and Technology | [[03-forensics-and-dev-workstation-setup]] |
| **NPU** | Neural Processing Unit | [[01-cpu-gpu-npu-microarchitecture]] |
| **NSE** | Notification Service Extension | [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **NTFS** | New Technology File System | [[02-files-external-storage-and-document-providers]] |
| **NTP** | Network Time Protocol | [[08-acquisition-sop-and-chain-of-custody]] |
| **NVD** | National Vulnerability Database | [[10-owasp-mastg-and-app-security-testing]] |
| **NVMe** | Non-Volatile Memory express | [[03-storage-nand-aes-effaceable]] |
| **NVRAM** | Non-Volatile RAM (boot-environment region) | [[01-boot-chain-securerom-iboot]] |
| **OCSP** | Online Certificate Status Protocol | [[08-keychain-on-ios]] |
| **ODR** | On-Demand Resources | [[04-the-app-bundle-and-ipa-structure]] |
| **OHTTP** | Oblivious HTTP | [[01-networkextension-and-vpn]] |
| **OID** | Object Identifier (X.509) | [[08-trollstore-and-the-coretrust-bug]] |
| **OOL** | Out-Of-Line (shared-memory buffer for SEP bulk data) | [[01-sep-sepos-deep-dive]] |
| **OOM** | Out Of Memory | [[06-memory-jetsam-app-lifecycle]] |
| **ORM** | Object-Relational Mapping | [[06-photos-and-the-camera-roll]] |
| **OTP** | One-Time Password | [[07-apple-account-icloud-and-apns]] |
| **OWASP** | Open Worldwide Application Security Project | [[02-traffic-interception-and-tls]] |
| **OWL** | Open Wireless Link (TU Darmstadt AWDL/Find My RE) | [[05-find-my-and-the-ble-mesh]] |
| **PAC** | Pointer Authentication Code(s) (arm64e, A12+) | [[01-cpu-gpu-npu-microarchitecture]] |
| **PAD** | Presentation-Attack Detection (biometric spoof defense) | [[07-biometrics-security-architecture]] |
| **PAN** | Personal Area Network; also Primary Account Number (vs DPAN) | [[04-wifi-bluetooth-and-proximity]] |
| **PAuth** | (FEAT_)Pointer Authentication | [[01-cpu-gpu-npu-microarchitecture]] |
| **PBKDF2** | Password-Based Key Derivation Function 2 | [[02-data-protection-and-keybags]] |
| **PCC** | Private Cloud Compute (Apple's attested server-side AI) | [[00-shortcuts-and-the-automation-surface]] |
| **PCI** | Payment Card Industry | [[10-owasp-mastg-and-app-security-testing]] |
| **PCIe** | Peripheral Component Interconnect express | [[04-baseband-and-cellular]] |
| **PDCP** | Packet Data Convergence Protocol (cellular L2) | [[04-baseband-and-cellular]] |
| **PDP** | Packet Data Protocol (`pdp_ipN` cellular context) | [[00-the-ios-networking-stack]] |
| **PEM** | Privacy-Enhanced Mail (text cert encoding) | [[04-configuration-profiles-and-mobileconfig]] |
| **PID** | Process Identifier | [[05-processes-mach-xpc]] |
| **PIE** | Position-Independent Executable | [[00-mach-o-arm64-deep-dive]] |
| **PII** | Personally Identifiable Information | [[02-files-external-storage-and-document-providers]] |
| **PIR** | Private Information Retrieval | [[01-networkextension-and-vpn]] |
| **PKA** | Public Key Accelerator (SEP RSA/ECC engine) | [[02-secure-enclave-hardware]] |
| **PKCS** | Public-Key Cryptography Standards (PKCS#7, PKCS#12) | [[04-configuration-profiles-and-mobileconfig]] |
| **PKI** | Public Key Infrastructure | [[02-mdm-supervision-and-abm]] |
| **PLMN** | Public Land Mobile Network | [[04-baseband-and-cellular]] |
| **PLT** | Procedure Linkage Table | [[00-mach-o-arm64-deep-dive]] |
| **PMC** | Performance Monitoring Counter | [[11-debugging-instruments-and-lldb-for-ios]] |
| **PMIC** | Power Management Integrated Circuit | [[07-connectivity-power-sensors-dfu]] |
| **PMU** | Performance Monitoring Unit (HW counters); also Power Management Unit | [[01-cpu-gpu-npu-microarchitecture]] / [[07-connectivity-power-sensors-dfu]] |
| **PNL** | Preferred Network List (remembered Wi-Fi) | [[04-wifi-bluetooth-and-proximity]] |
| **POI** | Point of Interest | [[07-location-history]] |
| **POSIX** | Portable Operating System Interface | [[00-the-ios-timestamp-zoo]] |
| **PPID** | Parent Process ID | [[05-processes-mach-xpc]] |
| **PPL** | Page Protection Layer (A12–A14 page-table guard) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **PQ3** | iMessage post-quantum protocol (Apple "Level 3") | [[07-apple-account-icloud-and-apns]] |
| **PRNG** | Pseudo-Random Number Generator | [[10-owasp-mastg-and-app-security-testing]] |
| **PSK** | Pre-Shared Key (Wi-Fi) | [[08-keychain-on-ios]] |
| **PUAF** | Physical Use-After-Free (KFD kernel-r/w primitive) | [[07-the-jailbreak-landscape-2026]] |
| **QLC** | Quad-Level Cell (NAND) | [[03-storage-nand-aes-effaceable]] |
| **QMI** | Qualcomm MSM Interface (AP↔modem control protocol) | [[04-baseband-and-cellular]] |
| **QoS** | Quality of Service (scheduling class) | [[01-cpu-gpu-npu-microarchitecture]] |
| **QR** | Quick Response (code) | [[04-configuration-profiles-and-mobileconfig]] |
| **QUIC** | Quick UDP Internet Connections (RemoteXPC/RSD tunnel transport) | [[03-forensics-and-dev-workstation-setup]] |
| **RAM** | Random Access Memory | [[00-how-ipados-diverges-from-ios]] |
| **RASP** | Runtime Application Self-Protection | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **RAT** | Radio Access Technology | [[04-baseband-and-cellular]] |
| **RCE** | Remote Code Execution | [[09-advanced-protections-lockdown-sdp-adp]] |
| **RCS** | Rich Communication Services | [[01-ios-platform-landscape-and-history]] |
| **RE** | Reverse Engineering | [[05-pro-and-developer-workflows-on-ipad]] |
| **REPL** | Read-Eval-Print Loop | [[05-dynamic-analysis-with-frida]] |
| **RF** | Radio Frequency | [[02-correlation-and-anti-forensics]] |
| **RFC** | Request for Comments | [[02-data-protection-and-keybags]] |
| **RIPA** | Regulation of Investigatory Powers Act (UK) | [[00-ios-forensics-landscape-and-authorization]] |
| **RLC** | Radio Link Control (cellular L2) | [[04-baseband-and-cellular]] |
| **ROB** | Reorder Buffer (CPU microarchitecture) | [[01-cpu-gpu-npu-microarchitecture]] |
| **ROM** | Read-Only Memory | [[07-the-jailbreak-landscape-2026]] |
| **ROP** | Return-Oriented Programming | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **RPA** | Resolvable Private Address (rotating BLE address) | [[04-wifi-bluetooth-and-proximity]] |
| **RPC** | Remote Procedure Call | [[05-dynamic-analysis-with-frida]] |
| **RRC** | Radio Resource Control (cellular L3) | [[04-baseband-and-cellular]] |
| **RSA** | Rivest-Shamir-Adleman | [[02-secure-enclave-hardware]] |
| **RSD** | RemoteServiceDiscovery (iOS 17+ RemoteXPC) | [[02-macos-to-ios-mental-model-reset]] |
| **RSP** | Remote SIM Provisioning (GSMA SGP.21/.22) | [[04-baseband-and-cellular]] |
| **RSR** | Rapid Security Response (out-of-band patch; suffix `(a)`/`(b)`) | [[01-ios-platform-landscape-and-history]] |
| **RTC** | Real-Time Clock | [[07-connectivity-power-sensors-dfu]] |
| **RTOS** | Real-Time Operating System (modem OS) | [[04-baseband-and-cellular]] |
| **RVI** | Remote Virtual Interface (`rvictl`; Mac-side packet capture) | [[00-the-ios-networking-stack]] |
| **SA** | Standalone (5G SA) | [[06-cellular-baseband-esim-and-identifiers]] |
| **SANS** | SysAdmin, Audit, Network, and Security (Institute; FOR585) | [[01-building-a-unified-timeline]] |
| **SAST** | Static Application Security Testing | [[10-owasp-mastg-and-app-security-testing]] |
| **SBPL** | Sandbox Profile Language (Lisp-like; compiled into `Sandbox.kext`) | [[05-the-sandbox-and-tcc]] |
| **SCEP** | Simple Certificate Enrollment Protocol | [[02-mdm-supervision-and-abm]] |
| **SCIP** | SEP memory-execution permission settings (set by the Boot Monitor) | [[02-secure-enclave-hardware]] |
| **SCT** | Signed Certificate Timestamp (Certificate Transparency) | [[02-traffic-interception-and-tls]] |
| **SDK** | Software Development Kit | [[00-how-to-use-this-course]] |
| **SDOM** | Security Domain (Image4 field) | [[01-boot-chain-securerom-iboot]] |
| **SDP** | Stolen Device Protection (biometric + 1 h Security Delay; iOS 17.3+) | [[07-biometrics-security-architecture]] |
| **SE** | Secure Element (certified payment/transit chip) | [[00-the-ios-security-model]] |
| **SEE** | SQLite Encryption Extension (page-level AES; not plain `sqlite3`) | [[05-find-my-and-the-ble-mesh]] |
| **SEGB** | Segmented Binary (Biome stream/event-log container; v1/v2) | [[02-biome-and-segb-streams]] |
| **SEL** | Selector (interned Objective-C method name) | [[06-objection-swizzling-and-runtime-exploration]] |
| **SEP** | Secure Enclave Processor | [[00-the-ios-security-model]] |
| **SEPOS / sepOS** | Secure Enclave Processor OS (Apple-customized L4 microkernel) | [[01-sep-sepos-deep-dive]] |
| **SEPROM** | the SEP's immutable boot ROM (SEP analogue of SecureROM) | [[01-sep-sepos-deep-dive]] |
| **SHA** | Secure Hash Algorithm (SHA-1 / SHA-256 / SHA-384) | [[05-backup-restore-migration-and-transfer]] |
| **SHM / -shm** | Shared Memory (SQLite WAL-index sidecar) | [[04-communications-imessage-and-sms]] |
| **SHSH** | Signed Hash (boot personalization blob; the APTicket) | [[01-boot-chain-securerom-iboot]] |
| **SI** | International System of Units (SI seconds) | [[00-the-ios-timestamp-zoo]] |
| **SIDF** | Subscription Identifier De-concealing Function (5G UDM) | [[06-cellular-baseband-esim-and-identifiers]] |
| **SIP** | System Integrity Protection (macOS; no direct iOS equivalent) | [[00-the-ios-security-model]] |
| **SK** | Secure Kernel (GL1 microkernel managing exclaves) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **SKU** | Stock Keeping Unit (`BasebandRegionSKU`) | [[04-baseband-and-cellular]] |
| **SLC** | System-Level Cache (SoC fabric); also Single-Level Cell (NAND write buffer) | [[01-cpu-gpu-npu-microarchitecture]] / [[03-storage-nand-aes-effaceable]] |
| **SLF0** | the structured-log format magic of an `.xcactivitylog` | [[00-ios-xcode-and-the-build-system]] |
| **SM-DP+** | Subscription Manager – Data Preparation+ (carrier eSIM server) | [[06-cellular-baseband-esim-and-identifiers]] |
| **SM-DS** | Subscription Manager – Discovery Server (eSIM) | [[06-cellular-baseband-esim-and-identifiers]] |
| **SME** | Scalable Matrix Extension (Armv9.2-A; Apple M4+) | [[01-cpu-gpu-npu-microarchitecture]] |
| **SMS** | Short Message Service | [[04-communications-imessage-and-sms]] |
| **SNE** | Secure Neural Engine (SEP-gated biometric matcher) | [[06-biometrics-hardware-faceid-touchid]] |
| **SNI** | Server Name Indication (TLS) | [[00-the-ios-networking-stack]] |
| **SoC** | System on a Chip | [[00-soc-lineup-and-device-matrix]] |
| **SOP** | Standard Operating Procedure | [[08-acquisition-sop-and-chain-of-custody]] |
| **SOS** | Secure Object Sharing (legacy iCloud Keychain sync) | [[08-keychain-on-ios]] |
| **SOW** | Statement of Work | [[00-mach-o-arm64-deep-dive]] |
| **SPA** | Simple Power Analysis (side-channel) | [[02-secure-enclave-hardware]] |
| **SPI** | System Programming Interface (private Apple API) | [[04-code-signing-amfi-entitlements]] |
| **SPKI** | SubjectPublicKeyInfo (the thing modern pins hash) | [[03-certificate-pinning-and-bypass]] |
| **SPM** | Swift Package Manager | [[07-frameworks-dylibs-and-dynamic-linking]] |
| **SPRR** | Shadow Permission Remapping Register | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **SPTM** | Secure Page Table Monitor (GL2; sole page-table authority, A15+/M2+) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **SRP** | Secure Remote Password | [[10-device-services-and-backups]] |
| **SS7** | Signalling System No. 7 | [[04-baseband-and-cellular]] |
| **SSH** | Secure Shell | [[05-pro-and-developer-workflows-on-ipad]] |
| **SSID** | Service Set Identifier (Wi-Fi network name) | [[04-wifi-bluetooth-and-proximity]] |
| **SSV** | Signed System Volume (Merkle-sealed read-only system volume) | [[03-apfs-on-ios-volumes]] |
| **STIX / STIX2** | Structured Threat Information eXpression (v2; the MVT IOC format) | [[03-forensics-and-dev-workstation-setup]] |
| **STS** | Scrambled Timestamp Sequence (802.15.4z secure ranging) | [[05-radios-wifi-bt-nfc-uwb]] |
| **SUCI** | Subscription Concealed Identifier (encrypted SUPI) | [[06-cellular-baseband-esim-and-identifiers]] |
| **SUPI** | Subscription Permanent Identifier (5G successor to IMSI) | [[06-cellular-baseband-esim-and-identifiers]] |
| **SVN** | Software Version Number | [[06-cellular-baseband-esim-and-identifiers]] |
| **SWGDE** | Scientific Working Group on Digital Evidence | [[08-acquisition-sop-and-chain-of-custody]] |
| **TAC** | Type Allocation Code (first 8 of an IMEI → make/model) | [[00-soc-lineup-and-device-matrix]] |
| **TBDR** | Tile-Based Deferred Rendering (Apple GPU architecture) | [[01-cpu-gpu-npu-microarchitecture]] |
| **TBI** | Top-Byte-Ignore (ARM pointer-tagging feature) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **TCC** | Transparency, Consent, and Control (privacy permissions; `tccd`) | [[05-the-sandbox-and-tcc]] |
| **TCN** | Technical Capability Notice (UK Investigatory Powers Act order) | [[09-advanced-protections-lockdown-sdp-adp]] |
| **TLC** | Triple-Level Cell (NAND) | [[03-storage-nand-aes-effaceable]] |
| **TLS** | Transport Layer Security | [[02-traffic-interception-and-tls]] |
| **TLV** | Type-Length-Value (keybag encoding); also Thread-Local Variables (Mach-O) | [[07-decrypting-backups-and-images]] / [[00-mach-o-arm64-deep-dive]] |
| **TMSI** | Temporary Mobile Subscriber Identity (2G/3G) | [[04-baseband-and-cellular]] |
| **TOCTOU** | Time-Of-Check / Time-Of-Use | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **ToF** | Time-of-Flight (UWB/LiDAR ranging) | [[05-radios-wifi-bt-nfc-uwb]] |
| **TRIM** | the flash-storage block-reclamation hint (defeats deleted-file carving) | [[14-deleted-data-recovery]] |
| **TRNG** | True Random Number Generator (SEP) | [[02-secure-enclave-hardware]] |
| **TSS** | (Tatsu) Signing Server (`gs.apple.com/TSS/controller`) | [[02-image4-personalization-shsh]] |
| **TSV** | Tab-Separated Values | [[01-building-a-unified-timeline]] |
| **TUN** | network TUNnel (virtual interface) | [[02-macos-to-ios-mental-model-reset]] |
| **TXM** | Trusted Execution Monitor (guarded code-signing/entitlement authority, A15+/M2+) | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **UAF** | Use-After-Free | [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **UDID** | Unique Device Identifier | [[01-ios-platform-landscape-and-history]] |
| **UDM** | Unified Data Management (5G core) | [[06-cellular-baseband-esim-and-identifiers]] |
| **UE** | User Equipment (cellular) | [[06-cellular-baseband-esim-and-identifiers]] |
| **UFED** | Universal Forensic Extraction Device (Cellebrite) | [[04-logical-acquisition-with-libimobiledevice]] |
| **UICC** | Universal Integrated Circuit Card (the physical SIM) | [[04-baseband-and-cellular]] |
| **UID** | Unique ID (per-device fused SEP key); also Unix user id (`mobile` = 501) | [[02-secure-enclave-hardware]] / [[02-macos-to-ios-mental-model-reset]] |
| **UIM** | (e)SIM card-application access service (QMI) | [[06-cellular-baseband-esim-and-identifiers]] |
| **ULEB** | Unsigned Little-Endian Base-128 (encoding) | [[00-mach-o-arm64-deep-dive]] |
| **UMA** | Unified Memory Architecture (one on-package LPDDR pool) | [[01-cpu-gpu-npu-microarchitecture]] |
| **USB** | Universal Serial Bus | [[02-files-external-storage-and-document-providers]] |
| **UTC** | Coordinated Universal Time | [[08-acquisition-sop-and-chain-of-custody]] |
| **UTI** | Uniform Type Identifier | [[11-third-party-app-methodology]] |
| **UUID** | Universally Unique Identifier | [[08-filesystem-layout-and-containers]] |
| **UWB** | Ultra-Wideband (impulse-radio ranging; U1/U2 chips) | [[05-radios-wifi-bt-nfc-uwb]] |
| **VA** | Virtual Address | [[00-mach-o-arm64-deep-dive]] |
| **VCSEL** | Vertical-Cavity Surface-Emitting Laser (Face ID dot projector) | [[06-biometrics-hardware-faceid-touchid]] |
| **VEK** | Volume Encryption Key | [[02-data-protection-and-keybags]] |
| **VFS** | Virtual File System | [[03-apfs-on-ios-volumes]] |
| **VM** | Virtual Memory | [[00-xnu-on-mobile]] |
| **VNC** | Virtual Network Computing | [[05-pro-and-developer-workflows-on-ipad]] |
| **VoIP** | Voice over IP | [[03-app-lifecycle-scenes-and-background-execution]] |
| **VoLTE** | Voice over LTE | [[04-baseband-and-cellular]] |
| **VoNR** | Voice over New Radio (5G) | [[06-cellular-baseband-esim-and-identifiers]] |
| **VPN** | Virtual Private Network | [[01-networkextension-and-vpn]] |
| **VPP** | Volume Purchase Program | [[02-mdm-supervision-and-abm]] |
| **VVM** | Visual Voicemail | [[05-call-history-voicemail-contacts-interactions]] |
| **W^X** | Write XOR Execute (no simultaneously writable + executable page) | [[02-macos-to-ios-mental-model-reset]] |
| **WAL** | Write-Ahead Log (SQLite `-wal` sidecar) | [[01-knowledgec-db-deep-dive]] |
| **WASM** | WebAssembly | [[05-pro-and-developer-workflows-on-ipad]] |
| **WMO** | Whole-Module Optimization (Release Swift) | [[00-ios-xcode-and-the-build-system]] |
| **WMS** | Wireless Messaging Service (QMI) | [[06-cellular-baseband-esim-and-identifiers]] |
| **WORM** | Write Once Read Many (media) | [[08-acquisition-sop-and-chain-of-custody]] |
| **WPA2** | Wi-Fi Protected Access 2 | [[04-configuration-profiles-and-mobileconfig]] |
| **WPKY** | Wrapped Per-class KeY (RFC-3394, in a keybag) | [[07-decrypting-backups-and-images]] |
| **WSTG** | Web Security Testing Guide (OWASP) | [[10-owasp-mastg-and-app-security-testing]] |
| **WWAN** | Wireless Wide Area Network (cellular) | [[12-unified-logs-sysdiagnose-crash-network]] |
| **WWDR** | (Apple) Worldwide Developer Relations (CA) | [[06-code-signing-and-provisioning-in-depth]] |
| **xART** | eXtended Anti-Replay Technology / Token (SEP anti-rollback) | [[03-apfs-on-ios-volumes]] |
| **XEX** | Xor-Encrypt-Xor (AES mode; SEP DRAM) | [[02-secure-enclave-hardware]] |
| **XNU** | X is Not Unix (Apple's hybrid Mach + BSD + IOKit kernel) | [[00-xnu-on-mobile]] |
| **XPC** | Cross-Process Communication (Apple high-level IPC; RemoteXPC over RSD) | [[05-processes-mach-xpc]] |
| **XTS** | XEX-based Tweaked-codebook with Ciphertext Stealing (AES storage mode) | [[03-storage-nand-aes-effaceable]] |

---

## Quick-reference clusters

Groupings that help you remember which acronyms belong to the same subsystem.

### Boot chain (Apple Silicon iOS)

```
SecureROM (BootROM) → LLB → iBoot → kernelcache (XNU) → launchd
                         every stage Apple-signed via IMG4 / IM4M (SHSH), personalized to the ECID
```
SEP boots in parallel: SEPROM → sepOS (`sepi`). Relevant: [[01-boot-chain-securerom-iboot]], [[02-image4-personalization-shsh]].

### Image4 / personalization vocabulary

| Term | Role |
|---|---|
| IMG4 | the container format (DER ASN.1) |
| IM4P | Payload — one firmware component |
| IM4M | Manifest — the Apple-signed authorization (= SHSH blob, a.k.a. APTicket) |
| IM4R | Restore Info — carries the raw boot nonce (BNCN) |
| KBAG | the `{type, IV, wrapped-key}` set inside an encrypted IM4P |
| BNCH / BNCN | Boot Nonce Hash / raw generator |
| DGST / CEPO | per-component Digest / Certificate Epoch |
| ECID / CPID / BDID / CPRV | per-die / chip / board / revision identifiers TSS keys on |

Relevant: [[02-image4-personalization-shsh]], [[00-soc-lineup-and-device-matrix]].

### Data-Protection classes & key hierarchy

```
passcode ⊗ SEP UID  →  class keys (in the keybag, via AKS/sks)  →  per-file key (AES-XTS)  →  file bytes
```
| Class | `NSFileProtection…` | Available |
|---|---|---|
| A | Complete | only while unlocked |
| B | CompleteUnlessOpen | create-while-locked, read only when unlocked (Curve25519) |
| C | CompleteUntilFirstUserAuthentication (default) | from first unlock until reboot — the AFU window |
| D | None | always (UID-only); the only class readable at **BFU** |

BFU vs AFU is set by whether the passcode has been entered since boot; the ~72 h **inactivity reboot** demotes AFU→BFU. Relevant: [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]], [[03-passcode-bfu-afu-and-inactivity]].

### Kernel-hardening ladder

```
KPP → KTRR/CTRR (KIP) → PAC → PPL (APRR/SPRR + GXF) → SPTM/TXM (+ Secure Exclaves/SK) → MIE/EMTE
```
Relevant: [[06-kernel-hardening-pac-sptm-txm-mie]].

### Cellular identifier zoo

| Acronym | Identifies |
|---|---|
| IMEI / MEID | the device/modem (chassis) |
| IMSI / SUPI / SUCI | the subscriber (SUCI = encrypted SUPI) |
| ICCID | the SIM card / eSIM profile |
| EID | the eUICC (eSIM) hardware |
| MSISDN | the dialable phone number |
| TMSI / GUTI | rotating temporary subscriber identities |
| MCC / MNC / MSIN | the IMSI's country / network / subscriber fields |

Relevant: [[06-cellular-baseband-esim-and-identifiers]], [[04-baseband-and-cellular]].

---

## Collisions & dual meanings

A handful of letter-strings carry two meanings in this course — disambiguate by context:

| Acronym | Meaning 1 | Meaning 2 |
|---|---|---|
| **ADP** | Advanced Data Protection (iCloud E2EE) | Alternative Distribution Packet (EU off-store package) |
| **DMA** | Digital Markets Act (EU regulation) | Direct Memory Access (USB-DMA exploit) |
| **IPA** | iOS App Store Package (`.ipa`) | Investigatory Powers Act 2016 (UK) |
| **IR** | Infrared (Face ID) | Incident Response |
| **MAC** | Media Access Control (address) | Mandatory Access Control (TrustedBSD) |
| **PMU** | Performance Monitoring Unit (CPU counters) | Power Management Unit (PMIC) |
| **SLC** | System-Level Cache (SoC) | Single-Level Cell (NAND write buffer) |
| **TLV** | Type-Length-Value (keybag encoding) | Thread-Local Variables (Mach-O) |
| **UID** | Unique ID (fused SEP key) | Unix user id (`mobile` = 501) |
| **CI** | Certificate Issuer (GSMA eSIM) | Cell ID / Continuous Integration |

> 🪟 **macOS cross-reference:** for acronyms shared with the desktop platform (SIP, TCC, APFS, SSV, AMFI, XNU, XPC, SEP, KEK/VEK, W^X, MDM, ADP, …) see the sibling **macos-mastery/reference/acronyms.md**. iOS inverts the policy layer (no user shell, mandatory AMFI code-signing, a universal sandbox, per-file Data Protection), so the same acronym often does heavier lifting here.

---

*See also: [[glossary]] for full term definitions · [[file-paths]] / [[artifact-index]] for where these subsystems write to disk · [[tooling]] for the CLIs (`ipsw`, `pymobiledevice3`, `iLEAPP`, `APOLLO`, `mvt-ios`, `frida`) that decode them.*
