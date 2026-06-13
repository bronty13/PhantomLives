---
title: Code signing & provisioning
part: P07 Development
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 08-security-architecture, 04-keychain-and-secrets, 00-xcode-demystified]
tags: [macos, code-signing, gatekeeper, developer-id, notarization, entitlements, hardened-runtime, codesign, spctl, security]
---

# Code signing & provisioning

> **In one sentence:** Code signing is macOS's cryptographic chain-of-custody system — every executable carries a tamper-evident seal that lets the kernel, Gatekeeper, TCC, and other subsystems each independently verify *who* made it and *that it hasn't changed*, without contacting a server at runtime.

## Why this matters

If you ship macOS apps — and if you are working in the PhantomLives repo you already do — code signing is not optional ceremony. It is the technical mechanism behind all of these things happening on your machine right now:

- The kernel refusing to execute unsigned pages on Apple Silicon (ARM requires a valid signature even for ad-hoc local builds — no signature = no exec)
- Gatekeeper quarantine-checking every downloaded file on first open
- TCC tracking which app was granted Full Disk Access (it tracks the signed identity, not the path)
- Keychain ACLs recognizing "the same app" across updates via the Designated Requirement
- Sparkle / notarization / stapling letting your apps auto-update without a new user approval dialog

The subsystems that consume signatures span the OS. Understanding the mechanism — not just the incantation — lets you debug failures, reason about security boundaries, and build release pipelines that don't silently ship stale or unsigned binaries.

> 🪟 **Windows contrast:** Windows uses Authenticode, which signs a PE binary with a CMS/PKCS#7 blob and optionally timestamps it with an RFC 3161 counter-signature. The chain of trust runs through commercial CAs (DigiCert, Sectigo, etc.) not through the OS vendor. Defender SmartScreen assigns reputation to the signing certificate's key, which means a newly-generated certificate starts with zero reputation regardless of CA. macOS's model is: Apple is the *only* trust anchor — there is no equivalent of buying a cert from DigiCert; you must join the Apple Developer Program. The payoff is that Apple-issued Developer ID certificates carry implicit reputation from day one.

---

## Concepts

### 1. The signing identity: certificate + private key

A "signing identity" is the pair that lives in your login Keychain:

```
Private key  ──────────────────────────────────────────────────┐
Certificate  (your public key + your name/team ID, signed by   │
             an Apple intermediate CA)                         ├─ identity
                   │                                           │
     Apple Worldwide Developer Relations CA (intermediate)    │
                   │                                           │
     Apple Root CA (self-signed, pre-installed in Trust Store)─┘
```

The certificate is a credential; the private key is the secret. Together they let `codesign` compute an ECDSA (or RSA, for older certs) signature over the code. The recipient only needs the public portion (embedded in the signature) plus the pre-installed Apple root to verify the entire chain.

**Certificate types you will actually use for macOS:**

| Certificate | Issued by Portal | Used for | Gatekeeper passes? |
|---|---|---|---|
| Apple Development | Yes | local dev/debug builds | No |
| Apple Distribution | Yes | TestFlight / App Store | No (MAS path only) |
| Developer ID Application | Yes | direct distribution, DMG, ZIP | **Yes** |
| Developer ID Installer | Yes | `.pkg` installers | Yes |
| 3rd Party Mac Developer Application | Yes | App Store submission | No (validates in Store) |

**Developer ID Application** is the one that matters for PhantomLives releases. It is tied to your Team ID (e.g. `SRKV8T38CD`). You get it from the Apple Developer Portal → Certificates, Identifiers & Profiles. Without this cert, your shipped app gets the Gatekeeper quarantine dialog that tells the user Apple cannot verify the developer.

List identities on your current machine:

```bash
security find-identity -v -p codesigning
```

Expected output:

```
  1) A3B2C1... "Developer ID Application: Robert Olen (SRKV8T38CD)"
  2) D4E5F6... "Apple Development: robert@example.com (SRKV8T38CD)"
     2 valid identities found
```

If it says `0 valid identities found`, your cert or private key is missing from the Keychain. Certs without matching private keys are useless.

