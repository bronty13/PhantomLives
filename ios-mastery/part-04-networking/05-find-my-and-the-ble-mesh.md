---
title: "Find My & the BLE mesh"
part: "04 — Networking & Connectivity"
lesson: 05
est_time: "45 min read + 15 min labs"
prerequisites: [radios-wifi-bt-nfc-uwb, wifi-bluetooth-and-proximity]
tags: [ios, networking, find-my, ble-mesh, airtag, openhaystack]
last_reviewed: 2026-06-26
---

# Find My & the BLE mesh

> **In one sentence:** Find My turns roughly a billion Apple devices into an anonymous, end-to-end-encrypted location-relay mesh in which a lost device or AirTag beacons a *rotating* P-224 public key over BLE, any nearby Apple device silently encrypts its own GPS fix to that key and uploads it, and only the owner — who alone holds the matching private key — can later fetch and decrypt the report from Apple, who never sees the location in plaintext.

## Why this matters

Find My is the most-deployed piece of applied public-key cryptography most people will ever carry, and it is a forensic double-edged sword. The same rotating-key design that makes the beacons un-trackable by a third party also leaves a rich, decryptable trail *on the owner's device*: which AirTags are paired, their identity keys, where they've been, and — through the anti-stalking machinery — a log of *other people's* trackers that followed the device around. For a forensicator, `searchpartyd`'s on-disk stores answer "what devices does this person own?", "where was this AirTag?", and "was this person being stalked, and by whose tag?". For a builder/RE, the protocol is fully reverse-engineered (SEEMOO/OpenHaystack), so you can deploy your own beacons, query the mesh, and understand exactly which security property protects whom. And because the whole thing rides BLE advertisements and an iCloud-Keychain-synced key hierarchy, it ties together everything from [[05-radios-wifi-bt-nfc-uwb]] to [[08-keychain-on-ios]] to [[07-apple-account-icloud-and-apns]]. It is also one of the cleanest case studies in the course of a system where the *cryptography* is fully public yet the *evidence* is still gated by lock state, key custody, and an access-controlled server — exactly the BFU/AFU and key-recovery realities you'll meet again across Parts 07–08.

## Concepts

### The mesh in one diagram

Find My (the "Find My network", internally **Search Party**) has three roles. A device can be all three at different moments.

```
   LOST DEVICE / AIRTAG            FINDER (any nearby Apple device)        OWNER
   "in beacon mode"               "report submitter"                      (online)
   ┌───────────────────┐          ┌──────────────────────────┐           ┌────────────────────┐
   │ rolls advert key   │  BLE adv │ overhears p_i            │           │ holds d_0, SK_0    │
   │ p_i per period     │ ───────► │ takes own GPS fix L      │           │ (iCloud Keychain)  │
   │ broadcasts p_i     │          │ C = ECIES_encrypt(p_i,L) │           │                    │
   │ (no GPS, no radio  │          │ idx = SHA-256(p_i)       │  HTTPS    │ recompute p_i      │
   │  beyond BLE)       │          │ upload {idx, C, t}  ─────┼──────────►│ idx=SHA-256(p_i)   │
   └───────────────────┘          └──────────────────────────┘  to Apple │ GET reports[idx]   │
                                                                  server  │ L = ECIES_decrypt  │
                                          (Apple stores ciphertext        │     (d_i, C)       │
                                           keyed by opaque hash;          └────────────────────┘
                                           cannot decrypt or link)
```

The genius is the asymmetry: the *finder* does all the location work and pays the battery/bandwidth cost, anonymously, for a stranger's device; the *server* is a dumb encrypted key-value store indexed by hashes it can't reverse to an identity; only the *owner* can read anything. Nobody in the path except the owner ever learns where the lost device is.

Notice what the lost device *isn't* doing: it has no GPS fix, no cellular link, and no idea where it is. It only emits a key. All spatial knowledge is contributed by the finders that happen to walk past — which is why a single AirTag can be located worldwide with a coin cell and a BLE radio, and why coverage is a function of *Apple-device density*: dense in a city, blind in a forest. The same property bounds the forensics — you can only ever recover positions where some finder was present to relay one.

> 🖥️ **macOS contrast:** You already met this mesh in `macos-mastery` as **Find My Mac + Activation Lock** — a MacBook left in a café still gets located, and a stolen one stays bricked to its iCloud account. Same network, same crypto, same `searchpartyd`. iOS just adds the *accessory* side (AirTags / Find My-network items) and the anti-stalking countermeasures, and on a phone the device is far more often the *finder* relaying for others. The Mac in front of you is a full participant: it runs `searchpartyd`, holds beacon keys, submits reports, and — crucially for the labs — keeps the **same on-disk stores at `~/Library/com.apple.icloud.searchpartyd/`** that an iPhone keeps at `/private/var/mobile/Library/com.apple.icloud.searchpartyd/`.

### The key hierarchy: one secret, infinitely many beacons

When you pair an AirTag (or a device enters Find My), the owner ecosystem generates a **master beacon key**:

- an elliptic-curve key pair `(d_0, p_0)` on **NIST P-224** (`secp224r1`), and
- a 32-byte **symmetric seed** `SK_0`.

`d_0` (private) and `SK_0` are the crown jewels. They are generated on-device, stored in the **Keychain**, and synced across the owner's devices through **end-to-end-encrypted iCloud Keychain** — so every device the owner signs into can independently locate the AirTag, but Apple's servers never see them. `p_0` (public) is all that's needed to *fetch* reports, but `d_0` is needed to *decrypt* them.

From this seed the system derives a never-ending sequence of **rolling advertisement keys**, one per ~15-minute period `i` (that 15-minute figure is the protocol's *key-derivation* period and the cadence a lost *iPhone/iPad/Mac* broadcasts at; a separated *AirTag* deliberately advertises each derived key for a full day — see *Nearby vs. separated* below). Two steps, both built on the **ANSI X9.63 KDF with SHA-256** (the same KDF Apple's CryptoKit ECIES uses everywhere):

```
# 1. Ratchet the symmetric seed forward (one-way; can't go back)
SK_i  = KDF( SK_{i-1}, label="update",    length=32 )

# 2. Diversify into two scalars
(u_i, v_i) = KDF( SK_i, label="diversify", length=72 )   # 36 bytes each
u_i = (u_i mod (n-1)) + 1                                 # n = order of P-224
v_i = (v_i mod (n-1)) + 1

# 3. Derive the period's key pair
d_i = ( d_0 * u_i + v_i )  mod n          # rolling PRIVATE key
p_i =   d_i * G                            # rolling PUBLIC key (G = base point)
```

The arithmetic identity that makes the whole scheme cheap for the owner:

```
p_i = u_i * p_0 + v_i * G          # computable from the PUBLIC master key alone
```

