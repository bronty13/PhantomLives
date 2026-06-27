---
title: "EU DMA sideloading & alternative marketplaces"
part: "10 — iOS App Engineering"
lesson: 10
est_time: "40 min read + 15 min labs"
prerequisites: [distribution-testflight-appstore-enterprise]
tags: [ios, dev, forensics, eu-dma, sideloading, alt-marketplace, distribution]
last_reviewed: 2026-06-26
---

# EU DMA sideloading & alternative marketplaces

> **In one sentence:** The EU's Digital Markets Act forced Apple to open three new app-distribution channels on iOS — alternative marketplaces, Web Distribution, and direct marketplace installs — but every one of them still routes through Apple's mandatory **Notarization-for-iOS** gate, so the result is *gated* sideloading that creates a brand-new, forensically distinguishable install-provenance category rather than the open download model macOS has always had.

## Why this matters

For its entire history iOS had exactly one app source: Apple's App Store, enforced in silicon by AMFI refusing to launch any binary whose code signature didn't chain to an Apple-issued certificate. The DMA cracked that — but only in the EU, only through Apple-mediated plumbing, and only for binaries Apple still notarizes. As a **builder**, this is a new distribution surface with its own entitlements, packaging format (the ADP), fee regime (CTF→CTC), and a non-WebKit browser-engine track that didn't exist before. As a **forensic examiner**, it is a new and growing install-provenance class: an app on a 2026 EU iPhone might have arrived from the App Store, from the Epic Games Store, from a developer's own website, or from a raw exploit-based sideload — and the on-disk metadata that tells these apart is exactly what distinguishes a notarized, attributable install from an anonymous one. This lesson is the map: the regulation, the mechanism, the entitlements, the packaging, the fee transition that was mid-flight in mid-2026, and the artifacts that survive on disk.

> 🖥️ **macOS contrast:** This whole lesson is a study in *platform divergence*. macOS has **always** allowed direct download and third-party distribution — drag a `.app` out of any `.dmg`, or run an unsigned binary after a right-click-Open or `spctl --master-disable`. Gatekeeper + Developer ID + notarization on macOS are *advisory*: a determined user can always override them. iOS sideloading is the opposite — brand-new, EU-only, and *tightly gated*: there is no "Open anyway" escape hatch, notarization is mandatory and unbypassable outside an exploit, and the OS will only honor an alternative source if MarketplaceKit and a user-approved developer authorization are both in place. iOS borrowed the macOS *word* "notarization" but built a far more restrictive *mechanism* underneath it.

## Concepts

### The DMA, gatekeeper designation, and why iOS opened (but only in the EU)

The **Digital Markets Act** (Regulation (EU) 2022/1925) designates large platforms as **"gatekeepers"** and imposes *ex ante* obligations on their **"core platform services."** In September 2023 the European Commission designated Apple a gatekeeper, naming **iOS, the App Store, and Safari** as core platform services (iPadOS was added as a designated CPS in 2024). Two DMA articles drive everything in this lesson:

- **Article 6(4)** — a gatekeeper must allow third-party app stores and **sideloading**, and must not technically prevent users from installing apps from outside its own store.
- **Article 6(7)** — a gatekeeper must allow effective interoperability and access to the same OS/hardware features its own apps use (this is the lever behind the non-WebKit browser-engine entitlements and NFC/Wallet access).

Apple's response shipped in **iOS 17.4 (March 2024)** as a sweeping set of "Alternative Terms Addendum for Apps in the EU." The legally critical engineering consequence: every new channel is **EU-only**, scoped by *device eligibility* (the user's Apple Account country + region signals), not by a simple toggle. A build that uses these entitlements will be inert on a non-EU device.

> ⚖️ **Authorization:** Apple gates EU eligibility on the **Apple Account country** and on-device region signals, *not* on physical location alone. For an examiner this is a determinable fact — if a device shows alternative-distribution artifacts, the account was EU-provisioned at install time. Document the account region; it is part of establishing how an app could legally have arrived on the device.

### The three new distribution channels (plus the unchanged one)

Post-DMA, an EU iOS device can receive an app through **four** routes. Three are new:

```
                    ┌─────────────────────────────────────────────┐
                    │              NOTARIZATION-FOR-iOS            │  ← every channel
                    │   (Apple baseline malware/integrity review,  │     passes through
                    │    automated + human; signs & encrypts ADP)  │     this gate
                    └─────────────────────────────────────────────┘
                       ▲           ▲             ▲            ▲
        ┌──────────────┘   ┌───────┘     ┌───────┘    ┌───────┘
   ┌────┴─────┐      ┌──────┴──────┐ ┌────┴────────┐ ┌─┴──────────────┐
   │ App Store│      │ Alternative │ │     Web     │ │   (Dev/Ad-Hoc/  │
   │ (default,│      │ marketplace │ │ Distribution│ │ Enterprise — old│
   │ global)  │      │ (Marketplace│ │ (developer's│ │ channels, NOT   │
   │          │      │  Kit, EU)   │ │  own site)  │ │ notarized: see  │
   └──────────┘      └─────────────┘ └─────────────┘ │ provenance below)│
                                                      └─────────────────┘
```

1. **App Store** — unchanged, global, full App Review.
2. **Alternative app marketplaces** — third-party stores that are themselves iOS apps, installed *from the marketplace operator's own website* (web-installed, behind a one-time developer approval — the same web-download plumbing as Web Distribution, but governed by the separate **marketplace-authorization** program, *not* Web Distribution's 1M-install eligibility bar), that then vend other apps using **MarketplaceKit**. EU + (since iOS 26.2) Japan.
3. **Web Distribution** — an authorized developer hosts the app on **their own website** and installs it directly to EU users after the user approves that developer in Settings.
4. The **old non-App-Store channels** — Developer/Ad-Hoc/Enterprise (in-house) and exploit-based sideloads (AltStore "classic," TrollStore, Sideloadly). These predate the DMA, are **not** notarized-for-iOS, and are a *separate* provenance class — see [[08-trollstore-and-the-coretrust-bug]].

