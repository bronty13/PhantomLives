# PurpleDiary — Security & Privacy Whitepaper

**Version**: covers PurpleDiary builds from May 2026 onward, with the Phase-1
privacy core in place — a SQLCipher-encrypted database, a Keychain-held
data-encryption key, optional passphrase protection, and a 24-word recovery
key. This whitepaper is updated each time the security posture changes; check
`CHANGELOG.md` for the per-version delta.

This document is meant to be read end-to-end by someone making a trust decision
about PurpleDiary — your journal is some of the most personal data you own, and
you deserve to know exactly what protects it. We describe what we protect, what
we don't, and how, in enough detail that a security-minded reader can audit the
source themselves.

The source tree is open. Everything stated here is verifiable in code.

The single most important fact about PurpleDiary: **it is local-only.** There is
no account, no server, no cloud sync, and no network code. Your journal never
leaves your Mac unless *you* export or copy it. Most of a typical privacy
whitepaper is about defending data in transit and in the cloud — for PurpleDiary
those attack surfaces simply don't exist, because the data never travels.

---

## 1. What we protect

PurpleDiary is a private journal. The words you write in it are meant to stay
yours, readable only on your Mac, by you.

In scope:

- **Journal content.** Every entry — titles, Markdown bodies, mood ratings,
  word counts, the date/time each entry is about, and the tags and people you
  attach. All of it lives inside `diary.sqlite`, which is **encrypted at rest**
  with SQLCipher (AES-256). To anyone without the key, the file is opaque
  ciphertext.
- **The search index and schema.** Because SQLCipher encrypts the database at
  the *page* level, the entire SQLite file — every table, index, and internal
  structure — is ciphertext. There is no plaintext "shadow" of your entries
  anywhere in the file.
- **Photo, video & audio attachments.** Media you attach to an entry — photos
  imported from Apple Photos or from Files, and videos and audio added from
  Files — is stored as BLOBs *inside* `diary.sqlite` (photos as a downscaled
  JPEG plus a thumbnail; video byte-for-byte plus a poster-frame thumbnail; audio
  byte-for-byte), so it inherits the same SQLCipher encryption at rest as your
  text — there are no separate plaintext media files on disk, and it rides along
  inside the encrypted backup zip. (One practical consequence: uncompressed video
  and audio live in the database, so a large file grows both the DB and every
  launch backup.)
- **The encryption key itself.** The 256-bit data-encryption key (DEK) is
  stored in the macOS login Keychain by default, and can additionally be wrapped
  under a passphrase-derived key you choose (opt-in). It is never written to
  disk in the clear.
- **The recovery path.** A 24-word BIP39 recovery key, shown once on first
  launch, can re-derive access to the DEK if your Keychain entry is ever lost.
  It is stored only inside an encrypted `recovery_envelope.json` — never in the
  clear.

Explicitly out of scope:

- **`settings.json` is plaintext.** Your preferences — accent color, week-start
  day, word goal, backup configuration, lock toggles — are stored as plain JSON.
  This file contains **no journal content**: no entry text, no titles, no tags
  you've written, no mood data. It is deliberately readable so the app can boot
  and so you can inspect/repair it. If that bothers you, see §10.
- **Local attack with admin / root on a running, unlocked Mac.** If an attacker
  can read your process memory or your Keychain while you are signed in and the
  journal is unlocked, the DEK is reachable. FileVault + your Mac login password
  are the primary defence; PurpleDiary is defence-in-depth on top of that.
- **Forensic recovery after a deliberate reset.** If the Keychain key is lost
  and you choose **Reset and start fresh** instead of entering your recovery
  key, the old encrypted database is *quarantined* on disk (renamed aside, not
  deleted) — but without the key or recovery phrase it stays unreadable. That's
  the point. Backups in `~/Downloads/PurpleDiary backup/` are your recovery
  path; so is the 24-word key.

---

## 2. Threat model

We think about these threats specifically:

1. **Device theft.** Mac stolen while locked. FileVault is the first wall;
   PurpleDiary's encrypted-at-rest database is the second. Even if FileVault is
   somehow defeated, the attacker faces AES-256 ciphertext at the file level,
   and — if you've set a passphrase or enabled app-lock — another gate on top.