> 🔬 **Forensics note:** Keychain items representing signing identities live at `~/Library/Keychains/login.keychain-db` (user login Keychain) and `/Library/Keychains/System.keychain` (system-level). The private key item class is `kSecClassKey`; the certificate is `kSecClassCertificate`. An investigator can enumerate all signing identities on a machine with `security find-identity -p codesigning /Library/Keychains/System.keychain` plus the user login Keychain. The presence of a Developer ID private key is itself meaningful evidence of a registered developer account.

---

### 2. What `codesign` actually embeds

When you sign an `.app` bundle, `codesign` modifies the main Mach-O executable by appending a superblob (a length-prefixed container) via the **`LC_CODE_SIGNATURE`** load command. Inside that superblob are several slots:

```
SuperBlob
├── CodeDirectory (slot 0)
│   ├── signing identifier  (CFBundleIdentifier or explicit -i flag)
│   ├── team identifier     (your 10-char Team ID, e.g. SRKV8T38CD)
│   ├── flags               (e.g. 0x10000 = hardened runtime)
│   ├── code slots          (SHA-256 hash of each 4096-byte code page)
│   └── special slots       (hash of Info.plist, CodeResources, entitlements, ...)
├── Entitlements (slot -5, DER-encoded since macOS 12.3+)
├── Entitlements (XML plist, slot -7, kept for compatibility)
├── Requirements (slot -2, compiled requirement language bytecode)
│   └── Designated Requirement (DR)
└── CMS Signature
    ├── ECDSA signature over CodeDirectory
    ├── Signing certificate chain
    └── RFC 3161 counter-signature (secure timestamp from Apple's TSA)
```

**cdhash:** The SHA-256 hash of the CodeDirectory blob itself. This 32-byte value is the compact, unique identity of *this exact build* of *this exact binary*. The OS uses cdhashes in the process table, in TCC decisions, and in Keychain ACL matching. When you re-sign a binary without changing any code, the cdhash changes because the timestamp changes.

**CodeResources:** For `.app` bundles (not bare Mach-O), `codesign` also generates `Contents/_CodeSignature/CodeResources` — a plist (version 2 since Mavericks) that contains a SHA-256 digest of every file in the bundle that is not the main executable (frameworks, nibs, resources, Info.plist, nested helpers). Rules in CodeResources specify which paths are sealed, which are excluded, and which are optional. Any file added, removed, or modified after signing invalidates the seal.

```bash
# Inspect the CodeResources manifest
plutil -p MyApp.app/Contents/_CodeSignature/CodeResources | head -60
```

**Entitlements:** A plist of capability grants. At runtime, the kernel and various daemons check the entitlements embedded in the running process's code signature before allowing certain operations. The `codesign` tool compiles them into the signature. Examples:

```xml
<!-- hardened runtime exception: allow JIT compilation -->
<key>com.apple.security.cs.allow-jit</key><true/>

<!-- allow loading unsigned plugins (broad; avoid if possible) -->
<key>com.apple.security.cs.disable-library-validation</key><true/>

<!-- Sandbox: disable it (needed for most CLI helpers and direct-dist apps) -->
<key>com.apple.security.app-sandbox</key><false/>

<!-- allow outgoing network connections (sandboxed apps) -->
<key>com.apple.security.network.client</key><true/>

<!-- Full Disk Access (requires user approval via TCC) -->
<key>com.apple.security.files.all</key><true/>
```

The `com.apple.security.*` namespace is Apple-controlled. Third-party entitlements exist too (e.g. `com.apple.developer.icloud-container-identifiers`) and require Apple provisioning approval for App Store distribution.

**Designated Requirement (DR):** A compiled predicate in Apple's Code Requirements Language that defines the identity test a verifier uses to recognize "the same" app across updates. Example DR for a Developer ID app:

```
identifier "com.example.MyApp"
  and certificate leaf[subject.O] = "Robert Olen"
  and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
  and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
  and anchor apple generic
```

Translation: the signing identifier must match, the leaf cert must belong to the named developer, specific OID fields prove it's a Developer ID certificate, and the chain must root at Apple. The Keychain and other subsystems use the DR to re-recognize the app at next launch without storing a path.

---

### 3. Signing contexts: ad-hoc, Developer ID, App Store

