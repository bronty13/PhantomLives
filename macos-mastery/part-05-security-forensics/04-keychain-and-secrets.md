---
title: Keychain & Secrets Management
part: P05 Security/Forensics
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 03-code-signing-and-notarization]
tags: [macos, security, keychain, secrets, forensics, icloud, passkeys, cli]
---

# Keychain & Secrets Management

> **In one sentence:** The macOS Keychain is a layered, daemon-mediated secret store whose file-backed and SEP-backed tiers use distinct AES-256-GCM key hierarchies — understanding the architecture lets you store, retrieve, and forensically examine secrets without being bitten by ACL traps or plaintext leaks.

---

## Why this matters

Every macOS process that stores a credential — your SSH client, Git, a CI runner, a signing tool, Safari — touches the Keychain. If you don't understand the tiers, you will occasionally lose secrets (wrong keychain unlocked), leak them (env var pattern), fail code-signing (wrong identity keychain), or waste hours debugging an ACL prompt loop. As a forensics examiner, the Keychain is simultaneously the richest artifact on the machine and the hardest one to decrypt without the login password — knowing exactly what lives where, what metadata is unencrypted, and which tooling can surface it defines your acquisition strategy.

---

## Concepts

### Architecture Overview

The Keychain is not one thing. It is a stack of components:

```
┌────────────────────────────────────────────────────────────┐
│  Passwords.app (macOS 15+)   Keychain Access.app (legacy) │
│  Safari / System Settings    third-party (1Password, BW)  │
└────────────────────┬───────────────────────────────────────┘
                     │ Security.framework (SecItem* API)
                     ▼
              ┌─────────────┐
              │  securityd  │  (user-space daemon, per-session)
              └──────┬──────┘
                     │
       ┌─────────────┼────────────────────┐
       ▼             ▼                    ▼
 File-based   Data-Protection        System
 Keychains    Keychain (Local         Keychain
 (legacy)     Items + iCloud sync)    (/Library)
```

`securityd` is the gatekeeper. Every `SecItem` API call routes through it. It enforces ACLs, manages unlock state, and is responsible for communicating with the Secure Enclave Processor (SEP) for the newer Data Protection tier.

---

### Tier 1 — File-Based Keychains (Legacy, Still Alive)

**Location:**
- `~/Library/Keychains/login.keychain-db` — your personal keychain, auto-unlocked at login
- `/Library/Keychains/System.keychain` — system-wide, readable by root/admin services
- `/Library/Keychains/SystemRoots.keychain` — read-only store of trusted root CAs; not user-editable
- `~/Library/Keychains/<UUID>/keychain-2.db` — the Data Protection keychain (see Tier 2)

The `.keychain-db` files are SQLite databases. You can open them with `sqlite3` but the content columns are AES-256-encrypted blobs — the schema is visible, the payloads are not.

**Login Keychain Encryption Key Derivation:**

```
User login password
      │
      ▼  PBKDF2 (3DES historically; newer items use AES-256-GCM)
  derived key
      │
      ▼
 wraps the keychain master key
      │
      ▼
 per-item encryption key (stored encrypted in the keychain's key table)
      │
      ▼
 item secret (kSecValueData)
```

The critical implication: **the login.keychain-db is as strong as your login password.** If your account uses a short local password for convenience, your keychain secrets are only as safe as that password. On FileVault-protected systems an attacker with the disk still needs to crack the login password; on unencrypted disks (increasingly rare post-T2/M-series) they have even less standing.

The login keychain **auto-unlocks** at login via a private PAM module (`/usr/lib/pam/pam_tid.so` handles Touch ID; the keychain unlock happens via `SecurityAgent`). It **re-locks** if you change your login password without letting the system update the keychain password — the PAM module's derived key no longer matches. This is the infamous "keychain password doesn't match login password" loop.

**Keychain Settings:**

```bash
# Show lock settings for the login keychain
security show-keychain-info ~/Library/Keychains/login.keychain-db

# Set lock-on-sleep + 30-min idle timeout
security set-keychain-settings -l -u -t 1800 \
    ~/Library/Keychains/login.keychain-db
```

