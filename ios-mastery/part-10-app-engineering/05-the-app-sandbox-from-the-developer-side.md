---
title: "The app sandbox from the developer side"
part: "10 — iOS App Engineering"
lesson: 05
est_time: "45 min read + 20 min labs"
prerequisites: [the-sandbox-and-tcc, code-signing-amfi-entitlements]
tags: [ios, dev, sandbox, entitlements, app-groups, capabilities]
last_reviewed: 2026-06-26
---

# The app sandbox from the developer side

> **In one sentence:** to a developer the iOS sandbox is not a setting you opt into but a wall you are *born inside* — every privilege you want (a shared container, a keychain group, push, HealthKit, a VPN tunnel) is an **entitlement** that an Apple-signed provisioning profile must authorize before AMFI will let your process claim it, and that same entitlement set is the single most compact statement of *what an app could do* that a reverse engineer or forensic examiner will ever read off the binary.

## Why this matters

You met the sandbox from the defender's side in [[the-sandbox-and-tcc]]: the `container` profile, the MACF hooks, AMFI gating launch. This lesson is the **builder's** view of the same machine — and the two views must agree, because the entitlements you toggle in Xcode are exactly the strings an examiner dumps off your `.ipa` later.

Three reasons this is load-bearing for *you* specifically:

1. **As a builder**, almost every "it works in the Simulator but the device build crashes on launch / can't see the shared file / `SecItemAdd` returns `errSecMissingEntitlement`" bug is an entitlement-vs-profile mismatch. Understanding the capability → entitlement → App ID → profile → codesign → AMFI chain turns those from voodoo into a five-minute diagnosis.
2. **As a reverse engineer**, `codesign -d --entitlements -` is the first command you run on any new binary. The entitlement dictionary is a manifest of intent: a `com.apple.developer.networking.networkextension` array means this app can see other apps' traffic; an `application-groups` list tells you *exactly which other bundles it shares a filesystem with*.
3. **As a forensic examiner**, the App Group container is where an app and its extensions stash the evidence that *isn't* in the app's own Data container — and the entitlement set tells you which containers to even go looking for.

This is the lesson where "the sandbox" stops being an abstraction and becomes a list of strings you can read, write, and follow on disk.

## Concepts

### The same wall, seen from inside

On macOS, you learned the App Sandbox as a thing you *choose*: a desktop app can ship with no sandbox at all, and even when sandboxed it can be signed **ad-hoc by you** with whatever entitlements you typed into the `.entitlements` file — the kernel trusts the signature because *you* are root on your own Mac. The sandbox is a container you voluntarily step into.

iOS inverts both halves of that:

- **Mandatory, not opt-in.** Every third-party app launches inside the `container` sandbox profile, applied by `containermanagerd` at install time and enforced by the Sandbox MACF policy module in XNU. There is no "unsandboxed app" on stock iOS. You cannot turn it off; you can only request *named holes* in it via entitlements.
- **Apple-authorized, not self-signed.** On a device, the entitlements baked into your code signature are only honored if they also appear in an **Apple-signed provisioning profile** embedded in the bundle (`embedded.mobileprovision`). AMFI cross-checks the two at launch. You cannot grant yourself `com.apple.developer.healthkit` by typing it into a plist — Apple's portal has to have associated that capability with your App ID and minted a profile that says so.

> 🖥️ **macOS contrast:** On macOS the sandbox is `com.apple.security.app-sandbox` = `true`, opt-in, and a developer can ad-hoc-sign arbitrary entitlements onto a binary because the OS trusts a locally-signed binary run by its owner. On iOS the sandbox is implicit and always-on, and the entitlement set is only as large as an **Apple-issued profile** permits — the trust root is Cupertino, not the user. The mental flip: on macOS you *add* a sandbox; on iOS you *negotiate exceptions* to one you can't leave.

### Entitlements vs capabilities vs provisioning — the three-layer authorization

These three words get used interchangeably and they are not the same thing. Keep them straight:

| Layer | What it is | Where it lives | Who controls it |
|---|---|---|---|
| **Capability** | A human-facing *feature toggle* in Xcode's **Signing & Capabilities** tab (e.g. "Push Notifications", "HealthKit", "App Groups") | Xcode UI / `.pbxproj` `SystemCapabilities` | You, in Xcode |
| **Entitlement** | A *key/value* in the code signature that the kernel and frameworks check at runtime (e.g. `aps-environment` = `development`) | `<App>.entitlements` → embedded in the signature | Xcode writes it; AMFI enforces it |
| **Provisioning profile** | An Apple-signed plist binding an App ID + its authorized entitlements + (for dev) a device allow-list + signing certs | `embedded.mobileprovision` in the bundle root | Apple's portal mints it |

The chain, in order, when you tick **+ Capability → App Groups** in Xcode:

```
  (1) Xcode UI: you add the "App Groups" capability and a group id
        │
        ▼
  (2) Xcode writes the entitlement into <Target>.entitlements:
        com.apple.security.application-groups = [ group.com.acme.shared ]
        │
        ▼
  (3) Xcode (automatic signing) registers/edits the App ID on the
      developer portal, enabling the "App Groups" SERVICE for it
        │
        ▼
  (4) Apple's portal mints a provisioning profile whose embedded
      <Entitlements> dict now INCLUDES that application-groups value
        │
        ▼
  (5) codesign seals BOTH the .entitlements (as an XML blob in
      __TEXT,__entitlements AND a DER copy) into the Mach-O signature,
      and Xcode copies embedded.mobileprovision into the .app
        │
        ▼
  (6) At launch on-device, amfid/AMFI reads the signed entitlements,
      compares them to the profile's authorized set, and either
      grants the capability or KILLS the process (or strips the claim)
```

