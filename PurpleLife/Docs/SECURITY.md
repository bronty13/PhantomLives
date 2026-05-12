# PurpleLife — Security & Privacy Whitepaper

**Version**: covers PurpleLife builds from May 2026 onward, with the full encryption foundation in place — passphrase-managed key, encrypted settings, encrypted attachment files, and SQLCipher-encrypted SQLite database (slices A1 + A3 + A2 of the encryption-foundation work). This whitepaper is updated each time the security posture changes; check `CHANGELOG.md` and `HANDOFF.md` for the per-version delta.

This document is meant to be read end-to-end by someone making a trust decision about PurpleLife. We're describing what we protect, what we don't, and how — in enough detail that a security-minded reader can audit the source themselves.

The source tree is open. Everything stated here is verifiable in code.

---

## 1. What we protect

PurpleLife is a personal data tool. The data you put in it is meant to stay yours.

In scope:

- **Record content.** Every field of every record — note bodies, contact details, planner items, journal entries, weight measurements, schema definitions you've created. Encrypted at rest on disk (after slice A2 lands, including the SQLite file; before that, settings.json + attachment files only). Encrypted in transit to Apple. Encrypted at rest in iCloud through CloudKit's end-to-end layer.
- **Attachments.** Photos, PDFs, screenshots — anything you paste into a note or attach to a record. Encrypted at rest locally (AES-256-GCM per file). Inline images inside rich-text notes ride inside the encrypted record blob (not as separate `CKAsset` files, which would have a weaker iCloud guarantee — see §5).
- **Application settings.** Your preferences, saved queries, theme choices — `settings.json` is wrapped with AES-256-GCM.
- **The encryption key itself.** The 256-bit data-encryption key is stored either in the macOS Keychain alone (default) or additionally wrapped under a passphrase-derived key-encryption key (opt-in).

Explicitly out of scope:

- **Local attack with admin / root on a running, unlocked Mac.** If an attacker can read your process memory or your Keychain while you're signed in, the data-encryption key is reachable. FileVault + your Mac login password are the primary defence; PurpleLife is defence-in-depth on top of that.
- **CloudKit metadata.** Apple necessarily sees that records exist, when they're modified, and what record types they belong to. The encrypted payload (`encryptedValues`) hides the contents but not the existence-and-shape envelope. We don't claim to anonymize this; CloudKit needs it to sync.
- **Forensic recovery after `Reset (destroys all data)`.** The keystore reset is intentional and unrecoverable. Backups land in `~/Downloads/PurpleLife backup/`; use those if you want recovery, not the reset flow.

---

## 2. Threat model

We think about these threats specifically:

1. **Device theft.** Mac stolen while locked. FileVault is the first wall; PurpleLife's encrypted-at-rest files are the second. Even if FileVault is somehow defeated, the attacker faces AES-256-GCM ciphertext at the file level.
2. **Bare-file exfiltration.** Time Machine backup landing on a NAS that turns out to be world-readable. Dropbox accidentally syncing the wrong folder. A copy of `~/Library/Application Support/PurpleLife/` ending up on a USB stick. None of these reveal your data, because the files themselves are encrypted and the key isn't in any of them.
3. **CloudKit server compromise.** Apple's infrastructure compromised, internal employee turning malicious, government subpoena to Apple, etc. `CKRecord.encryptedValues` exists exactly for this case — keys are derived from your iCloud account credentials and never leave your devices. Apple can hand over the bytes; the bytes are encrypted under keys Apple doesn't have.
4. **Network MitM.** Some hostile entity between you and Apple's servers. TLS 1.2+ with OS-pinned certificates — no custom networking, no plaintext fallback. The MitM sees encrypted blobs going to Apple's IPs.
5. **Lost device with iCloud still signed in.** Apple's Find My / Activation Lock handles the device side. On the PurpleLife side: if you've set a passphrase, "Lock now" before walking away (or schedule a lock — `kSecAttrAccessibleWhenUnlocked` ensures the Keychain item isn't available while the Mac is at the lock screen anyway). If you haven't set a passphrase, you're relying on the Mac login password as the gate.

Threats we acknowledge but don't fully mitigate:

- **Memory scraping during use.** While a note is open for editing, its plaintext is in process memory. We don't pin pages or zero buffers after decrypt. Standard OS protections (ASLR, page-level FileVault) apply.
- **Side-channels on Keychain access.** Touch ID / biometric gating on the DEK Keychain item isn't yet implemented. Currently a simple unlock check.
- **Forward secrecy on at-rest data.** If the DEK is ever compromised, all historic data on this Mac is exposed. We don't rotate per-record keys. Adding rotation is a meaningful architectural change for marginal benefit at this scale.

---

## 3. At rest

Every user-data file lives under `~/Library/Application Support/PurpleLife/`. Here's what's encrypted, and how:

| File | Encryption | Notes |
|---|---|---|
| `purplelife.sqlite` (entire file) | **SQLCipher 4.6.1** | AES-256-CBC page encryption + HMAC-SHA512 per-page authentication. Vendored amalgamation, built with the CommonCrypto crypto backend. Everything inside the SQLite file — `objects` rows, the FTS5 search index, attachments metadata, schema, indexes — is opaque ciphertext to anyone without the DEK. |
| `attachments/<sha256>.<ext>` file content | **AES-256-GCM** | Per-file wrap via `EncryptedJSON`. Filename is sha256 of the *plaintext* so deduplication works across the encryption boundary. |
| `settings.json` | **AES-256-GCM** | Same `EncryptedJSON` envelope. `safeWrite` refuses to silently downgrade an encrypted file to plaintext. |
| `keystore.json` | **Wrapped DEK** | Present only when a passphrase is set. Holds the DEK wrapped under a passphrase-derived KEK, plus salt + KDF parameters. Never contains the DEK in the clear. |

### §3a — How SQLCipher protects the SQLite file

SQLCipher applies encryption transparently below GRDB's SQL layer. Every 4096-byte SQLite page is encrypted with AES-256-CBC using the DEK as the page key. After encryption, an HMAC-SHA512 tag is computed over the (encrypted page + page number + nonce); this tag is stored alongside the page and checked on read. A wrong key or any single-byte tamper produces an HMAC mismatch and the page-read fails with "file is not a database" — never a silent corruption.

The encryption is at the **page level**, not the table level — meaning:

- Schema info (table definitions, column names) is in `sqlite_master`, which lives in encrypted pages.
- Indexes (including the FTS5 search index) live in encrypted pages.
- WAL journal entries are also encrypted.
- File metadata (size, modification time) is visible to the filesystem, but file *contents* are opaque.

The DEK never leaves `KeyStore`. SQLCipher's `PRAGMA key` is run by `Configuration.prepareDatabase` on every new GRDB connection, with the raw 256-bit DEK in `x'<hex>'` form — no further KDF is applied at the SQLCipher layer (the keystore already did PBKDF2 if the user set a passphrase). PRAGMA defaults are pinned explicitly so a future SQLCipher major release that changes defaults can't silently break our DB:

```
PRAGMA cipher_page_size = 4096
PRAGMA kdf_iter = 256000
PRAGMA cipher_hmac_algorithm = HMAC_SHA512
PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512
```

### §3b — Migration from a pre-SQLCipher install

On the first launch after the SQLCipher slice ships, existing installs have a plaintext `purplelife.sqlite`. PurpleLife detects this by reading the first 16 bytes of the file (the SQLite 3 magic header `SQLite format 3\0` is plaintext-only; a SQLCipher-encrypted file's first 16 bytes are random ciphertext), then runs SQLCipher's documented `sqlcipher_export()` migration:

```sql
ATTACH DATABASE 'purplelife.sqlite.sqlcipher.tmp' AS encrypted KEY "x'<hex>'";
SELECT sqlcipher_export('encrypted');
DETACH DATABASE encrypted;
```

The temporary file is then atomically renamed over the plaintext original. Idempotent — already-encrypted DBs skip the migration cleanly.

The `EncryptedJSON` envelope format: 5-byte magic header (`PLIF\x01`) followed by an AES-256-GCM "combined" blob (12-byte nonce ‖ ciphertext ‖ 16-byte authentication tag). The magic header lets readers detect plaintext-vs-ciphertext at byte 0; it also makes it instantly clear a file isn't a stray PurpleIRC or other PhantomLives sibling's file (each app uses a distinct magic).

The data-encryption key (DEK) is 256 bits, generated via `SecRandomCopyBytes`. By default it's stored in the macOS Keychain under a per-install slot (the account name is derived from a SHA-256 hash of the Application Support directory path, so multiple installs of PurpleLife don't share the slot). The app opens silently because the Keychain has the key.

Optional passphrase protection adds a wrapping layer:

- A 16-byte salt is generated via `SecRandomCopyBytes`.
- A key-encryption key (KEK) is derived from your passphrase via PBKDF2-HMAC-SHA256 with **300,000 iterations**.
- The DEK is wrapped with the KEK (AES-256-GCM) and stored in `keystore.json` along with the salt and KDF parameters.
- The unwrapped DEK is cached in the Keychain so subsequent launches don't reprompt. "Lock now" clears the cache; the next access requires you to type the passphrase.

300,000 iterations is calibrated against modern desktop-class hardware. Empirically: an Apple Silicon Mac derives the KEK in roughly 500ms. A determined attacker running on rented GPU hardware faces a meaningful cost-per-guess; combined with a passphrase of reasonable entropy, the search space is impractical.

Changing the passphrase re-wraps the DEK only — no user data is re-encrypted. Removing the passphrase deletes `keystore.json` and falls back to Keychain-only protection, after verifying the current passphrase first (so an attacker at an unlocked Mac can't strip protection without proving they know it).

**There is no passphrase recovery.** This is intentional. A recovery mechanism would mean we — or some third party — held a way back into your data. We don't. If you forget the passphrase and the Keychain cache is gone, the data is unrecoverable from that Mac. Backups (`~/Downloads/PurpleLife backup/`) and other signed-in Macs are your recovery paths.

---

## 4. In transit

Every byte that crosses the network goes through CloudKit's TLS 1.2+ connection to Apple's servers. Certificates are pinned by macOS. We do no custom networking, have no plaintext fallback, and never reach for an alternate transport.

If TLS to Apple fails (network captive portal, firewall, etc.), the sync transitions to a soft-error state and retries on a recovery interval. Your data stays local and usable; nothing is sent in the clear under any condition.

---

## 5. In iCloud — the end-to-end story

CloudKit offers two storage tiers for record data:

- **Plain fields**, which Apple can read server-side.
- **`encryptedValues`**, which Apple stores but cannot read.

PurpleLife puts every piece of user content into `encryptedValues`:

| Field on the wire | What it contains | Encrypted? |
|---|---|---|
| `encryptedValues["fieldsJSON"]` | The whole record's `fields_json` blob (your data) | ✅ E2E |
| `encryptedValues["typeJSON"]` | A serialized `ObjectType` definition | ✅ E2E |
| `type_id` (plain field) | Which type the record belongs to | ❌ Visible to Apple |
| `parent_id` (plain field) | Optional parent-record reference for hierarchy | ❌ Visible to Apple |
| `created_at` / `updated_at` (plain fields) | Timestamps for LWW conflict resolution | ❌ Visible to Apple |

The plain fields are what CloudKit needs to drive sync — Apple has to know "a record exists, of this type, last modified at this time" so the server can replicate and resolve conflicts. The plain fields **do not** contain user content; they're sync metadata.

**Pasted images in notes** live inside the rich-text body, which is inside `fieldsJSON`, which is inside `encryptedValues`. They get the same E2E protection as the text around them. This is the explicit reason we don't use `CKAsset` for in-note images: `CKAsset` storage is *not* end-to-end encrypted — Apple has keys for assets even though it doesn't have keys for `encryptedValues`. Trading off some image-bloat (a 1920-wide screenshot is ~150 KB after JPEG @ 0.7 compression) for true E2E was an explicit decision.

CloudKit derives the per-record encryption keys from your iCloud account material. The keys never leave your devices — Apple never sees them. Multi-device sync works because every Mac signing into the same iCloud account derives the same key material independently; they never have to share keys with each other through Apple's servers.

---

## 6. Multi-device sync

Each Mac running PurpleLife has its own data-encryption key (DEK). They are **not** ferried between devices — every Mac generates its own on first launch, and stores it in its own Keychain.

How then does multi-Mac sync work?

- Mac A writes a record. Its DEK is used to encrypt the SQLite payload locally. CloudKit then takes the same record, encrypts it under iCloud's E2E key (separate from PurpleLife's DEK), and pushes to Apple.
- Mac B pulls the record. iCloud's E2E key on Mac B decrypts the CloudKit blob. PurpleLife on Mac B receives the decrypted fields, then encrypts them locally under *its own* DEK before writing to its own SQLite.

The result: same data on both Macs, two different DEKs locally, and Apple has never seen either of them.

Adding a third Mac is "sign into iCloud, install PurpleLife, set a passphrase if you want one." That Mac generates its own DEK, joins iCloud's E2E party automatically, and starts seeing your records.

If you change your passphrase on Mac A, Mac B's passphrase is unaffected — they're independent. The DEK on each Mac is independent. Only iCloud's E2E key (which is at the iCloud-account level, not at the PurpleLife level) is shared, and that's managed by Apple's CloudKit infrastructure, not by us.

---

## 7. Cryptographic primitives (the table for the curious)

| Use | Primitive | Implementation |
|---|---|---|
| Symmetric encryption | AES-256-GCM (96-bit nonce, 128-bit tag) | `CryptoKit.AES.GCM` |
| Key derivation (passphrase → KEK) | PBKDF2-HMAC-SHA256, 300,000 iterations, 16-byte random salt | `CommonCrypto.CCKeyDerivationPBKDF` |
| Random number generation | System CSPRNG | `SecRandomCopyBytes` |
| Hashing (content-addressed attachments) | SHA-256 | `CryptoKit.SHA256` |
| Database encryption | SQLCipher 4.6.1: AES-256-CBC page encryption + HMAC-SHA512 per-page MAC + 256,000 PBKDF2 iterations (KDF unused; raw DEK passed via `x'<hex>'`) | Vendored amalgamation at `Vendor/SQLCipher/`, CommonCrypto backend |

No custom cryptographic constructions. Everything routes through Apple's vetted libraries or — for SQLCipher when it ships — Zetetic's audited build.

---

## 8. Where this lives in the source

| File | Role |
|---|---|
| [`Sources/PurpleLife/Services/Crypto.swift`](../Sources/PurpleLife/Services/Crypto.swift) | AES-GCM seal/open + PBKDF2 + `SecRandomCopyBytes` wrapper |
| [`Sources/PurpleLife/Services/KeyStore.swift`](../Sources/PurpleLife/Services/KeyStore.swift) | DEK lifecycle (generate / wrap with passphrase / unlock / lock / change passphrase / remove passphrase / reset) |
| [`Sources/PurpleLife/Services/KeychainStore.swift`](../Sources/PurpleLife/Services/KeychainStore.swift) | `SecItem`-level Keychain wrapper |
| [`Sources/PurpleLife/Services/EncryptedJSON.swift`](../Sources/PurpleLife/Services/EncryptedJSON.swift) | Magic-header envelope; `safeWrite` downgrade-refusal guard |
| [`Sources/PurpleLife/Models/AppSettings.swift`](../Sources/PurpleLife/Models/AppSettings.swift) | `SettingsStore` encrypted load/save |
| [`Sources/PurpleLife/Services/AttachmentService.swift`](../Sources/PurpleLife/Services/AttachmentService.swift) | Encrypted file-content read/write, launch-time sweep wraps any legacy plaintext attachment |
| [`Sources/PurpleLife/Services/CloudKitSyncService.swift`](../Sources/PurpleLife/Services/CloudKitSyncService.swift) | `encryptedValues["typeJSON"]` and `encryptedValues["fieldsJSON"]` push and pull paths |
| [`Sources/PurpleLife/Services/DatabaseService.swift`](../Sources/PurpleLife/Services/DatabaseService.swift) | SQLite open with `PRAGMA key` via SQLCipher; `migratePlaintextToSQLCipher` runs `sqlcipher_export()` for upgrade installs |
| [`Vendor/SQLCipher/`](../Vendor/SQLCipher/) | Vendored SQLCipher 4.6.1 amalgamation. See `PROVENANCE.md` for tarball SHA-256 + build recipe |
| [`Vendor/GRDB/`](../Vendor/GRDB/) | Locally-patched GRDB 6.29.3. The `Sources/CSQLite/` shim re-exports SQLCipher's sqlite3.h so GRDB's symbol bindings tag against our SQLCipher binary, not `libsqlite3.dylib` |

The test suite (`Tests/PurpleLifeTests/KeyStoreTests.swift`, `AtRestEncryptionTests.swift`) exercises the crypto paths against known-answer round-trips, wrong-key rejection, tamper detection, and the downgrade-refusal invariant.

---

## 9. Verifying the claims

You should be able to audit this without trusting us. Three checks anyone can run:

1. **Verify settings + attachments are encrypted at rest.**
   ```sh
   file ~/Library/Application\ Support/PurpleLife/settings.json
   # → "data" (not "ASCII text" or "JSON data")
   file ~/Library/Application\ Support/PurpleLife/attachments/*.png
   # → "data" (not "PNG image data")
   ```
   The first 5 bytes of every encrypted file are `50 4C 49 46 01` (`PLIF\x01`).

2. **Verify CloudKit can't read your records.** Open Apple's CloudKit dashboard for `iCloud.com.bronty13.PurpleLife`, find a record, inspect the fields. The `fieldsJSON` and `typeJSON` blocks appear as opaque binary — they're inside `encryptedValues` and Apple's dashboard cannot reveal them. The plain fields (`type_id`, timestamps) are visible — that's the metadata we acknowledge above.

3. **Verify the keystore behaves correctly.**
   ```sh
   cat ~/Library/Application\ Support/PurpleLife/keystore.json | python3 -m json.tool
   # → JSON with `salt`, `iterations`, `wrappedDEK` keys
   ```
   The `wrappedDEK` field is base64'd ciphertext. The salt is random per-passphrase. The iterations field reflects the current KDF cost (300000). No plaintext key material is anywhere.

---

## 10. Known limitations (the honest section)

- **The SQLite database is fully encrypted via SQLCipher.** Every page of `purplelife.sqlite` is AES-256-CBC ciphertext with an HMAC-SHA512 page MAC. The FTS5 search index, sync-metadata columns, attachment metadata, and schema all live inside encrypted pages — none of them are reachable from a bare-file inspection without the DEK. See §3a for the SQLCipher integration shape and §3b for the upgrade-from-plaintext migration path.
- **Keychain ACL trust boundary.** A user-level attacker on a running, unlocked Mac can extract the DEK from the Keychain (subject to Keychain ACLs and `kSecAttrAccessibleWhenUnlocked`). FileVault + login password is the primary defence; PurpleLife is defence-in-depth.
- **CloudKit metadata leakage to Apple.** Existence of records, modification timestamps, record-type names. By design — CloudKit needs these to sync. We can't hide them without abandoning CloudKit, and the alternatives (custom server, sync-via-encrypted-blob) cost months for a personal-scale app.
- **No forward secrecy on at-rest data.** A DEK compromise exposes all historic data. Adding per-record key rotation is a meaningful architectural change for marginal real-world benefit at our scale.
- **No biometric gating on the Keychain item.** Plain `kSecAttrAccessibleWhenUnlocked`. Touch ID gating would tighten the security against a casual side-channel attack (locked Mac, attacker swaps user accounts, accesses Keychain as that user); worth doing if a customer's threat model demands it.
- **Memory safety during editing.** Plaintext lives in RAM while a note is open. Standard OS-level protections apply; we don't pin pages or zero memory after decrypt.

---

## 11. Reporting a vulnerability

If you find a security issue in PurpleLife, please report it before disclosing publicly. Two channels:

- Email the developer directly: `robert.olen@gmail.com`. Encrypt the report with the developer's PGP key if you have it, or send a "please share key" email first.
- Open a **private** GitHub security advisory on the [`PhantomLives` repository](https://github.com/bronty13/PhantomLives). Don't file a public issue.

Acknowledgement within 5 business days; substantive triage within 30. We don't run a bug-bounty program (PurpleLife is a personal project), but we appreciate the work and will credit reporters by name in the changelog unless asked not to.

---

## 12. Version & changelog

This whitepaper covers PurpleLife versions where the encryption foundation (slices A1 + A3) is shipped. Earlier versions of the app did not encrypt at rest beyond what FileVault provides.

Each material change to security posture lands as a `CHANGELOG.md` entry and a `HANDOFF.md` decision record, plus an update here. The repository history is the canonical chronology — read the `HANDOFF.md` "Decisions" section from the bottom up if you want the full story of how the current state came to be.

---

*Drafted 2026-05-11. Last reviewed 2026-05-11.*
