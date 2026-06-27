---
title: "The Keychain on iOS"
part: "03 — Security Architecture"
lesson: 08
est_time: "50 min read + 20 min labs"
prerequisites: [data-protection-and-keybags]
tags: [ios, keychain, secrets, ksecattraccessible, forensics]
last_reviewed: 2026-06-26
---

# The Keychain on iOS

> **In one sentence:** The iOS Keychain is a single SQLite file — `/private/var/Keychains/keychain-2.db` — where every password, token, certificate, private key, and Wi-Fi/VPN credential on the device lives, and whether you can ever read a given secret is the product of three independent variables: the item's Data Protection class (its `pdmn` value), the acquisition method, and whether the device is BFU/AFU/unlocked at the moment of extraction.

## Why this matters

The Keychain is the highest-value target on the whole device and the one most resistant to acquisition. It is not "where settings are saved" — it is where authentication material is saved: the OAuth bearer token that re-logs an app into a cloud account without a password prompt, the saved website logins and passkeys, the Wi-Fi PSKs and 802.1X certificates, the VPN shared secrets, the app-specific encryption keys. Get the Keychain and you frequently get *lateral* access to accounts and services the device itself never stored. That is exactly why Apple wraps each item to the Secure Enclave through the Data Protection keybag, and why the same full-file-system extraction that hands you `chat.db` in the clear may hand you a Keychain blob you cannot decrypt. This lesson is the bridge between the [[02-data-protection-and-keybags]] theory you already have and the concrete on-disk reality: the table, the columns, the class codes, and the precise recoverability matrix that tells you, for any item, whether your acquisition will ever yield its plaintext.

For the builder, the same facts are the API contract: choosing `kSecAttrAccessible` is choosing your data's blast radius — `AfterFirstUnlock` keeps a background sync token working but makes it AFU-recoverable; `WhenPasscodeSetThisDeviceOnly` plus a `biometryCurrentSet` ACL plus a Secure-Enclave key is the strongest posture you can request, at the cost of no backup, no sync, and a live-auth prompt on every read. The forensic recoverability matrix and the developer's threat-model decision are *the same table read from opposite ends*, which is why this one lesson serves both halves of the curriculum.

## Concepts

### One file, one daemon, one broker

Every Keychain item on an iPhone or iPad lives in a single system-wide SQLite 3 database:

```
/private/var/Keychains/keychain-2.db          ← the Keychain (genp/inet/cert/keys/...)
/private/var/Keychains/keychain-2.db-wal      ← WAL sidecar (present when open)
/private/var/Keychains/keychain-2.db-shm      ← shared-memory index
/private/var/Keychains/caissuercache.sqlite3  ← CA issuer cache (cert chain building)
/private/var/Keychains/ocspcache.sqlite3      ← OCSP revocation cache
/private/var/Keychains/TrustStore.sqlite3     ← user/admin-installed trusted anchors
```

Unlike macOS, there is **no per-user `login.keychain-db`** and no folder of named keychain files — iOS is single-user (the multi-user exception is Shared iPad, addressed below), so there is one Keychain for the whole system. No process opens this file directly. The `securityd` daemon is the sole broker: an app calls `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` (the `SecItem` API in the Security framework), the call is marshalled over XPC to `securityd`, and `securityd` decides — from the caller's **entitlements** (`keychain-access-groups`, `application-identifier`, `application-group`) — which rows the caller may see, then performs the SQL and the crypto on the caller's behalf. Items are siloed by **access group** (`agrp`); an app can only touch rows whose `agrp` it is entitled to.

```
   app process                       securityd (sole broker)
  ┌─────────────┐   XPC   ┌────────────────────────────────────────┐
  │ SecItemAdd  │ ──────► │ 1. check caller entitlements (agrp)     │
  │ SecItemCopy │         │ 2. SQL on  keychain-2.db  (genp/inet/…) │──► /private/var/Keychains/
  │ Matching    │ ◄────── │ 3. wrap/unwrap secret via AppleKeyStore │──► AppleKeyStore (kernel)
  └─────────────┘  result │    using the class key named by pdmn    │       │  0xA wrap / 0xB unwrap
                          └────────────────────────────────────────┘       ▼
                                                                     Data Protection keybag (SEP-entangled)
```

The app never sees the file, the SQL, or the keys; it sees only the rows `securityd` is willing to return after the entitlement check and a successful keybag unwrap.

> 🖥️ **macOS contrast:** You studied two macOS keychains. The legacy, file-based **`login.keychain-db`** (`~/Library/Keychains/`) — its records encrypted with **3DES-CBC** under a master key derived from the login password by PBKDF2, browsable with `security dump-keychain` — has **no iOS counterpart**. What iOS uses is the second one: the **Data Protection keychain**, which on macOS also materializes as `keychain-2.db` inside a UUID-named folder under `~/Library/Keychains/`. Same `keychain-2.db` lineage, same `genp`/`inet`/`cert`/`keys` tables, same `kSecAttrAccessible` vocabulary — but on iOS the wrapping keys are bound to the SEP and the Data Protection keybag (see [[01-sep-sepos-deep-dive]]), so the macOS trick of decrypting with the login password does not exist here.

### Five item classes → four (really five) tables

The `SecItem` API exposes five item classes; the database stores them in correspondingly named tables:

| `kSecClass` constant | Table | Holds |
|---|---|---|
| `kSecClassGenericPassword` | `genp` | App secrets: tokens, app passwords, app-derived keys, "secure notes"; **saved Wi-Fi PSKs** (`svce` = `AirPort`) |
| `kSecClassInternetPassword` | `inet` | Credentials scoped to a server/protocol/port: website logins, mail (IMAP/SMTP), VPN |
| `kSecClassCertificate` | `cert` | X.509 certificates (DER) |
| `kSecClassKey` | `keys` | Cryptographic keys — RSA/EC private & public, symmetric, **SEP-bound key references** |
| `kSecClassIdentity` | (synthesized) | An identity = a `cert` row + its matching `keys` row, joined at query time (sometimes surfaced as an `idnt` view) |

The two password tables carry the bulk of forensic value. `genp` is keyed for search on **service** (`svce`) + **account** (`acct`); `inet` adds the network-scoping columns **server** (`srvr`), **protocol** (`ptcl`), **authentication type** (`atyp`), **security domain** (`sdmn`), **port**, and **path**. That is why a **website login** is an `inet` row (`srvr` = the host, `ptcl`/`port` = the scheme + port), while an app's API token — and, on iOS, a **saved Wi-Fi password** (a `genp` item, `svce` = `AirPort`, `acct` = the SSID, retrievable on macOS with `security find-generic-password -ga "<SSID>"`) — is a `genp` row.

