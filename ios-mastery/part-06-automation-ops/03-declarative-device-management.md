---
title: "Declarative Device Management"
part: "06 — Automation & Operations"
lesson: 03
est_time: "45 min read + 15 min labs"
prerequisites: [mdm-supervision-and-abm]
tags: [ios, operations, ddm, declarative-management, mdm]
last_reviewed: 2026-06-26
---

# Declarative Device Management

> **In one sentence:** Declarative Device Management (DDM) flips Apple's management model inside-out — instead of a server pushing imperative commands one at a time and polling for results, the device holds a set of JSON *declarations*, autonomously evaluates and enforces them, and proactively reports its own state up a *status channel* — which means the device itself now carries an on-disk, self-authored record of exactly how it is managed and what it told its MDM.

## Why this matters

You already know the imperative MDM world from [[mdm-supervision-and-abm]]: an APNs poke wakes the device, it polls the server's check-in URL, the server hands back one command (`InstallProfile`, `RemoveProfile`, `DeviceInformation`…), the device runs it and returns an `Acknowledged`/`Error`, repeat. That model is now legacy. As of the iOS/iPadOS/macOS **26** cycle, Apple's framing is blunt — *"the standard for device management is declarative management"* (Cyrus Daboo, WWDC26) — and the **27** releases begin *removing* imperative pathways (the software-update MDM commands are gone in 27.0).

For a forensic examiner this is not an IT-ops footnote; it changes what is on the disk. Under DDM the *desired state* is resident on the device as parseable JSON, the device runs a daemon (`remotemanagementd`) that continuously enforces it, and the device keeps a SQLite store of declarations plus a **status** ledger of what it has reported back. Recover that and you can read the device's exact management posture — which MDM owns it, what restrictions and passcode policy are enforced, supervision and enrollment state — *and* the device's own self-assessment as it was transmitted to the server. This lesson is the mechanism: the four declaration types, the inverted sync flow, how legacy `.mobileconfig` profiles get wrapped in, the WWDC26 backup/restore change, and where every bit of it lands on disk.

## Concepts

### The inversion: imperative commands → declared state

The defining difference is *where the intelligence lives*. In classic MDM the **server is the brain**: it decides what to do, issues a command, waits, decides the next command. The device is a thin executor that does nothing between pokes. This is chatty, serialized, and fragile — a device that misses a poke (offline, asleep, rebooting) silently drifts, and the server only finds out when it next polls.

DDM makes the **device the brain**. The server publishes a set of declarations describing the *desired end state*; the device takes ownership of reaching and *maintaining* that state on its own, re-evaluating when conditions change and self-correcting without being told. The server's job shrinks to (a) publishing declarations and (b) subscribing to the status items it cares about.

```
IMPERATIVE MDM (legacy)                  DECLARATIVE (DDM)
Server          Device                   Server                Device
  | InstallProfile -->|                    | DeclarativeManagement -->|  (bootstrap, once)
  | <-- Acknowledged -|                    | <-- GET .../tokens ------|  "what's the manifest?"
  | InstallProfile2 ->|                    | tokens(ids+ServerToken)->|
  | <-- Acknowledged -|                    | <-- GET changed decls ---|  (only what differs)
  | DeviceInformation>|                    | declaration JSON --------|
  | <-- Acknowledged -|                    |     [device evaluates predicates,
  |   ...one at a time |                    |      applies configs ATOMICALLY,
  | (server = brain;   |                    |      enforces continuously]
  |  device = executor)|                    | <-- POST .../status -----|  proactive, on change
                                            | (device = brain; server subscribes)
```

The payoffs are scale and resilience: the server is no longer a per-device state machine running a command queue, so one server fans out to far more devices; and because the device owns enforcement, a missed APNs poke just delays the *next* status report — the policy is already resident and still enforced.

> 🖥️ **macOS contrast:** This is not an iOS-only protocol. DDM is the **same cross-protocol model Apple now uses for macOS, tvOS, watchOS, and visionOS** — your `macos-mastery` work predated it, but a managed Mac in 2026 runs the identical `remotemanagementd`, holds the same four declaration types, and writes to a `RemoteManagement.sqlite` of the same shape (see the on-disk section). When you reason about DDM on iPhone you are simultaneously learning how a 2026 fleet Mac is managed. The one practical difference: a Mac gives you the `profiles` CLI to introspect locally; iOS has no on-device shell, so you read it from an acquired image.

### The four declaration types

Every declaration is a JSON object. There are exactly four top-level *classes*, distinguished by the `Type` string's prefix:

| Class | `Type` prefix | Role | Example identifiers |
|---|---|---|---|
| **Configuration** | `com.apple.configuration.*` | The actual policy — accounts, passcode, restrictions, software-update enforcement, a wrapped legacy profile, and (counterintuitively) **the server's status subscriptions**. **Inert until an activation references it.** | `com.apple.configuration.passcode.settings`, `com.apple.configuration.legacy`, `com.apple.configuration.softwareupdate.enforcement.specific`, `com.apple.configuration.management.status-subscriptions` |
| **Activation** | `com.apple.activation.*` | The "switch." References a set of configurations and (optionally) carries a **predicate**. When the predicate is true, all referenced configurations apply **atomically** (all-or-nothing). | `com.apple.activation.simple` |
| **Asset** | `com.apple.asset.*` | Ancillary/bulk data a configuration *references* — credentials, identity certs, a profile blob, per-user data. One asset → many configurations (no duplication). | `com.apple.asset.credential.certificate`, `com.apple.asset.data`, `com.apple.asset.useridentity` |
| **Management** | `com.apple.management.*` | Conveys overall management state *to* the device: organization info, what the *server* is capable of, and free-form server-defined **properties**. (Status subscriptions are **not** here — they are a *configuration*; see below.) | `com.apple.management.organization-info`, `com.apple.management.server-capabilities`, `com.apple.management.properties` |

The mental model is a small dependency graph: an **activation** points at one or more **configurations**; a configuration may point at one or more **assets**; **management** declarations describe the relationship itself (org identity, server capabilities, properties). What the device *reports back* is governed by a status-subscriptions **configuration** — counterintuitively a member of the *configuration* class, not the management class (`com.apple.configuration.management.status-subscriptions`), so it too is inert until an activation references it. Nothing takes effect until an *activation's predicate evaluates true on the device*.

### Anatomy of a declaration

Three keys are **required on every declaration**, regardless of class:

- **`Type`** — the declaration type string (the `com.apple.*` value above).
- **`Identifier`** — a server-chosen unique ID for *this* declaration (reverse-DNS by convention). Stable across revisions.
- **`ServerToken`** — an opaque string the server changes whenever the declaration's contents change. It is the **version/revision marker**: the device compares the `ServerToken` it holds against the one in the manifest to decide whether to re-fetch. (Think ETag.)

…plus a **`Payload`** carrying the type-specific keys.

A configuration (passcode policy):

```json
{
  "Type": "com.apple.configuration.passcode.settings",
  "Identifier": "com.acme.config.passcode",
  "ServerToken": "v3-2026-06-01",
  "Payload": {
    "RequirePasscode": true,
    "MinimumLength": 6,
    "RequireComplexPasscode": true,
    "MaximumFailedAttempts": 10
  }
}
```

An activation that turns it on, but only on iOS 26+:

```json
{
  "Type": "com.apple.activation.simple",
  "Identifier": "com.acme.activation.baseline",
  "ServerToken": "v1",
  "Payload": {
    "StandardConfigurations": [
      "com.acme.config.passcode",
      "com.acme.config.restrictions"
    ],
    "Predicate": "@status(device.operating-system.family) == 'iOS' AND @status(device.operating-system.version) >= '26.0'"
  }
}
```

Note `StandardConfigurations` is a *list of Identifiers*, not inline content — declarations reference each other by `Identifier`. The `Predicate` is an `NSPredicate`-style expression; status values are pulled in with the `@status(...)` operator (more below).

> 🔬 **Forensics note:** The `ServerToken` is quietly useful. Because it changes only when the declaration's content changes, a sequence of `ServerToken` values recovered across acquisitions (or across status reports) tells you *when policy was revised* even if the payload looks the same. And the `Identifier` set, recovered from one device, is the server's naming scheme for its whole fleet — reverse-DNS identifiers like `com.acme.activation.executives` leak organizational structure and intent.

### The status channel: device-reported state

The fourth pillar — and the most forensically interesting — is the **status channel**. Rather than the server polling `DeviceInformation`, the device **proactively POSTs status updates** to the server when subscribed values change. The server declares what it wants via a status-subscriptions **configuration** — note the type lives in the `com.apple.configuration.*` namespace (`com.apple.configuration.management.status-subscriptions`), *not* `com.apple.management.*`, so an activation must reference it before it takes effect:

```json
{
  "Type": "com.apple.configuration.management.status-subscriptions",
  "Identifier": "com.acme.config.status",
  "ServerToken": "v1",
  "Payload": {
    "StatusItems": [
      { "Name": "device.operating-system.version" },
      { "Name": "device.identifier.serial-number" },
      { "Name": "passcode.is-present" },
      { "Name": "passcode.is-compliant" },
      { "Name": "management.declarations" }
    ]
  }
}
```

Status items are a published namespace. A representative sample:

| Status item | Reports |
|---|---|
| `device.identifier.serial-number` | Device serial |
| `device.identifier.udid` | UDID |
| `device.operating-system.version` | OS version string |
| `device.operating-system.family` | `iOS` / `iPadOS` / `macOS` / … |
| `device.model.identifier` | e.g. `iPhone17,2` |
| `passcode.is-present` | Whether a passcode is set |
| `passcode.is-compliant` | Whether it meets the passcode configuration |
| `management.declarations` | The full set of declarations the device holds + their valid/active state |
| `management.client-capabilities` | Which declaration types/payloads this build supports |
| `softwareupdate.*` | Pending/installed update state for declarative SU enforcement |
| `diskmanagement.*` | FileVault/disk state (macOS) |

