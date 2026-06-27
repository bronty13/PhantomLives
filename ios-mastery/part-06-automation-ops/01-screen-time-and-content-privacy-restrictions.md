---
title: "Screen Time & Content/Privacy restrictions"
part: "06 — Automation & Operations"
lesson: 01
est_time: "40 min read + 15 min labs"
prerequisites: [knowledgec-db-deep-dive]
tags: [ios, operations, screen-time, restrictions, parental-controls, forensics]
last_reviewed: 2026-06-26
---

# Screen Time & Content/Privacy restrictions

> **In one sentence:** Screen Time is Apple's user-facing skin over the same CoreDuet "pattern-of-life" pipeline that feeds `knowledgeC`/Biome — it aggregates per-app and per-category usage into a Core Data store (`RMAdminStore`), enforces app/website limits and Downtime through OS-level shields, gates a long list of capabilities via Content & Privacy Restrictions, and guards all of it behind a **second, distinct credential** — the Screen-Time passcode — whose forensic and abuse implications are entirely separate from the device passcode.

## Why this matters

For the forensicator, Screen Time is a triple gift: it is a **redundant, pre-aggregated pattern-of-life source** (someone has already done the per-app/per-day rollup you would otherwise compute by hand from `knowledgeC`), it **records the enforcement posture** (which restrictions, limits, and Downtime windows were in force, and on whose authority), and it surfaces a **second secret** — the Screen-Time passcode — that is frequently set to something the suspect will hand over when they refuse the device passcode, and that is itself an instrument in coercive-control and stalkerware fact patterns. For the builder, the Screen Time API triad (`FamilyControls` / `ManagedSettings` / `DeviceActivity`) is the only sanctioned way an app reaches into another app's launchability, and it ships with hard sandbox and entitlement walls worth understanding before you design around them. Either way, "Screen Time" is a UI label over real daemons writing real SQLite — and that is what this lesson dissects.

## Concepts

### The Screen Time stack: frameworks, daemons, and two stores

"Screen Time" is not one process. It is a layered system that spans a developer-facing framework triad, a set of system daemons, the CoreDuet behavioral substrate you already know from [[01-knowledgec-db-deep-dive]], and a dedicated aggregation/enforcement store. Map the pieces before chasing artifacts:

| Layer | Component | Role |
|---|---|---|
| App-facing API | `FamilyControls.framework` | Authorization gate — an app requests permission to manage activity (`AuthorizationCenter`); returns opaque `ApplicationToken`/`WebDomainToken` so a third party never learns *which* apps are managed. |
| App-facing API | `ManagedSettings.framework` | The enforcer — a `ManagedSettingsStore` applies *shields* (block app launch / block Safari domains), restriction toggles, and lockout state at the OS level. |
| App-facing API | `DeviceActivity.framework` | The scheduler — defines time windows (`DeviceActivitySchedule`) and usage thresholds that fire `DeviceActivityMonitor` extension callbacks; this is how Downtime and per-app limits know *when*. |
| App-facing UI | `ManagedSettingsUI.framework` | Renders the shield screen the user hits when a limited app is launched. |
| Daemon | `ScreenTimeAgent` (`com.apple.ScreenTimeAgent`) | The user-side brain; uses `ScreenTimeCore.framework`; owns the Screen-Time passcode check, the family/account state, and reporting UI data. |
| Daemon | `remotemanagementd` (`com.apple.remotemanagementd`) | Owns the **`RMAdminStore`** databases — both the usage aggregation and the restriction/limit configuration. |
| Daemon | `knowledged` + `dasd` (DuetActivityScheduler) | The CoreDuet substrate: records foreground-app intervals etc. into `knowledgeC`/Biome, which Screen Time consumes upstream. |

The data flow is unidirectional from raw signal to user-facing rollup:

```
 app foreground / lock / web visit
        │  (CoreDuet ingest)
        ▼
 knowledged → knowledgeC.db / Biome SEGB        ← the raw "pattern of life" substrate
        │      (/app/inFocus, /app/usage, …)        (see knowledgec-db-deep-dive)
        ▼
 ScreenTimeAgent  ──aggregates per app + per category, per device, per day──┐
        │                                                                    │
        ▼                                                                    ▼
 remotemanagementd → RMAdminStore-Local.sqlite          RMAdminStore-Cloud.sqlite
        │              (this device's usage + limits)     (Family Sharing fan-out:
        ▼                                                   other devices on the account)
 ManagedSettings shields  ◄── enforcement (Downtime, app limits, web filter)
```

The crucial mental model: **`knowledgeC`/Biome is the per-event substrate; `RMAdminStore` is the pre-aggregated Screen-Time rollup.** They corroborate each other, with different granularity and different retention. `knowledgeC` gives you sub-second foreground intervals over a rolling ~4-week window; `RMAdminStore` gives you per-app/per-category daily totals (and the *configured* limits/restrictions) that can reach back further and sync across the family.

Keep the three stores straight — they answer different questions with different reach:

| Property | `knowledgeC.db` / Biome | `RMAdminStore-Local` | `RMAdminStore-Cloud` |
|---|---|---|---|
| Granularity | per-event intervals (sub-second) | per-app/per-category daily totals | same, fanned out per family device |
| Reach | this device | this device | the whole Family Sharing group |
| Retention | rolling ~4 weeks | longer (aggregated) | longer (server-backed) |
| Holds config? | no (pure telemetry) | yes — limits/restrictions | yes |
| Acquisition | FFS only | FFS only | FFS **or** cloud (ADP breaks cloud) |
| Owner daemon | `knowledged`/`dasd` | `remotemanagementd` | `remotemanagementd` |

