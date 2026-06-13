---
title: Notarization & Distribution
part: P07 Development
est_time: 60 min read + 60 min labs
prerequisites: [part-01-architecture/08-security-architecture, part-05-security-forensics/00-the-security-model, part-05-security-forensics/04-keychain-and-secrets]
tags: [macos, codesigning, notarization, gatekeeper, distribution, sparkle, dmg, pkg, developer-id]
---

# Notarization & Distribution

> **In one sentence:** Getting a macOS app onto someone else's machine without the "damaged app" or "unidentified developer" wall requires a precise chain — Developer ID signing with hardened runtime, notarization via Apple's scan pipeline, ticket stapling for offline verification, and a packaging format (DMG, PKG, or Sparkle feed) that preserves every link in that chain.

---

## Why this matters

Every macOS app you distribute outside the Mac App Store runs through two security checkpoints controlled by Apple: **Gatekeeper** (the local enforcement agent) and the **notary service** (Apple's cloud-based malware scanner). Since macOS Catalina (10.15), Gatekeeper requires notarization for all Developer ID–distributed software; since Sequoia (15), the last easy user escape hatch — Control-clicking to open unsigned apps from Finder — was removed. The consequence for distribution is stark: if any step in the signing and notarization chain is wrong, users on modern Macs see either "this app is damaged and should be moved to the Trash" (a quarantine + signature failure) or a dead-end modal with no obvious path forward.

For someone building and shipping macOS apps (the PhantomLives release pipeline ships a dozen notarized DMGs with Sparkle auto-update), this is not academic. Getting it wrong once at release time means manually reaching every user. Getting it systematically right means a reproducible CI/local pipeline you can trust.

This lesson covers the full chain from codesign flags to stapled DMG, including the Sparkle EdDSA auto-update layer on top.

---

## Concepts

### The trust model: certificates, signatures, and Gatekeeper

Apple's macOS trust model for third-party software has three distinct layers, each building on the previous:

```
Developer ID Certificate (issued by Apple CA)
    └── codesign --sign "Developer ID Application: ..."
            └── app bundle on disk with signature in __LINKEDIT + Contents/CodeSignature/
                    └── Notarization ticket (JSON + hash, either online lookup or stapled)
                            └── Gatekeeper spctl assessment → ALLOW / DENY
```

**Developer ID Application** certificates are issued by Apple to paid Developer Program members. The certificate is stored in your login keychain; codesign retrieves it by identity string. Without a Developer ID cert, you can only ad-hoc sign (for local use) or use a Mac App Store distribution cert (sandboxed App Store only).

**Hardened Runtime** is an execution environment flag (`--options runtime` on the codesign invocation) that disables several insecure behaviors: JIT compilation across security boundaries, library injection via `DYLD_INSERT_LIBRARIES`, unsigned Mach-O loading, and address-space layout randomization overrides. Apple's notary service **requires** hardened runtime. If you legitimately need one of those capabilities (an app embedding a JS engine, for example), you declare an entitlement — but that entitlement itself may require Apple review.

**Secure timestamp** (`--timestamp` flag) embeds an RFC 3161 timestamp token from Apple's TSA server into the signature. This proves the code was signed at a specific moment in time relative to the certificate's validity period, so the app continues to validate even after the signing cert expires. Notarization requires it.

**Notarization** is a cloud scan, not an in-person review. Apple's service receives your submission (zip, dmg, or pkg), verifies the Developer ID signature and hardened runtime requirement, checks entitlements against allowed lists, and scans for known malware signatures. It does **not** review your logic or UI. The turnaround is typically 30 seconds to 5 minutes; it occasionally stretches to 15+ minutes when Apple's service is under load.

**Stapling** attaches the notarization ticket to the artifact on disk so Gatekeeper can verify it offline. Without stapling, Gatekeeper contacts Apple's OCSP server on first launch; a user on a plane or behind a restrictive firewall gets a "cannot be opened" error. After stapling, the ticket is embedded and no network call is needed.

> 🔬 **Forensics note:** The com.apple.quarantine extended attribute is the first thing Gatekeeper checks. Every file downloaded via a browser, `curl`, or AirDrop gets quarantined. The attribute carries the download URL, the date, and the LSQuarantine event UUID. `xattr -p com.apple.quarantine /path/to/App.app` reveals the full value: e.g., `0083;65f2a3b4;Safari;UUID`. On first launch of a quarantined app, LaunchServices invokes `syspolicyd`, which calls into `GKAgent` (the user-facing security dialog process) and performs a `spctl` assessment. The notarization ticket — either stapled or fetched via the CDN at `api.apple-cloudkit.com` — is what makes that assessment pass. Investigators examining a compromised Mac should check whether quarantine was stripped (`xattr -d com.apple.quarantine`) as an indicator of deliberate bypass. See also [[part-05-security-forensics/00-the-security-model]] and [[part-05-security-forensics/03-forensic-artifacts]].

### The Gatekeeper assessment pipeline

`syspolicyd` is the daemon that enforces the policy. It is configured by `/var/db/SystemPolicy` (a SQLite database) and the rules compiled into the OS. `spctl` is the user-facing CLI into this daemon.

When a quarantined app launches:

1. `LaunchServices` → `lsd` → `syspolicyd` (via XPC) passes the path and signing identity.
2. `syspolicyd` calls `GKAssess()`:
   a. Checks the code signature with Security.framework.
   b. Verifies the certificate chain → Developer ID CA → Apple Root CA.
   c. Checks for a notarization ticket (stapled first; CDN lookup if not stapled and network available).
   d. Evaluates any Gatekeeper User Override stored in `com.apple.security.quarantine.user-excluded-apps` TCC-style records.
3. If assessment passes: the quarantine flag's 4th bit is flipped (bit `0x0100`), marking it "user approved." Future launches skip the full assessment.
4. If assessment fails: the dialog appears. **On macOS Sequoia+**, the only recourse for the user is `System Settings → Privacy & Security → Security → Open Anyway` (requires admin password). The old Finder Control-click bypass is gone.

> 🪟 **Windows contrast:** Windows SmartScreen is conceptually similar but reputation-based rather than certificate-authority-gated. An app signed with an EV (Extended Validation) code-signing certificate gets immediate reputation. A standard OV cert starts with zero reputation and shows a "Windows protected your PC" warning until the app accumulates enough users/downloads for Microsoft's telemetry to grant it. There is no equivalent of notarization scanning or a per-submission ticket — the burden is on certificate tier and crowd-sourced reputation. SmartScreen can be bypassed by clicking "More info → Run anyway" with no admin password, which is the gap Sequoia's Gatekeeper change closed on the macOS side.

### The notary service: what Apple checks and what gets rejected

Apple's notary service rejects submissions for these categories of issues (not exhaustive, but covering 95% of real-world failures):

| Rejection category | Root cause | Fix |
|---|---|---|
| `UNSIGNED_BINARY` | A helper, dylib, or nested `.app` lacks a signature | Sign inside-out (deepest binaries first), then the outer bundle |
| `MISSING_HARDENED_RUNTIME` | `--options runtime` not passed to `codesign` | Add `--options=runtime` to every `codesign` call |
| `MISSING_TIMESTAMP` | No secure timestamp embedded | Add `--timestamp` to every `codesign` call |
| `ENTITLEMENT_DISALLOWED` | Entitlement declared not permitted for Developer ID | Remove or request exception; common culprit: `com.apple.security.cs.disable-library-validation` without justification |
| `CERTIFICATE_REVOKED` or `CERTIFICATE_EXPIRED` | Signing cert is no longer valid | Renew cert in Developer Portal; re-sign everything |
| `INVALID_SIGNATURE` | Binary modified after signing (e.g., strip, install_name_tool) | Sign last, after all binary modifications |

The most common failure for complex apps is unsigned nested code: a bundled CLI tool, a `.dylib` shipped in `Contents/Frameworks/`, a Python or Electron runtime, or a shell script with `#!/usr/bin/env` that has execute bits but isn't a Mach-O (scripts don't get signed, but they must not appear as unsigned Mach-O). The inside-out signing rule is absolute: **sign every nested binary before signing the outer bundle**.