> 🪟 **Windows contrast:** DPAPI (Data Protection API) ties secret encryption to the user's Windows password via CryptProtectData/CryptUnprotectData, with machine-key or user-key scope — conceptually similar but implemented as a set of opaque DPAPI blobs in `%APPDATA%\Microsoft\Protect\<SID>\`. There is no global credential store "file" to examine; DPAPI blobs are scattered across many apps' AppData paths. The Windows Credential Manager (accessible via `cmdkey /list`) is the nearest equivalent to the macOS login keychain, but coverage is thinner — most native apps on Windows use DPAPI directly without routing through Credential Manager.

---

### Tier 2 — Data Protection Keychain (Modern, SEP-backed)

Modern SecItem API calls targeting `kSecAttrSynchronizable` or using the newer data-protection classes land in `~/Library/Keychains/<UUID>/keychain-2.db`. This is what the Passwords app, Safari's autofill, and iCloud Keychain use.

**Two-key encryption per item:**

| Key | What it protects | Who holds it |
|-----|-----------------|--------------|
| Metadata key | All attributes except the secret (kSecValueData) — service name, account, creation date, ACL | SEP-protected but **cached** in Application Processor for fast queries |
| Secret key | kSecValueData — the actual password/key/cert | **Never** cached; every read requires a live SEP round-trip |

This is why `security dump-keychain` can show you item metadata (service names, accounts, creation timestamps) even on an offline/locked system if the metadata key was cached, but cannot retrieve the secret value without the SEP in a running, authenticated session.

**Data Protection Classes (mirrors iOS):**

| Class constant | When accessible | Syncs via iCloud |
|---------------|----------------|-----------------|
| `kSecAttrAccessibleWhenUnlocked` | Only while session unlocked | Yes (if `kSecAttrSynchronizable=true`) |
| `kSecAttrAccessibleAfterFirstUnlock` | After first unlock until reboot | Yes |
| `kSecAttrAccessibleAlways` | Always (deprecated; avoid) | Yes |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | Requires passcode; device-local | No |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Unlocked; device-local | No |

The `ThisDeviceOnly` suffix means the key is bound to the local SEP — it **cannot** be migrated in an iTunes/iCloud backup or cross-machine iCloud sync, making it the strongest protection class for secrets that should not leave the device (e.g., private signing keys).

> 🔬 **Forensics note:** The UUID-named directory containing `keychain-2.db` is not predictable — you must enumerate `~/Library/Keychains/` to find it. The directory also contains `Analytics/` subdirectories. The `keychain-2.db` schema has tables `inet` (internet passwords), `genp` (generic passwords), `cert`, `keys`, and `tombstones` (deleted-item records with UUID + timestamp — **metadata survives deletion**). The `tombstones` table is a high-value artifact: it logs when items were added and removed even after deletion, with enough metadata to establish a timeline.

---

### Keychain Item Classes

| Class | SecItemClass | Typical contents | Managed by |
|-------|-------------|-----------------|------------|
| Generic password | `kSecClassGenericPassword` | API tokens, app secrets, CLI credentials | Anything; `security add-generic-password` |
| Internet password | `kSecClassInternetPassword` | Browser logins (URL + account) | Safari, Passwords.app |
| Certificate | `kSecClassCertificate` | DER-encoded X.509 certs | Keychain Access, trust store |
| Key | `kSecClassKey` | RSA/EC private keys, symmetric keys | Code signing, SSH, TLS |
| Identity | `kSecClassIdentity` | (cert, key) pair — logical; stored separately | Code signing |

Code-signing identities (e.g., `Developer ID Application: Acme Corp (XXXXXXXX)`) live in the login or System keychain as a matched cert + key pair. The `codesign` and `security` tools look for them across the entire keychain search list — which is why signing can fail in a CI environment if the keychain is not explicitly added to the search list. See [[03-code-signing-and-notarization]].

---

### ACLs and the "Always Allow" / Prompt Model

Every file-based keychain item has an ACL (Access Control List) consisting of:

1. **Trusted application list** — which app bundles (identified by their signed hash, not just path) may read the item without prompting the user
2. **ACL prompt behavior** — `kSecACLAuthorizationDecrypt` controls whether reading requires user confirmation

When you first store an item via `security add-generic-password`, the calling process (e.g., `/usr/bin/security`) is added to the trusted list. Any other application that tries to read the item gets the "application wants access to keychain" dialog. The user can choose:
- **Allow** (once — prompts again next time)
- **Always Allow** (adds the caller to the trusted list permanently)
- **Deny**

The "always allow" state is persisted in the ACL embedded in the keychain item itself. If you move an item to a different keychain or the app bundle changes identity (re-signed with a different team), the ACL trust breaks.