**Ad-hoc signing** (`-s -`): No certificate. `codesign` creates a valid signature structure but the "signer" field is empty. Required for all binaries on Apple Silicon (the kernel mandates a signature for any executable, even locally-built developer code). Ad-hoc-signed code:
- Passes kernel integrity checks
- Fails Gatekeeper
- Cannot be notarized
- TCC does not track it by identity (it falls back to path)

**Developer ID signing:** Uses your `Developer ID Application` cert, enables the hardened runtime, carries a secure timestamp, and can be submitted to Apple for notarization. This is the signing mode for all PhantomLives app releases. Gatekeeper's source check passes: `source=Developer ID`.

**App Store signing:** Uses `3rd Party Mac Developer Application` and a provisioning profile. The resulting binary is not Gatekeeper-valid for direct distribution — it only passes through the App Store's own delivery path where Apple re-signs with its own key. The App Store model mandates the App Sandbox (`com.apple.security.app-sandbox = true`), which is why most PhantomLives tools cannot ship through the App Store without significant capability restrictions.

---

### 4. The hardened runtime

Enabled with `--options runtime` (or `-o runtime`). It activates a set of kernel-enforced restrictions on the process at launch:

| Protection | Default (hardened) | Bypass entitlement |
|---|---|---|
| No code injection via `DYLD_INSERT_LIBRARIES` | Blocked | `cs.allow-dyld-environment-variables` |
| No unsigned dynamic libraries loaded | Blocked | `cs.disable-library-validation` |
| No JIT compilation (`MAP_JWX`) | Blocked | `cs.allow-jit` |
| No `task_for_pid` on self from unsigned debugger | Blocked | `cs.debugger` |
| No ptrace attach from unsigned code | Blocked | `cs.debugger` |
| No Apple Events to other apps without prompt | Restricted | (TCC dialog, not an entitlement bypass) |

**Notarization requires hardened runtime.** Apple's notarization service rejects submissions that lack it. This is why the PhantomLives release scripts always pass `-o runtime`.

> 🔬 **Forensics note:** A process running without the hardened runtime is a significant indicator. Check with `codesign -dvvv /path/to/binary | grep flags` — the flags field `0x10000` means hardened runtime is set. A flags value that lacks `0x10000` on a Developer ID-signed binary is either old (pre-2019) or suspicious. Malware frequently uses ad-hoc signing + no hardened runtime to permit code injection.

---

### 5. Provisioning profiles on macOS

Provisioning profiles are the iOS/tvOS mechanism Apple ported to Mac. On macOS they are mostly used for:

1. **Mac App Store distribution** — every MAS app embeds a `Contents/embedded.provisionprofile`
2. **Push notifications** — `com.apple.developer.aps-environment` requires a profile
3. **iCloud containers, Sign in with Apple, CloudKit** — all require Apple-provisioned entitlements embedded in a profile

For **direct distribution (Developer ID)**, you do *not* need a provisioning profile for most capabilities. The PhantomLives apps do not embed provisioning profiles. If you add a capability that *does* require one (e.g. iCloud), you create a profile in the portal, download the `.provisionprofile`, and add it to the build.

A provisioning profile is itself a CMS-signed blob. To inspect one:

```bash
security cms -D -i MyApp.app/Contents/embedded.provisionprofile | plutil -convert xml1 -o - -
```

Key fields inside:
- `AppIDName`, `ApplicationIdentifierPrefix` (Team ID)
- `Entitlements` — the superset of entitlements the profile permits
- `ExpirationDate` — profiles expire; expired = launch blocked
- `DeveloperCertificates` — the public certs whose private keys are authorized to sign

---

### 6. The Gatekeeper and spctl evaluation chain

When a user opens a quarantined app (downloaded from the internet, AirDrop, etc.), macOS executes this assessment:

```
1. Check com.apple.quarantine xattr — if absent, skip Gatekeeper
2. Evaluate codesign validity (codesign --verify)
3. Check spctl assessment policy:
   - Is it from the Mac App Store?  → allow
   - Is it Developer ID-signed with valid chain?  → allow
   - Is it notarized (stapled ticket OR online check)?  → bonus trust
   - None of the above?  → block / warn
4. Gatekeeper records the assessment result; second-open skips re-check
   (com.apple.quarantine xattr is cleared on pass)
```