### The schema you actually query

`PRAGMA table_info(genp)` on a real device dumps a wide row. The columns that matter forensically:

| Column | Meaning | Notes |
|---|---|---|
| `rowid` | SQLite primary key | per-row identity (the metadata-wrapping key is joined by protection **class**, not by `rowid` — see `metadatakeys`) |
| `cdat` | Creation date | `REAL`, **CFAbsoluteTime** (seconds since 2001-01-01 UTC) |
| `mdat` | Modification date | same epoch; `+978307200` → Unix |
| `labl` | User-visible label (`kSecAttrLabel`) | |
| `acct` | Account (`kSecAttrAccount`) | username / key handle |
| `svce` | Service (`kSecAttrService`) | `genp` only; app's namespace string |
| `srvr` | Server host (`kSecAttrServer`) | `inet` only |
| `ptcl` / `atyp` / `port` / `path` / `sdmn` | Protocol / auth type / port / path / security domain | `inet` only |
| `agrp` | Access group (`kSecAttrAccessGroup`) | the entitlement silo — e.g. `apple`, `com.apple.token`, a team-prefixed group |
| `pdmn` | **Protection domain** | the Data Protection class code — `ak`/`ck`/`dk`/`aku`/`cku`/`dku`/`akpu` |
| `accc` | Access control (`kSecAccessControl`) | the SAC/ACL blob — biometric & passcode gates live here |
| `tkid` | Token ID (`kSecAttrTokenID`) | `com.apple.setoken` marks a **Secure Enclave-bound** key |
| `sync` | Synchronizable flag | `1` ⇒ syncs via iCloud Keychain; `0` ⇒ local-only |
| `tomb` | Tombstone | `1` ⇒ a deleted-but-still-synced placeholder (a *sync* delete leaves a tombstone) |
| `vwht` | View hint | the CKKS sync "view" the item belongs to |
| `musr` | Multi-user / persona UUID | non-empty only on **Shared iPad** managed-user contexts |
| `data` | **The encrypted item** | version prefix + AES-GCM-wrapped metadata + secret (below) |
| `UUID` / `sha1` / `pcss`/`pcsk`/`pcsi` | Item UUID / SHA-1 of the cert/key / persistent-ref & PCS sync fields | |

> 🔬 **Forensics note:** `cdat`/`mdat` are **CFAbsoluteTime** (the Cocoa/Mac-Absolute 2001 epoch), not the nanosecond variant some newer Apple stores use — convert with `datetime(cdat + 978307200, 'unixepoch', 'localtime')`. The creation date of a credential is evidence in its own right: a saved-password row whose `cdat` predates the account's claimed creation, or a token row created at 03:00 when the subject claims the phone was off, both impeach a timeline. See [[00-the-ios-timestamp-zoo]] for the full epoch catalogue.

The database also carries a **`tversion`** table holding the Keychain's *schema* version, which `securityd` bumps and migrates across OS releases. It is a small but useful provenance signal: a `tversion` higher than the OS you believe produced the image is a contradiction worth chasing, and the schema version gates which columns and which encryption layout (e.g. how much metadata is cleartext) you should expect. Treat the exact version→OS mapping as something to look up for your target build rather than memorize.

### The `pdmn` column is the whole ballgame

Every row carries a `pdmn` (protection domain) — a short string that names the **Data Protection class** whose key wraps that item's secret. It is the single most important column in the database, because it determines *when* the wrapping key is available and therefore *whether* the secret can ever be decrypted. The codes decompose cleanly:

```
   a k  p  u
   │ │  │  └─ "u" = ThisDeviceOnly: wrapped to the device UID, never backed up, never synced
   │ │  └──── "p" = passcode REQUIRED (item ceases to exist if the passcode is removed)
   │ └─────── "k" = key (literal)
   └───────── availability tier:  a = When-unlocked   c = After-first-unlock   d = Always (deprecated)
```