```bash
# Dump the ACL on an item — shows which apps are trusted and the access operations allowed
security dump-keychain -a ~/Library/Keychains/login.keychain-db | less
# Look for "keychain item ACL" sections listing trusted app paths and their code signatures
```

> 🔬 **Forensics note:** The ACL trusted-app list stores the **code signature hash** of each trusted app, not just its path. This means you can determine which specific binary version was trusted when the item was created — useful for establishing what software was installed and when. A path mismatch (app moved or re-installed) with a matching hash is a normal update pattern; a path match with a hash mismatch can indicate binary replacement.

---

### The Passwords App (macOS 15 Sequoia / macOS 26 Tahoe)

Starting with macOS 15, Apple shipped a first-class **Passwords.app** (`/Applications/Passwords.app`), replacing the credential-management UI that previously lived in System Settings > Passwords and Safari Preferences. **Keychain Access.app** was simultaneously moved from `/System/Applications/Utilities/` to `/System/Library/CoreServices/Applications/Keychain Access.app` — it is still present but no longer in the standard Applications folder.

**Division of labor:**

| Tool | Manages |
|------|---------|
| Passwords.app | Internet passwords, passkeys, verification codes (TOTP), Wi-Fi passwords, synced via iCloud Keychain |
| Keychain Access.app | File-based keychains, certificates, raw keys, secure notes, keychain search list management |
| `security` CLI | Scripting access to both tiers; file-based keychain operations |

The Passwords app does **not** touch `login.keychain-db` for new items — it writes to the Data Protection keychain (`keychain-2.db`). Existing items in `login.keychain-db` remain there; they are not migrated automatically. This dual-source reality means a forensic examiner must check both locations.

**Passkeys / WebAuthn:** Passkeys created in Safari or Passwords.app are stored as `kSecClassKey` items in the Data Protection keychain with `kSecAttrTokenID = kSecAttrTokenIDSecureEnclave` — the private key never leaves the SEP. The public key and RP (relying-party) metadata are visible in `keychain-2.db`'s `keys` table as unencrypted attributes; the private key material is not.

**Verification codes (TOTP):** The TOTP secrets (base32 seeds) for two-factor codes are stored as internet password items in the Data Protection keychain. The Passwords app extracts them, computes the OTP, and displays it — it does not store computed codes. If an examiner needs the TOTP seed, it is in `keychain-2.db` encrypted with the Data Protection key hierarchy (not directly recoverable offline).

---

### The `security` CLI — Complete Reference for Power Users

`/usr/bin/security` is a direct interface to `securityd`. Everything the GUI does, `security` can do from a shell or script.

**Unlock a keychain (necessary in non-login shell contexts, e.g., CI):**

```bash
security unlock-keychain -p "$KEYCHAIN_PASS" ~/Library/Keychains/login.keychain-db
# Or the system keychain (requires sudo):
sudo security unlock-keychain -p "$PASS" /Library/Keychains/System.keychain
```

**Store a secret:**

```bash
# Generic password (-U updates if exists)
security add-generic-password \
    -a "myapp-api-key" \
    -s "com.example.myapp" \
    -w "super-secret-value" \
    -U \
    ~/Library/Keychains/login.keychain-db

# Internet password (with URL metadata)
security add-internet-password \
    -a "robert@example.com" \
    -s "api.example.com" \
    -r "htps" \          # protocol type (4-char code)
    -w "my-password" \
    -U
```

**Retrieve a secret (the -w flag prints only the value, no decoration):**

```bash
secret=$(security find-generic-password \
    -a "myapp-api-key" \
    -s "com.example.myapp" \
    -w 2>/dev/null)

# In a script, export it:
export API_KEY="$(security find-generic-password -a "myapp-api-key" -s "com.example.myapp" -w)"
```

**Show item metadata without the secret:**

```bash
security find-generic-password \
    -a "myapp-api-key" \
    -s "com.example.myapp"
# Prints all attributes; omit -w to get metadata without triggering ACL for the secret
```

**Delete an item:**

```bash
security delete-generic-password \
    -a "myapp-api-key" \
    -s "com.example.myapp"
```

**Dump all metadata (not secrets) from a keychain:**

```bash
security dump-keychain ~/Library/Keychains/login.keychain-db
# Include secrets (triggers ACL prompts for each item):
security dump-keychain -d ~/Library/Keychains/login.keychain-db
```

