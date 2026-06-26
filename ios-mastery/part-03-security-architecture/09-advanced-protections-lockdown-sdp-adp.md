---
title: "Advanced protections: Lockdown, SDP, ADP"
part: "03 — Security Architecture"
lesson: 09
est_time: "45 min read + 15 min labs"
prerequisites: [data-protection-and-keybags, the-ios-security-model]
tags: [ios, lockdown-mode, stolen-device-protection, advanced-data-protection, adp, privacy, forensics]
last_reviewed: 2026-06-26
---

# Advanced protections: Lockdown, SDP, ADP

> **In one sentence:** Lockdown Mode, Stolen Device Protection, and Advanced Data Protection are three opt-in hardening layers that don't add new cryptography so much as *remove avenues* — each one deletes a class of attack surface or acquisition route, and as a forensicator your job is to detect which are on and reason precisely about what each one has already foreclosed.

## Why this matters

By 2026 the baseline iOS security model — Secure Enclave, Data Protection class keys, the sandbox, code-signing — is the same on every device and not user-tunable. The interesting variance, for both an attacker and an examiner, lives in the **opt-in** layer. A device with Lockdown Mode, Stolen Device Protection, and Advanced Data Protection all enabled is a categorically different target from a default device: it has a smaller remote attack surface, a passcode that no longer buys a forensic pairing, and an iCloud account whose contents Apple itself cannot hand you under a warrant. None of that shows up in a device's model number — you have to *detect* it, and you have to understand the mechanism well enough to know which avenue each one closes and which it leaves wide open (local full-file-system acquisition, notably, is untouched by ADP). This lesson is about reading those three flags and knowing exactly what they cost you.

## Concepts

### The shape of the opt-in layer: three knobs, three foreclosed avenues

These three features are frequently lumped together as "the privacy stuff," but they target three different planes of the threat model, and confusing them will make you reason wrongly about an investigation.

| Feature | Plane it defends | What it removes | Primary defeat for an examiner |
|---|---|---|---|
| **Lockdown Mode (LDM)** | Remote *exploitation* surface | Risky parsers/features (WebKit JIT, rich message attachments, unsolicited FaceTime, profile installs, wired-while-locked) | Foreclosed: many artifact *types* never get created; the easy wired/MDM ingestion paths are shut |
| **Stolen Device Protection (SDP)** | *Physical-possession + known passcode* attacker | The passcode-only fallback for sensitive actions, including establishing trust | Foreclosed: passcode alone no longer authorizes a new pairing when away from familiar locations |
| **Advanced Data Protection (ADP)** | *Server-side* compromise / legal compulsion of Apple | Apple's ability to decrypt most iCloud categories | Foreclosed: the cloud route — warrant-to-Apple and token-based iCloud extraction return ciphertext |

Read the third column as a checklist of routes deleted. The three are independent flags — any subset can be on — and they compose: a Pegasus-target journalist will typically run all three.

> 🖥️ **macOS contrast:** You've met two of these already on the Mac. macOS has the *same* Lockdown Mode (System Settings → Privacy & Security → Lockdown Mode) with an analogous feature-disable list, and the *same* Advanced Data Protection toggle governing the *same* iCloud account (ADP is account-wide, not per-device — turning it on from your iPhone changes what Apple can decrypt for your Mac's iCloud data too). The macOS analogue SDP lacks is deliberate: SDP is about a thief who shoulder-surfed your passcode and grabbed the phone, a threat model specific to a pocket device with Face ID, so there is no Mac equivalent. When you reason about an Apple Account under ADP, remember every enrolled device — iPhone, iPad, Mac — sits behind the same wall.

### The threat model: mercenary spyware (Pegasus-class)

Lockdown Mode exists because of a specific adversary: commercial "lawful intercept" vendors — NSO Group (Pegasus), Intellexa/Cytrox (Predator), QuaDream, Paragon — who sell **zero-click** remote exploit chains to nation-state customers. The defining property of these chains is that they don't need the user to tap anything. They arrive through the very subsystems an iPhone exposes to the world to be useful: a malformed attachment in an iMessage (the 2021 *FORCEDENTRY* chain hid a PDF behind a `.gif` extension and tripped a JBIG2 integer overflow in the **CoreGraphics** PDF decoder, bootstrapping a Turing-complete "weird machine" that escaped the **BlastDoor** message sandbox — all before any notification rendered), a WebKit drive-by, a crafted FaceTime invite, a wallet pass, a font.

You cannot patch a bug you don't know about, so Lockdown Mode takes the only durable defense against an *unknown* zero-click: it **shrinks the surface**. It turns off the speculative-execution-fast-path parsers and the auto-rendering conveniences that exist purely for UX, on the bet that an at-risk user (journalist, dissident, diplomat, executive) would rather lose link previews than keep an `ImageIO` fast path that might harbor the next FORCEDENTRY. This is why Lockdown Mode's design language is *subtraction*, and why Apple frames it as "extreme" and not for everyone.