2. **Bare-file exfiltration.** A Time Machine backup landing on a NAS that turns
   out to be world-readable. Dropbox accidentally syncing the wrong folder. A
   copy of `~/Library/Application Support/PurpleDiary/` ending up on a USB stick.
   None of these reveal your journal, because `diary.sqlite` is encrypted and the
   key isn't in any of the copied files (it lives in the Keychain, or — if you
   set a passphrase — only as ciphertext you can't unwrap without the passphrase).
3. **Casual snooping on a shared Mac.** Someone sits down at your unlocked Mac
   and opens PurpleDiary. With app-lock enabled (Touch ID / device password /
   passphrase, lock-on-launch and lock-on-background), they hit the lock screen
   instead of your journal.
4. **Lost Keychain entry.** OS reinstall, a botched migration, a Keychain reset
   — the DEK slot vanishes but `diary.sqlite` is still encrypted and still on
   disk. Without recovery this would be permanent data loss. PurpleDiary's
   24-word recovery key re-derives the DEK and unlocks the database. (This is a
   deliberate difference from some sibling apps that have *no* recovery path.)

Threats we acknowledge but don't fully mitigate:

- **Memory scraping during use.** While an entry is open for editing, its
  plaintext is in process memory. We don't pin pages or zero buffers after
  decrypt. Standard OS protections (ASLR, page-level FileVault) apply.
- **Side-channels on Keychain access.** The DEK Keychain item uses
  `kSecAttrAccessibleWhenUnlocked` and is not itself gated behind Touch ID — the
  app-lock screen is a separate, app-level gate. A user-level attacker on a
  running, unlocked Mac could read the Keychain item subject to its ACLs.
- **Forward secrecy on at-rest data.** If the DEK is ever compromised, all
  historic entries on this Mac are exposed. We don't rotate per-entry keys.
  Adding rotation is a meaningful architectural change for marginal benefit at
  this scale.
- **The recovery key is a bearer token.** Anyone who has your 24 words can
  unlock your journal, the same way anyone with a seed phrase can drain a
  wallet. Protecting the phrase is your responsibility (see §3d).

---

## 3. At rest

Every user-data file lives under `~/Library/Application Support/PurpleDiary/`.
Here's what's encrypted, and how:

| File | Encryption | Notes |
|---|---|---|
| `diary.sqlite` (entire file) | **SQLCipher 4.6.1** | AES-256-CBC page encryption + HMAC-SHA512 per-page authentication. Vendored amalgamation, CommonCrypto backend. Every entry, the schema, all indexes, **and imported photo/video/audio attachments (stored as BLOBs)** are opaque ciphertext without the DEK. |
| `keystore.json` | **Wrapped DEK** | Present only when a passphrase is set. Holds the DEK wrapped under a passphrase-derived KEK (AES-256-GCM), plus the salt and KDF iteration count. Never contains the DEK in the clear. |
| `recovery_envelope.json` | **Wrapped DEK** | Always present after first launch. Holds the DEK wrapped under a key derived from your 24-word recovery phrase, plus salt + iteration count. Never contains the DEK in the clear. |
| `boot_state.json` | **Plaintext marker** | A small "this install has booted before" flag. Carries no key material and no journal content — it exists to prevent minting a *fresh* DEK (and orphaning your encrypted data) if the Keychain entry is lost out-of-band. |
| `settings.json` | **Plaintext** | Non-sensitive preferences only. No journal content. See §10. |

### §3a — How SQLCipher protects the database

SQLCipher applies encryption transparently below GRDB's SQL layer. Every
4096-byte SQLite page is encrypted with AES-256-CBC using the DEK as the page
key. After encryption, an HMAC-SHA512 tag is computed over the (encrypted page +
page number + nonce); the tag is stored alongside the page and checked on read.
A wrong key or any single-byte tamper produces an HMAC mismatch and the
page-read fails with "file is not a database" — never a silent corruption.

The encryption is at the **page level**, not the table level — meaning the
schema (`sqlite_master`), every index, and the WAL journal all live in encrypted
pages. File metadata (size, modification time) is visible to the filesystem, but
file *contents* are opaque.