| `pdmn` | `kSecAttrAccessible` constant | DP class | Secret available… |
|---|---|---|---|
| `ak` | `kSecAttrAccessibleWhenUnlocked` | A | only while the device is **unlocked** |
| `ck` | `kSecAttrAccessibleAfterFirstUnlock` | C | after the **first** unlock since boot, until shutdown |
| `dk` | `kSecAttrAccessibleAlways` *(deprecated)* | D | always, even BFU (no passcode dependency) |
| `aku` | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | A + UID | unlocked **and** never leaves this device |
| `cku` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | C + UID | after first unlock, never leaves this device |
| `dku` | `kSecAttrAccessibleAlwaysThisDeviceOnly` *(deprecated)* | D + UID | always, never leaves this device |
| `akpu` | `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | A + passcode + UID | unlocked, only if a passcode is set, never leaves device, **purged if passcode removed** |

The letter (A/C/D) ties each class to the matching keybag class key you met in [[02-data-protection-and-keybags]]: the class-A key is evicted from memory on lock; the class-C key is derived at first unlock and survives until shutdown; the legacy class-D key has no passcode dependency at all. The `u` suffix swaps in a UID-entangled variant of that class key (so the wrapped blob is meaningless on any other device), and `akpu` adds the rule that the item is *destroyed* the instant the user turns off their passcode.

> 🔬 **Forensics note:** **`kSecAttrAccessibleAfterFirstUnlock` (`ck`/`cku`) is the de-facto default for any credential an app needs in the background.** Push-notification apps, mail clients, anything that refreshes a token while the screen is off — all default to `ck` so they keep working after the user's first morning unlock. This is why an **AFU** acquisition (device seized powered-on and already unlocked once, kept alive) is worth so much more than a **BFU** one: at AFU the class-C key is resident in the SEP/kernel, so every `ck`/`cku` item is decryptable. At BFU only the deprecated `dk`/`dku` items are. The BFU→AFU→unlocked ladder *is* the Keychain recoverability ladder. See [[03-passcode-bfu-afu-and-inactivity]].

### `ThisDeviceOnly` vs syncable — the `sync` bit and iCloud Keychain

Orthogonal to the availability tier is **portability**, expressed by the `u` suffix on `pdmn` *and* the `sync` column:

- **`ThisDeviceOnly` items** (`aku`/`cku`/`dku`/`akpu`, with `sync = 0`) are wrapped to the device's hardware **UID**. The wrapped blob is cryptographically useless off the originating device. These items **never enter a backup and never sync to iCloud.** Apps choose this for keys that must not be portable: the device-binding key, biometric-gated app secrets.
- **Syncable items** (`sync = 1`, never a `…ThisDeviceOnly` class) participate in **iCloud Keychain**. `securityd` hands them to the sync stack: historically **SOS** (Secure Object Sharing — end-to-end-encrypted item exchange over IDS push, via `KeychainSyncingOverIDSProxy`), and on modern iOS **CKKS** (CloudKit Keychain Syncing) under the **Octagon** trust system (`TrustedPeersHelper` / "Cuttlefish"). The `vwht` (view hint) names which CKKS *view* the item rides in; a `sync`-delete leaves a `tomb = 1` tombstone so the deletion itself propagates.

The crucial property for forensics: **iCloud Keychain is end-to-end encrypted by design.** The sync payload is wrapped to the user's trusted device circle; Apple's servers hold ciphertext only and Apple cannot produce the plaintext under legal process. This is true *independently of Advanced Data Protection* — unlike iCloud Backup or iCloud Photos (which ADP flips from Apple-recoverable to E2E), the Keychain (and Health, and a few others) were **already E2E** before ADP existed.

> ⚖️ **Authorization:** Practically, this means a cloud-side legal request to Apple for "the iCloud Keychain" returns nothing usable — there is no Apple-held key. Recovering syncable Keychain items requires either an authenticated client-side join to the user's device circle (you need a trusted device + that device's passcode, or the iCloud Security Code / a recovery contact) or on-device acquisition. Don't promise an investigator that a subpoena to Apple will yield saved passwords; it will not. See [[06-icloud-acquisition-and-advanced-data-protection]] and [[07-apple-account-icloud-and-apns]].

### iCloud Keychain escrow — the one cloud-side path, and why it's gated

There *is* a single cloud-side recovery mechanism, and it exists so a user who loses every device can still get their passwords back: **iCloud Keychain escrow.** A copy of the syncable Keychain is escrowed with Apple, but it is wrapped to a key that Apple's servers cannot use on their own — the escrow record is sealed to Apple's **HSM (hardware security module) cluster**, and unwrapping it requires the user to prove knowledge of a secret (in the modern Octagon flow, the **device passcode/PIN**; in the legacy flow, the **iCloud Security Code**) plus a second-factor SMS to a trusted number. The HSMs enforce a strict **attempt limit** (historically ~10 tries) and then **destroy the escrow record** — the same anti-brute-force posture as the SEP, but in Apple's datacenter.

> 🔬 **Forensics note:** Escrow is the *only* avenue by which iCloud Keychain plaintext is ever reconstructable cloud-side, and it is **not** an Apple-can-just-hand-it-over path: it consumes the HSM attempt budget and needs the passcode + SMS factor, so it behaves like an online passcode-guess against a fast-locking oracle. Commercial "iCloud Keychain" extraction (Elcomsoft and peers) drives exactly this escrow flow with valid credentials + the second factor — it is account-takeover-shaped, not a silent server dump. **Verify the current attempt count and whether the device passcode or the iCloud Security Code is required against the live Apple Platform Security guide** — Apple has revised the escrow mechanism across the SOS→Octagon transition.

### How a secret is actually encrypted (the `data` blob)

Reading `keychain-2.db` with raw `sqlite3` gets you the schema and the metadata columns, but the `data` column is opaque. Its structure, as reverse-engineered from `securityd` (and re-confirmed publicly during the 2023 *Operation Triangulation* analysis):

```
┌────────────┬───────────────────────────────────────────────────────────┐
│  uint32    │  encrypted blob (NSKeyedArchiver-serialized)               │
│  version   │  ┌─────────────────────────┬──────────────────────────┐   │
│  prefix    │  │ AES-256-GCM(metadata)   │ AES-256-GCM(secret value)│   │
│  (4 bytes) │  │  key wrapped via the    │  key wrapped per-item via │  │
│            │  │  per-class "metadata    │  the AppleKeyStore kernel │  │
│            │  │  wrapping key" (cached;  │  module (the keybag class │  │
│            │  │  see `metadatakeys`)    │  key) — no cached wrapper  │  │
│            │  └─────────────────────────┴──────────────────────────┘   │
└────────────┴───────────────────────────────────────────────────────────┘
```

Two **independent AES-256-GCM keys** per item: one over the *metadata* (the `kSecAttr*` attributes), one over the *secret* (`kSecValueData`). The metadata key is wrapped by a cached per-class **metadata wrapping key** and stored in the `metadatakeys` table; the secret key is wrapped **per item** by handing it to the **`AppleKeyStore`** kernel extension, which performs the wrap/unwrap against the active **Data Protection keybag** using the class key named by `pdmn`. The kernel selectors are the same ones the whole Data Protection stack uses (`AppleKeyStore` external method `0xA` = wrap, `0xB` = unwrap).

The consequence is blunt: **possession of `keychain-2.db` alone yields nothing.** To decrypt you need the device's keybag *and* a live `AppleKeyStore` willing to unwrap — i.e. code execution on the device with the relevant class key currently available. A dead-disk copy of the file is, by itself, inert.

> 🔬 **Forensics note:** On **older** iOS the attribute columns (`acct`, `svce`, `srvr`, `labl`) were stored largely **in cleartext** in the table for indexed search, so even an un-decryptable Keychain leaked *what accounts and services existed*. Modern iOS encrypts the metadata too (that's the second key), so on a recent image those columns may be empty/opaque and only `cdat`/`mdat`/`pdmn`/`sync`/`agrp`/`rowid` remain as plaintext index fields. **Verify on your specific image** which attributes are cleartext — the cutover is version-dependent — because "the Keychain leaks service names even when locked" is a claim that was true for years and is now only partly true.

### The `cert` and `keys` tables

The two password tables get the attention, but `cert` and `keys` carry the cryptographic-identity material — 802.1X enterprise Wi-Fi certs, S/MIME and VPN identities, MDM identity certs, and app-generated key pairs — and they have their own column shapes:

| Table | Class | Representative columns | Holds |
|---|---|---|---|
| `cert` | `kSecClassCertificate` | `ctyp` (cert type), `cenc` (encoding), `labl`, `subj` (subject), `issr` (issuer), `slnr` (serial number), `skid` (subject key id), `pkhh` (public-key hash), `data`, `agrp`, `pdmn` | DER X.509 certificates |
| `keys` | `kSecClassKey` | `kcls` (key class: public/private/symmetric), `klbl` (application label, usually the public-key hash), `type` (`kty`: RSA/EC/AES), `perm` (permanent), `priv`/`sign`/`decr`/`wrap`/`unwp` (usage flags), `tkid`, `data`, `agrp`, `pdmn` | key material *or* SEP key references |

A `kSecClassIdentity` is not a stored row — it is a join: `securityd` matches a `cert` to a `keys` row by the shared public-key hash (`pkhh` ↔ `klbl`) at query time. This is how a VPN or enterprise-Wi-Fi *identity* (cert + private key) is reconstructed.

> 🔬 **Forensics note:** Certificates are public by nature, so the `cert` table's `data` blob is usually **not** secret-wrapped the way a password is — you can frequently DER-decode `subj`/`issr`/`slnr` directly (`openssl x509 -inform DER`) to enumerate which enterprise networks, MDM servers, and VPN endpoints a device was provisioned for, *even on a locked image*. The matching **private** key in `keys`, however, follows the `pdmn`/SEP rules above. So the cert tells you *what the device could authenticate to*; whether you can *impersonate* it depends on extracting the private half.

### SEP-bound keys: the secrets you *cannot* extract

When an item in the `keys` table carries `tkid = com.apple.setoken` (the value of `kSecAttrTokenIDSecureEnclave`), it is a **Secure Enclave-resident key**. The private key was generated *inside* the SEP and the key material never exists outside it; what lives in `keychain-2.db` is only a wrapped **reference/handle**, not the key. App crypto (sign/decrypt) is performed by sending the operation *to* the SEP, which uses the key internally and returns the result.

For acquisition this is a hard wall. A full file-system extraction **plus** the keybag still does not yield a SEP-bound private key, because the key was never on the file system to begin with. The most you recover is the public key and the fact that the private key exists and is SEP-protected. Apps use this exactly because it is non-exfiltratable: device-binding keys, app-attestation keys, and the keys behind "this only works on this physical phone" flows. See [[02-secure-enclave-hardware]].

### Biometric ACLs: the `accc` column

An item can be gated not just by lock state but by **user presence** via an access-control list (`SecAccessControl`, stored in `accc`). Created with flags like:

| `SecAccessControlCreateFlags` | Gate at retrieval |
|---|---|
| `.userPresence` | passcode **or** any enrolled biometric |
| `.biometryAny` | any currently-enrolled Face ID / Touch ID |
| `.biometryCurrentSet` | biometrics **as enrolled now** — invalidated if a finger/face is added or removed |
| `.devicePasscode` | passcode only |
| `.applicationPassword` | an additional app-supplied secret must be provided |

`biometryCurrentSet` is the strong one: the ACL is cryptographically bound to the *current* biometric enrollment, so adding a coerced fingerprint or a new Face ID enrollment **destroys** the item's accessibility rather than granting it. These items typically also use `akpu`/`aku` (passcode-set, this-device-only).

> 🔬 **Forensics note:** A biometric-ACL item is **not** decryptable by simply having an AFU device with the class key resident — retrieval triggers a `LocalAuthentication` (LAContext) prompt that must be satisfied *live*, by a real Face ID/Touch ID match or passcode entry, at extraction time. On a seized device this is the difference between "we have the file system" and "we still cannot read this token." It is why compelled-biometric vs. compelled-passcode is a live legal fight: the biometric is what actually unwraps `biometryCurrentSet` items.

### Access groups and entitlements (`agrp`)

`agrp` is the sandbox boundary inside the Keychain. An app may only read/write rows whose access group appears in its `keychain-access-groups` entitlement (its `application-identifier` is an implicit group; an App Group is another). System secrets sit in groups like `apple` and `com.apple.token`. Two apps from the same developer that share a `keychain-access-groups` value can share credentials; otherwise they are blind to each other's rows. For the reverse-engineer this maps an item back to its owning app; for the developer it is how a single sign-on token is shared across an app suite. (Entitlements and how `securityd` checks them are covered in [[04-code-signing-amfi-entitlements]] and [[05-the-sandbox-and-tcc]].)

### Where the Keychain is *not* — adjacent secret stores

A methodology trap: not every secret on the device is in `keychain-2.db`, and the Keychain holds things that aren't "passwords." Keep a mental map of the neighbors:

- **The keybag itself is not in the Keychain.** The Data Protection *class keys* that wrap Keychain items live in the **keybag** (`/private/var/keybags/`, SEP-entangled), not in `keychain-2.db`. The Keychain is the *vault*; the keybag is the *ring of keys*. ([[02-data-protection-and-keybags]])
- **Apple-account / iCloud tokens** land in the Keychain under system groups like `com.apple.account` and the **`com.apple.token`** access group (AuthKit/`accountsd`), alongside `apsd`'s APNs push credentials — high-value for account context, and easy to overlook if you only grep for `genp` user passwords.
- **App secrets stored *outside* the Keychain.** Plenty of apps stash tokens or keys in their *container* — a plist in `Library/Preferences/`, a file in `Documents/`, a Core Data/SQLite row — sometimes in cleartext, sometimes under `NSFileProtection` rather than the Keychain. These follow **file** Data Protection classes, not `pdmn`, so their recoverability is governed by the same BFU/AFU logic but their *location* is the app sandbox, not `keychain-2.db`. Triage both. ([[00-app-sandbox-and-filesystem-layout]])

> 🔬 **Forensics note:** When an app token is conspicuously *absent* from the Keychain, look in the app's container before concluding it isn't stored — insecure-storage findings (a bearer token in a plaintext `NSUserDefaults` plist) are a staple of mobile app-security testing precisely because so many apps bypass the Keychain. The Keychain is where secrets *should* live; the container is where they too often *also* live.

### The Keychain in backups — the encrypted-only rule

This is the rule examiners memorize:

- **Encrypted** iTunes/Finder backup (a backup *password* is set): the Keychain **is** included, re-wrapped from the device keybag to the **backup keybag** derived from the backup password. With the password you can decrypt those Keychain items off-device. **Syncable / non-`ThisDeviceOnly` items migrate.**
- **Unencrypted** backup (no backup password): the Keychain blob is still present in the backup but its items are wrapped such that they **only restore back to the same device** (UID-entangled) — they are **not** decryptable into plaintext off-device. In practice: no recoverable secrets.
- **`ThisDeviceOnly` items (`…u` classes) never migrate**, full stop — not into an encrypted backup, not into iCloud, not onto a new device during Transfer. They die with the device.

So the bumper-sticker: **only an *encrypted* backup yields Keychain secrets, and even then only the non-`ThisDeviceOnly` ones.** The backup keychain is delivered inside the backup as a property-list/manifest structure (`keychain-backup.plist`-style data referenced from `Manifest.db`), which backup-decryption tooling parses once you supply the backup password.

> ⚖️ **Authorization:** The "set a backup password to get the Keychain" technique is a double-edged, evidence-altering act — if no backup password was previously set, *setting one to force the Keychain into the backup changes device state* and must be documented in your chain of custody, performed only under authority, and ideally on a forensic acquisition that records the modification. See [[03-the-itunes-finder-backup-format]] and [[07-decrypting-backups-and-images]].

### Deleted items, tombstones, and the WAL

A "deleted" Keychain item is not always gone:

- A **local** `SecItemDelete` removes the row, but the freed SQLite page is not zeroed until reused. On a full-FS image you can carve freed pages and the **`keychain-2.db-wal`** for stale rows — though the *secret* in any carved row is still keybag-wrapped and follows the same `pdmn` rules, so carving a deleted `akpu` row off a locked device yields ciphertext, not a password.
- A **sync** delete leaves a deliberate **`tomb = 1`** tombstone (a real, queryable row, secret stripped) so the deletion propagates to the rest of the device circle. Tombstones are themselves evidence: they prove an item *existed and was removed*, with the `mdat` marking when.
- The **WAL** (`-wal`) is the highest-yield recovery target. Because it holds not-yet-checkpointed transactions, it can contain pre-update versions of rows — including a credential's prior value before a password change. **Image the `-wal` and `-shm` alongside the main DB**, always; a `sqlite3` open will checkpoint and collapse them.

> 🔬 **Forensics note:** Don't treat the absence of a current row as proof a credential was never present. Cross-check the WAL, freed pages, tombstones (`tomb=1`), *and* any encrypted backup's older keychain snapshot — and remember that a SEP/keybag-wrapped carved secret is still bound by its original `pdmn`. Deleted-data carving on the Keychain recovers *structure and existence* far more reliably than it recovers *plaintext*. See [[14-deleted-data-recovery]].

### The recoverability matrix

Put it together. For any item, recoverability = (its `pdmn`) × (acquisition method) × (lock state at acquisition):

| `pdmn` | BFU full-FS | AFU full-FS | Unlocked full-FS | Encrypted backup | iCloud Keychain |
|---|---|---|---|---|---|
| `dk` (Always) | ✅ | ✅ | ✅ | ✅ (syncable) | ✅ if `sync=1` |
| `dku` (Always, device-only) | ✅ | ✅ | ✅ | ❌ never migrates | ❌ |
| `ck` (AfterFirstUnlock) | ❌ | ✅ | ✅ | ✅ | ✅ if `sync=1` |
| `cku` (AFU, device-only) | ❌ | ✅ | ✅ | ❌ | ❌ |
| `ak` (WhenUnlocked) | ❌ | ❌* | ✅ | ✅ | ✅ if `sync=1` |
| `aku` (WhenUnlocked, device-only) | ❌ | ❌* | ✅ | ❌ | ❌ |
| `akpu` (PasscodeSet, device-only) | ❌ | ❌* | ✅ (+ passcode set) | ❌ | ❌ |
| any item with a **biometric `accc`** | ❌ | ❌ unless live-auth | ✅ only on live Face ID/Touch ID/passcode | — | — |
| any **SEP-bound** key (`tkid=com.apple.setoken`) | ❌ private key never extractable | ❌ | ❌ | ❌ | ❌ |

`*` AFU but currently **locked**: the class-A key is evicted on lock even after first unlock, so `ak`/`aku`/`akpu` are sealed until the next unlock. "Unlocked full-FS" means the device was acquired *while* unlocked (or you can re-unlock it), the only state in which class-A items are readable.

The full-file-system column assumes you have an extraction that includes a live `AppleKeyStore` unwrap (a checkm8/usbliter8-class BootROM foothold on A8–A13, or a commercial tool's exploit chain on supported A14+), because — as established above — the `keychain-2.db` file alone decrypts nothing. The acquisition mechanics live in [[05-full-file-system-acquisition]] and [[02-bfu-vs-afu-and-data-protection-classes]]; here the point is that **the item's class, not the tool, sets the ceiling.**

### Worked example: three credentials, three fates

Trace three real items through the matrix to make it concrete.

1. **A saved Wi-Fi password.** Lives in `genp`, access group `apple` (the system's `AirPort`/`com.apple.wifi` domain), `svce` = `AirPort`, `acct` = the SSID (not `inet` — iOS files Wi-Fi PSKs as generic passwords, the same way `security find-generic-password` reads them on macOS). System Wi-Fi credentials are classically a **low** protection class — historically `AlwaysThisDeviceOnly` (`dku`) so the device can auto-join a known network *at the lock screen, before first unlock* — which makes the SSID/PSK a staple **BFU-recoverable** artifact, yet `…u` so it **never** appears in a backup or iCloud. (`Always` is deprecated; **verify the exact current `pdmn`** on your target build — but it stays device-only and tends to remain available earlier than user-app secrets, which is the forensic point.)
2. **A third-party app's OAuth refresh token.** A `genp` row, `svce` = the app's namespace, `agrp` = the app's team-prefixed access group, **`pdmn = ck`** (so it refreshes in the background) and **`sync = 0`**. *Fate:* recoverable AFU; included in an **encrypted** backup (it's not `…u`); not synced. Pull this and you can frequently replay the app's cloud session off-device.
3. **A banking app's device-binding key.** A `keys` row, **`tkid = com.apple.setoken`** (SEP-bound), `accc` requiring **`biometryCurrentSet`**, `pdmn = akpu`. *Fate:* **never** extractable — the private key is in the SEP, and even retrieval of its handle is biometric-gated. The most a full-FS + keybag yields is its public key and the fact that it exists.

The discipline: for *every* item you care about, read `agrp` (whose is it?), `pdmn` (when is its key live?), `sync`/`tomb` (does it leave the device?), `tkid`/`accc` (is it SEP-bound or live-auth-gated?) — *before* you reason about whether your acquisition can produce the plaintext. Third-party-app triage methodology builds directly on this (see [[11-third-party-app-methodology]]).

## Hands-on

There is no shell on the device, so every command runs on the Mac — against a **Simulator** Keychain (real schema, fake crypto), a **sample image**, or a **decrypted backup**.

**Locate and open the Simulator's Keychain (unencrypted on the host):**

```bash
# Each booted Simulator has a normal SQLite Keychain on the Mac's disk:
SIMROOT=~/Library/Developer/CoreSimulator/Devices
find "$SIMROOT" -name 'keychain-2.db' 2>/dev/null
# .../Devices/<UDID>/data/Library/Keychains/keychain-2.db