The single most important sentence in this lesson lives in steps 2 and 4: **the capability you toggle in Xcode adds an entitlement, and that entitlement is inert unless the profile also authorizes it.** A `.entitlements` file claiming `com.apple.developer.healthkit` on a profile that doesn't list it is not a privilege — it is a launch-time crash (`Invalid Code Signature` / AMFI denial) on device, even though the *exact same build* runs fine in the Simulator (which has no AMFI).

**Managed vs restricted entitlements.** Most capabilities are *managed* — Xcode's automatic signing can enable the service and regenerate the profile for you (App Groups, push, HealthKit, Associated Domains). A few are *restricted*: `com.apple.developer.networking.networkextension`, CarPlay, and the privileged interception entitlements require Apple to **approve a request** before the portal will even offer the service. And a third tier — the truly Apple-internal entitlements (`com.apple.private.*`, `platform-application`, `task_for_pid-allow`) — can never be obtained by a third-party developer at all; you will only ever see those on Apple's own binaries or on a jailbroken `ldid`-signed payload (see [[the-code-signature-blob-and-entitlements-on-ios]] and [[trollstore-and-the-coretrust-bug]]).

> 🔬 **Forensics note:** Because the *signed* entitlement set is cryptographically sealed into the Mach-O and **mirrored by the Apple-signed profile**, the entitlements on a legitimately-distributed app are non-repudiable evidence of what Apple authorized that App ID to do. A discrepancy — entitlements present in the signature but absent from `embedded.mobileprovision`, or `com.apple.private.*` keys on a "normal" App Store-looking app — is a tamper/sideload indicator. Cross-check with [[code-signing-and-provisioning-in-depth]].

### The container tree the sandbox profile enforces

When `installd` installs an app, `containermanagerd` creates **two** container directories with random UUIDs, and the `container` sandbox profile confines the process to them:

```
  BUNDLE container (read-only to the app, code-signed, immutable)
  /private/var/containers/Bundle/Application/<UUID-A>/
      MyApp.app/                     ← the signed bundle; Mach-O, Info.plist,
      iTunesMetadata.plist             embedded.mobileprovision, _CodeSignature/
      .com.apple.mobile_container_manager.metadata.plist

  DATA container (read/write — this is where the app's runtime data lives)
  /private/var/mobile/Containers/Data/Application/<UUID-B>/
      Documents/        ← user-visible files; backed up; iTunes/Files share
      Library/
          Application Support/   ← app's private persistent data; backed up
          Caches/                ← purgeable; NOT backed up
          Preferences/           ← <bundle-id>.plist (NSUserDefaults)
          SplashBoard/, Saved Application State/, ...
      tmp/              ← scratch; purgeable; NOT backed up
      SystemData/
      .com.apple.mobile_container_manager.metadata.plist
```

Two details that matter constantly:

1. **The directory name is a random UUID, not the bundle id.** The mapping from UUID → bundle id is in the `.com.apple.mobile_container_manager.metadata.plist` at the root of each container, under the key **`MCMMetadataIdentifier`** (the bundle id) with **`MCMMetadataUUID`**. This is the first plist any forensic walk of a full-file-system image reads to label the anonymous container directories — see [[app-sandbox-and-filesystem-layout]] and [[filesystem-layout-and-containers]].
2. **`Documents/` vs `Library/Caches/` vs `tmp/` differ in backup and purge behavior**, and that difference is a forensic signal: data the developer wanted to survive a restore lands in `Documents/` or `Library/Application Support/` (and thus shows up in a [[the-itunes-finder-backup-format]] acquisition); data in `Caches/`/`tmp/` is excluded from backups and may be reaped under storage pressure, so its *presence* dates a recent session.

The sandbox profile additionally controls what *outside* these containers the app can touch — `tmp`-style shared areas, the Photos/Contacts data behind a TCC prompt, the `mediaserverd`-mediated camera, etc. Those cross-container holes are TCC's job ([[the-sandbox-and-tcc]]); the entitlements in *this* lesson are about widening the app's *own* container graph.

### App Groups — the shared container

An app is normally alone in its Data container. The **App Groups** capability punches a *shared* container that the app and its sibling targets (extensions, a paired second app from the same team) can all read and write.

- **Entitlement:** `com.apple.security.application-groups` — an array of group identifiers, each conventionally prefixed **`group.`** (e.g. `group.com.acme.notes`).
- **Container path on device:** `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` — again UUID-named, again mapped back to the group id via that directory's `.com.apple.mobile_container_manager.metadata.plist`.
- **API:** `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.acme.notes")` returns that URL. For shared defaults, `UserDefaults(suiteName: "group.com.acme.notes")` reads/writes a plist *inside* the group container instead of the app's private `Preferences/`.

Inside the shared container you can put anything: loose files, a shared SQLite database, a Core Data / SwiftData store, a shared `Library/`. This is the canonical way an app feeds data to its **extensions** — a Share extension dropping an inbound item, a Notification Service extension caching a decrypted payload, a WidgetKit widget reading the latest state, a keyboard extension's learned dictionary. (See [[extensions-app-clips-widgets-and-widgetkit]].)

Here is why that matters so much: **an app extension is a separate executable in a separate bundle with its own, independent sandbox and its own entitlements** — it is *not* part of the host app's process. The host app and each extension run as distinct processes confined to distinct Data containers; the **only** filesystem they share is the App Group container. So the topology a vendor's product actually presents on disk looks like this:

```
   ┌──────────────────────┐     ┌──────────────────────────┐
   │  Notes.app (process)  │     │  ShareExt (process)       │
   │  Data/Application/<U1> │     │  Data/Application/<U3>     │   ← each its own
   └──────────┬───────────┘     └────────────┬─────────────┘      sandbox + entitlements
              │                                │
              │   ┌──────────────────────────┐│
              │   │  Widget (process)          ││
              │   │  Data/Application/<U2>      ││
              │   └─────────────┬──────────────┘│
              │                 │                │
              ▼                 ▼                ▼
   ┌───────────────────────────────────────────────────────┐
   │  Shared/AppGroup/<UUID>   (group.com.acme.shared)        │  ← the ONLY shared FS
   │    shared.sqlite · cached attachments · group defaults   │
   └───────────────────────────────────────────────────────┘
   ┌───────────────────────────────────────────────────────┐
   │  keychain group  A1B2C3D4E5.com.acme.sso                 │  ← the ONLY shared secrets
   └───────────────────────────────────────────────────────┘
```

The implication for an examiner is exact: to reconstruct what the *product* did, you must acquire the app's container, **every extension's container**, the App Group container, and the shared keychain group — and the `application-groups` + `keychain-access-groups` entitlements (one `codesign -d` dump) are the map that tells you those last two even exist.

> 🖥️ **macOS contrast:** macOS has the same `com.apple.security.application-groups` entitlement, but the container lands at the *human-readable* path `~/Library/Group Containers/<group-id>/` — named by the group id itself. iOS names the directory by an opaque **UUID** and hides the group id inside a metadata plist. So the macOS reflex "ls the Group Containers folder and read the names" doesn't transfer: on an iOS image you must resolve every `Shared/AppGroup/<UUID>` through its `MCMMetadataIdentifier` first.

> 🔬 **Forensics note:** The App Group container is where the *richest* cross-process evidence hides, because the app's extensions write there. Practical examples examiners actually pull: a messaging app's Notification Service Extension caching decrypted message bodies into the group container before the main app ever runs; a keyboard extension's typing/learning store; a "save to app" Share extension's inbound queue; a widget's last-rendered snapshot. If you only carve the app's own `Data/Application/<UUID>` and skip `Shared/AppGroup/<UUID>`, you miss it. Map app↔group by intersecting the app's signed `application-groups` entitlement (from `codesign -d`) with the group containers on disk.

### Keychain access groups — shared *secrets*

The filesystem analogue above has a credentials twin. By default a keychain item an app stores is readable only by that app; **keychain access groups** let a family of apps share keychain items (tokens, passwords, keys).

The effective access-group list for a process is the **union of three entitlements** (Apple documents exactly this):

1. **`keychain-access-groups`** — explicit groups, each prefixed by the team's App ID prefix: `$(AppIdentifierPrefix)com.acme.shared` (the prefix is normally your **Team ID**).
2. **`application-identifier`** — the app's own App ID (`<TeamID>.<bundle-id>`). This is the **implicit, default** access group: every app can always read/write its own keychain items under this group without any extra capability.
3. **`com.apple.security.application-groups`** — the App Group ids *also* act as keychain access groups, so an app + extension that share a filesystem group can share keychain items too.

There is also the special **`com.apple.token`** group (used for SmartCard / cryptographic-token items), present implicitly.