Concretely, the `knowledgeC` streams Screen Time draws from are the ones you catalogued in [[01-knowledgec-db-deep-dive]] — chiefly `/app/inFocus` (foreground app + bundle ID, start/end), `/app/usage` (broader usage intervals including background), `/app/webUsage` and `/safari/history` (per-domain time for the web report), `/device/isBacklit` / `/display/isBacklit` and `/device/locked` (screen-on / lock transitions that bound a "pickup"), and `/app/install`. Screen Time's "pickups," "first used after pickup," and "notifications received" tiles are computed from exactly these streams plus the counted-usage stream. That is why the two stores must agree: `RMAdminStore` is *derived from* the same rows you can re-sum out of `knowledgeC`. A divergence between them is itself a finding — it can indicate a clock change, a partial wipe, or tampering with one store but not the other.

> 🖥️ **macOS contrast:** You met Screen Time on macOS (10.15+), shared via Family Sharing — same feature, same frameworks. On the Mac the stores live at `~/Library/Application Support/Knowledge/knowledgeC.db` and `~/Library/Application Support/com.apple.remotemanagementd/RMAdminStore-Local.sqlite`, with the agent container at `~/Library/Containers/com.apple.ScreenTimeAgent/Data/`. On iOS the *same* `RMAdminStore` schema lives under `/private/var/mobile/Library/Application Support/com.apple.remotemanagementd/`. The difference is **surface and centrality**: on iOS, Screen Time is the primary parental-controls UI and the CoreDuet feed underneath it is far richer (the phone is always-on and always-carried), so the iOS rollup is the higher-value pattern-of-life artifact. Yogesh Khatri's `mac_apt` ships a `screentime.py` (`SCREENTIME`) plugin that parses `RMAdminStore-Local`/`-Cloud` on both macOS and iOS images; the schemas are close cousins.

### The usage pipeline: RMAdminStore on disk

`RMAdminStore-Local.sqlite` is a Core Data SQLite store (note the `Z`-prefixed class tables and the `Z_PRIMARYKEY`/`Z_METADATA` Core Data bookkeeping). The Screen-Time usage rollup lives across an interlocking set of entity tables. Names confirmed across Cellebrite/Magnet write-ups and the `mac_apt` plugin:

| Table | What it holds |
|---|---|
| `ZUSAGEBLOCK` | The time-block spine — start/end of a usage window with the date/time fields you build the timeline from. |
| `ZUSAGECATEGORY` | The category bucket for a block (Social, Productivity, Entertainment, …) — the rollup the Screen Time report shows as a pie wedge. |
| `ZUSAGETIMEDITEM` | The per-app/per-domain leaf — bundle identifier / web domain and the seconds attributed to it inside a block. |
| `ZUSAGECOUNTEDITEM` | Counted (not timed) usage — pickups, notifications received, etc. |
| `ZUSAGE` | The parent usage record tying blocks to a device + user. |
| `ZCOREDEVICE` | The device a block belongs to (model, name) — *which* of the family's devices produced the usage. |
| `ZCOREUSER` | The account/family member the usage is attributed to. |

The relationships let you answer "**which family member, on which device, used which app, in which category, for how long, starting when**" — the full provenance of a usage block — in one join.

> ⚠️ **Exact column names drift by iOS version.** Do not write a query from memory. `RMAdminStore` is Core Data, so column names are generated (`ZSTARTDATE`, `ZBLOCKTYPE`, a bundle-ID string column on `ZUSAGETIMEDITEM`, a seconds/duration column on the leaf) and Apple has reshuffled them across releases. **Always `.schema ZUSAGEBLOCK` / `.schema ZUSAGETIMEDITEM` on the actual store first**, then build the SELECT against what you see. Treat the column names in the sample query below as a template to verify, not gospel.