Since macOS 15 Sequoia, **Apple closed the Finder bypass** (right-click → Open → Open Anyway from Finder) for unnotarized apps. The override now lives in System Settings → Privacy & Security → allow the specific app. This makes notarization effectively mandatory for user-facing distribution as of macOS 26.

> 🔬 **Forensics note:** The quarantine xattr is `com.apple.quarantine` with value like `0083;67a12bc4;Safari;uuid`. Field 0 is flags (0083 = quarantined + downloaded), field 1 is the download timestamp (hex Unix epoch), field 2 is the LSQuarantineAgentName (which app downloaded it), field 3 is a UUID correlated with entries in `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` — a SQLite database logging every quarantine event including the originating URL. This database is a gold mine for download history forensics even after the app has been opened and cleared.

---

### 7. Inspecting a signature

**Verify and display:**

```bash
codesign -dvvv MyApp.app
```

Key output lines:

```
Identifier=com.example.MyApp
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=45+7 location=embedded
Signature size=9012
Authority=Developer ID Application: Robert Olen (SRKV8T38CD)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=Jun 13, 2026 at 09:00:00
TeamIdentifier=SRKV8T38CD
Sealed Resources version=2 rules=13 files=89
Internal requirements count=1 size=200
```

`flags=0x10000(runtime)` → hardened runtime ON. `Timestamp=` → secure RFC 3161 timestamp embedded (if you see "none" here, the binary was signed with `--no-timestamp` or offline — this also means the signature becomes invalid when the cert expires rather than being frozen-in-time valid).

**Dump entitlements:**

```bash
codesign -d --entitlements - MyApp.app
```

Output is a binary plist. Pipe through plutil:

```bash
codesign -d --entitlements - MyApp.app 2>/dev/null | plutil -convert xml1 -o - -
```

**Dump the Designated Requirement:**

```bash
codesign -d -r - MyApp.app
```

Output:

```
designated => identifier "com.example.MyApp"
   and anchor apple generic
   and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
   and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
   and certificate leaf[subject.O] = "Robert Olen"
```

**Assess via Gatekeeper policy (spctl):**

```bash
spctl -a -vvv MyApp.app
```

Expected for a good Developer ID binary:

```
MyApp.app: accepted
source=Developer ID
origin=Developer ID Application: Robert Olen (SRKV8T38CD)
```

If it shows `rejected` or `CSSMERR_TP_CERT_REVOKED`, the cert chain is bad. If it shows `source=no usable signature`, the binary is ad-hoc or unsigned from spctl's perspective.

**Verify individual Mach-O binaries** (frameworks, helpers, CLI tools inside the bundle):

```bash
codesign --verify --deep --strict MyApp.app
```

`--deep` walks nested code. `--strict` applies stricter rules (e.g. sealed resources must be version 2). A clean bundle produces no output and exits 0.

---

### 8. The PhantomLives release signing flow

Looking at the pattern across PhantomLives build scripts, a complete release signing sequence looks like:

```bash
# 1. Sign all nested helpers and frameworks first (inside-out)
codesign --force --options runtime \
         --entitlements MyApp.entitlements \
         --sign "Developer ID Application: Robert Olen (SRKV8T38CD)" \
         --timestamp \
         MyApp.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/org.sparkle-project.Downloader.xpc

# 2. Sign the app bundle last (outside-in would be wrong — the bundle seal
#    covers nested signatures, so they must exist first)
codesign --force --options runtime \
         --entitlements MyApp.entitlements \
         --sign "Developer ID Application: Robert Olen (SRKV8T38CD)" \
         --timestamp \
         MyApp.app

# 3. Verify
codesign --verify --deep --strict MyApp.app && echo "Signature OK"
spctl -a -vvv MyApp.app
```

The `--timestamp` flag contacts Apple's Time Stamping Authority (`timestamp.apple.com`) to embed an RFC 3161 counter-signature. This "freezes" the signature in time: even after the cert expires, the embedded timestamp proves it was valid at signing time, so the signature remains acceptable indefinitely. **Always use `--timestamp` for release builds.**