Programmatically you pick a group by passing `kSecAttrAccessGroup` in your `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` query. Omit it and the system uses the first entitled group (historically the app's own). See [[keychain-on-ios]] for the storage format and the protection-class interaction.

> 🔬 **Forensics note:** The `keychain-access-groups` entitlement is a map of *trust between apps from the same vendor*. If app A and app B share `$(prefix)com.vendor.sso`, a token A wrote is readable by B — so an account compromise or token in one app implicates the family. When you decrypt a keychain from a full-file-system or backup acquisition ([[keychain-on-ios]], [[decrypting-backups-and-images]]), the access group on each item tells you which bundle(s) could see it, and the entitlement dumps tell you the intended sharing topology.

### Data protection from the developer side

[[data-protection-and-keybags]] covered the *crypto* — per-file keys wrapped by class keys, class keys tied to the passcode/SEP, the BFU/AFU distinction. From the **developer** side, that whole hierarchy reduces to one decision per file: which **NSFileProtection class** to stamp on it.

| Class (`FileProtectionType`) | Accessible when… | Typical use |
|---|---|---|
| `.complete` (`NSFileProtectionComplete`) | Only while the device is **unlocked** | Most sensitive user data; key becomes unavailable on lock |
| `.completeUnlessOpen` (`…UnlessOpen`) | Created/opened while unlocked; a file already open stays readable **after lock** | Background writes that must finish after lock (downloads) |
| `.completeUntilFirstUserAuthentication` (`…UntilFirstUserAuthentication`) | After the **first unlock since boot** (AFU), then stays available even when re-locked | **The default** for files |
| `.none` (`NSFileProtectionNone`) | **Always**, even Before First Unlock (BFU) | Data that must be readable at boot before unlock — avoid for anything sensitive |

These four NSFileProtection levels are exactly the developer-facing names for the Apple Platform Security **Data Protection classes** you met in [[data-protection-and-keybags]]:

| NSFileProtection level | Data Protection class | Class key available… |
|---|---|---|
| `.complete` | **Class A** (`NSFileProtectionComplete`) | only while unlocked |
| `.completeUnlessOpen` | **Class B** (`NSFileProtectionCompleteUnlessOpen`) | unlocked to create; asymmetric key keeps open files readable after lock |
| `.completeUntilFirstUserAuthentication` | **Class C** (`NSFileProtectionCompleteUntilFirstUserAuthentication`) | after first unlock since boot (AFU) |
| `.none` | **Class D** (`NSFileProtectionNone`) | always (key wrapped only by the hardware UID key, not the passcode) |

So when an examiner says "Class C is reachable in an AFU acquisition," that is the *same statement* as a developer leaving a file at the default `.completeUntilFirstUserAuthentication`. The dev knob and the forensic class are two names for one mechanism.

You set it three ways:

- **Per file at creation:** `FileManager` `attributes: [.protectionKey: FileProtectionType.complete]`, or write with `Data.WritingOptions` `.completeFileProtection` / `.completeFileProtectionUnlessOpen` / `.completeFileProtectionUntilFirstUserAuthentication` / `.noFileProtection`.
- **After the fact:** set the URL resource value `.fileProtectionKey`, or `setAttributes(_:ofItemAtPath:)`.
- **Whole-app default via entitlement:** the **Data Protection** capability writes `com.apple.developer.default-data-protection` = `NSFileProtectionComplete`, raising the default class for files the app creates (without per-file calls).

On a real device each protected file carries a per-file content-protection class in its metadata and a wrapped per-file key in the keybag; the exact on-disk encoding is the subject of [[data-protection-and-keybags]] — do not assume a specific xattr name here.

> 🖥️ **macOS contrast:** There is no NSFileProtection on macOS — FileVault encrypts the whole Data volume with one key tied to a logged-in session, not per-file classes tied to lock state. iOS's per-file, lock-state-aware classes are why "the phone was locked" (BFU/AFU) is a *cryptographic* fact about which files are even readable, not just a UI state — the cornerstone of [[bfu-vs-afu-and-data-protection-classes]].

> 🔬 **Forensics note:** The developer's class choice is the examiner's reachability map. On a **BFU** image, only `NSFileProtectionNone` files are decryptable; everything `.complete` is ciphertext until the passcode is supplied. So the protection class a developer stamped on a database literally determines whether you can read it from a given lock state. Apps that (sloppily) leave a sensitive SQLite at `.none` or rely on the `…UntilFirstUserAuthentication` default are the ones you recover from an AFU acquisition.

### Mapping a capability to its entitlement + App ID config

The general pattern — toggle capability → entitlement(s) appear → App ID service enabled → profile authorizes — is identical for every capability; only the strings change. Four worked examples you will meet constantly, both as a builder and at the disassembler:

**Push Notifications.**
- Capability: *Push Notifications* → entitlement **`aps-environment`** = `development` (debug builds) or `production` (Release/App Store).
- App ID config: the *Push Notifications* service must be enabled; you also generate an APNs key/cert. At runtime the app calls `registerForRemoteNotifications`, gets a device token from `apsd`, and ships it to its server.
- RE tells: `aps-environment` present ⇒ the app receives remote pushes; pair with a Notification Service / Content extension to know it mutates payloads. (Push backend mechanics: [[apple-account-icloud-and-apns]].)

**HealthKit.**
- Capability: *HealthKit* → entitlement **`com.apple.developer.healthkit`** (= `true`), often with **`com.apple.developer.healthkit.access`** (an array, e.g. `health-records`).
- App ID config: HealthKit service enabled; **plus** the `Info.plist` usage-description strings `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` (no string ⇒ guaranteed crash on first access — a TCC, not entitlement, requirement; see [[the-sandbox-and-tcc]]).
- Forensic tell: this entitlement means the app could read the Health store ([[health-and-fitness]]). Whether it *did* is in its own container / the Health DB, but the *capability* is right here in the signature.

**Network Extension (the restricted one).**
- Capability: *Network Extensions* → entitlement **`com.apple.developer.networking.networkextension`**, an **array of provider-type strings**: `packet-tunnel-provider`, `app-proxy-provider`, `content-filter-provider`, `dns-proxy` (macOS system-extension distribution adds `-systemextension` suffixed variants).
- App ID config: **requires Apple approval** of a Network Extension request before the portal offers the service — this is not auto-managed.
- RE/forensic tell: this is the loudest entitlement on the phone. A `content-filter-provider` or `packet-tunnel-provider` can **see or redirect other apps' traffic** — a legitimate VPN/parental-control/enterprise-DLP app, or, on a malicious build, a traffic-interception capability. Always flag it. (Mechanism: [[networkextension-and-vpn]]; interception/MITM: [[traffic-interception-and-tls]].)

**Associated Domains.**
- Capability: *Associated Domains* → entitlement **`com.apple.developer.associated-domains`**, an array of `service:host` strings: `applinks:acme.com` (Universal Links), `webcredentials:acme.com` (shared-web-credential / Password AutoFill), `appclips:acme.com`.
- App ID config: service enabled; the *server* must host `/.well-known/apple-app-site-association` (AASA) that names this App ID — a two-way handshake.
- Forensic tell: `applinks:` entries enumerate the web domains that deep-link into the app; `webcredentials:` entries reveal which sites the app participates in AutoFill for (i.e. whose credentials may sit in the shared-web-credentials keychain).

The point of stacking four examples: once you internalize the chain, you can read *any* unfamiliar entitlement as "capability X, authorized by Apple, that lets this app reach Y." The entitlement dictionary is a **capability inventory** — which is exactly why dumping it is step one of triage.

Here is a triage card of high-signal entitlements — the ones that change how you scope an investigation the moment you see them:

| Entitlement | What it proves the app *could* do | Examiner action |
|---|---|---|
| `com.apple.security.application-groups` | Shares a filesystem container with named siblings/extensions | Acquire every `Shared/AppGroup/<UUID>` in the list |
| `keychain-access-groups` | Shares keychain items with the listed vendor groups | Decrypt keychain; map items by access group across the family |
| `com.apple.developer.networking.networkextension` | Can see / tunnel / filter **other apps' traffic** | Flag for interception capability; check for a VPN/filter config profile |
| `aps-environment` | Receives remote pushes (+ NSE may mutate payloads) | Look for a Notification Service Extension cache in the App Group |
| `com.apple.developer.associated-domains` | Deep-links from / shares credentials with named web domains | Enumerate `applinks:`/`webcredentials:` hosts; check AutoFill keychain |
| `com.apple.developer.healthkit` | Could read the Health store | Pull the Health DB; correlate ([[health-and-fitness]]) |
| `com.apple.developer.location.push` / background location | Location wake-ups | Correlate with location stores ([[location-history]]) |
| `com.apple.private.*` / `platform-application` / `task_for_pid-allow` | **Cannot belong to a legit third-party App Store app** | Strong tamper/sideload/jailbreak indicator — escalate |

> 🔬 **Forensics note (synthesis):** Run `codesign -d --entitlements -` on a suspect app and you have, in one screen, a near-complete answer to *"what could this app do?"* — its data-sharing graph (`application-groups`, `keychain-access-groups`), its sensitive-store reach (`healthkit`, contacts/photos via Info.plist usage strings), its network power (`networkextension`), its deep-link/credential surface (`associated-domains`), and its push capability (`aps-environment`). It does **not** tell you what the app *did* — that's the container/DB work in Part 08 — but it scopes the investigation and tells you which containers (`Data/Application/<UUID>` *and* every `Shared/AppGroup/<UUID>`) to acquire.

> ⚖️ **Authorization:** An App Group container is **shared by a family of apps/extensions**, so mining it may surface data created by a sibling app or by an extension that is *outside* the bundle named in your warrant or consent scope. Resolve the `MCMMetadataIdentifier` and the `application-groups` membership first, document which bundle(s) the group serves, and confirm your authority covers that data set before you carve it. A group container is also a place a vendor SDK (analytics, ad attribution) may have written third-party-controlled data — note provenance in your chain-of-custody log.

## Hands-on

There is no shell on the phone; everything below runs on the **Mac**, against a Simulator app, a `.app`/`.ipa` you have, or a decoded profile.

### Dump the signed entitlements of any bundle

```bash
# XML entitlements blob sealed into the code signature
codesign -d --entitlements - /path/to/MyApp.app
# (older syntax printed binary; ":-" forces the property-list to stdout)
codesign -d --entitlements :- /path/to/MyApp.app | plutil -p -

# Full signing detail: TeamID, Authority chain, flags, CDHash
codesign -dv --verbose=4 /path/to/MyApp.app
```

Expected (abridged) for an app with App Groups + push + a keychain group:

```xml
<dict>
  <key>application-identifier</key>            <string>A1B2C3D4E5.com.acme.notes</string>
  <key>com.apple.developer.team-identifier</key><string>A1B2C3D4E5</string>
  <key>aps-environment</key>                   <string>production</string>
  <key>com.apple.security.application-groups</key>
      <array><string>group.com.acme.shared</string></array>
  <key>keychain-access-groups</key>
      <array>
        <string>A1B2C3D4E5.com.acme.notes</string>
        <string>A1B2C3D4E5.com.acme.sso</string>
      </array>
</dict>
```

### Decode the embedded provisioning profile

```bash
# embedded.mobileprovision is a CMS (PKCS#7) wrapper around a plist
security cms -D -i /path/to/MyApp.app/embedded.mobileprovision -o /tmp/profile.plist
plutil -p /tmp/profile.plist | grep -E 'Name|TeamIdentifier|application-identifier|ExpirationDate|ProvisionedDevices' 

# The profile's OWN authorized entitlements (compare to the signature above!)
plutil -extract Entitlements xml1 -o - /tmp/profile.plist | plutil -p -
```

The investigative move: diff the **signed** entitlements (from `codesign -d`) against the **profile's** `Entitlements` dict. On a legitimately distributed app they agree (the signed set ⊆ profile set). A mismatch is a tamper/sideload signal.

### Pull entitlements out of an `.ipa` (no device)

An `.ipa` is a zip with a `Payload/<App>.app/` inside — so the entire entitlement triage happens on the Mac before you ever touch a phone:

```bash
unzip -q Suspect.ipa -d /tmp/suspect && APP=/tmp/suspect/Payload/*.app

# Signed entitlements (XML) — the capability inventory
codesign -d --entitlements :- $APP 2>/dev/null | plutil -p -

# Same thing without Apple's tools (handy on Linux triage boxes too):
#   ldid -e $APP/<MachO>            # prints the entitlement plist
#   jtool2 --ent $APP/<MachO>       # Levin's jtool2 entitlement dump

# The profile Apple actually authorized (device builds carry this; App Store
# re-signed copies replace it). Diff its Entitlements vs the signature above.
security cms -D -i $APP/embedded.mobileprovision 2>/dev/null \
  | plutil -extract Entitlements xml1 -o - - | plutil -p -
```

Note that the signature carries **two** copies of the entitlements — the legacy XML blob and a **DER-encoded** copy that AMFI prefers on modern iOS. `codesign -d --entitlements -` shows you the decoded plist regardless; the DER detail matters when you hand-parse the `LC_CODE_SIGNATURE` blob in [[the-code-signature-blob-and-entitlements-on-ios]].

### Resolve a Simulator app's containers

```bash
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)

# Bundle container (the .app)         | Data container | App-Group container
xcrun simctl get_app_container "$DEV" com.acme.notes app
xcrun simctl get_app_container "$DEV" com.acme.notes data
xcrun simctl get_app_container "$DEV" com.acme.notes group.com.acme.shared
xcrun simctl get_app_container "$DEV" com.acme.notes groups   # list ALL groups
```

Each prints an absolute Mac path under `~/Library/Developer/CoreSimulator/Devices/<DEV>/data/Containers/…` that you can then `ls`, `sqlite3`, and `plutil` directly (see [[simulator-internals-and-on-disk-filesystem]]).

### Read a container's identity metadata

```bash
plutil -p \
 "$(xcrun simctl get_app_container "$DEV" com.acme.notes data)/.com.apple.mobile_container_manager.metadata.plist"
# => MCMMetadataIdentifier => "com.acme.notes"   (this is how a UUID dir is labeled)
```

## 🧪 Labs

> ⚠️ **All labs are device-free.** Where a lab uses the **Simulator**, remember its fidelity caveats: the Simulator runs macOS frameworks, so there is **no AMFI, no real sandbox enforcement, no SEP, and no Data-Protection-at-rest** — you can read *any* Simulator app's container from the Mac (the `container` profile is not enforced), `.complete` files are plaintext, and the device-only daemons don't run. The Simulator teaches you *structure, paths, and the entitlement plumbing*; lock-state cryptography and AMFI enforcement are taught from sample images and walkthroughs.

### Lab 1 — Walk the container tree (Simulator)

**Substrate:** Xcode Simulator. **Caveat:** no sandbox enforcement / no encryption (structure only).

1. In Xcode, create a trivial SwiftUI app, run it on a booted Simulator so it installs.
2. Resolve its bundle and data containers with `xcrun simctl get_app_container … app` and `… data`.
3. `ls -la` the data container. Confirm `Documents/`, `Library/{Caches,Preferences,Application Support}/`, `tmp/`. Note that nothing stops you (on the Mac) from reading another app's container — that's the missing enforcement.
4. `plutil -p` the `.com.apple.mobile_container_manager.metadata.plist`; confirm `MCMMetadataIdentifier` is your bundle id. **This is the UUID→bundle-id resolution you'll do on real images.**

### Lab 2 — Add App Groups and watch the shared container appear (Simulator)

**Substrate:** Simulator. **Caveat:** the group container exists and is writable, but with no real sandbox the "sharing" is unenforced — you're exercising the *plumbing*, not the *isolation*.

1. In **Signing & Capabilities**, add **App Groups** and a group id (`group.<your-team>.lab`). Observe Xcode write `com.apple.security.application-groups` into the `.entitlements` file.
2. In code, `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` and write a file there; also write a value via `UserDefaults(suiteName:)`.
3. Re-run, then `xcrun simctl get_app_container <DEV> <bundle> groups` to list the group, and resolve its path. Find your file and the suite plist.
4. Run `codesign -d --entitlements :- <SimApp> | plutil -p -` on the built `.app` and confirm the `application-groups` array is sealed into the (ad-hoc) signature. **This is the same dump you'll run on an `.ipa` later.**

### Lab 3 — Read entitlements off a real signed binary (read-only walkthrough)

**Substrate:** any real signed `.app`/`.ipa` you possess (a TestFlight/Ad-Hoc build, or — for the *form* — a macOS app). **Caveat:** Simulator builds are ad-hoc-signed and carry **no** `embedded.mobileprovision`; the profile half of this lab needs a *device* build.

1. `codesign -d --entitlements :- <App> | plutil -p -` — read off the capability inventory. Identify: data-sharing (`application-groups`, `keychain-access-groups`), network power (`networkextension`), push (`aps-environment`), deep-links (`associated-domains`).
2. If it's a device build: `security cms -D -i <App>/embedded.mobileprovision -o /tmp/p.plist`, then `plutil -extract Entitlements xml1 -o - /tmp/p.plist | plutil -p -`.
3. **Diff** the two entitlement sets. They should agree. Write one sentence per entitlement: *"this lets the app do X."* That sentence is your triage note.

### Lab 4 — App-Group evidence hunt on a public sample image (read-only)

**Substrate:** a public iOS reference image (Josh Hickman / Digital Corpora) extracted to disk, parsed with **iLEAPP**, or browsed directly. **Caveat:** device-only — this is the real `Shared/AppGroup` layout the Simulator can't reproduce.

1. Under `/private/var/mobile/Containers/Shared/AppGroup/`, list the UUID directories.
2. For each, `plutil -p .com.apple.mobile_container_manager.metadata.plist` to resolve `MCMMetadataIdentifier` → the owning group id / app family.
3. Pick a messaging or social app's group container and enumerate it: shared SQLite stores, cached attachments, a Notification Service Extension's cache. Note evidence that is **not** in the app's own `Data/Application/<UUID>` container.
4. Cross-reference: from the app's `embedded.mobileprovision` (or iLEAPP's entitlement output), confirm the `application-groups` value matches the group container you just mined — closing the loop from *entitlement* to *on-disk evidence*. See [[communications-imessage-and-sms]] and [[third-party-app-methodology]].