DB="$SIMROOT/<UDID>/data/Library/Keychains/keychain-2.db"
cp "$DB" /tmp/sim-keychain.db        # COPY FIRST — SELECT still spawns -wal/-shm

sqlite3 /tmp/sim-keychain.db '.tables'
# access  genp  inet  cert  keys  metadatakeys  tversion  ...

sqlite3 /tmp/sim-keychain.db 'PRAGMA table_info(genp);'   # full column list
```

**Read the forensically interesting columns (works on the Simulator; metadata is cleartext there):**

```bash
sqlite3 -header -column /tmp/sim-keychain.db "
SELECT rowid,
       agrp,
       svce,
       acct,
       pdmn,
       sync,
       datetime(cdat + 978307200, 'unixepoch', 'localtime') AS created,
       length(data) AS data_len
FROM genp
ORDER BY cdat DESC
LIMIT 30;"
```

**Triage view — flag each item's fate at a glance** (SEP-bound? biometric-gated? leaves the device?):

```bash
sqlite3 -header -column /tmp/sim-keychain.db "
SELECT agrp,
       pdmn,
       sync,
       tomb,
       CASE WHEN tkid IS NOT NULL AND tkid != '' THEN 'SEP' ELSE '' END AS sep_bound,
       CASE WHEN accc IS NOT NULL AND length(accc) > 0 THEN 'ACL' ELSE '' END AS access_ctrl,
       CASE WHEN pdmn LIKE '%u' THEN 'device-only' ELSE 'portable' END AS portability