The DEK never leaves `KeyStore`. SQLCipher's `PRAGMA key` is run by GRDB's
`Configuration.prepareDatabase` on every new connection, with the raw 256-bit
DEK in `x'<hex>'` form — no further KDF is applied at the SQLCipher layer (the
keystore already did PBKDF2 if you set a passphrase). PRAGMA defaults are pinned
explicitly so a future SQLCipher major release that changes defaults can't
silently break the database:

```
PRAGMA cipher_page_size = 4096
PRAGMA kdf_iter = 256000
PRAGMA cipher_hmac_algorithm = HMAC_SHA512
PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512
```

### §3b — Migration from a plaintext database

If you ran an earlier (pre-encryption) build of PurpleDiary, your existing
`diary.sqlite` is plaintext. On the first launch after the encryption slice
ships, PurpleDiary detects this by reading the first 16 bytes of the file (the
SQLite 3 magic header `SQLite format 3\0` is plaintext-only; a SQLCipher file's
first 16 bytes are random ciphertext), then runs SQLCipher's documented
`sqlcipher_export()` migration into a keyed sibling file:

```sql
ATTACH DATABASE 'diary.sqlite.sqlcipher.tmp' AS encrypted KEY "x'<hex>'";
SELECT sqlcipher_export('encrypted');
DETACH DATABASE encrypted;
```

The temporary file is then atomically renamed over the plaintext original.
The migration is idempotent — an already-encrypted database skips it cleanly.
Crucially, the **launch-time backup runs *before* the migration**, so the
pre-migration plaintext state is captured in `~/Downloads/PurpleDiary backup/`
as a safety net the first time encryption is applied.

### §3c — The data-encryption key and the optional passphrase

The DEK is 256 bits, generated via `SecRandomCopyBytes`. By default it's stored
in the macOS login Keychain under the service `com.bronty13.PurpleDiary`. The
app opens silently because the Keychain holds the key — no prompt, no friction.

Optional passphrase protection adds a wrapping layer:

- A 16-byte salt is generated via `SecRandomCopyBytes`.
- A key-encryption key (KEK) is derived from your passphrase via PBKDF2-HMAC-SHA256
  with **300,000 iterations**.
- The DEK is wrapped with the KEK (AES-256-GCM) and stored in `keystore.json`
  along with the salt and iteration count. The unwrapped DEK is cached in the
  Keychain so subsequent launches don't reprompt; "Lock now" clears that cache.

300,000 iterations is calibrated against modern desktop-class hardware:
empirically an Apple Silicon Mac derives the KEK in roughly 500 ms. A determined
attacker running on rented GPU hardware faces a meaningful cost-per-guess;
combined with a passphrase of reasonable entropy, the search space is
impractical. This matches what 1Password and Signal use on desktop today.

Changing the passphrase re-wraps the DEK only — no journal data is re-encrypted.
Removing the passphrase deletes `keystore.json` and falls back to Keychain-only
protection, after verifying the current passphrase first (so an attacker at an
unlocked Mac can't strip protection without proving they know it).

### §3d — The 24-word recovery key

Unlike a pure passphrase model, PurpleDiary gives you a way back in if the
Keychain entry is ever lost. On first launch it shows you a **24-word BIP39
recovery key** and requires you to confirm you've saved it (write it down, print
it, or store it in a password manager) before continuing.

- The 24 words encode 256 bits of entropy plus a BIP39 checksum, so a mistyped
  or transposed word is rejected rather than silently producing a wrong key.
- A KEK is derived from the phrase (PBKDF2-HMAC-SHA256, 300,000 iterations,
  16-byte salt) and used to wrap the DEK (AES-256-GCM). The result lives in
  `recovery_envelope.json`. The phrase itself is **never stored** — only the
  envelope it can open.
- If the Keychain DEK is ever missing, PurpleDiary shows a recovery screen: enter
  your 24 words, the app re-derives the KEK, unwraps the DEK, re-caches it in the
  Keychain, and your journal opens. You can regenerate the recovery key anytime in
  **Settings → Security** (which mints a new phrase and rewraps the envelope).

Because the phrase *is* the key, treat it like a seed phrase: anyone who has it
can read your journal. There is no "reset my recovery key from inside the app
without it" — that would defeat the purpose.

---

## 4. In transit — there is no "in transit"