### `notarytool` vs the deprecated `altool`

`xcrun altool --notarize-app` was deprecated in Xcode 13 and removed in Xcode 15. Do not use it. `xcrun notarytool` (introduced Xcode 13) is the current tool. It is dramatically faster (async with `--wait`), has better error output, and stores credentials securely in the keychain.

```
notarytool subcommands:
  store-credentials    Store auth in keychain (one-time setup)
  submit               Upload and optionally wait for result
  info                 Poll status of a submission by ID
  log                  Download the full JSON log for a submission
  history              List recent submissions
```

Credentials come in two flavors:

**App-specific password (recommended for personal pipelines):**
```bash
xcrun notarytool store-credentials "NotaryProfile" \
  --apple-id "robert.olen@icloud.com" \
  --team-id  "SRKV8T38CD" \
  --password "@keychain:notary-app-password"
# The password is an app-specific password generated at appleid.apple.com
# (not your Apple ID login password). The @keychain: prefix reads it from
# a keychain item you previously stored with:
#   security add-generic-password -a "robert.olen@icloud.com" \
#     -s "notary-app-password" -w "<app-specific-password>"
```

**App Store Connect API key (recommended for CI):**
```bash
xcrun notarytool store-credentials "NotaryProfileCI" \
  --key        "/path/to/AuthKey_XXXXXXXXXX.p8" \
  --key-id     "XXXXXXXXXX" \
  --issuer     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# The API key is downloaded once from App Store Connect → Users → Keys.
# The issuer ID is shown on the same page.
```