The timestamps are **Apple/Cocoa Core Data time** — seconds since `2001-01-01 00:00:00 UTC` (the Mac Absolute Time epoch). Add `978307200` to convert to Unix epoch, exactly as in [[01-knowledgec-db-deep-dive]] and the macOS forensic-artifacts work. A representative rollup query (after you've confirmed the schema):

```sql
SELECT
  cu.ZNAME                                          AS family_member,
  cd.ZNAME                                          AS device,
  cat.ZIDENTIFIER                                   AS category,
  item.ZBUNDLEIDENTIFIER                            AS app_or_domain,
  datetime(blk.ZSTARTDATE + 978307200,'unixepoch')  AS block_start_utc,
  datetime(blk.ZENDDATE   + 978307200,'unixepoch')  AS block_end_utc,
  item.ZTOTALTIME                                   AS seconds_used
FROM ZUSAGETIMEDITEM item
  JOIN ZUSAGECATEGORY cat ON item.ZCATEGORY = cat.Z_PK
  JOIN ZUSAGEBLOCK    blk ON cat.ZBLOCK     = blk.Z_PK
  JOIN ZUSAGE         u   ON blk.ZUSAGE     = u.Z_PK
  JOIN ZCOREDEVICE    cd  ON u.ZDEVICE      = cd.Z_PK
  JOIN ZCOREUSER      cu  ON u.ZCOREUSER    = cu.Z_PK
ORDER BY blk.ZSTARTDATE DESC
LIMIT 100;
```

> 🔬 **Forensics note — read the `-wal`.** `RMAdminStore-Local.sqlite` is a WAL-mode database; the most recent usage and limit changes frequently live in `RMAdminStore-Local.sqlite-wal`, **not yet checkpointed into the main file**. A tool (or analyst) that copies only the `.sqlite` and ignores the sibling `-wal`/`-shm` silently drops the freshest hours of activity — exactly the window you usually care about. Acquire all three files together, and when querying with `sqlite3`, let it checkpoint a *copy* (never the original) so the WAL is merged: `cp` the trio, then open the copy. This is the standard copy-before-query discipline, with the WAL twist that matters here specifically.

> 🔬 **Forensics note — acquisition tier.** `RMAdminStore` is **not in an iTunes/Finder backup** and not reachable by logical acquisition. It requires a **full-file-system extraction** (`checkm8`/`usbliter8`-class BootROM exploit on A8–A13, an agent-based FFS on supported devices, or a GrayKey/Cellebrite image). See [[05-full-file-system-acquisition]] and [[01-the-acquisition-taxonomy]] — the same boundary that governs `knowledgeC` and the rest of the device-only pattern-of-life corpus.

> 🔬 **Forensics note — the cloud copy is a second path.** Because Screen Time syncs across a Family Sharing group, the rollup also exists server-side, and `RMAdminStore-Cloud.sqlite` is its on-device reflection. That opens a **cloud-acquisition** route to Screen-Time usage independent of the locked handset — with the same authenticated-iCloud caveats as any cloud pull, and the hard wall that **Advanced Data Protection (ADP) end-to-end-encrypts the relevant containers and breaks cloud acquisition**. So on a target with ADP enabled, neither the local store (no FFS) nor the cloud store (E2EE) is reachable — the usage data is, practically, unrecoverable. See [[06-icloud-acquisition-and-advanced-data-protection]].

### App/Website limits & Downtime — the enforcement mechanism

Limits, Downtime, and Always-Allowed are **scheduled shields**, not hooks inside each app. When a limit fires, `ManagedSettings` writes a shield into the active `ManagedSettingsStore`, and the OS — not the target app — refuses to bring the app to foreground, painting the `ManagedSettingsUI` shield screen instead. Because enforcement is at the OS/launch-services layer, the user cannot defeat it by force-quitting, rebooting, or switching apps; only the Screen-Time passcode (or an authorized parent approval) lifts it.

Three implementation facts worth carrying:

- **The shield is configuration, not telemetry.** Finding an active shield/limit tells you a control *was configured*, not that the app was *blocked at a given second*. The "you reached your limit" moment is reconstructed by correlating the configured `DeviceActivitySchedule`/threshold against the `knowledgeC` `/app/usage` and `/app/inFocus` intervals.
- **Cross-process state lives in App Groups.** The main Screen Time process, the `DeviceActivityMonitor` extension, and the shield extension run as **separate processes** and cannot share a Core Data store — they coordinate through `UserDefaults` in a shared App Group container. Third-party Screen-Time apps follow the same pattern, so their managed state hides in `Library/Group Containers/<group>/` rather than the app's own sandbox.
- **Downtime is a `DeviceActivitySchedule` window.** Its configured start/end times are stored in `RMAdminStore`; whether the user was actually *in* Downtime at time T is, again, a correlation against the usage substrate.

> 🔬 **Forensics note — reconstructing "limit reached."** There is no single row that says "the shield blocked Instagram at 21:14." You build it: take the configured per-app limit and Downtime window from `RMAdminStore`, then walk the `knowledgeC` `/app/usage` intervals for that bundle ID across the day until the cumulative time crosses the threshold — that crossing is the modelled block moment, and a *subsequent* `/app/inFocus` interval for the same app implies the passcode was used to grant "more time" or "ignore limit." The unified log (`ManagedSettings`/`ScreenTimeAgent` subsystems) sometimes records the shield-applied event directly; check there to corroborate the modelled moment with a logged one.

### Content & Privacy Restrictions — what they gate

Content & Privacy Restrictions is the iOS descendant of the old "Restrictions" pane. It is a broad policy surface; the categories it gates:

| Category | Examples of what it blocks/forces |
|---|---|
| iTunes & App Store purchases | Installing apps, deleting apps, in-app purchases, requiring password every time |
| Allowed apps | Hiding/disabling built-ins (Safari, Camera, FaceTime, Mail, Wallet, AirDrop, …) |
| Content ratings | Region rating ceiling for music/podcasts/movies/TV/books/apps; explicit-content block |
| **Web content** | `Limit Adult Websites` (on-device heuristic filter + allow/deny URL lists) or `Allowed Websites Only` (whitelist) |
| **Communication Limits** | Who the child may communicate with (during the day / during Downtime), driven by contacts |
| **Communication Safety** | On-device ML that blurs/intervenes on nudity in Messages, FaceTime, AirDrop, Contact Posters, and the Photos picker — **on-device, never uploaded** (the WWDC 2026 / iOS 27 preview widens it to violent/gore imagery; see the dated baseline) |
| Privacy | Locking TCC grants (Location, Contacts, Photos, Mic, Camera, Tracking) so apps can't change them |
| Allow changes | Freezing account, passcode, cellular, background activity, and other settings |

Two distribution paths set these, and they land in different stores:

- **Screen Time / Family Sharing** restrictions are persisted into `RMAdminStore` alongside the usage rollup (they are part of the managed *configuration*, which is why `remotemanagementd` owns both).
- **MDM / configuration-profile** restrictions (the enterprise/supervision path) land under the ManagedConfiguration machinery — `/private/var/mobile/Library/ConfigurationProfiles/` and `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/` — as installed profile payloads. A `com.apple.applicationaccess` restrictions payload here is the device's *enforced policy*, independent of (and stronger than) a family Screen-Time toggle. See [[04-configuration-profiles-and-mobileconfig]] and [[02-mdm-supervision-and-abm]].

A `com.apple.applicationaccess` payload is plain XML once you `plutil -convert xml1` it; the keys *are* the policy, and each one is a fact about the device's posture and who imposed it:

```xml
<dict>
  <key>PayloadType</key>            <string>com.apple.applicationaccess</string>
  <key>allowSafari</key>            <false/>   <!-- Safari hidden/disabled -->
  <key>allowCamera</key>           <false/>   <!-- Camera disabled — note for any camera-evidence claim -->
  <key>allowAppInstallation</key>   <false/>   <!-- can't install apps -->
  <key>allowAppRemoval</key>        <false/>   <!-- can't delete apps (anti-anti-forensic) -->
  <key>forceWiFiPowerOn</key>       <true/>
  <key>allowEraseContentAndSettings</key> <false/>   <!-- remote-wipe / factory-reset blocked -->
  <key>ratingRegion</key>           <string>us</string>
  <key>ratingApps</key>             <integer>600</integer>   <!-- app age-rating ceiling: 600=17+, 300=12+, 1000=allow all -->
</dict>
```

> 🔬 **Forensics note:** That `allowEraseContentAndSettings` / `allowAppRemoval` pair is doubly interesting — a supervision policy that *prevents wipe and app deletion* is exactly the posture you want before acquisition (the suspect couldn't trivially nuke evidence), and a device showing camera/Safari disabled by policy changes what other artifacts you should and shouldn't expect to find. Always read the enforced restriction payload early; it tells you the shape of the rest of the image.

> 🔬 **Forensics note — Communication Safety leaves (almost) no artifact.** A common examiner misconception is that Communication Safety keeps a log of what it blurred. It does not. The nudity classification (and the violent/gore classification arriving in the iOS 27 preview) runs **on-device, in real time, and is ephemeral** — Apple never receives the image and the system does not persist a record of "image X was flagged at time T." Do not expect a "blocked content" database; its absence is by design, not by deletion. Any persistent trace lives in the *underlying* app (the Messages `chat.db` row for the message that was sent/received, the Photos asset, etc.), not in a Communication-Safety store. Treat "was it flagged?" as generally unanswerable from artifacts and reason from the underlying content instead.

> 🔬 **Forensics note — legacy Restrictions passcode artifact.** On iOS 7–11 the parental-controls passcode (then called "Restrictions") was a salted **PBKDF2-HMAC-SHA1** hash stored in `/private/var/mobile/Library/Preferences/com.apple.restrictionspassword.plist` (the `Key` + `Salt` fields). In an iTunes backup this is the file hashed to `398bc9c2aeeab4cb0c12ada0f52eea12cf14f40b`. Because the 4-digit space is only 10,000 candidates, this hash is trivially brute-forced offline — that is exactly what **`pinfinder`** does. If you are working an older device or an old backup, this artifact alone can recover the control passcode in seconds.

> ⚖️ **Authorization:** A web-content allow/deny list, a Communication-Limits contact set, or a Content-rating ceiling is **evidence of who was controlling whom**. In a coercive-control or stalkerware matter, the *configured restriction policy* (and the account that set it) can be as probative as the usage data. Treat the restriction config as substantive evidence, document the controlling Apple Account, and stay inside the authority that names the device and the account holder.

### Family Sharing parental controls and the separate Screen-Time passcode

Modern parental controls are an **account** construct, not just a per-device toggle. A **Child Account** in a Family Sharing group carries an age band; the organizer manages the child's Screen Time remotely, and the child's usage/limits fan out through `RMAdminStore-Cloud.sqlite`. The control credential is the **Screen-Time passcode** — and it is *not* the device passcode:

- It is a **distinct secret**, separately set, that gates changing Screen Time settings, lifting limits, and (optionally) is required after a device-passcode reset.
- **Storage evolution (verify the exact keychain item against your build):**
  - *iOS 7–11:* salted PBKDF2-HMAC-SHA1 hash in `com.apple.restrictionspassword.plist` (above) — recoverable.
  - *iOS 12:* moved into the **device keychain**; because it rode along in the encrypted-backup keychain, it was recoverable from a password-protected local backup (the Elcomsoft/Decipher workflow).
  - *iOS 13 and later:* **no longer present in backups at all** — held in a device-only keychain item, not synced and not exported to the backup keychain. Recovery from a backup is impossible; the user-facing path is **Screen-Time Passcode Recovery via the Apple Account**.
- Forensically this means: on a current device, the Screen-Time passcode is recoverable **only** from a full-file-system image (where the keychain item is present) or by the Apple-Account reset path — never from a logical backup.

> 🔬 **Forensics note — the passcode is a second credential, and that cuts both ways.** A suspect who refuses the device passcode may volunteer the Screen-Time passcode (they perceive it as "just the parental thing"). Conversely, the *existence* of a Screen-Time passcode set on an adult's own primary device — with no children in the family group — is a small but real signal worth noting; it is sometimes set by a controlling partner to lock another adult out of changing settings, or by a user trying to add a second factor over local backups (a known trick: a Screen-Time passcode can be required to *change the local-backup password*, frustrating "just re-pair and back it up" acquisition plans). Record whether one is set and who holds it.

> 🖥️ **macOS contrast:** On the Mac the Screen-Time passcode is likewise distinct from the login password and the FileVault password — three independent secrets. The same Family-Sharing organizer manages it across the user's Mac, iPhone, and iPad together, and the same `RMAdminStore-Cloud` fan-out applies. The iOS device is simply the richer data producer in that shared graph.

The Family-Sharing control graph is worth drawing, because each edge is an evidentiary relationship — who could see, and who could set, what:

```
        ┌─────────────────────────────┐
        │   Family Organizer (adult)  │  sets limits/restrictions, holds reset authority
        │   Apple Account A           │  sees each child's usage report (Cloud fan-out)
        └──────────────┬──────────────┘
                       │ Screen-Time passcode + Family Sharing
        ┌──────────────┼───────────────────────────┐
        ▼              ▼                             ▼
   Child Acct B   Child Acct C                 Organizer's own devices
   (age band)     (age band)                   (iPhone / iPad / Mac)
   iPhone+iPad    iPhone                        │
        │              │                        │
        ▼              ▼                        ▼
   RMAdminStore-Local  per device  ───►  RMAdminStore-Cloud  ───►  visible to Organizer
```

A child's `RMAdminStore-Cloud` therefore contains usage attributable to the **organizer's** account context as the controller, and the organizer's device can hold a cloud copy of the **child's** usage. In a custody, coercive-control, or minor-safety matter, this means usage data for one person can be recovered from a *different* person's device — follow the account, not just the handset.

> ⚖️ **Authorization:** The Family-Sharing fan-out means examining one device can incidentally surface a **third party's** (often a *minor's*) usage data via `RMAdminStore-Cloud`. Confirm your authority covers the data subject you're actually reading, not just the device owner — a warrant naming the parent's handset may not, on its face, authorize mining the child's synced usage. Flag cross-account data, scope it against the legal authority, and document the provenance edge (whose account, whose device) for each artifact.

### Abuse, bypass, and anti-forensic angles

Screen Time is a control surface, and control surfaces get weaponised. The patterns you will actually encounter:

- **The Screen-Time passcode as a backup-acquisition lock.** A non-obvious trick: enabling a Screen-Time passcode lets a user *require it to change the encrypted-backup password*. A subject can thus block the classic "re-pair, set a known backup password, pull a logical backup" workflow without ever touching the device passcode. If a backup attempt errors on the backup-password step despite a cooperative pairing, suspect a Screen-Time passcode gate — and pivot to a full-file-system tier where the policy and the data live anyway.
- **Restrictions as instruments of control.** A Communication-Limits contact whitelist, an "Allowed Websites Only" list, "Don't Allow Changes" on the account/passcode, and a forced Screen-Time passcode on an *adult's* device with no children in the family group are classic stalkerware/coercive-control configurations. The restriction config and the controlling account are substantive evidence of the relationship, not just device hygiene.
- **Bypass attempts leave traces.** Common user bypasses — changing the device clock to defeat Downtime, deleting and reinstalling a limited app, toggling time zone — surface elsewhere: a clock change shows as a discontinuity across `knowledgeC`/`RMAdminStore` timestamps and in the unified log; an app reinstall shows in `/app/install` and the install/iTunes stores ([[12-unified-logs-sysdiagnose-crash-network]]). Treat a Screen-Time/`knowledgeC` time discontinuity as a tampering indicator to chase, per [[02-correlation-and-anti-forensics]].
- **The OS-level shield is hard to defeat in-band.** Because `ManagedSettings` enforces at launch services, force-quit/reboot/account-switch do not lift a shield — only the Screen-Time passcode or an authorized approval does. The realistic "bypasses" are out-of-band (clock/timezone, reinstall, or a full settings reset), each of which is itself loggable.

> 🔬 **Forensics note — developer/RE angle.** Any third-party "parental control," "focus," or — abused — *stalkerware* app that limits or watches other apps must hold the **`com.apple.developer.family-controls`** entitlement and obtain `FamilyControls` authorization; its managed state lives in a shared **App Group** container (`Library/Group Containers/<group>/`), and it ships separate **`DeviceActivityMonitor`** and **shield** app extensions. When triaging a suspect app, `codesign -d --entitlements :- <app>` for the family-controls entitlement, and check the App Group container — not just the app sandbox — for the policy it enforced. See [[05-the-app-sandbox-from-the-developer-side]] and [[08-extensions-app-clips-widgets-and-widgetkit]].

### Dated 2026 baseline (verify at author time)

Durable mechanism is above; these are the perishable specifics as of **2026-06-26** (iOS/iPadOS **26.5**):

- **Defaults flipped for minors.** Under-18 Apple Accounts now ship with **Safari web-content filtering and Communication-Safety nudity blurring ON by default**; Child Accounts aged 13–17 are auto-opted-in to web filters, app restrictions, and Communication Safety.
- **Communication Safety — surfaces now, content-type next.** In **current iOS (26.x)**, on-device Communication Safety blurs/intervenes on **nudity** across an expanded surface set — Messages, FaceTime (including video messages), AirDrop, Contact Posters, the Photos picker, shared albums, and adopting third-party apps via `SensitiveContentAnalysis` — all on-device, nothing uploaded to Apple. The **content type** widens to **violent/gore** imagery in Apple's **WWDC 2026 preview (announced 2026-06-08, shipping with iOS 27 / iPadOS 27 / macOS 27 in autumn 2026)** — that is **not in 26.5**; do not assert it as current.
- **`PermissionKit` (iOS 26, WWDC25).** This framework lets third-party apps route "follow/friend/message a new person" through **parental approval**, surfaced to the parent as a structured **"question" inside Messages** they approve or deny inline — backing the **Communication Limits** that span Phone, FaceTime, Messages, and iCloud contacts, plus any adopting third-party app. A *separate*, companion **Declared Age Range API** (also iOS 26) lets an app request a **coarse age range** (e.g. "13–15") instead of an exact birthdate — don't conflate the two: PermissionKit routes approvals, Declared Age Range discloses a band.
- **WWDC 2026 previews (iOS 27, autumn 2026).** Beyond the Communication-Safety content-type widening above, Apple previewed further Screen Time changes — **"Ask to Browse"** (per-site Safari approval routed to the parent), **"Time Allowances"** / **Daily Schedules** for app categories, and a **redesigned Screen Time dashboard**. Treat any post-26.5 artifact-path claim as **research-at-author-time**; the `RMAdminStore`/`knowledgeC` substrate described here is the durable layer beneath whatever the UI becomes.

## Hands-on

There is no on-device shell — everything runs Mac-side against a Simulator container, a public sample image, or a mounted full-file-system extraction. Copy-before-query always.

**0. Orient on the Simulator (structure only — no real usage data):**

```bash
xcrun simctl list devices booted                 # get the booted UDID
DEV=~/Library/Developer/CoreSimulator/Devices/<UDID>/data
# The Simulator stubs the Screen Time stack; you're confirming layout, not harvesting usage:
find "$DEV" -iname '*remotemanagement*' -o -iname '*ScreenTime*' -o -iname 'knowledgeC.db' 2>/dev/null
# Contrast against the faithful macOS store on your own Mac:
ls ~/Library/Application\ Support/com.apple.remotemanagementd/
```

**1. Locate the Screen Time stores in a mounted FFS image (paths are durable):**

```bash
# In a mounted full-file-system extraction rooted at $IMG
find "$IMG/private/var/mobile/Library/Application Support/com.apple.remotemanagementd" \
     -name 'RMAdminStore-*.sqlite*'
# RMAdminStore-Local.sqlite   RMAdminStore-Local.sqlite-wal   RMAdminStore-Local.sqlite-shm
# RMAdminStore-Cloud.sqlite   ...

# The CoreDuet substrate for cross-corroboration:
ls "$IMG/private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db"
ls "$IMG/private/var/mobile/Library/Biome/"
```

**2. Copy the whole WAL trio, then dump the schema before any SELECT:**

```bash
D="$IMG/private/var/mobile/Library/Application Support/com.apple.remotemanagementd"
cp "$D"/RMAdminStore-Local.sqlite{,-wal,-shm} /tmp/st/
sqlite3 /tmp/st/RMAdminStore-Local.sqlite '.schema ZUSAGEBLOCK'
sqlite3 /tmp/st/RMAdminStore-Local.sqlite '.schema ZUSAGETIMEDITEM'
# Confirm the real column names, THEN run the rollup SELECT from the Concepts section.
```

**3. Inspect installed restriction/configuration profiles:**

```bash
# Installed configuration/restriction profiles live in the ConfigurationProfiles stores —
# NOT in ProvisioningProfiles (those hold per-app code-signing provisioning, a different thing).
CP="$IMG/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles"
ls "$CP" "$CP/Store" 2>/dev/null
ls "$IMG/private/var/mobile/Library/ConfigurationProfiles/"
# Managed-profile state is stored as (often binary) plists — convert each to XML and look
# for an installed restrictions payload:
for p in "$CP"/Store/*.plist "$CP"/*.plist; do
  plutil -convert xml1 -o - "$p" 2>/dev/null | grep -q applicationaccess && echo "restrictions payload in: $p"
done
# A standalone .mobileconfig is CMS/PKCS#7-signed — unwrap it first (Mac-side) before plutil:
#   security cms -D -i profile.mobileconfig | plutil -p -
```

**4. Brute the legacy Restrictions passcode (older device/backup only):**

```bash
# pinfinder operates on an iTunes/Finder backup (supports iOS 8–12.4.x; iOS 13+ removed it)
python3 pinfinder.py --backup ~/Library/Application\ Support/MobileSync/Backup/<UDID>
# Recovers the 4-digit Restrictions/Screen-Time PIN: on iOS 7–11 from the salted PBKDF2-HMAC-SHA1
# hash in com.apple.restrictionspassword.plist; on iOS 12 from the backup keychain item it moved to.
```

**5. Run the community parsers (they know the per-version schema drift):**

```bash
# iLEAPP has Screen Time / RMAdminStore modules; mvt parses many usage stores
ileapp -t fs -i "$IMG" -o /tmp/ileapp_out          # browse the "Screen Time" / usage sections
mvt-ios check-fs "$IMG" --output /tmp/mvt_out       # triage + timeline across stores
```

**6. Triage a suspect "parental control" / monitoring app for the Screen Time entitlement:**

```bash
# Family-controls apps carry a specific entitlement; their policy hides in an App Group
codesign -d --entitlements :- "/path/to/Suspect.app" 2>/dev/null | grep -i family-controls
# <key>com.apple.developer.family-controls</key><true/>   ← it manages other apps

# Then inspect the shared App Group container in the image, not the app sandbox:
find "$IMG/private/var/mobile/Containers/Shared/AppGroup" -iname '*.plist' -path '*group*' 2>/dev/null
```

> 🔬 **Forensics note:** Prefer iLEAPP/`mac_apt`/commercial parsers for the *final* report — they track Apple's column renames per iOS version — but always hand-verify one or two rows with `sqlite3` against the raw store so you can testify to the underlying data, not just the tool's output.

## 🧪 Labs

> ⚠️ Every lab is **device-free**. The Simulator runs macOS frameworks: it has **no SEP, no Data Protection, no real `ScreenTimeAgent`/`remotemanagementd` usage daemon and no `knowledged` pattern-of-life ingest**, so it will **not** populate `RMAdminStore` with genuine usage. Use the Simulator to learn *where things live* and the macOS Screen Time store / a public iOS sample image for *real schema and data*.

### Lab 1 — Map the Screen Time surface (substrate: Simulator + your own Mac; fidelity: structure only, no device usage data)

1. Boot a Simulator and locate its data root:
   `xcrun simctl list devices booted` → note the UDID → `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/`.
2. Search it for the agent and store names: `find <data> -iname '*remotemanagement*' -o -iname '*ScreenTime*'`. Observe what *is* and *isn't* there — the Simulator stubs much of this. Document the gap.
3. Now look at the **real** equivalents on your Mac: `~/Library/Application Support/com.apple.remotemanagementd/` and `~/Library/Application Support/Knowledge/knowledgeC.db`. This is the closest faithful `RMAdminStore` you can touch without a device.

### Lab 2 — Parse a real `RMAdminStore` (substrate: macOS Screen Time store or public iOS sample image; fidelity: real schema + data)

1. On your Mac, enable Screen Time (System Settings → Screen Time) and let it accrue a day of usage.
2. `cp` the trio `RMAdminStore-Local.sqlite{,-wal,-shm}` to `/tmp/st/`.
3. `.schema ZUSAGEBLOCK` and `.schema ZUSAGETIMEDITEM` — write down the **actual** column names on your OS build (they will differ from the template query).
4. Build and run the rollup join. Reconcile its per-app daily totals against what the Screen Time UI reports for the same day. Note any discrepancy and reason about WAL-checkpoint lag.
5. (Optional) Run `mac_apt.py ... SCREENTIME` and diff its output against your hand query.

### Lab 3 — Recover a legacy control passcode (substrate: public sample backup / your own old backup; fidelity: exact)

1. Obtain an iOS 7–12 era unencrypted backup (Josh Hickman's reference images, or an old personal backup).
2. Run `pinfinder` against it; recover the Restrictions/Screen-Time PIN.
3. Open `com.apple.restrictionspassword.plist` (the `398bc9c2…40b` file) with `plutil -convert xml1`; identify the `Key` and `Salt` and confirm they match what `pinfinder` consumed.
4. Write one sentence on why this workflow **fails** on an iOS 13+ device (the credential left the backup keychain) — and what acquisition tier you'd need instead.

### Lab 4 — Cross-corroborate Screen Time against `knowledgeC` (substrate: public iOS sample image; fidelity: exact for that image)

1. From a sample FFS image, copy both `RMAdminStore-Local.sqlite` (the rollup) and `CoreDuet/Knowledge/knowledgeC.db` (the substrate — see [[01-knowledgec-db-deep-dive]]).
2. Pick one app and one day. From `RMAdminStore` get the daily total; from `knowledgeC` sum the `/app/inFocus` (and `/app/usage`) intervals for the same bundle ID and day.
3. Explain the difference: foreground-focus seconds vs. Screen Time's "usage" accounting (which folds in background/notification context and category rollups). Document which store you'd cite for which claim.

### Lab 5 — Read the enforced restriction posture (substrate: a `.mobileconfig` you author + a sample image; fidelity: exact for the payload format)

1. Author a `com.apple.applicationaccess` payload in any plist editor (or hand-write the XML from the Concepts example) and save it as a `.mobileconfig`. This is the same payload format Screen Time/MDM persist — you're learning to *read* it by *writing* one.
2. `plutil -lint` it, then `plutil -convert xml1 -o - file.mobileconfig` and confirm every restriction key round-trips.
3. In a sample image, locate the installed profiles under `/private/var/mobile/Library/ConfigurationProfiles/` and `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/`; convert any binary plists and identify whether a `com.apple.applicationaccess` payload is present.
4. Write a one-paragraph "device posture" summary from the payload: what's disabled, what's forced, whether wipe/app-removal is blocked — the framing you'd put at the top of an exam report.

## Pitfalls & gotchas

- **Ignoring the `-wal` loses the freshest hours.** `RMAdminStore-Local.sqlite-wal` holds uncheckpointed recent activity. Acquire and parse the full `.sqlite`/`-wal`/`-shm` trio; copy all three before opening. This is the single most common Screen-Time parsing miss.
- **Trusting memorized column names.** `RMAdminStore` and `knowledgeC` are Core Data stores whose `Z*` columns Apple renames across iOS versions. `.schema` first, every time. A query that "worked last year" can silently return zero rows or wrong joins.
- **Wrong epoch.** These are Mac Absolute Time (2001) seconds — add `978307200`. Mixing in the Unix or WebKit/Cocoa-nanosecond epochs (as elsewhere in the iOS timestamp zoo) yields timestamps decades off. See [[00-the-ios-timestamp-zoo]].
- **Conflating the Screen-Time passcode with the device passcode.** They are different secrets with different storage and different recovery paths. A handed-over "Screen Time passcode" does **not** unlock the device or its Data-Protection-class files.
- **Assuming Screen Time is in a backup.** `RMAdminStore` and the modern Screen-Time passcode are **full-file-system-only**. A logical/iTunes backup will not contain them. Don't promise a client usage data you can only get from an FFS-class extraction.
- **Treating restriction config as usage.** A configured limit/shield/web-filter proves a *control existed*, not that an app was blocked at a given second — that requires correlation against `knowledgeC`. Keep the policy claim and the activity claim separate.
- **MDM vs. family restrictions.** `com.apple.applicationaccess` payloads under ConfigurationProfiles are an enforced device policy distinct from family Screen-Time toggles; on a supervised/managed device, that's where the real restriction posture lives. Check both surfaces.
- **Simulator ≠ device for usage.** The Simulator will never produce real `RMAdminStore` usage rows — no usage daemon. Use it for layout, the Mac/sample-image stores for data.
- **ADP silently zeroes the cloud route.** If the target has Advanced Data Protection on, the `RMAdminStore-Cloud` containers are end-to-end-encrypted and a cloud pull returns nothing usable — don't mistake an ADP wall for "no Screen Time was configured." Confirm ADP status before concluding usage data is absent.
- **Usage attribution is per *account*, not per *handset*.** On a shared or hand-me-down device, blocks in `ZUSAGE`/`ZCOREUSER` are tied to the signed-in family member at the time. Don't attribute usage to "the device's owner" without checking `ZCOREUSER`/`ZCOREDEVICE` — the family graph can route one person's usage onto another's device copy.

## Key takeaways

- Screen Time is a **UI skin over the CoreDuet pipeline**: raw signal in `knowledgeC`/Biome → aggregated by `ScreenTimeAgent` → persisted/enforced by `remotemanagementd` in `RMAdminStore` → shielded by `ManagedSettings`.
- The usage rollup is `RMAdminStore-Local.sqlite` (per-app/per-category/per-device/per-day, Mac Absolute Time); the family fan-out is `RMAdminStore-Cloud.sqlite`. **Always include the `-wal`.**
- These stores are **full-file-system-only** — not in any backup, not reachable logically. The acquisition tier is the same A8–A13 BootROM/agent/GrayKey boundary that governs the rest of the pattern-of-life corpus.
- Content & Privacy Restrictions gate purchases, allowed apps, content ratings, web content, Communication Limits/Safety, and TCC/settings changes; family restrictions persist in `RMAdminStore`, MDM restrictions in ConfigurationProfiles (`com.apple.applicationaccess`).
- The **Screen-Time passcode is a distinct credential** from the device passcode. Legacy Restrictions PINs (iOS 7–12) are brute-forceable from backups (`pinfinder`); iOS 13+ removed it from backups entirely (device-only keychain; Apple-Account recovery).
- Forensically, Screen Time is a **corroborating, pre-aggregated pattern-of-life source** plus a **record of the enforcement posture and the controlling account** — and the passcode carries coercive-control / acquisition-frustration significance.
- 2026 specifics (verify): under-18 defaults now ON; Communication Safety's **violence/gore** expansion is a **WWDC 2026 / iOS 27 (autumn) preview — not yet in 26.5**; `PermissionKit` (iOS 26) routes parental approvals through Messages, with a *separate* Declared Age Range API for coarse age disclosure.

## Terms introduced

| Term | Definition |
|---|---|
| Screen Time | Apple's usage-tracking + parental-controls feature; a UI/aggregation layer over the CoreDuet pattern-of-life pipeline. |
| `RMAdminStore-Local.sqlite` | Core Data SQLite store (owned by `remotemanagementd`) holding this device's aggregated Screen-Time usage + restriction/limit config. |
| `RMAdminStore-Cloud.sqlite` | The Family-Sharing fan-out store — usage/limits synced across the account's other devices. |
| `ZUSAGEBLOCK` / `ZUSAGECATEGORY` / `ZUSAGETIMEDITEM` | The time-block / category-bucket / per-app(-domain) leaf tables forming the Screen-Time usage rollup. |
| `remotemanagementd` | Daemon (`com.apple.remotemanagementd`) that owns the `RMAdminStore` databases. |
| `ScreenTimeAgent` | User-side Screen Time daemon (`com.apple.ScreenTimeAgent`, `ScreenTimeCore.framework`) — passcode check, family/account state, reporting. |
| FamilyControls / ManagedSettings / DeviceActivity | The three developer frameworks for authorization / enforcement (shields) / scheduling that implement limits, Downtime, and restrictions. |
| Content & Privacy Restrictions | The policy surface gating purchases, allowed apps, content ratings, web content, communication, and TCC/settings changes. |
| Communication Safety | On-device ML feature that blurs/intervenes on nudity in Messages/FaceTime/AirDrop/Contact Posters/Photos picker — nothing uploaded (widens to violent/gore imagery in the iOS 27 / WWDC 2026 preview, not 26.5). |
| Screen-Time passcode | The control credential for Screen Time — distinct from the device passcode; device-only keychain since iOS 13, Apple-Account recovery. |
| Restrictions passcode (legacy) | Pre-iOS 12 parental PIN stored as a salted PBKDF2-HMAC-SHA1 hash in `com.apple.restrictionspassword.plist`; brute-forceable (`pinfinder`). |
| `pinfinder` | Open-source tool that recovers the legacy Restrictions/Screen-Time PIN (iOS 7–12) from a backup's salted hash. |
| `PermissionKit` | iOS 26 framework routing parental approvals (follow/friend/message) through Messages "questions"; coarse age-range disclosure is the *separate* companion Declared Age Range API, not PermissionKit itself. |
| `com.apple.developer.family-controls` | The entitlement a third-party app must hold to shield/monitor other apps via the Screen Time APIs. |
| App Group | Shared container (`Library/Group Containers/<group>/`) the main app, `DeviceActivityMonitor`, and shield extensions use to share managed state across their separate processes. |
| `com.apple.applicationaccess` | The configuration-profile restrictions payload (MDM/supervision path) — the enforced device policy distinct from family Screen-Time toggles. |
| Mac Absolute Time | Cocoa/Core Data timestamp epoch (2001-01-01 UTC); add `978307200` for Unix epoch. |

## Further reading

- Apple — *Screen Time API* documentation (`FamilyControls`, `ManagedSettings`, `DeviceActivity`, `ManagedSettingsUI`) on developer.apple.com; WWDC22 "What's new in Screen Time API"; WWDC25 "Enhance child safety with PermissionKit."
- Apple Newsroom — "Apple previews new child safety features" (2026-06); Apple Support — "Use parental controls," "Create/manage a Screen Time passcode," "If you forgot the Screen Time passcode."
- Apple — *Configuration Profile Reference* (the `com.apple.applicationaccess` restrictions payload) and the Platform Deployment Guide — for the MDM/supervision restriction path.
- Heather Mahalik / Cellebrite — "Data Quality and Quantity… Examining Screen Time Artifacts" and "A Look Into Apple's Screen Time Feature" (the `RMAdminStore` table walkthrough).
- Magnet Forensics — "Getting Evidence from iOS Screen Time Artifacts" and "A look into iOS 18's changes."
- Yogesh Khatri — `mac_apt` `plugins/screentime.py` (github.com/ydkhatri/mac_apt) for a working parser of the macOS store schema.
- Elcomsoft / Decipher Tools blogs — Screen-Time-passcode storage evolution and recovery (iOS 12 vs 13+); `pinfinder.net` for the legacy-PIN brute force.
- RealityNet — *iOS-Forensics-References* (github.com/RealityNet/iOS-Forensics-References); ZENA Forensics (blog.digital-forensics.it) "A first look at iOS 18 forensics."
- SANS FOR518 Mac & iOS poster; Sarah Edwards (mac4n6.com) and APOLLO for the `knowledgeC` substrate this aggregates from.

---
*Related lessons: [[01-knowledgec-db-deep-dive]] | [[02-biome-and-segb-streams]] | [[05-full-file-system-acquisition]] | [[04-configuration-profiles-and-mobileconfig]] | [[02-mdm-supervision-and-abm]] | [[00-the-ios-timestamp-zoo]] | [[08-keychain-on-ios]]*
