---
title: "MDM, supervision & ABM"
part: "06 — Automation & Operations"
lesson: 02
est_time: "50 min read + 15 min labs"
prerequisites: [code-signing-amfi-entitlements, the-ios-security-model]
tags: [ios, operations, mdm, supervision, abm, ade, forensics]
last_reviewed: 2026-06-26
---

# MDM, supervision & ABM

> **In one sentence:** Mobile Device Management is a queue-and-poll control protocol bootstrapped by a single configuration profile, APNs is only the doorbell, and the *supervision* trust bit — set at the factory-fresh moment of enrollment — is the switch that turns a polite advisory relationship into near-total remote authority over the device, which makes "who manages this phone, and what can they do to it right now?" a first-order forensic question.

## Why this matters

For the examiner, a managed device is a different animal entirely. A supervised, Automated-Device-Enrollment iPhone has a *remote actor* — an organization with an MDM server — that can, the instant the device touches a network, **erase it, lock it, locate it, push or pull apps and profiles, and (if it escrowed the unlock token) clear the passcode**. That is a live destruction risk that ranks with Find My: triage means RF isolation *first*, questions later. It also reshapes acquisition: a supervised device can *prohibit host pairing*, so your `idevicepair pair` over USB simply fails unless you hold the organization's supervision identity. And it hands you investigative leads — the `ServerURL` in the MDM payload names the controlling organization (a subpoena target), the enrollment timestamps anchor a timeline, and the escrowed bypass code may be a lawful-access avenue. For the builder, the same protocol is how every enterprise fleet, school cart, and kiosk on earth is provisioned, and how Apple's 2026 management stack (declarative device management) is replacing the imperative command model you're about to learn. You cannot reason about an enterprise iPhone — its threat model, its restrictions, its acquirability — without knowing this layer.

## Concepts

### The management trust spectrum

"Managed" is not one state. There is a spectrum of trust, and where a device sits on it determines everything downstream — what the server may command, whether the user can walk away from management, and whether you can even pair to it:

```
LESS TRUST  ──────────────────────────────────────────────►  MORE TRUST

 Unmanaged       User-/Account-driven      Device-enrolled       Supervised
 (no MDM)        enrollment (BYOD)          (manual profile)      (ADE or Configurator)
   │                  │                        │                      │
   │             managed Apple Acct       full-device MDM,       full-device MDM +
   │             + separate managed       profile USER-          NON-removable profile,
   │             data volume; user        REMOVABLE; small       Activation-Lock bypass,
   │             owns the device          restriction set        the LARGE restriction set,
   │                                                             supervised-only commands
```

Two axes hide inside that line and people constantly conflate them:

1. **Enrolled vs. supervised.** *Enrollment* establishes the MDM relationship (the device will talk to a server). *Supervision* is an additional, elevated trust state — a bit set on the device — that unlocks the heavy management surface. A device can be enrolled-but-not-supervised (a user who manually installed a company profile); it cannot be supervised without also being enrolled.
2. **User-enrolled vs. device-enrolled.** Modern BYOD uses *account-driven user enrollment*: a **managed Apple Account** federates in, and managed apps/data land on a **cryptographically separated APFS data volume** so the org can wipe *its* data without touching the user's photos. Device enrollment manages the whole device.

The forensic punchline: **supervision + Automated Device Enrollment is the maximum-authority configuration**, and it is exactly the configuration enterprise and education fleets ship in.

> 🖥️ **macOS contrast:** You met this on the Mac as Jamf/Kandji/Intune pushing `.mobileconfig` profiles, ABM/ADE zero-touch, and the `mdmclient` daemon writing into `/var/db/ConfigurationProfiles/`. It is the **same protocol family and the same ABM/ADE programs** — Apple deliberately unified them. The difference that matters: **iOS supervision unlocks dramatically more** than macOS supervision does. On macOS the user account model and SIP carry much of the weight, and many supervised restrictions simply don't exist; on iOS, supervision is the gate to kiosk/Single App Mode, the global HTTP proxy, app-install suppression, Activation Lock bypass, host-pairing prohibition, and a long restrictions list. A supervised iPhone is far more *owned* by its org than a supervised Mac is.

### The MDM payload: how the relationship is established

Everything begins with one configuration profile containing a payload of type **`com.apple.mdm`**. (Configuration profiles in general — their CMS signing, payload structure, and on-disk form — are [[configuration-profiles-and-mobileconfig]]; this is the one payload that turns a profile into a *management channel*.) The key fields:

| Key | Meaning |
|---|---|
| `ServerURL` | HTTPS endpoint the device POSTs to for the **command** protocol (polling for queued commands). |
| `CheckInURL` | Endpoint for the **check-in** protocol (enroll/token/unenroll). If absent, `ServerURL` is used. |
| `Topic` | The APNs **topic** = the subject of the MDM push certificate (e.g. `com.apple.mgmt.External.<UUID>`). The device only honors pushes on this topic. |
| `IdentityCertificateUUID` | References the per-device **identity certificate** (provisioned via SCEP, or ACME in modern flows) used for **mutual-TLS client auth** on every connection — this is how the server proves the connecting device is the enrolled one, and vice-versa. |
| `AccessRights` | A bitmask granting specific capabilities (inspect/install profiles, lock, erase, query info…). Legacy granularity; modern MDM requests them all. |
| `CheckOutWhenRemoved` | If true, the device sends a `CheckOut` when the profile is removed. |
| `ServerCapabilities` / `SignMessage` | Negotiated features and whether the device CMS-signs its messages with the identity cert. |