Two properties make them powerful:

1. **Selective subscription.** The server hears only the items it asked for — no firehose, no polling.
2. **Status items double as predicate inputs.** The very same `passcode.is-compliant` the server subscribes to is what an *activation predicate* can test (`@status(passcode.is-compliant) == true`). This is the closed loop that lets the device act autonomously: it reads its own status, evaluates predicates locally, and applies/removes configurations without a round trip.

The device also reports the *result of applying each declaration* — a per-declaration `valid` / `invalid` / `unknown` state and any errors — which is how the server learns a configuration failed without issuing a query. A status report the device emits is itself JSON, roughly:

```json
{
  "StatusItems": {
    "management": {
      "declarations": {
        "configurations": [
          { "identifier": "com.acme.config.passcode", "active": true, "valid": "valid", "server-token": "v3-2026-06-01" }
        ],
        "activations": [
          { "identifier": "com.acme.activation.baseline", "active": true, "valid": "valid" }
        ]
      }
    },
    "device": { "operating-system": { "version": "26.5" } },
    "passcode": { "is-present": { "value": true }, "is-compliant": { "value": true } }
  }
}
```

That single object is a device-authored snapshot: *which* declarations it holds, *whether* it considers each active and valid, its OS version, and its passcode posture — all as the device itself sees it.

> 🔬 **Forensics note:** The status channel turns the device into a **self-authoring ledger**. The status it has reported is the device's *own* assessment of itself — OS version, passcode present/compliant, which declarations it considers active and valid — captured at the moment of each report. Recovering that store (or even the most recent serialized report queued for transmission) gives you the device's self-described posture at a point in time, independent of what any server-side record claims. When server logs and device-reported status disagree, that discrepancy is itself evidence.

### Predicates and autonomous activation

A predicate is what lets the device decide locally. It is an `NSPredicate` string that the device evaluates against status item values via `@status(<item>)`. Examples of the shape:

```
@status(device.operating-system.version) >= '26.0'
@status(passcode.is-present) == true
@status(device.model.family) == 'iPad'
@status(management.client-capabilities.supported-features.declarative-device-management) == true
```

When an activation's predicate flips from false to true (e.g., the user finally sets a passcode, or an OS update changes the version), the device *atomically* applies that activation's whole `StandardConfigurations` set; when it flips back to false, it removes them. The atomicity is the contract: you never get a half-applied activation where the Wi-Fi config landed but the certificate it depends on did not. This is why assets and configurations are separate declarations — the device resolves the entire dependency graph for an activation and commits it as a unit.

### Extensibility and client capabilities

The fourth design pillar (after declarations, status, and predicates) is **extensibility** — the protocol is built so new declaration types and status items can be added each OS cycle without a protocol revision, and so a server can *discover* what a device supports rather than guessing from the OS version. The device publishes a **client-capabilities** structure (queryable as a status item, e.g. `management.client-capabilities.supported-payloads.declarations.configurations`) enumerating exactly which declaration types and payload keys *this* build understands. A well-built management server reads that and only sends declarations the device can act on.

This is why the 2026 migration is incremental rather than a flag-day cutover: Intelligence/Siri/keyboard controls became declarative configurations at **26.4**, software-update enforcement went declarative earlier, and `ProfileAssetReference` arrived at **27** — each addition surfaces in client-capabilities, and older devices simply don't advertise it. For an examiner, the recovered client-capabilities (and the set of declaration types actually present) is a fingerprint of the device's OS-feature generation that corroborates the reported `operating-system.version`.

### The synchronization flow

DDM does not get its own transport; it **rides on top of the existing MDM enrollment** (same identity, same APNs, same check-in plumbing from [[mdm-supervision-and-abm]]). The handoff is one bootstrap command:

1. **Bootstrap.** The server sends a single imperative `DeclarativeManagement` MDM command over the legacy check-in channel. This is the *only* imperative step — it tells the device "from here, you're declarative" and points at the DDM endpoint.
2. **Token sync.** The device requests the **tokens** endpoint: the server returns the *manifest* — every declaration `Identifier` it should have, each tagged with its current `ServerToken`. The device diffs this against what it holds.
3. **Selective fetch.** For each `Identifier` whose `ServerToken` differs (or is new), the device fetches just that declaration (`declaration/<type>/<identifier>`). Unchanged declarations are never re-transferred.
4. **Local evaluation + atomic apply.** The device resolves activations → configurations → assets, evaluates predicates against its own status, and applies/removes configurations atomically.
5. **Status push.** The device POSTs to the **status** endpoint — proactively, on change — reporting subscribed items and the per-declaration apply results.

After the bootstrap, steps 2–5 recur on the device's own initiative (and on APNs wake), with no per-command server choreography.

### ProfileAssetReference: wrapping legacy profiles into DDM