So a *finder* (and the **public**) needs only `p_i` to encrypt; the owner needs `d_i` to decrypt. A device that has only `p_0` can still derive every future `p_i` and fetch reports, but cannot read them. This is exactly how a researcher tool tracks an OpenHaystack tag it doesn't "own": it knows `p_0`, computes the `p_i` series, hashes them, and pulls reports — without ever decrypting more than it deployed itself.

Picture the ratchet as a one-way chain that fans out one disposable identity per period:

```
 SK_0 ──update──► SK_1 ──update──► SK_2 ──update──► SK_3 ── … (forward only; SHA-256 ratchet)
   │                │                │                │
 diversify        diversify        diversify        diversify
   │                │                │                │
 (u_0,v_0)        (u_1,v_1)        (u_2,v_2)        (u_3,v_3)
   │                │                │                │
   ▼                ▼                ▼                ▼
  p_0              p_1              p_2              p_3      ◄── 15-min advertisement keys
 (master)        15:00            15:15            15:30         + the BLE MAC for that slot
```

To locate a tag "over last Tuesday" the owner walks the chain to Tuesday's slots, derives ~96 `p_i` (4/hour × 24h), hashes each to an index, and asks Apple for all of them in one batched query — then decrypts whatever comes back with the matching `d_i`. The number of indices you must compute scales linearly with the time window, which is why fetching a long history is heavier than fetching "right now."

