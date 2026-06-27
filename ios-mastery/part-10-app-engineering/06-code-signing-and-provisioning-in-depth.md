---
title: "Code signing & provisioning in depth"
part: "10 — iOS App Engineering"
lesson: 06
est_time: "50 min read + 20 min labs"
prerequisites: [code-signing-amfi-entitlements, the-app-bundle-and-ipa-structure]
tags: [ios, dev, code-signing, provisioning, certificates, forensics]
last_reviewed: 2026-06-26
---

# Code signing & provisioning in depth

> **In one sentence:** On iOS, a binary is allowed to run not because it is *notarized* but because a `embedded.mobileprovision` profile — Apple-signed, naming a certificate, an App ID, and a list of device UDIDs — authorizes a *specific build* of code carrying a *subset* of the profile's entitlements to execute on *specific hardware*, and AMFI enforces that contract at every launch.

## Why this matters

You already studied code signing from the security side in [[04-code-signing-amfi-entitlements]] — the CDHash, the trust cache, AMFI as the gatekeeper. This lesson is the same machinery from the **developer's chair**: the actual files Xcode generates, the keychain identity you can't see, the profile you can decode byte-for-byte, and the four failure messages that eat a third of every new iOS developer's first week. Master this and you can re-sign any recovered binary for dynamic analysis, read a seized `.mobileprovision` to attribute who built an app and which devices it was authorized for, and diagnose a "won't install" without flailing in Xcode's Signing & Capabilities pane. The macOS instinct — "just notarize it and it runs anywhere" — is *wrong* on iOS, and unlearning it is the whole game.

> 🖥️ **macOS contrast:** macOS answers "may this run?" with **Gatekeeper + notarization**: a Developer-ID-signed, Apple-notarized binary runs on *any* Mac, no device list, no per-machine authorization. iOS deletes that model. There is no notarization-for-execution and no "any device" — every non-App-Store build is bound to an explicit set of UDIDs (or, for in-house Enterprise, to "all devices owned by this org"). The provisioning profile *is* the iOS analogue of notarization, but it authorizes **(this code) × (these entitlements) × (these devices)** instead of "(this developer) anywhere." App Store apps are the exception that proves the rule: Apple re-signs them server-side and **strips the `embedded.mobileprovision` entirely** — a downloaded Store app carries no profile on disk and runs under the App Store's own trust path.

## Concepts

### The signing triad baked into a provisioning profile

A provisioning profile (`embedded.mobileprovision` inside the `.app`, `*.mobileprovision` in your library, `*.provisionprofile` for Mac) is a **CMS-signed property list**: an XML plist wrapped in a PKCS#7 / CMS (RFC 5652) container, signed *by Apple* after your developer-portal request. The CMS wrapper is what makes it tamper-evident — you cannot edit the plist and re-use it, because the Apple signature won't verify. Decoding it (`security cms -D`) reveals a dictionary whose three load-bearing keys form the **signing triad**:

```
embedded.mobileprovision  (CMS-signed plist)
├── DeveloperCertificates : [ <base64 DER X.509>, … ]   ← WHO may sign
├── Entitlements          : { application-identifier:…, … } ← WHAT (App ID + allowlist)
└── ProvisionedDevices    : [ "00008110-001A…", … ]      ← WHICH hardware
        (or ProvisionsAllDevices = true   for Enterprise in-house)
        (or  key absent                   for App Store distribution)
```

Plus the bookkeeping keys you'll read constantly: `Name`, `UUID` (the filename once Xcode installs it), `TeamIdentifier` / `ApplicationIdentifierPrefix` (your 10-char Team ID), `TeamName`, `CreationDate`, `ExpirationDate`, `Platform`, `Version`, and `IsXcodeManaged` (true when Xcode's "Automatically manage signing" minted it).

#### 1. The signing certificate — *who* may sign

`DeveloperCertificates` holds the **public-key certificates** (DER X.509, Apple-CA-issued) of every identity permitted to sign code under this profile. The matching **private keys never leave your login Keychain** — Apple never sees them. At install time the device checks that the leaf certificate in the binary's CMS signature matches one of these certs *and* chains to an Apple root. Certificate *type* dictates what the profile is for:

| Certificate type | Issued to | Used for | Lifetime |
|---|---|---|---|
| **Apple Development** | individual member | dev/debug builds on registered devices | 1 year |
| **Apple Distribution** | team (paid program) | App Store, TestFlight, Ad Hoc | 1 year |
| **Apple Enterprise (Distribution: In-House)** | ADEP org | internal-only distribution, no App Store | 1 year |
| **(legacy) iOS App Development / iOS Distribution** | older split per-platform certs | superseded by the unified "Apple …" certs | 1 year |

> The old per-platform cert names (*iOS App Development*, *iOS Distribution*) were unified into **Apple Development** / **Apple Distribution** in 2019 so one cert covers iOS, macOS, tvOS, watchOS. You'll still meet the legacy names in older profiles and in tools.

#### 2. The App ID — *what* (identity + entitlement allowlist)

Inside the profile's `Entitlements` dict, `application-identifier` is `TEAMID.bundle.id` — e.g. `9XYZ1234AB.com.acme.notes`. This is the **App ID**, and it comes in two flavors:

- **Explicit App ID** — `9XYZ1234AB.com.acme.notes`. Required for any app using App-ID-scoped capabilities: Push (APNs), iCloud, App Groups, Associated Domains, In-App Purchase, Sign in with Apple. The bundle ID of your binary must match *exactly*.
- **Wildcard App ID** — `9XYZ1234AB.*` (or a prefix-wildcard `…com.acme.*`). One profile signs many bundle IDs, but **cannot carry** the capabilities above (the system can't provision push for `*`). Free personal teams effectively get wildcard-style behavior with a forced unique bundle ID.

The rest of the `Entitlements` dict is the **allowlist** of capabilities this profile is authorized to grant: `get-task-allow` (debuggability — true for dev, **false/absent** for distribution), `aps-environment` (`development`/`production` push), `com.apple.developer.team-identifier`, `keychain-access-groups`, `com.apple.security.application-groups`, `com.apple.developer.associated-domains`, and so on.

#### 3. The device list — *which* hardware

`ProvisionedDevices` is an array of **UDIDs**. Pre-2018 devices use the old 40-hex-character UDID (a SHA-1-length digest); iPhone XS/XR and later (A12+, 2018+) use the modern **25-character** form — 24 hex digits split `XXXXXXXX-XXXXXXXXXXXXXXXX` by a single dash. A development or Ad-Hoc profile installs **only** on devices whose UDID is in this array. Two escape hatches:

- **`ProvisionsAllDevices = true`** — Enterprise (ADEP) in-house profiles only; no UDID list, installs on any device that trusts the enterprise cert. This is the key that **pirate "app store" installers** (TutuApp / AppValley-style) and other enterprise-certificate-abuse tooling historically rode on — pushing apps to arbitrary devices with no App Store review.
- **Key absent entirely** — the **App Store / TestFlight distribution** profile you generate in the portal carries no device list at all. And the app users actually download carries **no `embedded.mobileprovision` whatsoever**: Apple re-signs it and *strips* the profile during ingestion, so a shipped Store/TestFlight app runs under the App Store trust path with no profile on disk.

> 🔬 **Forensics note:** A recovered `embedded.mobileprovision` is a rich attribution artifact. `TeamName` + `TeamIdentifier` name the organization that built the app; `DeveloperCertificates` → decode each with `openssl x509` to recover the **Common Name** of the signing developer (e.g. `Apple Development: Jane Doe (ABC123DEF4)`); `ProvisionedDevices` is a literal **list of UDIDs that were in the developer's possession** when the profile was minted — often a roomful of test phones, sometimes the suspect's own device; `CreationDate`/`ExpirationDate` bound when the build was produced. A sideloaded-malware `.ipa` whose profile is `ProvisionsAllDevices` Enterprise tells you it leaned on an abused/stolen enterprise cert — a different investigative thread than an Ad-Hoc build naming five UDIDs.

### How the profile authorizes the binary: the subset rule

This is the rule that AMFI enforces and that generates most signing errors:

```
   ┌──────────────────────────────────────────────┐
   │ Profile Entitlements (the ALLOWLIST)         │
   │   application-identifier  = TEAM.com.acme.x   │
   │   aps-environment         = development       │
   │   get-task-allow          = true              │
   │   keychain-access-groups  = [TEAM.com.acme.x] │
   │   application-groups      = [group.com.acme]  │
   └──────────────────────────────────────────────┘
                        ⊇  (must contain)
   ┌──────────────────────────────────────────────┐
   │ Binary's SIGNED entitlements (the CLAIM)     │
   │   application-identifier  = TEAM.com.acme.x   │
   │   get-task-allow          = true              │
   └──────────────────────────────────────────────┘
```

**Every entitlement the binary claims must appear in the profile's allowlist, with a compatible value.** The binary may claim *fewer* than the profile allows (a subset) — that's fine. It may not claim *more*. The binary's entitlements live in its **code signature**, embedded by `codesign` from your `.entitlements` file; the profile's allowlist is what Apple signed off on at provisioning time. At launch, AMFI compares them. A mismatch is fatal: the app won't install or won't launch.

> 🖥️ **macOS contrast:** On macOS, entitlements are largely self-asserted in the signature and trusted if the binary is properly signed (with a few exceptions requiring provisioning profiles or special Apple grants). On iOS, **no entitlement is self-asserted** — the profile is the second party that had to agree, and Apple is the third party that signed the profile. Three signatures stand between your `get-task-allow` and a running debugger.

### Free personal team vs. paid program

You don't need the $99/yr Apple Developer Program to build for a device — a free **Personal Team** (any Apple Account added to Xcode) works, with sharp limits:

| | Free Personal Team | Paid Apple Developer Program ($99/yr) |
|---|---|---|
| **Profile lifetime** | **7 days** | **12 months** |
| **Cert** | Apple Development only | Development **+ Apple Distribution** |
| **Distribution** | none (device-local only) | App Store, TestFlight, Ad Hoc, Enterprise (separate ADEP) |
| **App IDs** | ~10 per 7-day window, forced-unique bundle IDs | 100s; explicit + wildcard |
| **Capabilities** | crippled — **no** Push, Associated Domains, App Groups, iCloud, etc. | full entitlement catalog |
| **Devices** | small per-account cap | 100 per device class per membership year |

The 7-day expiry is the defining free-tier pain: a sideloaded app **stops launching after a week** when its profile expires, and you must rebuild/re-deploy. This is exactly the constraint that AltStore/SideStore automate around (periodic background re-sign) and that EU alternative marketplaces ([[10-eu-dma-sideloading-and-alternative-marketplaces]]) eliminate.

> 🔬 **Forensics note:** A 7-day-lifetime development profile in a recovered app is a strong signal of **free-tier sideloading** (AltStore, SideStore, raw Xcode deploy) rather than App Store provenance — the app was put there by someone with physical/USB access and an Apple Account, not via the Store. Combine with the absence of a FairPlay-encrypted `SC_Info/` directory ([[03-fairplay-encryption-and-decrypting-app-store-apps]]) to confirm non-Store origin.

### The certificate + key + profile + keychain dance

The pieces are generated in a specific order, and confusing them is the root of "valid signing identity not found":

```
 1. Xcode/openssl generates a keypair → PRIVATE key stays in login Keychain,
    PUBLIC key goes into a CSR (Certificate Signing Request).
 2. CSR → Apple Developer portal → Apple's CA signs it → you download a .cer
    (your PUBLIC cert, chaining to "Apple Worldwide Developer Relations CA").
 3. Keychain pairs the downloaded .cer with the matching private key →
    this pair is a "signing identity" (security find-identity -v -p codesigning).
 4. You register an App ID + device UDIDs + capabilities in the portal →
    Apple mints a provisioning PROFILE binding (cert + App ID + devices) and
    CMS-signs it.
 5. codesign uses the identity (step 3) to hash+sign the binary, embeds your
    .entitlements, and the build copies the profile to App.app/embedded.mobileprovision.
```

The single most common breakage: the `.cer` lands on a machine **without the private key** (you exported the cert but not the identity). The cert is public and useless alone — only the `.p12`/`.pfx` (cert **+** private key) is a portable signing identity. This is why teams pass around `.p12` files (or use App Store Connect API keys + `fastlane match`, which stores the identity in a shared encrypted git repo).

> 🖥️ **macOS contrast:** Identical Keychain plumbing to Developer-ID signing you already did on macOS (`security find-identity -v -p codesigning` lists both Mac and iOS identities side by side). The novelty on iOS is **step 4** — there is no provisioning-profile step at all for a Developer-ID Mac app; you sign and notarize and ship. On iOS the profile is mandatory and Apple-signed.

### Anatomy of an iOS Mach-O code signature

The signature is a `LC_CODE_SIGNATURE` load command pointing at a **SuperBlob** (`CSMAGIC_EMBEDDED_SIGNATURE = 0xfade0cc0`) — a container of typed sub-blobs. Each is referenced by index from a **special-slot** table with negative indices:

| Magic | Blob | Special slot | Contents |
|---|---|---|---|
| `0xfade0c02` | **CodeDirectory** | (slot 0) | per-page SHA-256 hashes, CDHash, `identifier`, `teamid`, `flags` |
| `0xfade0c01` | Requirements vector | −2 | designated requirement (which cert must sign) |
| (resource dir) | CodeResources | −3 | hashes of bundle resources (`_CodeSignature/CodeResources`) |
| `0xfade7171` | **Entitlements (XML)** | −5 | the legacy plist-XML entitlements blob |
| `0xfade7172` | **Entitlements (DER)** | −7 | the **DER-encoded** entitlements — *mandatory since iOS 15* |
| `0xfade0b01` | CMS / BlobWrapper | — | the PKCS#7 signature (your leaf cert + chain) |

Two things matter for 2026-era iOS specifically:

1. **DER entitlements are mandatory.** Since iOS/iPadOS 15, the system reads entitlements from the **DER** blob in special slot **−7** (`0xfade7172`), not the XML in slot −5. `codesign` adds both by default (`--generate-entitlement-der`, on by default since macOS 12 Monterey's toolchain). A binary that carries only the old XML entitlements (slot −5 populated, slot −7 empty) **will not launch on iOS 15+** — this is the classic "re-sign to add DER entitlements" failure documented in Apple's *Using the latest code signature format*. When you re-sign a recovered binary for analysis, you must produce the DER blob or it's DOA on a modern device.

2. **The CDHash is the identity AMFI checks.** The CodeDirectory's hash (the **CDHash**, also called the cdhash) is what lands in the **trust cache** and what `amfid` validates against the CMS signature. Change one byte of the binary and the CDHash changes and the signature breaks — this is why you cannot patch an installed binary in place.

### AMFI enforcement at first launch

Walk the kill chain from `exec()` to running code on-device:

```
 execve(MyApp)                                        (no device shell — narrated)
   → kernel maps Mach-O, finds LC_CODE_SIGNATURE
   → AppleMobileFileIntegrity (AMFI) kext intercepts
       1. Is CDHash in a trust cache?  (platform/static/dynamic)  ──yes──► run
       2. else: amfid (userspace) validates the CMS signature:
            • leaf cert chains to an Apple root?
            • CDHash matches the signed CodeDirectory?
       3. amfid ALSO validates embedded.mobileprovision (installd enforces
          the same at install time):
            • Apple-signed and not expired?
            • signing leaf is one of the profile's DeveloperCertificates?
            • this device's UDID in ProvisionedDevices (or ProvisionsAllDevices)?
            • binary's DER entitlements ⊆ profile allowlist?  (the SUBSET RULE)
       4. all pass → entitlements granted → process runs
          any fail → install refused (installd) / immediate kill at launch
```

On iOS the profile checks live in **amfid/AMFI** with **installd** (MobileInstallation) refusing the install on failure — there is no separate profile daemon (macOS factors this into its own `provisioningprofiled`; iOS does not). The profile must be *present* on-device too: dev installs drop it at `/var/MobileDevice/ProvisioningProfiles/<UUID>.mobileprovision` (alongside the copy embedded in the `.app`). App Store apps skip the profile dance entirely because Apple's re-signing put them under a platform/Store trust path with no profile on disk.

> 🔬 **Forensics note:** In a full-file-system acquisition ([[07-decrypting-backups-and-images]]), `/var/MobileDevice/ProvisioningProfiles/` is a manifest of **every non-App-Store app ever provisioned on the device** — enterprise apps, developer builds, sideloaded tools, MDM-pushed apps — even after the app itself is deleted, the profile often lingers. Each profile decodes to its triad: who signed, what entitlements, which devices. It's one of the highest-signal directories for "what unusual software touched this phone."

## Hands-on

There is no on-device shell — everything runs on the **Mac**. Build a Simulator/device app or grab any `.ipa`, then dissect its signature and profile.

### Decode the provisioning profile (the CMS plist)

```bash
# Unzip an .ipa and find the profile (App Store apps have NONE — Apple strips it;
# use a development / Ad-Hoc / enterprise .ipa to get a real embedded.mobileprovision)
unzip -o MyApp.ipa -d /tmp/myapp >/dev/null
PROFILE=/tmp/myapp/Payload/*.app/embedded.mobileprovision

# Strip the CMS wrapper → human-readable plist
security cms -D -i $PROFILE -o /tmp/profile.plist
plutil -p /tmp/profile.plist
```
Described output — the triad in the clear:
```
{
  "AppIDName" => "Acme Notes"
  "TeamIdentifier" => [ "9XYZ1234AB" ]
  "TeamName" => "Acme Inc."
  "ExpirationDate" => 2026-12-01 09:14:33 +0000
  "Entitlements" => {
     "application-identifier" => "9XYZ1234AB.com.acme.notes"
     "get-task-allow" => 1
     "aps-environment" => "development"
     "keychain-access-groups" => [ "9XYZ1234AB.com.acme.notes" ]
  }
  "DeveloperCertificates" => [ <base64 DER…> ]
  "ProvisionedDevices" => [ "00008110-001A2B3C…", … ]   # absent ⇒ App Store
}
```

### Identify the signing developer from the embedded cert

```bash
# Pull the first DeveloperCertificate out of the plist and read its subject
plutil -extract DeveloperCertificates.0 raw -o - /tmp/profile.plist \
  | base64 -D | openssl x509 -inform DER -noout -subject -dates -issuer
```
```
subject=UID=9XYZ1234AB, CN=Apple Development: Jane Doe (ABC123DEF4), OU=9XYZ1234AB, O=Acme Inc., C=US
issuer=CN=Apple Worldwide Developer Relations Certification Authority, …
notBefore=Jun  1 09:14:33 2025 GMT   notAfter=Jun  1 09:14:33 2026 GMT
```
The `CN` names the human; the leaf chains to Apple's WWDR CA.

### Inspect the binary's code signature

```bash
BIN=/tmp/myapp/Payload/*.app/MyApp
codesign -dvvv "$BIN"
```
```
Identifier=com.acme.notes
TeamIdentifier=9XYZ1234AB
CodeDirectory v=20500 size=… flags=0x0(none) hashes=…+7 location=embedded
Hash type=sha256 size=32
CandidateCDHash sha256=… 
Authority=Apple Development: Jane Doe (ABC123DEF4)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
Signed Time=...
```

### Dump entitlements, and prove the DER blob (slot −7) exists

```bash
# Human-readable entitlements (decoded to an XML plist)
codesign -d --entitlements - --xml "$BIN" | plutil -p -

# There is NO codesign flag that prints the raw DER blob — `--entitlements :-`
# dumps the DECODED XML text, not the on-disk blob. To see the slot-−7 magic,
# carve the LC_CODE_SIGNATURE region out of the Mach-O and grep its hex:
read OFF SIZE < <(otool -l "$BIN" \
  | awk '/LC_CODE_SIGNATURE/{c=1} c&&/dataoff/{o=$2} c&&/datasize/{print o,$2; exit}')
dd if="$BIN" bs=1 skip="$OFF" count="$SIZE" 2>/dev/null \
  | xxd -p | tr -d '\n' | grep -oE 'fade71(71|72)' | sort -u
# fade7171 ⇒ XML entitlements (slot −5);  fade7172 ⇒ DER entitlements (slot −7)
```
If `fade7172` is absent the binary carries only legacy XML entitlements and **won't launch on iOS 15+** (Apple's *Using the latest code signature format*). To inspect the DER tree, carve just that blob — skip its 8-byte magic+length header — into `openssl asn1parse -inform DER`.

### Verify a signing identity exists locally

```bash
security find-identity -v -p codesigning
#  1) ABCD…  "Apple Development: Jane Doe (ABC123DEF4)"
#  2) EF01…  "Apple Distribution: Acme Inc. (9XYZ1234AB)"
#     2 valid identities found
```
If a cert shows but signing fails with "no identity found," the **private key** isn't in this Keychain — re-import the `.p12`.

### Inspect Mach-O load commands with vtool

```bash
vtool -show "$BIN" | grep -A3 -E 'LC_CODE_SIGNATURE|LC_BUILD_VERSION'
# LC_BUILD_VERSION  platform IOS  minos 18.0  sdk 26.0 …
# LC_CODE_SIGNATURE  dataoff … datasize …
```
`minos`/`sdk` tells you the deployment target and which SDK built it — useful for dating a sample and for the iOS-26-SDK-mandatory submission rule.

## 🧪 Labs

> All labs are **device-free**. Substrates are named per lab. Fidelity caveat: the **Simulator does not run AMFI** — it executes unsigned x86_64/arm64 macOS-host binaries, so it teaches *signature structure and tooling* but **cannot demonstrate launch-time enforcement, the subset rule rejecting a binary, or profile/device-UDID matching** (no SEP, no Data Protection, no `amfid`/`installd` profile gate). Enforcement behavior is reasoned about from real signed `.ipa`s and the format, not executed.

### Lab 1 — Decode a development/Ad-Hoc profile vs. an App Store app (substrate: two `.ipa`s, read-only)

1. Grab a **development or Ad Hoc** `.ipa` (it has an `embedded.mobileprovision`) and, for contrast, an app extracted from a device's **App Store** install.
2. Run the `security cms -D` + `plutil -p` recipe on the dev/Ad-Hoc `embedded.mobileprovision`.
3. Confirm the prediction: the **dev/Ad-Hoc** profile has `ProvisionedDevices` and `get-task-allow = 1`. Now check the App Store app — it has **no `embedded.mobileprovision` at all** (Apple stripped it at ingestion), the on-disk proof that Store apps run under Apple's re-signing, not your profile. (A **TestFlight** build behaves like the Store app here — Apple-re-signed, profile stripped, `get-task-allow` off — *not* like a dev build.)
4. From the dev profile, extract and `openssl x509` the developer certificate. Record the CN, Team ID, and validity window — this is the attribution workflow on a seized app.

### Lab 2 — Prove the subset rule on paper (substrate: real `.ipa`, read-only walkthrough)

1. `codesign -d --entitlements - --xml` the binary → the **claim**.
2. `plutil -p` the profile's `Entitlements` dict → the **allowlist**.
3. Diff them by hand. Verify every claimed key appears in the allowlist (subset holds). Now imagine adding `aps-environment` to the binary that the profile lacks — write down the exact error AMFI would raise ("...doesn't include the aps-environment entitlement"). This is the reasoning you'll apply to every real signing failure.

### Lab 3 — Confirm DER entitlements (slot −7) presence (substrate: real `.ipa`, read-only)

1. Carve the signature blob and look for the magic — the `codesign … --entitlements` flag won't show it (it prints decoded text, not the on-disk blob); use the Hands-on recipe: `dd` out the `LC_CODE_SIGNATURE` region, then `xxd -p | tr -d '\n' | grep -oE 'fade71(71|72)'`. A modern binary shows **both** `fade7171` (XML, slot −5) and `fade7172` (DER, slot −7).
2. Compare against an old (pre-2021) sample `.ipa` if you have one: the legacy binary may show only `fade7171`.
3. Explain, in one sentence, why the legacy (DER-less) binary won't launch on iOS 18/26 and what `codesign --generate-entitlement-der --force` would do to fix it.

### Lab 4 — Re-sign a binary for analysis (substrate: Mac + your own dev identity OR `ldid`, walkthrough)

> ⚠️ **ADVANCED:** Re-signing third-party apps is for **lawfully authorized** analysis of software you may examine. Re-signing to redistribute someone else's paid app is piracy. Re-signing only matters on a **device** (the Simulator runs unsigned), so the *launch* step here is a narrated device step.

1. Strip the old signature and re-sign with your identity + a fresh entitlements file:
   ```bash
   # ad-hoc / ldid route (jailbroken-device or analysis workflow)
   ldid -S/tmp/ent.xml MyApp.app/MyApp           # ldid by saurik; embeds entitlements

   # or full codesign route with a real identity (needed for non-jailbroken device)
   codesign --force --sign "Apple Development: Jane Doe (ABC123DEF4)" \
            --entitlements /tmp/ent.xml --generate-entitlement-der \
            --deep MyApp.app
   ```
2. Re-verify: `codesign -dvvv MyApp.app` should show your `Authority=` chain and a fresh CandidateCDHash; the entitlements dump should show your new keys in slot −7.
3. (Narrated device step) Re-zip to `.ipa`, install via your dev profile, and the app now runs **with `get-task-allow = 1`** — i.e. attachable by `lldb`/`frida`. This is the standard prep for [[05-dynamic-analysis-with-frida]]: a Store binary ships `get-task-allow` *off*; re-signing flips it on so a debugger can attach. Tools that automate the whole flow: `fastlane sigh resign`, `frida-ios-dump`/`bagbak` (which also defeat FairPlay), and `objection patchipa`.

### Lab 5 — Map a recovered profile to its authorization (substrate: sample image / loose `.mobileprovision`, read-only)

1. From a sample full-file-system image, list `/var/MobileDevice/ProvisioningProfiles/*.mobileprovision`.
2. Decode each with `security cms -D`. Build a table: `Name | TeamName | TeamID | get-task-allow | #devices | ProvisionsAllDevices | ExpirationDate`.
3. Flag the interesting rows: any `ProvisionsAllDevices = true` (enterprise distribution — possibly abused cert), any expired-but-present profile (deleted dev app residue), any whose `ProvisionedDevices` includes a UDID you can tie to other evidence. Write a two-line investigative note for the most suspicious profile.

## Pitfalls & gotchas

- **"Notarize and ship" is a macOS reflex that does not exist on iOS.** There is no execution-notarization. The profile + device list is the authorization model; do not look for a notary ticket.
- **A `.cer` without the private key is worthless.** Exporting/importing certs without the matching Keychain private key is the #1 cause of "no valid signing identity." Move the `.p12` (cert+key), or use `fastlane match`.
- **`get-task-allow` is the debuggability switch and it's *off* in distribution.** Store/TestFlight/Ad-Hoc/Enterprise distribution profiles set it false. You cannot attach `lldb`/Frida to a distribution-signed app on a stock device without re-signing — see Lab 4.
- **DER entitlements (slot −7) are mandatory since iOS 15.** A re-sign that produces only XML entitlements (slot −5) yields a binary that installs nowhere modern. Always pass `--generate-entitlement-der` (default in current `codesign`, but verify).
- **Wildcard App IDs silently can't carry App-ID-scoped capabilities.** If push/iCloud/App-Groups "won't turn on," check whether you're on a `*` profile — the capability requires an explicit App ID.
- **Free-team 7-day expiry kills sideloaded apps on a weekly clock.** "It worked last week" with a sudden refuse-to-launch is profile expiry, not a code bug.
- **A shipped App Store app has *no* `embedded.mobileprovision`.** Apple strips it during ingestion, so don't expect one and never try to attribute a Store app to a developer via a profile — attribute via the App Store receipt / `iTunesMetadata.plist` (seller, Apple ID) instead. A profile *is* present on dev / Ad-Hoc / enterprise builds.
- **`codesign --deep` is shallow on nested helpers in subtle ways.** For app extensions, frameworks, and `PlugIns/`, sign inside-out (frameworks → extensions → app) or you'll get "bundle format unrecognized" / nested-entitlement mismatches.
- **The Simulator doesn't enforce signing — so a Simulator "it runs" proves nothing about device signing.** Validate signing logic against a real `.ipa`/device, never against a green Simulator run.

## Key takeaways

- iOS replaces macOS notarization-for-execution with a **provisioning profile** that authorizes **(this code) × (these entitlements) × (these devices)**, Apple-signed in a CMS-wrapped plist.
- The **signing triad** lives in `embedded.mobileprovision`: `DeveloperCertificates` (who), `Entitlements`/`application-identifier` (what + App ID), `ProvisionedDevices` (which hardware) — or `ProvisionsAllDevices` for enterprise, or no list for App Store.
- The **subset rule** is the enforced contract: the binary's signed entitlements must be ⊆ the profile's allowlist; AMFI rejects any extra claim at install/launch.
- **Free personal team = 7-day profiles, no distribution, crippled capabilities**; paid program = 12-month profiles, Apple Distribution cert, full catalog.
- The signing **identity** is cert + private key together; the cert is public and useless alone — `.p12`/`fastlane match` move identities, not bare `.cer`s.
- The signature is a **SuperBlob** (`0xfade0cc0`) of typed blobs; **DER entitlements in slot −7 (`0xfade7172`) are mandatory since iOS 15**, and the **CDHash** is the identity AMFI validates against the trust cache and CMS signature.
- For RE: **re-signing flips `get-task-allow` on** so debuggers attach; for forensics, a recovered profile is an **attribution goldmine** (developer CN, Team ID, authorized UDIDs, build window) and `/var/MobileDevice/ProvisioningProfiles/` catalogs every non-Store app the device ever ran.

## Terms introduced

| Term | Definition |
|---|---|
| `embedded.mobileprovision` | The provisioning profile copied into an `.app`; a CMS-signed XML plist binding cert + App ID + devices |
| Provisioning profile | Apple-signed authorization document; the iOS analogue of macOS notarization-for-execution |
| Signing triad | The three load-bearing profile keys: `DeveloperCertificates`, `Entitlements`/App ID, `ProvisionedDevices` |
| App ID | `TEAMID.bundle.id`; **explicit** (exact bundle, supports scoped capabilities) or **wildcard** (`*`, no scoped caps) |
| `DeveloperCertificates` | Array of DER X.509 certs allowed to sign under the profile; private keys never included |
| `ProvisionedDevices` | Array of UDIDs the profile installs on; absent for App Store, replaced by `ProvisionsAllDevices` for enterprise |
| `ProvisionsAllDevices` | Enterprise-only profile flag authorizing install on any device, no UDID list |
| Subset rule | The binary's signed entitlements must be a subset of the profile's entitlement allowlist; AMFI enforces |
| `get-task-allow` | Entitlement permitting debugger attach; true in development, false in distribution |
| Apple Development / Apple Distribution | Unified (2019+) signing cert types for dev/debug vs. App Store/TestFlight/Ad-Hoc/Enterprise |
| Personal Team | Free Apple-Account signing tier; 7-day profiles, no distribution, restricted capabilities |
| Signing identity | A certificate **plus** its matching private Keychain key; the unit `codesign` actually uses |
| CSR | Certificate Signing Request: your public key sent to Apple's CA to be signed into a `.cer` |
| `.p12` / `.pfx` | PKCS#12 bundle of cert + private key; the portable form of a signing identity |
| SuperBlob | The `LC_CODE_SIGNATURE` container (`0xfade0cc0`) holding CodeDirectory, entitlements, requirements, CMS blobs |
| CodeDirectory / CDHash | The signature blob (`0xfade0c02`) of per-page hashes; its hash (CDHash) is AMFI's identity check |
| DER entitlements (slot −7) | DER-encoded entitlements blob (`0xfade7172`), mandatory since iOS 15; legacy XML lives in slot −5 (`0xfade7171`) |
| CMS / PKCS#7 | Cryptographic Message Syntax (RFC 5652) signed container used for both the profile and the signature blob wrapper |
| `amfid` / AMFI | AppleMobileFileIntegrity — the userspace daemon + kext that validate signatures and entitlements at launch |
| TN3125 | Apple's "Inside Code Signing: Provisioning Profiles" technote; canonical reference for this lesson |

## Further reading

- Apple, **TN3125: Inside Code Signing: Provisioning Profiles** — developer.apple.com/documentation/technotes/tn3125 (and the companion TN3126/TN3127 in the "Inside Code Signing" series)
- Apple, **"Using the latest code signature format"** — the iOS-15 DER-entitlements requirement
- Apple Platform Security Guide (security.apple.com) — AMFI, trust caches, the launch-time validation path
- Apple Developer, **Compare Memberships** (developer.apple.com/support/compare-memberships) — free vs. paid limits; **Provisioning profile updates** help page (12-month / 7-day lifetimes)
- objc.io issue 17, **"Inside Code Signing"** — still the clearest walk through CMS-wrapped profiles and the entitlement allowlist
- `man codesign`, `man security`, `man vtool`, `man ldid` — exact flag semantics on your toolchain version (Xcode 26.4 / Swift 6.3 era)
- Jonathan Levin, *MacOS and iOS Internals* vol. III + newosxbook.com / `jtool2` — SuperBlob/CodeDirectory format, AMFI internals
- `qyang-nj/llios` (`LC_CODE_SIGNATURE.md`) and `blacktop/go-macho` — open-source parsers documenting every blob magic and slot
- OWASP MASTG — "iOS Tampering and Reverse Engineering" / re-signing recipes (`fastlane sigh resign`, `objection patchipa`); `frida-ios-dump`, `bagbak`
- saurik's **`ldid`** and **`fastlane match`** repos — the two canonical ways to (re)sign and to share identities

---
*Related lessons: [[04-code-signing-amfi-entitlements]] | [[04-the-app-bundle-and-ipa-structure]] | [[01-the-code-signature-blob-and-entitlements-on-ios]] | [[09-distribution-testflight-appstore-enterprise]] | [[10-eu-dma-sideloading-and-alternative-marketplaces]] | [[05-dynamic-analysis-with-frida]] | [[03-fairplay-encryption-and-decrypting-app-store-apps]]*