Not every payload has a native declarative equivalent yet. The bridge is the **legacy profile configuration**, `com.apple.configuration.legacy` (and `com.apple.configuration.legacy.interactive` for ones needing user interaction), which wraps an ordinary `.mobileconfig` *inside* the DDM model so a single declarative activation can own both native configurations and old-style profiles.

Historically the legacy declaration referenced the profile by an inline/`ProfileURL` mechanism. WWDC26 introduced the **`ProfileAssetReference`** key (devices on **iOS/iPadOS/macOS/tvOS/visionOS/watchOS 27**): the legacy configuration points at an **asset declaration** (`com.apple.asset.data`) that holds the profile, which the device downloads from an arbitrary URL — decoupling *where the profile is hosted* and *how the device authenticates to fetch it* from the MDM server itself. DDM's built-in **integrity verification** (the asset carries a content hash) ensures the downloaded profile wasn't tampered with in transit.

```json
// legacy configuration that references an asset (OS 27+)
{
  "Type": "com.apple.configuration.legacy",
  "Identifier": "com.acme.config.wifi-legacy",
  "ServerToken": "v2",
  "Payload": { "ProfileAssetReference": "com.acme.asset.wifi-profile" }
}
// the asset the device downloads + integrity-checks
{
  "Type": "com.apple.asset.data",
  "Identifier": "com.acme.asset.wifi-profile",
  "ServerToken": "v1",
  "Payload": {
    "Reference": {
      "ContentType": "application/x-apple-aspen-config",
      "DataURL": "https://cdn.acme.com/profiles/wifi.mobileconfig"
      /* plus a content hash for integrity verification */
    }
  }
}
```

> ⚠️ The exact `Payload`/`Reference` key names for `com.apple.asset.data` (e.g. the hash key) shift between releases — confirm against the live `developer.apple.com/documentation/devicemanagement` declaration schema at author time before relying on a specific field name. The *mechanism* (legacy config → asset → downloaded-and-hash-verified `.mobileconfig`) is the durable part.

So even in a "fully declarative" 2026 fleet, you will still find ordinary `.mobileconfig` profiles on disk — now arriving via a `com.apple.configuration.legacy` declaration rather than a bare `InstallProfile` command. The on-disk profile store ([[configuration-profiles-and-mobileconfig]]) is still where they land.

### Migrating an imperative fleet into DDM

