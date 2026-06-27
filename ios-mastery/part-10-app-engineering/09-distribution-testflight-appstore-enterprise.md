---
title: "Distribution: TestFlight, App Store, enterprise"
part: "10 — iOS App Engineering"
lesson: 09
est_time: "45 min read + 15 min labs"
prerequisites: [code-signing-and-provisioning-in-depth]
tags: [ios, dev, forensics, distribution, testflight, app-store, enterprise]
last_reviewed: 2026-06-26
---

# Distribution: TestFlight, App Store, enterprise

> **In one sentence:** Every legitimate path an app can take onto an iPhone — App Store review, TestFlight beta, ad-hoc UDID lists, enterprise in-house signing, ABM Custom Apps, or (in the EU) a notarized alternative marketplace — leaves a *different, durable fingerprint* in the bundle's signature, provisioning profile, and metadata, so "how did this app get here?" is itself a forensic question with an answer you can read off disk.

## Why this matters

On macOS the learner already internalized three distribution lanes — Mac App Store, Developer-ID-direct + notarization, and unsigned/`spctl`-overridden — and Gatekeeper was a *check at first launch*, not a gate at install time. iOS is the opposite world: there is no Developer-ID-direct lane (until the EU DMA cracked one open), App Review is a mandatory human gate for the public store, and the platform enforces *who may install a given binary* via cryptographic provisioning at install time, not just at launch. For the builder, that means six genuinely distinct release channels with different review surfaces, expiry rules, and device limits. For the forensic examiner, it is even more valuable: the **channel an app arrived through is provenance evidence**. An App-Store binary, a TestFlight beta, an ad-hoc build, and an enterprise-signed app are *physically different files* — different signing authority, different provisioning profile shape, FairPlay-encrypted or not — and an **enterprise-signed app on a device with no MDM enrollment** is one of the loudest red flags in mobile DFIR. This lesson teaches the channels as a builder *and* teaches you to fingerprint them as an examiner.

## Concepts

### The iOS distribution problem (and why it differs from macOS)

On macOS, code signing answers "is this from a known developer and unmodified?" and Gatekeeper decides whether to *launch* it. Anyone with a $99 Apple Developer membership can sign with a **Developer ID** certificate, notarize, and hand the `.app` to the entire planet — no store, no review, no per-device authorization. The user double-clicks; Gatekeeper verifies the Developer-ID signature and the stapled notarization ticket; it runs.

iOS deliberately removed that lane. Until 2024 there was **no way to put your binary on an arbitrary stranger's iPhone except through App Review**. Every other channel is *bounded*: TestFlight caps testers and expires builds; ad-hoc embeds an explicit allow-list of device UDIDs; enterprise is contractually restricted to your own employees; Custom Apps go only to organizations you name. The platform enforces these bounds through the **provisioning profile** — a CMS-signed plist (`embedded.mobileprovision`) baked into the `.app` at sign time — plus the leaf certificate's identity and AMFI's install-time checks (see [[code-signing-amfi-entitlements]] and [[code-signing-and-provisioning-in-depth]]).

```
                         How an app reaches an iPhone (2026)
   ┌──────────────────────────────────────────────────────────────────────┐
   │  PUBLIC                          │  BOUNDED / PRIVATE                  │
   ├──────────────────────────────────┼─────────────────────────────────────
   │  App Store        → App Review   │  TestFlight   → Beta App Review     │
   │  (worldwide)        (human gate) │  (≤10k ext.)    (lighter gate)      │
   │                                  │                                     │
   │  EU marketplaces  → Notarization │  Ad-hoc       → no review           │
   │  / Web Distribution (automated   │  (≤100/devtype, UDID allow-list)    │
   │   + human baseline)              │                                     │
   │                                  │  Enterprise   → no review           │
   │                                  │  (in-house, own employees only)     │
   │                                  │                                     │
   │                                  │  Custom Apps  → App Review          │
   │                                  │  (named orgs via ABM)               │
   └──────────────────────────────────┴─────────────────────────────────────
```

> 🖥️ **macOS contrast:** macOS Developer-ID-direct = sign + notarize + ship to anyone, no review, no device list. iOS has *no general equivalent*: the closest is **EU Notarization** (automated + human malware/integrity baseline, but only inside EU alternative marketplaces / Web Distribution), and the *strictest-bounded* cousins are ad-hoc (per-UDID) and enterprise (per-employer). The macOS `spctl --master-disable` "run anything" escape hatch simply does not exist on stock iOS — that capability is what jailbreaks and TrollStore exist to manufacture.

### The signing identities behind the channels

Each channel is ultimately defined by *which certificate signs the binary* and *which provisioning profile authorizes it*, all chaining to an Apple root via the **Apple Worldwide Developer Relations (WWDR)** intermediate. The leaf identity is exactly what `codesign -dvvv` prints as `Authority=…`, so knowing the mapping turns a signature dump into a channel verdict:

| Channel | Signing certificate (leaf) | Profile shape |
|---|---|---|
| Development | **Apple Development: \<person\>** | development (`get-task-allow` + `ProvisionedDevices`) |
| Ad-hoc | **Apple Distribution / iPhone Distribution: \<Team\>** | ad-hoc (`ProvisionedDevices`, no `get-task-allow`) |
| TestFlight / App Store (upload) | **Apple Distribution: \<Team\>** | App Store distribution (`beta-reports-active` for TF) |
| App Store / Custom App (shipped) | re-signed by **Apple iPhone OS Application Signing** | *no* embedded profile in the shipped bundle |
| Enterprise in-house | **iPhone Distribution: \<Enterprise Org\>** (enterprise cert) | in-house (`ProvisionsAllDevices=true`) |
| EU marketplace / Web Distribution | developer/marketplace distribution cert | marketplace/Web-Distribution profile + Apple notarization ticket |

The pivotal asymmetry: a *shipped* App-Store/Custom-App binary is re-signed by **Apple's own** app-signing intermediate (always-valid, non-revocable from a third party's perspective), whereas every side channel keeps a **third-party leaf** (your Team's or an enterprise org's) that Apple can expire or revoke. That is the cryptographic reason side-channel apps are inherently more fragile — and why the leaf authority string is such a clean provenance tell.