> 🔬 **Forensics note:** Because the symmetric ratchet is *one-way* (`SK_i → SK_{i+1}` only), seizing a device tells you keys *going forward* from the current `SK_i`, but recovering historical advertisement keys requires the stored `SK_0`/`d_0` (present in the Keychain and in `searchpartyd`'s `OwnedBeacons`/`ItemSharingKeys.db`). With those master values you can regenerate the *entire* `p_i` history and independently re-query Apple for that tag's location reports — turning a seized phone into a tool that re-derives where the owner's own AirTag has been.

### The BLE advertisement: a public key on the air

In each broadcast period (≈15 min by default; see the separated-AirTag caveat below) the beaconing device emits `p_i` as a BLE **manufacturer-specific advertisement** using Apple's company ID **`0x004C`** and the **offline-finding type byte `0x12`** (length `0x19` = 25). P-224 public keys are 28 bytes; a BLE advertisement is only 31 bytes total, so Apple smears `p_i` across two places:

```
BLE random (static) address  : p_i[0..5]   first 6 bytes of the key
   └─ top two bits of byte0 forced to 0b11 (BLE "static random address" rule)
Manufacturer payload:
   0x4C 0x00            Apple company ID (little-endian)
   0x12                 type = offline finding
   0x19                 length = 25
   <status byte>        battery / maintained-vs-separated hint
   p_i[6..27]           remaining 22 bytes of the public key
   <2 bits>             the two high bits of p_i[0] (recovered into the address)
   <hint/counter byte>  iOS finder: an owner-device hint (often 0x00). A separated
                        AirTag uses it as a counter that ticks every ~15 min even
                        though the key itself stays fixed for the day (Catley).
```

Two consequences a third-party tracker can't get around:

1. **The BLE MAC address is a random static address that rotates in lockstep with the key** — every ~15 min for a lost iOS device, but only ~daily for a separated AirTag (it rolls *with* the key, never independently). Either way there is no stable hardware identifier to follow.
2. **The advertised "identity" *is* an ephemeral public key** that looks like random bytes and changes every period, so consecutive beacons can't be linked to each other or to the device's owner.

> 🖥️ **macOS contrast:** This is the same BLE-privacy posture as the **rotating, resolvable private addresses** you saw behind Continuity/Handoff in [[04-wifi-bluetooth-and-proximity]] — but pushed further. Continuity addresses rotate so passive sniffers can't follow a Mac around a conference; Find My beacons rotate *and* carry no resolvable identity at all, because the "address" is literally a throwaway public key. The unlinkability is structural, not just a randomized MAC.

### Nearby vs. separated: two states, two rotation cadences

A device/AirTag distinguishes two states, encoded in the **status byte** of the advertisement, and this distinction is what the anti-stalking layer keys off:

- **Nearby / "maintained" / connected** — the owner's device is in BLE range, so the item is effectively already "found." Per Adam Catley's teardown, an AirTag in this state does **not** beacon into the offline-finding mesh at all (no `0x12` offline-finding broadcasts while connected) — there is nothing for finders to relay and no reports are generated.
- **Separated / "lost"** — no owner device has been seen for a threshold time (deliberately fuzzed, historically on the order of hours). *Now* the item broadcasts the `0x12` offline-finding advertisement that finders relay into reports — and this is also what triggers a victim's phone to start counting "this thing is following me."

Here is the counter-intuitive part, and the point the casual "the key rotates every 15 minutes" summary gets wrong for AirTags: **a separated *AirTag* deliberately rotates its full advertising key *slowly* — only about once every 24 hours (Catley clocked the change at 04:00 local) — while a small *counter byte* in the payload increments every ~15 minutes.** The clean 15-minute *full-key* rotation the SEEMOO paper documents is the cadence a lost **iPhone/iPad/Mac** uses in offline-finding mode; an AirTag *slows down on purpose* once separated. The reason is exactly the anti-stalking design below: if a planted tag re-keyed every 15 minutes, a victim's phone could never recognize "the same tag has shadowed me for three hours." That same slow rotation is a privacy weakness for the *owner* — anyone in BLE range can re-identify a separated tag for the rest of the day — and Positive Security's **"Find You"** clone abused the *inverse* (re-keying fast while separated) to slip past unwanted-tracking detection entirely.

The status byte also carries a coarse **battery level** (full / medium / low / very-low) and a maintained-vs-separated flag, which is why your `bleak` scanner can tell a *separated* tag from a merely *nearby* device without decrypting anything. The practical upshot: the mesh only does heavy lifting for genuinely *lost/separated* items, and that same "separated and moving with a stranger" signal is precisely the stalking primitive.

> 🔬 **Forensics note:** The nearby/separated transition has an evidentiary meaning. A tag that flips to *separated* and starts generating dense reports marks the moment it left its owner — e.g., when it was slipped into a victim's bag, or when a stolen device left the thief's proximity. Correlate the report cadence (sparse → dense) against `WildModeAssociationRecord` first-seen times to bracket *when* separation happened.

### The location report: ECIES to a stranger's key

A finder that overhears `p_i` does standard **ECIES** (Apple's CryptoKit flavor):

1. Generate an **ephemeral** P-224 key pair `(d_e, p_e)`.
2. `shared = ECDH(d_e, p_i)` → run **ANSI X9.63 KDF(SHA-256)** over `shared || p_e` to derive a 16-byte AES key + 16-byte IV.
3. `C = AES-128-GCM(key, iv, plaintext = {lat, lon, accuracy, status})`.
4. Build the report: `timestamp || p_e || C || GCM-tag`.
5. Compute the server **index** `idx = SHA-256(p_i)` and upload `{idx, report}` to Apple over HTTPS.

Apple stores the encrypted blob under the opaque `idx`. To recover location the owner: derives the `p_i` for each slot across the window of interest, computes each `idx = SHA-256(p_i)`, asks Apple "any reports under these indices?" (the server is a key-value store that accepts up to ~256 hashes per request, returning up to ~20 reports per key), then for each hit does `shared = ECDH(d_i, p_e)`, re-derives the AES key, and GCM-decrypts. Apple retains reports for a **limited window**: the SEEMOO measurement found reports recoverable for up to ~7 days, and Apple's own support text says Find My can't show a location once **more than seven days** have passed since the last network sighting — so the ~7-day figure is corroborated from both sides (still re-verify at author time). Finders **batch** uploads to save power — SEEMOO measured a median ~26 minutes from sighting to upload, so a "live" Find My location is often tens of minutes stale.

The decrypted plaintext is small and fixed-layout — roughly: latitude and longitude as **signed 32-bit integers scaled by 1e7** (degrees × 10^7), a 1-byte horizontal **accuracy/confidence**, and a **status** byte (the beacon's own battery/state echoed back). The *finder* device that submitted it is **never named** in the report — that's the anonymity guarantee, and the reason a fetched location tells you *where the lost item was* but nothing about *whose phone* relayed it.

> 🔬 **Forensics note:** Two timestamps live in a report and they mean different things. The report carries the **finder's GPS-fix time** (when the sighting happened), while the server/fetch layer adds an **upload/seen time**. With the ~26-minute batching lag they can differ materially. When you reconstruct a tag's track via `FindMy.py`, anchor your timeline on the *fix* time, not the upload time — and remember each report carries its own finder fix-timestamp, so multiple finders (or repeat sightings) under the same key still yield distinct time-stamped positions. Temporal resolution therefore tracks *finder density*, not just the key period — which matters for a separated AirTag whose single daily key may still collect many reports.

### What each party can and cannot learn (the unlinkability table)

| Party | Sees the BLE beacon? | Sees the report? | Can identify the device/owner? | Can read the location? |
|---|---|---|---|---|
| Passive BLE sniffer nearby | Yes (rotating `p_i`, rotating MAC) | No | **No** — key & MAC rotate (≈15 min; ~daily for a separated AirTag) and never tie to an owner | No |
| Finder device | Yes | Encrypts & uploads it | **No** — only has a public key | No (encrypts to a key it can't decrypt) |
| Apple server | No | Stores ciphertext keyed by `SHA-256(p_i)` | **No** — index is an opaque hash | No (E2E; no private key) |
| Owner (`d_0`, `SK_0`) | (their other devices) | Fetches by index | Yes (it's their key) | **Yes** — only party who can |

The design's whole point: **make the relay anonymous and the storage blind, so the mesh is useful to owners without being a global tracking dragnet.** The residual privacy risk is exactly what the anti-stalking work below addresses — a *physical AirTag planted on a victim* defeats unlinkability the low-tech way, by simply staying with the victim while its owner reads the (legitimately decryptable, because it's *their* tag) reports.

The threat model the cryptography *does* and *does not* cover is worth stating plainly. It defeats: passive RF tracking of strangers' devices, a curious finder learning what they relayed, and a compromised/ subpoenaed Apple learning locations from the report store alone (the reports are E2E to the owner). It does **not** defeat: an owner abusing their *own* tag to follow someone (the planted-AirTag case — a *policy/UX* problem, hence DULT), an examiner who has lawfully recovered the owner's master keys from `searchpartyd`/Keychain (they become the owner, cryptographically), or correlation against *other* on-device stores. The crypto draws a clean line around *who can read a report*; it was never meant to stop the device's lawful owner — or an authorized examiner standing in the owner's shoes — from reading it.

### AirTags and the anti-stalking countermeasures

An AirTag is a coin-cell (CR2032) BLE beacon + a **UWB** chip for Precision Finding (the **U1** in the original 2021 AirTag; the **U2** in the 2025 AirTag 2, which roughly triples UWB range) + an accelerometer (for separated-mode movement detection) + a piezo speaker + an **NFC** tag (NTAG) that, on tap, surfaces the Lost Mode URL and owner-contact hint. It has no GPS and no cellular — *all* its location ability is borrowed from the finder mesh above; the UWB chip only helps *the owner* close the last few meters once the mesh has put them roughly in range, and the NFC is the serviceability channel DULT relies on. Because a $29 tag that silently reports its location to its owner is a stalker's dream, Apple (and now the industry) layered on countermeasures:

- **"Separated" state and audible alarm.** When an AirTag is away from its owner for a (deliberately not-fully-documented, anti-evasion) period — historically ~8–24 h depending on movement — it enters *separated* mode, and if it then detects movement it **plays a sound** to reveal itself.
- **Unwanted-tracking alerts on the victim's phone.** iOS continuously scans for separated trackers that are *moving with you over time and place*. When one is seen at multiple locations following you, you get **"Item Found Moving With You"**, can make it play a sound, see its serial/identifier, and read NFC-tap instructions to disable it (pull the battery).
- **Precision Finding to the tag.** Once flagged, UWB + ARKit guide the victim straight to the hidden tag.
- **The cross-platform spec — DULT.** Apple and Google co-authored **"Detecting Unwanted Location Trackers"**, submitted to the **IETF (the DULT working group)**. The production rollout landed in **iOS 17.5 and Android 6.0+ in May 2024**, so a *non-Apple* phone also alerts on a moving AirTag (and vice-versa), and compliant third-party tags (Chipolo, eufy, Pebblebee, Motorola, etc.) play by the same rules. Treat exact DULT revision/state as **verify-at-author-time**.
- **AirGuard.** TU Darmstadt's SEEMOO lab ships **AirGuard** (open source, iOS + Android, F-Droid), which scans for separated trackers more aggressively than the OS default and warns after a tracker is seen at 3+ locations — the researcher-grade detector, processing everything on-device.

> ⚖️ **Authorization:** Two distinct legal surfaces here. (1) *Using* an AirTag to track a person without consent is a crime in many jurisdictions (and the basis of civil suits and a multi-district class action against Apple). (2) *Examining* the anti-stalking artifacts on a victim's phone — the records of which tag followed them — is often the **evidence of the stalking** and must be acquired under proper authority with chain of custody intact. Don't conflate the two roles: the same `searchpartyd` directory holds both "tags this person owns" and "tags that were stalking this person."

### Item sharing and third-party accessories

Two wrinkles complicate the clean "one owner, one key" picture:

- **Find My item sharing.** An owner can share an AirTag (or Find My item) with others; the recipient's device receives the key material needed to *locate* it and stores those records under `SharedBeacons/` (with the advertisement data and private keys also landing in `ItemSharingKeys.db`). Forensically this means "this account could see tag X" does **not** prove "this account owns tag X" — a shared tag can be owned by someone else entirely, which matters for attribution.
- **The Find My Network Accessory Program (MFi).** Third-party trackers (Chipolo, eufy, Pebblebee) and even other product categories (some bikes, headphones, Belkin cases) can be **certified to advertise into Apple's mesh** using the same offline-finding payload. To Apple's network they are AirTags-by-another-name; to DULT they must implement the serviceability/separated-state rules. So "an AirTag" in a `WildModeAssociationRecord` may actually be a certified third-party accessory — read the model/category fields before naming the hardware.

> 🔬 **Forensics note:** `SharedBeacons` + `ItemSharingKeys.db` are where "who could track whom" gets nuanced. A shared tag in a suspect's `SharedBeacons` implies a *relationship* with the owner (the sharer invited them) and gives the suspect's device the keys to locate it — relevant to both stalking-by-proxy and to establishing who had visibility into a tagged object's movements.

### How DULT detection actually works

The detection logic is a deliberately simple, on-device heuristic — no cloud, no profiling — and understanding it tells you both why it works and how a determined stalker evades it:

1. **Separated trackers only.** The scanner ignores beacons whose owner is nearby (status byte = nearby/maintained); a tag near *its* owner isn't "following you." It watches the *separated* population.
2. **Persistence across place and time.** It buckets a separated beacon's sightings and only alerts when the same tracker is seen **with you across multiple locations over time** — Apple's OS uses a rolling window keyed to your own movement; AirGuard's threshold is **3+ distinct locations**. A single fleeting sighting (you passed someone's keys) never alerts.
3. **Identity continuity despite rotation.** Here's the subtlety: a *separated* tag rolls its key on a slower cadence (the daily ratchet), so within a tracking window the advertised key is stable *enough* for the scanner to recognize "same tag" across hours — which is exactly the property the anti-stalking design needs and the unlinkability design tries to deny. The trade-off is intentional: perfect 15-minute unlinkability would also blind the victim's phone.
4. **Serviceability.** Once flagged, DULT requires the tracker expose, on an NFC tap, a URL/identifier and disablement instructions, and (for Apple tags) the last 4 digits of the owner's phone number — so a victim (on iOS *or* Android) can identify and silence it.

The evasions follow directly: a tracker that never enters separated mode (owner shadowing the victim), a non-compliant tag that lies about its state, or hardware with a muted speaker. DULT is a floor, not a ceiling — which is why SEEMOO ships AirGuard with a more aggressive scan than the OS default.

> 🔬 **Forensics note:** The DULT/anti-stalking detector running on the *victim's* phone is what writes `WildModeAssociationRecord`. So the very mechanism above is your evidence generator: each "staged"/alerted record is the OS's own contemporaneous determination that a specific separated tracker met the persistence threshold while moving with the victim — an unusually clean, system-authored artifact of the stalking event.

### The research lineage: OWL → OpenHaystack → macless-haystack

Apple published *none* of the above. It came from **SEEMOO/TU Darmstadt's Open Wireless Link (OWL)** project, which reverse-engineered AWDL first (see [[04-wifi-bluetooth-and-proximity]]) and then the offline-finding protocol, published as **"Who Can Find My Devices? Security and Privacy of Apple's Crowd-Sourced Bluetooth Location Tracking System"** (Heinrich et al., PoPETs 2021). They then released **OpenHaystack**: firmware (ESP32, nRF, Linux/BlueZ) that beacons a *fixed* `p_0`, plus a macOS app that fetches and decrypts the reports — i.e., **build-your-own-AirTag** for $5 of hardware, and a research scaffold for measuring the mesh.

The original OpenHaystack had one ugly dependency: fetching reports needs an authenticated request to Apple's `gateway`/`fetch` endpoint, and OpenHaystack got those tokens by piggy-backing on **Apple Mail running with elevated privileges** (an Anisette/auth hack). The modern fork, **macless-haystack** (and the Python **FindMy.py** library), drops the Mail plugin and authenticates directly with an Apple ID + Anisette, so the whole fetch/decrypt loop runs headless on Linux/macOS with no Apple hardware in the path. That same loop is what lets a researcher (or examiner with the master key) reconstruct a tag's history programmatically.

> 🔬 **Forensics note:** OpenHaystack also exposed the **`Send My`** trick (Positive Security): because the *only* thing that distinguishes report indices is the public key you broadcast, you can encode arbitrary bits as a *choice of which keys to advertise*, turning the Find My mesh into a low-bandwidth, BLE-only, internet-egress covert channel — a malware exfil vector that needs no Wi-Fi/cell association. Worth knowing exists when you're explaining how data left an "airgapped" device.

### Activation Lock: the same account, weaponized against theft

The Find My switch you flip also arms **Activation Lock**. When Find My is on, the device's identity is cryptographically bound to the owner's Apple Account: the Secure Enclave records that the device is locked to that account, and Apple's activation servers refuse to re-provision it for anyone else after an erase. A thief who wipes the phone hits an Apple-ID gate at setup that only the original credentials clear — turning a stolen iPhone into a brick (and a Mac into the same, via the same mechanism you saw in `macos-mastery`). Later hardening layered on **Stolen Device Protection** (introduced iOS 17.3, 2024) and **parts pairing / Activation Lock for parts** (iOS 18, 2024) — both carried into the iOS 26 era — so even component-level scavenging is throttled.

> 🖥️ **macOS contrast:** Activation Lock is the piece of Find My you already met head-on in `macos-mastery` — the T2/Secure-Enclave-enforced "this Mac belongs to this Apple ID" lock that survives an erase-install. On iOS it's identical in spirit but spans the whole device lineup and the accessory/parts ecosystem. For an examiner this is the wall *before* acquisition even starts: an Activation-Locked, wiped device is not just encrypted, it's **administratively un-bootable into a usable state** without the account — a fact to capture in the report, since "couldn't acquire" here is a *policy* lock, not (only) a crypto one.

> ⚖️ **Authorization:** Activation Lock status and the bound Apple Account are obtainable from Apple via legal process (the Apple ID is part of what device-bound records can reveal), and is routinely relevant to proving *ownership* — both for returning recovered stolen property and for attributing a planted AirTag to an account. The lock itself is not yours to remove; document it, don't defeat it.

### Where it all lands on disk: `searchpartyd`

Both iOS and macOS persist Find My state under the **`com.apple.icloud.searchpartyd`** container. On iOS: `/private/var/mobile/Library/com.apple.icloud.searchpartyd/`. On macOS: `~/Library/com.apple.icloud.searchpartyd/`. Two sibling locations matter alongside it: the `findmylocated` daemon's store, and — richer for triage — the **Find My app's own cache `com.apple.findmy.fmipcore`**, which holds the higher-level `Items.data`, `Devices.data`, `Owner.data`, `SafeLocations.data`, and `ItemGroups.data` (human-readable owner/item/device inventory that frequently parses *without* the `searchpartyd` Keychain keys). The `searchpartyd` container itself holds the cryptographic core:

| Path (under `…/com.apple.icloud.searchpartyd/`) | What it holds | Format / protection |
|---|---|---|
| `OwnedBeacons/<UUID>.record` | Tags **this account owns** — the master keys (`SK_0`, private material), model, pairing date | Encrypted bplist: AES-GCM, key in Keychain (`searchpartyd` access group) |
| `SharedBeacons/<UUID>.record` | Tags **shared with** this account (Find My item sharing) | Same |
| `BeaconNamingRecords/<UUID>/…` | The human label ("Robert's Keys"), emoji, model, role/category | Encrypted bplist |
| `BeaconStore` / `KeyStore` entries | The 32-byte symmetric/AES keys backing the above | iOS **Keychain**, 32-byte values |
| `Observations.db` (+ `-wal`) | Every Find My-compatible beacon this device **observed** (relayed for others *and* itself): MAC, RSSI, ephemeral pubkey, lat/lon, `scanDate` | **SQLite Encryption Extension (SEE)**, AES-256-OFB, key in Keychain |
| `ItemSharingKeys.db` | Advertisement data + private keys for **shared** beacons; `NearOwnerKeys` predicts upcoming rotated MACs | SEE-encrypted SQLite |
| `WildModeAssociationRecord/<UUID>.record` | **Anti-stalking detections** — a *separated* tracker seen following this device: payload, MAC, first/last seen location, `status` ("staged" = pending alert) | Encrypted bplist |

The encrypted-bplist records share a layout: a small container holding `[0] = 12-byte AES-GCM nonce`, `[1] = 16-byte GCM tag`, `[2] = ciphertext`, decrypted with a 32-byte key pulled from the Keychain `searchpartyd` access group. The two `.db` files use **SEE** (not plain SQLite): 4096-byte pages, a 12-byte IV padded at the end of each page, AES-256-OFB, and only bytes 16–23 of the SQLite header left in plaintext — so you cannot `sqlite3` them directly without the SEE key + the right cipher params.

Once decrypted, `Observations.db` is a small, normalized schema split across three tables joined by an advertisement row id — worth knowing field-by-field because it *is* the relayed-beacon trail:

| Table | Key fields | Meaning |
|---|---|---|
| `ObservedAdvertisement` | `macAddress`, `rssi` | The (rotated, random-static) BLE address and signal strength of a beacon this device heard |
| `ObservedAdvertisementBeaconInfo` | `advertisementData` (28-byte ephemeral pubkey), `beaconIdentifier` (UUID, for owned/shared), sequence/index | Links a heard advertisement to a key and, where applicable, to a known owned/shared beacon |
| `ObservedAdvertisementLocation` | `latitude`, `longitude`, `scanDate` | **This device's own GPS fix** at the moment it relayed the beacon — i.e. where *the phone* was |

`ItemSharingKeys.db`'s `NearOwnerKeys` table is subtler: it stores `nearOwnerAdvertisement` — the **predicted upcoming rotated MACs** for shared beacons — plus an `index`. That means the device pre-computes a shared tag's *future* addresses to recognize it quickly, and an examiner can use those predicted MACs to tie scattered `Observations.db` rows back to one shared beacon even across rotations within the recorded range.

> 🔬 **Forensics note:** **`Observations.db` self-destructs fast.** Observation rows for beacons you don't own/aren't shared with are vacuumed within *hours*, and the live `-wal` routinely holds records absent from the main file — Hickman found "forty more records" in the WAL than the DB. So: **acquire the WAL, copy before you query, and treat this store as volatile** — it is closer to a rolling cache than a ledger. `OwnedBeacons`/`WildModeAssociationRecord` persist; `Observations.db` does not. Apple's **`Lost_Apples`** parser (Josh Hickman) and **iLEAPP** decode these once you supply the Keychain keys from a full-file-system or decrypted-backup acquisition.

> 🔬 **Forensics note — what each store *proves*:** `OwnedBeacons` = devices/AirTags the subject **owns** (with pairing timestamps — a tag added the day before a victim noticed it is a strong signal). `WildModeAssociationRecord` = the subject **was followed** by tracker X starting at place/time Y (or, on the stalker's phone, evidence of evasion testing). `Observations.db` (while it survives) = a high-resolution by-product location trail: every Find My beacon the phone *relayed* was, by definition, **near this phone at `scanDate`** — i.e. it corroborates the device's own movements even when [[07-location-history]]'s primary stores are sparse.

## Hands-on

There is no on-device shell. Everything below runs on your Mac — which, conveniently, is a first-class Find My participant, so its own `searchpartyd` and BLE radio are faithful substrates for most of this lesson (the device-only gaps are called out per lab).

### Look at the Mac's own Find My state

```bash
# The Mac runs the exact same daemon as iOS
ls -la ~/Library/com.apple.icloud.searchpartyd/
# OwnedBeacons/  SharedBeacons/  BeaconNamingRecords/  Observations.db  Observations.db-wal  ...

pgrep -lf searchpartyd          # the daemon
log show --last 1h --predicate 'process == "searchpartyd"' --style compact | head -40
# …searchparty… ‘BeaconManager’ rotated advertising key … submitted N reports …
```

> 🔬 **Forensics note:** The Unified Log itself is a corroborating Find My artifact. `searchpartyd`'s log lines record key rotations, report submissions, and beacon observations with timestamps — so even when `Observations.db` has already vacuumed, the **log archive** (a separate acquisition target on both macOS and iOS sysdiagnose; see [[12-unified-logs-sysdiagnose-crash-network]]) may still hold the fact that the device relayed *something* at a given minute. Collect `log collect`/sysdiagnose alongside the `searchpartyd` container.

### Inspect an owned-beacon record (encrypted bplist)

```bash
# The .record is an encrypted bplist — plutil shows the container, not the cleartext
cp ~/Library/com.apple.icloud.searchpartyd/OwnedBeacons/*.record /tmp/ob.record 2>/dev/null
plutil -p /tmp/ob.record
# {
#   "0" => <data 12 bytes>     # AES-GCM nonce
#   "1" => <data 16 bytes>     # GCM tag
#   "2" => <data N bytes>      # ciphertext (the real bplist)
# }
# Decryption needs the 32-byte key from the Keychain 'searchpartyd' access group.
```

### Confirm an Observations.db is SEE-encrypted, not plain SQLite

```bash
cp ~/Library/com.apple.icloud.searchpartyd/Observations.db /tmp/obs.db
sqlite3 /tmp/obs.db '.tables'
# Error: file is not a database     <-- expected: it's SEE/AES-256-OFB, not plaintext SQLite

xxd -l 32 /tmp/obs.db | head        # only bytes 16-23 of the header are recognizable
```

### Scan the air for live Find My beacons (your Mac's BLE radio)

```bash
python3 -m pip install bleak
python3 - <<'PY'
import asyncio
from bleak import BleakScanner
APPLE = 0x004C
def cb(dev, adv):
    md = adv.manufacturer_data.get(APPLE)
    if md and md[0] == 0x12:               # 0x12 = offline-finding (Find My) type
        status = md[1] if len(md) > 1 else None
        print(f"FindMy beacon {dev.address}  status=0x{status:02x}  rssi={adv.rssi}  keybytes={md[2:6].hex()}…")
asyncio.run(BleakScanner(cb).start()) and asyncio.get_event_loop().run_forever()
PY
# Find My beacon 7A:1C:…  status=0x10  rssi=-71  keybytes=a3f0…
# Each line is a *separated* nearby device/AirTag broadcasting a rotating p_i.
```

### Re-derive a tag's reports with FindMy.py / macless-haystack (read-only walkthrough)

```bash
# Researcher / examiner-with-keys path — needs the master key (your own tag, or seized SK_0/d_0)
pip install findmy
# Provide the .keys/.plist (private key d_0 or full master) exported from OpenHaystack/searchpartyd,
# authenticate with an Apple ID + Anisette, then:
#   FindMyAccount.fetch_last_reports(keypair)  -> [LocationReport(lat, lon, ts, accuracy)…]
# This recomputes p_i over the window, hashes to indices, pulls + GCM-decrypts the reports.
```

The fetch endpoint is the one piece that needs Apple-side authentication: a valid Apple ID session plus an **Anisette** data blob (Apple's anti-abuse device-fingerprint/one-time-token, the thing OpenHaystack originally stole from the Mail plugin and macless-haystack now generates via a small `anisette-server`). Without it, Apple returns 401 and you can derive keys all day but fetch nothing — a useful reminder that the *crypto* is open but the *report store* is access-controlled.

### Find the searchpartyd Keychain access group

```bash
# The 32-byte AES/SEE keys that unlock everything above live in the searchpartyd access group.
security dump-keychain 2>/dev/null | grep -iA2 searchparty | head
# "agrp"<blob>="com.apple.icloud.searchpartyd"   ... (32-byte key material, login-pw protected)
# On iOS these are Data-Protection-class keys, so BFU/AFU lock state decides if they're even derivable.
```

### Parse a sample image with iLEAPP / Lost_Apples (offline)

```bash
# Against an extracted FFS tree or a decrypted backup mount — never the live device store:
python3 ileapp.py -t fs -i /path/to/extraction -o /tmp/ileapp_out
#   → modules emit "Find My" / "Search Party" reports: owned beacons, observations, wild-mode hits
git clone https://github.com/joshuahickman1/Lost_Apples && cd Lost_Apples
python3 Lost_Apples.py    # walks com.apple.icloud.searchpartyd + com.apple.findmy.findmylocated
```

## 🧪 Labs

> Substrate note: Labs 1–3 use **your own Mac** — a genuine Find My participant, so its `searchpartyd` stores and BLE radio are *high-fidelity* analogues of the iOS daemon (same code lineage, same record formats). The fidelity gap: on iOS the records are protected by **Data Protection class keys tied to the SEP/passcode**, and the device-only anti-stalking scanner runs continuously; on macOS there's **no SEP-bound Data Protection at rest** and the Mac is less often a *separated* beacon. Lab 4 uses a **public sample image** for the iOS-specific `WildModeAssociationRecord` anti-stalking artifact, which a Mac won't populate. Lab 5 is a **read-only walkthrough** of an on-device-bound step.

### Lab 1 — Map your own Mac's Find My footprint (Mac, live, read-only)

1. `ls -R ~/Library/com.apple.icloud.searchpartyd/` and enumerate `OwnedBeacons/`, `SharedBeacons/`, `BeaconNamingRecords/`.
2. For each `OwnedBeacons/*.record`, `plutil -p` it and confirm the 3-element `{nonce, tag, ciphertext}` container shape. Note you **cannot** read the cleartext without the Keychain key — write down *why* (the AES-GCM key lives in the `searchpartyd` Keychain access group).
3. Count how many beacons this account owns vs. has shared. Correlate the count to what the Find My app shows under *Items*. Fidelity caveat: this is the Mac's view of an iCloud-account-wide set, so it reflects the *account*, not just this machine.

### Lab 2 — Catch the rotation in the air (Mac, live BLE)

1. Run the `bleak` scanner from Hands-on for ~20–30 minutes, logging `(timestamp, MAC, status, full manufacturer payload)` for every `0x12` beacon.
2. Pick one strong, persistent beacon (stable RSSI) and watch what changes. **Expect a surprise:** for a *separated AirTag* the MAC and public key will likely **stay fixed** across your whole capture — only the trailing **counter byte** ticks (≈ every 15 min), because a separated AirTag re-keys just once a day (04:00 local). The clean 15-minute *full-key* rotation is what a lost *iPhone/iPad/Mac* in offline-finding mode does; you may or may not catch one in range. Record which behavior you actually observed.
3. Confirm you **cannot** link a tag *across* its daily full-key rotation from the air alone (the next day's key bytes are unrelated to today's). Write one sentence on why fast rotation would defeat a passive stalker but *also* blind a victim's "moving with you" detector — the deliberate tension this lesson's anti-stalking section resolves. Fidelity caveat: you're seeing other people's separated devices; you can't prove which physical object any beacon maps to without the owner's key, and AirTag daily re-keying means a 20-minute window rarely shows a *full* rotation.

### Lab 3 — Prove `Observations.db` is volatile and SEE-encrypted (Mac)

1. `cp` the `Observations.db` **and** its `-wal` to `/tmp`. Run `sqlite3 /tmp/obs.db '.tables'` and capture the "not a database" error — this is the SEE-vs-plaintext lesson.
2. Wait an hour, re-copy, and compare file sizes / `stat -f %Sm`. Observe how aggressively it churns (the vacuum behavior). Write down the chain-of-custody implication: **the WAL must be acquired with the DB, and a delayed acquisition loses observation rows permanently.**

### Lab 4 — Parse iOS anti-stalking + owned-beacon artifacts (public sample image)

Substrate: a public iOS reference image (Josh Hickman / thebinaryhick.blog or the `Lost_Apples` test data) — needed because a Mac won't generate `WildModeAssociationRecord` and stores iOS records under different protection.

1. Run **iLEAPP** (or `Lost_Apples`) against the image; locate its Find My / Search Party output module.
2. In `OwnedBeacons`, find a tag's **pairing timestamp**; note the epoch (Apple/Mac Absolute Time, 2001-01-01 — see [[00-the-ios-timestamp-zoo]]).
3. In any `WildModeAssociationRecord`, read the `status` field — find a record in **"staged"** (alert pending) and note the **first-seen location**. Articulate, in one line, how this row alone could corroborate a stalking complaint and identify the offending tag.

### Lab 5 — Deploy-your-own-beacon, conceptually (read-only walkthrough)

> ⚠️ **ADVANCED:** Beaconing a fixed `p_0` makes a *trackable* device — only run real hardware against keys you own, and never plant a beacon on a person or vehicle.

1. Read the **OpenHaystack** README and the **macless-haystack** fork notes. Diagram the data flow: firmware broadcasts fixed `p_0` → mesh finders upload reports under `SHA-256(p_i)` → your host computes the `p_i` series, hashes, fetches, GCM-decrypts with `d_i`.
2. Identify the one step that *cannot* be done without an Apple ID + Anisette token (the authenticated report fetch) and explain why the original OpenHaystack abused the Mail plugin for it while macless-haystack does it directly.
3. Map each OpenHaystack stage onto the matching `searchpartyd` artifact from Lab 1 — i.e. the keys you'd hand `FindMy.py` are exactly what `OwnedBeacons` stores encrypted.

### Lab 6 — Decode a Find My advertisement by hand (Mac, paper exercise)

Take one full manufacturer-data payload from your Lab 2 capture (extend the scanner to print `md.hex()`), and reconstruct the public key:

1. Confirm the leading bytes: type `12`, length `19` (decimal 25), then the status byte. Decode the status byte's high bits as battery level and the maintained/separated flag.
2. Reassemble `p_i`: the BLE advertising address supplies `p_i[0..5]` (remember byte 0 had its top two bits forced to `0b11` for "static random" — the *real* top two bits are carried in the dedicated bits-byte near the end of the payload), and the payload carries `p_i[6..27]`.
3. Hash the reconstructed 28-byte key with SHA-256. That value is *exactly* the index Apple's server files this beacon's reports under. You've now derived, by hand, the link between an over-the-air beacon and its server-side report bucket — without any private key, demonstrating why the fetch side must be access-controlled (Anisette) and not merely "know the hash."
   Fidelity caveat: you can compute the index, but you can't fetch a stranger's reports — the endpoint authenticates you and only returns buckets you query for; you'd see nothing meaningful without that owner's key set.

## Pitfalls & gotchas

- **`Observations.db` is not a SQLite file you can open.** It's SEE/AES-256-OFB; `sqlite3` returns "file is not a database." You need the Keychain SEE key *and* the right cipher params, or a parser (`Lost_Apples`, iLEAPP) that knows them. Don't conclude "no data" from a failed `.tables`.
- **The `.record` files are encrypted bplists, not plists.** `plutil -p` shows a `{nonce, tag, ciphertext}` wrapper, not the label/keys. The 32-byte AES-GCM key is in the **Keychain `searchpartyd` access group** — which means **BFU/AFU lock state and Data Protection class gate whether you can decrypt at all** on a real device (vs. the always-open Mac).
- **Acquire the WAL, and acquire *fast*.** Observation rows vacuum within hours and the `-wal` frequently holds records missing from the main DB. A logical backup taken a day late silently loses the relay trail.
- **"Live" Find My location is stale by design.** Finders batch uploads (~26 min median sighting→upload, per SEEMOO), so a fetched fix can be tens of minutes old. Don't treat a Find My timestamp as the moment the device was *there* — treat it as "no later than."
- **Rotating MAC ≠ trackable (mostly).** A reflex from classic BLE forensics is to pivot on a device's MAC. Find My MACs are random static addresses that roll in lockstep with the key (every ~15 min for a lost iOS device; only ~daily for a separated AirTag) — there is **no stable hardware identifier** in the air. The owner's key, recovered from `searchpartyd`, is the durable handle, not the MAC. (The wrinkle the anti-stalking layer exploits: a separated AirTag's daily-stable key *is* trackable-for-a-day — that's the privacy cost of being detectable.)
- **Owned vs. observed vs. stalking are three different stores — don't merge them.** `OwnedBeacons`/`SharedBeacons` = the subject's tags; `Observations.db` = beacons the phone relayed (mostly strangers'); `WildModeAssociationRecord` = trackers that followed the subject. Mislabeling an *observed* stranger's tag as *owned* is a serious analytic error.
- **ADP and account state can move the goalposts.** With Advanced Data Protection the key material is even more tightly held; and item sharing means a tag a subject can locate may live in `SharedBeacons`, owned by someone else — chain-of-custody for "whose tag" runs through the iCloud account, not just the device.
- **"AirTag" may not be an AirTag.** Certified third-party accessories advertise the same offline-finding payload. Don't write "AirTag" in a report off the bare presence of a Find My beacon — read the model/category/role fields from the decoded record before naming hardware.
- **Activation Lock is not encryption.** A wiped, Activation-Locked device that won't progress past setup is blocked by a *server-side policy* tied to the Apple Account, not by at-rest encryption. Conflating the two in a report ("the data is encrypted") is wrong and may mislead on what legal process (Apple account records vs. on-device key recovery) would actually help.
- **The crypto is open; the report store is not.** You can derive every `p_i` and `SHA-256(p_i)` index for *any* public key — that's public math. But fetching reports requires a live Apple ID session + **Anisette** token; without it you get 401s. "I can compute the index" ≠ "I can pull the location." Plan acquisitions around having the master keys *and* a working fetch path.
- **Epoch trap.** `searchpartyd` timestamps are largely **Apple/Mac Absolute Time (2001-01-01)**; mixing them with Unix epoch throws everything off by 31 years. See [[00-the-ios-timestamp-zoo]].
- **A fix is a *relay event*, not a *presence* of the owner.** A decrypted report proves only that *some finder* and the *beacon* were co-located; it says nothing about where the owner was. Don't infer the owner's location from their lost tag's track.
- **`Observations.db` rows are mostly strangers.** The vast majority of observed beacons are other people's devices the phone relayed for. Treat an observation as evidence of *the phone's* location at `scanDate`, not of any relationship to the observed beacon's owner — unless its key resolves to an owned/shared beacon.

## Key takeaways

- Find My is an anonymous, end-to-end-encrypted **crowd-sourced location mesh**: a beacon broadcasts a rotating public key, any nearby Apple device encrypts its GPS fix to that key and uploads it, and only the owner (holding the private key) can fetch and decrypt — Apple stores blind ciphertext keyed by an opaque hash.
- The cryptography is a **P-224 master key `(d_0,p_0)` + symmetric seed `SK_0`** that derive an endless series of **rolling advertisement keys `p_i`** via an ANSI X9.63 KDF (one per ~15-min period — but a *separated AirTag* advertises each key for a full day, a deliberate anti-stalking concession); `p_i = u_i·p_0 + v_i·G` is computable from the public master alone, so finders/researchers can encrypt and fetch without ever decrypting.
- **Unlinkability is structural:** rotating random-static MACs + ephemeral public keys mean a passive sniffer, a finder, and Apple all fail to identify the device or read the location. Only the owner can.
- **AirTags borrow 100% of their location ability from the mesh** (no GPS/cell) — coverage scales with Apple-device density (rich in cities, blank where no finder walks by), which is why Apple/Google layered on anti-stalking: separated-mode alarms, "moving with you" alerts, UWB precision finding, the **IETF DULT** cross-platform spec (iOS 17.5 / Android, May 2024), and SEEMOO's **AirGuard**.
- The protocol was reverse-engineered by **SEEMOO/OWL** ("Who Can Find My Devices?", PoPETs 2021) and productized as **OpenHaystack** / **macless-haystack** / **FindMy.py** — the same toolchain a researcher (or examiner with the master key) uses to reconstruct a tag's history.
- Forensically, **`com.apple.icloud.searchpartyd`** is the gold: `OwnedBeacons`/`SharedBeacons` (tags owned/shared, with pairing timestamps), `WildModeAssociationRecord` (anti-stalking — who was followed by whose tag), and the **volatile, SEE-encrypted `Observations.db`** (a relay-derived location trail that vacuums within hours — grab the WAL, copy before query).
- Mind the walls and the attribution traps: the Find My toggle arms **Activation Lock** (a *policy* re-provisioning block, distinct from encryption); **item sharing** means "could locate" ≠ "owns"; **certified third-party accessories** advertise as AirTags-by-another-name; and the **crypto is open but the report store is Anisette-gated** — computing an index isn't fetching a location.
- macOS is a faithful lab substrate (same daemon, same record formats) for everything except the **SEP-bound Data Protection** on the keys and the iOS-only continuous anti-stalking scanner.

## Terms introduced

| Term | Definition |
|---|---|
| Find My network (Search Party) | Apple's crowd-sourced offline-finding mesh; on-disk container/daemon name is `searchpartyd` / `com.apple.icloud.searchpartyd` |
| Master beacon key | The per-tag secret `(d_0, p_0)` on NIST P-224 plus a 32-byte symmetric seed `SK_0`, synced via E2E iCloud Keychain |
| Rolling advertisement key (`p_i`) | The ephemeral P-224 public key broadcast each period (~15 min for a lost iOS device; a separated AirTag holds each key ~24 h), derived from the master via an ANSI X9.63 KDF ratchet |
| Offline finding | Apple's term for locating a device that has no internet of its own, via finder devices in the mesh |
| Finder device | Any nearby Apple device that overhears a beacon, encrypts its own location to `p_i`, and anonymously uploads the report |
| ECIES (CryptoKit) | Elliptic-Curve Integrated Encryption Scheme: ephemeral ECDH → ANSI X9.63 KDF(SHA-256) → AES-128-GCM; how finders encrypt reports |
| Unlinkability | Property that rotating MAC + ephemeral keys prevent a third party from linking beacons to each other or to an owner |
| Separated mode | An AirTag's state when away from its owner; switches it to `0x12` offline-finding advertising with slow (~daily) key rotation, and triggers audible alerts + unwanted-tracking detection |
| DULT | "Detecting Unwanted Location Trackers" — the Apple/Google cross-platform anti-stalking spec at the IETF (iOS 17.5 / Android, May 2024) |
| AirGuard | SEEMOO/TU Darmstadt open-source unwanted-tracker detector (iOS + Android) |
| OpenHaystack / macless-haystack | SEEMOO framework (and Apple-hardware-free fork) to deploy custom Find My beacons and fetch/decrypt their reports |
| OWL (Open Wireless Link) | TU Darmstadt project that reverse-engineered AWDL and Find My offline finding |
| `OwnedBeacons` / `SharedBeacons` | `searchpartyd` directories of `.record` (encrypted bplist) files for tags the account owns / has shared |
| `Observations.db` | SEE-encrypted (AES-256-OFB) SQLite of Find My beacons this device observed; vacuums within hours |
| `WildModeAssociationRecord` | `searchpartyd` records of separated trackers detected following the device — the anti-stalking artifact |
| SEE | SQLite Encryption Extension — page-level AES encryption used by `Observations.db`/`ItemSharingKeys.db`, not openable by plain `sqlite3` |
| Send My | Covert-channel technique abusing Find My report indices to exfiltrate arbitrary data over the BLE mesh |
| Activation Lock | Secure-Enclave-enforced binding of a device to its owner's Apple Account, armed by enabling Find My; blocks re-provisioning after erase |
| Anisette | Apple's anti-abuse device-fingerprint/one-time-token data required to authenticate report-fetch requests to Apple's Find My servers |
| Find My Network Accessory Program | The MFi program letting certified third-party trackers/accessories advertise into Apple's mesh using the offline-finding payload |
| `NearOwnerKeys` | Table in `ItemSharingKeys.db` storing predicted upcoming rotated MACs for shared beacons |

## Further reading

- Apple Platform Security — "Find My security" / "Locating missing devices" (support.apple.com/guide/security) — Apple's own (sparse) description of the offline-finding key hierarchy and Activation Lock
- Heinrich, Stute, Kornhuber, Hollick, **"Who Can Find My Devices? Security and Privacy of Apple's Crowd-Sourced Bluetooth Location Tracking System,"** PoPETs 2021 (arXiv:2103.02282) — the canonical protocol reverse-engineering
- **owlink.org** (SEEMOO / TU Darmstadt) — OWL, the Find My papers, and the AWDL lineage; `github.com/seemoo-lab/openhaystack`
- **macless-haystack** and **FindMy.py** (`malmeloo/FindMy`) — headless fetch/decrypt without Apple hardware
- AirGuard — `github.com/seemoo-lab/AirGuard` and F-Droid (`de.seemoo.at_tracking_detection`)
- Positive Security, **"Send My: Arbitrary data transmission via Apple's Find My network"** (positive.security/blog/send-my)
- Positive Security (Fabian Bräunlein), **"Find You: Building a stealth AirTag clone"** (positive.security/blog/find-you) — the fast-re-keying clone that evades unwanted-tracking detection; the canonical demo of the separated-mode rotation trade-off
- Adam Catley, **"Apple AirTag Reverse Engineering"** (adamcatley.com/AirTag.html) — hardware + BLE payload teardown
- Josh Hickman, thebinaryhick.blog — "More on iOS Search Party" / "Where The Wild Tags Are" + the **`Lost_Apples`** parser (`github.com/joshuahickman1/Lost_Apples`)
- iLEAPP (Alexis Brignoni) Find My / Search Party modules; the IETF **DULT** working-group drafts (datatracker.ietf.org)
- Apple & Google, "Detecting Unwanted Location Trackers" — joint spec announcement and the May-2024 iOS 17.5 / Android rollout newsroom posts (apple.com/newsroom)
- D204n6 (Ian Whiffin), "AirTag, You're It!" (blog.d204n6.com) — early `searchpartyd`/AirTag artifact teardown
- `man bleak` / the `bleak` docs; furiousMAC `continuity` BLE message catalog (`github.com/furiousMAC/continuity`)

---
*Related lessons: [[04-wifi-bluetooth-and-proximity]] | [[05-radios-wifi-bt-nfc-uwb]] | [[08-keychain-on-ios]] | [[07-apple-account-icloud-and-apns]] | [[07-location-history]] | [[00-the-ios-timestamp-zoo]]*