The crucial mental shift: routes 2 and 3 are **not** "raw sideloading." They are Apple-mediated installs that happen to originate off the App Store. Apple still signs the binary, still runs Notarization, still tracks the install through system frameworks.

### How "EU-only" is actually enforced

The regional gate is not a single boolean. Apple computes an **EU eligibility** status from a combination of signals — principally the **Apple Account country/region**, plus device-side signals (the device's region setting, and Apple's own location/SIM heuristics used to resist trivially spoofing eligibility). Eligibility is evaluated by the system, not by individual apps, and it controls whether MarketplaceKit, Web-Distribution installs, and the browser-engine entitlements are honored at all.

Two engineering consequences fall out of this:

- **Binaries are region-scoped, not just features.** Because the entitlements only function for EU eligibility, vendors who want both EU and non-EU behavior often maintain **two builds** (one with the DMA entitlements, one without) — a real maintenance burden and a frequent developer complaint to the Commission.
- **Eligibility can lapse.** Apple has stated that if a user is outside the EU for an extended period, alternative-distribution capabilities can be curtailed (e.g., installed marketplace apps may keep running but lose the ability to install new apps). Treat the exact grace-period behavior as **perishable — verify**; the durable point is that eligibility is *evaluated state*, not a one-time switch.

> 🔬 **Forensics note:** Eligibility state is itself an artifact. If a device carries marketplace/Web-Distribution apps, the account was EU-eligible **at install time**. Capturing the account country, region setting, and SIM/carrier history helps you reconstruct *when* the device could legally have received off-store apps — and whether eligibility later lapsed.

### MarketplaceKit — the on-device install broker

A marketplace is not a special OS component; it is **an ordinary iOS app** holding the marketplace entitlement, and the actual installation of *vended* apps is brokered by a system framework, **MarketplaceKit**, so that a third party never gets raw `installd` access.

The flow when a user taps "Install" inside a marketplace app, or clicks an install link in a browser:

```
Browser / marketplace app
   │  opens URL with the reserved scheme:  marketplace-kit://…
   ▼
MarketplaceKit (system framework)  ──►  the marketplace's MarketplaceExtension
   │   (an app extension: handles auth, install requests, deep-link launch)
   ▼
MarketplaceKit talks to the marketplace BACK-END over Apple-defined endpoints
   │   (returns the Apple-issued, notarized, signed ADP + metadata)
   ▼
installd  ──►  places bundle in /private/var/containers/Bundle/Application/<UUID>/
              AMFI verifies the Apple signature; the app launches
```

Key pieces to name:

- **`com.apple.developer.marketplace.app-installation`** — the **marketplace entitlement**. An app holding it may *vend and install other apps*. Approval is heavily gated: you must be a Developer Program org **incorporated/domiciled/registered in the EU** (or with an EU subsidiary), and you commit to ongoing requirements. (Verify the exact current criteria at author time — Apple has revised them more than once.)
- **`MarketplaceExtension`** — the app-extension point a marketplace implements to handle authentication, install/uninstall requests, and deep-link launches on the system's behalf.
- **`marketplace-kit`** — the reserved URI scheme that a marketplace's authorized website (or the marketplace app) uses to hand an install request to MarketplaceKit.

### Web Distribution — installing straight from a developer's website

Web Distribution lets a qualifying developer host a notarized app on **their own domain** and install it to EU users with no marketplace in between. The user flow inserts a one-time **developer approval** step in **Settings → (General →) VPN & Device Management / app-installation approval**, semantically similar to (but distinct from) trusting an enterprise certificate.

The qualifying bar is high and is the lesson's most perishable detail — **verify before relying on these numbers** — but as of mid-2026 the criteria were approximately:

| Requirement | Approx. value (verify at author time) |
|---|---|
| Developer Program enrollment | Org **incorporated/domiciled/registered in the EU** (or EU subsidiary) |
| Membership standing | Member in **good standing for 2+ continuous years** |
| App install scale | App had **> 1 million first annual installs on iOS in the EU** in the prior calendar year |
| Compliance | Agreed to the EU **Alternative Terms Addendum**; ongoing notarization |

The "good standing + 1M installs" floor means Web Distribution is, in practice, for *established* apps — it is not a route a hobbyist uses to ship a one-off binary. That floor is itself a forensic signal: a web-distributed app on a device implies a large, EU-incorporated publisher.

### The Alternative Distribution Packet (ADP) — the off-store package format

App Store apps ship as an **`.ipa`** (a zip with `Payload/<App>.app/`, plus `iTunesMetadata.plist` and a StoreKit receipt injected by the store — see [[04-the-app-bundle-and-ipa-structure]]). Off-store apps use a different container: the **Alternative Distribution Packet (ADP)**.

Mechanism:

1. You archive your app in Xcode as usual.
2. You **export for alternative distribution**, producing an **ADP** rather than an `.ipa`.
3. You **submit the ADP to Apple for Notarization** (via the App Store Connect API / Transporter). Apple runs the baseline review, then **encrypts and signs** the packet and returns the distributable artifact.
4. You **host the notarized ADP** — on your own server (Web Distribution) or behind your marketplace back-end (marketplace channel).
5. At install time, MarketplaceKit / the web-install flow fetches the ADP; `installd` + AMFI verify Apple's signature before the bundle is allowed to run.