> ⚠️ **ADVANCED:** Signing without `--timestamp` for release binaries means the signature validity window is exactly the certificate's validity period (~5 years for Developer ID). After the cert expires, the signature is invalid for Gatekeeper even if the binary itself is unchanged. Notarized stapled tickets carry their own timestamp and provide an additional validity anchor, but the signature timestamp is still the authoritative one.

---

### 9. Re-signing and stripping signatures

Sometimes you need to re-sign a binary you did not build — a vendored CLI tool, a bundled helper, a modified copy of a framework:

```bash
# Strip existing signature and re-sign
codesign --force --sign "Developer ID Application: Robert Olen (SRKV8T38CD)" \
         --options runtime --timestamp \
         path/to/binary
```

`--force` is required when a signature already exists. Without it, `codesign` exits with "already signed."

To strip a signature entirely (leaving the binary unsigned — only do this before re-signing, not as a final state for app-bundle content on Apple Silicon):

```bash
codesign --remove-signature path/to/binary
```

> ⚠️ **DESTRUCTIVE:** Stripping a production binary's signature and not re-signing leaves it unable to run on Apple Silicon. Back up the binary before stripping. Rollback: restore from backup or re-sign.

**The `ditto` requirement:** When copying signed binaries, always use `ditto` instead of `cp`. Standard `cp` strips the resource fork and sets xattr bits that cause "resource fork, Finder information, or similar detritus not allowed" failures on re-sign. The PhantomLives install scripts already use `ditto --noextattr` for this reason.

```bash
# Good — preserves code signature metadata
ditto --noextattr MyApp.app /Applications/MyApp.app

# Bad — may corrupt the signature
cp -r MyApp.app /Applications/MyApp.app
```

---

### 10. Common failures and what they actually mean

| Error message | Root cause | Fix |
|---|---|---|
| `resource fork, Finder information, or similar detritus not allowed` | The bundle contains files with resource forks (often from `cp -r` or certain zip tools) | `xattr -cr MyApp.app` then re-sign; use `ditto` for all future copies |
| `code object is not signed at all` | A nested helper or framework inside the bundle lacks a signature | Sign the nested code before signing the outer bundle; use `--deep` to find the culprit with `codesign --verify --deep --strict` |
| `CSSMERR_TP_CERT_EXPIRED` | Certificate expired and no embedded timestamp | Renew cert in portal; re-sign with `--timestamp` |
| `invalid entitlements` | Entitlements plist is malformed, or you are using entitlements that require a provisioning profile you have not embedded | Validate plist with `plutil`; check if the key requires a profile |
| `The application cannot be verified` (Gatekeeper dialog) | Unnotarized app, invalid signature, or cert revoked | Notarize and staple; verify with `spctl -a -vvv` |
| `sealed resource is missing or invalid` | A file in the bundle was modified after signing | Rebuild from scratch rather than patching a signed bundle |
| `ambiguous` from `security find-identity` | Multiple identities match the short name | Use the full cert name or the SHA1 hash from `security find-identity` as the `-s` argument |
| `errSecInternalComponent` | The private key is not accessible — Keychain locked, or the cert was imported without the private key | Unlock Keychain; import the full `.p12` (cert + private key) |

---

## Hands-on (CLI & GUI)

### Inspect any installed app

Pick an app that ships with your system:

```bash
# Verify the signature
codesign --verify --deep --strict /Applications/Safari.app && echo "OK"

# Show all signature details
codesign -dvvv /Applications/Safari.app 2>&1 | head -30

# Dump entitlements (Safari has interesting ones)
codesign -d --entitlements - /Applications/Safari.app 2>/dev/null | plutil -convert xml1 -o - -

# Show Designated Requirement
codesign -d -r - /Applications/Safari.app

# Gatekeeper assessment
spctl -a -vvv /Applications/Safari.app
```

### Inspect the PhantomLives binaries

```bash
# Check one of your own release builds
codesign -dvvv /Applications/PurpleMark.app 2>&1 | grep -E "Authority|flags|Timestamp|TeamIdentifier"
spctl -a -vvv /Applications/PurpleMark.app
```