PurpleDiary has **no networking code**. It does not phone home, check for
updates over the network, sync to a cloud, send telemetry, or open a socket for
any reason. There is no account to create and no server to compromise. The
threat categories that dominate most security reviews — TLS configuration,
server breaches, man-in-the-middle, end-to-end-encryption guarantees against the
cloud provider — do not apply, because nothing is ever transmitted.

If you want your journal on more than one Mac, the planned approach (a later
phase) is the simplest possible one: point the database or its backups at a
folder you already sync (iCloud Drive, Dropbox, a file server). Because the
database is already encrypted at rest, the synced file is protected in flight
and at rest by the same SQLCipher layer — the sync provider only ever sees
ciphertext. That feature is not in this build; it's noted here so the privacy
story for it is on record up front.

---

## 5. App-lock

App-lock is a second, app-level gate in front of your journal, independent of
the on-disk encryption. Configure it in **Settings → Security**:

- **Require unlock** puts a lock screen in front of the app.
- **Lock on launch** shows the lock screen every time you open PurpleDiary.
- The app also **locks when it loses focus** (you switch away, or it goes to the
  background), so a journal left open doesn't sit exposed.
- Unlock with **Touch ID** / your Mac password (via Apple's `LocalAuthentication`),
  or with your **passphrase** if you've set one.
- **Touch ID only** mode disables the password fallback for a stricter gate
  (recover by quitting and turning the mode back off if your sensor fails).
- **Lock Now** (⌘L, or the menu) locks immediately.

App-lock and encryption are complementary: encryption protects the file if it's
copied off your Mac; app-lock protects the live app if someone reaches your
unlocked desktop.

---

## 6. Cryptographic primitives (the table for the curious)

| Use | Primitive | Implementation |
|---|---|---|
| Symmetric encryption (key wrapping, envelopes) | AES-256-GCM (96-bit nonce, 128-bit tag) | `CryptoKit.AES.GCM` |
| Key derivation (passphrase / recovery phrase → KEK) | PBKDF2-HMAC-SHA256, 300,000 iterations, 16-byte random salt | `CommonCrypto.CCKeyDerivationPBKDF` |
| Database encryption | SQLCipher 4.6.1: AES-256-CBC page encryption + HMAC-SHA512 per-page MAC + 256,000 PBKDF2 iterations (KDF unused; raw DEK passed via `x'<hex>'`) | Vendored amalgamation at `Vendor/SQLCipher/`, CommonCrypto backend |
| Recovery key encoding | BIP39 24-word mnemonic (256-bit entropy + checksum) | `RecoveryKey.swift` (pure Swift, bundled wordlist) |
| Random number generation | System CSPRNG | `SecRandomCopyBytes` |

No custom cryptographic constructions. Everything routes through Apple's vetted
libraries (`CryptoKit`, `CommonCrypto`, `SecRandomCopyBytes`) or Zetetic's
audited SQLCipher build. The only hand-written cryptographic-adjacent code is the
BIP39 word↔entropy encoder, which is a deterministic encoding (not a cipher) and
is covered by reference-vector tests.

---

## 7. Where this lives in the source

| File | Role |
|---|---|
| `Sources/PurpleDiary/Services/Crypto.swift` | AES-GCM seal/open + PBKDF2 + `SecRandomCopyBytes` wrapper |
| `Sources/PurpleDiary/Services/KeyStore.swift` | DEK lifecycle (generate / wrap with passphrase / unlock / change / remove / recovery envelope / reset) |
| `Sources/PurpleDiary/Services/KeychainStore.swift` | `SecItem`-level Keychain wrapper (service `com.bronty13.PurpleDiary`) |
| `Sources/PurpleDiary/Services/RecoveryKey.swift` | BIP39 24-word encode / decode / checksum-validate, recovery-KEK derivation |
| `Sources/PurpleDiary/Services/BIP39Wordlist.swift` | The 2048-word BIP39 English wordlist |
| `Sources/PurpleDiary/Services/BootState.swift` | "ever-booted" marker that guards against minting a fresh DEK over existing data |
| `Sources/PurpleDiary/Services/BiometricAuthService.swift` | `LocalAuthentication` bridge for Touch ID / device password |
| `Sources/PurpleDiary/Services/DatabaseService.swift` | SQLite open with `PRAGMA key` via SQLCipher; `migratePlaintextToSQLCipher` runs `sqlcipher_export()` for upgrade installs |
| `Vendor/SQLCipher/` | Vendored SQLCipher 4.6.1 amalgamation. See `PROVENANCE.md` for the tarball SHA-256 + build recipe |
| `Vendor/GRDB/` | Locally-patched GRDB. The `Sources/CSQLite/` shim re-exports SQLCipher's `sqlite3.h` so GRDB's symbol bindings tag against our SQLCipher binary, not `libsqlite3.dylib` |

The test suite (`Tests/PurpleDiaryTests/`) exercises the crypto paths against
known-answer round-trips, wrong-key rejection, BIP39 reference vectors and
checksum/typo rejection, passphrase-mismatch handling, recovery-unlock
round-trips, and the at-rest invariants (ciphertext on disk, wrong-key
rejection, plaintext→SQLCipher migration preserves rows).

---

## 8. Verifying the claims

You should be able to audit this without trusting us. A few checks anyone can
run on their own install:

1. **Verify the database is encrypted at rest.**
   ```sh
   head -c 16 ~/Library/Application\ Support/PurpleDiary/diary.sqlite | xxd
   ```
   The first 16 bytes should be **random**, not the ASCII string
   `SQLite format 3\0` (`53 51 4c 69 74 65 20 66 6f 72 6d 61 74 20 33 00`).
   If you see that magic header, the file is plaintext — file a bug.

   ```sh
   file ~/Library/Application\ Support/PurpleDiary/diary.sqlite
   # → "data"  (not "SQLite 3.x database")
   ```

2. **Confirm there's no key material on disk in the clear.**
   ```sh
   cat ~/Library/Application\ Support/PurpleDiary/recovery_envelope.json | python3 -m json.tool
   # → JSON with `salt`, `iterations`, `wrappedDEK` (base64 ciphertext)
   ```
   `wrappedDEK` is the DEK encrypted under a key you can only derive from the
   24-word phrase. The salt is random; the iteration count reflects the current
   KDF cost (300000). No plaintext key bytes appear anywhere. If you've set a
   passphrase, `keystore.json` has the same shape.

3. **Confirm settings.json carries no journal content.**
   ```sh
   cat ~/Library/Application\ Support/PurpleDiary/settings.json | python3 -m json.tool
   ```
   You should see only preferences (accent color, week start, word goal, backup
   path, lock toggles) — no entry text, titles, tags, or moods.

4. **Confirm there's no network traffic.** Watch the app with Little Snitch, or
   `lsof -i -nP | grep -i purplediary` while it runs. There should be nothing —
   PurpleDiary opens no sockets.

---

## 9. Backups and the encrypted database

PurpleDiary backs up the whole `~/Library/Application Support/PurpleDiary/`
directory to `~/Downloads/PurpleDiary backup/` on every launch (5-minute
debounce, 14-day retention by default). Because that directory includes the
encrypted `diary.sqlite` plus `keystore.json` and `recovery_envelope.json`, a
backup restored onto a fresh Mac is fully recoverable: the Keychain DEK won't be
present there, but you can unlock with your passphrase or your 24-word recovery
key. The backup **Test** action opens the archived database *with the live key*
so verification works on an encrypted archive; **Restore** writes a
`pre-restore` safety backup first, then swaps the live directory.

The one moment a plaintext database can appear in a backup is the very first
launch after the encryption upgrade: that launch's backup intentionally captures
the *pre-migration* plaintext `diary.sqlite` as a safety net (see §3b). Every
backup after the migration contains only the encrypted database.

---

## 10. Known limitations (the honest section)

- **`settings.json` is not encrypted.** It holds only non-sensitive preferences
  and never journal content, so the privacy cost is low — but it is plaintext on
  disk, unlike the database. If your threat model requires even your preferences
  to be opaque, that's not covered today.
- **Photo, video & audio attachments are in the database.** Media you attach
  (photos from Apple Photos or Files, videos and audio from Files) is stored as
  BLOBs inside the SQLCipher database (see §1, §3), so it's encrypted at rest and
  captured by backups like everything else. Photos are downscaled; **video and
  audio are stored uncompressed**, so a large file noticeably grows the database
  and every launch backup. Arbitrary-file attachments are not yet supported.
- **Hidden journals are a visibility gate, not separate encryption.** A journal
  marked *hidden* is filtered out of the Timeline, Calendar, Search, and Insights
  until you unlock it for the session (Touch ID / device password / passphrase).
  But its entries are stored under the **same single database key** as everything
  else — they are exactly as encrypted at rest as any other entry, no more and no
  less, and a full export includes them. A snooper at an *unlocked* Mac who
  bypasses the app could still read a hidden journal's bytes from the open
  database. For genuine per-journal cryptographic separation, use a **Vault**
  (below). Treat "hidden" as "kept out of sight," not "separately encrypted."
- **Vault journals are separately encrypted, even with the app open.** A journal
  made into a *vault* (right-click → Make Vault…) has each entry's **title, body,
  and attachment bytes** (the `data` and `thumbnail_data` BLOBs) sealed under a
  per-journal random 256-bit content key (CK), AES-256-GCM, with a `pdvlt1:`
  sentinel (a raw-bytes prefix for blobs). CK is wrapped two ways in the
  `vault_envelopes` table
  — under a **passphrase-derived KEK** (PBKDF2-HMAC-SHA256, 300k iters, per-journal
  salt) and under a **KEK derived from the 24-word recovery key** — so a forgotten
  passphrase isn't permanent lockout. CK lives only in an in-memory session map
  while unlocked; it is dropped on app-lock (⌘L), on relaunch, and on **Lock Vault
  Now**. Consequences that strengthen the model: a locked vault's entries are
  ciphertext on disk *and* in the open database (a snooper at an unlocked Mac who
  bypasses the app sees only ciphertext), are gated out of all views, and are
  **skipped by export** (only unlocked vaults emit plaintext). Creating a vault
  verifies *both* wraps round-trip back to CK before any entry is sealed
  (all-or-nothing). Sealing follows the entry through convert (Make Vault),
  remove (decrypt-in-place), and moves across journals (re-keyed in both
  directions). **Metadata not sealed:** an entry's date, mood, word count, tags,
  and an attachment's filename/MIME/dimensions/`size_bytes` stay queryable under
  the single DB DEK, so a vault hides *content*, not the fact that entries exist
  or their rough size. The recovery key is a master key for vaults too: anyone
  holding it can open them.
- **Keychain ACL trust boundary.** The DEK uses `kSecAttrAccessibleWhenUnlocked`
  and is not gated behind Touch ID at the Keychain level (app-lock is a separate
  gate). A user-level attacker on a running, unlocked Mac can reach the DEK
  subject to Keychain ACLs. FileVault + login password is the primary defence.
- **No forward secrecy on at-rest data.** A DEK compromise exposes all historic
  entries on this Mac. We don't rotate per-entry keys.
- **Memory safety during editing.** Plaintext lives in RAM while an entry is
  open. Standard OS-level protections apply; we don't pin pages or zero memory
  after decrypt.
- **The recovery key is a bearer credential.** Convenience (you can always get
  back in) trades against risk (anyone with the 24 words can too). Store it like
  a seed phrase.

---

## 11. Reporting a vulnerability

If you find a security issue in PurpleDiary, please report it before disclosing
publicly. Two channels:

- Email the developer directly: `robert.olen@gmail.com`. Encrypt the report with
  the developer's PGP key if you have it, or send a "please share key" email
  first.
- Open a **private** GitHub security advisory on the
  [`PhantomLives` repository](https://github.com/bronty13/PhantomLives). Don't
  file a public issue.

Acknowledgement within 5 business days; substantive triage within 30. We don't
run a bug-bounty program (PurpleDiary is a personal project), but we appreciate
the work and will credit reporters by name in the changelog unless asked not to.

---

## 12. Version & changelog

This whitepaper covers PurpleDiary versions where the Phase-1 privacy core
(SQLCipher encryption-at-rest, Keychain DEK, optional passphrase, 24-word
recovery key, app-lock) is shipped. Earlier scaffold builds stored the database
in plaintext and treated app-lock as UI-only.

Each material change to the security posture lands as a `CHANGELOG.md` entry and
an update here. The repository history is the canonical chronology.

---

*Drafted 2026-05-30. Last reviewed 2026-05-31 (photo, video & audio attachments stored as encrypted BLOBs).*