**List all keychains in the search list:**

```bash
security list-keychains
# Add a keychain to the search list (e.g., for CI signing):
security list-keychains -d user -s \
    ~/Library/Keychains/login.keychain-db \
    /path/to/ci-signing.keychain-db
```

**Find a certificate by name:**

```bash
security find-certificate -c "Developer ID Application" -a ~/Library/Keychains/login.keychain-db
```

**Manage trust for a certificate:**

```bash
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    /path/to/root-ca.pem
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `security dump-keychain -d` triggers an ACL prompt for every item and prints plaintext secrets to stdout. Run only in a secure terminal session; do not redirect to a file on disk. To roll back: no rollback needed, but clear your shell history (`history -c` or delete `~/.zsh_history` entries) if the command included a `-p` password flag.

---

### Storing CLI Secrets Safely — Patterns and Anti-Patterns

| Pattern | Safe? | Notes |
|---------|-------|-------|
| `.env` file in repo | No | Easy git leak; persists in history |
| `export SECRET=...` in shell profile | No | Visible in `env`, inherited by child processes |
| `security add-generic-password` + `$(security find-generic-password -w)` | Yes | ACL-protected; not in env by default; no disk file |
| 1Password CLI (`op read`) | Yes | Additional auth layer (biometric); audit log |
| Secret in environment variable from CI system | Depends | OK if CI system encrypts at rest and masks in logs |
| `echo password | openssl enc ...` in script | No | Password in process list / command history |

**Recommended shell pattern for scripts:**

```bash
#!/usr/bin/env bash
# Retrieves a secret at runtime; not stored in the script or env
API_KEY="$(security find-generic-password \
    -a "deploy-key" \
    -s "com.mycompany.ci" \
    -w 2>/dev/null)"

if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API key not found in keychain. Run:" >&2
    echo "  security add-generic-password -a 'deploy-key' -s 'com.mycompany.ci' -w '<key>'" >&2
    exit 1
fi

# Use the key — it lives only in this variable, never touches disk
curl -H "Authorization: Bearer $API_KEY" https://api.example.com/deploy
```

**The `-T` ACL gotcha:** When you add an item with `security`, `/usr/bin/security` is automatically trusted. If you want to allow another binary to read it without prompting:

```bash
security add-generic-password \
    -a "myapp-key" \
    -s "com.example.myapp" \
    -w "secret" \
    -T /usr/bin/security \        # security tool itself
    -T /usr/local/bin/myapp       # your app binary
```

Any binary in the `-T` list can read this item without prompting the user. Be conservative — adding `/bin/bash` effectively makes the item readable by any shell script.

---

### iCloud Keychain Sync

Items marked `kSecAttrSynchronizable = kCFBooleanTrue` sync via iCloud Keychain using end-to-end encryption. The sync protocol uses an iCloud Keychain service key derived from a combination of:

1. The user's iCloud account credentials
2. A device-enrollment public key generated during iCloud Keychain setup
3. A "circle of trust" model where each device must be approved to join

The sync transport is encrypted; Apple states they cannot read synced keychain items. Items in the Data Protection keychain at `keychain-2.db` include a sync flag; you can examine it in the SQLite schema's `sync` column.

**Practical implications for forensics:** If you have a suspect's Apple ID credentials and a trusted device, you can enroll a new device and receive a copy of the iCloud Keychain. Without those credentials, the encrypted keychain sync data in Apple's infrastructure is not accessible — the end-to-end encryption is genuine.

> 🔬 **Forensics note:** The `~/Library/Keychains/` directory also contains a `ocspcache.sqlite3` (OCSP response cache) and `TrustStore.sqlite3` (custom trust anchors). Both are useful artifacts: `ocspcache.sqlite3` reveals which TLS certificates the user's system recently validated, effectively a partial browsing/connection history for HTTPS-using apps.

---

### Code-Signing Identities in the Keychain

When you install a Developer ID certificate from Apple, it lands as a `(certificate, private key)` identity in your login keychain (or the System keychain if installed system-wide). Tools like `codesign` and `productsign` look for these via the SecIdentity API.

```bash
# List signing identities the current user can use
security find-identity -v -p codesigning

