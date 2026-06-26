---
title: "iCloud acquisition & Advanced Data Protection"
part: "07 — Forensic Acquisition & Imaging"
lesson: 06
est_time: "45 min read + 15 min labs"
prerequisites: [advanced-protections-lockdown-sdp-adp, the-acquisition-taxonomy]
tags: [ios, forensics, icloud, cloud-acquisition, adp, dfir]
last_reviewed: 2026-06-26
---

# iCloud acquisition & Advanced Data Protection

> **In one sentence:** Every iPhone has a second copy of itself in the cloud — an iCloud backup blob plus a constellation of CloudKit-synced containers — reachable three ways (credentials, a stolen auth token, or legal process to Apple), and **Advanced Data Protection** is the single switch that turns most of it end-to-end encrypted and slams all three routes shut for the categories it covers.

> ⚖️ **AUTHORIZED USE ONLY.** Cloud acquisition reaches data that never left Apple's servers and that the account holder may not know is exposed — so it demands authority as clear as any device extraction, plus a *second* layer most physical methods don't: every route here runs against a third party (Apple) or a logged-in machine you've seized, and each carries its own legal instrument. Authenticating to a live iCloud account, replaying a lifted token, or serving legal process on Apple are all *searches* — do none of them without the matching authority (a warrant for content, the correct § 2703 instrument for metadata, consent, or a court order whose scope you have read; [[ios-forensics-landscape-and-authorization]] carries the full legal frame, incl. *Riley v. California*). A forensic login can also notify the subject and mutate the very account you are imaging, so scope *and* sequence matter. The mechanics below are inert facts; the authority to apply them is the whole job.

## Why this matters

When the device is dead, locked in BFU, A14-or-newer (so no BootROM exploit), and you have no passcode, the on-device routes from the rest of Part 07 run out. The cloud is the parallel evidence source that does not care about the device's lock state — and historically it has been the *easier* target, because the account holder, a trusted computer, or a search warrant to Apple could all unlock it. **Advanced Data Protection (ADP) changed the entire calculus.** It is not a setting you can ignore: for a US account with ADP on, the cloud goes dark for backups, Drive, Photos, and Notes simultaneously — third-party extraction tools fail *and* the warrant-to-Apple route returns "we hold no key." For a forensicator, ADP state is the first cloud question you ask, because it decides whether the cloud is a goldmine or a graveyard. This lesson is the mechanism: what is up there, how the encryption tiers actually work, the three authentication routes, what a warrant to Apple yields versus what a token yields, and the policy fault line (the 2025 UK episode) that now makes *jurisdiction* part of the answer.

## Concepts

### Two clouds in one account: backup vs. synced data

"iCloud" is two structurally different evidence stores sharing one Apple Account. Conflating them is the first beginner error.

**iCloud Backup** is a *point-in-time blob* — a nightly snapshot of a single device, taken when it is locked, charging, and on Wi-Fi. It is the cloud twin of an iTunes/Finder backup (see [[the-itunes-finder-backup-format]]). It contains the camera roll, app container data, device settings, the Home-screen layout, SMS/MMS and (if escrowed) iMessage, visual voicemail, call history, and ringtones. One device → one backup chain of dated snapshots. It answers *"what did this phone look like on the night of the 14th?"*

**CloudKit-synced data** is *current-state, multi-device, live*. There is no single snapshot — each category is a continuously-mirrored container that every signed-in device reads and writes. The CloudKit-synced categories are the ones the prompt-worthy investigations live in:

```
                 ┌─────────────────────── Apple Account ───────────────────────┐
                 │                                                              │
   ┌─────────────┴──────────────┐                  ┌────────────────────────────┴───────────┐
   │   iCloud BACKUP (blob)      │                  │   CloudKit-SYNCED containers (live)      │
   │   point-in-time snapshot    │                  │   current-state, multi-device            │
   │   ─────────────────────     │                  │   ─────────────────────────────          │
   │   • camera roll             │                  │   • iCloud Photos      • Notes           │
   │   • app container data      │                  │   • iCloud Drive       • Health          │
   │   • device settings         │                  │   • Messages in iCloud • Safari (hist)   │
   │   • SMS/MMS, call history    │                  │   • iCloud Keychain    • Reminders       │
   │   • visual voicemail         │                  │   • Wallet, Home, Maps, Voice Memos…     │
   └─────────────────────────────┘                  └──────────────────────────────────────────┘
        historical / per-device                          present-state / account-wide
```