> 🔬 **Forensics note:** Apple's **Threat Notifications** (the "Apple believes you are being targeted by mercenary spyware…" emails/iMessages, sent since 2021 and re-worded in 2023) are themselves an artifact. They land in the target's Apple Account email and in Messages, and they are the recommended trigger for running **mvt** (Mobile Verification Toolkit) against a sysdiagnose/backup to hunt Pegasus IOCs. A subject who enabled all three of these features around the same date is often a subject who received such a notification — correlate the enablement window with their inbox.

### Lockdown Mode: subtraction, enumerated

When the flag is on, the OS enforces a fixed policy across many subsystems. The durable, version-stable core (re-verify the exact list against the live *Apple Platform Security* guide each release — Apple tunes it):

- **WebKit JIT is disabled.** The just-in-time JavaScript compiler — historically the richest iOS RCE primitive, because JIT requires writable-then-executable memory and a bug in the compiler yields native code — is turned off in Safari and *every* WebKit-backed browser/web view system-wide (all third-party iOS browsers are WebKit). Pages fall back to the interpreter: slower, far smaller attack surface. A site the user explicitly excludes can re-enable it.
- **Most message attachment types and link previews are blocked.** Incoming Messages drops everything except a short allowlist of image/video/audio formats; **link previews are not fetched or rendered**. This kills the auto-parse-on-receipt path (FORCEDENTRY's delivery vector).
- **Unsolicited inbound communication is refused.** Incoming **FaceTime from someone you've never called** is blocked; the same "must have prior contact" rule applies to incoming Apple-service invitations (e.g. SharePlay/shared content). Inbound from established contacts still works.
- **Shared Albums** in Photos are disabled (no new shared-album invitations; existing shared albums are removed from the device).
- **Configuration-profile installation and new MDM enrollment are blocked.** While LDM is on you *cannot* install a `.mobileconfig` or enroll the device in management.
- **Wired data connections are blocked while the device is locked.** A locked device in LDM will not establish a *data* connection to a computer or accessory; it must be **unlocked** first to connect.
- **2G cellular support is turned off** where the network allows (forces the modem off the most-trivially-spoofable legacy RAT — the one a fake base station / IMSI-catcher prefers), and some networking conveniences (e.g. automatic joining of non-secure Wi-Fi) are removed.

Enforcement is system-wide policy, not a single sandbox: each subsystem queries the global Lockdown-Mode state and changes behavior. There is no per-app "lockdown" — it's the whole device.

> ⚠️ **Naming-collision trap — "Lockdown Mode" ≠ `lockdownd`/"lockdown files."** This is the single most common confusion in iOS forensics and you must not fall into it. **`lockdownd`** is the long-standing on-device pairing/trust daemon; the **"lockdown records" / "lockdown files"** are the pairing certificates an examiner extracts from a trusted host's `/var/db/lockdown/` (macOS) or `%ProgramData%\Apple\Lockdown\` (Windows) to perform AFU logical acquisition without re-pairing. That subsystem predates Lockdown *Mode* by a decade and has nothing to do with it. When a tool or article says "lockdown," determine which one — the **pairing** machinery (acquisition gold) or the **attack-surface Mode** (acquisition obstacle). They even pull in opposite directions: pairing records *help* you; Lockdown Mode *blocks* the wired path those records ride on.

> 🔬 **Forensics note — detect Lockdown Mode by its negative space.** There is no timestamped "LDM was enabled at T" event stream; the authoritative on-device signal is a **state flag in a managed/global preference** (in a full-file-system image, inspect the system preferences domain for the Lockdown-Mode boolean — *verify the exact domain/key against the iOS version you're examining rather than trusting a stale path*). But the more robust forensic technique, emphasized in Andrea Fortuna's 2026 writeup, is **evidence of absence**: a device that's been in LDM for weeks shows a distinctive profile — **no link-preview cache entries**, **no non-image Messages attachments** after the enablement window, **no Shared Albums**, **FaceTime call history only with prior contacts**, and **failed/blocked configuration-profile installs**. Those artifacts weren't deleted — the feature prevented their creation. Build the timeline from when each artifact *class* stops appearing.

#### Lockdown Mode's wired blocking vs. USB Restricted Mode — don't conflate them

Two different mechanisms gate the Lightning/USB-C **data** pins, and an examiner must know which is in play because their timing differs:

| | USB Restricted Mode (default, all devices) | Lockdown Mode wired blocking |
|---|---|---|
| Setting | Face ID & Passcode → **Accessories** (USB Restricted Mode is the *absence* of "Allow access when locked") | Privacy & Security → **Lockdown Mode** |
| Trigger | Data pins disabled after the device has been **locked ~1 hour** (and *immediately on lock* if no wired data accessory has connected in the past **3 days**; a previously-paired accessory — remembered 30 days — may still attach inside the 1-hour window) | Data connection refused **whenever the device is locked** — no 1-hour grace |
| Effect on acquisition | You have a ~1-hour window after last unlock to attach a forensic bridge | You must get the device **unlocked first**, every time, before any wired link |

So on a default device you race the ~1-hour USB Restricted Mode clock; on a Lockdown-Mode device that clock is effectively **zero** — locked means no data, period. Both are why field seizure procedure is "keep it powered, keep it unlocked (or in a Faraday bag with charge), get it to the lab fast." See [[passcode-bfu-afu-and-inactivity]] for the lock-state machine these ride on.

### Stolen Device Protection: killing the passcode fallback

SDP defends a mundane but common attack: a thief who watched you type your passcode (or coerced it), then snatched the phone. With only the passcode, such a thief historically could change your Apple Account password, disable Find My, turn off Stolen Device Protection, drain saved passwords, and lock you out of your own recovery. SDP closes that by **demoting the passcode** for sensitive actions when the phone is somewhere it doesn't recognize.

Two mechanisms, both gated on **"away from familiar locations"**:

1. **Biometric-only, no passcode fallback.** Sensitive *access* actions require a live **Face ID / Touch ID** match with **no "enter passcode instead" escape hatch**. Covered actions include: viewing/using saved passwords & passkeys (Keychain), viewing a stored payment method, applying for an Apple Card, turning off Lost Mode, erasing all content and settings, setting up a new device with the iPhone, and using the iPhone to access certain account settings.
2. **One-hour Security Delay.** The highest-stakes account-control actions — changing the Apple Account password, changing the device passcode, disabling Face ID/Touch ID, turning **off** Stolen Device Protection itself, changing trusted phone numbers, updating account recovery (recovery key/contact), eSIM transfer — require biometric → **wait one hour** → **biometric again**. The window exists so the rightful owner has time to mark the device lost and lock the account before the thief can re-key it.

**"Familiar locations"** are computed from the system's learned **Significant Locations** (the same `routined`-maintained home/work model used elsewhere; see [[location-history]]). At home or work, SDP's extra requirements relax (the passcode fallback and delay can be skipped) — which is why the *user-chosen* setting "Require Security Delay: Away from Familiar Locations" vs. "Always" matters to you: the stricter "Always" removes the home/work relaxation entirely.

Note what SDP **deliberately leaves alone**: it does not require biometrics to *unlock the phone for normal use*, and it does not block **Find My** / Activation Lock — those are the rightful owner's recovery levers, so SDP is careful not to wall them off. The actions it gates are exactly the ones a thief would use to **sever the owner's recovery** (re-key the account, kill Find My's usefulness, wipe-and-resell). Crucially for an examiner, **Erase All Content and Settings** is on the biometric-required list when away from familiar locations — a passcode-only operator cannot trivially wipe the device, but neither can they use "erase" as a path to a clean re-setup.

> 🔬 **Forensics note — the pairing handshake is the casualty.** This is the bit that hits an examiner directly. Establishing trust between an iPhone and a forensic workstation (the "**Trust This Computer?**" dialog, which mints a pairing record) historically required only that the device be unlocked *with the passcode*. **Under SDP, when the device is away from a familiar location, the trust handshake requires Face ID/Touch ID — the passcode alone is no longer a sufficient credential** to authorize a *new* pairing (Elcomsoft, June 2026). Since minting a fresh pairing record is step one of advanced-logical acquisition, SDP can shut that door even when you *know* the passcode and the device is in AFU. The escape valves: a **pre-existing, valid pairing record** still works on an AFU device, and the lab is itself a "familiar location" only if the subject's significant-locations model already contains it (it won't). Treat any seized modern device as **potentially SDP-protected** until you've confirmed it's off — a security-conscious subject (exactly the kind whose phone you're imaging) is the likely adopter.

### Advanced Data Protection: deleting Apple's keys

ADP is the one that rewrites the legal-process calculus. To understand it, recall the default iCloud key model. CloudKit data is encrypted under a hierarchy rooted in a per-user, per-service **CloudKit Service key**. By default these come in two flavors:

- **End-to-end encrypted service keys** — the private key exists only on the user's trusted devices (synced via iCloud Keychain) and is **never** uploaded to Apple. ~14 categories are E2EE by default: Passwords & Keychain, Health, Home, Wi-Fi passwords, Maps favorites, Siri info, Memoji, payment/card info, QuickType vocabulary, Screen Time, etc.
- **Available-after-authentication service keys** — the private key is escrowed in Apple's data-center **HSMs**, releasable to Apple servers after the account authenticates. This is what lets Apple show your **iCloud Backup**, **Photos**, **iCloud Drive**, **Notes**, etc. on iCloud.com and **hand them to law enforcement under legal process**.

**Turning on ADP deletes the available-after-authentication CloudKit Service keys from Apple's HSMs and moves them into the account's iCloud Keychain protection domain — i.e. onto the user's trusted devices only.** The category count protected by E2EE rises from **14 to 23**, now including **iCloud Backup, Photos, iCloud Drive, Notes, Reminders, Safari bookmarks, Voice Memos, Wallet passes, Freeform**, and more. Apple no longer holds keys it could be compelled to use, for those categories.

Three details that change how you investigate:

- **The exceptions stay warrantable.** Even with ADP on, **iCloud Mail, Contacts, and Calendar are NOT end-to-end encrypted** — they must interoperate with the global SMTP/CardDAV/CalDAV ecosystem, so Apple keeps those keys and can still produce that data under legal process. When ADP forecloses everything else, *those three are where the cloud route still goes*.
- **The backup was the backdoor to Messages — until ADP.** iMessage is E2EE in transit, and "Messages in iCloud" is itself E2EE — but **without ADP, the key to Messages in iCloud is included in your iCloud Backup, and the backup is available-after-authentication.** So historically Apple could produce your iMessages by way of the backup, even though Messages "is encrypted." ADP makes the **backup itself** E2EE, which finally closes that path. If you're chasing iMessage content via Apple and the account has ADP, that door is shut; pivot to the *other* endpoint's device or its backup.
- **ADP changes the cloud, not the device.** ADP does **nothing** to on-device Data Protection. A full-file-system or AFU logical extraction of an ADP-enabled phone yields exactly the same plaintext as a non-ADP phone — the class keys, the keybag, the BFU/AFU behavior are all identical. **ADP forecloses the *cloud* avenue only.** Don't let "ADP" on a case sheet talk you out of local acquisition.

Enabling ADP **requires the user to first set up account recovery** (a Recovery Contact and/or a Recovery Key), because Apple can no longer reset their way back in. Forensically, possession of the **Recovery Key** (a 28-character code) is a genuine asset — it can re-establish access to the account's E2EE material. ADP also restricts **iCloud.com web access** by default: the user must explicitly authorize web access from a trusted device for each session.

> 🔬 **Forensics note — detecting ADP is mostly detecting *failure*.** There's no clean public CLI flag that says "this account has ADP." You detect it where it bites: a legal-process return or a token-/credentials-based iCloud extraction (Elcomsoft Phone Breaker-class, or `mvt`/your own CloudKit pull) comes back **encrypted** for Backup/Photos/Drive/Notes while **Mail/Contacts/Calendar** come back **plaintext** — that split *is* the ADP signature. On a device you control, the account's Data & Security / iCloud state reflects it, but treat the cloud-return ciphertext as the authoritative tell.

> ⚖️ **Authorization:** ADP doesn't just *technically* foreclose the cloud route — it changes what a lawful order can *yield*. A warrant served on Apple for an ADP account's Backup/Photos/Drive returns **ciphertext Apple cannot decrypt**; the only producible categories are Mail/Contacts/Calendar (plus pointer/metadata). That is by design and is not defeatable by drafting a broader order — there is no key for Apple to surrender. Scope your legal process accordingly: when the target data is E2EE under ADP, the productive authority is one that reaches the **device or its local backup** (or the counterpart endpoint), not Apple's servers. Document the ciphertext return as the basis for pivoting, and never represent E2EE cloud data as "available from Apple" in an affidavit.

### What each forecloses — the synthesis

```
                         DEFAULT          LDM            SDP            ADP
                         device           on             on             on
 ─────────────────────────────────────────────────────────────────────────────
 Wired logical (AFU,     OK               BLOCKED        BLOCKED         OK
 new pairing)                             while locked   (passcode no    (cloud-
                                          (unlock first) longer mints    only
                                                         a pairing       feature)
                                                         off-site)
 ─────────────────────────────────────────────────────────────────────────────
 Wired logical, EXISTING OK               OK if unlocked OK (AFU)        OK
 pairing record                           (LDM blocks
                                          while locked)
 ─────────────────────────────────────────────────────────────────────────────
 Full-file-system (FFS)  per exploit/     per exploit    per exploit     SAME
 on-device extraction    BootROM avail.   (unchanged)    (unchanged)     (ADP is
                                                                         cloud-only)
 ─────────────────────────────────────────────────────────────────────────────
 iCloud — warrant to     Backup/Photos/   same           same            ONLY Mail/
 Apple                   Drive/Notes +                                   Contacts/
                         Mail/Contacts/                                  Calendar;
                         Calendar                                        rest = E2EE
 ─────────────────────────────────────────────────────────────────────────────
 iCloud — token/cred     full set         same           same            ciphertext
 extraction                                                              for E2EE
                                                                         categories
 ─────────────────────────────────────────────────────────────────────────────
 Remote zero-click       full surface     SHRUNK         unchanged       unchanged
 exploit surface                          (JIT off,
                                          parsers off)
```

The point of the table: **the three features cut three different cords.** LDM and SDP mostly attack the *wired* and *remote* planes; ADP attacks the *cloud* plane and leaves the device untouched. An examiner who internalizes this stops asking "is it locked down?" and starts asking "which of my four avenues survives?"

### The UK saga — why "is ADP even available?" is a jurisdiction question (dated)

> *Durable point:* ADP availability is **policy-contingent and geographic**, so always check whether ADP is even offerable in the subject's jurisdiction before assuming a category is E2EE.

The volatile specifics as of **2026-06-26** (re-verify): in **January 2025** the UK government served Apple a secret **Technical Capability Notice** under the Investigatory Powers Act ("IPA"/"Snooper's Charter") demanding a means to access ADP-protected data — effectively a backdoor. Apple's response in **February 2025** was to **withdraw ADP for UK users entirely** rather than weaken it: new UK enrollments were blocked and existing UK users were told to disable it. Apple filed a legal challenge (Investigatory Powers Tribunal), set for early 2026. In **August 2025**, following US diplomatic pressure (DNI involvement), reporting indicated the UK had *dropped* the broad demand — but Apple had **not** re-enabled ADP for the UK as of late-2025 reporting, and the EFF flagged a narrower renewed UK demand targeting UK users' backups. **Bottom line for an examiner: in the UK, ADP-protected categories may simply not exist on the account**, which (perversely, from a privacy view) keeps the warrant-to-Apple cloud route open there. Confirm the current state for the relevant jurisdiction at author time — this is actively moving.

## Hands-on

There is no on-device shell — everything runs on your Mac analysis host against a Simulator, a connected (consented) device, a sample image, or the cloud. The commands below show what *succeeds*, what *fails*, and what the failure proves.

### Inspect pairing / trust state with libimobiledevice

```bash
# Is there a usable pairing record for the attached device?
idevicepair list
idevicepair validate           # "SUCCESS: ..." if a valid record exists & device is unlocked enough

# Attempt to mint a NEW pairing record (this is the SDP-sensitive step)
idevicepair pair
#   Default device, AFU, passcode entered on-device  ->  "SUCCESS: Paired with device <udid>"
#   SDP on + away from familiar location             ->  device shows Trust dialog demanding
#                                                        Face ID/Touch ID; passcode-only won't
#                                                        complete -> pair stalls / errors
```

A `pair` that *requires* a face/finger and rejects the passcode is your real-world confirmation that SDP is active and the location is unfamiliar. Document it — that observation is evidence about the device's configuration.

### Confirm ADP is cloud-only: a local backup is unaffected

```bash
# A normal encrypted local backup works regardless of ADP (ADP governs iCloud, not Finder/iTunes backups)
idevicebackup2 encryption on <BACKUP_PASSWORD>     # set a backup password if none
idevicebackup2 backup --full ./case_backup/

# The resulting Manifest.db / Manifest.plist + files decrypt with the backup password,
# whether or not the account has ADP. ADP never enters this path.
```

This is the concrete proof of the "ADP changes the cloud, not the device" claim: you can pull a complete encrypted local backup from an ADP account.

### Read a managed-preference flag offline (mechanism demo)

On a full-file-system image, the LDM/SDP state lives in system preference domains. The *mechanism* — copy-then-read a preference plist without touching the original — is the same one you used on macOS:

```bash
# NEVER read in place; copy first (a plist read is low-risk, but keep the discipline)
cp "<image>/private/var/Managed Preferences/mobile/<domain>.plist" /tmp/pref.plist
plutil -p /tmp/pref.plist           # human-readable dump; look for the Lockdown-Mode / SDP boolean
#  (Verify the exact domain + key name against the iOS 26 build you're examining — do not assume.)
```

> Treat the precise domain/key as a **per-version detail to confirm**, not a memorized constant. The reliable cross-check is always the negative-space artifact survey below.

### Hunt mercenary-spyware IOCs with mvt

```bash
pipx install mvt
# From a (consented) encrypted iTunes/Finder backup:
mvt-ios decrypt-backup -p '<backup_password>' -d ./decrypted ./case_backup/
mvt-ios check-backup --output ./mvt_out ./decrypted
# Or straight from a sysdiagnose / FFS. mvt flags known Pegasus/Predator domains,
# process anomalies, and (crucially) the receipt of an Apple Threat Notification.
```

### What Apple can actually return (read the guidelines, don't guess)

```bash
# There is no API for this — it's a document. Pull Apple's Legal Process Guidelines (US)
# and read the iCloud section: with ADP on, Backup/Photos/Drive/Notes/etc. are returned
# as customer-keyed ciphertext Apple cannot decrypt; Mail/Contacts/Calendar remain producible.
open "https://www.apple.com/legal/privacy/law-enforcement-guidelines-us.pdf"
```

## 🧪 Labs

> **Substrate note for this lesson:** every avenue these features touch is device-only — SEP-backed biometrics, the pairing handshake, iCloud key escrow. The **Simulator has none of it** (no SEP, no Data Protection, no biometric matcher, no real iCloud account, and the LDM/SDP policy daemons don't enforce), so the Simulator labs teach you to recognize an artifact's *presence* so you can reason about its *absence*; the device-bound mechanics are read-only walkthroughs against public images / the literature. None require a phone.

### Lab 1 — Build the "negative-space" artifact baseline (Simulator)

**Goal:** know what a *normal* device produces, so you can spot the holes Lockdown Mode leaves.

1. Boot a Simulator and open Messages and Safari:
   ```bash
   xcrun simctl boot "iPhone 17 Pro"
   xcrun simctl openurl booted "https://example.com"
   ```
2. In the Simulator's Messages, send yourself a message containing a URL and a non-image attachment, so a **link preview** and an **attachment** row get created.
3. Find the SMS/iMessage store under the Simulator's data container and copy it before querying:
   ```bash
   DEV=$(xcrun simctl get_app_container booted com.apple.MobileSMS data 2>/dev/null || \
         echo "~/Library/Developer/CoreSimulator/Devices/<UDID>/data")
   # The chat store + attachments live under the Messages container; copy, don't query in place:
   find ~/Library/Developer/CoreSimulator/Devices -name 'sms.db' 2>/dev/null
   ```
4. In a copy of `sms.db`, locate the **attachment** rows and any **rich-link / preview** metadata. Write down which tables/columns hold the link preview and the attachment path.
5. **Now reason:** under Lockdown Mode, steps 2–4 produce *nothing* — the preview is never fetched, the non-image attachment never lands. Your detection routine on a real image is "are these rows present after date X?" Caveat: the Simulator never enforces LDM, so you are learning the artifact's *shape*, not watching the suppression.

### Lab 2 — Detect Lockdown Mode in a full-file-system image (read-only walkthrough)

**Substrate:** a public iOS reference image (Josh Hickman / Digital Corpora) or any FFS you're authorized to examine. The Simulator can't model LDM, so this is a structured walkthrough.

1. Survey for the **state flag** first: copy the candidate system/managed preference plist and `plutil -p` it, looking for the Lockdown-Mode boolean (verify the key for that build).
2. Survey the **negative space**, which is more robust than any single flag:
   - **Messages:** any non-image attachments or rendered link previews *after* a candidate enablement date? Their disappearance bounds the window.
   - **Photos:** any **Shared Album** assets/membership? LDM strips them.
   - **FaceTime/call history:** any inbound calls from numbers with no prior outbound? LDM blocks unsolicited inbound.
   - **Configuration profiles:** evidence of *blocked/failed* profile installs.
3. Cross-check **2G/3G**: prolonged absence of legacy-RAT cell records can corroborate (weak signal alone).
4. Write the finding as a **bounded interval**, not a point: "Lockdown Mode consistent with enabled from ≈\<date> onward, based on cessation of \[artifact classes]." You usually cannot recover the exact toggle timestamp from a single flag — say so.

### Lab 3 — Why your forensic bridge won't pair (read-only walkthrough)

**Substrate:** the Elcomsoft SDP writeup + the libimobiledevice `idevicepair` flow above; no device needed.

1. Trace the trust handshake: a `Trust This Computer?` prompt mints a pairing record under `lockdownd`. Default behavior accepts the **passcode** to confirm.
2. Apply SDP-away-from-home: the confirmation now demands **Face ID/Touch ID with no passcode fallback**. A passcode-only operator — even one who *knows* the passcode — cannot mint a fresh pairing.
3. Enumerate your remaining moves and their preconditions: (a) reuse an **existing valid pairing record** from a seized trusted host (works on AFU); (b) bring the device to an actual familiar location (rarely feasible/ethical); (c) obtain biometric consent under appropriate authority; (d) fall back to a **BootROM-level FFS** path **iff** the SoC is in the A8–A13 exploit window. Note that (d) is unaffected by SDP — SDP gates *pairing*, not silicon exploits.
4. Record the SoC generation and OS version: on **A14+ silicon** (no public BootROM exploit), an active SDP plus no usable pairing record plus no biometric consent is frequently a *hard stop* for logical acquisition. Knowing that early reshapes the whole acquisition plan.

### Lab 4 — The ADP cloud wall, on paper (read-only walkthrough)

**Substrate:** Apple's iCloud security guide + Legal Process Guidelines; reason it through, no account.

1. List the 23 ADP-E2EE categories vs. the 14 default; circle the three permanent exceptions (**Mail, Contacts, Calendar**).
2. For a hypothetical iMessage-content request: trace it **with** ADP (blocked — backup is E2EE, Messages key not at Apple) vs. **without** ADP (recoverable via the available-after-auth backup). Articulate why "iMessage is encrypted" did *not* historically protect it from a backup-based return.
3. Pretend a token/credentials iCloud pull returns ciphertext for Backup/Photos/Drive but plaintext for Mail/Contacts/Calendar. State the conclusion in one sentence ("ADP is enabled; pivot to the device, the counterpart endpoint, or the three non-E2EE categories").
4. Add the jurisdiction check: confirm whether ADP is even *available* in the subject's country (the UK case) before concluding a category is E2EE.

## Pitfalls & gotchas

- **Don't try to "just turn off Lockdown Mode" to ease acquisition.** Disabling LDM requires a **restart**, which drops the device from AFU to **BFU** and destroys live key access — you'd trade an inconvenience for a catastrophe. (Same trap as letting the 72 h inactivity-reboot fire; see [[passcode-bfu-afu-and-inactivity]].)
- **Conflating Lockdown *Mode* with `lockdownd`/lockdown *records*.** They're unrelated and pull in opposite directions. Re-read the naming-collision callout until it's reflexive.
- **Assuming ADP blocks local acquisition.** It does not. ADP is cloud-only; on-device Data Protection is identical with or without it. A subject's lawyer flagging "ADP" should never deter a local FFS/AFU pull.
- **Assuming ADP encrypts Mail/Contacts/Calendar.** It never has — those three stay producible by Apple. If those are your target categories, ADP doesn't help the subject and the warrant route is open.
- **Forgetting iMessage's backup backdoor on *non*-ADP accounts.** "iMessage is E2EE" lulls examiners into skipping the iCloud Backup, which (without ADP) carries the Messages key. Check the backup.
- **Treating "familiar locations" as fixed.** SDP's relaxation depends on the *subject's* learned Significant Locations; your lab is never one of them. But a stricter user may have set "Require Security Delay: **Always**," removing even the home/work relaxation — confirm which.
- **Assuming SDP is off because it's "opt-in."** SDP is opt-in (introduced **iOS 17.3**; the **"Always"** Security-Delay option arrived in **17.4**) and must be enabled *before* a theft to bite — but the at-risk subject whose phone you're imaging is exactly the likely adopter. *Assume a modern seized device may be SDP-protected and confirm before betting an acquisition plan on a fresh pairing.* (Whether any *current* build ships SDP **default-on** is a moving, version-specific detail — verify against the live release rather than asserting it.)
- **Expecting a precise enablement timestamp.** These are mostly **state flags**, not event streams. You bound the window via negative-space artifact cessation; don't overstate to a point-in-time.
- **Letting an old `mvt`/IOC list go stale.** Mercenary-spyware indicators rot fast; pull current IOCs (Amnesty/Citizen Lab/`mvt` upstream) before every spyware triage.

## Key takeaways

1. Lockdown Mode, SDP, and ADP are **subtractive** controls: each *removes* an avenue (remote surface / passcode-trust / Apple-held keys) rather than adding cryptography. Reason about them as cords cut, not walls built.
2. **They hit different planes.** LDM shrinks the remote zero-click surface; SDP demotes the passcode and breaks fresh pairing off-site; ADP deletes Apple's iCloud decryption keys. Know which avenue each closes.
3. **ADP is cloud-only.** It never changes on-device Data Protection — local FFS/AFU acquisition of an ADP phone yields the same plaintext as any other. The casualty is the *cloud* route.
4. **The ADP exceptions are your foothold:** iCloud **Mail, Contacts, Calendar** are never E2EE and remain warrantable; and **without** ADP the iCloud **Backup carries the Messages key**, so iMessage content is recoverable from Apple despite "E2EE."
5. **SDP breaks the pairing handshake:** away from familiar locations the passcode no longer mints a new pairing — biometric only. A pre-existing pairing record on an AFU device is the escape valve. Opt-in since **iOS 17.3**, but assume a careful subject enabled it — confirm before relying on a pairing-based pull.
6. **Detect by negative space.** No single timestamped event marks LDM/SDP enablement — bound the window via absent artifact classes (link previews, non-image attachments, shared albums, unsolicited-inbound calls).
7. **Never reboot to clear a protection** (disabling LDM forces a restart → BFU). Never let convenience cost you AFU.
8. **ADP availability is geographic and political** (the UK TCN saga) — verify it even *exists* for the jurisdiction before assuming a category is E2EE.

## Terms introduced

| Term | Definition |
|---|---|
| Lockdown Mode (LDM) | Opt-in, system-wide attack-surface-reduction mode that disables WebKit JIT, most message attachment types and link previews, unsolicited FaceTime, Shared Albums, config-profile/MDM install, and wired data while locked — for users targeted by mercenary spyware. |
| Stolen Device Protection (SDP) | Opt-in protection that, when the device is away from familiar locations, requires biometric-only auth (no passcode fallback) for sensitive actions and imposes a 1-hour Security Delay on account-control changes. Introduced iOS 17.3; the "Always" Security-Delay option added in 17.4. |
| Security Delay | SDP's mandatory biometric → wait 1 hour → biometric sequence gating Apple Account password / device passcode / SDP-disable / recovery changes. |
| Familiar locations | System-learned home/work/frequent locations (from Significant Locations / `routined`) where SDP relaxes its extra requirements. |
| Advanced Data Protection (ADP) | Opt-in iCloud setting that deletes the available-after-authentication CloudKit Service keys from Apple's HSMs and keeps them only on trusted devices, raising E2EE iCloud categories from 14 to 23 and removing Apple's ability to decrypt them. |
| CloudKit Service key | Per-user, per-service asymmetric key rooting an iCloud container's key hierarchy; either E2EE (device-only) or available-after-authentication (HSM-escrowed). |
| Available-after-authentication | iCloud key class escrowed in Apple's HSMs and releasable to Apple servers post-auth — the basis for iCloud.com viewing and legal-process production; deleted from HSMs when ADP is enabled. |
| `lockdownd` / lockdown records | The on-device pairing/trust daemon and the pairing certificates (`/var/db/lockdown/`) used for AFU logical acquisition — unrelated to Lockdown *Mode* despite the name. |
| Threat Notification | Apple's targeted-spyware alert to a likely mercenary-spyware victim; both a defensive prompt and a forensic artifact correlating with protection-feature enablement. |
| FORCEDENTRY | The 2021 NSO zero-click iMessage exploit (a JBIG2 overflow in the CoreGraphics PDF decoder, disguised as a `.gif`, that built a Turing-complete weird machine and bypassed BlastDoor) — exemplifies the attack class Lockdown Mode is designed to blunt. |
| Technical Capability Notice (TCN) | A secret UK Investigatory Powers Act order; the January 2025 TCN to Apple precipitated ADP's withdrawal for UK users. |

## Further reading

- Apple Platform Security Guide — *Lockdown Mode*, *Advanced Data Protection for iCloud*, *iCloud encryption* (the CloudKit Service-key hierarchy, the 14→23 category list, the Mail/Contacts/Calendar exceptions).
- Apple Support — "About Stolen Device Protection for iPhone" (support.apple.com/120340); "Advanced Data Protection for iCloud" (security guide); "Apple can no longer offer Advanced Data Protection in the United Kingdom" (support.apple.com/122234).
- Apple Legal Process Guidelines (US) — what iCloud categories Apple can/can't produce; the ADP effect on returns.
- Andrea Fortuna — "iOS Lockdown mode and forensic analysis: a technical perspective" (andreafortuna.org, 2026-03-29) — the negative-space detection method.
- ElcomSoft blog — "Forensic Implications of Apple Stolen Device Protection" (2026-06) and "Forensic Implications of iOS Lockdown (Pairing) Records" (the `lockdownd`-records side of the naming collision).
- Citizen Lab & Amnesty International Security Lab — Pegasus/Predator forensic methodology; the IOC sets behind `mvt`.
- `mvt` (github.com/mvt-project/mvt) — Mobile Verification Toolkit: backup/FFS/sysdiagnose spyware triage.
- libimobiledevice / pymobiledevice3 — `idevicepair`, `idevicebackup2` man pages and source for the pairing/backup mechanics.
- EFF Deeplinks — coverage of the UK Investigatory Powers Act ADP order and its 2025 reversals (for the jurisdiction-availability angle).

---
*Related lessons: [[data-protection-and-keybags]] | [[passcode-bfu-afu-and-inactivity]] | [[the-ios-security-model]] | [[icloud-acquisition-and-advanced-data-protection]] | [[logical-acquisition-with-libimobiledevice]] | [[lockdown-mode-and-enterprise-posture]] | [[location-history]] | [[the-jailbreak-landscape-2026]]*