The ADP is *not* an `.ipa` you can rename and AirDrop. It is an Apple-signed, encrypted distribution unit whose verification is enforced at install — which is precisely why off-store distribution can be "open" (any developer, any server) yet still attributable (Apple signed every byte that lands).

> 🔬 **Forensics note:** Because Apple **signs and encrypts** every notarized ADP, an alternative-marketplace or web-distributed app on disk carries an **Apple-issued code signature** in its `Contents`/embedded signature blob — just like an App Store app, and unlike a Developer-ID/enterprise/exploit-sideloaded binary. The *presence* of a valid Apple notarization signature, combined with the *absence* of a full App Store StoreKit receipt and `iTunesMetadata.plist`'s App Store account block, is the on-disk fingerprint of "notarized but off-store." See the provenance table below and [[01-the-code-signature-blob-and-entitlements-on-ios]].

### Notarization-for-iOS — the gate every channel shares

Apple reused the macOS *brand* "notarization" but built a stricter mechanism. **Every** EU-distributed app — App Store, marketplace, or Web Distribution — passes Notarization-for-iOS:

- **Automated** malware/virus/known-threat scanning, **plus human review** to confirm the app *functions as advertised* and doesn't commit egregious fraud.
- It is a **baseline platform-integrity** review, **not** App Review. Apple explicitly does **not** reject for business model, for competing with Apple's own apps, or for editorial/content/quality reasons on off-store apps.
- On success Apple **signs and (for ADPs) encrypts** the artifact. Installation is gated on that signature — there is **no user override** to install an un-notarized binary through these channels.

This is the load-bearing contrast with macOS. On macOS, notarization is a *trust hint*: Gatekeeper warns, but the user can right-click-Open or disable assessment entirely, and plenty of perfectly good Mac software ships un-notarized. On iOS there is no such valve — un-notarized code can only run via the *old* signing channels (dev/enterprise) or by defeating AMFI with an exploit.

> 🖥️ **macOS contrast:** Same word, different teeth. macOS notarization → a stapled ticket + `spctl` assessment you can bypass. iOS notarization → a mandatory, install-blocking Apple signature with no "Open anyway." If the learner's reflex is "notarization is the thing I can turn off," unlearn it for iOS.

### Non-WebKit browser engines — the end of the engine ban (on paper)

Before the DMA, **every** iOS browser was a WebKit reskin. Chrome and Firefox on iOS were `WKWebView` frontends; App Store rule 2.5.6 banned third-party engines outright. DMA Article 6(7) forced this open via **BrowserEngineKit**, the framework that lets an EU browser ship its own engine (Blink, Gecko) with the privileged primitives a modern engine needs — **JIT compilation**, multiprocess isolation, and a content-process sandbox profile.

The entitlement family (verify exact suffixes — the BrowserEngineKit set has been revised):

| Capability | Entitlement (approx.) | Who needs it |
|---|---|---|
| Host a full alternative browser engine | `com.apple.developer.web-browser-engine.host` | Dedicated browser apps |
| Rendering process | `com.apple.developer.web-browser-engine.rendering` | Engine's render process |
| Networking process | `com.apple.developer.web-browser-engine.networking` | Engine's network process |
| Web-content (JIT) process | `com.apple.developer.web-browser-engine.webcontent` | Engine's JS/JIT process |

"On paper," because as of mid-2026 the practical uptake was near-zero (verify): browser vendors and **Open Web Advocacy** argued Apple's terms — EU-only binaries, a requirement to test on physical EU devices, and the loss of cross-region reach — made shipping a real non-WebKit iOS engine commercially unattractive, so no major browser had broadly shipped one. The EU opened a specification proceeding over exactly this. Treat "has anyone actually shipped a non-WebKit engine at scale?" as a live, verify-at-author-time question.

> 🔬 **Forensics note:** A non-WebKit iOS browser is an **artifact landmine**. Your Safari/`WKWebView` parsing assumptions — `History.db` schema, `WebKit/` cache layout, `Cookies.binarycookies` format from [[08-safari-and-third-party-browsers]] — **do not apply** to a Blink- or Gecko-based browser. A Chromium engine writes Chromium artifacts (a `History` SQLite with `urls`/`visits`, a `Network/Cookies` store, `Login Data`), a Gecko engine writes `places.sqlite`. If you ever encounter a true alternative-engine browser on an EU device, identify the engine *first* and switch parsers accordingly.

### The fee transition: CTF → CTC (perishable — verify exact rates)

This is the **single most version-volatile fact in the course**. Pin everything here to mid-2026 and re-verify.

The DMA-era EU business terms unbundled what the standard App Store commission used to fold together into separately-charged components. The headline transition was from a **per-install fee** to a **revenue commission**:

- **Core Technology Fee (CTF)** — the original DMA-era charge: **€0.50 per "first annual install"** of an app, applied only **above 1,000,000 first annual installs per year**. A pure per-download fee, paid regardless of whether the app earned a cent. Widely criticized as a poison pill for free/viral apps. (Marketplace apps themselves also incurred the CTF per first annual install, with a waiver path for small developers.)
- **Core Technology Commission (CTC)** — the replacement: a **revenue-based commission (~5% on digital goods/services)** that applies across **all** EU channels — App Store, Web Distribution, and marketplaces — instead of the per-install CTF.

Apple announced (June 2025) a tiered structure intended to *fully retire* the CTF by **1 January 2026**, replacing it with the CTC, alongside a "Store Services" fee in tiers (≈5% vs ≈13% depending on services used) and an initial-acquisition fee (~2%). **As of mid-2026 the exact end-state was still contested** — reporting indicated the CTC (≈5%) was in force while Apple remained in discussions with the European Commission over the model, and some sources described the CTF as already replaced and others as not fully wound down.