### Lab 5 — Data-protection class on your own file (read-only walkthrough + Simulator)

**Substrate:** code-reading + Simulator. **Caveat:** the Simulator does **not** encrypt, so the protection class is recorded but never enforced — the lock-state behavior is conceptual here; verify the cryptographic effect against [[bfu-vs-afu-and-data-protection-classes]].

1. In code, write the same `Data` four times with `.completeFileProtection`, `.completeFileProtectionUnlessOpen`, `.completeFileProtectionUntilFirstUserAuthentication`, and `.noFileProtection`.
2. Read back each file's `.fileProtectionKey` URL resource value and print it; confirm the class round-trips.
3. Reason through, for each: in a **BFU** acquisition, which is readable? (Only `.none`.) In an **AFU** acquisition? (`.none` + `…UntilFirstUserAuthentication`, plus already-open `…UnlessOpen`.) This is the developer choice → examiner reachability mapping.

### Lab 6 — Make the macOS-vs-iOS contrast concrete (Mac, read-only)

**Substrate:** your Mac's `/Applications`. **Caveat:** this is the *macOS* sandbox model on purpose — the point is to feel the difference, not to model iOS.

1. Pick a sandboxed Mac App Store app and a non-sandboxed one. `codesign -d --entitlements :- /Applications/<App>.app | plutil -p -` on each.
2. Find one with `com.apple.security.app-sandbox` = `true` and one **without the key at all** — proof macOS sandboxing is opt-in.
3. Now contrast with any iOS `.app`/`.ipa` from Lab 3: there is **no** `app-sandbox` key, because the iOS sandbox isn't a key you set — it's mandatory and implicit. Write the one-sentence contrast in your own words: *macOS = add a sandbox; iOS = negotiate exceptions to one you can't leave.*
4. Optional: `codesign -dv --verbose=4` the macOS app and note you can re-sign it yourself ad-hoc (`codesign -f -s - …`) and it still runs — the trust root is *you*. On iOS device that re-sign would fail AMFI without an Apple profile.