# Output example:
# 1) A1B2C3... "Developer ID Application: Acme Corp (XXXXXXXX)"
# 2) D4E5F6... "Apple Development: robert@example.com (YYYYYYYY)"
#    2 valid identities found
```

In a CI pipeline, signing fails if the keychain is locked or not in the search list. The standard pattern:

```bash
# Unlock and add to search list; set very long timeout so it doesn't re-lock mid-build
security create-keychain -p "$KEYCHAIN_PASS" ci-signing.keychain-db
security set-keychain-settings -lut 21600 ci-signing.keychain-db
security unlock-keychain -p "$KEYCHAIN_PASS" ci-signing.keychain-db
# Import cert + key from p12
security import signing.p12 \
    -k ci-signing.keychain-db \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
security list-keychains -d user -s \
    ci-signing.keychain-db \
    ~/Library/Keychains/login.keychain-db
```

Cross-reference: [[03-code-signing-and-notarization]] covers the full signing pipeline.

---

### Third-Party Secret Managers

**1Password:**
- Stores secrets in encrypted `.1pux` vaults, optionally synced via iCloud or 1Password cloud
- `op` CLI (`brew install 1password-cli`) provides `op read`, `op inject`, `op run`
- `op read "op://vault/item/field"` retrieves a single field; integrates with shell scripts and CI
- `op run --env-file=.env.tpl -- ./deploy.sh` injects secrets as environment variables into a subprocess without writing them to disk
- 1Password can serve as an SSH agent (`eval $(op ssh-agent)`) — SSH keys live in the vault, unlocked per-session

**Bitwarden:**
- `bw` CLI (`brew install bitwarden-cli`)
- Session key model: `export BW_SESSION=$(bw unlock --raw)`; session key cached in env, not keychain by default
- `bw get password "item name"` retrieves a field
- For scripts, pipe `bw get` into your command rather than storing in a variable that persists

**Comparison:**

| Tool | CLI | vault sync | macOS Keychain integration | Passkeys |
|------|-----|-----------|---------------------------|---------|
| macOS Keychain | `security` | iCloud (optional) | Native | Yes (SEP-backed) |
| 1Password | `op` | 1P cloud or local | Can store macOS keychain items | Yes |
| Bitwarden | `bw` | Bitwarden cloud or self-host | Separate store | Partial |

---

### Forensics Deep Dive

#### What you can get without the password

- Item **metadata**: service name, account name, creation date, modification date, ACL trusted-app list with code signature hashes, data class, sync flag — all from `keychain-2.db` or `dump-keychain` without decrypting secrets
- `tombstones` table: records of deleted items (UUIDs, timestamps, partial attributes)
- OCSP cache: recent certificate validations
- `TrustStore.sqlite3`: custom trust anchors added by the user (VPN software, MDM profiles, or attacker-installed root CAs)
- Keychain search-list settings: which keychains are in the default search order

#### What you need the login password for

- Secret values (`kSecValueData`) in file-based keychains — requires either the login password or a master key from a memory dump
- Secret values in the Data Protection keychain — requires a running authenticated session (SEP must be present and unlocked)

#### Chainbreaker — Offline Keychain Extraction

[chainbreaker](https://github.com/n0fate/chainbreaker) (n0fate, with forks from gremwell and rixvet for newer macOS) is the standard academic/forensics tool for offline keychain extraction from file-based `.keychain-db` files:

```bash
pip3 install chainbreaker
# With login password:
chainbreaker --password "loginpassword" \
    ~/Library/Keychains/login.keychain-db

# Extract hashcat-compatible hash for offline cracking:
chainbreaker --dump-hash \
    ~/Library/Keychains/login.keychain-db
# Then:
hashcat -m 23100 keychain.hash wordlist.txt
```

**Chainbreaker support caveat:** The tool was originally built for macOS through Catalina/Mojave. Newer macOS versions (Big Sur+) changed internal structures. Forks (gremwell, rixvet) have varying levels of post-Catalina support. Verify the fork's tested macOS version against your target. The Data Protection keychain (`keychain-2.db`) requires a running SEP — chainbreaker cannot decrypt it offline because the secret key never leaves the Secure Enclave on Apple Silicon.

> 🔬 **Forensics note:** On Intel + T2 Macs (pre-M1), the Secure Enclave is on the T2 coprocessor. The T2 is cryptographically bonded to the main CPU — even physical chip-off of the T2 SSD storage does not bypass the T2's encryption. For forensic acquisition, the practical path remains: obtain login password, use it to unlock the keychain in a live session. On Apple Silicon, the SEP is integrated in the M-series die — the security posture is equivalent or stronger.

**Memory artifacts:** In a live acquisition or memory dump, the keychain master key may be present in `securityd`'s heap — this is the basis for volatility/volafox-based keychain extraction. The metadata key is explicitly documented by Apple as being cached in the Application Processor, making it potentially recoverable from RAM.

---

## Hands-on (CLI & GUI)

### Explore your keychains

```bash
# See all keychains on your search list
security list-keychains