Both methods write to `~/Library/Keychains/login.keychain-db`. The profile name (e.g., `"NotaryProfile"`) is what you pass to `--keychain-profile` on all subsequent submissions. **You never store the raw credential in the command line or a script** — only the profile name.

> ⚠️ **CI / sandbox gotcha:** The keychain is locked or unreachable in certain sandboxed environments and in Finder-launched helper processes. If you run notarization from a CI environment (GitHub Actions, Jenkins), the keychain containing the NotaryProfile must be unlocked before the call: `security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db`. If `notarytool` returns "profile not stored" or "credentials not found" despite the profile existing, the sandbox cannot read the login keychain — the fix is to disable the sandbox for that shell session or use an explicit keychain path. See [[part-05-security-forensics/04-keychain-and-secrets]] for keychain internals.

### Reading the notarization log

When a submission fails (or even when it succeeds, for forensic depth), download the full JSON log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "NotaryProfile" notary-log.json
cat notary-log.json | python3 -m json.tool | less
```

The log JSON has a top-level `issues` array. Each issue has:

```json
{
  "severity": "error",
  "code": null,
  "path": "YourApp.app/Contents/MacOS/helper-binary",
  "message": "The binary is not signed with a valid Developer ID certificate.",
  "docUrl": "https://developer.apple.com/documentation/...",
  "arch": "arm64"
}
```

The `path` field is relative to the submitted artifact root and uses the nested path. This is your primary diagnostic: if 12 binaries are unsigned, you'll see 12 entries each pointing at the exact Mach-O path. The `arch` field matters on universal binaries — a fat binary can have a properly signed arm64 slice and a broken x86_64 slice if you assembled slices from separately-built binaries without re-signing the fat result.

### Packaging for distribution

#### DMG (Disk Image)

A DMG is the standard delivery vehicle for `.app` bundles distributed outside the App Store. The canonical user experience is:

```
[App Icon]  →  [Applications alias]
  (drag)              (shortcut)
```

Two tools dominate DMG creation:

**`hdiutil` (built-in, scriptable):**
```bash
# 1. Create a writable staging image
hdiutil create -size 200m -fs HFS+ -volname "MyApp" /tmp/myapp-staging.dmg

# 2. Mount it, copy the app, add Applications alias
hdiutil attach /tmp/myapp-staging.dmg
cp -R MyApp.app /Volumes/MyApp/
ln -s /Applications /Volumes/MyApp/Applications
# (arrange icons, set background via AppleScript/SetFile if desired)
hdiutil detach /Volumes/MyApp

# 3. Convert to read-only compressed UDIF format
hdiutil convert /tmp/myapp-staging.dmg \
  -format UDZO -imagekey zlib-level=9 \
  -o MyApp-1.0.0.dmg
```

**`create-dmg` (Homebrew: `brew install create-dmg`):**
```bash
create-dmg \
  --volname "MyApp 1.0.0" \
  --background "Assets/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "MyApp.app" 180 170 \
  --hide-extension "MyApp.app" \
  --app-drop-link 480 170 \
  "MyApp-1.0.0.dmg" \
  "dist/MyApp.app"