The transition is designed to be non-destructive. A server can take a profile it *already* pushed imperatively (an `InstallProfile`'d `.mobileconfig`) and **take ownership of it** under DDM — re-declaring it as a `com.apple.configuration.legacy` declaration that points at the same payload — without removing and reinstalling it (which would, for example, tear down and re-establish a VPN or wipe accounts). The device recognizes the migrated profile and folds it into the declarative graph. From that point the profile's lifecycle is governed by the activation/predicate model, not by imperative install/remove commands.

The practical sequence for a fleet: send the one-time `DeclarativeManagement` bootstrap command; publish management + activation + configuration declarations; migrate existing profiles into legacy configurations; then retire the imperative command paths. Because devices that don't yet support DDM (or a given declaration type) simply don't advertise it in client-capabilities, the server can run both models during the cutover and the same policy intent lands either way.

> 🔬 **Forensics note:** A device caught mid-migration is informative — you may find the *same* policy expressed twice, once as a classically-installed profile and once as a legacy declaration, with the declaration's `ServerToken`/timestamps bracketing *when* the org moved that device to DDM. That transition moment can anchor a timeline of organizational control changes (e.g., a fleet re-tooled after an acquisition or an MDM-vendor switch).

### WWDC26: devices no longer restore management state from backup

A change announced at WWDC26 and taking effect on **iOS 27 / iPadOS 27 / visionOS 27**: a device **no longer restores its device-management state from a backup**. Previously the enrollment profile, management configuration, and supervision status could ride along in a backup and be reinstated on restore. On the 27 releases that no longer happens — a restored device that was enrolled via **Automated Device Enrollment (ADE)** simply **re-runs ADE** at Setup Assistant and pulls the *current* configuration from the MDM fresh. The old escape hatch, the `do_not_use_profile_from_backup` restriction key, **has no effect on the 27 releases** (it is moot — nothing restores from backup to suppress).

The rationale is operational hygiene: restored devices used to come back carrying *stale* management state; re-running ADE guarantees the device lands on whatever policy is current.

> 🔬 **Forensics note:** This breaks an inference examiners have leaned on. On OS 27+, a device's *current* management configuration reflects its **most recent ADE enrollment after the last restore**, not its management history — you cannot read pre-restore management posture off a restored device, and a backup will not carry that posture forward either. If you need the historical management state, you need an acquisition *predating* the restore (or the backup file itself, where any pre-27 management remnants would live). Pair this with [[backup-restore-migration-and-transfer]]: the backup format and the restore behavior are now decoupled for management state specifically.

### Where DDM lives on disk

This is the forensic payoff. DDM is implemented by **`remotemanagementd`** (logging subsystem `com.apple.remotemanagementd`), which persists declarations and status to a SQLite store. On **macOS** the device-level store is confirmed at:

```
/private/var/db/rmd/secure/Database/RemoteManagement.sqlite      # device-level (system)
~/Library/Application Support/com.apple.RemoteManagementAgent/Database/RemoteManagement.sqlite   # user-level
```

On **iOS/iPadOS** the same `remotemanagementd` runs and the analogous store lives under `/private/var/db/` — but treat the **exact iOS path as a verify-on-acquisition item**: the macOS path above is confirmed from a managed Mac; the iOS location should be confirmed against a full-file-system image rather than assumed identical. ([[full-file-system-acquisition]] is the only acquisition class that reaches it — none of this is in an iTunes/Finder backup.)

The *legacy* configuration-profile state — the `.mobileconfig` payloads themselves, plus enrollment/supervision metadata — lives in the long-standing iOS profile stores (FFS-only, **not** in a backup):

```
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/
/private/var/mobile/Library/ConfigurationProfiles/
/private/var/MobileDevice/ProvisioningProfiles/      # enterprise/dev provisioning (.mobileprovision)
```

Inside the `ConfigurationProfiles` directory you find the installed profiles and management metadata plists. The one to know by name is **`CloudConfigurationDetails.plist`** — the ADE/Apple-Business-Manager "cloud configuration" (which MDM server the device was assigned to, whether enrollment is mandatory, supervision flag). Other plists there carry the *effective* restriction/settings state and MDM computer info; treat their exact filenames as verify-at-author-time (they have churned across iOS versions).

And the install/enrollment trail:

```
/private/var/installd/Library/Logs/MobileInstallation/     # profile/app install events
```

| Artifact | Path (iOS, FFS-only) | What it tells you |
|---|---|---|
| DDM store | `…/db/rmd/…/RemoteManagement.sqlite` (verify exact iOS path) | The declarations the device holds + reported status |
| Cloud config | `…/ConfigurationProfiles/CloudConfigurationDetails.plist` | ADE assignment, MDM server URL, supervision/mandatory flags |
| Profile payloads | `…/ConfigurationProfiles/` | Installed `.mobileconfig` content (restrictions, accounts, Wi-Fi, certs) |
| Provisioning | `…/MobileDevice/ProvisioningProfiles/` | Enterprise/dev `.mobileprovision` — sideloaded/in-house app trust |
| Install log | `…/installd/Library/Logs/MobileInstallation/` | When profiles/apps were installed/removed |
| Live DDM activity | unified log, subsystem `com.apple.remotemanagementd` | Sync, predicate evaluation, apply errors (in a sysdiagnose) |

A concrete investigative pass against an iOS full-file-system image, in order: (1) parse `CloudConfigurationDetails.plist` to establish *whether* the device was ADE-enrolled, which MDM server URL it was assigned to, and whether supervision was set — this is the "who owns this device" anchor; (2) enumerate the `ConfigurationProfiles` payloads to read the *enforced* restrictions and accounts; (3) open `RemoteManagement.sqlite` (copy-first) to read the declaration graph — the activation predicates reveal the *conditions* under which policy applies, and the recovered status reveals what the device admitted to its server; (4) pull `remotemanagementd` log lines from any available sysdiagnose to timeline sync events, predicate flips, and apply failures; (5) cross-check the install log for *when* profiles arrived. Each layer corroborates the next, and contradictions (a restriction in a profile that the status reports as non-compliant, say) are leads.

> 🔬 **Forensics note:** Together these answer "how was this device managed, by whom, since when, and what did it admit to?" — `CloudConfigurationDetails.plist` names the MDM and supervision state; the `ConfigurationProfiles` payloads spell out the *enforced* restrictions (which can corroborate or contradict a custodian's account of device limits); the `RemoteManagement.sqlite` declarations are the desired-state graph; and the reported status is the device's own self-assessment. See [[unified-logs-sysdiagnose-crash-network]] — a sysdiagnose captures `remotemanagementd` activity (sync timing, predicate flips, apply failures) even when you only have logical/sysdiagnose-level access rather than a full image.

> ⚖️ **Authorization:** Management artifacts frequently belong to an *employer*, not the device's user — an ADE-enrolled, supervised corporate device's configuration profiles, MDM identity, and status history are organizational records. Confirm your authority covers the *managing organization's* data, not just the handset, before extracting or reporting it; supervision/enrollment state often determines who has standing to consent.

## Hands-on

There is no on-device shell on iOS, and the Simulator has no MDM/DDM stack, so the device-side store is read from acquired images. But DDM declarations are *just JSON*, and the protocol is observable on a managed **Mac** — so most of the hands-on is Mac-side authoring, validation, and (on macOS) live introspection.

**Author and validate a declaration set (pure JSON, any Mac):**

```bash
cd /private/tmp
cat > passcode.json <<'JSON'
{ "Type":"com.apple.configuration.passcode.settings",
  "Identifier":"com.acme.config.passcode","ServerToken":"v1",
  "Payload":{ "RequirePasscode":true,"MinimumLength":6 } }
JSON
# Validate it's well-formed JSON and pull the three required keys
jq -e '.Type and .Identifier and .ServerToken' passcode.json   # -> true (exit 0) if all present
jq '{Type, Identifier, ServerToken}' passcode.json
```

**Watch DDM on a managed Mac (the iOS analogue you can actually run):**

```bash
# Live DDM daemon activity — sync, predicate evaluation, apply results
log show --predicate 'subsystem == "com.apple.remotemanagementd"' --info --last 1h
# Or stream it while you trigger a sync:
log stream --predicate 'process == "remotemanagementd"' --info
```

**Inspect the macOS DDM store (copy-before-query — SQLite write-locks even on SELECT):**

```bash
sudo cp /private/var/db/rmd/secure/Database/RemoteManagement.sqlite /private/tmp/rm.sqlite
sqlite3 /private/tmp/rm.sqlite '.tables'         # enumerate the schema first
# Then SELECT from the declaration/status tables you find (schema varies by OS build).
```

**Native macOS introspection (no DB needed):**

```bash
profiles status -type enrollment      # is this Mac enrolled? supervised? user-approved?
sudo profiles list                    # installed configuration profiles
profiles show -type configuration     # payload detail
```

**Decode a `.mobileconfig` (the legacy payloads DDM wraps), on Mac:**

```bash
plutil -p /private/tmp/some.mobileconfig          # human-readable plist dump
# Recovered from an iOS image's ConfigurationProfiles dir, same command applies.
```

**From an iOS full-file-system image — read the cloud config and profiles:**

```bash
# (image already mounted/extracted; paths relative to the FFS root)
plutil -p './private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/CloudConfigurationDetails.plist'
ls -la  './private/var/MobileDevice/ProvisioningProfiles/'
```

## 🧪 Labs

> Every lab here is **device-free**. DDM's transport needs a real enrolled device, which you don't have — so the labs exercise the *parseable substrate*: hand-authored JSON declarations, a managed **Mac** as the cross-platform stand-in for `remotemanagementd`, and a public iOS sample image for the device-only profile stores. **Fidelity caveat:** the **Simulator is useless for this lesson** — it runs macOS frameworks with no MDM/DDM stack, so `remotemanagementd`, `RemoteManagement.sqlite`, and the `ConfigurationProfiles` stores do not exist or do not populate there. Where a real iPhone's DDM store is required, the lab uses a sample image or a read-only walkthrough.

### Lab 1 — Build a four-type declaration graph by hand (substrate: pure JSON on the Mac)

Model a real policy with all four declaration classes and prove the dependency graph is internally consistent. No device touched.

1. Write declaration files spanning all four classes: a **configuration** (`com.apple.configuration.passcode.settings`), an **asset** (`com.apple.asset.data`, referenced by a *second*, legacy configuration `com.apple.configuration.legacy`), a status-subscriptions **configuration** (`com.apple.configuration.management.status-subscriptions` subscribing to `passcode.is-present` and `passcode.is-compliant` — remember status subscriptions are a *configuration*, not a management declaration), a **management** declaration (`com.apple.management.organization-info`), and an **activation** (`com.apple.activation.simple`) whose `StandardConfigurations` lists the configuration Identifiers and whose `Predicate` tests `@status(device.operating-system.version) >= '26.0'`.
2. Validate each is well-formed and has all three required keys: `for f in *.json; do jq -e '.Type and .Identifier and .ServerToken' "$f" || echo "MISSING KEYS: $f"; done`.
3. Write a one-liner that checks **referential integrity**: every Identifier listed in the activation's `StandardConfigurations` must exist as the `Identifier` of one of your configuration files. (Collect activation references with `jq`, collect configuration Identifiers, diff.)
4. Bump the configuration's `ServerToken` and articulate what the device would do on next token sync (re-fetch *only* that declaration; re-evaluate the activation; re-apply atomically).

**Fidelity caveat:** you are modeling the protocol's data plane, not enrolling a device — there is no predicate *evaluation* here (no live status), only structural validation.

### Lab 2 — Observe `remotemanagementd` on a managed Mac (substrate: macOS, the cross-platform analogue)

The same daemon and store shape run on macOS; this is the closest you get to seeing DDM execute without an iPhone.

1. If you have a managed/enrolled Mac available, run `profiles status -type enrollment` and note enrollment + supervision state. (On an unenrolled personal Mac you'll see "not enrolled" — that's the expected read-only-walkthrough outcome; reason about what each field *would* say.)
2. `log show --predicate 'subsystem == "com.apple.remotemanagementd"' --info --last 1d` — read the sync lifecycle: token request, declaration fetch, predicate evaluation, apply results. Identify one line showing a status report.
3. If enrolled: copy `RemoteManagement.sqlite` (copy-first!) and `.tables` it; map the tables you see onto the four declaration types + status.

**Fidelity caveat:** macOS is the *same* protocol but a different platform — passcode/Data-Protection semantics differ, and a personal Mac is likely unenrolled, making steps 1–2 a read-only walkthrough rather than live capture.

### Lab 3 — Recover management posture from an iOS sample image (substrate: public sample FFS image)

Use a public full-file-system reference image (Josh Hickman / Digital Corpora) to read the device-only stores the Simulator can't produce.

1. Locate `…/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/` in the image. `ls` it and note which plists are present.
2. `plutil -p CloudConfigurationDetails.plist` — extract the MDM server reference and supervision/ADE flags (or confirm the device was *unmanaged*, which is itself a finding).
3. `plutil -p` any installed `.mobileconfig`/profile payload and enumerate the restrictions it enforces.
4. Check `…/MobileDevice/ProvisioningProfiles/` for any `.mobileprovision` — their presence indicates sideloaded/in-house/enterprise-signed apps; cross-reference with [[the-app-bundle-and-ipa-structure]].

**Fidelity caveat:** most public reference images are of *unmanaged* devices, so expect the artifact to document the *absence* of management. The skill — knowing the paths and parsing them — is the deliverable; a managed sample image makes it richer.

### Lab 4 — Explore declarations with a real DDM tool (substrate: read-only walkthrough / Mac app)

1. Skim Apple's **WWDC21 "Meet declarative device management"** and **WWDC22 "Adopt declarative device management"** sessions for the canonical declaration/status JSON examples.
2. Look at **Jamf's open-source `ddm-explorer`** (github.com/Jamf-Concepts/ddm-explorer) to see how a real management tool composes activations/configurations/assets and reads status.
3. Map each example back to your Lab 1 files: identify the bootstrap `DeclarativeManagement` command, the tokens manifest, and a status report in the documented flow.

## Pitfalls & gotchas

- **"DDM replaced MDM" is wrong; DDM rides *on* MDM.** There is no separate enrollment, identity, or APNs path — the device must still be MDM-enrolled, and the bootstrap is an imperative `DeclarativeManagement` *command*. Don't expect to find DDM on a device with no MDM enrollment record.
- **None of this is in a backup.** The DDM store, `ConfigurationProfiles`, and provisioning profiles are **full-file-system-only**. A logical/iTunes-Finder backup ([[the-itunes-finder-backup-format]]) will not contain the management posture — reaching for it requires [[full-file-system-acquisition]].
- **The OS-version split is real and load-bearing.** Imperative *software-update* commands/queries/restrictions are **removed in 27.0** — tooling that still issues them silently does nothing on a 27 device. The Intelligence/Siri/keyboard controls moved from MDM restrictions to declarative configurations (`com.apple.configuration.intelligence.settings`, `…siri.settings`, `…keyboard.settings`) starting **26.4**. Pin your version claims; 26.5 is current shipping, the 27 changes were announced at WWDC26 and ship in that cycle.
- **Restore no longer carries management forward (27+).** Don't infer a device's management history from its current state if it has been restored — it re-ran ADE and pulled *current* policy. `do_not_use_profile_from_backup` is inert on 27.
- **`ServerToken` ≠ a timestamp.** It's an opaque revision marker. You can order revisions by it only if the server uses an ordered scheme (many do, e.g. `v3`/dates); never *assume* it encodes time.
- **Copy-before-query the SQLite store.** `RemoteManagement.sqlite` is live SQLite — even a `SELECT` takes a write lock and can spawn `-wal`/`-shm` sidecars. Always `cp` first (the same discipline as every other artifact store in this course).
- **The Simulator will mislead you here.** It has *no* DDM/MDM substrate; an empty result in the Simulator is not evidence a real device lacks management — it's just the wrong substrate.
- **Exact iOS paths/keys drift.** The confirmed `RemoteManagement.sqlite` path is from macOS; specific `ConfigurationProfiles` plist filenames and `com.apple.asset.data` payload keys have churned across releases — verify against the live image/schema rather than hard-coding from memory.

## Key takeaways

- DDM **inverts** the model: the device, not the server, holds desired state, evaluates predicates, enforces continuously, and *reports its own status proactively* — scaling better and surviving missed pokes.
- There are exactly **four declaration types** — configurations (policy, inert alone), activations (the predicate-gated switch that applies configs atomically), assets (referenced bulk/credential data), and management (org info + server capabilities + properties). A subtlety worth pinning: the device's **status subscriptions** are themselves a *configuration* (`com.apple.configuration.management.status-subscriptions`), not a management declaration.
- Every declaration carries `Type`, `Identifier`, `ServerToken` (the revision marker) + a `Payload`; declarations reference each other by `Identifier`.
- The **status channel** is the forensic prize: it's the device's own, self-authored, point-in-time assessment of itself, sent to the MDM — and the same status items feed activation predicates.
- **`ProfileAssetReference`** (OS 27) wraps legacy `.mobileconfig` profiles into the DDM model as downloadable, hash-verified assets, so "fully declarative" fleets still produce on-disk profiles.
- **WWDC26 / OS 27:** devices **no longer restore management state from backup** — they **re-run ADE** after a restore — so a restored device's management config is *current*, not historical, and won't carry forward in a backup.
- On disk, `remotemanagementd` persists to **`RemoteManagement.sqlite`**; `CloudConfigurationDetails.plist` and the `ConfigurationProfiles`/`ProvisioningProfiles` stores spell out enrollment, supervision, and enforced restrictions — all **FFS-only**, none in a backup.
- DDM is **cross-platform** — the identical model and daemon manage a 2026 Mac, so this lesson doubles as fleet-Mac knowledge.

## Terms introduced

| Term | Definition |
|---|---|
| Declarative Device Management (DDM) | Apple's 2026-standard management model where the device holds JSON declarations, autonomously enforces desired state, and proactively reports status — replacing imperative command/poll MDM. |
| Declaration | A JSON management object with required `Type`, `Identifier`, `ServerToken` keys + a `Payload`; one of four classes. |
| Configuration | Declaration class (`com.apple.configuration.*`) holding a policy (passcode, restrictions, accounts, legacy profile); inert until an activation references it. |
| Activation | Declaration class (`com.apple.activation.*`) that references configurations and carries a predicate; applies its configs atomically when the predicate is true. |
| Asset | Declaration class (`com.apple.asset.*`) holding ancillary/bulk data (credentials, certs, a profile blob) referenced by configurations, one-to-many. |
| Management declaration | Declaration class (`com.apple.management.*`) conveying organization info, server capabilities, and server-defined properties to the device. (Status subscriptions are *not* a management declaration — they are a configuration, `com.apple.configuration.management.status-subscriptions`.) |
| Status channel | The device-to-server path on which the device proactively reports subscribed status items and per-declaration apply results. |
| Status item | A namespaced device-state value (`device.*`, `passcode.*`, `management.*`…) the server can subscribe to and a predicate can test via `@status(...)`. |
| `ServerToken` | Opaque per-declaration revision marker; the device re-fetches a declaration only when its `ServerToken` changes. |
| Predicate | An `NSPredicate`-style expression over status items that the device evaluates locally to decide whether an activation applies. |
| `ProfileAssetReference` | OS 27 key letting a legacy configuration reference a downloadable, hash-verified `.mobileconfig` asset instead of inlining it. |
| `com.apple.configuration.legacy` | Declaration type that wraps a classic `.mobileconfig` profile into the DDM model. |
| `remotemanagementd` | The daemon implementing DDM on iOS/macOS; logs under subsystem `com.apple.remotemanagementd`. |
| `RemoteManagement.sqlite` | The on-disk SQLite store of DDM declarations and status (macOS: `/private/var/db/rmd/secure/Database/`). |
| `CloudConfigurationDetails.plist` | iOS plist recording ADE/ABM cloud configuration — assigned MDM server, supervision and mandatory-enrollment flags. |
| `DeclarativeManagement` command | The single imperative MDM check-in command that bootstraps a device into declarative management. |

## Further reading

- Apple Platform Deployment Guide — "Intro to declarative device management" and "Use declarative device management to manage Apple devices" (support.apple.com/guide/deployment).
- Apple Platform Deployment Guide — "WWDC26 device management updates" and "Legacy profile declarative configuration" (the `ProfileAssetReference` + backup/restore changes).
- developer.apple.com/documentation/devicemanagement — `Declarations`, `DeclarativeManagementRequest`, declaration and status-item schemas (the authoritative, versioned key reference).
- WWDC21 "Meet declarative device management" (Session 10131) and WWDC22 "Adopt declarative device management" (Session 10046); WWDC26 "What's new in managing Apple devices" (Session 206).
- Der Flounder — "Reading DDM logging on macOS Sequoia" (the `remotemanagementd` subsystem + `RemoteManagement.sqlite` path).
- Omnissa Tech Zone — "A primer on Declarative Device Management for Apple devices" (declarations / status / predicates / extensibility overview).
- Jamf — `github.com/Jamf-Concepts/ddm-explorer` (a tool for exploring real declaration/status flows); Jamf and Fleet WWDC26 admin write-ups.
- iOS forensics references — the iOS `ConfigurationProfiles` / `ProvisioningProfiles` artifact paths (community cheat sheets; verify on a current FFS image); DarthNull.org "Inside Apple's MDM Black Box" for the enrollment/check-in plumbing DDM rides on.
- `man profiles`, `man log`, `man plutil`, `man sqlite3` — exact flag semantics on the target OS version.

---
*Related lessons: [[mdm-supervision-and-abm]] | [[configuration-profiles-and-mobileconfig]] | [[backup-restore-migration-and-transfer]] | [[lockdown-mode-and-enterprise-posture]] | [[full-file-system-acquisition]] | [[unified-logs-sysdiagnose-crash-network]]*