### Channel 1 — App Store + App Review

The public lane. You archive the app in Xcode, upload the `.ipa` to **App Store Connect**, attach metadata (screenshots, description, privacy "nutrition label", age rating, export-compliance), and submit. A human reviewer plus automated tooling evaluates it against the **App Store Review Guidelines** before it can go live.

Mechanism worth knowing:

- **The binary is re-signed and FairPlay-encrypted by Apple.** What you upload is *your* Distribution-signed `.ipa`; what ships to users is re-signed by **Apple's "Apple iPhone OS Application Signing" intermediate** and has its primary Mach-O `__TEXT` wrapped in **FairPlay DRM** (the load command `LC_ENCRYPTION_INFO_64` gets `cryptid = 1`). This is the single most reliable provenance signal in the whole lesson — *only App Store and Custom-App binaries are FairPlay-encrypted*; everything else is `cryptid = 0`.
- **A receipt and `iTunesMetadata.plist` are attached.** The App Store wraps the bundle with an `iTunesMetadata.plist` (the purchasing Apple Account, item ID, purchase date, bundle ID, storefront) and a StoreKit **production receipt**. These do not exist on side-channel builds.
- **Review timing (2026, volatile):** Apple states ~90% of submissions are reviewed in under 24 h; real-world 2026 observations run 24–72 h, sometimes longer for brand-new accounts or sensitive-API apps. An **Expedited Review** request exists for critical fixes. The most common rejection bucket remains **Guideline 2.1 (App Completeness)** — crashes, placeholder content, broken demo accounts.

The submission has a **state machine** worth knowing, because each state is observable in App Store Connect and leaves a timestamped trail:

```
  Prepare for Submission ──submit──▶ Waiting for Review ──▶ In Review
        │                                                     │
        │                              ┌──────────────────────┼─────────────┐
        ▼                              ▼                       ▼             ▼
   (edit metadata)           Pending Developer Release   Rejected    Metadata Rejected
                                       │                  (resubmit)
                                       ▼
                              Ready for Distribution ──▶ (live, optionally Phased Release over 7 days)
```

The unit model also matters: an **app record** owns one or more **versions** (the user-facing version string), and each version is fulfilled by exactly one **build** (the uploaded binary, identified by `CFBundleVersion`). The *same* build can be promoted from TestFlight to a version submission — i.e. you can ship the exact bits your beta testers ran. **Phased Release** rolls a new version to a growing percentage of users over ~7 days (pausable), which is why "version went live" and "user actually received it" can be days apart — a timeline nuance for the examiner reconstructing *when* a given build could have reached a specific device.

> 🖥️ **macOS contrast:** A Mac App Store submission also goes through App Review and gets a Mac App Store receipt (`_MASReceipt/receipt`). The big difference: on macOS you can *bypass the store entirely* with Developer ID. On iOS, App Review is unavoidable for worldwide reach.

### Channel 2 — TestFlight (internal vs external, build expiry)

TestFlight is Apple's first-party beta channel, run *through* App Store Connect. The same upload you'd submit for review can instead be distributed to testers. Two tiers with sharply different rules:

| | **Internal testers** | **External testers** |
|---|---|---|
| Who | Up to **100** App Store Connect *users* (your team) | Up to **10,000** people (by email or public link) |
| Review gate | **None** — installable as soon as the build finishes processing | **Beta App Review** required for the *first build of each version* (lighter than full App Review) |
| Typical use | Dev/QA dogfooding | Public-ish beta |
| Build expiry | **90 days** | **90 days** |

The **90-day build expiry** is the rule examiners and builders both trip on: every uploaded build becomes uninstallable/unlaunchable 90 days after upload, regardless of tier. Apple does not extend it; you ship a fresh build, which starts its own 90-day clock. When a build expires the tester *loses the app entirely* — login state, local data, sandbox contents — gone.

Two operational details that matter to both roles: external testers can be invited individually by email *or* via a **public TestFlight link** (a shareable `testflight.apple.com/join/<code>` URL with a configurable join cap up to the 10,000 ceiling), which means a beta can spread to people the developer never personally invited — relevant when reconstructing how a tester obtained access. And every build still requires an **export-compliance** answer (encryption usage) before testers can install, so even a beta has a small compliance paper trail in App Store Connect.

Forensic fingerprints of a TestFlight install:

- Installed by the **TestFlight app** (`com.apple.TestFlight`), not the App Store, so install-attribution logs name TestFlight.
- The binary is **not** FairPlay-encrypted (`cryptid = 0`) — you can read its Mach-O directly.
- The `embedded.mobileprovision` carries the **`beta-reports-active`** entitlement, the cleanest "this was a TestFlight build" tell.
- StoreKit receipt is a **`sandboxReceipt`**, not a production `receipt`.

> 🔬 **Forensics note:** A `sandboxReceipt` alongside `beta-reports-active` in the embedded profile means the app on this device came through TestFlight, not the public Store — useful when reconstructing *when* and *how* a suspect obtained a not-yet-released or limited-distribution app. The 90-day expiry also bounds the timeline: a still-working TestFlight build was uploaded within the last 90 days.

### Channel 3 — Ad-hoc distribution (UDID-limited)

Ad-hoc lets a regular **$99 Apple Developer Program** member install on a fixed set of *specific* devices with no review and no TestFlight. The provisioning profile embeds an explicit allow-list:

- You register each device's **UDID** in the developer portal, generate an **ad-hoc distribution profile** whose `Entitlements` and `ProvisionedDevices` array name those exact UDIDs, and sign with an **iPhone Distribution** certificate.
- **Limit: 100 devices *per device type* per membership year** (iPhone, iPad, iPod touch, Apple Watch, Apple TV are separate buckets — so 100 iPhones *and* 100 iPads). The count resets at annual renewal, and you can only remove devices to reclaim slots once per year.
- Install vehicle is typically an **`itms-services://` manifest** (the "OTA install" `.plist` pointing at the `.ipa`) or a tool like Apple Configurator.

Forensic fingerprints:

- `embedded.mobileprovision` contains a **`ProvisionedDevices`** array of UDIDs — the literal list of which devices were *authorized* to run it. That list is investigative gold: it ties the binary to specific hardware.
- `cryptid = 0` (not FairPlay), no `iTunesMetadata.plist`, no production receipt, no `beta-reports-active`, signed by an `iPhone Distribution: <Team>` leaf.

> 🔬 **Forensics note:** A `ProvisionedDevices` list is a *roster of co-conspirator hardware*. If you recover an ad-hoc IPA, the UDIDs inside enumerate every device the signer intended to provision — even devices you have not yet seized.

### Channel 4 — Apple Developer Enterprise Program + in-house distribution

The **Apple Developer Enterprise Program (ADEP)** is a separate, restricted program for distributing *proprietary internal apps to your own employees* without the App Store, TestFlight, or per-UDID lists. Eligibility and terms (2026):

- **$299/year**, and you must be a **legal entity with 100+ employees** (no DBAs/fictitious names/branches). Apple vets enrollment and there is a **~14-day wait** after enrollment before you can create the enterprise provisioning credentials.
- You sign with an **enterprise Distribution certificate** and an **in-house provisioning profile** whose hallmark is **`ProvisionsAllDevices = true`** — *no* UDID list. That single key is what lets an enterprise build run on *any* device, which is precisely why this credential is so dangerous when abused.
- Apple's terms require in-house apps to be distributed only to employees and gated behind some authentication; first launch prompts the user to **trust the developer** under *Settings → General → VPN & Device Management*.

**Abuse is the forensic story here.** Because an enterprise cert + `ProvisionsAllDevices` profile installs on *any* iPhone with only a manual "trust" tap, it has been the workhorse of iOS malware and gray-market sideloading for a decade:

- **WireLurker** and **YiSpecter** (multi-component malware) abused enterprise certificates to install on non-jailbroken devices.
- **Gray-market "signing services"** (historically KravaSign, FlekStore, AppleP12, and many others) resell enterprise/developer certs to mass-install tweaked or **pirated** App Store apps. Apple periodically **revokes** these certs in waves — sometimes catching innocent developers in the blast radius.
- Revocation works because the device checks certificate validity (OCSP-style); once Apple revokes the enterprise cert, every app signed with it stops launching on next check.

> 🔬 **Forensics note:** An **enterprise-signed app on a device that is NOT MDM-enrolled** is a top-tier red flag. Legitimate enterprise apps arrive on *managed* devices via MDM. An enterprise-signed binary on a personal, unmanaged phone strongly suggests gray-market sideloading, a signing service, or malware. Read the leaf certificate's Organization (`codesign -dvvv`) and the profile's `ProvisionsAllDevices`/`TeamName` to identify *whose* enterprise account signed it — the signer's identity is often not the app's purported author.