# Typical output on a standard install:
#   "/Users/bronty13/Library/Keychains/login.keychain-db"
#   "/Library/Keychains/System.keychain"

# Show lock settings
security show-keychain-info ~/Library/Keychains/login.keychain-db

# Count items by class (raw SQLite — schema is visible, values are encrypted)
sqlite3 ~/Library/Keychains/login.keychain-db \
    "SELECT COUNT(*) FROM genp; SELECT COUNT(*) FROM inet;"

# Explore the Data Protection keychain
ls ~/Library/Keychains/
# Find the UUID directory:
ls ~/Library/Keychains/*/keychain-2.db

sqlite3 ~/Library/Keychains/*/keychain-2.db \
    ".tables"
# Tables: cert, genp, inet, keys, tombstones, outgoing_messages, ...

sqlite3 ~/Library/Keychains/*/keychain-2.db \
    "SELECT agrp, acct, svce, cdat, mdat FROM genp LIMIT 20;"
# agrp = access group, acct = account, svce = service, cdat/mdat = dates
```

### Inspect certificates

```bash
# Open Keychain Access at the specific path (macOS 15+)
open /System/Library/CoreServices/Applications/Keychain\ Access.app

# List all certificates in login keychain
security find-certificate -a -p ~/Library/Keychains/login.keychain-db | \
    openssl crl2pkcs7 -nocrl -certfile /dev/stdin | \
    openssl pkcs7 -print_certs -text -noout 2>/dev/null | \
    grep "Subject:"

# Find signing identities
security find-identity -v -p codesigning
```

---

## Labs

### Lab 1 — Store, Retrieve, and Delete a Secret

> ⚠️ This lab modifies your login keychain. The changes are easily reversed with the delete command below. No backup required for this lab — it writes only test data.

```bash
# Step 1: Add a test generic password
security add-generic-password \
    -a "lab-test-account" \
    -s "com.macos-mastery.lab-04" \
    -w "my-lab-secret-$(date +%s)" \
    -j "Added by macOS Mastery Lab 04" \
    ~/Library/Keychains/login.keychain-db

# Step 2: Verify it was stored (metadata only, no secret)
security find-generic-password \
    -a "lab-test-account" \
    -s "com.macos-mastery.lab-04"
# Expected: prints attributes including "acct", "svce", "desc"

# Step 3: Retrieve just the secret value
secret=$(security find-generic-password \
    -a "lab-test-account" \
    -s "com.macos-mastery.lab-04" \
    -w)
echo "Retrieved: $secret"
# Expected: prints "Retrieved: my-lab-secret-<timestamp>"
# macOS will prompt for keychain access on first retrieval (Allow / Always Allow)

# Step 4: Check what metadata is visible in SQLite without decryption
sqlite3 ~/Library/Keychains/login.keychain-db \
    "SELECT rowid, acct, svce, cdat, mdat FROM genp WHERE svce = 'com.macos-mastery.lab-04';"

# Step 5: Clean up
security delete-generic-password \
    -a "lab-test-account" \
    -s "com.macos-mastery.lab-04"
echo "Deleted. Exit code: $?"
```

**What to observe:** The SQLite query (Step 4) returns account and service names in plaintext — these are metadata-key-protected columns, and in a live session they are accessible. The `cdat` and `mdat` values are epoch timestamps. This demonstrates what a forensic examiner sees in a metadata-only extraction.

---

### Lab 2 — Inspect ACLs on a Keychain Item

> ⚠️ Read-only lab. No changes to your keychain.

```bash
# Step 1: Dump all items with ACL information
security dump-keychain -a ~/Library/Keychains/login.keychain-db 2>/dev/null | \
    grep -A 20 "keychain item ACL" | head -80
# Look for "Trusted Applications:" blocks and the code hash after each app path

# Step 2: Find a specific item's ACL
security dump-keychain -a ~/Library/Keychains/login.keychain-db 2>/dev/null | \
    grep -B 5 -A 25 "acct.*<blob>=.*bronty13"
# Replace "bronty13" with your username to find your items
```

**What to observe:** The `Trusted Applications` list shows each trusted binary's path plus a `<data>` hash block. Applications you granted "Always Allow" appear here. A new signing certificate or a moved binary will not match this hash — triggering the prompt again.

---

### Lab 3 — Use a Keychain Secret in a Script (CI-Safe Pattern)

This lab creates a complete, production-style pattern for scripted secret access.

> ⚠️ Writes a test item to your keychain; cleaned up at the end of the lab.

```bash
# Step 1: Store the "API token" once (do this interactively, not in the script)
security add-generic-password \
    -a "lab-api-token" \
    -s "com.macos-mastery.lab-deploy" \
    -w "tok_test_1234567890abcdef" \
    -T /usr/bin/security \
    -U

# Step 2: Create the script that uses it
cat > /tmp/lab-deploy.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

TOKEN="$(security find-generic-password \
    -a "lab-api-token" \
    -s "com.macos-mastery.lab-deploy" \
    -w 2>/dev/null)" || {
    echo "ERROR: token not found in keychain" >&2
    exit 1
}

# Simulate using the token (replace with real API call)
echo "Would POST to API with token: ${TOKEN:0:8}... (truncated for safety)"
# TOKEN is never written to disk or exported to child env
SCRIPT

chmod +x /tmp/lab-deploy.sh

# Step 3: Run it
/tmp/lab-deploy.sh
# Expected: prints "Would POST to API with token: tok_test... (truncated for safety)"
# No ACL prompt because -T /usr/bin/security was set in Step 1

# Step 4: Verify the token is NOT in the environment
env | grep -i token || echo "Good: TOKEN not in environment"

# Step 5: Clean up
security delete-generic-password \
    -a "lab-api-token" \
    -s "com.macos-mastery.lab-deploy"
rm /tmp/lab-deploy.sh
```

---

### Lab 4 — Forensic Metadata Extraction (Tombstones)

> ⚠️ Read-only. Queries your existing keychain databases.

```bash
# Step 1: Add an item then delete it to create a tombstone
security add-generic-password \
    -a "tombstone-test" \
    -s "com.macos-mastery.lab-tombstone" \
    -w "ephemeral-secret"

security delete-generic-password \
    -a "tombstone-test" \
    -s "com.macos-mastery.lab-tombstone"

# Step 2: Check for tombstones in the Data Protection keychain
# The login.keychain-db does NOT have tombstones; check keychain-2.db
sqlite3 ~/Library/Keychains/*/keychain-2.db \
    "SELECT rowid, grp, acct, svce, tomb, mdat FROM tombstones ORDER BY mdat DESC LIMIT 10;"