> ⚠️ **ADVANCED (perishable):** Do **not** quote a fee number to a developer from this lesson. The structure (per-install CTF → revenue CTC, plus unbundled Store-Services + acquisition components) is the durable takeaway; the **rates, thresholds, tier definitions, and whether CTF is fully retired** were all in flux in 2026 and may have changed by the time you read this. Pull live values from `developer.apple.com/support/dma-and-apps-in-the-eu/` and the EU terms addendum.

> 🖥️ **macOS contrast:** There is **no macOS equivalent** to the CTF/CTC. Distributing a Mac app directly (your own `.dmg`, your own website) costs you a Developer ID membership and that's it — no per-install fee, no platform commission on off-store sales. The very existence of a "Core Technology" charge on iOS *off-store* distribution is the structural tell that iOS's openness is Apple-licensed, not free-as-in-macOS. On iOS, leaving the App Store doesn't leave Apple's meter running.

### The 2026 marketplace catalog (perishable — verify)

A snapshot as of **mid-2026**, EU (and noted Japan) — expect churn:

| Marketplace | Model | Notes (verify) |
|---|---|---|
| **Epic Games Store** | First-party + third-party games | Launched EU Aug 2024; Fortnite, Fall Guys, Rocket League Sideswipe |
| **AltStore PAL** | **Self-hosted "sources"** — devs host apps, users add a source URL | The notarized, MarketplaceKit successor to AltStore "classic"; UTM, OldOS, iTorrent, etc. |
| **Aptoide** | Curated/open catalog with safety scanning | iOS launched invite beta Jun 2024, then EU-wide |
| **Onside** | Lower dev rates; Apple Pay/card support | EU **and Japan as of 2026-02-17** |
| **Skich** | Discovery-first ("swipe to match") | EU |
| **Setapp Mobile** | Curated subscription bundle | **SHUT DOWN 2026-02-16** — a notable closure |

The Setapp Mobile shutdown and Onside's Japan expansion both happened in February 2026 — concrete evidence of how fast this catalog moves. **Japan** is now a *parallel* regime: its **Mobile Software Competition Act** drove Apple's "Changes to iOS in Japan," and alternative distribution + non-Apple payment processing arrived for Japan around **iOS 26.2**. EU and Japan are governed by different statutes but share much of the same MarketplaceKit/notarization plumbing.

To re-derive the live roster at author time rather than trusting this table: pull Apple's "marketplaces using MarketplaceKit" listings and the App Store Connect "Alternative Marketplaces and Web Distribution" API surface, and cross-check against current press coverage. The roster is volatile enough that an examiner naming a marketplace in a report should cite *when* it was confirmed active — a closed marketplace (Setapp Mobile) still leaves installed apps and association records on devices long after it shuts down.

### Install provenance — the forensic payoff

Here is the table an examiner actually uses. The same bundle on disk looks different depending on how it arrived, and the metadata that distinguishes the channels is exactly the metadata that establishes attribution.

| Channel | Notarized? | Code signature chains to | `iTunesMetadata.plist` | StoreKit/App Store receipt | Provisioning profile | Tell-tale artifacts |
|---|---|---|---|---|---|---|
| **App Store** | Yes | Apple App Store | **Full** (account block, `apple-id`, `purchaseDate`, `itemId`) | **Yes** | No (App Store apps have none) | `iTunesMetadata.plist` `com.apple.iTunesStore.downloadInfo` → `accountInfo` (purchaser AppleID + DSID) |
| **Alternative marketplace** | **Yes** | Apple (notarization) | Off-store metadata; **no App Store account block** | **No** App Store receipt | No | MarketplaceKit records; marketplace bundle ID associated; notarized signature |
| **Web Distribution** | **Yes** | Apple (notarization) | Off-store metadata | **No** | No | Web-distribution approval record; developer-domain provenance; notarized signature |
| **TestFlight** | (beta review) | Apple | TestFlight metadata | **Sandbox** receipt | No | TestFlight container/markers (see [[09-distribution-testflight-appstore-enterprise]]) |
| **Enterprise (in-house)** | **No** | Enterprise distribution cert | Usually **absent** | No | **Yes** (enterprise profile) | Enterprise provisioning profile + cert; trusted-developer record |
| **Dev / Ad-Hoc sideload** | **No** | Developer cert | **Absent** | No | **Yes** (dev/ad-hoc profile) | Embedded `embedded.mobileprovision`; UDID allowlist (ad-hoc) |
| **Exploit sideload (TrollStore)** | **No** | **Fake/forged** (CoreTrust bug) | Absent | No | None / forged | No valid Apple chain; CoreTrust-era only (≤ iOS 17.0); see [[08-trollstore-and-the-coretrust-bug]] |

The big-picture rule: **notarization splits the world.** App Store, marketplace, web-distributed, and TestFlight apps are all **Apple-signed/attributable**; enterprise, dev, ad-hoc, and exploit installs are **not notarized** and carry a *different* trust anchor (or none). Within the notarized set, the **App Store account block in `iTunesMetadata.plist` + a StoreKit receipt** is what specifically marks an *App Store* install — its absence on an otherwise-notarized app points to a marketplace or Web Distribution origin.

