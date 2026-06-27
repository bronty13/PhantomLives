---
title: "Apple Account, iCloud & APNs"
part: "04 — Networking & Connectivity"
lesson: 07
est_time: "45 min read + 15 min labs"
prerequisites: [advanced-protections-lockdown-sdp-adp, the-ios-networking-stack]
tags: [ios, networking, apple-account, icloud, apns, ids, forensics]
last_reviewed: 2026-06-26
---

# Apple Account, iCloud & APNs

> **In one sentence:** Every iPhone is, at the network layer, an *identity terminal* — a single Apple Account binds the whole device to Apple's cloud, `apsd` holds one persistent TLS pipe that wakes every app, IDS publishes the per-device keys that make iMessage end-to-end encrypted, and the tokens that authenticate all of it sit on disk where the cloud-acquisition examiner can lift them.

## Why this matters

On macOS the Apple Account is a *property of a local user account* you studied as one artifact among many. On iOS the relationship inverts: **the device is the primary account holder.** One Apple Account owns the phone, and that account is the hub the entire cloud surface hangs from — Photos, Messages, Backup, Find My, Keychain, MDM check-in, even the iMessage key directory. For a forensic examiner this is the single highest-leverage pivot: the account artifacts on disk (the `Accounts*.sqlite` store, `MobileMeAccounts.plist`, the Grand Slam tokens in the keychain) are what a tokenized cloud acquisition runs *on top of* — they let a tool impersonate the trusted device and pull synced data without ever re-passing two-factor auth. And whether that pull succeeds at all is governed by one toggle — Advanced Data Protection — that re-draws the entire end-to-end-encryption coverage map. This lesson is the account/iCloud/push layer as mechanism: the daemons, the tokens, the persistent connection, the key directory, and the on-disk residue each leaves.

> ⚖️ **Authorization:** Cloud acquisition is legally distinct from on-device acquisition. Lifting Apple Account tokens to pull a suspect's iCloud is a *search of Apple's servers via the device's credentials* — it almost always requires its own legal authority (warrant scope covering remote/stored cloud content, often a separate Apple Legal Process request), and in many jurisdictions the token-replay technique sits in contested territory. Know your warrant's scope before you authenticate as someone else's device.

## Concepts

The whole layer, one picture — identity at the bottom, three consumers on top, on-disk residue at every node:

```
                    ┌──────────────────────────────────────────┐
   AUTH / IDENTITY  │  Apple Account (DSID) ── handles (☎/✉)     │
                    │  akd → GrandSlam tokens + anisette/ADI      │  ← keychain + Accounts4.sqlite
                    └───────────────┬──────────────────────────-─┘
                                    │ (tokens authenticate everything above)
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                            ▼
   iCLOUD MESH                  PUSH (apsd)                  IDENTITY (IDS)
   cloudd / bird / CKKS    one TLS pipe :5223→:443      identityservicesd
   Photos Drive Notes      multiplexes ALL push          iMessage/FaceTime
   Health Keychain Backup  silent/VoIP/MDM/location      per-device keys (PQ3)
        │                           │                            │
   E2EE map × ADP           courier (re)connect           handle↔device dir
   = what LE can pull       = device-online markers        + Contact Key Verif.
```

### The Apple Account model — the device is the account holder