The identity certificate is the crux of authentication. There are no shared secrets on the wire after enrollment: **every** check-in and command exchange is a mutual-TLS handshake using the device's enrollment identity, so a stolen `ServerURL` alone buys an attacker nothing. (If your PKI instincts are rusty, this is the SCEP/ACME enrollment dance riding on top of the code-signing/identity machinery from [[code-signing-amfi-entitlements]].)

### The check-in protocol — enroll, token, unenroll

MDM is split into two sub-protocols. The **check-in** protocol manages the *existence* of the relationship and runs three message types (the device sends a plist with a `MessageType` key to `CheckInURL`):

- **`Authenticate`** — sent first, at enrollment. Carries the device `UDID` and the push `Topic`. The server validates eligibility and accepts (or rejects) management.
- **`TokenUpdate`** — sent immediately after, and whenever the push token rotates. Carries:
  - `Token` — the **APNs device token** (where to send the wake-up push).
  - `PushMagic` — a UUID string the **device generates** and reports to the server here in `TokenUpdate`; the server then **must echo it back inside every push payload** (the top-level `mdm` key) or the device ignores the push. This is the anti-spoofing nonce that stops a random APNs message from triggering a poll, and it **rotates on every unenroll/re-enroll** — a stale value logs *"Rejecting MDM push dictionary because it does not have the right magic string."*
  - `UnlockToken` — an **escrowed blob the device generates that lets the server clear the passcode** (the `ClearPasscode` command) without knowing it. (Forensically loud — see below.)
- **`CheckOut`** — sent when the MDM profile is removed (only if `CheckOutWhenRemoved` is set), telling the server to forget the device.

> 🔬 **Forensics note:** The `UnlockToken` is the quiet bombshell of this protocol. If the MDM server escrowed it at enrollment, the controlling organization can issue a `ClearPasscode` and **remove the device passcode** — which, on an **AFU** (After-First-Unlock) device, is a real path to the data without brute force. That makes the org a lawful-access lead: a warrant to the MDM operator may yield the unlock token (and the Activation Lock bypass code below). Tie this to [[passcode-bfu-afu-and-inactivity]] — the escrow only helps while keys are available (AFU); a **BFU** device that has hit the inactivity reboot is still cold.

### The command/poll model — APNs is only a doorbell

Here is the single most misunderstood thing about MDM: **APNs carries no commands.** The server cannot push instructions to the device. The model is a queue the device drains on its own schedule:

```
 MDM SERVER                         APNs                         DEVICE
     │                               │                              │
 1.  │  queue command(s)             │                              │
     │  for device                   │                              │
 2.  │ ── push (token, mdm=PushMagic) ─►                            │
     │                               │ ── wake-up notification ───► │
     │                               │                              │ 3. verify PushMagic
     │                               │                              │    matches; else ignore
 4.  │ ◄──────── HTTPS POST "Idle" status (mutual-TLS) ──────────── │
 5.  │ ── HTTP 200 + next command (plist: CommandUUID + RequestType) ►
     │                               │                              │ 6. execute
 7.  │ ◄── HTTPS POST status: Acknowledged / Error / NotNow ─────── │
     │     (CommandUUID + result)                                   │
 8.  │ ── 200 + NEXT command, or 200 with EMPTY body (queue drained)►
     │                               │                              │ 9. go idle
```

Walk it: the server **queues** commands and rings the doorbell via APNs (step 2). The push payload's top-level `mdm` key contains the **PushMagic**; the device checks it against what it sent in `TokenUpdate` (step 3) and only then **connects out** over mutual-TLS HTTPS to `ServerURL` and reports `Idle` (step 4). The server hands back **one** command at a time — a plist with a `CommandUUID` and a `Command` dict whose `RequestType` names the operation (step 5). The device executes, POSTs a status (`Acknowledged`, `Error`, or the deferral `NotNow`) tagged with that `CommandUUID` (step 7), and asks for the next. When the queue is empty the server returns an empty body and the device goes idle (steps 8–9).

Consequences you should internalize:

- **All command data flows device→server over the direct HTTPS channel**, never through APNs. APNs is fire-and-forget and may be coalesced/dropped; the device also polls on its own cadence and after reboots, so commands eventually land even if a push is missed.
- **`NotNow`** is the device saying "I can't do this in my current state" (classically: it's locked and the command needs the passcode-derived keys). The server re-pushes later.
- **The device dials out.** For interception/analysis you watch the device's outbound TLS to `ServerURL`, not inbound (cf. [[traffic-interception-and-tls]]).

> 🖥️ **macOS contrast:** Identical model on the Mac — `mdmclient` polls the same way after an APNs wake, which is why an offline Mac "ignores" MDM until it reconnects. The protocol is shared; only the daemon name and the on-disk profile store differ (`/var/db/ConfigurationProfiles/` on macOS vs. the systemgroup container on iOS, below).

### The command catalog — what the server can actually order

A command is a plist with a `CommandUUID` and a `Command` dict whose **`RequestType`** names the operation. The catalog is large and version-evolving; the ones that matter for the threat/forensic picture, and whether they need supervision:

| `RequestType` | Effect | Supervision |
|---|---|---|
| `DeviceInformation` | Query serial, model, capacity, OS, IMEI/MEID, names | enrolled |
| `ProfileList` / `InstalledApplicationList` / `CertificateList` | Inventory installed profiles / apps / certs | enrolled |
| `InstallProfile` / `RemoveProfile` | Push or pull a configuration profile | enrolled |
| `DeviceLock` | Lock the device (optional message + phone number) | enrolled |
| `ClearPasscode` | **Remove the passcode** (needs the escrowed `UnlockToken`) | enrolled |
| `EraseDevice` | **Remote wipe** (Erase All Content & Settings) | enrolled |
| `InstallApplication` | Push a managed app (silent on supervised) | enrolled / silent ⇒ supervised |
| `Settings` | Set wallpaper, device name, app attributes, data roaming | mostly supervised |
| `EnableLostMode` / `DisableLostMode` | Lost Mode lock + on-screen message | **supervised** |
| `DeviceLocation` | Return GPS coordinates (only while in Lost Mode) | **supervised** |
| `RestartDevice` / `ShutDownDevice` | Power-cycle the device | **supervised** |
| `ClearActivationLock` / Activation-Lock bypass | Clear Activation Lock via escrowed code | **supervised** |
| `DeclarativeManagement` | Flip the device into declarative (DDM) mode | enrolled |

The two rows to burn in are `EraseDevice` and `ClearPasscode`: both work on a **merely enrolled** device, not just a supervised one. That is the entire basis of the remote-wipe race and of the unlock-token lawful-access path. (The exact supervision requirement of a few commands has shifted across iOS versions — `RestartDevice`/`ShutDownDevice` and silent `InstallApplication` in particular — so confirm the current requirement against Apple's MDM Protocol Reference for your target build.)

> 🔬 **Forensics note:** `MDMEvents.plist` (below) records the commands a device actually *received*. An `EraseDevice`, `EnableLostMode`, or `ClearPasscode` entry timestamped near your seizure tells you the organization tried to act on the device after it left the user's hands — directly relevant to spoliation, to whether the data you have is complete, and to the device's lock state when you got it.

### Enrollment variants you'll meet in the wild

"Enrolled" hides several distinct flows, and the variant determines both the management ceiling and what an examiner can recover:

- **Automated Device Enrollment (ADE)** — zero-touch, supervised, non-removable. The maximum-authority flow (detailed next).
- **Apple Configurator** — USB, supervised, requires a wipe. The manual path to supervision for devices not in ABM.
- **Device enrollment (manual profile)** — a user installs a company `.mobileconfig` (from a portal or email). Full-device MDM but **user-removable** and **not supervised** — the small capability column above.
- **Account-driven user enrollment (BYOD)** — the user signs in with a **managed Apple Account**; managed apps and their data land on a **separate, cryptographically isolated APFS data volume**, so the org can wipe *its* footprint (`AccountConfiguration`/managed data) without touching the user's personal photos, messages, or apps. The org gets *no* device-wide control, *no* serial/IMEI, *no* erase-the-whole-device — by design, to make BYOD palatable. Forensically this matters: a user-enrolled device's *personal* partition is the user's and is acquired normally; only the managed volume is the org's.

The SCEP/ACME identity step deserves a callout because it sequences the whole enrollment: the profile bundles a SCEP (or, increasingly, **ACME**) payload that provisions the device's **client identity certificate** *before* the `com.apple.mdm` payload activates, because the device must already hold that cert to complete the first mutual-TLS connection to `ServerURL`. ACME (the same protocol family as Let's Encrypt, adapted by Apple for device attestation) additionally lets the device **attest in hardware** that the key lives in the Secure Enclave — closing the door on a cloned/extracted enrollment identity.

### Supervision: the trust bit, and how a device gets it

**Supervision is a flag on the device** establishing that the organization *owns* it (not merely manages a user's personal device). It is set at one of exactly two moments, both requiring either a factory-fresh device or a wipe:

1. **Automated Device Enrollment (ADE)** — the zero-touch path. The device's serial number is assigned to an MDM server in Apple Business/School Manager. At **Setup Assistant**, the device contacts Apple's activation service (`iprofiles.apple.com` / `mdmenrollment.apple.com`), receives an **activation record** naming the org's MDM `ServerURL`, and enrolls **before the user finishes setup** — supervised, with a **non-removable** management profile the user cannot delete. No physical handling, no cable. **This is the configuration that "cannot be bypassed by the user."**
2. **Apple Configurator** — the manual path. A Mac running Apple Configurator (or its `cfgutil` CLI) tethers the device over USB, "Prepares" it with an organization and a **supervision identity**, wipes it, and supervises it. Used for kiosks, lab carts, and re-supervising devices not in ABM.

The **supervision identity** is itself a forensic and operational artifact: it's a certificate + private key (exported as an encrypted PKCS#12 `.p12`) that authorizes a host to pair with the supervised device. When the org also sets the *prohibit host pairing* restriction (below), **only computers holding a matching supervision identity can pair** — every other Mac is refused at the USB layer.

> ⚠️ **ADVANCED:** Supervising a device **erases it**. There is no "upgrade an existing personal device to supervised in place." Any walkthrough that supervises a device is destructive — never run Configurator "Prepare"/`cfgutil prepare` against an evidence device. The only non-destructive thing you do with a device here is *read* its existing management state.

### ABM / ASM and Automated Device Enrollment (the program formerly called DEP)

**Apple Business Manager (ABM)** and **Apple School Manager (ASM)** are Apple's web portals where an organization (a) links its purchased devices — bought from Apple or an authorized reseller, tied to the org by purchase — to its account, (b) assigns them to an MDM server for **Automated Device Enrollment (ADE)**, and (c) manages **managed Apple Accounts** and app/book licensing (the old "VPP"). ADE is the 2026 name for what was historically **DEP** (Device Enrollment Program) — same mechanism, current branding. The chain is:

```
Apple/reseller purchase ──► device serial bound to org in ABM/ASM
        │
        └─► org assigns serials to an MDM server (ADE)
                │
                └─► device, at Setup Assistant, pulls activation record
                        └─► auto-enrolls + supervises (non-removable)
```

The forensic value: **ABM binding is sticky and survives a wipe.** Erasing an ADE device and walking back through Setup Assistant re-pulls the activation record and re-enrolls it — the device "phones home" to the org again. You cannot launder a supervised ADE device clean by wiping it; that property is the entire point of Activation-Lock-style theft deterrence, and it tells you the device's provenance is institutional.

### What supervision unlocks

Supervision is the gate to the bulk of the management surface. Unsupervised (manually enrolled) devices get a small, polite subset; supervised devices get the heavy machinery. A representative — not exhaustive — split:

| Capability | Unsupervised | Supervised-only |
|---|---|---|
| Install/remove configuration profiles, query device info, **DeviceLock**, **EraseDevice** (wipe) | ✓ | |
| Inspect installed apps, install managed apps *with* user prompt | ✓ | |
| **Silent** managed-app install/removal, prevent app removal, app allow/deny lists | | ✓ |
| **Activation Lock bypass** (escrow + clear the lock) | | ✓ |
| **Global HTTP proxy / web content filter** (force all traffic through a filter) | | ✓ |
| **Single App Mode / Autonomous Single App Mode** (kiosk lockdown) | | ✓ |
| **Prohibit host pairing** (only supervision-identity hosts may pair over USB) | | ✓ |
| **Lost Mode** (`EnableLostMode`: lock + on-screen message + locate via `DeviceLocation`) | | ✓ |
| Restrict AirDrop, App Store, Safari, iMessage, Erase-All-Content, account/Wi-Fi/cellular changes, USB/accessory, Find My, naming, wallpaper… | | ✓ (mostly) |
| `RestartDevice` / `ShutDownDevice`, set device name/wallpaper, clear restrictions password | | ✓ |

Two unlocks deserve their own paragraphs because they bite forensics directly:

**Activation Lock bypass.** On a supervised device, Activation Lock is *off by default*, but the MDM can permit it and **escrow a bypass code**. The MDM generates a random **31-byte** code, registers it with Apple's servers, and on the Activation Lock screen the code is entered **in the password field with the username left blank** to clear the lock. Timing matters and is examinable: the bypass code is retrievable for up to **~15 days after the device is first supervised**, or until the MDM fetches and clears it — miss that window and the code is gone. So a managed device that's been supervised more than ~15 days may have an *unretrievable* code unless the MDM grabbed it in time. (Verify the 31-byte / 15-day specifics against Apple's current Deployment guide — Apple has tuned these.)

**Prohibit host pairing.** This is the supervised restriction that breaks your USB workflow. When set, the device refuses to establish a pairing record with any host lacking a matching supervision identity — so `idevicepair pair` (and therefore lockdown-mediated logical acquisition, see [[logical-acquisition-with-libimobiledevice]]) returns *"pairing prohibited by supervisor."* Without the org's `.p12`, the USB door is shut.

> 🔬 **Forensics note:** **Host-pairing prohibition is the supervised-device acquisition wall.** A logical/backup acquisition over USB depends on a pairing record (the `escrow bag` exchanged during pair). If the supervisor prohibited pairing, you cannot pair, cannot extract a backup, cannot run `pymobiledevice3` lockdown services — unless you obtain the **supervision identity** from the controlling org. This is frequently *the* reason a "simple logical extraction" fails on an enterprise iPhone, and it routes you to either the org (for the `.p12`) or to a method that doesn't need pairing.

### Declarative device management is the 2026 baseline

The imperative queue-and-poll model above is being *displaced*, not retired, by **Declarative Device Management (DDM)** — the 2026 management standard across every serious vendor (Jamf, Kandji, Mosyle, Intune). Instead of the server queuing commands and the device polling, the device **holds declarations** (Configurations, Activations, Assets, Management) and **proactively reports state changes over a status channel** — lower latency, no constant polling, autonomous policy enforcement. DDM bootstraps over the *same* enrollment and the same APNs doorbell (a `DeclarativeManagement` command flips the device into declarative mode), so everything above still anchors it. The migration has teeth in this era:

- **iOS/iPadOS/macOS 26.4** *deprecated* the legacy MDM **restriction** keys for Apple Intelligence, Siri, and keyboard, moving them to **declarative configurations** (Genmoji, Image Playground, Writing Tools, Siri access).
- The **legacy software-update** commands, queries, deferrals, and restrictions are being **removed entirely** on the 27.0 platforms (announced WWDC 2025/2026) — software update is becoming **DDM-only**. Fleets still pushing updates the old way break.
- WWDC26 added DDM **network** configurations (VPN/IKEv2/IPsec/DNS proxy/relay), delivery of **legacy profiles as declarative assets**, **Lockdown Mode status reporting on supervised devices**, and **remote log collection** commands.

DDM is its own lesson — [[declarative-device-management]]. Know here only that the imperative protocol is the substrate DDM rides on, and that 2026-era artifacts increasingly reflect *declarations*, not commands.

> ⚖️ **Authorization:** A managed device is owned by an organization, and that org's policies, its right to wipe, and its escrowed credentials are legal facts about the device. Acquisition that leans on management — obtaining a supervision identity, an `UnlockToken`, or an Activation-Lock bypass code from the MDM operator — requires the appropriate legal process directed at *that organization*, separate from your authority over the device itself. Document the management state as part of chain of custody: it changes who else has had (and retains) control.

### Detecting management — the on-disk truth, the logs, the UI

For triage, you must determine — fast — whether a device is managed, supervised, and by whom. Three layers:

**1. On-disk configuration-profile store (the authoritative truth).** On iOS the profile/MDM state lives in the systemgroup container, not in `~/Library`:

```
/private/var/containers/Shared/SystemGroup/
    systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/
        ├── MDM.plist                      # the active MDM relationship: ServerURL, Topic, identity refs
        ├── MDMEvents.plist                # MDM event log (commands seen, enroll/checkout events)
        ├── CloudConfigurationDetails.plist# the ADE/cloud-config activation record (org, MDM URL)
        ├── Truth.plist / *truth*          # the "truth" store of installed profiles & their payloads
        └── (effective settings / restriction plists)
/private/var/mobile/Library/ConfigurationProfiles/   # active profile payloads (legacy path)
```

(Exact filenames drift across iOS versions — confirm the set on your target image; the *names* above are the ones to grep for. `CloudConfigurationDetails.plist` is the highest-value single file: it's the ADE activation record and names the controlling organization and MDM server.)

**2. The management daemons and their logs.** Profile installation is handled by **`profiled`**; the MDM client side by the MDM daemon (**`mdmd`** on iOS / **`mdmclient`** on macOS — verify the exact iOS binary name on your build); cloud configuration / ADE by **`cloudconfigurationd`**. Their activity surfaces in the unified log and in a **sysdiagnose** under subsystems like `com.apple.ManagedClient` (predicate on `process == "mdmd"` / `"profiled"` / `"cloudconfigurationd"`). A sysdiagnose also bundles a **profiles/configuration report** — often the fastest read on a *cooperating* device. (Unified-log and sysdiagnose mechanics: [[unified-logs-sysdiagnose-crash-network]].)

**3. The UI / management-state surfaces.** **Settings → General → VPN & Device Management** lists installed profiles and, on a supervised device, shows the banner *"This iPhone is supervised and managed by \<Organization\>."* The presence and removability of the management profile (greyed-out "Remove Management" = supervised/non-removable) is a one-glance read. On a backup or full-file-system image you reconstruct the same facts from the plists above.

> 🔬 **Forensics note:** Parse `CloudConfigurationDetails.plist` and `MDM.plist` first. Together they answer the triage question — *managed? supervised? by whom?* — and hand you the `ServerURL` (organization identity → subpoena target) and enrollment timestamps (timeline anchor). `MDMEvents.plist` can show the *history* of commands the device received: a `EraseDevice` or `EnableLostMode` in that log near your acquisition time tells you the org tried to act on the device.

### The triage decision flow

Synthesize the above into the order of operations the moment a possibly-managed device lands on your bench. "Who controls this device, and what can they do?" is not a curiosity — it dictates whether you must isolate it *this second* and whether your normal acquisition will even work:

```
 Powered-on device on the bench
        │
        ▼
 RF-ISOLATE FIRST (Faraday) ── a queued EraseDevice/EnableLostMode can land
        │                       the instant it sees a network. Isolate, THEN look.
        ▼
 Managed?  ──no──►  treat as an ordinary device; normal acquisition path
        │yes
        ▼
 Supervised?  (Settings banner / MDM.plist / non-removable profile)
        │
   ┌────┴───────────────┐
   │no (user-enrolled)   │yes (ADE/Configurator)
   ▼                     ▼
 profile is removable    profile NON-removable; serial sticky in ABM
 small command set       LARGE command set + Lost Mode + Activation-Lock bypass
 USB pairing works       USB pairing MAY be prohibited (need supervision .p12)
        │                     │
        └─────────┬───────────┘
                  ▼
 Identify the org from ServerURL / CloudConfigurationDetails.plist
                  ▼
 Legal process to the ORG for: supervision identity (.p12) → pairing;
   UnlockToken → ClearPasscode (AFU only); Activation-Lock bypass code
```

The branch that trips people: a supervised device that *prohibits host pairing* will defeat a textbook USB logical extraction with no obvious cause — the cable is fine, the device is unlocked, and `idevicepair pair` still refuses. Recognizing that this is a *management* failure, not a hardware or pairing-record failure, is what routes you to the org for the `.p12` instead of burning hours on the cable.

## Hands-on

There is no on-device shell, and the Simulator does not enroll in MDM (it runs macOS frameworks with no supervision/MDM client — see the lab caveats). So the realistic device-free work is: **dissect MDM payloads on the Mac**, and **parse management plists out of a sample full-file-system image**. The commands below run on the Mac.

**Dissect a signed `.mobileconfig` and find the MDM payload.** A profile is CMS/PKCS#7-signed; strip the signature, then pretty-print:

```bash
# A .mobileconfig is CMS-signed DER. Decode the signed content to the inner XML plist:
security cms -D -i enrollment.mobileconfig -o enrollment.plist
plutil -p enrollment.plist | less
# Look for the payload whose PayloadType is com.apple.mdm:
#   "PayloadType" => "com.apple.mdm"
#   "ServerURL"   => "https://mdm.example.com/mdm"
#   "CheckInURL"  => "https://mdm.example.com/checkin"
#   "Topic"       => "com.apple.mgmt.External.<UUID>"
#   "AccessRights"=> 8191
#   "IdentityCertificateUUID" => "<UUID>"
```

**Pull just the MDM payload fields with PlistBuddy or `plutil -extract`:**

```bash
# Enumerate payloads, then read the MDM one's key fields:
/usr/libexec/PlistBuddy -c "Print :PayloadContent" enrollment.plist | grep -A1 ServerURL
plutil -extract PayloadContent.0.ServerURL raw enrollment.plist
plutil -extract PayloadContent.0.AccessRights raw enrollment.plist   # e.g. 8191
```

**Decode the `AccessRights` bitmask.** It's a sum of capability bits; the well-established low bits:

```
   1  Inspect installed configuration profiles
   2  Install / remove configuration profiles
   4  Device lock + passcode removal
   8  Device erase
  16  Query Device Information (capacity, serial)
  32  Query Network Information (phone/SIM numbers)
  64  Inspect installed provisioning profiles
 128  Install / remove provisioning profiles
 256  Inspect installed apps
 (higher bits cover restrictions/settings/app-management — confirm against
  Apple's current MDM Protocol Reference; modern MDM typically requests ALL,
  e.g. AccessRights = 8191 = "everything")
```

```bash
# Quick decoder for the low bits:
python3 - 8191 <<'PY'
import sys
bits={1:"inspect-cfg",2:"install-cfg",4:"lock+clear-pass",8:"erase",
      16:"device-info",32:"network-info",64:"inspect-provision",
      128:"install-provision",256:"inspect-apps"}
n=int(sys.argv[1]); print("AccessRights",n,"=>",[v for b,v in bits.items() if n&b])
PY
```

**Parse management state out of a sample full-file-system image** (plists, not SQLite — `plutil`/PlistBuddy, no `cp`-then-`sqlite3` dance needed, but still work on a copy of the extraction):

```bash
ROOT=/path/to/extracted/ffs   # mounted/exported sample image
CP="$ROOT/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"

plutil -p "$CP/CloudConfigurationDetails.plist"   # ADE activation record: org + MDM URL
plutil -p "$CP/MDM.plist"                          # active MDM relationship
plutil -p "$CP/MDMEvents.plist"                    # MDM command/event history
# Effective restrictions often surface here too; grep the directory:
grep -rIl "allowHostPairing\|globalHTTPProxy\|SupervisorHostCertificates" "$CP" 2>/dev/null
```

**Let a forensic parser do it.** Both **iLEAPP** (Brignoni) and **mvt-ios** (Amnesty's Mobile Verification Toolkit) enumerate installed configuration profiles and MDM state from a backup or FFS extraction:

```bash
# iLEAPP — has a configuration-profiles / MDM artifact module:
python3 ileapp.py -t fs -i "$ROOT" -o /tmp/ileapp_out

# mvt-ios — decrypt a backup, then check modules incl. profiles:
mvt-ios decrypt-backup -p '<backup-password>' -d /tmp/dec ~/path/to/backup
mvt-ios check-backup --output /tmp/mvt_out /tmp/dec
# (mvt's profile output names installed/configuration profiles; review for an MDM payload)
```

**Read management state from a *cooperating* live device (walkthrough — needs a device + pairing).** With a paired, unlocked device, `pymobiledevice3` exposes the `MCInstall` profile service and a `sysdiagnose` capture:

```bash
# Device-bound; shown for completeness, requires a real paired device:
pymobiledevice3 profile list                      # installed profiles incl. MDM
pymobiledevice3 syslog live | grep -Ei "mdmd|profiled|cloudconfigurationd"
```

## 🧪 Labs

> All labs are device-free. Labs 1–2 use only a Mac and a sample `.mobileconfig`. Lab 3 uses a **public sample full-file-system image** for the device-only management plists. Labs 4–5 are **read-only walkthroughs** of irreducibly device-bound flows.

### Lab 1 — Dissect an MDM enrollment profile (Mac only; no device)

**Substrate:** a sample/signed `.mobileconfig` on the Mac. **Fidelity caveat:** none needed — profile parsing is identical to a real enrollment profile; you're reading the exact bytes a device would.

1. Obtain a sample enrollment `.mobileconfig` (any MDM vendor's demo, MicroMDM's test fixtures, or one you export from a free MDM trial). Run `security cms -D -i it.mobileconfig -o it.plist` to strip the CMS signature, then `plutil -p it.plist`.
2. Find the payload with `"PayloadType" => "com.apple.mdm"`. Record `ServerURL`, `CheckInURL`, `Topic`, and whether `SignMessage` is true.
3. Note the *other* payloads bundled with it (an SCEP/ACME identity payload, a root CA, restrictions). Explain why the SCEP/ACME payload must install *before* the MDM payload (the device needs its identity cert to mutual-TLS to the server).

### Lab 2 — Decode the AccessRights bitmask (Mac only; no device)

**Substrate:** the `AccessRights` value from Lab 1. **Fidelity caveat:** none.

1. Run the Python decoder against your profile's `AccessRights`. Which capabilities did this server request?
2. Compute the value for a "least-privilege, query-only" MDM (inspect profiles + device info + inspect apps, nothing destructive) and confirm it equals `1 + 16 + 256 = 273`.
3. Explain why a real enterprise MDM almost always requests the *full* mask, and what that means for the device's threat model the moment it enrolls (lock + erase + clear-passcode are all on the table).

### Lab 3 — Reconstruct management state from a sample image (public sample image)

**Substrate:** a public iOS reference full-file-system image (Josh Hickman's thebinaryhick.blog / Digital Corpora, or the iLEAPP test data). **Fidelity caveat:** the Simulator **cannot** produce these — there is no MDM client, `mdmd`/`profiled`/`cloudconfigurationd`, or supervision bit in CoreSimulator, so the `systemgroup.com.apple.configurationprofiles` store does not populate. Use a real device image.

1. Navigate to `…/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/`. List what's present.
2. `plutil -p` the `MDM.plist` / `CloudConfigurationDetails.plist` if present. Is the device managed? Supervised? Can you name the organization and `ServerURL`?
3. Run **iLEAPP** against the image and find its configuration-profiles output. Compare it to your hand-parse — did the tool surface the same management facts? (If your sample image is an *unmanaged* personal device, that's the expected and instructive result: an empty/absent MDM store = no management, and you should be able to state that confidently.)

### Lab 4 — ADE enrollment, read-only walkthrough (no device)

**Substrate:** Apple Business Manager docs + an MDM vendor's ADE setup guide. **Fidelity caveat:** narration only; performing ADE needs an ABM org, an MDM server, and a factory-fresh/wiped device.

1. Write the ADE chain end to end from the lesson: purchase → serial bound in ABM → assigned to MDM server → Setup-Assistant activation-record pull (`iprofiles.apple.com`) → auto-enroll + supervise (non-removable).
2. State exactly *when* the supervision bit is set and why it cannot be set on an already-set-up personal device without a wipe.
3. Explain the forensic consequence: an examiner wipes a recovered supervised ADE device and walks Setup Assistant — what happens, and why "wiping to clean it" fails to launder its institutional provenance.

### Lab 5 — The host-pairing wall, acquisition impact (read-only reasoning)

**Substrate:** the lesson + libimobiledevice/`pymobiledevice3` behavior. **Fidelity caveat:** the *failure* is device-bound; reason it through rather than provoke it.

1. Describe what `idevicepair pair` exchanges (a pairing record / escrow bag) and why logical/backup acquisition depends on it.
2. Explain why a supervised device with *prohibit host pairing* returns "pairing prohibited by supervisor," and what single artifact would let you pair anyway (the org's supervision identity `.p12`).
3. Decide the triage move: a recovered, powered-on enterprise iPhone shows the "supervised and managed by Acme Corp" banner. List your first three actions in order (RF isolation; document management state; route to Acme/legal for the supervision identity + escrowed unlock/bypass) and justify the ordering against the remote-wipe risk.

## Pitfalls & gotchas

- **"It has a profile" ≠ "it's supervised."** A manually installed company profile is *user-enrolled and removable* with a small capability set. Supervision is a separate bit, set only at ADE/Configurator on a wiped device, and it's what unlocks the heavy surface. Check the supervision state explicitly — don't infer it from the mere presence of an MDM profile.
- **APNs is not the command channel.** Do not look for "the command that came over push." Commands flow device→server over mutual-TLS HTTPS; the push only carries the **PushMagic** wake. Network analysis must watch the device's *outbound* TLS to `ServerURL`.
- **The Simulator has no MDM.** CoreSimulator runs macOS frameworks: no supervision bit, no `mdmd`/`profiled`/`cloudconfigurationd`, no `systemgroup.com.apple.configurationprofiles` MDM store. You can parse `.mobileconfig` *files* on the Mac all day, but you cannot enroll a Simulator or observe device-side management behavior there. Management artifacts are sample-image-only.
- **The remote-wipe race is real and fast.** A managed device that reconnects can receive a queued `EraseDevice` before you finish triage. Treat a managed/supervised device like a Find-My device: **RF-isolate first**. Many "the phone wiped itself in the lab" incidents are a queued MDM command landing the instant Wi-Fi came back.
- **Host pairing may be prohibited.** Don't assume a USB logical extraction will work on an enterprise iPhone. If pairing is supervisor-prohibited, you need the supervision identity from the org — plan the legal request early, not after the extraction fails.
- **Profile-store filenames drift across iOS versions.** `MDM.plist`, `CloudConfigurationDetails.plist`, `MDMEvents.plist`, and the "truth" store are the names to grep for, but Apple reshuffles the `ConfigurationProfiles` directory between releases. Confirm the actual file set on *your* image rather than assuming the path.
- **Don't run Configurator against evidence.** `cfgutil prepare` / Configurator "Prepare" **erases** the device to supervise it. The only safe device interaction here is reading existing state.
- **2026 churn: legacy commands are dying.** Software-update commands/restrictions are removed on the 27.0 platforms, and the Intelligence/Siri/keyboard restriction keys were deprecated at 26.4 in favor of DDM declarations. Artifacts and live behavior you read in 2026 increasingly reflect *declarations*, not the imperative command queue — re-verify against the current build.

## Key takeaways

- **MDM is queue-and-poll; APNs is only a doorbell.** The server queues commands and rings APNs (carrying the **PushMagic** nonce); the device verifies the magic, dials out over **mutual-TLS HTTPS**, and drains the queue one command at a time. No command data ever rides the push.
- **One payload (`com.apple.mdm`) bootstraps everything** — `ServerURL`, `CheckInURL`, `Topic`, and a per-device **identity certificate** (SCEP/ACME) that authenticates every connection. The **check-in** sub-protocol (`Authenticate`/`TokenUpdate`/`CheckOut`) manages the relationship; the `TokenUpdate` carries the `PushMagic` and the **escrowed `UnlockToken`**.
- **Supervision is a separate, elevated trust bit**, set only at **ADE** (zero-touch, non-removable, can't be user-bypassed) or **Apple Configurator** (USB, requires a wipe), and it is the gate to the large restriction set, silent app management, the global proxy, kiosk mode, **Activation Lock bypass**, **host-pairing prohibition**, and Lost Mode.
- **ABM/ASM + ADE (formerly DEP)** bind a device's serial to an organization at purchase; the binding is **sticky across wipes**, so a supervised ADE device re-enrolls after an erase — its institutional provenance can't be laundered.
- **Management rewrites the forensic picture.** A managed device has a remote actor that can **wipe/lock/locate/clear-passcode** — RF-isolate first. Supervision can **prohibit host pairing**, blocking USB logical acquisition unless you hold the org's supervision identity. The `ServerURL` names a subpoena target; the escrowed `UnlockToken`/bypass code are lawful-access leads.
- **Detect management from three layers:** the on-disk `systemgroup.com.apple.configurationprofiles` store (`MDM.plist`, `CloudConfigurationDetails.plist`, `MDMEvents.plist`), the `mdmd`/`profiled`/`cloudconfigurationd` unified-log/sysdiagnose trail, and the Settings/VPN & Device Management banner.
- **Declarative Device Management is the 2026 standard** layered on the same enrollment; legacy software-update and Intelligence/Siri/keyboard restrictions are deprecated/removed (26.4 → 27.0), so modern artifacts increasingly reflect declarations, not commands — see [[declarative-device-management]].

## Terms introduced

| Term | Definition |
|---|---|
| MDM (Mobile Device Management) | Apple's queue-and-poll management protocol: a server queues commands, APNs wakes the device, and the device polls over mutual-TLS HTTPS to retrieve and acknowledge them. |
| `com.apple.mdm` payload | The configuration-profile payload that establishes the management relationship (`ServerURL`, `CheckInURL`, `Topic`, identity cert, `AccessRights`). |
| Check-in protocol | The MDM sub-protocol managing the relationship's lifecycle via `Authenticate`, `TokenUpdate`, and `CheckOut` messages. |
| `TokenUpdate` | Check-in message carrying the APNs `Token`, `PushMagic`, and escrowed `UnlockToken`. |
| PushMagic | A device-generated nonce (sent to the server in `TokenUpdate`) that the server must echo in every APNs push so the device knows the wake-up is legitimate before polling. |
| UnlockToken | An escrowed blob letting the MDM clear the device passcode (`ClearPasscode`) without knowing it. |
| Supervision | An elevated device trust bit (set at ADE or Apple Configurator on a wiped device) that unlocks the large supervised-only management surface. |
| ADE (Automated Device Enrollment) | Zero-touch enrollment via ABM/ASM where a factory-fresh device auto-enrolls and supervises at Setup Assistant; the program formerly called DEP. |
| ABM / ASM | Apple Business Manager / Apple School Manager — Apple's portals for binding devices to an org, assigning ADE, and managing Apple Accounts/licenses. |
| Supervision identity | A certificate + private key (`.p12`) authorizing a host to pair with a supervised device; required to pair when host pairing is prohibited. |
| Activation Lock bypass code | A ~31-byte code an MDM escrows on a supervised device to clear Activation Lock (entered in the password field, blank username); retrievable ~15 days post-supervision. |
| `CloudConfigurationDetails.plist` | On-device ADE activation record naming the controlling organization and MDM server. |
| `mdmd` / `mdmclient` | The MDM client daemon (iOS / macOS) that polls the server and executes commands. |
| `cloudconfigurationd` | The daemon handling cloud configuration / ADE activation-record retrieval. |
| DDM (Declarative Device Management) | The 2026 management standard: the device holds declarations and proactively reports state, displacing the imperative command queue. |

## Further reading

- Apple, *Apple Platform Deployment Guide* (support.apple.com/guide/deployment) — MDM, supervision, ADE/ABM/ASM, Activation Lock, restrictions for supervised devices, "WWDC26 device management updates."
- Apple Developer, *Device Management* (developer.apple.com/documentation/devicemanagement) — the MDM protocol reference: check-in messages (`Authenticate`/`TokenUpdate`/`CheckOut`), command `RequestType`s, the `Restrictions` payload, declarative management.
- Apple, *Apple Platform Security Guide* — MDM trust model, Activation Lock, escrow.
- David Schuetz, "Inside Apple's MDM" (Black Hat US 2011) — the foundational reverse-engineering of the check-in/command protocol and the `AccessRights` bitmask (dated, but the protocol skeleton is intact).
- MicroMDM / NanoMDM (github.com/micromdm, github.com/jessepeterson/nanomdm) — open-source MDM servers; the `mdm` package is a readable, authoritative model of every message type.
- mosen, *Configuration Profiles documentation* (mosen.github.io/profiledocs) — `mdmclient`/`profiled` logging, cloud-config record files, profile internals.
- Fleet, "What is Apple MDM?" and "APNs in MDM" (fleetdm.com/articles) — current 2026 plain-language protocol overview.
- Alexis Brignoni, iLEAPP (github.com/abrignoni/iLEAPP) — configuration-profile / MDM artifact parsing from iOS extractions.
- Amnesty International, mvt (github.com/mvt-project/mvt) — `mvt-ios` profile enumeration from backups/FFS.
- Josh Hickman, thebinaryhick.blog / Digital Corpora — public iOS reference images for the device-only management stores.
- `man security` (the `cms` subcommand), `man plutil`, `man defaults` — Mac-side profile dissection.

---
*Related lessons: [[configuration-profiles-and-mobileconfig]] | [[declarative-device-management]] | [[logical-acquisition-with-libimobiledevice]] | [[passcode-bfu-afu-and-inactivity]] | [[ios-forensics-landscape-and-authorization]] | [[lockdown-mode-and-enterprise-posture]]*