> 🔬 **Forensics note:** Reliable, well-documented provenance fields live in the per-app **`iTunesMetadata.plist`** at the bundle-container root (`/private/var/containers/Bundle/Application/<UUID>/iTunesMetadata.plist`). For App Store apps it carries `com.apple.iTunesStore.downloadInfo` → `accountInfo` (the **purchasing Apple ID and DSID**), `purchaseDate`, `itemId`, `artistId`, `genre`, `softwareVersionBundleId`, and `softwareVersionExternalIdentifier` (the App Store version build the user actually got). A subtle pivot: the Apple ID in `accountInfo` is the account that **purchased/downloaded** the app — for a sideloaded or copied app it may be a *different* account than the device owner, which can directly indicate the binary was sourced from someone else's library. Treat the exact key set on iOS 26 as worth confirming against your sample image — Apple has added and renamed keys across versions.

> ⚖️ **Authorization:** Install provenance is frequently a *contested* point in court — "I never installed that, someone else did," or "that app came from a third party I don't control." The notarization signature, the `accountInfo` Apple ID/DSID, the developer-approval record (Web Distribution), and the marketplace association are each attribution evidence. **Copy before you query** every SQLite store you touch (a bare `SELECT` write-locks the DB and spawns `-wal`/`-shm`), preserve the bundle container's metadata files, and log which channel each app's artifacts point to. Don't overstate: "notarized, off-store, downloaded under account X" is defensible; "the suspect deliberately sideloaded malware" is an inference you must support.

### On-device records the install flow leaves

Beyond the per-app `iTunesMetadata.plist` and the code-signature blob inside each bundle, the *act* of installing through a DMA channel leaves system-level records an examiner should look for. Mechanism-first (exact paths/schemas evolve per OS version — confirm against your sample image):

- **The install ledger.** `installd` is the daemon that unpacks every bundle into `/private/var/containers/Bundle/Application/<UUID>/` and registers it. SpringBoard/FrontBoard tracks app/container state in **`applicationState.db`** (`/private/var/mobile/Library/FrontBoard/applicationState.db`, SQLite) — bundle IDs, container UUIDs, and state flags. This ledger doesn't care *which channel* installed the app, but it's the authoritative list of "what is/was installed," and it persists references after a bundle is removed.
- **MarketplaceKit association records.** MarketplaceKit must remember which marketplaces the user added and authorized, and (per Apple's model) which apps were installed via which marketplace, so it can route updates and uninstalls. That state lives in MarketplaceKit's own data store under the framework's container (exact filename/path is worth confirming on iOS 26 — do not quote one you haven't verified). It is the artifact that ties an off-store app back to *the specific marketplace* that vended it.
- **The developer-approval record (Web Distribution + enterprise).** Approving a developer to install from their website, like trusting an enterprise certificate, writes a trust record surfaced in **Settings → General → VPN & Device Management**. The presence of a trusted *Web-Distribution* developer is direct evidence the device was set up to receive web-distributed apps.
- **Unified logs.** The install handoff is chatty: the browser's `marketplace-kit` scheme invocation, MarketplaceKit's back-end conversation, and `installd`'s unpack/verify all emit `os_log` entries. On a live or sysdiagnose-captured device you can pivot on the `installd` / MarketplaceKit subsystems to time-anchor an install. (Confirm the exact subsystem strings rather than trusting memory — see [[11-third-party-app-methodology]] for the methodology of mapping an app's stores.)

> 🔬 **Forensics note:** The forensic win of the DMA channels is *attribution density*. A raw pre-DMA sideload (dev cert + AltServer) is comparatively anonymous. A DMA-channel install threads through **four** corroborating records — the Apple notarization signature on the bundle, the `applicationState.db` registration, the MarketplaceKit/marketplace association (or the Web-Distribution developer-approval record), and the unified-log handoff trail. Reconstruct them together; any one alone is weaker than the chain.

### Two AltStores, two provenance classes

A common confusion worth resolving explicitly, because the *name* collides but the *provenance* is opposite:

| | **AltStore "classic"** (pre-DMA, global) | **AltStore PAL** (DMA, EU) |
|---|---|---|
| Mechanism | Re-signs apps with a **free personal-team developer cert**, refreshed every **7 days** by a companion **AltServer** on a trusted Mac | A **notarized, MarketplaceKit** alternative marketplace |
| Notarized? | **No** | **Yes** |
| Signature anchor | Your own developer cert (7-day expiry) | Apple (notarization) |
| Forensic tells | `embedded.mobileprovision`, short-lived cert, AltServer pairing on a Mac | Notarized signature, MarketplaceKit association, no App Store receipt |
| Region | Anywhere (it's a signing trick, not a DMA channel) | EU only |

The classic model is a *signing trick* exploiting personal-team certificates (the same primitive Sideloadly uses); the PAL model is a *sanctioned DMA marketplace*. An examiner who sees "AltStore" must determine **which** — they sit in different rows of the provenance table and imply very different things about how the device was set up.

## Hands-on

There is **no on-device shell**; everything here runs on the Mac against the Simulator, the iOS SDK, or a public sample image. You cannot perform a real EU marketplace install without an EU-eligible physical device, so the install *flow* is a walkthrough and the *artifacts/entitlements* are dissected on substrates you have.

**Inspect the entitlements that gate these channels, straight from the iOS SDK runtime.** The MarketplaceKit and BrowserEngineKit frameworks ship in the SDK; you can confirm the framework exists and read its symbols:

```bash
# Locate the iOS runtime root for the installed SDK
xcrun --sdk iphoneos --show-sdk-path

# Confirm MarketplaceKit / BrowserEngineKit are present in the SDK
ls "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks" | grep -iE 'Marketplace|BrowserEngine'
# MarketplaceKit.framework
# BrowserEngineKit.framework

# Dump exported symbols to see the install/marketplace API surface
nm -gU "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/MarketplaceKit.framework/MarketplaceKit.tbd" 2>/dev/null | head
```

**Read the embedded entitlements of any `.app` with `codesign`.** This is how you tell, from a binary alone, which privileged capabilities it claims (marketplace, browser-engine, web-distribution):

```bash
# Show the DER/plist entitlements embedded in a signed app binary
codesign -d --entitlements :- /path/to/SomeApp.app 2>/dev/null

# Grep for the marketplace / browser-engine entitlements specifically
codesign -d --entitlements :- /path/to/SomeApp.app 2>/dev/null \
  | grep -iE 'marketplace|web-browser-engine|web-distribution'
```

**Confirm an App Store app's provenance from `iTunesMetadata.plist`** (works on any IPA you have rights to, or a sample-image bundle container):

```bash
# Unzip an .ipa and read the account/provenance block
unzip -o SomeAppStoreApp.ipa -d /tmp/ipa_extract >/dev/null
plutil -p /tmp/ipa_extract/iTunesMetadata.plist \
  | grep -A6 -iE 'downloadInfo|accountInfo|apple-id|purchaseDate|itemId'
```

**Examine the code-signature trust anchor** to distinguish notarized vs. dev/enterprise-signed:

```bash
# Full signing info: authority chain tells you Apple vs. Developer ID vs. enterprise
codesign -dvvv /path/to/SomeApp.app 2>&1 | grep -iE 'Authority|TeamIdentifier|flags'
```

**The developer-side ADP export** (walkthrough — requires EU authorization, but the *shape* of the workflow is the same `xcodebuild -exportArchive` machinery you know from [[09-distribution-testflight-appstore-enterprise]]). You archive, then export with an `ExportOptions.plist` whose `method` selects an alternative-distribution variant instead of `app-store`/`ad-hoc`/`enterprise`:

```bash
# 1. Archive as usual
xcodebuild -scheme MyApp -archivePath build/MyApp.xcarchive archive

# 2. Export — the method key selects the distribution channel; the alternative-
#    distribution methods produce an ADP rather than an .ipa. (Confirm the exact
#    method string for the current Xcode — Apple has used names along the lines of
#    'alternative-distribution' / web-distribution variants; verify in Xcode's
#    Organizer or `xcodebuild -help`.)
xcodebuild -exportArchive \
  -archivePath build/MyApp.xcarchive \
  -exportPath  build/export \
  -exportOptionsPlist ExportOptions.plist

# 3. Submit the ADP to Apple for Notarization via the App Store Connect API /
#    Transporter; Apple returns the encrypted, signed, notarized packet to host.
```

The takeaway is structural: the build/sign machinery is the same toolchain; only the `method` (and the resulting *container* — ADP vs. `.ipa`) and the *destination* (your server / marketplace back-end vs. App Store Connect) differ. The Notarization step is the non-negotiable middle.

## 🧪 Labs

> All labs are **device-free**. EU marketplace/Web-Distribution installs **cannot** be reproduced without an EU-eligible physical device, so those steps are read-only walkthroughs; the substrate that *can* be exercised (Simulator, the iOS SDK, public sample images) is named per lab, with its fidelity caveat. **Simulator fidelity caveat:** the Simulator runs macOS frameworks — no SEP, no Data-Protection-at-rest, no AMFI/notarization enforcement, no baseband — and the device-only daemons (`knowledged`, `biomed`, `powerd`/PowerLog, `routined`) do **not** populate device-style stores; MarketplaceKit installs do not occur on the Simulator at all.

### Lab 1 — Map the entitlement gates (substrate: iOS SDK on your Mac)

1. Run the `xcrun --sdk iphoneos --show-sdk-path` + `ls … | grep` commands above. Confirm `MarketplaceKit.framework` and `BrowserEngineKit.framework` exist in your SDK.
2. From [[06-code-signing-and-provisioning-in-depth]], recall that a privileged entitlement must be *both* declared in the build *and* authorized by a provisioning profile/Apple. List the four channels (marketplace, web-distribution, browser-engine host, embedded browser engine) and write the entitlement that gates each.
3. **Caveat:** the framework existing in the SDK does **not** mean the Simulator will honor a marketplace install — entitlement enforcement is a *device* behavior absent on the Simulator.

### Lab 2 — Build the provenance fingerprint table from a sample image (substrate: public sample forensic image, e.g. Josh Hickman's iOS reference image / iLEAPP test data)

1. Mount or extract a public iOS sample image. Navigate to `/private/var/containers/Bundle/Application/`.
2. For several apps, locate each bundle container's `iTunesMetadata.plist` and `plutil -p` it. Note which apps have a full `com.apple.iTunesStore.downloadInfo` → `accountInfo` block (App Store) vs. which lack it.
3. For one App Store app, extract the **purchasing Apple ID and DSID** from `accountInfo`. Compare it to the device-owner account elsewhere in the image. Do they match? A mismatch is a finding.
4. **Caveat:** most public sample images predate broad EU alternative-distribution adoption, so you will mostly see App Store + dev/enterprise apps. Use the *absence* pattern (notarized but no App Store account block) as the conceptual signature for marketplace/web-distribution; you may not have a real off-store sample to confirm against. Flag this limitation in your notes.

### Lab 3 — Walk the MarketplaceKit install handoff (substrate: read-only walkthrough)

1. On paper, trace an install from a browser tap to a running app: `marketplace-kit://` URL → MarketplaceKit → the marketplace's `MarketplaceExtension` → marketplace back-end → notarized ADP returned → `installd` places the bundle → AMFI verifies Apple's signature → launch.
2. Identify, at each step, **what an examiner could recover**: the URL scheme invocation (browser history / unified logs), the MarketplaceKit association records, the bundle container + `iTunesMetadata.plist`, and the Apple-signed code-signature blob.
3. Contrast with a TrollStore install ([[08-trollstore-and-the-coretrust-bug]]): no MarketplaceKit, no notarization, a **forged** signature — i.e., the *opposite* provenance fingerprint.

### Lab 4 — Distinguish trust anchors with `codesign` (substrate: Simulator build + any signed `.app` you own)

1. Build any toy app and inspect it with `codesign -dvvv … | grep -iE 'Authority|TeamIdentifier'`. Note the authority chain for a dev-signed build.
2. If you have an App Store `.ipa` you're entitled to inspect, extract its `.app` and compare the authority chain — an Apple/App-Store anchor vs. your Developer ID/dev anchor.
3. Write the one-line rule you'd apply in triage to bucket an unknown app into *notarized (App Store / marketplace / web)* vs. *not-notarized (dev / enterprise / exploit)*.
4. **Caveat:** a Simulator build is signed for the Simulator, not notarized; it teaches the *codesign workflow*, not real device notarization state.

### Lab 5 — Triage "AltStore" provenance (substrate: read-only walkthrough + sample image if available)

1. Given an app whose install you suspect came from "AltStore," list the two hypotheses (classic vs. PAL) and the *single* discriminator that separates them: **is the signature notarized (Apple anchor) or self-signed (personal-team dev cert)?**
2. Enumerate the corroborating artifacts you'd seek for each: for **classic**, a short-lived `embedded.mobileprovision` and evidence of an AltServer/Mac pairing; for **PAL**, a notarized signature + a MarketplaceKit association record + the absence of an App Store receipt.
3. Write the triage decision as a flowchart: *valid Apple notarization?* → yes → marketplace/web/App-Store branch (then split on App Store receipt); no → dev/enterprise/exploit branch (then split on provisioning profile vs. forged signature).
4. **Caveat:** without a real EU off-store sample you are reasoning from the fingerprint, not confirming against ground truth — state that limitation in your report.

## Pitfalls & gotchas

- **"Sideloading on iOS = open like macOS."** No. The new channels are Apple-mediated and notarization-gated; there is no `spctl --master-disable`, no right-click-Open, no un-notarized install through any DMA channel. Truly un-notarized code still requires the *old* dev/enterprise signing or an AMFI bypass (exploit).
- **Assuming the entitlements work outside the EU.** Marketplace, Web-Distribution, and browser-engine entitlements are **EU-only** (Japan now parallel for some). A build using them is inert on a non-EU/Japan device. Don't conclude "the entitlement is broken" — check the account region.
- **Quoting CTF/CTC rates from memory.** The fee regime was *mid-transition* in 2026 and litigated. Any specific percentage or threshold you remember is probably stale. Cite the live Apple EU support page; describe the *structure*, verify the *numbers*.
- **Treating "notarization" as the macOS concept.** On iOS it's mandatory and unbypassable through these channels — same word, far stronger enforcement. Reviewing for *malware/integrity*, **not** App Review (no content/business-model rejection).
- **Assuming a third-party browser uses WebKit.** Pre-DMA that was guaranteed; post-DMA an EU browser *might* ship Blink/Gecko via BrowserEngineKit. If it does, its artifacts are Chromium/Gecko-shaped, not Safari-shaped. Identify the engine before parsing. (Uptake was still near-zero in mid-2026 — verify.)
- **Renaming an ADP to `.ipa` (or vice versa).** They are different containers; the ADP is Apple-encrypted/signed for install-time verification. You cannot hand-distribute a notarized ADP as a plain zip.
- **Catalog rot.** The marketplace list churns fast — Setapp Mobile *closed* and Onside *expanded to Japan* both in Feb 2026. Never present the marketplace roster as stable; date it.
- **Over-attributing from the Apple ID in `iTunesMetadata.plist`.** The `accountInfo` Apple ID is the *purchaser/downloader*, which may not be the device owner (shared/copied app). That mismatch is a *lead*, not a conclusion — corroborate.
- **Confusing the two "AltStores."** AltStore *classic* (personal-team cert, 7-day refresh, not notarized, global) and AltStore *PAL* (notarized DMA marketplace, EU) share a name but sit in opposite rows of the provenance table. Resolve *which* before drawing any conclusion about how the device was provisioned.
- **Treating EU eligibility as permanent.** It is *evaluated state* keyed to the Apple Account country plus device signals, and it can lapse if the user is outside the EU long enough. "This device has marketplace apps" proves EU eligibility *at install time*, not necessarily now.

## Key takeaways

- The **DMA** forced iOS open in the EU via **three new channels** — alternative marketplaces (MarketplaceKit), Web Distribution (developer's own site), and direct marketplace installs — but **every channel still passes Apple's mandatory Notarization-for-iOS** gate.
- **Notarization-for-iOS ≠ App Review** (it's baseline malware/integrity, automated + human) and **≠ macOS notarization** (it's mandatory and unbypassable, with no user override).
- The off-store package is the **ADP (Alternative Distribution Packet)** — Apple-signed and encrypted at notarization, hosted by the developer/marketplace, verified by `installd`/AMFI at install.
- **`com.apple.developer.marketplace.app-installation`** gates operating a marketplace; **Web Distribution** needs a high bar (EU org, 2+ yrs good standing, ~1M EU first-annual-installs — *verify*); **BrowserEngineKit** entitlements unlock non-WebKit engines (EU-only, near-zero real uptake in mid-2026 — *verify*).
- The **CTF→CTC** transition (per-install €0.50 fee → ~5% revenue commission) was **in flux in 2026** — learn the *structure*, never quote the *rate* from memory.
- For forensics, **notarization splits provenance**: App Store / marketplace / web-distributed / TestFlight apps are Apple-signed and attributable; enterprise / dev / ad-hoc / exploit (TrollStore) installs are **not notarized** and carry a different (or forged) trust anchor.
- Within the notarized set, the **App Store account block in `iTunesMetadata.plist` + a StoreKit receipt** is the specific marker of an *App Store* install; its absence on an otherwise-notarized app points to a marketplace or Web Distribution origin.
- **EU eligibility is evaluated state**, not a switch — keyed to the Apple Account country plus device signals, and it can lapse; marketplace artifacts therefore prove EU eligibility *at install time*.
- A DMA-channel install threads **four corroborating records** (notarization signature, `applicationState.db` registration, MarketplaceKit/Web-Distribution association, unified-log handoff) — reconstruct them together for attribution.
- The marketplace catalog (Epic, AltStore PAL, Aptoide, Onside, Skich; Setapp Mobile closed) and the EU/Japan regime split are **highly perishable** — date every catalog claim and re-verify.

## Terms introduced

| Term | Definition |
|---|---|
| DMA | Digital Markets Act (EU Reg. 2022/1925); designates "gatekeepers" and forces app-store/sideloading openness (Art. 6(4)) and feature interoperability (Art. 6(7)) |
| Gatekeeper (DMA) | An EU-designated large platform with *ex ante* obligations; Apple's iOS, App Store, Safari (and iPadOS) are designated core platform services |
| Alternative app marketplace | A third-party iOS app, holding the marketplace entitlement, that vends and installs other apps via MarketplaceKit (EU; Japan since iOS 26.2) |
| Web Distribution | Installing an authorized developer's notarized app directly from the developer's own website to EU users, after in-Settings developer approval |
| MarketplaceKit | The system framework brokering off-store installs; uses the `marketplace-kit` URI scheme and a marketplace's `MarketplaceExtension` |
| `com.apple.developer.marketplace.app-installation` | The marketplace entitlement; permits an app to vend/install other apps |
| MarketplaceExtension | App-extension point a marketplace implements for auth, install/uninstall, and deep-link launch on the system's behalf |
| ADP (Alternative Distribution Packet) | The off-store package format; Apple-signed and encrypted at notarization, hosted by the dev/marketplace, install-verified by `installd`/AMFI |
| Notarization-for-iOS | Apple's mandatory baseline malware/integrity review (automated + human) for *all* EU-distributed apps; signs/encrypts the artifact, no user override |
| BrowserEngineKit | Framework allowing EU browsers to ship non-WebKit engines (Blink/Gecko) with JIT, multiprocess, and a content-process sandbox |
| Browser-engine entitlements | `com.apple.developer.web-browser-engine.{host,rendering,networking,webcontent}` — gate hosting/running an alternative engine (verify suffixes) |
| CTF (Core Technology Fee) | The original DMA-era €0.50 *per first-annual-install* fee, charged above 1M installs/yr regardless of revenue (being phased out) |
| CTC (Core Technology Commission) | The revenue-based replacement (~5% on digital goods/services) applied across all EU channels (transition state perishable — verify) |
| `iTunesMetadata.plist` | Per-app provenance plist at the bundle-container root; App Store copies carry the `downloadInfo`/`accountInfo` purchaser Apple ID + DSID, `purchaseDate`, `itemId` |
| Install provenance | The forensic determination of how an app arrived (App Store / marketplace / web / TestFlight / enterprise / dev / exploit), via signature anchor + metadata |

## Further reading

- Apple — "Update on apps distributed in the European Union" (`developer.apple.com/support/dma-and-apps-in-the-eu/`); "Getting started as an alternative app marketplace in the EU"; "Using alternative browser engines in the EU"; the **Alternative Terms Addendum for Apps in the EU** (PDF)
- Apple Developer Documentation — **MarketplaceKit**, **BrowserEngineKit**, `com.apple.developer.marketplace.app-installation`; App Store Connect Help → "Managing alternative distribution" (Create a marketplace app / Submit for Notarization)
- Apple Support — "About alternative app distribution" (HT118110); "Installing apps through alternative app distribution" (HT117767)
- European Commission — DMA text (Reg. (EU) 2022/1925); gatekeeper designation decisions; Apple specification/non-compliance proceedings
- **Open Web Advocacy** — "Apple's Browser Engine Ban Persists, Even Under the DMA" and the Apple DMA Review (browser-engine track critique)
- RevenueCat blog — "Apple's June 2025 EU update: one entitlement, three fees, and CTF's 2026 sunset"; Michael Tsai (mjtsai.com) — "EU App Store Tiers and Core Technology Commission"; Daring Fireball (DMA policy-change analysis)
- TechCrunch — "Meet the alternative app stores available in the EU and elsewhere" (2026 catalog); Bright Inventions — "Diving into Alternative Marketplaces"
- Forensics — **Hexordia**, "What's brewing with IPAs — Working with IPA files for Forensic Examiners" (`iTunesMetadata.plist`, SINF, provenance keys); Alexis Brignoni / iLEAPP (bundle-container parsing); SANS FOR585
- `man codesign`, Apple TN3125 (inside code signing); `xcrun`, `plutil`, `nm`

---
*Related lessons: [[09-distribution-testflight-appstore-enterprise]] | [[04-the-app-bundle-and-ipa-structure]] | [[06-code-signing-and-provisioning-in-depth]] | [[01-the-code-signature-blob-and-entitlements-on-ios]] | [[08-trollstore-and-the-coretrust-bug]] | [[11-third-party-app-methodology]] | [[08-safari-and-third-party-browsers]]*