## Pitfalls & gotchas

- **"Works in the Simulator, crashes on device at launch."** The Simulator has **no AMFI**, so it ignores the entitlement-vs-profile cross-check. A `.entitlements` claim with no matching profile authorization is silently fine in the Simulator and a hard launch failure on device. Always test capabilities on real hardware (or at minimum re-read the profile's `Entitlements` dict).
- **Editing `.entitlements` by hand and expecting it to "just work."** Adding a key the profile doesn't authorize doesn't grant the privilege — on device it breaks launch; in the Simulator it does nothing. The capability must be enabled on the **App ID**, which regenerates the profile. (Manual entitlement edits are how RE/jailbreak workflows *re-sign*, but those rely on `ldid`/TrollStore/CoreTrust bypasses, not Apple's trust chain — [[the-code-signature-blob-and-entitlements-on-ios]].)
- **App Group / keychain group strings are exact and prefixed.** App Groups use the `group.` convention; keychain access groups are prefixed with `$(AppIdentifierPrefix)` (your Team ID). A mismatch returns `errSecMissingEntitlement` (-34018) from `SecItem*` or a `nil` from `containerURL(forSecurityApplicationGroupIdentifier:)` — and `nil` there is the #1 silent App-Group bug.
- **The container directory is a UUID, not the bundle id — and the UUID changes.** A reinstall (and sometimes an OS migration) mints a *new* container UUID. Never hardcode a container path; always resolve via the API (build side) or the `MCMMetadataIdentifier` plist (forensic side).
- **`Library/Caches/` and `tmp/` are not in backups and can be reaped.** Developers who stash important state there lose it on restore; examiners who only work a logical [[the-itunes-finder-backup-format]] backup *won't see it at all* — you need a full-file-system acquisition for `Caches`/`tmp`.
- **The default protection class is `…UntilFirstUserAuthentication`, not `.complete`.** Files you didn't explicitly protect are readable in **AFU**. Don't assume "it's iOS, so it's encrypted at rest while locked" — that's only true for `.complete`/`.completeUnlessOpen`.
- **Restricted entitlements can't be self-served.** `com.apple.developer.networking.networkextension` (and friends) need an **approved Apple request** before the portal will offer them; automatic signing alone won't conjure them. Plan for the lead time.
- **Don't confuse usage-description strings with entitlements.** HealthKit/Photos/Contacts/Camera need *both* an entitlement/capability (where applicable) **and** an `Info.plist` `NS…UsageDescription`. A missing usage string is a guaranteed runtime crash — and it's a TCC requirement, distinct from the AMFI-enforced entitlement.
- **Raising the default protection class is not retroactive.** Adding `com.apple.developer.default-data-protection` = `NSFileProtectionComplete` only governs files the app creates *afterward*; files already written at the old (weaker) class keep that class until rewritten. An examiner can find a sensitive store still sitting at `…UntilFirstUserAuthentication` long after the developer "turned on Complete Protection."

## Key takeaways

- On iOS the sandbox is **mandatory and Apple-authorized**, the inverse of macOS's **opt-in, self-signable** App Sandbox: you don't add a sandbox, you negotiate Apple-approved exceptions to one you can't leave.
- The authorization chain is **capability (Xcode UI) → entitlement (signed key/value) → App ID service → provisioning profile → codesign → AMFI**. The entitlement is inert unless the **Apple-signed profile** also authorizes it.
- Each app gets a UUID-named **bundle** container (read-only) and **data** container (`Documents`/`Library`/`tmp`); the UUID→bundle-id mapping lives in `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`).
- **App Groups** (`com.apple.security.application-groups`, `group.` prefix) create a shared container at `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` — the prime place an app *and its extensions* stash shared evidence.
- **Keychain access groups** = the union of `keychain-access-groups`, the implicit `application-identifier` group, and the App Groups — the trust topology for shared secrets across an app family.
- **NSFileProtection** classes are the developer's one-line interface to the data-protection keybag; the default is `…UntilFirstUserAuthentication` (AFU-readable), and the class chosen *is* the examiner's reachability map across BFU/AFU.
- For RE/forensics, `codesign -d --entitlements -` is the **capability inventory**: it answers *what an app could do* and scopes which containers (its own **and** every App Group) to acquire — without telling you what it *did*.

## Terms introduced

| Term | Definition |
|---|---|
| Capability | A feature toggle in Xcode's *Signing & Capabilities* tab that, when enabled, writes one or more entitlements and updates the App ID/profile. |
| Entitlement | A key/value sealed into the code signature (XML + DER copy) that the kernel/AMFI/frameworks check at runtime to grant a privilege. |
| Provisioning profile | Apple-signed plist (`embedded.mobileprovision`, CMS-wrapped) binding an App ID, its authorized entitlements, devices, and certs; cross-checked against the signature by AMFI. |
| Managed capability | A capability Xcode's automatic signing can enable on the App ID and regenerate the profile for (push, App Groups, HealthKit, Associated Domains). |
| Restricted entitlement | A capability (e.g. `networkextension`, CarPlay) requiring explicit Apple approval before the portal offers the service. |
| `com.apple.security.application-groups` | Entitlement listing App Group ids (conventionally `group.`-prefixed) that share a container and act as keychain access groups. |
| App Group container | Shared, UUID-named directory at `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` an app + its extensions read/write. |
| `MCMMetadataIdentifier` | Key in `.com.apple.mobile_container_manager.metadata.plist` mapping a container's random UUID directory back to its bundle/group id. |
| `keychain-access-groups` | Entitlement listing `$(AppIdentifierPrefix)`-prefixed keychain groups the app may share items with. |
| `application-identifier` | The app's App ID (`<TeamID>.<bundle-id>`); the implicit default keychain access group every app gets. |
| `kSecAttrAccessGroup` | `SecItem*` query attribute selecting which entitled keychain access group an item is stored in / read from. |
| `FileProtectionType` / NSFileProtection class | The per-file data-protection class (`.complete`, `.completeUnlessOpen`, `.completeUntilFirstUserAuthentication`, `.none`) set via `.protectionKey` / write options. |
| `com.apple.developer.default-data-protection` | Entitlement raising the whole app's default file-protection class (e.g. to `NSFileProtectionComplete`). |
| `aps-environment` | Push entitlement (`development`/`production`) authorizing remote notifications via APNs. |
| `com.apple.developer.healthkit` | Entitlement authorizing HealthKit access (paired with `NS*HealthUsageDescription` strings). |
| `com.apple.developer.networking.networkextension` | Restricted entitlement (array of provider types) authorizing VPN/proxy/content-filter/DNS-proxy extensions that can see other apps' traffic. |
| `com.apple.developer.associated-domains` | Entitlement (array of `service:host`) enabling Universal Links (`applinks:`), shared web credentials (`webcredentials:`), App Clips (`appclips:`). |
| `containermanagerd` | The iOS daemon that creates app/group containers and applies the `container` sandbox profile at install time. |

## Further reading

- Apple — *Entitlements* reference (developer.apple.com/documentation/bundleresources/entitlements): `com.apple.security.application-groups`, `keychain-access-groups`, `com.apple.developer.networking.networkextension`, `com.apple.developer.associated-domains`, `aps-environment`.
- Apple — *Adding capabilities to your app*; *Configuring app groups*; *Configuring network extensions*; *Sharing access to keychain items among a collection of apps*; *Encrypting your app's files* (developer.apple.com/documentation/xcode & .../security).
- Apple — *Provisioning with managed capabilities* and *Enable app capabilities* (Account help); **TN3125** *Inside Code Signing: Provisioning Profiles*; **TN2415** *Entitlements Troubleshooting*.
- Apple Platform Security Guide — Data Protection classes (Class A–D ↔ the four NSFileProtection levels) and the keybag hierarchy; Apple Platform Deployment Guide — managed app config.
- Jonathan Levin, *MacOS and iOS Internals* Vol. III — `containermanagerd`/`installd`, the container layout, AMFI/`amfid`, entitlement enforcement; newosxbook.com, `jtool2`.
- Alexis Brignoni — iLEAPP (container & App-Group parsing) and the `.com.apple.mobile_container_manager.metadata.plist` resolution workflow; Josh Hickman / Digital Corpora iOS reference images.
- OWASP MASTG — *Testing Data Storage* (NSFileProtection / Data-Protection testing) and *Testing Code Quality & Build Settings* (entitlement review).
- `man codesign`, `man security`, `man simctl` (`xcrun simctl get_app_container`); `plutil(1)`; `ldid` (entitlement (re)signing on jailbroken/sideloaded payloads).

---
*Related lessons: [[the-sandbox-and-tcc]] | [[code-signing-amfi-entitlements]] | [[data-protection-and-keybags]] | [[keychain-on-ios]] | [[filesystem-layout-and-containers]] | [[app-sandbox-and-filesystem-layout]] | [[code-signing-and-provisioning-in-depth]] | [[the-code-signature-blob-and-entitlements-on-ios]] | [[extensions-app-clips-widgets-and-widgetkit]] | [[networkextension-and-vpn]]*