FROM genp
ORDER BY agrp;"
# Read it as: pdmn = when its key is live · sync/portability = does it leave the device ·
# SEP/ACL = non-extractable / live-auth-gated. That is the recoverability matrix, per row.
```

**Inspect the `data` blob's version prefix (proves it's wrapped, even on the Simulator):**

```bash
sqlite3 /tmp/sim-keychain.db \
  "SELECT quote(substr(data,1,8)) FROM genp LIMIT 5;"   # leading uint32 = encryption version
```

**Make and read a Simulator item with a chosen accessibility class** — the cleanest way is a 12-line test app (Lab 2), but you can also drive the Simulator's running processes; the point is to *watch the `pdmn` column change* with the requested `kSecAttrAccessible`.

**macOS contrast on the same box** (the Data Protection keychain, the iOS analogue):

```bash
# The iOS-style Data Protection keychain on macOS — same keychain-2.db lineage:
ls ~/Library/Keychains/*/keychain-2.db
# Legacy file keychain (NO iOS counterpart) — browse metadata without secrets:
security dump-keychain ~/Library/Keychains/login.keychain-db | head -40
```

**Against a real image / decrypted backup** (sample data, not a live device):

```bash
# In a decrypted full-FS image, the file is present but the data blobs are keybag-wrapped:
sqlite3 image/private/var/Keychains/keychain-2.db \
  "SELECT pdmn, count(*) FROM genp GROUP BY pdmn;"   # class census, no decryption needed

# Decrypting an ENCRYPTED iTunes/Finder backup's keychain (you supply the backup password):
pip install iphone-backup-decrypt          # jsharkey13/iphone_backup_decrypt (open source)
python3 - <<'PY'
from iphone_backup_decrypt import EncryptedBackup, RelativePath
b = EncryptedBackup(backup_directory="~/sample-encrypted-backup", passphrase="BACKUP_PW")
# the keychain is delivered inside the backup's protected manifest; the library
# exposes decrypted keychain items once the backup password unwraps the backup keybag.
PY
```

> 🔬 **Forensics note:** Whatever the source, **copy `keychain-2.db` before you `SELECT`.** A plain read opens it in WAL mode and writes `-wal`/`-shm` sidecars next to the original — on a mounted evidence image that is a modification of the evidence. Image first, work on the copy, hash both.

**Producing an encrypted backup to capture the Keychain** (libimobiledevice; device-bound — narrate it, don't run it without a device + authority):

```bash
# Set a backup password so the Keychain is included and decryptable off-device:
idevicebackup2 -i encryption on '<PASSWORD>'      # ⚠️ alters device state — see ⚖️ below
idevicebackup2 backup --full ./case-backup
# Then decrypt + parse with iphone_backup_decrypt / mvt-ios as above.
```

**Tracing the on-device API (read-only walkthrough; needs a jailbroken/instrumented device):**

```bash
# Watch which items an app requests, and with what query, via Frida:
frida-trace -U -n TargetApp \
  -i 'SecItemCopyMatching' -i 'SecItemAdd' -i 'SecItemUpdate'
# The hooked CFDictionary reveals kSecClass, kSecAttrService/Account, kSecAttrAccessible,
# and the access group — i.e. the item's class and silo, live, without touching the DB.
```

`frida-trace` here is the dynamic-analysis counterpart to the static schema dump: instead of reading `pdmn` off disk you watch the app *declare* its accessibility class at the API boundary. Pair this with [[05-dynamic-analysis-with-frida]].

## 🧪 Labs

> These labs are device-free. The Simulator labs teach **schema, columns, `pdmn`, and epochs** with full fidelity; they teach you **nothing about real encryption** — the Simulator runs on macOS with **no SEP, no Data Protection keybag, and no `AppleKeyStore`**, so its `data` blobs are protected only by host file permissions and its lock-state behavior is fictional. The sample-image lab supplies the real (encrypted) on-disk reality.

### Lab 1 — Dissect the Simulator Keychain schema *(substrate: Xcode Simulator)*

1. Boot any iOS Simulator: `xcrun simctl boot "iPhone 17"` (or pick one from `xcrun simctl list devices`).
2. Locate its `keychain-2.db` with the `find` command above; **copy it** to `/tmp`.
3. `.tables`, then `PRAGMA table_info(genp);` and `PRAGMA table_info(inet);`. Map each column you see to the schema table in this lesson. Note which columns exist in `inet` but not `genp` (`srvr`, `ptcl`, `atyp`, `port`, `path`, `sdmn`).
4. Run the "forensically interesting columns" query. Record the **distinct `pdmn` values** present and the **distinct `agrp` values**. Which system access groups appear on a freshly-booted Simulator?
5. Pull the version prefix of a `data` blob with `quote(substr(data,1,8))`. You have just confirmed the secret is wrapped, not plaintext — even here.

### Lab 2 — Watch `pdmn` track `kSecAttrAccessible` *(substrate: Xcode Simulator)*

Create a throwaway iOS app (or single-view SwiftUI app) and drop this in a button action, then run it on the booted Simulator:

```swift
import Security

func add(_ acct: String, _ accessible: CFString) {
    let q: [String: Any] = [
        kSecClass as String:        kSecClassGenericPassword,
        kSecAttrService as String:  "lab.keychain.demo",
        kSecAttrAccount as String:  acct,
        kSecValueData as String:    Data("s3cret".utf8),
        kSecAttrAccessible as String: accessible,
    ]
    SecItemDelete(q as CFDictionary)
    print(acct, SecItemAdd(q as CFDictionary, nil))   // 0 == errSecSuccess
}
add("when_unlocked",      kSecAttrAccessibleWhenUnlocked)              // expect pdmn = ak
add("after_first",        kSecAttrAccessibleAfterFirstUnlock)          // expect pdmn = ck
add("unlocked_devonly",   kSecAttrAccessibleWhenUnlockedThisDeviceOnly)// expect pdmn = aku
add("passcode_devonly",   kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly) // expect pdmn = akpu
```

1. Run it once.
2. Re-copy the Simulator `keychain-2.db` and query:
   `SELECT acct, pdmn, sync FROM genp WHERE svce='lab.keychain.demo';`
3. Confirm each account landed in the predicted `pdmn`. Confirm the two `…ThisDeviceOnly` items have `sync = 0` and could never be `1`.
4. *(Fidelity caveat: `kSecAttrAccessible` is honored as an attribute and reflected in `pdmn`, but the Simulator does not actually evict any class key on "lock" — the availability semantics are inert here. Exact column population can vary by Xcode version; trust your `PRAGMA`, not memory.)*

### Lab 3 — The real thing is encrypted *(substrate: a public sample full-FS image — e.g. a Josh Hickman iOS reference image)*

1. Mount or extract the sample image read-only; navigate to `private/var/Keychains/keychain-2.db`. Copy it out.
2. Run the **class census**: `SELECT pdmn, count(*) FROM genp GROUP BY pdmn;` and the same for `inet`. You get a profile of the device's secret population **without any decryption** — note how many are `ck`/`cku` (the AFU-recoverable bulk) vs `akpu` (the most protected).
3. Pull a `data` blob and hexdump its first 32 bytes. Contrast with the Simulator: same structural shape, but here the bytes are genuinely keybag-wrapped and inert without the device.
4. Write one paragraph: given this census, *which* of these items would a **BFU** extraction recover, which would **AFU** recover, and which need the device **unlocked or live-biometric**? You are now reading the recoverability matrix off real data.

### Lab 4 — On-device unwrap (read-only walkthrough) *(substrate: narrated; pair with Lab 2/3)*

> ⚠️ **ADVANCED / device-only — narration, not execution.** On a Keychain-unlockable device you have lawful authority over, the decrypt path is: get a foothold that can talk to `AppleKeyStore` (a BootROM-level exploit — **checkm8** on A8–A11, **usbliter8** on A12–A13 (public 2026-06-18), or a commercial chain on A14+), boot a ramdisk, ensure the device is **AFU/unlocked** so the needed class keys are resident, then run an on-device agent (`keychain_dumper`-class tooling, or Frida hooking `SecItemCopyMatching` / the `securityd` XPC) that asks `AppleKeyStore` (external methods `0xA`/`0xB`) to unwrap each row's secret key and returns the plaintext.
>
> The fidelity stand-in you *can* run today: Lab 2 gives you the schema-and-`pdmn` mechanics; Lab 3 gives you the encrypted reality and the census; together they exercise every analyst skill except the live unwrap, which is gated on hardware you don't have.

### Lab 5 — Enumerate provisioned networks/MDM from the `cert` table *(substrate: a public sample full-FS image)*

Certificates are public, so this works on a **locked** image with **no decryption** — the point is to extract investigative context the password tables can't give you.

1. From the sample image's `keychain-2.db`, list certs:
   `SELECT rowid, length(data) AS der_len, hex(substr(labl,1,16)) FROM cert;`
2. Export one cert's DER and decode it:
   ```bash
   sqlite3 copy.db "SELECT writefile('/tmp/c.der', data) FROM cert WHERE rowid=<N>;"
   openssl x509 -inform DER -in /tmp/c.der -noout -subject -issuer -dates -ext subjectAltName
   ```
3. Across all certs, note any **enterprise/802.1X**, **MDM identity**, or **VPN** issuers — each tells you a network or management server the device was provisioned for, *even though you can't read a single password*.
4. Now reason about the matching private keys in `keys`: which would you need (and in what lock state) to actually *impersonate* the device to one of those endpoints? *(Fidelity caveat: the `cert` DER is genuinely decodable here; the private half follows the `pdmn`/SEP rules and is not extractable from this offline image.)*

## Pitfalls & gotchas

- **The file alone is worthless.** The single most common rookie error is treating a copied `keychain-2.db` like `chat.db` — running `sqlite3` and expecting passwords. The `data` column is AES-GCM-wrapped to the keybag via `AppleKeyStore`; without the device's live unwrap you get class codes and (maybe) metadata, never secrets.
- **`pdmn`, not the tool, sets the ceiling.** No acquisition technique recovers an `akpu` item from a locked device or a SEP-bound private key from anywhere. Read the class first; it tells you what's even possible.
- **BFU vs AFU is decisive and perishable.** A device seized **unlocked-once and still powered** exposes every `ck`/`cku` item; let it hit the 72-hour inactivity reboot (or any reboot) and it drops to **BFU**, sealing class-A and class-C keys until the passcode is re-entered. Keep seized devices powered and isolated. ([[03-passcode-bfu-afu-and-inactivity]])
- **Don't expect cloud/legal-process to yield the Keychain.** iCloud Keychain is E2E by design, *independent of ADP*. A subpoena to Apple for saved passwords returns nothing decryptable. (iCloud *Backup* is different — and ADP changes *that* — but the Keychain itself was always E2E.)
- **Setting a backup password to extract the Keychain alters the device.** It's a legitimate technique, but it's an evidentiary modification — authority and documentation required.
- **`ThisDeviceOnly` items vanish in migration.** Don't conclude an app "had no token" because a restored/migrated device or a backup lacks it — `…u`-class items never migrate; they were simply never in the backup to begin with.
- **Metadata-cleartext is a fading assumption.** "Locked Keychains still leak service names" was true for years and is now only partially true as metadata encryption rolled in. Confirm cleartext columns per image; don't assert it from old training.
- **Epoch mismatch.** `cdat`/`mdat` are CFAbsoluteTime (2001), `+978307200`. Don't reach for the `/1e9` nanosecond conversion you use on newer Apple stores — that yields timestamps decades off.
- **Copy before `SELECT`.** WAL sidecars (`-wal`/`-shm`) are written on open. On an evidence image that's contamination; on a live device path it's a write to a protected store.
- **The Simulator's crypto is fiction.** Its `keychain-2.db` teaches schema, `pdmn`, and epochs perfectly, but it has no SEP/keybag — never reason about *decryptability* or *lock-state behavior* from the Simulator. Use a sample image for that.
- **Not every secret is in the Keychain.** Apple-account/APNs tokens hide in system access groups (`com.apple.token`, `com.apple.account`), and third-party apps frequently stash tokens in their *container* (sometimes plaintext). A Keychain that "has no token for app X" is a prompt to check the sandbox, not a conclusion.

## Key takeaways

- The iOS Keychain is one SQLite file, `/private/var/Keychains/keychain-2.db`, brokered exclusively by `securityd`; the `genp` and `inet` tables hold the credentials of interest.
- The **`pdmn`** column (`ak`/`ck`/`dk` + `u`/`p` suffixes) names each item's Data Protection class and is the single variable that decides *when* its secret is unwrappable — `ck`/`cku` (AfterFirstUnlock) is the de-facto default and the reason AFU acquisition matters.
- Recoverability = **class × acquisition method × lock state** (× backup encryption for the offline path). The class sets the ceiling; the tool only determines whether you can reach it.
- The `data` blob is two AES-256-GCM keys (metadata + secret) wrapped to the keybag through `AppleKeyStore`; **the file is inert without a live device unwrap.**
- **`ThisDeviceOnly`** items (`…u` classes) never back up, never sync, never migrate; **syncable** items ride iCloud Keychain, which is **end-to-end encrypted independent of ADP** (Apple cannot produce it).
- **SEP-bound keys** (`tkid = com.apple.setoken`) and **biometric-ACL items** (`accc` with `biometryCurrentSet`) are the hard walls — non-extractable and live-auth-gated respectively, even with a full file system.
- In backups, **only an *encrypted* backup yields Keychain secrets**, and only the non-`ThisDeviceOnly` ones.
- Same `keychain-2.db` lineage and `kSecAttrAccessible` vocabulary as the macOS **Data Protection keychain**, but iOS binds the wrapping keys to the SEP — the macOS login-password decrypt does not transfer.

## Terms introduced

| Term | Definition |
|---|---|
| `keychain-2.db` | The single system-wide SQLite Keychain at `/private/var/Keychains/`; tables `genp`, `inet`, `cert`, `keys`, `metadatakeys`. |
| `securityd` | The iOS daemon that brokers all `SecItem` access, enforces access-group entitlements, and performs Keychain crypto. |
| `genp` / `inet` | Generic-password and internet-password tables; `inet` adds server/protocol/port/auth-type network scoping. |
| `pdmn` | Protection-domain column — the short code (`ak`/`ck`/`dk`/`aku`/`cku`/`dku`/`akpu`) naming an item's Data Protection class. |
| `kSecAttrAccessible` | The `SecItem` attribute that selects the protection class (WhenUnlocked / AfterFirstUnlock / WhenPasscodeSetThisDeviceOnly / …). |
| `AfterFirstUnlock` (`ck`/`cku`) | The common default: secret available after the first post-boot unlock until shutdown — the reason AFU acquisition is high-value. |
| `ThisDeviceOnly` (`…u`) | UID-entangled variant: never backed up, never synced, never migrated. |
| `sync` column | `1` ⇒ the item participates in iCloud Keychain (CKKS/Octagon, formerly SOS); `0` ⇒ local only. |
| `tomb` | Tombstone flag (`1`) marking a sync-deleted placeholder so the deletion propagates. |
| `accc` | Stored `SecAccessControl` ACL — biometric/passcode gates (`biometryCurrentSet`, `.userPresence`, etc.). |
| `tkid` / `com.apple.setoken` | Token-ID column; the value `com.apple.setoken` marks a Secure Enclave-bound (non-extractable) key. |
| `agrp` | Access group — the entitlement silo (`keychain-access-groups`) that bounds which app may see a row. |
| `metadatakeys` | Table holding the per-class wrapping keys for the metadata-encryption layer of the `data` blob. |
| `AppleKeyStore` | Kernel module performing keybag wrap/unwrap (external methods `0xA`/`0xB`); the gate that makes the file inert offline. |
| iCloud Keychain | The E2E-encrypted sync transport for `sync=1` items (CKKS under Octagon today, SOS over IDS historically). |
| iCloud Keychain escrow | The HSM-held, attempt-limited cloud copy used for device-loss recovery; gated by passcode/iCloud Security Code + SMS — the only cloud-side keychain recovery path. |
| Octagon / CKKS | The modern iCloud Keychain trust + CloudKit sync stack (`TrustedPeersHelper`/"Cuttlefish"), successor to SOS-over-IDS. |
| `cert` / `keys` tables | Hold X.509 certificates and key material/SEP references; an `Identity` is a query-time join of the two on the public-key hash. |
| `biometryCurrentSet` | `SecAccessControl` flag binding an item to the *current* biometric enrollment — enrolling a new finger/face invalidates it. |
| WAL (`-wal`/`-shm`) | SQLite write-ahead log sidecars; high-yield carving target for pre-update/deleted keychain rows — image them with the DB. |
| CFAbsoluteTime | The 2001-01-01 epoch used by `cdat`/`mdat`; `+978307200` converts to Unix time. |

## Further reading

- Apple Platform Security guide — "Keychain data protection," "Secure keychain syncing," "iCloud Keychain security overview" (`support.apple.com/guide/security/`).
- Apple Developer — `SecItem` / `kSecAttrAccessible` / `kSecAttrTokenIDSecureEnclave` / `SecAccessControl` reference (`developer.apple.com/documentation/security`).
- Apple open-source `Security` project — `keychain/securityd/SecItemDb.c` (the genp/inet schema), `keychain/ckks/` (CKKS sync), the `AppleKeyStore` interfaces.
- RandoriSec / Shindan — "iOS Keychain: how items are stored" + "Operation Triangulation — Keychain module analysis" (the modern `data`-blob + dual-key reverse engineering).
- Wojciech Reguła (SecuRing) — "Stealing your app's keychain entries from locked iPhone" (accessibility-class misuse in practice).
- Elcomsoft blog — "Extracting and Decrypting iOS Keychain: Physical, Logical and Cloud Options Explored" (the acquisition×class matrix from a tool vendor's view).
- The Apple Wiki — "iCloud Keychain," keybag/SOS/Octagon notes (`theapplewiki.com`).
- Jonathan Levin, *MacOS and iOS Internals* — `securityd`, Data Protection, and the keybag/`AppleKeyStore` plumbing.
- `nabla-c0d3/iphone-dataprotection` and `iphone_backup_decrypt` — reference implementations for keybag-class unwrap and encrypted-backup Keychain extraction.
- `man security` (the macOS contrast tool); `PRAGMA table_info` (`sqlite3` docs) for live schema dumps.

---
*Related lessons: [[02-data-protection-and-keybags]] | [[01-sep-sepos-deep-dive]] | [[03-passcode-bfu-afu-and-inactivity]] | [[07-biometrics-security-architecture]] | [[03-the-itunes-finder-backup-format]] | [[07-decrypting-backups-and-images]] | [[06-icloud-acquisition-and-advanced-data-protection]]*