### List all your signing identities with full SHA1 fingerprints

```bash
security find-identity -v -p codesigning
```

If both Developer ID and Apple Development certs are listed, use the full certificate name string (or the hex SHA1) to avoid ambiguity in `codesign -s`.

### Check what entitlements a running process has

```bash
# Get PID of running app
PID=$(pgrep -n "PurpleMark")
# Dump its code signature live (macOS 12+)
codesign -dvvv /proc/$PID/exe 2>/dev/null || codesign -dvvv $(ps -p $PID -o comm=)
```

### Examine the quarantine database for forensic download history

```bash
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  "SELECT datetime(LSQuarantineTimeStamp + 978307200, 'unixepoch'), LSQuarantineAgentName, LSQuarantineOriginURLString, LSQuarantineDataURLString FROM LSQuarantineEvent ORDER BY LSQuarantineTimeStamp DESC LIMIT 20;"
```

> 🔬 **Forensics note:** `LSQuarantineOriginURLString` is the HTTP `Referer` of the page you were on when the download started. `LSQuarantineDataURLString` is the direct download URL. This persists even after the app is deleted. The epoch offset 978307200 is Apple's `NSDate` reference date (2001-01-01).

---

## Labs

### Lab 1 — Sign a binary from scratch

> ⚠️ **Lab prep:** This lab creates and modifies a throw-away binary in `/tmp`. No destructive impact on your system. Rollback: `rm /tmp/labsign/`.

```bash
mkdir -p /tmp/labsign
# Compile a minimal C hello-world binary
cat > /tmp/labsign/hello.c << 'EOF'
#include <stdio.h>
int main() { puts("hello from siglab"); return 0; }
EOF
clang -o /tmp/labsign/hello /tmp/labsign/hello.c

# 1. Confirm it is ad-hoc signed (Apple Silicon auto-signs on compile)
codesign -dvvv /tmp/labsign/hello

# 2. Strip the signature
codesign --remove-signature /tmp/labsign/hello
codesign -dvvv /tmp/labsign/hello  # should now say "code object is not signed at all"

# 3. Ad-hoc sign it (the dash = no certificate)
codesign -s - /tmp/labsign/hello
codesign -dvvv /tmp/labsign/hello  # flags should show no "runtime"; Authority = ad-hoc

# 4. Sign with hardened runtime and your Developer ID
codesign --force --options runtime \
         --sign "Developer ID Application: Robert Olen (SRKV8T38CD)" \
         --timestamp \
         /tmp/labsign/hello
codesign -dvvv /tmp/labsign/hello
# Expected: flags=0x10000(runtime), Authority=Developer ID Application..., Timestamp=...
```

### Lab 2 — Create an entitlements file and sign with it

> ⚠️ **Lab prep:** Creates files in `/tmp/labsign/`. No system impact.

```bash
cat > /tmp/labsign/hello.entitlements << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --options runtime \
         --entitlements /tmp/labsign/hello.entitlements \
         --sign "Developer ID Application: Robert Olen (SRKV8T38CD)" \
         --timestamp \
         /tmp/labsign/hello

# Inspect the embedded entitlements
codesign -d --entitlements - /tmp/labsign/hello 2>/dev/null | plutil -convert xml1 -o - -
```

### Lab 3 — Deliberately break and detect a signature

> ⚠️ **Lab prep:** Modifies `/tmp/labsign/hello`. Rollback: rerun Lab 1.

```bash
# Sign cleanly first
codesign --force -s - /tmp/labsign/hello

# Verify it passes
codesign --verify /tmp/labsign/hello && echo "Signature valid"

# Tamper with the binary: flip a byte
printf '\x90' | dd of=/tmp/labsign/hello bs=1 seek=100 conv=notrunc 2>/dev/null

# Now verify — this should FAIL
codesign --verify /tmp/labsign/hello 2>&1
# Expected: /tmp/labsign/hello: a sealed resource is missing or invalid

# The binary is now unrunnable on Apple Silicon because the signature is invalid
# Demonstrate:
/tmp/labsign/hello 2>&1 || echo "Exit: $?"
# Expected: Killed: 9 (or "Segmentation fault" / "Bad CPU type" depending on damage)
```