# Step 3: Count total tombstones (shows history of credential turnover)
sqlite3 ~/Library/Keychains/*/keychain-2.db \
    "SELECT COUNT(*) FROM tombstones;"
```

**What to observe:** Deleted items leave a tombstone with their access group, account, service, and deletion timestamp. This is a key forensic artifact — it can show deleted credentials (VPN configs, mail accounts, browser logins) long after the user thought they had removed them.

---

## Pitfalls & Gotchas

**Login password ≠ keychain password:** If you change your login password without following the system's prompts to update the keychain, the login keychain remains locked at next login. Fix: `security unlock-keychain -p "OLD_PASS" ~/Library/Keychains/login.keychain-db` then `security set-keychain-password` to set a new one.

**Keychain Access.app location changed in macOS 15:** Scripts or documentation pointing to `/System/Applications/Utilities/Keychain Access.app` will fail. The new path is `/System/Library/CoreServices/Applications/Keychain Access.app`. `open -a "Keychain Access"` still works (Launch Services finds it).

**`security dump-keychain -d` requires ACL approval for every item:** On a keychain with 500 items, this means 500 prompts unless you choose "Always Allow" — which then trusts every future `security` invocation permanently. Set up isolated keychains for sensitive items.

**CI/CD: keychain times out mid-build:** `set-keychain-settings -lut 21600` sets a 6-hour unlock timeout. The default is 5 minutes, which expires on long builds.

**`-T` trust list accepts any binary — be cautious:** Adding `/bin/bash` or `/usr/bin/env` to the trusted list effectively grants any shell script access to the item without prompting. This is a common mistake in CI setup scripts.

**Data Protection keychain is not accessible offline:** If you are building forensics tooling expecting to dump all secrets from `keychain-2.db` on an imaged disk, you will be disappointed — the secret key always requires a live SEP round-trip. Plan your acquisition strategy around live acquisition or login-password-based online access.

**Passware / chainbreaker version compatibility:** Both tools have incomplete support for macOS 11+ (Apple Silicon / unified kernel) file-based keychains. Test your specific tooling against known-good samples from the macOS version you are analyzing before drawing conclusions in a real examination.

**Git history leaks:** `security` invocations with `-p` (keychain password) or `-w` (item value) in a shell script committed to git expose those values in history forever. Use environment variables, read from stdin, or use `op inject`.

---

## Key Takeaways

- The Keychain has two distinct tiers: legacy file-based (`.keychain-db`, SQLite, password-derived key) and modern Data Protection (`keychain-2.db`, SEP-backed, class keys). They behave differently for scripting and forensics.
- `securityd` mediates all access; it enforces ACLs per item and communicates with the SEP for Data Protection items.
- Item metadata (service name, account, creation date, ACL trust list, code signature hashes) is accessible without the secret-key hierarchy — a rich forensic source even without the login password.
- The `tombstones` table in `keychain-2.db` retains records of deleted items with timestamps — treat it as a credential-activity timeline.
- `security find-generic-password -w` is the correct pattern for scripted secret retrieval; never embed secrets in files, env exports in profiles, or command-line arguments.
- `security add-generic-password -T /path/to/binary` controls which binaries can read an item without prompting; be conservative with this.
- Passkeys live in the Data Protection keychain with `kSecAttrTokenIDSecureEnclave`; the private key is permanently SEP-bound and cannot be exported.
- For forensics, the login password is the master key to file-based keychains; the SEP must be present and authenticated for Data Protection secrets. Memory-resident master keys are the only offline alternative.

---

## Terms Introduced

| Term | Definition |
|------|-----------|
| `securityd` | User-space daemon mediating all SecItem API calls and ACL enforcement |
| `login.keychain-db` | File-based personal keychain, unlocked at login; SQLite database |
| `keychain-2.db` | Data Protection keychain; SEP-backed; used by Passwords.app and modern APIs |
| Data Protection class | Access policy for a keychain item (when accessible, whether device-local) |
| ACL (Keychain) | Per-item list of trusted app bundles (by code signature hash) that may read it |
| Metadata key | AES-256 key protecting item attributes; SEP-protected but AP-cached |
| Secret key | AES-256 key protecting `kSecValueData`; never leaves SEP |
| Tombstone | Record of a deleted keychain item retained in `keychain-2.db` |
| `kSecAttrSynchronizable` | Flag marking an item for iCloud Keychain sync |
| Passkey | WebAuthn credential stored as a SEP-bound EC key; replaces password |
| TOTP seed | Base32 secret stored as an internet password item; Passwords.app derives the OTP |
| chainbreaker | Forensics tool for offline extraction from file-based `.keychain-db` files |
| DPAPI | Windows Data Protection API — Windows equivalent of macOS keychain encryption |

---

## Further Reading

- [Apple Platform Security — Keychain data protection](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web)
- [Howard Oakley — Does Sequoia's Password app change keychains?](https://eclecticlight.co/2024/06/19/does-sequoias-password-app-change-keychains/) — Howard's analysis of what changed and what didn't in macOS 15
- [n0fate/chainbreaker](https://github.com/n0fate/chainbreaker) — canonical forensics tool for offline keychain extraction
- [gremwell/chainbreaker](https://github.com/gremwell/chainbreaker) — fork with updated macOS support
- [Passware — Deep Dive into Apple Keychain Decryption](https://www.forensicfocus.com/articles/a-deep-dive-into-apple-keychain-decryption/) — commercial forensics perspective on key hierarchy and cracking strategies
- [scripting-osx.com — Get Password from Keychain in Shell Scripts](https://scriptingosx.com/2021/04/get-password-from-keychain-in-shell-scripts/) — practical scripting patterns
- `man security` — the authoritative flag reference for all `security` subcommands
- [[01-boot-process]] — where `securityd` starts in the boot sequence
- [[03-code-signing-and-notarization]] — signing identities in the keychain and CI setup