# Result: a writable-then-converted DMG, unsigned, with the drag layout.
```

Note: `create-dmg` produces an UDIF image with a detachable signature slot. After creation you sign and notarize the DMG itself (not just the app inside it).

**Stapling order for DMGs:** You must staple both the app bundle (before DMG creation) AND the DMG itself (after notarizing the DMG). The workflow is:

```
1. Sign app bundle (inside-out)
2. Notarize app bundle (submit zip of app, wait, staple)
3. Create DMG containing the already-notarized+stapled app
4. Sign the DMG with Developer ID (codesign or productsign is not needed for a DMG — the DMG itself doesn't need to be signed with Developer ID, but it does need to be notarized)
5. Notarize the DMG
6. Staple the DMG
7. Distribute the stapled DMG
```

The app bundle inside the DMG carries its own stapled ticket. The DMG wrapper carries a separate ticket. Both are checked independently.

#### PKG installers

PKGs are used when you need to install files outside `/Applications/` — kernel extensions (though KEXTs require additional approval), Launch Daemons, shared frameworks, CLIs to `/usr/local/bin/`, or privileged helper tools. Two-stage build:

```bash
# Stage 1: pkgbuild — wrap one "component" (usually an app or payload dir)
pkgbuild \
  --root ./payload \          # directory tree to install
  --identifier com.example.MyApp \
  --version 1.2.3 \
  --install-location /Applications \
  --sign "Developer ID Installer: Your Name (TEAMID)" \
  MyApp-component.pkg

# Stage 2: productbuild — compose a "distribution" PKG with custom UI,
# multiple components, or install scripts
productbuild \
  --distribution distribution.xml \
  --resources ./Resources \
  --package-path . \
  --sign "Developer ID Installer: Your Name (TEAMID)" \
  MyApp-1.2.3.pkg
```

Note the **different certificate type**: PKGs require "Developer ID Installer" (not "Application"). Both can be issued from the same Apple Developer account but are separate certs.

```bash
# Notarize a PKG directly (no zip wrapper needed)
xcrun notarytool submit MyApp-1.2.3.pkg \
  --keychain-profile "NotaryProfile" \
  --wait

# Staple
xcrun stapler staple MyApp-1.2.3.pkg
```

#### Mac App Store path

Sandboxed, reviewed, no notarization needed (the App Review process replaces it), distributed via `Transporter` or Xcode's Archive → Distribute. Uses a completely different certificate ("Apple Distribution" or "Mac App Distribution"). The entitlement set is heavily restricted. Not covered in detail here — the PhantomLives pipeline does not use this path.

### Sparkle: auto-update with EdDSA signing

[Sparkle](https://sparkle-project.org/) is the de facto standard open-source auto-update framework for Mac apps outside the App Store. The PhantomLives apps (PurpleMark, PurpleAttic, etc.) use Sparkle 2 with EdDSA signing.

**How Sparkle works:**

```
App → SUUpdater checks SUFeedURL in Info.plist (the "appcast URL")
    → Downloads appcast.xml (RSS-like XML)
    → Finds newest <item> with version > current
    → Verifies sparkle:edSignature on the download URL
    → Downloads delta or full update zip
    → Verifies EdDSA signature
    → Installs via privileged xpc helper (SPU framework)
    → Relaunches app
```

**EdDSA key setup (one-time per app):**

```bash
# Generate a key pair using Sparkle's tool
./bin/generate_keys
# Outputs:
#   Private key: stored in your macOS Keychain (NOT exported; stays on signing machine)
#   Public key:  a base64 string to embed in Info.plist as SUPublicEDKey
```

The private key never leaves the signing machine's keychain. The public key is compiled into the app. Any update that doesn't pass the EdDSA signature check is silently rejected by Sparkle — even a man-in-the-middle who controls the appcast server cannot deliver a malicious update without the private key.

**Signing a release and generating the appcast:**

```bash
# After building and notarizing MyApp-1.2.3.dmg:
./bin/generate_appcast /path/to/releases/
# Scans all .dmg/.zip files in that directory,
# generates or updates appcast.xml with:
#   <enclosure url="..." length="..." type="application/octet-stream"
#              sparkle:version="1.2.3" sparkle:edSignature="base64..." />
```

`generate_appcast` reads the EdDSA private key from the keychain automatically. It also sets `sparkle:shortVersionString` and `sparkle:version` from the bundle's `CFBundleShortVersionString` and `CFBundleVersion`.

**Appcast XML minimum viable structure:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MyApp Changelog</title>
    <item>
      <title>Version 1.2.3</title>
      <sparkle:releaseNotesLink>https://example.com/release-notes/1.2.3.html</sparkle:releaseNotesLink>
      <pubDate>Fri, 13 Jun 2025 10:00:00 +0000</pubDate>
      <enclosure
        url="https://example.com/releases/MyApp-1.2.3.dmg"
        length="12345678"
        type="application/octet-stream"
        sparkle:version="12300"
        sparkle:shortVersionString="1.2.3"
        sparkle:edSignature="BASE64SIGNATURE=="
      />
    </item>
  </channel>
</rss>
```

**Minimum `Info.plist` keys:**
```xml
<key>SUFeedURL</key>
<string>https://example.com/releases/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>BASE64PUBLICKEY==</string>
<key>NSAppTransportSecurity</key>
<dict>
  <!-- Sparkle 2 requires HTTPS for the feed URL; HTTP is blocked by ATS -->
</dict>
```

> 🔬 **Forensics note:** Sparkle leaves artifacts under `~/Library/Application Support/<AppName>/Sparkle/` (update cache, downloaded packages) and under `~/Library/Caches/<BundleID>/` (older Sparkle versions). Network logs in unified logging (`subsystem: org.sparkle-project`) capture the feed URL, the version discovered, and the install decision. On a machine you're investigating, these logs establish when a particular app version was installed via auto-update vs. fresh install.

---

## Hands-on (CLI & GUI)

### Verifying code signature depth

```bash
# Check the outer bundle signature
codesign -dv --verbose=4 /Applications/MyApp.app
# Look for: Authority= (Developer ID Application: ...), TeamIdentifier=, Timestamp=

# Deep verify (checks all nested components)
codesign --verify --deep --strict --verbose=2 /Applications/MyApp.app
# Expect: /Applications/MyApp.app: valid on disk
#          /Applications/MyApp.app: satisfies its Designated Requirement

# List all signed components in a bundle
codesign -dv --verbose=4 /Applications/MyApp.app 2>&1 | grep -E "^Identifier|^TeamIdentifier"
```

### Checking entitlements

```bash
# Print entitlements embedded in the signature
codesign -d --entitlements :- /Applications/MyApp.app
# The :- argument outputs as XML to stdout
# Look for any hardened runtime relaxations:
#   com.apple.security.cs.allow-unsigned-executable-memory → true  (risky)
#   com.apple.security.cs.disable-library-validation → true         (risky)
```

### Gatekeeper assessment

```bash
# Assess an app
spctl -a -vv /Applications/MyApp.app
# Expected output for a valid notarized app:
#   /Applications/MyApp.app: accepted
#   source=Notarized Developer ID
#   origin=Developer ID Application: Your Name (TEAMID)

# Assess a DMG
spctl -a -vv -t open MyApp-1.2.3.dmg --context context:primary-signature

# Check quarantine status
xattr -l /path/to/downloaded/MyApp.app
# Look for com.apple.quarantine value

# Remove quarantine (for a known-safe app in a dev context)
# ⚠️ ADVANCED: only do this for apps you trust completely
xattr -d com.apple.quarantine /path/to/MyApp.app
```

### Checking a stapled ticket

```bash
# Verify stapling (check for embedded ticket)
xcrun stapler validate /Applications/MyApp.app
# Expected: The validate action worked!

xcrun stapler validate MyApp-1.2.3.dmg
# Expected: The validate action worked!

# If not stapled, this returns exit code 65.
```

### Checking notarization history

```bash
xcrun notarytool history --keychain-profile "NotaryProfile"
# Lists all recent submissions with IDs, dates, status

xcrun notarytool info <submission-id> --keychain-profile "NotaryProfile"
# Shows current status: In Progress / Accepted / Invalid
```

---

## Labs

### Lab 1: Sign, notarize, and staple an app bundle

This lab walks through the complete end-to-end notarization of a Developer ID–signed app.

> ⚠️ **Prerequisites:** An enrolled Apple Developer Program account, a Developer ID Application certificate in your login keychain, and `xcrun notarytool store-credentials` already run with your keychain profile (e.g., `"NotaryProfile"`). You need an app bundle to practice with — use any of the PhantomLives apps built with `./build-app.sh`.

```bash
APP="/path/to/YourApp.app"
IDENTITY="Developer ID Application: Your Name (TEAMID)"
PROFILE="NotaryProfile"   # set by store-credentials earlier
VERSION="1.0.0"

# Step 1: Verify the existing signature (build-app.sh should have done this)
codesign --verify --deep --strict --verbose=2 "$APP"

# Step 2: Check entitlements are sensible
codesign -d --entitlements :- "$APP"

# Step 3: Create a zip for submission
# (notarytool also accepts .dmg and .pkg directly; zip is for bare .app)
ditto -c -k --keepParent "$APP" /tmp/YourApp-notarize.zip

# Step 4: Submit to Apple's notary service and wait for result
xcrun notarytool submit /tmp/YourApp-notarize.zip \
  --keychain-profile "$PROFILE" \
  --wait \
  --output-format plist
# --wait polls until complete (typically 30s–5min)
# On success: status=Accepted, id=<UUID>
# On failure: status=Invalid, id=<UUID> — proceed to step 5

# Step 5 (if failed): Download and inspect the log
xcrun notarytool log <submission-UUID> \
  --keychain-profile "$PROFILE" \
  /tmp/notary-log.json
python3 -m json.tool /tmp/notary-log.json | grep -A5 '"severity": "error"'

# Step 6: Staple the ticket to the app
xcrun stapler staple "$APP"
# Expected: The staple and validate action worked!

# Step 7: Verify the staple
xcrun stapler validate "$APP"

# Step 8: Confirm Gatekeeper assessment
spctl -a -vv "$APP"
# Expected: accepted  source=Notarized Developer ID
```

**Rollback:** Notarization is additive (you submit, get a ticket back). If something goes wrong, there's nothing to roll back on your machine — you just have an unsigned/un-stapled app. Re-run the sign+notarize pipeline from Step 1.

---

### Lab 2: Build a notarized DMG

> ⚠️ **Requires:** A notarized+stapled `.app` from Lab 1. Install `create-dmg` via `brew install create-dmg`.

```bash
APP="/path/to/YourApp.app"   # already notarized + stapled
VERSION="1.0.0"
PROFILE="NotaryProfile"
OUTPUT_DIR="$HOME/Downloads/YourApp"
mkdir -p "$OUTPUT_DIR"
STAGING_DIR="/tmp/dmg-staging-$$"
mkdir -p "$STAGING_DIR"

# Step 1: Copy the notarized app into staging
cp -R "$APP" "$STAGING_DIR/"

# Step 2: Build the DMG with create-dmg
create-dmg \
  --volname "YourApp $VERSION" \
  --window-pos 200 120 \
  --window-size 580 360 \
  --icon-size 100 \
  --icon "YourApp.app" 140 170 \
  --hide-extension "YourApp.app" \
  --app-drop-link 440 170 \
  "$OUTPUT_DIR/YourApp-$VERSION.dmg" \
  "$STAGING_DIR/"
# create-dmg returns exit code 2 "no valid signature" — this is expected
# because the DMG is not yet notarized. Ignore it.

# Step 3: Notarize the DMG itself
xcrun notarytool submit "$OUTPUT_DIR/YourApp-$VERSION.dmg" \
  --keychain-profile "$PROFILE" \
  --wait

# Step 4: Staple the DMG
xcrun stapler staple "$OUTPUT_DIR/YourApp-$VERSION.dmg"

# Step 5: Validate
xcrun stapler validate "$OUTPUT_DIR/YourApp-$VERSION.dmg"
spctl -a -vv -t open "$OUTPUT_DIR/YourApp-$VERSION.dmg" \
  --context context:primary-signature

# Cleanup
rm -rf "$STAGING_DIR"
echo "Distributable DMG: $OUTPUT_DIR/YourApp-$VERSION.dmg"
```

**What to look for:** After attaching the DMG in Finder, double-click the app. It should open immediately with no Gatekeeper dialog (since it's notarized and the ticket is stapled). Check `xattr -l /Volumes/YourApp/YourApp.app` — you should see NO `com.apple.quarantine` attribute because the app was never "downloaded" (it came from a local volume).

---

### Lab 3: Diagnose a signing failure with a broken test app

> ⚠️ **This lab intentionally creates a broken app to trigger notarization rejection. No sensitive data involved; create a throwaway target.**

```bash
# Create a minimal app bundle
BROKEN="/tmp/BrokenApp.app"
mkdir -p "$BROKEN/Contents/MacOS"
printf '#!/bin/bash\necho hello' > "$BROKEN/Contents/MacOS/BrokenApp"
chmod +x "$BROKEN/Contents/MacOS/BrokenApp"
cat > "$BROKEN/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key> <string>com.test.broken</string>
  <key>CFBundleName</key>        <string>BrokenApp</string>
  <key>CFBundleVersion</key>     <string>1</string>
</dict>
</plist>
EOF

# Sign WITHOUT hardened runtime (missing --options runtime)
codesign --sign "Developer ID Application: Your Name (TEAMID)" \
  --timestamp \
  "$BROKEN"

# Verify: this will succeed locally...
codesign --verify --deep --strict --verbose=2 "$BROKEN"

# ...but Gatekeeper assessment will fail (not notarized)
spctl -a -vv "$BROKEN"
# Expected: /tmp/BrokenApp.app: rejected  source=no usable signature

# Submit to notary (this will get rejected)
ditto -c -k --keepParent "$BROKEN" /tmp/broken.zip
xcrun notarytool submit /tmp/broken.zip \
  --keychain-profile "NotaryProfile" \
  --wait \
  --output-format plist
# Expected: status=Invalid

# Fetch the log — observe the MISSING_HARDENED_RUNTIME error
xcrun notarytool log <submission-UUID> \
  --keychain-profile "NotaryProfile" \
  /tmp/broken-log.json
cat /tmp/broken-log.json | python3 -m json.tool
```

Read the `issues` array. You'll see `"message": "The binary does not have the hardened runtime enabled."` with the exact path. Now fix it:

```bash
# Re-sign with hardened runtime
codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  --timestamp \
  "$BROKEN"

# Resubmit — this one will still be rejected because a shell script
# binary can't be notarized, but the hardened-runtime error will be gone
# and you'll see the actual content issue instead.
```

---

### Lab 4: Verify a Sparkle auto-update signature

If you have a Sparkle-enabled app with `generate_appcast` set up:

```bash
# After building and notarizing a new release DMG:
RELEASES_DIR="$HOME/Downloads/releases/"
SPARKLE_BIN="/path/to/Sparkle.framework/Versions/B/Resources"

# Sign the DMG and generate/update the appcast
"$SPARKLE_BIN/generate_appcast" "$RELEASES_DIR"
# Output: Updated appcast.xml with sparkle:edSignature for each .dmg

# Inspect the generated signature
grep "edSignature" "$RELEASES_DIR/appcast.xml"
# Should show a base64 Ed25519 signature per item

# Verify the signature manually with sign_update
"$SPARKLE_BIN/sign_update" "$RELEASES_DIR/YourApp-1.2.3.dmg"
# Prints the expected edSignature — compare to appcast.xml

# Upload appcast.xml and the DMG to your web server
# Users running the old version will auto-update on next check
```

---

## Pitfalls & gotchas

**1. Modifying binaries after signing invalidates the signature.**
`strip`, `install_name_tool`, `codesign --deep` (which re-signs nested components), and even `touch` on the binary path can invalidate. Always sign last in your build pipeline, after all binary transformations.

**2. `codesign --deep` is not a substitute for inside-out signing.**
`--deep` re-signs nested components recursively but does so without specifying entitlements for each component. Frameworks and helpers may require their own entitlement files. Sign each component explicitly, then sign the outer bundle without `--deep`.

**3. DMGs need their own notarization ticket, separate from the app inside.**
A common mistake is notarizing the app, putting it in a DMG, and distributing the un-notarized DMG. When a user downloads the DMG and mounts it, the DMG itself is checked by Gatekeeper when it's opened. The stapled app inside has its own ticket, but the DMG wrapper also needs one.

**4. The keychain must be unlocked in CI.**
`xcrun notarytool` reads from the login keychain. In non-interactive CI environments (GitHub Actions macOS runners, headless Jenkins), the keychain is locked at the start of each job. Unlock it before calling notarytool:
```bash
security unlock-keychain -p "$KEYCHAIN_PASSWORD" \
  "$HOME/Library/Keychains/login.keychain-db"
```

**5. `--wait` in notarytool has no timeout.**
If Apple's service is congested, `--wait` blocks indefinitely. In production pipelines, add a watchdog or use `--no-wait` + `notarytool info` polling with a max-retry loop.

**6. Sparkle EdDSA private key loss = inability to ship updates users trust.**
The private key is stored only in the keychain on your signing machine. If you lose it, you must ship a new app version with a new public key compiled in — and users need to install that manually (the old Sparkle instance won't trust updates signed with the new key). Back up your Sparkle private key in a secrets vault, not just the keychain.

**7. Universal binaries (fat Mach-O) with mixed-source slices.**
If you `lipo` together an arm64 binary from one build and an x86_64 binary from another, the resulting fat binary has no valid signature (lipo strips the individual signatures). You must codesign the fat binary after lipo. The notary log's `arch` field will tell you which slice failed.

**8. Sequoia removed the Ctrl-click Finder bypass.**
If you're testing your own unsigned builds on macOS Sequoia (15) or macOS 26 (Tahoe), the old Ctrl-click → Open path in Finder is gone. You must go to `System Settings → Privacy & Security → Security → Open Anyway` and enter your admin password. For your own developer builds, it's faster to just remove quarantine: `xattr -d com.apple.quarantine /path/to/MyApp.app`. For apps you're distributing, the answer is: notarize them properly.

**9. Entitlement `com.apple.security.cs.allow-jit` triggers extra scrutiny.**
Apps that need JIT (game engines, JavaScript runtimes, Python with ctypes) must declare this entitlement. Apple's notary service accepts it, but if you combine it with other relaxations, you may hit `ENTITLEMENT_DISALLOWED`. Use the minimal set of entitlements.

**10. `spctl --master-disable` system-wide disables Gatekeeper.**
This command opens all apps regardless of signing status. It is sometimes recommended as a "fix" in online forums. It is a terrible idea on any machine used for real work. Audit with `spctl --status` (should return "assessments enabled"). If you find it disabled on a machine you're investigating: document it as a significant security misconfiguration.

> 🔬 **Forensics note:** `spctl --status` output and the Gatekeeper master switch state are readable from `defaults read /var/db/SystemPolicy-prefs.plist`. The value `GKAutoRearm` and `enabled` keys show whether Gatekeeper is active. The `SystemPolicy` SQLite database at `/var/db/SystemPolicy` contains the full rule set plus an `assessments` table that logs every Gatekeeper decision with timestamp, path, and outcome — a goldmine for forensic timelines of software execution on a compromised machine.

---

## Key takeaways

- Notarization is a two-phase process: submit to Apple's cloud scanner, then staple the returned ticket. Without stapling, users on restricted networks get false failures.
- The signing order is absolute: inside-out (deepest nested binaries first), then the outer bundle. `codesign --deep` is insufficient for production.
- `xcrun notarytool` replaces the removed `altool`. Use `store-credentials` once; reference the keychain profile name everywhere else. Never embed credentials in scripts.
- Hardened runtime (`--options runtime`) and secure timestamp (`--timestamp`) are both required by the notary service. Missing either → immediate rejection.
- The notarization log JSON (`notarytool log <id>`) is your primary diagnostic. The `path` field in each `issues` entry points to the exact binary causing the problem.
- DMGs and PKGs need their own notarization submissions and stapling, separate from the app bundle inside them.
- Sparkle auto-update uses EdDSA (Ed25519) asymmetric signing. The private key lives only in your keychain; the public key is compiled into the app. Loss of the private key requires a manual re-installation from your user base to recover.
- Since macOS Sequoia, the Ctrl-click Gatekeeper bypass is gone. Properly notarized apps are the only frictionless path for end users.
- `spctl -a -vv` and `xcrun stapler validate` are your post-build confidence checks. Run both as part of every release pipeline.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Developer ID Application** | Certificate type for signing apps distributed outside the Mac App Store; issued by Apple to Developer Program members |
| **Developer ID Installer** | Certificate type for signing PKG installers; separate cert from Developer ID Application |
| **Hardened Runtime** | Execution mode (enabled by `--options runtime` codesign flag) that disables insecure behaviors; required for notarization |
| **Secure timestamp** | RFC 3161 timestamp token embedded in the signature proving when it was created; required for notarization |
| **Notarization** | Apple's cloud scan of a submitted artifact: checks signing, hardened runtime, entitlements, and known malware |
| **Notarization ticket** | JSON blob containing a hash of the artifact and Apple's signed approval; downloaded from CDN or stapled to the artifact |
| **Stapling** | Embedding a notarization ticket into the artifact on disk so Gatekeeper can verify offline |
| **`notarytool`** | Apple CLI (part of Xcode) for submitting artifacts to the notary service, checking status, and downloading logs |
| **Keychain profile** | Named credential set stored in the macOS Keychain by `notarytool store-credentials`; referenced by `--keychain-profile` |
| **Gatekeeper** | macOS system enforcing that launched apps meet code signing and notarization policy; enforced by `syspolicyd` |
| **`spctl`** | CLI for querying and configuring System Policy (Gatekeeper assessment) |
| **Quarantine** | `com.apple.quarantine` extended attribute applied by browsers and download tools; triggers Gatekeeper assessment on first launch |
| **`com.apple.quarantine`** | Extended attribute (xattr) recording download source, date, and UUID; Gatekeeper's signal to perform an assessment |
| **UDIF** | Universal Disk Image Format — the `.dmg` file format used by macOS; `hdiutil` creates/converts UDIF images |
| **`create-dmg`** | Open-source CLI tool (Homebrew) for creating drag-to-Applications DMG installers with custom layouts |
| **Sparkle** | Open-source macOS auto-update framework; uses appcasts (RSS XML) and EdDSA-signed payloads |
| **EdDSA / Ed25519** | Elliptic-curve signature scheme used by Sparkle 2 to authenticate update payloads |
| **Appcast** | RSS-format XML file listing available Sparkle updates with version metadata and EdDSA signatures |
| **`generate_appcast`** | Sparkle tool that scans a release directory and produces/updates `appcast.xml` with EdDSA signatures |
| **App-specific password** | Single-purpose password issued at appleid.apple.com; used for notarytool authentication without exposing the Apple ID password |
| **App Store Connect API key** | Service-account credential (`.p8` file) for CI systems; preferred over app-specific passwords for automation |
| **`pkgbuild`** | Apple CLI for wrapping a payload directory into a component PKG |
| **`productbuild`** | Apple CLI for composing a distribution PKG (with installer UI, scripts, multiple components) |
| **`altool`** | Deprecated predecessor to `notarytool`; removed in Xcode 15 |

---

## Further reading

- [Apple Developer: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — canonical requirements and workflow
- [Apple Platform Security Guide](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) — Gatekeeper internals and SIP integration
- [xcrun notarytool man page](https://keith.github.io/xcode-man-pages/notarytool.1.html) — all subcommands and flags
- [Sparkle documentation: Publishing an update](https://sparkle-project.org/documentation/publishing/) — generate_appcast workflow
- [Sparkle documentation: EdDSA migration](https://sparkle-project.org/documentation/eddsa-migration/) — upgrading from DSA to EdDSA
- [Scripting OS X: Notarize a Command Line Tool with notarytool](https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/) — practical walkthrough including CLI tool signing nuances
- [Howard Oakley (Eclectic Light): Gatekeeper and code signing](https://eclecticlight.co/gatekeeper-code-signing-and-notarisation/) — deep dives on quarantine mechanics and Sequoia changes
- [[part-05-security-forensics/00-the-security-model]] — macOS security architecture overview including SIP, TCC, Gatekeeper
- [[part-05-security-forensics/04-keychain-and-secrets]] — keychain internals, unlocking in CI, keychain item management
- [[part-05-security-forensics/03-forensic-artifacts]] — quarantine xattr forensics, SystemPolicy database, Gatekeeper log artifacts
- [[part-01-architecture/08-security-architecture]] — Secure Enclave, trust hierarchy, certificate chains