> ⚠️ **ADVANCED:** Do not "trust" and launch an unknown enterprise-signed app on an evidentiary or personal device to "see what it does." Trusting it executes attacker-controlled, all-device-provisioned code outside any review. Analyze the IPA statically (next section's commands) or in an isolated, throwaway test environment only.

### Channel 5 — Custom Apps via Apple Business Manager

The *sanctioned* private-distribution channel that ADEP-abusers are trying to imitate. A **Custom App** is a normal App-Store-reviewed app that you choose to make **invisible to the public** and available only to specific organizations:

- You build and submit it through App Store Connect (it **goes through App Review** like any App Store app), but set its distribution to **"Custom Apps"** / **"Make app available to specific organizations"** and name the buying orgs by their **Apple Business Manager (ABM)** / Apple School Manager ID.
- The org then distributes it via **managed distribution (VPP)** through their MDM, or via **redemption codes** (legacy; max 10,000 codes per request, 25,000/week, country-specific, single-use). You keep the source and IP; the org just gets entitled copies.
- Because it is still an App-Store binary, it is **FairPlay-encrypted (`cryptid = 1`)** and carries `iTunesMetadata.plist` + a production receipt — the metadata may indicate B2B/VPP provenance and the entitling organization.

This is the legitimate answer to "I need a private internal app but don't qualify for / don't want the liability of ADEP." It trades the no-review freedom of enterprise for App Review safety and MDM-based distribution.

> 🔬 **Forensics note:** A Custom App is nearly indistinguishable on disk from a public App-Store app — same `cryptid=1`, same "Apple iPhone OS Application Signing" leaf, a present `iTunesMetadata.plist`. The differentiator lives in the metadata/receipt: B2B/VPP markers and the entitling organization rather than an individual consumer purchase. So when an app's binary screams "App Store" but the device is enterprise-managed, check whether it is actually a *Custom App* delivered via MDM — a legitimate private channel, not the enterprise-cert abuse pattern. Distinguishing the two (managed Custom App vs. raw enterprise sideload) hinges on signer identity and MDM enrollment state, not on the FairPlay layer.

### Channel 6 — Notarization-for-iOS + EU alternative marketplaces

The EU **Digital Markets Act (DMA)** forced Apple to open iOS to **alternative app marketplaces** and **Web Distribution** for users in the EU. The gate for these is **Notarization for iOS** — and it is *not* App Review:

- **Notarization is an automated + human integrity baseline**, not editorial curation. Apple's notary service uses machine learning, heuristics, and accumulated signals to check that the app is free of known malware, **functions as promised**, accurately represents itself, and does not expose users to **egregious fraud**. It does **not** judge business model, content category, or guideline compliance the way App Review does.
- Each alternative marketplace then applies **its own** review/curation policy on top. Apple notarizes for platform integrity; the marketplace decides what it lists.
- **All** iOS apps distributed in the EU — App Store, Web Distribution, *or* alternative marketplace — must still be notarized by Apple.
- **Web Distribution** is a *distinct* EU channel: an authorized developer distributes their **own** app directly from their **own website** (no marketplace intermediary), still gated by Apple Notarization plus a developer entitlement and a managed-by-Apple authorization-token / install-sheet flow. It is the closest iOS gets to a true "download an app from a website" experience — but only for EU users and only for developers Apple authorizes.
- **Business terms are mid-transition (volatile):** Apple is moving the EU to a single model, replacing the per-install **Core Technology Fee (CTF)** with the **Core Technology Commission (CTC)** on digital goods/services across the App Store, Web Distribution, and alternative marketplaces. Treat the exact fee rates and effective dates as *verify-at-author-time* — they have shifted repeatedly under regulatory pressure.

> 🖥️ **macOS contrast:** EU iOS Notarization is the *philosophical* sibling of macOS notarization — an automated malware/integrity scan that issues a ticket, with **no human editorial review** of whether the app is "good." It is the first time iOS has had a macOS-Developer-ID-shaped lane at all. The difference: macOS notarization works worldwide for any Developer-ID app; iOS Notarization only unlocks distribution *inside EU marketplaces/Web Distribution for EU users*, and the marketplace itself is still a gatekept entity. (See [[eu-dma-sideloading-and-alternative-marketplaces]] for the full DMA mechanics.)

### The iOS 26 SDK floor (a build-time gate, not a runtime one)

A current submission rule that bites everyone: **since 2026-04-28, every app uploaded to App Store Connect must be built with Xcode 26+ and an iOS/iPadOS/tvOS/visionOS/watchOS **26 SDK**.** Two clarifications that trip people up:

- This is about the **SDK you compile against**, *not* your **deployment target**. You can still set a minimum of iOS 16/17/18 and run on older devices — you just must *build* with the 26 SDK.
- A side effect: apps built against the iOS 26 SDK **adopt the Liquid Glass UI** on native controls by default unless you explicitly opt out. So a forced SDK bump can silently change your app's appearance.

The SDK floor is enforced at *upload* (App Store Connect rejects non-conforming binaries), so it applies to App Store, TestFlight, and Custom-App submissions. It does **not** retroactively pull existing live apps.

### Choosing a channel (builder's decision table)

| Goal | Channel | Review | Reach | Key constraint |
|---|---|---|---|---|
| Ship to the public worldwide | App Store | App Review | Anyone | Guidelines + IAP rules |
| Beta-test broadly | TestFlight (external) | Beta App Review | ≤10,000 | 90-day build expiry |
| Dogfood with your team | TestFlight (internal) | none | ≤100 ASC users | 90-day build expiry |
| Hand a build to a few named devices | Ad-hoc | none | ≤100/device type/yr | per-UDID registration |
| Internal app for your own employees | Enterprise (ADEP) | none | own employees | 100+-employee org, abuse risk |
| Private app for a named client org | Custom App (ABM) | App Review | named orgs | client must use ABM/MDM |
| Distribute in the EU off-Store | Marketplace / Web Distribution | Notarization | EU users | EU-only, CTC terms |

The decision usually collapses to two questions: **"public or private?"** and, if private, **"do I control the devices?"** Public → App Store (+ TestFlight to get there). Private + you control the devices → MDM Custom App. Private + you *don't* control the devices and they're your employees → enterprise (with eyes open about revocation risk). Anything that wants "install on any stranger's phone, no review" outside the EU does not exist as a sanctioned channel — and that absence is precisely the gap malware and sideload services try to fill.

### Provenance matrix — reading the channel off the binary

This is the lesson's forensic payload. Given a recovered `.app`/`.ipa` (or an app bundle pulled from a device image), four artifacts together identify the distribution channel with near-certainty:

| Channel | FairPlay `cryptid` | `embedded.mobileprovision` | Signing leaf (from `codesign -dvvv`) | `iTunesMetadata.plist` / receipt |
|---|---|---|---|---|
| **App Store** | **1** (encrypted) | *absent from bundle* | Apple iPhone OS Application Signing | present + **production** receipt |
| **Custom App (ABM/VPP)** | **1** (encrypted) | *absent from bundle* | Apple iPhone OS Application Signing | present (often B2B/VPP markers) |
| **TestFlight** | 0 | present, **`beta-reports-active`** | iPhone Distribution: \<Team\> | **`sandboxReceipt`** |
| **Ad-hoc** | 0 | present, **`ProvisionedDevices`=[UDIDs]** | iPhone Distribution: \<Team\> | none |
| **Development** | 0 | present, `ProvisionedDevices` + **`get-task-allow`** | Apple Development: \<name\> | none |
| **Enterprise in-house** | 0 | present, **`ProvisionsAllDevices`=true**, *no UDID list* | iPhone Distribution: \<Enterprise Org\> | none |
| **EU marketplace (notarized)** | 0 | marketplace distribution profile | marketplace/dev cert (+ Apple notarization ticket) | varies; not a Store receipt |

Reading order that resolves fastest:

1. **`cryptid`** (`otool -l … | grep crypt`): `1` ⇒ App Store *or* Custom App, full stop. `0` ⇒ a side channel; keep going.
2. **Presence + shape of `embedded.mobileprovision`**: absent ⇒ Store/Custom; `ProvisionsAllDevices` ⇒ enterprise; `ProvisionedDevices` array ⇒ ad-hoc/development; `beta-reports-active` ⇒ TestFlight.
3. **Signing leaf identity** (`codesign -dvvv`): "Apple iPhone OS Application Signing" ⇒ Store; "iPhone Distribution: \<Org\>" ⇒ check whether \<Org\> is an enterprise account; "Apple Development" ⇒ dev build.
4. **`iTunesMetadata.plist` / receipt type**: production receipt ⇒ Store/Custom; `sandboxReceipt` ⇒ TestFlight; none ⇒ ad-hoc/dev/enterprise.

> 🔬 **Forensics note:** These four artifacts cross-corroborate, which is what makes the inference robust to tampering. A re-signed/sideloaded App-Store rip is the classic anomaly: `cryptid` may be `0` (the FairPlay layer was stripped by a decrypt-and-repackage tool like frida-ios-dump), yet a leftover `iTunesMetadata.plist` still names the *original* purchasing Apple Account, while a *new* `embedded.mobileprovision` shows the **re-signer's** team/enterprise identity. That mismatch — original-purchaser metadata + foreign signer — is the signature of piracy/sideloading. (FairPlay decryption itself is covered in [[fairplay-encryption-and-decrypting-app-store-apps]].)

> ⚖️ **Authorization:** App binaries pulled from a device or an iCloud/iTunes backup are evidence. Classify provenance on a **working copy**, hash the original first (`shasum -a 256`), and log every command. The `iTunesMetadata.plist`'s purchasing Apple Account is **attributable PII** linking a human to an install — handle it under the same authority and minimization rules as any account identifier in scope.

### How revocation kills a side-channel app

The bounded channels stay bounded partly because Apple can pull the rug. Provisioning profiles and signing certificates both carry **expiry dates**, and certificates can also be **revoked** out-of-band:

- **Profile/cert expiry** is checked at launch. An ad-hoc or enterprise build with an expired `embedded.mobileprovision` simply refuses to launch — this is why sideloaded apps "stop working after a year" and why free-tier (7-day) development profiles are so short-lived.
- **Revocation** is the heavier hammer. When Apple revokes an enterprise/developer certificate (e.g. a busted signing service), devices learn of it through an online validity check (OCSP-style) and via Apple's pushed **trust state**; on the next launch/validation the AMFI/`amfid` path rejects the now-untrusted signature and the app dies — *all* apps signed by that cert, on *all* devices, at once. App-Store apps are unaffected because they are signed by Apple's own always-valid signing intermediate, not a revocable third-party leaf.

> 🔬 **Forensics note:** An app present on disk that **won't launch** can itself be evidence: a recovered enterprise/sideloaded binary whose signing cert was revoked still carries its full provenance (`embedded.mobileprovision`, signer identity, `cryptid=0`) even though it's now inert. Correlate the cert's revocation date (from public revocation-wave reporting or the device's validity-check logs) against the unified log to bound *when* the app last successfully ran.