Apple renamed **Apple ID → Apple Account** with the 2024 OS wave (iOS 18 / macOS 15); the branding changed, the plumbing did not. Underneath the email/phone-number handles is a stable numeric identifier, the **DSID** (the account's directory/destination services ID) — that integer, not the email address, is the account's true primary key everywhere in the cloud. An Apple Account can have many *handles* (one primary email, additional reachable emails, verified phone numbers) but exactly one DSID.

On iOS the account is provisioned **device-wide**: Settings → [Your Name] signs the entire device into iCloud, and per-app entitlements then ride that one account. Compare macOS, where iCloud is keyed to a *local UNIX user* — two macOS users on one Mac have two separate `~/Library/Accounts` stores. iOS is single-user, so there is one account store at the device level.

The account subsystem is the **Accounts framework** (`ACAccountStore` to developers), backed by the daemon **`accountsd`**. It does not store *just* the Apple Account — it is the registry for *every* account on the device: the iCloud account, IDS (the iMessage/FaceTime identity), CardDAV/CalDAV, Exchange, third-party OAuth accounts apps register. Each is an `ACAccount` with a *type* (`com.apple.account.iCloud`, `com.apple.account.AppleAccount`, `com.apple.account.IDS`, `com.apple.account.CardDAV`, …) and a set of *data classes* it owns (mail, contacts, calendars, CloudKit, …).

> 🖥️ **macOS contrast:** Same framework, same daemon, same SQLite schema, same `MobileMeAccounts.plist` keys — you already dissected these on macOS. The only structural difference is scope: macOS `~/Library/Accounts/Accounts4.sqlite` is per-user; iOS `/private/var/mobile/Library/Accounts/Accounts4.sqlite` is the whole device. The query you wrote on macOS runs unchanged against an iOS extraction.

### The account/identity daemon constellation

One Apple Account is serviced by a small constellation of cooperating daemons. Knowing which one owns which job tells you which log subsystem to query and which on-disk store to pull:

| Daemon | Framework | Role |
|---|---|---|
| `accountsd` | Accounts | The account registry/store (`ACAccountStore`) — every account, its type, data classes |
| `akd` | AuthKit | GrandSlam authentication, two-factor, anisette generation |
| `apsd` | ApplePushService | The single persistent push connection; device + per-app tokens |
| `identityservicesd` | IDS | iMessage/FaceTime key directory + push routing ("Madrid") |
| `cloudd` | CloudKit | Record-based cloud sync (Photos, Notes, Health, third-party) |
| `bird` | CloudDocs | iCloud Drive / document sync |
| `searchpartyd` | — | Find My (offline-finding BLE mesh; see [[05-find-my-and-the-ble-mesh]]) |
| `secd` / `securityd` | Security | iCloud Keychain (CKKS) syncing + escrow client |
| `gamed`, `nsurlsessiond` | GameKit / Foundation | Game Center identity; background CloudKit/asset transfers |

### AuthKit, two-factor, and trusted devices

Authentication is **AuthKit**, daemon **`akd`** (`/System/Library/PrivateFrameworks/AuthKit.framework/.../akd`). When you sign in, AuthKit runs Apple's **Grand Slam Authentication (GSA)** handshake: a modified **SRP-6a** mutual authentication (so the password is never sent), then a two-factor challenge that pushes a 6-digit code to the account's *trusted devices*.

A **trusted device** is one already inside the account's **trust circle** — it can both *display* an incoming 2FA code and *generate* one locally (the 6-digit codes in Settings are computed on-device from a per-device secret, not fetched). This is Apple's **HSA2** (two-factor) scheme, distinct from the legacy "two-step verification" it replaced. The account also carries trusted **phone numbers** (SMS/call fallback), an optional **recovery key** (a 28-character code that, once enabled, *disables* Apple-assisted account recovery — making the account unrecoverable without it), **recovery contacts**, and **legacy contacts** (post-mortem access). Two-factor is mandatory for any account that wants iCloud Keychain, ADP, or modern services.

The trust circle is also the membership set for **iCloud Keychain syncing**: joining the circle requires approval from an existing member device *and* knowledge of the device passcode/iCloud Security Code, which is what gates the escrow recovery path (see *iCloud Keychain escrow* below).

The forensic consequence of "trusted device": **once a machine is trusted, it can mint the second factor itself.** That is exactly the property token-replay acquisition abuses (next section). A seized, signed-in, trusted Mac or unlocked iPhone is therefore not just a data source — it is a *standing 2FA authenticator* for the whole account.

### Grand Slam tokens and anisette data — the cloud-acquisition fulcrum

After a successful GSA login, the server issues a bundle of **GrandSlam tokens** (a master `GsIdMS` token plus per-service tokens). These are what subsequent requests to iCloud services present instead of the password. They are persisted in the **keychain** (items in the `com.apple.gs.*` / AuthKit service space) and referenced from the account store.

But a token alone is not enough to look like a trusted device. Apple binds each authenticated session to the *specific machine* via **anisette data** — a small bundle of headers AuthKit attaches to every request:

| Header | Meaning | Stability |
|---|---|---|
| `X-Apple-I-MD-M` | **Machine ID (MID)** — derived from the device's one-time **ADI** provisioning | Per-device, long-lived |
| `X-Apple-I-MD` | **One-time password (OTP)** generated from the provisioned ADI seed (TOTP-like) | ~30 s validity |
| `X-Apple-I-MD-RINFO` | Routing info | Stable |
| `X-Mme-Device-Id` | Device **UDID** | Per-device |
| `X-Apple-I-SRL-NO` | Device **serial number** | Per-device |

The **ADI** provisioning (Apple doesn't publicly expand the acronym) is a one-time session that seeds an on-device generator; the cross-platform anisette tooling (Provision / pypush / AltServer) exposes the resulting blob at `~/.adi/adi.pb` on a Mac, while genuine macOS keeps the equivalent under `akd`/AOSKit management and iOS holds it inside the protected data partition / keychain-adjacent storage. The OTP is regenerated locally every ~30 s from that seed, exactly like a TOTP authenticator — which is *why* a trusted device never re-prompts for a code.

> 🔬 **Forensics note:** This is the mechanism behind **tokenized cloud acquisition** (Elcomsoft Phone Breaker, others). A tool that lifts the GrandSlam tokens *and* can reproduce valid anisette (because it ran on, or extracted the ADI/machine binding from, the suspect's trusted computer or device) authenticates to iCloud **as that trusted device, with no password and no 2FA prompt.** Extract the tokens + anisette from a seized, signed-in Mac or an unlocked iPhone image, and the cloud opens. This is why the account artifacts below are the bridge to [[06-icloud-acquisition-and-advanced-data-protection]]: the on-disk tokens are the cloud key.

> ⚠️ **ADVANCED:** Replaying another person's GrandSlam tokens authenticates *as them* to live Apple servers and can trigger account-security signals, new-device emails to the subject, or token revocation. It is a live network action against a third party's account — never a sandbox. Do it only inside explicit legal authority, on a forensic copy of the token material, with the network consequences understood.

### Sign-in, sign-out, and account switching

A device's account history is rarely a single clean line. Each transition leaves distinct residue:

- **Sign-in** adds an `iCloud`-type row to the account store (with its `date_added`), provisions GrandSlam tokens into the keychain, enables the chosen data classes, and registers IDS handles. The first sign-in also runs the one-time **ADI provisioning** that seeds anisette.
- **Sign-out** tears down the active account and its data classes and revokes tokens server-side — but on-device **remnants persist**: stale account-store rows, orphaned keychain items, cached IDS state, and CloudKit caches can survive until overwritten. A "clean" `MobileMeAccounts.plist` does not mean the device was never signed into a different account.
- **Account switching** (sign out of A, into B) layers B's current state over A's residue. Correlating `Accounts4.sqlite` `date_added`/removal timing with keychain item creation dates and unified-log auth events can reconstruct the switch.
- **Activation Lock** is the sticky one: signing out of iCloud does *not* by itself clear Find My / Activation Lock binding, which ties the *hardware* to the account at the SEP/`mobileactivationd` level — a critical fact when a seized device is account-locked. See [[05-find-my-and-the-ble-mesh]].

> 🔬 **Forensics note:** The gap between an account-store row's `date_added` and the *device's* setup/first-boot time is a strong "was this device re-signed-in or restored?" signal. A late `date_added` on the iCloud account, against an old device, suggests a sign-out/sign-in or a restore-from-backup event worth explaining on the timeline.

### The iCloud service mesh — CloudKit and friends

"iCloud" is not one protocol; it is a mesh of sync engines sharing the one account:

```
                         Apple Account (DSID)
                                 │
        ┌────────────┬───────────┼───────────┬──────────────┐
     cloudd        bird      identityservicesd  searchpartyd  (per-app)
    (CloudKit)  (CloudDocs/    (IDS: iMessage/   (Find My)    daemons
        │        iCloud Drive)  FaceTime keys)       │
   ┌────┴────┐        │              │               │
 Photos  Notes/    Drive files   key directory   FindMy beacons
 Health  Reminders  & app docs   + push routing   (BLE mesh)
 (CKKS keychain sync = separate escrow path)
```

- **`cloudd`** — the **CloudKit** daemon. App data modeled as CloudKit records (Photos, Notes, Reminders, Health, many third-party apps) syncs through here.
- **`bird`** — **CloudDocs / iCloud Drive**: file-backed documents and the `~/Library/Mobile Documents` namespace.
- **iCloud Keychain** syncs through a *separate* path — **CKKS** (CloudKit Keychain) for the device-to-device sync, plus **iCloud Keychain escrow** for recovery. It is not "just another CloudKit container."
- **`identityservicesd`** (IDS) and **`searchpartyd`** (Find My) are covered below / in [[05-find-my-and-the-ble-mesh]].

#### CloudKit: the sync data model

Most modern iCloud sync rides **CloudKit**. The data model the examiner should carry: each app has a **container** (`iCloud.<bundle-id>`); a container holds a **private database** (the user's own data, keyed to their account), a **shared database** (records others shared *to* them), and a **public database** (app-global). Data is grouped into **zones** of **`CKRecord`s** (typed key/value records with references and `CKAsset` file attachments). Sync is **push-driven**: when a record changes server-side, CloudKit sends an APNs push (topic in the CloudKit space) that wakes `cloudd`/`bird` to fetch the delta — i.e., *the iCloud sync engine is itself an APNs client*. iCloud Keychain is the special case: its records sync through **CKKS** with end-to-end encryption that CloudKit servers never see in plaintext.

> 🔬 **Forensics note:** CloudKit's separation of *private* vs *shared* databases matters for attribution. A record in the **shared** database originated on *another* account and was shared in — do not attribute shared-database content to the device owner without checking provenance. On disk, `cloudd`'s caches and the per-app CloudKit metadata (under each app's container and `~/Library/Caches`-equivalent paths) can reveal what synced and when even before you reach the cloud.

#### The Cloud Key Vault — the escrow boundary

Synced keychain secrets recover through the **Cloud Key Vault**, a cluster of tamper-hardened **HSMs**. The wrapped escrow record is encrypted to an **RSA-2048** public key held only inside those HSMs. To recover, a device proves knowledge of the user's **iCloud Security Code** (in practice the **device passcode**) to the HSM cluster via **SRP** — *the code itself never leaves the device*. The firmware enforces a hard limit: **10 wrong attempts and the HSM destroys the escrow record**, permanently. The administrative smart-cards that could reflash that firmware were physically destroyed (Apple's Ivan Krstić demonstrated this at Black Hat 2016), so even Apple cannot lift the attempt cap or extract the key.

> 🔬 **Forensics note — the escrow is a one-way ratchet against brute force.** This is the hard wall behind "iCloud Keychain is E2EE." You cannot grind the iCloud Security Code in the cloud: the 10-try HSM limit means a passcode-guessing attack against escrow self-destructs the record. Recovering synced keychain secrets from the cloud therefore requires the **actual device passcode** (or membership in the trust circle from another device), not compute. Practically, on-device keychain extraction from an **AFU** image is the productive path; the cloud escrow path needs the passcode you'd have used on the device anyway.

#### The end-to-end-encryption coverage map

The forensically decisive question for any category is: **does Apple hold a key it could be compelled to use?** Three tiers (verify exact membership against Apple's *iCloud data security overview*, support.apple.com/en-us/102651 — the list grows each release):

| Tier | Examples | Can Apple decrypt? |
|---|---|---|
| **End-to-end encrypted (always, "standard" default)** | Passwords & **iCloud Keychain**, **Health**, **Home**, **Messages in iCloud**¹, Payment info, Apple Card, Maps, Memoji, Screen Time, Siri info, QuickType learned vocabulary, **Wi-Fi passwords**, W1/H1 Bluetooth keys, Journal (17.2+) | **No** — keys only on the user's trusted devices |
| **Server-key-held (standard) → E2EE only under ADP** | **iCloud Backup**, **iCloud Drive**, **Photos**, **Notes**, **Reminders**, **Voice Memos**, **Safari bookmarks**, Wallet passes, Freeform | **Standard: yes** (Apple HSM holds the key) → producible to LE. **ADP: no** |
| **Never E2EE (interop standards)** | **iCloud Mail**, **Contacts**, **Calendars** | **Yes**, regardless of ADP |

¹ The Messages-in-iCloud caveat is the trap every examiner must internalize — see below.

Apple's published counts: **14 categories E2EE by default; 23 with ADP** (Apple's stated figures since the 2022 launch — the support doc grows each release, so re-verify against 102651). The three interop categories (Mail/Contacts/Calendars) are *never* E2EE because they must speak SMTP/CardDAV/CalDAV to the outside world.

> 🔬 **Forensics note — the Messages-in-iCloud backup-key trap:** "Messages in iCloud" is listed as end-to-end encrypted *by default*. But if **iCloud Backup is ON and ADP is OFF**, the backup deliberately **includes a copy of the Messages-in-iCloud encryption key** so Apple can help you recover messages after losing all devices. That copy is in a backup Apple *can* decrypt. **Net effect: with the default settings on the vast majority of phones, Apple can produce iMessage content to law enforcement** — not by breaking the E2EE Messages container, but by handing over the key that rode along in the backup. Turning on ADP makes the backup (and therefore that key) E2EE, and the path closes. This single nuance decides whether an iCloud warrant returns messages or ciphertext.

### Advanced Data Protection re-draws the map

[[09-advanced-protections-lockdown-sdp-adp]] covers ADP in depth; here is the networking/account-layer consequence. **ADP moves the "server-key-held" tier into E2EE** — iCloud Backup, Drive, Photos, Notes, Reminders, and the rest lose their Apple-held keys, and the key escrow shifts entirely to the user's trusted devices (with a user-set Recovery Key / Recovery Contact as the only fallback). After that:

- A backup-content or Photos warrant served on Apple returns **encrypted blobs Apple cannot decrypt**.
- Tokenized acquisition still *authenticates*, but downloads ciphertext — useless without device-side keys.
- The only three categories still producible are **Mail, Contacts, Calendars**, plus pure account metadata (when account created, connected devices, sign-in IPs).

So the examiner's very first cloud-side question is **"Is ADP on?"** — it is the difference between a rich cloud pull and three address-book categories.

### APNs — the one persistent connection that wakes everything

Every push on iOS rides **one** connection. **`apsd`** (the Apple Push Service daemon, `/System/Library/PrivateFrameworks/ApplePushService.framework/apsd`) opens and *maintains* a single persistent **TLS connection** to a **courier** server — `N-courier.push.apple.com` — on **TCP 5223** (falling back to **443** when 5223 is blocked, e.g., captive Wi-Fi). That one socket multiplexes push for *all* apps and system services:

```
   App A   App B   Mail   MDM   Find My   iMessage(IDS)
     │       │       │      │       │          │
     └───────┴───────┴──apsd┴───────┴──────────┘
                       │  (one persistent TLS, :5223 → :443 fallback)
                       ▼
            N-courier.push.apple.com  (APNs)
```

Two kinds of token live here:

- **Device push token** — the device's identity to APNs, established when `apsd` connects. Routes *to this device*.
- **Per-app push token** — minted when an app calls `registerForRemoteNotifications`; APNs returns a token the app ships to *its own provider server*. A provider sends a push by POSTing (HTTP/2 to `api.push.apple.com`) to that token; APNs fans it down the device's one connection. The push **topic** is the app's bundle ID.

**Silent / background push** (`content-available: 1`, no alert) wakes a backgrounded app for a short execution window (~30 s) to fetch data — the backbone of Background App Refresh, MDM "poke-then-pull" check-ins, and Find My commands. **PushKit** (VoIP) and the **Notification Service Extension** are higher-tiers on the same pipe.

The **provider side** is decoupled and modern: a provider authenticates to APNs (either a `.p8` **token-based JWT** signed with an APNs auth key, or the legacy per-app TLS certificate) and **POSTs HTTP/2** requests to `api.push.apple.com:443` (sandbox: `api.sandbox.push.apple.com`), one stream per notification, addressed by the device's per-app token with an `apns-topic` header. Key headers carry forensically-meaningful intent:

| APNs concept | Detail |
|---|---|
| `apns-topic` | The push **topic** = the app's **bundle ID** (with suffixes like `.voip`, `.complication`, `.pushkit.fileprovider` for special push types) |
| `apns-priority` | **10** = immediate/alerting; **5** = power-considerate (silent/background); **1** = low |
| `apns-push-type` | `alert`, `background`, `voip`, `location`, `complication`, `mdm`, `fileprovider`, … — each gated by an **entitlement** |
| Special entitlements | **VoIP** (PushKit), **background location** pushes, **MDM** (`com.apple.mgmt.*` topic), and Critical/Time-Sensitive alerts are privileged push classes apps must be entitled for |

So the *type* of push an app can receive is an entitlement fingerprint: an app subscribed to the `location` push type can be silently woken to report location; a `voip` subscriber can be launched into the background to ring. That capability map is itself investigative signal.

> 🖥️ **macOS contrast:** Byte-for-byte the same `apsd`, same courier, same 5223. On macOS `apsd` keeps its push certificates in a private keychain at **`/Library/Keychains/apsd.keychain`** — a detail you can inspect right now on your Mac. iOS keeps the equivalent material in the protected keystore. The mechanism the learner saw driving macOS Continuity/iMessage/MDM is *the same daemon* doing the same job on the phone; iOS just leans on it harder (it is the wake source for nearly everything).

> 🔬 **Forensics note:** `apsd`'s persistent connection and topic subscriptions are a *device-activity* signal. In the unified log (`process == "apsd"`) you can see courier (re)connections — which double as **network-availability / wake markers** — and the set of subscribed topics, i.e., **which apps and services were push-active**. Cross-reference these against [[01-knowledgec-db-deep-dive]] and [[03-powerlog-and-aggregate-dictionary]] to corroborate a pattern-of-life timeline. (Token *values* in the log are typically redacted.)

### IDS — the key directory behind iMessage and FaceTime

**Identity Services (IDS)**, daemon **`identityservicesd`**, is Apple's **public-key directory and routing layer** for end-to-end-encrypted communication — primarily **iMessage** and **FaceTime**. It is the piece that makes "send a blue bubble to an email address" work securely:

```
 1. Each of your devices registers its HANDLES (phone #, emails) with IDS,
    publishing  [per-device public keys]  +  [APNs push token].
 2. To message bob@icloud.com, your device QUERIES IDS for that handle.
 3. IDS returns Bob's set of devices: each device's public key + push token.
 4. Your device encrypts the message ONCE PER recipient device, then hands
    each ciphertext to apsd → APNs delivers to that device's push token.
```

iMessage encryption is therefore *per-recipient-device*: add a new iPad, and senders must re-query IDS to learn its key before it can decrypt new messages. The integrity weak point is step 2/3 — historically you *trusted* IDS to return the right keys. **Contact Key Verification** (CKV, iOS 17.2+) closes that: device keys are entered into a verifiable **Key Transparency** log so a silently-added ("ghost") device shows up as a verification-code mismatch.

**The crypto on the wire — PQ3.** The original iMessage scheme was a static per-device RSA-encrypt + ECDSA-sign construction. Since **iOS/iPadOS 17.4 / macOS 14.4 (2024)** iMessage uses **PQ3**, the first messaging protocol Apple classifies at **"Level 3" security** (post-quantum in *both* initial key establishment *and* ongoing rekeying). PQ3 is a **hybrid**: classical **ECDH (P-256)** combined with a post-quantum **KEM (Kyber / ML-KEM)** — **Kyber-1024** for each device's long-term/initial key establishment, **Kyber-768** for the **continuous key ratchet** that rekeys the ongoing conversation (the smaller parameter holds down the per-message overhead of frequent rekeying) — so a compromised key heals forward automatically. (Apple shipped PQ3 with Kyber in 17.4, ahead of NIST's FIPS 203 ML-KEM finalization.) The forensic takeaway is durable: **iMessage content is not recoverable from intercepted ciphertext** even with future quantum capability; you recover messages from an *endpoint* (`sms.db` on the device) or from a *standard, non-ADP iCloud backup* (whose embedded Messages key Apple holds), never from the transport.

The **internal service name for iMessage is "Madrid"** (`com.apple.madrid`) — you will see it in IDS logs and registration dumps. FaceTime and the IDS handle-registration flows are siblings on the same daemon.

> 🔬 **Forensics note:** IDS state answers *which handles and which devices belong to this account*. The registration data and `IDStatusCache`-style plists record handle→device mappings and the last-known capabilities/keys of correspondents — useful for proving an account controlled a given phone number/email, and for enumerating the suspect's other devices. iMessage *content* lives in `sms.db` (see [[04-communications-imessage-and-sms]]); IDS gives you the *identity and routing* metadata around it.

### The account/identity artifact map

Pulling the forensic threads together — where each subsystem's residue lands on an iOS extraction (paths under `/private/var/mobile/`):

| Artifact | Path (under `/private/var/mobile/`) | What it proves |
|---|---|---|
| **Accounts store** | `Library/Accounts/Accounts4.sqlite` (iOS 10+; `Accounts3.sqlite` on older) | Every account: Apple Account/iCloud, IDS, mail/cal, third-party — type, username, date added, owning bundle |
| **iCloud account summary** | `Library/Preferences/MobileMeAccounts.plist` | Primary Apple Account email, **DSID**, `LoggedIn` state, and the **enabled services** list (Photos, Find My, Keychain, Backup…) |
| **GrandSlam tokens / anisette binding** | keychain (`com.apple.gs.*` / AuthKit items) + ADI material | The cloud-acquisition credentials — replayable to authenticate as the device |
| **APNs tokens / topics** | `apsd` state + `Library/Preferences/com.apple.apsd.plist` (exact DB filename varies by version — verify) | Push-active apps/services; connection/wake markers in the unified log |
| **IDS / iMessage identity** | IDS stores + `IDStatusCache`-style plists | Handle↔device mappings; the account's other devices; correspondent capabilities |
| **System account presence** | `Library/Preferences/SystemConfiguration/com.apple.accounts.exists.plist` | Quick overview of which account *types* are configured |

> 🔬 **Forensics note — `MobileMeAccounts.plist` is the fast win.** It is a small, unencrypted (in an AFU/decrypted image) property list that names the account owner's primary email and DSID and lists exactly which iCloud services were enabled — Photos on? Backup on? Find My on? Keychain on? That tells you *before you touch the cloud* what a successful tokenized acquisition could even contain, and the DSID is the join key to correlate Apple Legal Process returns against the device.

### What the account layer proves — the forensic synthesis

Pulled together, this single subsystem answers a remarkable number of an examiner's questions *before any cloud round-trip*:

| Investigative question | Where the account layer answers it |
|---|---|
| **Who owns/owned this device?** | `MobileMeAccounts.plist` (primary email + DSID); `Accounts4.sqlite` iCloud row; the iCloud account's `date_added` |
| **What other devices belong to this person?** | IDS handle↔device registrations; the trust circle; account metadata from an Apple Legal Process return (keyed by DSID) |
| **What identities (phone/email) did they communicate under?** | IDS registered handles; the `IDS`-type rows in the account store |
| **What is reachable in the cloud, and is it plaintext?** | `MobileMeAccounts.plist` enabled-services list **×** ADP status **×** the E2EE coverage map |
| **Can I do a tokenized cloud pull at all?** | Presence of valid GrandSlam tokens (keychain) + reproducible anisette/ADI binding; lock state (AFU vs BFU) |
| **When was the device online / push-active?** | `apsd` courier (re)connect markers + subscribed topics in the unified log |
| **Is iMessage content recoverable, and from where?** | PQ3 on the wire (no) → endpoint `sms.db` (yes) → standard non-ADP backup (yes, via embedded key) → ADP backup (no) |

This is the lesson's payload: the account/iCloud/push layer is simultaneously an **attribution engine**, a **cloud-scope map**, and the **credential bridge** to remote acquisition.

## Hands-on

There is **no on-device shell**. Everything below runs **on the Mac** — against your Mac's own (schema-identical) account daemons, against a parsed iOS extraction, or against a public sample image. Copy-before-query discipline applies to every SQLite database (a bare `SELECT` write-locks the file and spawns `-wal`/`-shm`).

**Read the account store (Mac analogue of the iOS file — identical schema):**

```bash
# Copy first — never query the live store in place
cp ~/Library/Accounts/Accounts4.sqlite /tmp/acc.db

sqlite3 /tmp/acc.db "
SELECT
  at.ZACCOUNTTYPEDESCRIPTION              AS type,
  a.ZUSERNAME                             AS username,
  a.ZACCOUNTDESCRIPTION                   AS descr,
  a.ZOWNINGBUNDLEID                       AS owner_bundle,
  datetime(a.ZDATE + 978307200,'unixepoch','localtime') AS date_added
FROM ZACCOUNT a
LEFT JOIN ZACCOUNTTYPE at ON a.ZACCOUNTTYPE = at.Z_PK
ORDER BY a.ZDATE;"
# Apple Account → type 'iCloud'; iMessage/FaceTime → type 'IDS'; plus any CardDAV/Exchange/OAuth.
# NOTE: column names (ZDATE/ZACCOUNTDESCRIPTION) drift across OS versions — confirm with .schema ZACCOUNT.
```

The `978307200` constant converts **Apple Mac Absolute Time** (epoch 2001-01-01) to Unix — the same epoch the macOS artifacts lesson hammered.

**Read the iCloud account summary:**

```bash
plutil -p ~/Library/Preferences/MobileMeAccounts.plist
# Accounts → [ { AccountID = "user@icloud.com"; AccountDSID = 000123456789;
#                LoggedIn = 1; Services = ( {Name=...CloudKit}, {Name=FindMyiPhone}, ... ) } ]
```

**Watch the push spine live (`apsd` is the same on your Mac):**

```bash
# Confirm the persistent connection and its port
lsof -nP -p "$(pgrep -x apsd)" | grep -E '5223|443'
nettop -P -p "$(pgrep -x apsd)"            # live throughput on apsd's sockets

# Courier (re)connections + topic activity — wake/availability markers
log stream --predicate 'process == "apsd"' --info
# …Connected to courier 1-courier.push.apple.com…  / topic-enable for <bundle ids>

# apsd's private push-certificate keychain (macOS)
security dump-keychain /Library/Keychains/apsd.keychain 2>/dev/null | head
```

**Inspect IDS / iMessage identity activity:**

```bash
log show --last 1d --predicate 'process == "identityservicesd"' --info \
  | grep -iE 'register|lookup|madrid|handle' | tail -40
```

**Surface the GrandSlam / AuthKit token residue in the keychain (Mac):**

```bash
# Metadata only — labels/services of GS / AuthKit items, no secret extraction
security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null \
  | grep -iE 'svce|labl' | grep -iE 'gs\.|authkit|grandslam|idms|com\.apple\.account' | sort -u
# On an iOS AFU extraction, the equivalent items live in the decrypted keychain plist
# (keychain-2.db / OBJC keychain dump from the acquisition tool).
```

**Confirm CloudKit/Drive sync daemons and their push wakeups (Mac):**

```bash
pgrep -lx 'cloudd|bird'                                   # the sync daemons
log show --last 2h --predicate 'process == "cloudd" OR process == "bird"' --info \
  | grep -iE 'push|fetch|zone|container' | tail -30        # push-driven delta fetches
```

**Parse the account artifacts out of an iOS extraction (sample image, no device):**

```bash
# iLEAPP has dedicated parsers for the account stores + iCloud prefs
python3 ileapp.py -t fs -i /path/to/extracted_fs -o /tmp/ileapp_out
#   → "Account Data" (Accounts4.sqlite) and "Mobile Backup / iCloud" reports

# mvt-ios likewise surfaces account + iCloud config from a backup/fs dump
mvt-ios check-fs /path/to/extracted_fs -o /tmp/mvt_out
```

## 🧪 Labs

> **Substrate note:** The iOS Simulator does **not** sign into a real iCloud account, runs **no `apsd` push connection**, and performs **no IDS registration** — those are device-only. So these labs use (a) your **Mac's own** schema-identical account/`apsd`/IDS daemons as a high-fidelity stand-in for the *parsing and live-mechanism* skills, and (b) **public iOS sample images** for the device-resident artifacts. Where the Mac stands in for the phone, the *code is the same binary*; the only gap is scope (per-user vs device-wide) and the absence of cellular/SEP-bound key material.

### Lab 1 — Map your account store (Mac account daemon; schema-identical to iOS)

1. `cp ~/Library/Accounts/Accounts4.sqlite /tmp/acc.db`, then run `sqlite3 /tmp/acc.db ".schema ZACCOUNT"` and confirm the real column names on *your* OS version before trusting the query above.
2. Run the join query from Hands-on. Identify the row whose type is `iCloud` (your Apple Account) and the `IDS` row (iMessage/FaceTime identity).
3. Note the `date_added` of the iCloud account. On a phone, that timestamp is a useful "account first configured on this device" anchor. *Fidelity caveat: this is a macOS per-user store; an iOS device has one device-wide store at `/private/var/mobile/Library/Accounts/`.*

### Lab 2 — Read the iCloud service map (`MobileMeAccounts.plist`)

1. `plutil -p ~/Library/Preferences/MobileMeAccounts.plist`.
2. Record the **DSID** and the **Services** array. Translate each enabled service into a forensic statement: e.g., *Find My enabled → location-history cloud pull is in scope; Backup enabled → cloud backup may exist; Keychain enabled → iCloud Keychain escrow exists.*
3. Decision drill: for each service, write whether a **standard** (Apple-key) cloud warrant would return plaintext or ciphertext, then redo the column assuming **ADP on**. This is the coverage-map table, applied.

### Lab 3 — Observe the single push connection (`apsd`)

1. `lsof -nP -p "$(pgrep -x apsd)" | grep -E '5223|443'` — confirm exactly **one** courier connection, and which port won (5223, or 443 if your network blocks it).
2. `log stream --predicate 'process == "apsd"' --info` for ~60 s. Watch for `Connected to courier …` and topic-enable lines. Toggle Wi-Fi off/on and watch the *single* reconnection re-establish push for *every* app at once.
3. Write one sentence explaining why, on a phone, a courier reconnect in the log is a defensible **device-was-online** marker. *Fidelity caveat: macOS `apsd`; identical mechanism, but a phone's reconnects also correlate with cellular handoffs and Low Power Mode.*

### Lab 4 — Parse account + iCloud artifacts from a public sample image (read-only walkthrough)

1. Obtain a public iOS reference image (Josh Hickman / thebinaryhick.blog, or the iLEAPP test data set) and extract the file system tree.
2. Run `python3 ileapp.py -t fs -i <tree> -o /tmp/ileapp_out` and open the **Account Data** and **iCloud** reports. Identify the image owner's Apple Account email and DSID *without ever touching a network*.
3. Locate `Library/Preferences/MobileMeAccounts.plist` and `Library/Accounts/Accounts4.sqlite` in the tree and confirm iLEAPP's parse against your own `plutil`/`sqlite3` read. *Substrate: a real device image — this is the faithful one; the Simulator cannot produce it.*

### Lab 5 — Trace an iMessage's identity path (Mac IDS logs)

1. `log show --last 1d --predicate 'process == "identityservicesd"' --info | grep -iE 'lookup|register|madrid'`.
2. Find a `lookup` for a handle and reason about the flow: handle → IDS query → recipient device keys + push tokens → per-device encryption → `apsd`. Note that the *content* never appears here — IDS is identity/routing only.
3. Relate to [[04-communications-imessage-and-sms]]: IDS tells you *who/which devices*, `sms.db` holds *what was said*. Confirm (Settings → [Your Name] → Messages, or the PQ3 logs) that the conversation negotiated PQ3 — proof the transport is post-quantum and that recovery must come from an endpoint or non-ADP backup, never the wire.

### Lab 6 — Build the ADP coverage decision tree (analysis drill)

A device-free reasoning exercise that turns the coverage map into an SOP step. Take a worked scenario: *standard data protection, iCloud Backup ON, Find My ON, Photos syncing.*

1. For each of these categories — iMessage content, Photos, iCloud Drive, Health, Mail, Contacts, Wi-Fi passwords, keychain passwords — write whether a warrant served on Apple returns **plaintext, ciphertext, or nothing**.
2. Flip exactly one variable: turn **ADP on**. Re-derive the same column and mark which categories moved from plaintext to ciphertext.
3. Now flip a *different* single variable from the original: turn **iCloud Backup off** (ADP still off). Explain specifically what happens to the **iMessage** answer and why (the backup-embedded Messages key path).
4. Write the one-line rule you'd put at the top of a cloud-acquisition SOP. *Substrate: pure analysis against the documented Apple model — no device, no image; this is the judgment the artifacts feed.*

## Pitfalls & gotchas

- **"Messages in iCloud is E2EE" is a half-truth.** With the default config (Backup on, ADP off) Apple can produce iMessage content via the backup-embedded key. Do not tell a requesting attorney that iCloud iMessage is unrecoverable until you have confirmed ADP status. (See the forensics note above.)
- **Check ADP *first*.** Every cloud-acquisition plan hinges on it. ADP on collapses a rich pull to Mail/Contacts/Calendars + account metadata. The status is account-level, not visible from most on-device artifacts alone — confirm via the account or an Apple Legal Process return.
- **Token replay is a live action against a third party's account.** It is not "reading a file." It can email the subject, trip security heuristics, and revoke the very tokens you're using. Treat it as a network operation requiring its own authorization.
- **Anisette is machine-bound and time-bound.** Tokens lifted *without* a reproducible anisette/ADI binding will be rejected as coming from an untrusted machine; the `X-Apple-I-MD` OTP also expires in ~30 s. Lifting the token bundle is necessary but not sufficient — the device binding matters.
- **Apple Mac Absolute Time, again.** Account-store timestamps (`ZDATE`) are 2001-epoch — add `978307200`. Mixing this with Unix or WebKit/Cocoa epochs throws timelines off by decades (see [[00-the-ios-timestamp-zoo]]).
- **Port 443 fallback hides APNs.** On a restrictive network `apsd` silently moves to 443; an analyst grepping pcap for "5223 = push" will miss it. Identify APNs by SNI/host (`*-courier.push.apple.com`), not by port alone — relevant in [[02-traffic-interception-and-tls]].
- **Schema and path drift.** `Accounts3 → Accounts4`, `Apple ID → Apple Account`, and exact `apsd`/IDS store filenames have all changed across releases. Confirm `.schema` and actual paths on the target OS version; never write a column name from memory into a report.
- **BFU kills the keychain-bound tokens.** After the 72-hour inactivity reboot drops the device to **BFU** (see [[03-passcode-bfu-afu-and-inactivity]]), keychain-protected GrandSlam material is locked. Token extraction needs an **AFU** (after-first-unlock) or otherwise decrypted state.
- **The DSID, not the email, is the identity.** Email handles and primary addresses can change; the numeric **DSID** is the stable account key. Attribute and join on the DSID, and treat a matching email as corroboration, not proof.
- **A subscribed push topic ≠ active use.** A topic in `apsd`'s subscription set proves an app is *installed and push-registered*, not that the user opened or used it. Treat it as a capability/installation signal and corroborate use from [[01-knowledgec-db-deep-dive]].
- **Shared-database content is not the owner's.** CloudKit's *shared* database holds records others shared *in*. Do not attribute shared-zone content to the device owner without checking provenance.
- **Sign-out leaves residue.** A current, single-account `MobileMeAccounts.plist` does not mean the device was never signed into another account; check account-store remnants, keychain item dates, and Activation Lock state.

## Key takeaways

- On iOS the **device is the account holder** — one Apple Account (keyed by a numeric **DSID**, not an email) binds the whole phone to the cloud, managed by **`accountsd`** with the same Accounts framework you learned on macOS.
- **`akd` / GSA** authenticate via SRP-6a + two-factor; after login the device holds **GrandSlam tokens** in the keychain, bound to the machine by **anisette/ADI** data — together these are the credentials **tokenized cloud acquisition** replays to pull iCloud without a password or 2FA prompt.
- The **iCloud mesh** is many sync engines on one account: `cloudd` (CloudKit), `bird` (Drive), CKKS + escrow (Keychain), IDS, Find My.
- The **E2EE coverage map** is the examiner's compass: **14 categories E2EE by default, 23 with ADP** (Apple's published figures); **Mail/Contacts/Calendars are never E2EE**; and the **Messages-in-iCloud key rides inside a standard backup**, so default-config iMessage is usually cloud-producible.
- **`apsd` maintains one persistent TLS connection** (`*-courier.push.apple.com`, **TCP 5223 → 443 fallback**) that multiplexes push for every app and service; silent pushes wake backgrounded apps and drive MDM/Find My.
- **IDS** (`identityservicesd`, internal name **"Madrid"** for iMessage) is the **public-key directory** that makes iMessage per-device end-to-end encrypted; **Contact Key Verification** adds transparency against ghost-device injection.
- The high-value account artifacts — **`Accounts4.sqlite`**, **`MobileMeAccounts.plist`**, the **GrandSlam keychain tokens**, and IDS handle/device maps — are the on-disk bridge into [[06-icloud-acquisition-and-advanced-data-protection]].

## Terms introduced

| Term | Definition |
|---|---|
| Apple Account | The 2024 rebrand of "Apple ID"; the cloud identity that owns an iOS device. Keyed by a stable numeric **DSID**, with email/phone handles. |
| DSID | Directory/Destination Services Identifier — the numeric primary key of an Apple Account across all cloud services. |
| `accountsd` | Daemon backing the Accounts framework (`ACAccountStore`); registry of every account on the device. |
| `akd` | AuthKit daemon; runs the GrandSlam (GSA) authentication and two-factor flows. |
| Grand Slam Authentication (GSA) | Apple's account-auth protocol (modified SRP-6a + 2FA) that, on success, issues reusable service tokens. |
| HSA2 / trust circle | Apple's current two-factor scheme; the set of trusted devices that can generate codes and approve iCloud Keychain joins. |
| Recovery Key | Optional 28-char code that, once set, disables Apple-assisted recovery — the account becomes unrecoverable without it. |
| GrandSlam tokens | Reusable post-login tokens (master + per-service) stored in the keychain; presented instead of the password. |
| Anisette data | Per-request headers (machine ID, ~30 s OTP, routing info, UDID, serial) that bind a session to a specific trusted machine. |
| ADI | The one-time on-device provisioning that seeds anisette's OTP generator and machine ID (acronym not officially expanded; blob surfaced at `~/.adi/adi.pb` by the cross-platform anisette tooling). |
| CloudKit / `cloudd` | Apple's record-based cloud sync framework and its daemon (Photos, Notes, Health, many apps). |
| CloudKit container / zone / `CKRecord` | The per-app namespace, its record groupings, and the typed records (with `CKAsset` attachments) that sync. Private vs shared vs public databases. |
| `bird` / CloudDocs | The iCloud Drive document-sync daemon and namespace. |
| iCloud Keychain escrow | Passcode-SRP-protected recovery path for synced keychain secrets, guarded by the Cloud Key Vault HSMs. |
| Cloud Key Vault | HSM cluster (RSA-2048-wrapped escrow, SRP-verified, 10-try-then-destroy) backing iCloud Keychain recovery. |
| PQ3 | iMessage's post-quantum protocol (iOS 17.4+): hybrid ECDH (P-256) + Kyber/ML-KEM (Kyber-1024 long-term, Kyber-768 ratchet) with continuous key ratcheting; Apple's "Level 3" security. |
| Push topic | The APNs routing label for a notification — an app's bundle ID, optionally suffixed (`.voip`, `.complication`, …). |
| Advanced Data Protection (ADP) | Opt-in setting that moves the server-key-held iCloud categories (Backup, Drive, Photos, …) into device-only E2EE. |
| APNs | Apple Push Notification service — the cloud push backbone. |
| `apsd` | Apple Push Service daemon; maintains the single persistent TLS connection to a courier and multiplexes all push. |
| Courier | An APNs edge server (`N-courier.push.apple.com`) the device keeps a persistent connection to on TCP 5223 (443 fallback). |
| Push token (device / per-app) | The device's APNs identity, and the per-app token an app hands to its provider for targeted pushes. |
| Silent push | A `content-available` push with no alert that wakes a backgrounded app for a short execution window. |
| IDS / `identityservicesd` | Identity Services — Apple's public-key directory + routing for iMessage/FaceTime end-to-end encryption. |
| Madrid | The internal Apple service name for iMessage (`com.apple.madrid`), seen in IDS logs. |
| Contact Key Verification (CKV) | Key-transparency layer (iOS 17.2+) that exposes silently-added ("ghost") iMessage devices. |
| `MobileMeAccounts.plist` | Property list naming the iCloud account email + DSID and the list of enabled iCloud services. |
| `Accounts4.sqlite` | The Accounts-framework SQLite store (`Accounts3` on older iOS) holding all configured accounts. |

## Further reading

- **Apple** — *iCloud data security overview* (support.apple.com/en-us/102651, the authoritative E2EE category list — re-check each release); *Apple Platform Security guide* (iCloud, iCloud Keychain escrow, ADP, Contact Key Verification, IDS/iMessage crypto); *Escrow security for iCloud Keychain* + *Secure iCloud Keychain recovery* (the Cloud Key Vault / HSM 10-try mechanics); *Intro to Apple identity services* (support.apple.com/guide/deployment); *Use Advanced Data Protection for iCloud* (support.apple.com/en-us/108756); Apple Legal Process Guidelines (US) for what a cloud request actually returns.
- **PQ3 / post-quantum** — Apple Security Research, *iMessage with PQ3: the new state of the art in quantum-secure messaging at scale* (security.apple.com/blog/imessage-pq3); *Quantum-secure cryptography in Apple operating systems* (Apple Platform Security); Ivan Krstić, Black Hat 2016 — "Behind the Scenes of iOS Security" (the destroyed-admin-card Cloud Key Vault disclosure).
- **Developer docs** — User Notifications / "Registering your app with APNs", "Establishing a token-based connection to APNs"; TN2265 (push troubleshooting — the courier/5223 mechanics).
- **GSA / anisette internals** — The Apple Wiki, *Grand Slam Authentication* and *Identity Services*; JJTech's `gsa.py` / **pypush** and Dadoum's **Provision**/libprovision (ADI, anisette, machine provisioning); MathewYaldo's *Apple-GSA-Protocol*; vtky's *AppleID Auth* write-up.
- **Forensics** — Elcomsoft blog, "Apple vs Law Enforcement: Cloudy Times" (tokenized acquisition + anisette) and Phone Breaker docs; Alexis Brignoni **iLEAPP** (account-store + iCloud parsers); **mvt** (mvt-ios); RealityNet **iOS-Forensics-References**; Josh Hickman / Digital Corpora sample images; Sarah Edwards (mac4n6.com) on account/identity artifacts; SANS FOR585.
- **Push/RE** — `mfrister/pushproxy` (apsd MITM, certificate pinning, courier protocol); `man 8 apsd`.
- **Cross-references** — [[06-icloud-acquisition-and-advanced-data-protection]], [[09-advanced-protections-lockdown-sdp-adp]], [[04-communications-imessage-and-sms]], [[02-traffic-interception-and-tls]].

---
*Related lessons: [[06-icloud-acquisition-and-advanced-data-protection]] | [[09-advanced-protections-lockdown-sdp-adp]] | [[00-the-ios-networking-stack]] | [[04-communications-imessage-and-sms]] | [[05-find-my-and-the-ble-mesh]] | [[03-passcode-bfu-afu-and-inactivity]]*