### Lab 4 — Read the CodeResources seal of an app bundle

> ⚠️ **No risk.** Read-only inspection.

```bash
APP="/Applications/TextEdit.app"
# Count sealed files
plutil -convert json -o - "$APP/Contents/_CodeSignature/CodeResources" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('files2',{})), 'sealed resources')"

# Show the first 5 entries with their hash2 (SHA-256) values
plutil -convert json -o - "$APP/Contents/_CodeSignature/CodeResources" | \
  python3 -c "
import sys,json,base64
d=json.load(sys.stdin)
items = list(d.get('files2',{}).items())[:5]
for path, info in items:
    h = base64.b64decode(info.get('hash2',{}).get('NS.data',''))
    print(h.hex()[:16]+'...', path)
"
```

### Lab 5 — Inspect a provisioning profile (if you have a MAS or push-enabled app)

```bash
# If you have any app with an embedded.provisionprofile:
PROFILE=$(find /Applications -name "embedded.provisionprofile" 2>/dev/null | head -1)
if [ -n "$PROFILE" ]; then
  security cms -D -i "$PROFILE" | plutil -convert xml1 -o - - | \
    grep -A2 -E "ExpirationDate|TeamName|AppIDName"
else
  echo "No provisioning profiles found in /Applications (expected for Developer ID apps)"
fi
```

---

## Pitfalls & gotchas

**Signing order matters — inside out.** When signing a bundle that contains nested code (Sparkle XPC services, helper apps, embedded frameworks), sign the innermost code first. The outer bundle's CodeResources seal will hash the inner signatures; if you sign the outer bundle first and then try to sign a nested helper, you break the outer seal.

**`--deep` is a crutch, not a solution.** `codesign --deep` signs nested code, but it applies the *same* flags and entitlements to everything. Nested XPC services and helper apps almost always need their *own* entitlements files (different from the main app). The PhantomLives release scripts explicitly enumerate and sign each sub-bundle.

**`cp` corrupts; `ditto` preserves.** Copying signed bundles with `cp -r` or zip/unzip on macOS can add resource forks, which then fail `codesign`'s sanity check. The fix before re-signing is `xattr -cr bundle.app`. The prevention is `ditto --noextattr`.

**The secure timestamp requires network access.** `--timestamp` contacts `timestamp.apple.com`. If you sign in a CI environment without outbound HTTP, either pre-cache the TSA response (not supported) or accept that your CI builds have no embedded timestamp. For release builds, sign on a machine with internet access.

**Certificate expiry vs. signature validity.** A Developer ID cert is valid for 5 years. If you signed with `--timestamp`, the embedded RFC 3161 timestamp proves the cert was valid at signing time, so the *signature* is valid indefinitely. Without the timestamp, the signature expires with the cert. This is why `--timestamp` is mandatory for any binary you intend to distribute.

**Identity resolution ambiguity.** If you pass a short substring as `-s "Robert Olen"` and the Keychain contains both an `Apple Development` and `Developer ID Application` cert for the same name, `codesign` exits with `ambiguous`. Always pass the full certificate name string exactly as printed by `security find-identity`.

**Gatekeeper re-evaluation after modification.** Once Gatekeeper has cleared an app (removed the quarantine xattr), it does not re-evaluate it on subsequent launches — even if the binary has been modified since. An attacker who can write to an app bundle after first-run clearance bypasses Gatekeeper. SIP prevents this for system-bundle locations; the user's `/Applications` is protected by TCC-based Finder access controls.

**Team ID is burned into the DR, not just the cert.** If you ever change developer accounts (Team ID), your users' Keychain ACLs and TCC grants will not automatically transfer to the new identity. The DR will no longer match and TCC will prompt again. Plan identity continuity from the start.

---

## Key takeaways

1. A code signature is a cryptographic seal computed over the binary's code pages, resource files, entitlements, and metadata — stored inside the `LC_CODE_SIGNATURE` Mach-O load command and in `Contents/_CodeSignature/CodeResources` for bundles.

2. The **cdhash** is the compact, unique identity of a specific build. The **Designated Requirement** is the stable predicate that re-identifies the same *app* across builds.