### Where the install itself is recorded on-disk

Provenance lives in the *binary*, but the *act of installing* is recorded by the device's install subsystem — a second, corroborating evidence source the Simulator does not reproduce. On a real device image:

- **The wrapper container** at `/private/var/containers/Bundle/Application/<UUID>/` holds the `.app`, `iTunesMetadata.plist` (Store/Custom only), `SC_Info/` (FairPlay `sinf`/`supf` key material — present only for Store/Custom apps), and a per-container `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier` = the app's bundle ID, plus the container's identity).
- **The data container** at `/private/var/mobile/Containers/Data/Application/<UUID>/` holds the app's runtime data, including its `StoreKit/` receipt (`receipt` vs `sandboxReceipt`).
- **`installd`** is the daemon that performs installs; it writes a dedicated **MobileInstallation log** at `/private/var/installd/Library/Logs/MobileInstallation/` (a top-tier install-history artifact — iLEAPP parses it) and emits to the **unified log** under the `com.apple.mobileinstallation` subsystem, while the App Store download path runs through **`appstored`/`itunesstored`** — together naming *which* installer placed the app (App Store vs TestFlight vs a profile-based install) at install time.
- **`applicationState.db`** (under `/private/var/mobile/Library/FrontBoard/`) tracks per-app state and bundle-path↔container-UUID mappings — useful for resolving a UUID-named container back to a human-readable bundle ID. (Confirm the exact path on your target OS version; FrontBoard/SpringBoard layout has shifted across releases.)

> 🔬 **Forensics note:** Triangulate provenance from *both* sources: the binary's signature/`cryptid`/profile says **what channel** the app belongs to, while the `installd`/`appstored` unified-log entries and container metadata say **when and by which installer** it actually landed on this device. Agreement strengthens the finding; disagreement (e.g. an App-Store-shaped binary installed by something other than the App Store) is exactly the sideload/piracy anomaly worth chasing.

### What survives into a backup (and what doesn't)

A critical acquisition caveat for this whole chapter: a **logical iTunes/Finder backup does not contain the app binaries.** On restore, apps are *re-downloaded* from the App Store, so the backup carries each app's **data container** and an **installed-apps inventory** (bundle IDs, and in many backups per-app purchase metadata), but *not* the `.app`, its `embedded.mobileprovision`, or the Mach-O whose `cryptid` you'd inspect. That means **binary-level provenance (`cryptid`, signer, profile) is only available from a full-file-system acquisition or the live device — not from a standard logical backup.** iCloud backup behaves the same way: it records the app list and data, with the binary re-fetched from the user's purchase history. The *purchasing-account* link therefore often comes from the App Store **purchase history** tied to the Apple Account rather than from the backup itself. (See [[the-itunes-finder-backup-format]] and [[full-file-system-acquisition]]; exact backup-manifest keys vary by iOS version — confirm against your target.)

> 🔬 **Forensics note:** If your acquisition is a logical backup, you can still prove *which* apps were installed and read their data, but you **cannot** classify distribution channel from the binary because the binary isn't there. Channel fingerprinting (`cryptid`, `embedded.mobileprovision`, signer) requires full-file-system or live access — plan the acquisition method around the question you need to answer.

## Hands-on