The forensic consequence: a backup is *history* (and may hold a deleted-on-device item that the synced container has since purged), while synced data is *now* (and reflects edits/deletions made on any device, including after seizure). You want both, and you treat their timestamps differently.

> 🖥️ **macOS contrast:** You studied iCloud/Apple ID from the *account holder's* side on the Mac — System Settings → Apple Account, the `~/Library/Mobile Documents/` Drive mirror, `defaults read MobileMeAccounts`. Same backend, same CloudKit containers. The iOS forensic question is the inverse of the user question: not "how do I sync my stuff," but **"what can a third party with a token, or a court with a warrant, pull from this account — and what does ADP foreclose for both?"** The Mac is also the *richest place to steal the token from* (below).

### The encryption tiers: Standard vs. Advanced Data Protection

Everything in iCloud is encrypted in transit (TLS) and at rest (AES on Apple's servers). The only question that matters forensically is **who holds the key**.

**Standard Data Protection (the default).** Apple holds the class keys for most categories in *Hardware Security Modules* in its data centers. Apple *can* decrypt that data, which means Apple can (a) help a user recover it after a lockout and (b) produce its plaintext under a search warrant. A subset of categories is *already* end-to-end encrypted even at this default tier — Apple counts **14** of them (the same figure it has published since ADP launched in iOS 16.2/16.3; re-verify against `support.apple.com/en-us/102651`). The principal ones — Apple's enumeration also counts QuickType-keyboard learned vocabulary, and splits a couple of the grouped rows below into separate entries to reach 14:

| Category (E2EE *by default*, Standard tier) | Notes |
|---|---|
| Passwords & iCloud Keychain | always E2EE; never producible by Apple |
| Health data | E2EE |
| Home data (HomeKit) | E2EE |
| **Messages in iCloud** | E2EE **only if not escrowed** — see the key-escrow trap below |
| Payment information / Apple Card transactions | E2EE |
| Maps (favorites, guides, search history) | E2EE |
| Safari history, tab groups, iCloud Tabs | E2EE |
| Screen Time | E2EE |
| Siri information | E2EE |
| Wi-Fi passwords | E2EE |
| W1/U1 Bluetooth pairing keys, Memoji | E2EE |

Everything *not* on that list — under Standard protection — Apple can decrypt: **iCloud Backup, iCloud Drive, Photos, Notes, Reminders, Voice Memos, Wallet passes, Siri Shortcuts, Freeform.**

**Advanced Data Protection (opt-in).** Flipping ADP on promotes that second group to end-to-end encryption too, raising the total to **23** categories in Apple's current materials (the canonical **14 → 23** jump). Apple removes its own copy of the class keys; the keys are held only by the user's trusted devices and an optional recovery contact / recovery key. **Apple now holds no key for those categories.** The user-recovery promise is deliberately surrendered for the security guarantee.

**Never E2EE — even with ADP on:** **iCloud Mail, Contacts, and Calendars.** Apple keeps these server-decryptable on purpose, because they must interoperate with the global IMAP / CardDAV / CalDAV ecosystem (your iCloud calendar has to talk to a stranger's Exchange invite). These three are the *permanent* warrant-reachable content categories regardless of ADP. (Shared Albums, iWork real-time collaboration, and "anyone with the link" shares are likewise not E2EE even under ADP.)

> 🔬 **Forensics note — the Messages-in-iCloud key-escrow trap.** "Messages in iCloud" is listed as E2EE, but there's a documented catch that wins or loses cases. When **iCloud Backup is enabled and ADP is off**, the key that decrypts Messages in iCloud is *included inside the iCloud Backup* (the backup itself is server-decryptable at the Standard tier). Net effect: **Apple can read the target's iMessages**, via the backup, even though the Messages container is nominally end-to-end encrypted. Two things sever that access: turning **iCloud Backup off**, or turning **ADP on** (which encrypts the backup too). So before you assume iMessage content is unreachable, check whether iCloud Backup is enabled — and before you assume it *is* reachable, check ADP. This is the single most consequential E2EE nuance in iOS cloud forensics.

### The three authentication routes

There are exactly three ways into a live iCloud account. Tools differ only in polish; the routes are fixed.

**Route 1 — Apple Account credentials + 2FA.** You have the Apple ID and password *and* can satisfy the two-factor challenge (a trusted-device approval prompt or an SMS code to a trusted number). This is what Elcomsoft Phone Breaker, Cellebrite Cloud, Magnet AXIOM Cloud, and Oxygen Cloud Extractor do when handed creds. Brittle: 2FA is the wall, Apple's server-side anomaly detection flags forensic-workstation logins, and a wrong region/IP can trigger a lock.

**Route 2 — an extracted authentication token / anisette data from a seized, signed-in computer.** This is the route that *bypasses 2FA*, because the target machine is *already* a trusted device. When a Mac (or Windows PC running iCloud for Windows) is signed in, it holds a long-lived authentication token. Lift that token and you inherit the trust without ever seeing the password or the second factor. On macOS the relevant artifacts are the **Accounts framework store** `~/Library/Accounts/Accounts4.sqlite` (which account, which services) plus the **login keychain**, where the IDMS / Apple Account tokens live (item labels along the lines of `com.apple.account.idms.token` and `com.apple.account.AppleAccount.token` — exact labels vary by OS, verify on the target). Crucially, a bare token is not enough: Apple's *Grand Slam* authentication (GSA) binds the token to **anisette data** — the machine identifiers (`X-Apple-I-MD`, `X-Apple-I-MD-M`, and the routing info `X-Apple-I-MD-RINFO`) produced by Apple's on-device ADI library. Replay the token from a different machine without matching anisette and Apple's servers reject it. Elcomsoft Phone Breaker is the canonical tool that extracts the token *and* the machine-specific data from a live or non-live macOS/Windows image, then replays both.

**Route 3 — legal process to Apple** (its own section below). Not "into the account" — a request *to Apple* to produce what *Apple* can decrypt.

> ⚠️ **ADVANCED — token extraction alters chain of custody.** Pulling the token from a *live* seized Mac requires the machine on, the account logged in, and (for the login keychain) the user's password or an unlocked keychain. Running an extraction tool against a live system writes to the disk, touches the keychain, and creates network connections to Apple under the subject's identity — all of which mutate the evidence and can *alter the very account you are imaging* (a forensic login can appear as a new sign-in, can trip Apple's anomaly response, and can push a notification to the subject's other devices). Image the Mac first, document the keychain state, and prefer the non-live token-extraction path (from a forensic image of the Mac) over touching the running machine. See [[acquisition-sop-and-chain-of-custody]].

> 🔬 **Forensics note — the 2026 protocol cutover.** Token-based iCloud extraction is an arms race against Apple's server protocols, not a stable capability. Apple executed a hard cutover in **January–February 2026**: the legacy authentication endpoints were retired and the cloud auth flow was overhauled, which **broke every token-based extraction tool overnight**. Vendors re-implemented against the new protocol — **Elcomsoft Phone Breaker 11 (April 2026)** restored synced-data, iCloud Drive, and backup extraction, *except the end-to-end-encrypted categories* (Health, iCloud Keychain, Messages, Maps, Safari history), which stayed inaccessible — a concrete reminder that no tool defeats E2EE, only the server-key tier. Apple then **reworked the iCloud Backup format from the ground up in iOS/iPadOS 26**, breaking the tools again until **EPB 11.2 (June 2026)** became the first to download iOS-26-era backups. The durable lesson: a cloud-acquisition tool's "supported" status is a perishable, version-stamped fact you confirm *the week of the exam*, never an assumption from a datasheet. Capability you had in December can be gone in February.

### The legal-process route — Apple as a respondent

The third route doesn't touch the account at all; it serves legal process *on Apple* for what Apple is technically and legally able to produce. The contract is public: **Apple's Legal Process Guidelines** (US edition, current revision published **October 2025** — `apple.com/legal/privacy/law-enforcement-guidelines-us.pdf`). It maps each data class to the legal instrument required, and the through-line is the classic **content vs. metadata** split: metadata/transactional records fall to lesser process; *content* requires a probable-cause search warrant.

| What you want | Legal instrument (US) | Notes / retention |
|---|---|---|
| Subscriber / customer info, connection logs (incl. IP) | **Subpoena** (or greater) | Connection logs retained **up to ~25 days** |
| Mail logs (to/from, time, date — *not bodies*) | **18 U.S.C. § 2703(d)** order | Header-level metadata only |
| **iCloud content** — Photos, Drive docs, Contacts, Calendars, Safari bookmarks, **iOS device backups** (camera roll, device settings, app data, iMessage, SMS/MMS, voicemail) | **Search warrant** (probable cause) | Only the categories Apple can decrypt |
| Preservation (freeze the account before you have the warrant) | **§ 2703(f) preservation request** | Holds for **90 days**, renewable |

Two operational moves the guidelines enable: a **preservation request** under § 2703(f) freezes the account's current state for 90 days *before* you've assembled probable cause (use it early — synced data is live and a co-conspirator can wipe it remotely), and an **emergency disclosure** path exists for imminent danger-to-life.

> ⚖️ **Authorization.** The warrant route is *to a third-party custodian* (Apple), and its scope is the warrant's four corners. Apple's compliance is gated on the legal instrument matching the data class — a subpoena will not get content, full stop. Outside the US, you are in **MLAT / mutual-legal-assistance** territory (or the US–UK CLOUD Act bilateral), which can add months. And note the jurisdictional collision: a warrant issued in country A for an account whose holder is in country B routes through treaty channels and the data-localization rules of wherever Apple stores that region's data. Document the legal authority for *every* cloud request the way you document chain of custody for a physical exhibit.

> 🔬 **Forensics note — what a warrant to Apple gets you when ADP is ON.** Apple's own guidelines now carry the ADP caveat: for accounts with Advanced Data Protection enabled, **"limited iCloud data may be available."** Concretely, Apple can still produce: **Mail, Contacts, Calendars** (never E2EE), **all metadata and transactional logs** (subscriber info, connection/IP logs, mail headers, sign-in records, device lists), and the *fact* that categories exist. Apple **cannot** produce the plaintext of Backup, Drive, Photos, Notes, Reminders, Voice Memos, Wallet, or Messages-in-iCloud, because **it holds no key**. The warrant is valid and served; Apple simply has nothing decryptable to hand over for those categories.

### The game-changer: ADP forecloses *both* extraction and the warrant

Put the three routes against the ADP switch and the picture is stark. ADP does not just defend against hackers — it **simultaneously kills third-party extraction and the warrant-to-Apple content route** for every category it covers, because both ultimately depend on a key Apple no longer holds:

```
                          ADP OFF (default)              ADP ON
  ───────────────────────────────────────────────────────────────────────
  Backup / Drive /       Token route:  ✅ extractable    Token route:  ❌ (no key in cloud)
  Photos / Notes /       Warrant→Apple: ✅ producible    Warrant→Apple: ❌ "no key"
  Reminders / Voice
  Memos / Wallet /
  Messages-in-iCloud*

  Mail / Contacts /      Token route:  ✅                Token route:  ✅ (never E2EE)
  Calendars              Warrant→Apple: ✅                Warrant→Apple: ✅

  Metadata / IP logs /   Always producible via subpoena/2703(d) — ADP does not touch metadata
  sign-in records
  ───────────────────────────────────────────────────────────────────────
  * Messages-in-iCloud is reachable with ADP OFF *only if iCloud Backup is on* (key escrow).
```

The strategic pivot for the investigator: **ADP relocates the evidence from the cloud back to the endpoint.** When the cloud is dark, your only remaining decryptable copy of Photos/Notes/Backup content is *on the device*, which throws you back to the device-acquisition ladder — full-file-system on an exploitable SoC (A8–A13 BootROM via checkm8/usbliter8), a logical/backup acquisition on a passcode-known AFU device, or nothing. The cloud chapter and the device chapter are not independent: **ADP on the account is what makes the device acquisition mandatory rather than optional.** Always check the cloud *first* — it's often the path of least resistance — but read ADP state as the signal that tells you whether to even bother.

### The policy fault line: the 2025 UK episode (dated)

ADP's availability is no longer purely a user choice — it is now **jurisdictional**, and that directly governs whether the cloud route is open. The precedent:

- **January 2025:** the UK Home Office served Apple a secret **Technical Capability Notice (TCN)** under the **Investigatory Powers Act 2016** (the "Snooper's Charter"), reportedly demanding a *blanket capability* to access ADP-encrypted material — and, controversially, worldwide, not just for UK users.
- **February 2025:** rather than build a backdoor (which would have broken E2EE for everyone), Apple **withdrew ADP as an option for UK users** — disabling new enrollments and committing to migrate existing UK ADP users off the feature. Apple's public support note (`support.apple.com/en-us/122234`, titled *"…in the United Kingdom to new users"*) documents that it can no longer offer ADP in the UK.
- **August 2025:** the US Director of National Intelligence (Tulsi Gabbard) announced the UK had **agreed to drop the demand as it applied to US persons' data**, easing the worst of the cross-border overreach.
- **Autumn 2025:** the Home Office **re-issued the order narrowed to UK users only** (dropping the worldwide / US-persons reach). That narrowing became the "change in circumstances" that reshaped the litigation.
- **Into 2026 (as of this writing, 2026-06):** **ADP remains unavailable to UK users**, with no announced reinstatement. After the order was narrowed to UK-only, the **Investigatory Powers Tribunal dismissed Apple's own appeal** (Apple and the Home Office agreed to drop that claim) — but the **separate Privacy International / Liberty challenge to the secrecy of the TCN regime continues**. Re-verify status at exam time — this is fast-moving.

> 🔬 **Forensics note — region now predicts the cloud route.** The practical investigative takeaway: **the account's region can decide whether E2EE content is reachable at all.** A UK-region account in 2026 *cannot have ADP on*, so its iCloud Backup, Photos, Drive, and Notes remain Standard-tier and therefore **warrant-reachable from Apple** — the cloud route is open. A US-region account with ADP enabled is dark for the same categories. When you triage an account, log the **region** alongside the ADP state; together they tell you which of the three routes is even viable before you spend a subpoena on it.

### The tooling landscape (concept, not endorsement)

| Tool | Routes it uses | What it pulls | ADP? |
|---|---|---|---|
| **Elcomsoft Phone Breaker** | creds+2FA, **token/anisette**, trusted-device auth | iCloud Backup, synced data, iCloud Drive, keychain (with device) | ❌ cannot defeat E2EE; needs decryptable categories |
| **Cellebrite Cloud** (UFED Cloud / Cloud Analyzer) | creds+2FA, token | backups + synced categories + many third-party clouds | ❌ |
| **Magnet AXIOM Cloud** | creds+2FA, token | iCloud + cross-cloud (Google, social) | ❌ |
| **Oxygen Forensic Cloud Extractor** | creds+2FA, token | iCloud + cross-cloud | ❌ |
| **mvt** (Mobile Verification Toolkit, Amnesty) | *no cloud pull* | decrypts & parses **local** encrypted backups / FFS dumps, checks STIX2 IOCs (spyware triage) | n/a — backup-analysis, not acquisition |

The unifying truth across the commercial row: every one of them needs **either** valid credentials+2FA **or** a token, and **none defeats ADP's end-to-end encryption** — they extract only what Apple's servers can decrypt. **mvt** is the odd one out and worth knowing precisely: it is *not* a cloud puller. It is an offline analyzer that decrypts an iTunes/Finder backup (or parses a full-filesystem dump) and runs it against indicator-of-compromise lists for spyware triage (Pegasus, Predator). Its "iCloud" relevance is limited to analyzing a backup you obtained by other means — the prompt's "mvt (limited)" framing. See [[decrypting-backups-and-images]] for the backup-decryption mechanics it shares.

## Hands-on

There is no on-device shell and no physical device. Everything here runs on **your Mac** — which is exactly the substrate Route 2 targets (a signed-in computer), so these commands double as a study of the token-extraction *preconditions*.

### 1. Confirm an account is signed in and which services are live

`MobileMeAccounts` is the clean, durable defaults domain for the signed-in Apple Account and its per-service enable flags:

```bash
defaults read MobileMeAccounts
```

```
{
    Accounts =     (
        {
            AccountID = "robert.olen@icloud.com";
            AccountDescription = iCloud;
            DisplayName = "...";
            LoggedIn = 1;
            Services =             (
                { Name = "CLOUDDOCS";   Enabled = 1; },   # iCloud Drive
                { Name = "MAIL";        Enabled = 1; },
                { Name = "FIND_MY";     Enabled = 1; },
                { Name = "BACKUP";      Enabled = 1; },   # iCloud Backup ← Messages-escrow signal
                { Name = "KEYCHAIN_SYNC"; Enabled = 1; },
                ...
            );
        }
    );
}
```

`LoggedIn = 1` is the Route-2 precondition. The `BACKUP` service flag is your **Messages-in-iCloud escrow tell** — if backup is on and ADP is off, the iMessage key is escrowed in that backup (above). Note: `MobileMeAccounts` exposes the *user's* view; it does not report ADP state directly (ADP is a server/account property — confirm it from device settings, the account-recovery configuration, or Apple's response to legal process).

### 2. Enumerate the macOS Accounts store (copy-before-query)

```bash
cp ~/Library/Accounts/Accounts4.sqlite /tmp/accts.db          # copy first — SELECT write-locks SQLite
sqlite3 /tmp/accts.db ".tables"
sqlite3 /tmp/accts.db "SELECT ZUSERNAME, ZIDENTIFIER, ZACCOUNTDESCRIPTION FROM ZACCOUNT;"
```

The `ZACCOUNT` / `ZACCOUNTTYPE` / `ZDATACLASS` tables enumerate every configured account and the data classes (mail, contacts, calendars, CloudKit) each one services. The iCloud account type identifier is along the lines of `com.apple.account.AppleAccount` (historically `com.apple.account.iCloud`). Exact column/identifier strings drift across macOS releases — run `.schema ZACCOUNT` and verify before quoting them in a report.

### 3. Inspect the iCloud tokens' *metadata* in the login keychain (no secrets)

```bash
# Item labels/attributes only — does NOT print secrets without unlock
security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null \
  | grep -iE 'idms|AppleAccount|iCloud|com.apple.account' | head
```

This shows the *existence* of the IDMS / Apple Account token items — the thing Route 2 lifts — without their contents. Extracting the token *value* is what a tool like Elcomsoft Phone Breaker does (and what requires the keychain password / an unlocked keychain). Treat printing the value as evidence-altering.

### 4. Watch CloudKit sync telemetry on the Mac

```bash
# What the sync daemons are doing — the Mac side of the synced-container model
log show --last 1h --predicate 'process == "cloudd" OR subsystem == "com.apple.cloudkit"' \
  --style compact | head -40

# Local CloudKit / iCloud Drive working state
ls ~/Library/Application\ Support/CloudDocs/session/db/ 2>/dev/null
ls ~/Library/Mobile\ Documents/                          # the iCloud Drive local mirror
```

`cloudd` is the CloudKit client daemon; its log narrates container fetches and pushes. The `CloudDocs` session DB and `~/Library/Mobile Documents/` are the locally-cached face of the synced containers — a forensic shortcut when you have the Mac but not the account.

### 5. (Walkthrough) Token extraction with Elcomsoft Phone Breaker

EPB is a Windows/macOS GUI tool; narrate, don't pretend to run it on a device:

```
Apple → "Download from iCloud" → "Extract authentication token"
   ├─ Live local machine:    EPB reads Accounts4.sqlite + login keychain, mints the token
   ├─ Non-live image:        point EPB at a forensic image of the Mac/PC; it reconstructs
   │                          token + anisette/machine data offline (preferred for CoC)
   └─ Replay:                EPB authenticates to iCloud with token + machine data,
                              then downloads backup / synced data / iCloud Drive
```

The non-live path (against an *image* of the signed-in computer) is the chain-of-custody-clean variant of Route 2 — it never touches the running subject machine.

## 🧪 Labs

> ⚠️ All labs are **device-free** and read-only. Where a lab uses *your* Mac, it is standing in for "a seized, signed-in computer" (Route 2's substrate); the **fidelity caveat** is that this is the *macOS* Accounts/keychain/CloudKit stack — an iOS device keeps its equivalents inside the keychain + `accountsd` and behind Data Protection, unreachable without device acquisition, and the device-only daemons never run here.

### Lab 1 — Map the account's cloud surface (substrate: your live Mac as a stand-in seized computer)

1. Run `defaults read MobileMeAccounts`. Record the `AccountID`, `LoggedIn`, and every service with `Enabled = 1`.
2. Note whether **`BACKUP`** is enabled. Write one sentence on what that implies for Messages-in-iCloud reachability *if* ADP is off (the escrow trap).
3. `cp ~/Library/Accounts/Accounts4.sqlite /tmp/accts.db` and enumerate `ZACCOUNT`. Cross-check that the iCloud account from step 1 appears, and list the data classes it services.
4. **Fidelity caveat to write down:** this is the Mac's account store; the iOS equivalent is not on disk in plaintext — it lives behind Data Protection and is only reachable via device acquisition ([[full-file-system-acquisition]]).

### Lab 2 — Build the ADP coverage matrix (substrate: read-only walkthrough of Apple's docs)

1. Open `support.apple.com/en-us/102651` (iCloud data security overview) and Apple's US Legal Process Guidelines PDF.
2. Build a three-column table: **Category | Reachable via token (ADP off) | Reachable via warrant-to-Apple (ADP off) | Reachable when ADP ON**.
3. Fill rows for: iCloud Backup, Photos, Drive, Notes, Messages-in-iCloud, Mail, Contacts, Calendars, Keychain, Health.
4. Circle the three rows that stay warrant-reachable **regardless of ADP** (Mail, Contacts, Calendars) and the rows that go fully dark under ADP. This matrix *is* the deliverable — it's the decision aid you'd attach to a cloud-acquisition request.

### Lab 3 — Decrypt and triage a local backup with mvt (substrate: a public sample / your own encrypted backup)

> The offline analogue to "iCloud Backup content," using the local backup format ([[the-itunes-finder-backup-format]]). Use a public sample encrypted backup (mvt's test data or a Hickman reference image) — no device needed.

```bash
pipx install mvt
mvt-ios decrypt-backup -p '<backup-password>' -d /tmp/decrypted ./sample_backup
mvt-ios check-backup --output /tmp/mvt_out /tmp/decrypted
```

1. Decrypt the backup; observe `mvt` writing the plaintext tree to `/tmp/decrypted`.
2. Run `check-backup` and read which modules fired (SMS, Safari, datausage, etc.).
3. **Fidelity caveat:** a *local* encrypted backup mirrors what an *iCloud* Backup holds for a non-ADP account, but the iCloud key-escrow and lock-state semantics differ — and `mvt` analyzes, it does not *acquire from the cloud*.

### Lab 4 — Observe the synced-container model on the Mac (substrate: your live Mac; CloudKit, not device daemons)

1. Run the `cloudd` / `com.apple.cloudkit` `log show` from Hands-on step 4 while editing a Note or adding a file to iCloud Drive. Watch the container push.
2. List `~/Library/Mobile Documents/` and `~/Library/Application Support/CloudDocs/session/db/`. These are the local cache of the live containers.
3. **Fidelity caveat:** this is macOS CloudKit. The iOS pattern-of-life daemons (`knowledged`, `biomed`, `routined`) that populate the device-side synced/behavioral stores **do not run here**, so you see the sync plumbing but not the device's behavioral telemetry.

## Pitfalls & gotchas

- **"It's E2EE so it's safe" is wrong for Messages-in-iCloud.** The iCloud Backup key-escrow path means iMessage content is Apple-readable whenever Backup is on and ADP is off. Check both flags before concluding either way.
- **ADP state is not in `MobileMeAccounts`.** ADP is a server/account property. Don't infer it from the Mac's service flags — confirm it from device settings (Apple Account → iCloud → Advanced Data Protection), the account-recovery configuration, or Apple's legal-process response.
- **A forensic iCloud login can notify the subject and alter the account.** Authenticating to a live account (Route 1) or replaying a token from the wrong machine pushes a new-sign-in notification to the subject's trusted devices and can trip Apple's anomaly lock. Prefer the non-live, image-based token path. File a **§ 2703(f) preservation request** *before* you risk touching the account.
- **Tool support is perishable.** The Jan–Feb 2026 protocol cutover broke every token tool until vendors caught up (EPB 11, April 2026). Never assume a datasheet capability — confirm the tool authenticates *this week*.
- **Region ≠ ADP availability.** A UK-region account *cannot enable ADP* (2025–2026 TCN fallout), so its content stays warrant-reachable from Apple — a US account with ADP-on does not. Log the region.
- **Metadata survives ADP.** Even fully E2EE, Apple still holds subscriber info, IP/connection logs (~25-day retention), mail headers, sign-in records, and device lists — subpoena/2703(d)-reachable. ADP is a *content* shield, not a metadata shield. Don't forget the metadata request just because the content is dark.
- **Connection logs age out fast.** ~25 days. If IP attribution matters, the subpoena is time-critical — send it before the window closes.
- **Backup vs. synced timestamps mean different things.** A backup timestamp is "snapshot taken"; a synced-item timestamp is "last edited on some device" — possibly *after* seizure, by a co-conspirator. Don't treat them interchangeably on a timeline ([[the-ios-timestamp-zoo]] discipline applies).
- **Don't conflate iCloud Backup with a full-file-system image.** The backup excludes a lot (no keychain in plaintext, no system/Data-Protection-class-A material the way a FFS dump has it). The cloud is a *complement* to device acquisition, not a substitute.

## Key takeaways

- iCloud is **two** evidence stores: a per-device **backup blob** (point-in-time history) and **CloudKit-synced containers** (live, account-wide current state). Acquire and timestamp them differently.
- The only encryption question that matters is **who holds the key.** Standard tier: Apple holds keys for Backup/Drive/Photos/Notes (warrant-producible). ADP tier: Apple holds **no** key for those — they go dark.
- **Mail, Contacts, Calendars are never E2EE**, even with ADP — the permanent warrant-reachable content. **Metadata is never E2EE either** — always subpoena-reachable.
- There are exactly **three routes in**: credentials+2FA, a **token/anisette** lifted from a signed-in computer (bypasses 2FA), and **legal process to Apple**. Tools differ only in polish.
- **ADP forecloses BOTH third-party extraction AND the warrant-to-Apple content route** for the categories it covers — because both depend on a key Apple gave up. It relocates the evidence back onto the endpoint.
- **Messages-in-iCloud is Apple-readable when Backup is on and ADP is off** (key escrow). The single most consequential nuance — check both flags.
- **Jurisdiction now gates the cloud route:** the UK's 2025 TCN forced Apple to pull ADP for UK users (still unavailable in 2026), so UK-region content stays warrant-reachable while US ADP accounts do not.
- **Always check the cloud first** (often the path of least resistance) and **read ADP + region state as the signal** for whether device acquisition becomes mandatory.

## Terms introduced

| Term | Definition |
|---|---|
| iCloud Backup | Per-device, point-in-time encrypted snapshot blob (camera roll, app data, settings, SMS/MMS, voicemail); the cloud analogue of a Finder backup |
| CloudKit-synced data | Continuously-mirrored, current-state, multi-device containers (Photos, Drive, Notes, Health, Safari, Messages-in-iCloud, Keychain) |
| Standard Data Protection | Default iCloud tier; Apple holds class keys for most categories (server-decryptable, warrant-producible); 14 categories E2EE by default (Apple's current count) |
| Advanced Data Protection (ADP) | Opt-in tier raising the E2EE set to 23 categories (the 14 → 23 jump); Apple holds no key — forecloses extraction and warrant-to-Apple content |
| Messages-in-iCloud key escrow | When iCloud Backup is on and ADP is off, the Messages decryption key is stored in the backup, making iMessage Apple-readable despite nominal E2EE |
| Authentication token (iCloud) | Long-lived credential held by a signed-in computer; lifting it inherits the device's trust and bypasses 2FA (Route 2) |
| Anisette data | Machine identifiers (`X-Apple-I-MD`, `-MD-M`, `-MD-RINFO`) from Apple's ADI library that bind a token to a device in Grand Slam (GSA) auth |
| `Accounts4.sqlite` | macOS Accounts-framework store (`~/Library/Accounts/`) enumerating configured accounts and their data classes |
| `MobileMeAccounts` | macOS defaults domain reporting the signed-in Apple Account and per-service enable flags (CLOUDDOCS, MAIL, BACKUP, …) |
| Legal Process Guidelines | Apple's published map of data class → required legal instrument (subpoena / 2703(d) / warrant); US edition rev. Oct 2025 |
| § 2703(f) preservation request | US legal instrument that freezes an account's state for 90 days before a warrant is obtained |
| Technical Capability Notice (TCN) | UK Investigatory Powers Act order compelling a provider to provide access capability; basis of the 2025 UK–Apple ADP dispute |
| `cloudd` | macOS CloudKit client daemon; narrates synced-container fetches/pushes in the unified log |

## Further reading

- Apple — *iCloud data security overview* (`support.apple.com/en-us/102651`) and *Advanced Data Protection for iCloud* in the Apple Platform Security guide — the authoritative E2EE category lists and key hierarchy.
- Apple — *Legal Process Guidelines: U.S. Law Enforcement* (`apple.com/legal/privacy/law-enforcement-guidelines-us.pdf`, current rev.) — the content-vs-metadata ladder and ADP caveat.
- Apple Support — *"Apple can no longer offer Advanced Data Protection in the United Kingdom to new users"* (`support.apple.com/en-us/122234`).
- Elcomsoft blog & EPB help — *About Authentication token* and *"Elcomsoft Phone Breaker 11 Restores iCloud Access"* (2026-04) — the token/anisette mechanism and the 2026 protocol cutover.
- Mobile Verification Toolkit (`github.com/mvt-project/mvt`) — `mvt-ios decrypt-backup` / `check-backup` for offline backup triage.
- Privacy International — *PI Apple TCN Challenge*; UK Constitutional Law Association analyses — the IPA 2016 / TCN legal context.
- Vendor cloud-acquisition docs — Cellebrite Cloud (UFED Cloud), Magnet AXIOM Cloud, Oxygen Forensic Cloud Extractor — for the commercial-tool authentication model.
- SANS FOR585 (Smartphone Forensics) cloud modules; Sarah Edwards (mac4n6.com) on Apple account artifacts.
- `man security`, `man defaults`, `man sqlite3` — exact flag semantics on your macOS version.

---
*Related lessons: [[advanced-protections-lockdown-sdp-adp]] | [[the-acquisition-taxonomy]] | [[the-itunes-finder-backup-format]] | [[decrypting-backups-and-images]] | [[apple-account-icloud-and-apns]] | [[acquisition-sop-and-chain-of-custody]]*