3. **Developer ID Application** is the certificate type for direct distribution outside the App Store. It must chain to Apple Root CA; there is no third-party CA option.

4. **Hardened runtime** (`-o runtime`) locks the process against code injection, unsigned dylib loading, and JIT — and is required for notarization.

5. Sign bundles **inside out**: nested helpers and frameworks first, the outer `.app` last.

6. Always use `--timestamp` for release builds. Always copy bundles with `ditto`. Use `--force` only when re-signing an already-signed object.

7. `codesign -dvvv` and `spctl -a -vvv` are the primary diagnostic tools. The quarantine SQLite database at `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` is the primary forensic artifact for download provenance.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Code signature** | The cryptographic seal embedded in or alongside a Mach-O binary or bundle verifying its identity and integrity |
| **Signing identity** | The (certificate, private key) pair in a Keychain used to compute a signature |
| **Developer ID Application** | The certificate type for macOS direct distribution that passes Gatekeeper without the App Store |
| **Team ID** | Apple's 10-character alphanumeric identifier for a developer team, embedded in every signature |
| **CodeDirectory** | The central data structure inside `LC_CODE_SIGNATURE` containing code page hashes, special slot hashes, flags, and identifiers |
| **cdhash** | The SHA-256 hash of the CodeDirectory; the compact, build-unique identity used by the kernel and TCC |
| **CodeResources** | The plist manifest (`Contents/_CodeSignature/CodeResources`) sealing every resource file in an `.app` bundle |
| **Designated Requirement (DR)** | A compiled predicate in Apple's requirement language defining how to recognize a given app across builds |
| **Hardened runtime** | A kernel-enforced set of process protections activated by the `runtime` signing flag; required for notarization |
| **Entitlements** | A plist of capability grants embedded in the signature; checked by the kernel and OS subsystems at runtime |
| **Secure timestamp** | An RFC 3161 counter-signature from Apple's TSA embedded by `--timestamp`, proving the cert was valid at signing time |
| **Provisioning profile** | A CMS-signed plist from Apple's Developer Portal authorizing specific entitlements for specific team/app combinations |
| **spctl** | System Policy control; CLI frontend to the Gatekeeper assessment engine |
| **Quarantine xattr** | The `com.apple.quarantine` extended attribute set on downloaded files; triggers Gatekeeper on first open |
| **Ad-hoc signing** | A signature with no certificate (`-s -`); valid for kernel page mapping but not for Gatekeeper |

---

## Further reading

- **Apple TN2206 — macOS Code Signing In Depth** (Apple Developer Library archive): the canonical reference for CodeDirectory internals, CodeResources format, and spctl usage
- **Apple TN3126 — Inside Code Signing: Hashes** and **TN3127 — Inside Code Signing: Requirements** (Apple Developer Documentation): the modern successors to TN2206 on specific subsystems
- **Apple Platform Security guide** (downloadable PDF from apple.com/privacy): chapters on Secure Boot, Signed System Volume, and Gatekeeper explain how code signing integrates with the hardware trust chain ([[01-boot-process]], [[02-apple-silicon-soc-and-secure-enclave]])
- **Howard Oakley — "A brief history of code signing on Macs"** (eclecticlight.co, 2025): timeline from Leopard to Sequoia with clear explanations of each era's changes
- **Howard Oakley — "What's happening with code signing and future macOS?"** (eclecticlight.co, January 2026): current state of requirements under macOS 26 Tahoe
- **mothersruin.com/software/Archaeology** — "All About Code Signing": detailed reverse-engineering walkthrough of the CodeDirectory binary format
- **`codesign(1)` man page** (`man codesign`): complete flag reference; the `-R` / `--requirements` section covers the requirement language grammar
- **`spctl(8)` man page** (`man spctl`): assessment policy options, batch operations, policy database management
- **`security(1)` man page**: Keychain operations, identity management, CMS decode
- Related lessons: [[08-security-architecture]] (Gatekeeper, SIP, TCC overview), [[04-keychain-and-secrets]] (Keychain internals, identity storage), [[04-notarization-and-distribution]] (the next step after signing), [[00-anatomy-of-an-app-bundle]] (bundle layout that CodeResources seals)