There is no on-device shell; everything below runs on the **Mac**, against an `.ipa`/`.app` you have lawfully obtained (your own Xcode export, an open-source app's IPA, or a bundle carved from a sample forensic image). Start by unwrapping:

```bash
# An .ipa is just a zip; the bundle lives under Payload/
unzip -q MyApp.ipa -d /tmp/ipa && ls /tmp/ipa/Payload/MyApp.app
APP=/tmp/ipa/Payload/MyApp.app
```

**Decode the provisioning profile** (CMS-signed; `security cms` unwraps it):

```bash
security cms -D -i "$APP/embedded.mobileprovision" | plutil -p -
# Look for, in the printed plist:
#   "ProvisionsAllDevices" => 1            ← enterprise in-house
#   "ProvisionedDevices" => [ "00008…" ]   ← ad-hoc / development (UDID allow-list)
#   "Entitlements" => { "beta-reports-active" => 1 }   ← TestFlight
#   "Entitlements" => { "get-task-allow" => 1 }        ← development
#   "TeamName" / "TeamIdentifier"          ← who signed it
#   "ExpirationDate"                       ← when the profile dies
```

**Read the signing authority chain and Team ID:**

```bash
codesign -dvvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier='
# Authority=Apple iPhone OS Application Signing   ← App Store / Custom App
# Authority=iPhone Distribution: Acme Corp (ABCDE12345)  ← enterprise/ad-hoc dist cert
# TeamIdentifier=ABCDE12345
```

**Dump the embedded entitlements** (the *effective* grants, independent of the profile):

```bash
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p -
# application-identifier, get-task-allow, beta-reports-active, aps-environment, etc.
```

**Check FairPlay (`cryptid`) — the channel discriminator:**

```bash
MACHO="$APP/$(plutil -extract CFBundleExecutable raw "$APP/Info.plist")"
otool -arch arm64 -l "$MACHO" | grep -A4 -i 'LC_ENCRYPTION_INFO'
#   cryptid 1   ← FairPlay-encrypted ⇒ App Store / Custom App
#   cryptid 0   ← not encrypted ⇒ any side channel (or already-decrypted rip)
```

**Inspect App-Store provenance metadata** (only present on Store/Custom builds):

```bash
plutil -p "$APP/iTunesMetadata.plist" 2>/dev/null
# Key fields: "apple-id"/"appleId" (purchasing account), "itemId",
# "purchaseDate", "softwareVersionBundleId", "kind", "s"/storefront,
# and VPP/B2B markers on Custom Apps.   (Verify exact key names per OS version.)
```

**blacktop/`ipsw` cross-checks** (handy for batch entitlement/cert inspection):

```bash
ipsw ent --ipa MyApp.ipa            # entitlements view straight from the IPA
ipsw macho info "$MACHO" | grep -i crypt   # alternative cryptid read
```

**Chain of custody first.** Before any of the above against evidence, hash the original and work on a copy:

```bash
shasum -a 256 MyApp.ipa | tee MyApp.ipa.sha256        # record before touching
cp MyApp.ipa /case/working/ && cd /case/working        # analyze the copy only
```

**Device-only inventory (for when a device *is* in scope).** With a connected, unlocked, trusted device, `libimobiledevice` / `pymobiledevice3` enumerate installed apps and pull bundles — none of this works against the Simulator or a logical backup, and it is included only for completeness of the workflow:

```bash
# DEVICE-ONLY (no device here): list user apps with bundle IDs + versions
ideviceinstaller list --user                    # or: pymobiledevice3 apps list
# Pull an app's bundle for offline classification (requires the right tooling/jailbreak
# state for FairPlay-encrypted Store apps; see the FairPlay lesson)
```

**Builder side — exporting each channel.** `xcodebuild -exportArchive` selects the channel via the `method` key in the export-options plist (Xcode 15.3+ renamed these — `app-store` → `app-store-connect`, `ad-hoc` → `release-testing`, `development` → `debugging`; `enterprise`/`validation` unchanged):

```bash
# method values: app-store-connect | release-testing | enterprise | debugging | validation
xcodebuild -exportArchive \
  -archivePath build/MyApp.xcarchive \
  -exportPath  build/export \
  -exportOptionsPlist ExportOptions.plist
# Then upload to App Store Connect / TestFlight. xcrun altool --upload-app is
# DEPRECATED — prefer the Transporter app or the App Store Connect API. EU
# Notarization is submitted through Xcode Organizer / App Store Connect to the
# notary service (verify the current CLI surface at author time).
```

## 🧪 Labs

> Substrate note: Labs 1–2 use the **Xcode Simulator** and a **self-built IPA on your Mac** — fully device-free. **Fidelity caveat:** the Simulator builds apps for the *simulator* SDK, so a Simulator-installed app is **adhoc-signed (`-`), has no `embedded.mobileprovision`, and is never FairPlay-encrypted** — it cannot reproduce App-Store/TestFlight/enterprise provenance. For *real* channel fingerprints (FairPlay `cryptid=1`, production receipts, `ProvisionedDevices`), Lab 3 uses a **public sample forensic image**. The device-only install daemons (`installd`, `itunesstored`/`appstored`) and FairPlay-at-rest do not exist on the Simulator.

### Lab 1 — Anatomy of a Simulator app bundle (Simulator)

1. In Xcode, run any app on a booted Simulator. Then enumerate installed apps and their on-disk bundle paths:
   ```bash
   xcrun simctl listapps booted | plutil -p - | grep -E 'CFBundleIdentifier|Bundle.*Path|Data.*Path'
   ```
2. Pick your app's bundle path and inspect its signature and entitlements:
   ```bash
   APP="<path from step 1>"
   codesign -dvvv "$APP" 2>&1 | grep -E 'Authority|flags|Identifier='
   codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p -
   ```
3. Confirm the fidelity caveats yourself: `ls "$APP" | grep -i mobileprovision` returns **nothing** (no profile), the authority is **adhoc (`-`)**, and `otool -l "$APP/<exec>" | grep -i crypt` shows **`cryptid 0`** (no FairPlay). Write down *why* none of these can stand in for a real App-Store binary.

### Lab 2 — Classify your own exports (self-built IPA)

1. Archive an app in Xcode, then export it twice with different `method`s — e.g. `release-testing` (ad-hoc) and `debugging` (development) — producing two IPAs.
2. For each IPA, run the **Hands-on** pipeline (`security cms -D` on `embedded.mobileprovision`, `codesign -dvvv`, `codesign -d --entitlements`).
3. Tabulate the differences. You should see `get-task-allow` and a `ProvisionedDevices` list in the *development* export, and a `ProvisionedDevices` list **without** `get-task-allow` in the *ad-hoc* export. Map each to the provenance matrix row. (If you have a TestFlight-eligible distribution cert, add an `app-store-connect` export and observe there is *no* `ProvisionedDevices` and a different leaf — though Apple's FairPlay/`iTunesMetadata` wrapping only appears *after* the Store processes it, which the Simulator/Mac cannot reproduce.)

### Lab 3 — Read real channel provenance off a sample image (public forensic image)

> Use a public iOS reference image (e.g. a Josh Hickman / Digital Corpora image) mounted or extracted read-only. Work on copies; hash first.

1. Locate installed third-party app bundles under the wrapper container path:
   ```bash
   ls /<mounted-image>/private/var/containers/Bundle/Application/
   # each <UUID>/ holds the .app, iTunesMetadata.plist (Store apps),
   # BundleMetadata.plist, SC_Info/ (FairPlay sinf/supf), and the
   # .com.apple.mobile_container_manager.metadata.plist
   ```
2. For a chosen app, classify it using the four-artifact order: read `cryptid` (`otool`/`ipsw macho info`), check for `embedded.mobileprovision` and its keys, read `codesign -dvvv` for the leaf, and `plutil -p iTunesMetadata.plist`.
3. Find at least one App-Store app (expect `cryptid=1`, `iTunesMetadata.plist` present, *no* `embedded.mobileprovision`) and record the **purchasing Apple Account** from its metadata. Note in your lab log why that field is attributable PII and what authority you would need to act on it.
4. Stretch: if the image contains any *non-Store* third-party app, identify which side channel it came through and what that implies about how the device's user obtained it.

### Lab 4 — The piracy anomaly, end-to-end (read-only walkthrough)

> Substrate: a **read-only walkthrough** of the device-bound steps you cannot perform without a jailbroken phone, paired with a Mac-side reasoning exercise. **Fidelity caveat:** actually *producing* a decrypted-and-re-signed App-Store rip requires on-device FairPlay memory dumping (frida-ios-dump/`bagbak` against a jailbroken device) — out of scope here and covered in [[fairplay-encryption-and-decrypting-app-store-apps]]. This lab teaches you to *recognize* the result.

1. **Mental model of the attack.** A pirate buys an app once (legit App-Store install, `cryptid=1`, `iTunesMetadata.plist` naming *their* Apple Account). On a jailbroken device they dump the decrypted Mach-O from memory (now `cryptid=0`), repackage it, and **re-sign** it with a developer/enterprise cert so it installs on non-jailbroken victims. Trace what each step does to the four provenance artifacts.
2. **Predict the fingerprint.** Before reading on, write down what `cryptid`, `embedded.mobileprovision`, the signing leaf, and `iTunesMetadata.plist` should each show on the *final* pirated IPA. Then check yourself: `cryptid=0` (decrypted), a **freshly added** `embedded.mobileprovision` with the **re-signer's** team/enterprise identity, a leaf that is *not* "Apple iPhone OS Application Signing", yet a **surviving `iTunesMetadata.plist`** still naming the *original purchaser*.
3. **Name the tell.** The contradiction — *App-Store-only metadata + a non-Apple signer + missing FairPlay* — is the signature. Articulate why each artifact alone is ambiguous but the *combination* is conclusive.
4. **Tie it to install records.** On a real victim image, the app would have been placed by a profile-based installer, **not** `appstored`/`itunesstored`. Note which on-disk install records (from the "Where the install itself is recorded" section) you would pull to confirm the app did not arrive through the App Store, completing the picture the binary started.

> ⚠️ **ADVANCED:** The decrypt-and-re-sign workflow itself is device-bound and, applied to apps you did not author, is copyright infringement. This lab is recognition-only; do not perform FairPlay dumping or re-signing of third-party apps outside authorized research with proper rights.

## Pitfalls & gotchas

- **macOS reflex: "I'll just notarize and ship it."** There is no iOS Developer-ID-direct lane outside the EU. A notarized iOS app only installs through an EU alternative marketplace / Web Distribution for EU users — not "anyone, anywhere" like macOS Developer ID.
- **`cryptid=0` does not prove "not from the App Store."** A pirated/sideloaded App-Store app has been *decrypted* (FairPlay stripped) and re-signed — so it reads `cryptid=0` *but* still carries the original `iTunesMetadata.plist`. Always cross-check the metadata and signer, don't trust `cryptid` alone.
- **The 90-day TestFlight clock is silent.** A build "just stops working" for testers on day 91 with no warning to the developer. Don't schedule a beta that depends on a build outlasting 90 days.
- **Enterprise ≠ "for distributing to customers."** ADEP is contractually employees-only. Using it to ship to the public is an Agreement violation and gets the cert **revoked** — taking down *every* app it ever signed, on every device, at once. This is why gray-market signing services are perpetually unstable.
- **Ad-hoc device buckets are *per type* and reset annually.** 100 iPhones is a separate pool from 100 iPads, and you can only reclaim removed slots once per membership year — plan device rosters accordingly.
- **The iOS 26 SDK requirement is a build gate, not a runtime gate.** Don't confuse "must build with the 26 SDK" with "must require iOS 26." Your deployment target is independent. But beware the **Liquid Glass** default styling that the 26 SDK switches on.
- **`xcrun altool --upload-app` is deprecated.** Scripts pinned to it will rot; move to Transporter / the App Store Connect API. (Notarization for *macOS* uses `notarytool`; iOS EU notarization rides the Xcode/App Store Connect path — verify the current surface before automating.)
- **Custom Apps still pass App Review.** "Private" (ABM Custom App) is *not* "unreviewed." If you need genuinely unreviewed internal distribution you're in enterprise/MDM territory, with all its abuse-magnet baggage.
- **A logical backup cannot answer the channel question.** Re-stating because it bites: app binaries aren't in iTunes/Finder/iCloud backups (they're re-downloaded on restore). If your acquisition is logical-only, you have the data containers and the installed-apps list but *not* the `cryptid`/profile/signer needed to fingerprint distribution channel — escalate to a full-file-system or live acquisition if provenance is the question.
- **`cryptid` reads must target the right slice.** On a multi-arch (fat) Mach-O, inspect the **arm64/arm64e** slice (`otool -arch arm64 …`) — checking the wrong slice or a thinned simulator binary will mislead you about FairPlay status.

## Key takeaways

- iOS has **six legitimate distribution channels** — App Store, TestFlight, ad-hoc, enterprise in-house, ABM Custom Apps, and (EU) notarized marketplaces/Web Distribution — each bounded differently and each leaving a distinct on-disk fingerprint.
- **App Review** (human + automated, ~24–72 h in 2026) gates the public store and Custom Apps; **Beta App Review** is a lighter gate for TestFlight external testers; **Notarization** is an automated+human *integrity* baseline for EU alternative distribution, not editorial review.
- **TestFlight**: ≤100 internal / ≤10,000 external testers, **90-day build expiry**, fingerprinted by `beta-reports-active` + a `sandboxReceipt`.
- **Ad-hoc** embeds a `ProvisionedDevices` UDID allow-list (≤100 per device type/year); **enterprise** uses `ProvisionsAllDevices=true` (no list) and is the classic abuse vector for malware and gray-market sideloading.
- **FairPlay `cryptid`** is the fastest channel discriminator: `1` ⇒ App Store/Custom App, `0` ⇒ a side channel *or* a decrypted rip.
- For the examiner, **how an app arrived is provenance evidence**: an **enterprise-signed app on an unmanaged (non-MDM) device** is a major red flag, and an **original-purchaser `iTunesMetadata.plist` + a foreign re-signer** is the signature of piracy/sideloading.
- The **iOS 26 SDK / Xcode 26 upload requirement** (since 2026-04-28) is a build-time gate that also flips on Liquid Glass styling by default; **CTF→CTC** in the EU is still in flux — verify fee facts at author time.

## Terms introduced

| Term | Definition |
|---|---|
| App Review | Apple's mandatory human + automated evaluation of App Store / Custom App submissions against the App Store Review Guidelines. |
| Beta App Review | A lighter review applied to the first build of each version distributed to TestFlight **external** testers. |
| TestFlight | Apple's first-party beta channel (via App Store Connect): ≤100 internal, ≤10,000 external testers; builds expire after 90 days. |
| Build expiry (90-day) | A TestFlight build becomes uninstallable/unlaunchable 90 days after upload; not extendable. |
| Ad-hoc distribution | Installing on a fixed allow-list of registered device UDIDs (≤100 per device type/year) with no review. |
| UDID | Unique Device Identifier; the per-device value embedded in ad-hoc/development provisioning profiles. |
| `embedded.mobileprovision` | The CMS-signed provisioning-profile plist baked into a `.app`, encoding allowed devices, entitlements, team, and expiry. |
| `ProvisionedDevices` | Provisioning-profile array of authorized device UDIDs (ad-hoc/development). |
| `ProvisionsAllDevices` | Provisioning-profile flag (`=true`) marking an **enterprise** in-house profile that runs on any device. |
| `beta-reports-active` | Entitlement marking a TestFlight build. |
| `get-task-allow` | Entitlement marking a development build (allows debugger attach). |
| Apple Developer Enterprise Program (ADEP) | $299/yr program for 100+-employee legal entities to sign internal-only apps for their own employees. |
| In-house distribution | Enterprise channel using an enterprise Distribution cert + `ProvisionsAllDevices` profile, employees-only. |
| Custom Apps | App-Store-reviewed apps made visible only to organizations you name, distributed via ABM (MDM/VPP or redemption codes). |
| Apple Business Manager (ABM) | Apple's org portal for buying/distributing apps and managing devices; entitling layer for Custom Apps and VPP. |
| Managed distribution (VPP) | Distributing entitled app copies to a device fleet through MDM rather than per-user purchase. |
| Redemption codes | Single-use, country-specific codes (≤10,000/request, 25,000/week) for distributing a purchased/custom app. |
| Notarization (iOS) | Apple's automated + human *integrity* baseline (malware-free, functions-as-promised, no egregious fraud) gating EU alternative distribution. |
| Core Technology Fee / Commission (CTF/CTC) | The per-install fee (CTF) being replaced by a commission model (CTC) for EU app distribution under the DMA. |
| FairPlay / `cryptid` | App Store/Custom-App DRM encrypting the primary Mach-O; `LC_ENCRYPTION_INFO_64` `cryptid=1` when present. |
| `iTunesMetadata.plist` | Plist wrapped onto App Store/Custom-App bundles recording purchasing Apple Account, item ID, purchase date, etc. |
| `sandboxReceipt` | The StoreKit receipt variant present on TestFlight (sandbox) installs, vs. a production receipt on Store installs. |
| iOS 26 SDK requirement | Since 2026-04-28, App Store Connect uploads must be built with Xcode 26 + an OS-26 SDK (build-time, not deployment-target, gate). |

## Further reading

- Apple — *App Review* (developer.apple.com/distribute/app-review/) and the **App Store Review Guidelines**.
- Apple — *TestFlight overview* (App Store Connect Help) for tester limits and the 90-day expiry.
- Apple — *Apple Developer Enterprise Program* (developer.apple.com/programs/enterprise/) + the **Enterprise Program License Agreement** PDF.
- Apple — *Volume Purchase and Custom Apps* and *Set distribution methods* (App Store Connect Help) for ABM Custom Apps / managed distribution.
- Apple — *Update on apps distributed in the European Union* and *Submit for Notarization* (DMA notarization + alternative marketplaces); **Complying with the DMA** PDF.
- Apple — *Upcoming/Minimum SDK requirements* news (the iOS 26 SDK / Xcode 26 mandate, effective 2026-04-28).
- Apple Developer — TN3125 (in-process code signing) and the entitlements reference, for the profile/entitlement keys above.
- The Apple Wiki — *Misuse of enterprise and developer certificates* (WireLurker, YiSpecter, signing-service revocations).
- Forensics — Sarah Edwards (mac4n6.com), Alexis Brignoni (**iLEAPP**), Jonathan Levin (*MacOS and iOS Internals*) for app-container layout, `iTunesMetadata.plist`, and receipt artifacts.
- Tooling — `man codesign`, `man security` (`cms`), `man otool`; blacktop/`ipsw`; `frida-ios-dump` / `bagbak` (FairPlay decrypt context).

---
*Related lessons: [[code-signing-and-provisioning-in-depth]] | [[the-app-bundle-and-ipa-structure]] | [[eu-dma-sideloading-and-alternative-marketplaces]] | [[fairplay-encryption-and-decrypting-app-store-apps]] | [[mdm-supervision-and-abm]] | [[app-sandbox-and-filesystem-layout]] | [[the-jailbreak-landscape-2026]]*
