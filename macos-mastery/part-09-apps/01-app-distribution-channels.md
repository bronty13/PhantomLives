---
title: "App distribution: App Store vs direct vs Homebrew"
part: "P09 Apps"
est_time: "50 min read + 40 min labs"
prerequisites: [02-filesystem-layout, 05-security-gatekeeper-sip]
tags: [macos, apps, homebrew, app-store, gatekeeper, notarization, security, forensics]
---

# App distribution: App Store vs direct vs Homebrew

> **In one sentence:** macOS has four distinct software distribution channels, each with a different trust model, capability envelope, and on-disk artifact set — understanding all four lets you make intelligent installation decisions, uninstall cleanly, and reconstruct exactly how software arrived on a machine.

## Why this matters

On Windows the question is usually "did I run the `.exe`?" On macOS the *channel* through which software arrived determines what it can do, how it updates, what it leaves behind when you remove it, and how much Apple's infrastructure vouches for it. A forensic examiner reading a Mac image needs to distinguish between App Store receipts, Gatekeeper assessment records, quarantine xattrs, and Homebrew Cellar entries — they tell completely different stories about software provenance. A power user who ignores channel distinctions ends up with three competing auto-updaters fighting over the same binary and no clean way to audit what's installed.

> 🪟 **Windows contrast:** Windows has four loosely analogous channels — Microsoft Store (sandboxed UWP/MSIX), traditional `.exe`/`.msi` installers, `winget` (the official package manager that wraps both), and Chocolatey/Scoop (community). The parallels are: Store ↔ Mac App Store; `.exe` ↔ `.dmg`/`.pkg` direct; `winget` ↔ `brew`; Scoop ↔ MacPorts. The key differences: macOS Gatekeeper is mandatory and kernel-enforced from day one; Windows SmartScreen is advisory and bypassable far more easily. macOS's sandbox for Store apps is stricter than the Windows Store's MSIX container model.

---

## Concepts

### Channel 1 — The Mac App Store

**Trust model:** Apple has human-reviewed the app, Apple servers distribute it, App Review enforces policy. The user trusts Apple's review, not the developer directly.

**Technical enforcement — App Sandbox:** Every MAS app must declare an entitlements plist with the `com.apple.security.app-sandbox` entitlement set to `true`. The kernel enforces this via `Sandbox.kext`/`seatbelt` — the app runs in a container under a mandatory access control policy that restricts filesystem access to:

- Its own container: `~/Library/Containers/<bundle-id>/`
- Files the user explicitly hands it (via Open/Save panels or drag-and-drop, mediated by PowerBox)
- Specific entitlement-gated directories (e.g., `com.apple.security.files.user-selected.read-write` for user-chosen files, `com.apple.security.files.downloads.read-write` for `~/Downloads`)

Apps cannot access arbitrary filesystem paths, other apps' containers, or system internals without an explicit entitlement. This is what makes the sandbox simultaneously the *feature* (safety) and the *limitation* (capability ceiling). An app that needs to read arbitrary files — a disk utility, a terminal emulator, a developer tool — simply cannot live in the MAS in useful form without defeating its own purpose.

**Additional entitlements gate additional capabilities:**
- `com.apple.security.network.client` / `.server` — network
- `com.apple.security.device.camera`, `.microphone` — hardware
- `com.apple.security.automation.apple-events` — restricted AppleScript targets

Apps with unusually broad entitlements (e.g., `com.apple.security.temporary-exception.*` for legacy compat) are possible but reviewed with extra scrutiny.

**Receipt validation:** Purchases are tied to your Apple ID. The receipt file lives at `<App>.app/Contents/_MASReceipt/receipt` and is a PKCS#7-signed CMS blob. At launch, `StoreKit` validates it against the hardware UUID (so a receipt extracted from one Mac won't work on another without re-downloading). This is what powers Family Sharing — you share the license, not the binary.

**On-disk location:** `/Applications/<App>.app` for most; the MAS installs directly there.

**Auto-update:** Managed by the App Store daemon (`storedownloadd`, `commerce`, `appstoreagent`). Updates appear in the App Store app under Updates. There is no per-app update binary shipped.

**Where the MAS fails power users:**

| Limitation | Root cause |
|---|---|
| No kernel extensions (deprecated anyway, but still) | Sandbox + SIP |
| No clipboard monitoring without permission prompt | Entitlement required, Apple often rejects |
| Cannot control other apps via Accessibility without user grant | Sandboxed entitlement gated |
| Versions sometimes lag direct-download builds | Developer ships MAS version separately; sandbox requires code changes |
| Some apps ship a crippled MAS edition alongside a capable direct build | e.g., BBEdit, Proxyman, many dev tools |

**The `mas` CLI:** `brew install mas` gives you a scriptable interface:

```bash
mas search "1Password"          # search the store, returns app IDs
mas install 1333542190          # install by App Store numeric ID
mas upgrade                     # upgrade all MAS apps
mas list                        # all MAS-installed apps with IDs
mas outdated                    # apps with pending updates
mas purchase 1333542190         # initiate a purchase (opens store for free apps)
```

`mas` authenticates through the existing signed-in Apple ID in System Settings → Apple Account. It cannot make paid purchases programmatically — `mas purchase` opens the App Store for confirmation. You must already own the app to `mas install` it.

> 🔬 **Forensics note:** MAS apps leave a rich artifact trail. `/Library/Receipts/com.apple.dt.Xcode.bom` style receipts are less relevant here; what matters is `~/Library/Containers/<bundle-id>/` (the sandbox container — examine this for user data even after app deletion), `~/Library/Caches/com.apple.appstoreagent/` (download history), and the receipt at `<App>.app/Contents/_MASReceipt/receipt`. The `installhistory.plist` at `/Library/Receipts/InstallHistory.plist` logs MAS installs with timestamps.

---

### Channel 2 — Direct download from the developer

**Trust model:** You trust the developer's signing certificate (Developer ID Application, issued by Apple after account verification) and Apple's notarization stamp (automated malware scan + code-sign check). The chain is: Developer → Apple's notarization service → your Mac.

**The .dmg / .pkg / .zip triad:**

| Format | Mechanism | What it installs | Notes |
|---|---|---|---|
| `.dmg` | Disk image, user drags app to `/Applications/` | Single `.app` bundle | Most common for GUI apps; no installer script |
| `.pkg` | macOS Installer package, runs `preinstall`/`postinstall` scripts | Arbitrary paths, may touch system dirs | Used by Apple, enterprise, anything needing root; `pkgutil --bom` to inspect |
| `.zip` | Plain archive, Safari/Chrome auto-expands | `.app` or CLI tools | Common for GitHub releases; no GUI installation |

**Gatekeeper and notarization — the enforcement path:**

1. You download a file. The downloading app (Safari, Chrome, curl, etc.) calls `quarantine_file()` in `libquarantine`, which stamps the extended attribute `com.apple.quarantine` onto the file.
2. The xattr value is a colon-delimited string encoding: quarantine flags, an epoch timestamp, the quarantining app's bundle ID, a UUID, and the originating URL (in some contexts). Example: `0083;65f1a2b4;com.apple.Safari;2A3B4C5D-...`
3. On first launch, `LaunchServices` sees the quarantine bit and invokes `Gatekeeper` (user-space daemon `syspolicyd`). Gatekeeper calls `Security.framework` to:
   - Verify the code signature against Developer ID Application cert chain
   - Check the notarization ticket (either stapled into the binary or looked up online from `api.apple-enhancedruntime.com`)
   - Consult `XProtect` for known-bad signatures
4. If all checks pass, Gatekeeper removes the quarantine bit and allows launch.
5. If the app is unsigned or un-notarized: the dialog says "cannot be opened because Apple cannot check it for malicious software."

**What "not sandboxed" actually means:** Direct-download apps compiled with Developer ID but without the `com.apple.security.app-sandbox` entitlement run with your full user privileges — they can read any file you can read, write anywhere you can write, spawn subprocesses, install LaunchAgents, watch the clipboard, intercept input, etc. This is what makes them more *capable* but also more *dangerous*. You are trusting the developer's intentions and Apple's signing infrastructure, not a technical constraint.

**Sparkle — the de facto auto-updater:** The majority of direct-download macOS apps use [Sparkle](https://sparkle-project.org/), an open-source update framework. Sparkle:
- Polls an RSS/Atom "appcast" feed (a developer-hosted XML file)
- Verifies Ed25519 (EdDSA) signatures on downloaded updates
- Supports delta updates (binary diffs, not full re-downloads)
- Has its own XPC helper (`Sparkle Updater.app` inside the bundle) that handles the privileged file-replace step without requiring the main app to run as root

The update binary is sandboxed in its XPC service even if the main app is not — a thoughtful design. When Sparkle checks for updates, look for `SUFeedURL` in the app's `Info.plist`.

> 🔬 **Forensics note:** The `com.apple.quarantine` xattr is your single most important download provenance artifact. Use `xattr -p com.apple.quarantine <file>` to read it. The timestamp field is Unix epoch hex. Tools like `mdls -name kMDItemWhereFroms` (Spotlight metadata) often preserve the source URL even longer than the quarantine flag. The `ExecPolicy` SQLite database at `/var/db/SystemPolicy` records every Gatekeeper assessment with a timestamp, the binary's SHA-256, and the policy outcome — this is your authoritative "was this app ever run and did Gatekeeper approve it?" log.

---

### Channel 3 — Homebrew Cask (the power-user default)

Homebrew is a package manager, and its Cask extension manages GUI `.app` bundles alongside CLI tools. At its core, a Cask is a Ruby DSL file in the `homebrew/cask` tap that describes exactly how to download, verify, and install a specific app — using the same `.dmg`/`.pkg`/`.zip` the developer distributes directly, just automated.

**Installation:**

```bash
brew install --cask firefox
brew install --cask iterm2
brew install --cask visual-studio-code
```

Internally, `brew install --cask` downloads the artifact to `$(brew --cache)`, verifies a SHA-256 hash baked into the Cask formula, extracts/mounts it, copies the `.app` to `/Applications/`, and records the install in Homebrew's JSON database at `$(brew --prefix)/var/homebrew/`.

**The formula audit trail:** Every Cask is a file in the tap's git history. `brew cat --cask firefox` shows the current formula. To see exactly what version was installed when, `brew info --cask firefox --json=v2 | jq .`. The cask formula pins an exact version and SHA-256; if the developer modifies the binary post-release (supply-chain tampering), the hash fails and the install aborts.

**The auto-update collision problem:** This is the most important nuance for power users.

Many apps (Chrome, Firefox, 1Password, Dropbox) ship their own background updater. Homebrew marks their cask with `auto_updates true`. Historically `brew upgrade` would skip these — your Chrome would update itself to v130 while Homebrew still thought you had v128, and `brew upgrade` would then attempt a "downgrade" to v128.

The current behavior (as of late 2025):
- `brew upgrade` — skips `auto_updates true` casks by default
- `brew upgrade --greedy` — upgrades everything including self-updating apps
- `brew upgrade --greedy-latest` — more conservative greedy (skips `version :latest` casks)
- `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1` — opt-out env var to restore old behavior

For apps without built-in updaters (Little Snitch, BBEdit, etc.), `brew upgrade --cask` is how you keep them current. For apps with updaters, `brew upgrade --greedy` is the "I want Homebrew as the single source of truth" approach.

**Uninstalling via Cask:**

```bash
brew uninstall --cask firefox         # removes /Applications/Firefox.app
brew uninstall --cask --zap firefox   # removes app + all associated files
                                       # (Cask "zap" stanza lists every known artifact)
```

The `--zap` flag is what makes Homebrew actually clean — it uses the Cask's `zap` stanza (if defined) to remove `~/Library/Application Support/<App>/`, `~/Library/Caches/<App>/`, `~/Library/Preferences/<bundle-id>.plist`, LaunchAgents, etc. Compare this to MAS uninstall (drag to Trash leaves all container data) or direct-download uninstall (entirely manual or requires AppCleaner).

> 🔬 **Forensics note:** Homebrew's install database at `$(brew --prefix)/var/homebrew/linked/` and the JSON files in `$(brew --prefix)/Cellar/` record install times and versions. For Apple Silicon the prefix is `/opt/homebrew`; for Intel it was `/usr/local`. Check both if analyzing a machine with a mixed history or Rosetta overlap. The cask download cache at `$(brew --cache)/downloads/` often retains old `.dmg` files — these are your copy of exactly what was installed.

**`brew bundle` and the Brewfile:** This is the "dotfiles for apps" pattern. A `Brewfile` in your home dir or repo captures your entire software stack:

```ruby
# Brewfile
tap "homebrew/bundle"
tap "homebrew/cask-fonts"

# CLI tools
brew "mas"
brew "git"
brew "ripgrep"
brew "fd"
brew "jq"

# GUI apps via Cask
cask "iterm2"
cask "visual-studio-code"
cask "firefox"
cask "little-snitch"

# Mac App Store apps (requires mas)
mas "Reeder 5.", id: 1529448980
mas "1Password 7", id: 1333542190
mas "Craft", id: 1487937127

# VSCode extensions
vscode "eamodio.gitlens"
```

Commands:
```bash
brew bundle install              # install everything in ./Brewfile
brew bundle install --global     # install from ~/.Brewfile
brew bundle dump                 # generate Brewfile from current installs
brew bundle check                # check if everything is installed
brew bundle cleanup --force      # uninstall anything NOT in Brewfile
```

This is how you reproduce a full Mac setup after a fresh install, or audit drift between two machines.

---

### Channel 4 — Outside the gate: unsigned, un-notarized, self-built

This covers three distinct scenarios:

**A. Apps signed with Developer ID but not notarized** (increasingly rare post-2021 when Apple made notarization mandatory for Gatekeeper to allow launch at all on recent macOS). These are usually old apps that predate the requirement or were built by a developer who skipped notarytool.

**B. Completely unsigned apps** — open-source tools you've compiled yourself from source, internal enterprise tools signed with a private cert, or old abandonware.

**C. Apps with a valid notarization but `spctl` assessment fails** for other reasons (revoked cert, quarantine attribute was added by a tool that misidentified the source).

**How to run an app you've decided to trust:**

Method 1 — Settings UI (the safe path, one-time grant):
1. Attempt to open the app. Gatekeeper blocks it.
2. Open System Settings → Privacy & Security → scroll to the bottom.
3. The blocked app appears with an "Open Anyway" button. Click it, authenticate.
4. Gatekeeper records this in `syspolicyd`'s database and won't ask again.

Method 2 — `xattr -d` (the power-user path, understand what you're doing):
```bash
xattr -d com.apple.quarantine /Applications/SomeTool.app
# or for a downloaded archive before extraction:
xattr -d com.apple.quarantine ~/Downloads/SomeTool.dmg
```

This removes the quarantine bit, so Gatekeeper never fires. The app will open as if you downloaded it from a trusted source. **Only do this if you obtained the binary through a channel you trust** (the developer's own GitHub releases, your own compilation, internal distribution).

Method 3 — `codesign` self-signing (for unsigned tools that need to run as-is):
```bash
codesign --force --deep --sign - /Applications/SomeTool.app
```
The `-` signs with an ad-hoc identity (your machine's local key, not a Developer ID cert). This satisfies macOS's requirement that all apps be code-signed (introduced in macOS 10.15 Catalina) without needing an Apple Developer account. It does not notarize.

> ⚠️ **ADVANCED / DESTRUCTIVE:** Removing the quarantine attribute bypasses Apple's malware check for that specific file. Gatekeeper is not infallible, but it does catch known-bad binaries via XProtect signatures. Only remove quarantine from binaries whose provenance you can verify independently — GitHub releases with a matching SHA-256, your own builds, or software from a developer you've assessed.

**App Store vs direct version differences:** Several high-profile apps ship two distinct editions:

| App | MAS edition | Direct edition |
|---|---|---|
| BBEdit | Full features but some scripting limitations | Full AppleScript + CLI tools |
| Proxyman | No network extension (sandbox can't install KEXTs) | Full SSL proxying with system extension |
| Little Snitch | Not available on MAS at all | Network monitor requires NEFilterDataProvider entitlement that Apple doesn't grant to MAS apps |
| Amphetamine | On MAS | — |
| CleanMyMac | Both, but direct has more system-level cleanup | — |

When a developer ships both, the direct version typically has broader OS capabilities because it isn't boxed by the sandbox. The versions sometimes also diverge in update frequency — developers control their own release cadence for direct downloads, while MAS releases go through App Review (days to weeks).

---

## Choosing a channel

```
           ┌─────────────────────────────────────────────────────────────┐
           │   DO I TRUST THE DEVELOPER AND THIS SPECIFIC BINARY?        │
           └──────────────────┬──────────────────────────────────────────┘
                              │ Yes
                              ▼
           ┌──────────────────────────────────────────────────────────────┐
           │   IS IT A GUI APP or a CLI/library tool?                     │
           └──────┬───────────────────────────────────────┬───────────────┘
                  │ GUI app                               │ CLI/lib
                  ▼                                       ▼
   ┌──────────────────────────┐              ┌────────────────────────┐
   │  Is it on Homebrew Cask? │              │  brew install <tool>   │
   └──────┬────────┬──────────┘              └────────────────────────┘
          │ Yes    │ No
          ▼        ▼
  brew install   Direct .dmg/.pkg          
  --cask <app>   from developer            
  (audit trail,  (if Cask lags or          
  easy uninstall  app isn't casked)         
  via --zap)                                
          │
          ▼
  Is the app capability-limited by MAS sandbox
  AND available in a more capable direct build?
  → Prefer direct or Cask
  Otherwise → either is fine; MAS gets you
  auto-update managed by macOS and receipt-based
  license portability
```

**Update unification:** The real pain is keeping four update pathways from stepping on each other. A pragmatic strategy:

1. `brew upgrade --greedy` weekly (via `launchd` or `brew autoupdate`) — handles Cask apps
2. `mas upgrade` weekly — handles MAS apps  
3. Let Sparkle handle direct-download apps that aren't Casked
4. For everything not in Homebrew: use `topgrade` (wraps `brew`, `mas`, and dozens of other package managers into one command)

---

## Hands-on (CLI & GUI)

**Inspect an installed app's provenance:**
```bash
# How did this app arrive?
xattr -l /Applications/Firefox.app          # look for com.apple.quarantine
spctl --assess -vv /Applications/Firefox.app  # Gatekeeper's verdict
codesign -dvv /Applications/Firefox.app       # signing details, team ID
pkgutil --pkgs | grep -i firefox            # was it installed via .pkg?

# MAS-installed app?
ls ~/Library/Containers/                    # sandbox container exists?
cat "/Applications/Firefox.app/Contents/_MASReceipt/receipt" 2>/dev/null \
  | xxd | head -5                           # binary receipt means MAS

# Homebrew-installed?
brew list --cask | grep firefox
brew info --cask firefox
```

**Check what a .pkg actually does before running it:**
```bash
pkgutil --expand somefile.pkg /tmp/pkg-inspect/
ls /tmp/pkg-inspect/                        # Scripts/, Payload
cat /tmp/pkg-inspect/Scripts/postinstall    # what does the installer run as root?
```

**Find all quarantine xattrs recursively (useful on a forensic image):**
```bash
find /Applications -xattrname com.apple.quarantine 2>/dev/null
xattr -p com.apple.quarantine /Applications/SomeTool.app
# Output: 0083;65f1a2b4;com.apple.Safari;UUID
# Field 1: flags (0083 = FILE_QUARANTINE_WAS_DOWNLOADED)
# Field 2: timestamp (hex Unix epoch)
# Field 3: quarantining app bundle ID
# Field 4: event UUID
```

**Check Gatekeeper's assessment database (requires root):**
```bash
sudo sqlite3 /var/db/SystemPolicy "SELECT * FROM authority ORDER BY rowid DESC LIMIT 20;"
# Columns: type, allow, disabled, label, filter_unsigned, require_lv, priority,
#          id, ctime, mtime, label, requirement, comment, expires
```

**Inspect Homebrew's download cache for forensics:**
```bash
ls -lh "$(brew --cache)/downloads/"         # cached .dmg/.zip files with SHA hashes
brew info --cask --json=v2 visual-studio-code | jq '.[] | {version, sha256, url}'
```

---

## Labs

### Lab 1 — Install the same app via Cask vs direct; compare artifacts

> ⚠️ **ADVANCED:** This lab installs and uninstalls real apps. Back up your `/Applications` folder with `ditto /Applications ~/Desktop/Applications-backup` before starting. Rollback: `brew uninstall --cask --zap <app>` or drag the app to Trash.

We'll use Firefox as the example (you can substitute any app available both ways).

```bash
# Step 1: Install via Cask
brew install --cask firefox

# Step 2: Examine what Cask installed
ls -la /Applications/Firefox.app
xattr -l /Applications/Firefox.app
codesign -dvv /Applications/Firefox.app
brew info --cask firefox | head -20

# Step 3: Check quarantine status (Cask strips it on install)
xattr -p com.apple.quarantine /Applications/Firefox.app 2>/dev/null \
  && echo "QUARANTINED" || echo "No quarantine xattr (expected for Cask install)"

# Step 4: Uninstall via Cask
brew uninstall --cask firefox

# Step 5: Download directly from mozilla.org
# (Download Firefox.dmg manually from https://www.mozilla.org/firefox/)
# Then inspect before mounting:
xattr -l ~/Downloads/Firefox*.dmg        # com.apple.quarantine is present
xattr -p com.apple.quarantine ~/Downloads/Firefox*.dmg

# Step 6: Mount and install normally
open ~/Downloads/Firefox*.dmg
# Drag Firefox to /Applications when prompted

# Step 7: Compare quarantine state
xattr -l /Applications/Firefox.app       # quarantine xattr IS present this time
spctl --assess -vv /Applications/Firefox.app  # Gatekeeper assesses it

# First launch: Gatekeeper fires, assesses, then removes quarantine bit
open /Applications/Firefox.app
xattr -l /Applications/Firefox.app       # quarantine bit is now gone

# Step 8: Compare what's left to clean up
# Direct install: you need AppCleaner or manual cleanup
# Cask install would have had: brew uninstall --cask --zap firefox
```

**Expected findings:** Cask-installed apps have no quarantine xattr (Homebrew strips it after verifying SHA-256); directly downloaded apps carry the quarantine bit until first launch or manual removal.

---

### Lab 2 — Write a Brewfile for your personal stack

> ⚠️ **Non-destructive.** `brew bundle install` is additive only (won't remove existing apps). `brew bundle cleanup --force` IS destructive — don't run it until you've verified the Brewfile captures everything you want.

```bash
# Step 1: Generate a Brewfile from your current install state
brew bundle dump --file ~/Desktop/Brewfile-current --force
cat ~/Desktop/Brewfile-current

# Step 2: Inspect and annotate
# The generated file groups: taps, brews, casks, mas entries
# mas entries require you to already have mas installed: brew install mas

# Step 3: Get App Store IDs for your MAS apps
mas list
# Output: <ID>   <App Name>   (<version>)

# Step 4: Create a curated ~/.Brewfile
cat > ~/.Brewfile << 'EOF'
tap "homebrew/bundle"

# Core CLI utilities
brew "mas"
brew "git"
brew "ripgrep"
brew "fd"
brew "jq"
brew "fzf"
brew "bat"

# GUI apps
cask "iterm2"
cask "visual-studio-code"
cask "little-snitch"
cask "rectangle"

# App Store apps — substitute real IDs from `mas list`
# mas "1Password 7", id: 1333542190
# mas "Reeder 5.", id: 1529448980
EOF

# Step 5: Test idempotency
brew bundle check --global      # reports what's installed vs what's in Brewfile
brew bundle install --global    # installs anything missing; no-ops for existing

# Step 6: Simulate a new machine setup
brew bundle install --global --no-upgrade   # install-only, don't upgrade existing
```

**Commit your `~/.Brewfile` to your dotfiles repo.** It's the single-file answer to "what software do I run?"

---

### Lab 3 — Safely run an un-notarized app you trust

> ⚠️ **ADVANCED / DESTRUCTIVE risk:** Removing the quarantine attribute bypasses Gatekeeper's malware check. Only perform this on a binary whose source you have independently verified. Do not do this with a binary you can't account for.

For this lab, build a simple tool from source (so you know exactly what it is):

```bash
# Option A: Build something trivial yourself
cat > /tmp/hello.c << 'EOF'
#include <stdio.h>
int main() { printf("hello from an unsigned binary\n"); return 0; }
EOF
clang -o /tmp/hello /tmp/hello.c

# This binary is unsigned — try to run it:
/tmp/hello      # works fine for CLI tools; macOS checks sandbox on .app bundles, not plain executables

# For a proper unsigned .app test — wrap it:
mkdir -p /tmp/HelloApp.app/Contents/MacOS
cp /tmp/hello /tmp/HelloApp.app/Contents/MacOS/HelloApp
# Gatekeeper doesn't fire on .app in /tmp; move to /Applications:
sudo cp -r /tmp/HelloApp.app /Applications/

# Option B: Test with a real un-notarized older app you trust
# (e.g., an old open-source tool from GitHub that predates notarization)

# Check its state:
codesign --verify /Applications/HelloApp.app 2>&1   # "not signed" or "no identity"
spctl --assess /Applications/HelloApp.app 2>&1       # "rejected"

# METHOD 1: System Settings → Privacy & Security → Open Anyway (GUI)
open /Applications/HelloApp.app    # triggers the block dialog
# Then: System Settings → Privacy & Security → scroll to bottom → Open Anyway

# METHOD 2: xattr removal (command line)
xattr -d com.apple.quarantine /Applications/HelloApp.app 2>/dev/null || true
# Note: if the app was never quarantined (built locally, copied with ditto), 
# the quarantine xattr may already be absent

# METHOD 3: Ad-hoc self-sign (for apps that need to satisfy code-signing requirements)
codesign --force --deep --sign - /Applications/HelloApp.app
codesign --verify /Applications/HelloApp.app  # now "valid on disk"
spctl --assess /Applications/HelloApp.app 2>&1 # still "rejected" (no notarization)
# But macOS will let it launch after the Settings "Open Anyway" grant

# Rollback:
sudo rm -rf /Applications/HelloApp.app
```

> 🔬 **Forensics note:** The "Open Anyway" click is recorded in `syspolicyd`'s database (`/var/db/SystemPolicy`). Even if the quarantine xattr is later removed, the policy database entry persists, recording that a user explicitly allowed an un-notarized app. This is strong evidence of intentional bypass.

---

## Pitfalls & gotchas

**The version drift trap with Cask + Sparkle:** If you install Chrome via Cask and Chrome auto-updates itself to v130, then `brew upgrade --cask chrome` (without `--greedy`) skips it. But `brew info --cask google-chrome` shows the Cask formula is at v128. Run `brew upgrade --greedy` periodically or use `HOMEBREW_AUTO_UPDATE_SECS=86400` to keep Homebrew's metadata current.

**MAS apps and sandboxed containers survive uninstall:** Dragging a MAS app to Trash removes the `.app` bundle but leaves `~/Library/Containers/<bundle-id>/` intact (often gigabytes of data). Use `brew install --cask appcleaner` or manually nuke the container after confirming you don't need the data.

**`spctl --master-disable` is gone on Sequoia 15.x:** The old `sudo spctl --master-disable` that enabled "Allow apps from Anywhere" in System Preferences was removed (actually removed in Ventura for most users, fully gone in Sequoia). You cannot globally disable Gatekeeper on a stock macOS 26 system. The per-app "Open Anyway" flow is the only supported route.

**`xattr -d` on an `.app` bundle vs its executable:** The quarantine attribute lives on the `.app` directory itself (and propagates to all files inside during extraction). Running `xattr -d com.apple.quarantine /Applications/SomeTool.app` is sufficient; you don't need to recurse with `-r` for the quarantine removal case (though `-r` doesn't hurt).

**Homebrew Cask vs direct: same binary, different trust chain:** A Cask formula verifies the SHA-256 of the artifact it downloads. But the Cask formula itself lives in a git repo (`homebrew/cask`) that you've implicitly trusted by running `brew`. The trust chain is: you trust Homebrew maintainers → they audit formula PRs → formula pins a specific URL + SHA-256. This is auditable in git history; a direct download is a point-in-time trust decision.

**MAS version vs direct version feature parity:** Always check the developer's website before buying on the MAS. Many developers explicitly document which features are MAS-only absent. The BBEdit website maintains a "Features exclusive to the direct download edition" page. Same for Proxyman, CleanMyMac, and others.

**`pkg` installers run arbitrary code as root:** A `.pkg` can contain `preinstall` and `postinstall` shell scripts that execute as root during installation. `pkgutil --expand` and reading those scripts before running an installer is a professional habit, especially for software from less-established sources. The macOS Installer app does not show you these scripts.

---

## Key takeaways

1. The four distribution channels — MAS, direct download, Homebrew Cask, and ungated — represent a spectrum from "Apple controls everything" to "developer (or you) controls everything," with proportional capability and risk at each step.

2. The App Sandbox is the MAS's defining constraint: container-isolated, entitlement-gated, incapable of system-level power. This is why all the serious sysadmin and security tools live outside it.

3. Developer ID + notarization is the trust handshake for direct downloads. The `com.apple.quarantine` xattr is how that trust check is triggered; its presence, timestamp, and originating-app ID are primary forensic artifacts for reconstructing software provenance.

4. Homebrew Cask wraps the same direct-download binaries in a reproducible, auditable, easily-uninstallable layer. `brew install --cask --zap` is the closest macOS gets to a real uninstaller. A `Brewfile` + `mas` + `brew bundle` is the correct answer to "how do I document and reproduce my Mac setup."

5. The auto-update collision between Homebrew and an app's built-in Sparkle updater is a real operational headache. Use `brew upgrade --greedy` to let Homebrew win, or be explicit about which channel owns updates for each app.

6. `spctl --master-disable` is gone. Per-app "Open Anyway" or `xattr -d` are the supported paths for un-notarized software you trust. Both leave evidence in `syspolicyd`'s database.

---

## Terms introduced

| Term | Definition |
|---|---|
| **App Sandbox** | Kernel-enforced MAC policy that restricts an app to its container and explicitly granted entitlements; mandatory for all MAS apps |
| **Entitlement** | Plist key declaring a sandbox permission; embedded in a binary's code signature; auditable with `codesign -d --entitlements -` |
| **Developer ID** | Apple-issued code-signing certificate for distributing software outside the MAS; requires an Apple Developer Program account |
| **Notarization** | Apple's automated submission/scan of a binary; produces a signed ticket that Gatekeeper checks on first launch; mandatory since macOS 10.15 |
| **com.apple.quarantine** | Extended filesystem attribute stamped on downloaded files; triggers Gatekeeper assessment on first launch; the key provenance artifact |
| **XProtect** | Apple's on-device malware signature engine; consulted by Gatekeeper; updated silently via Background Task Management |
| **syspolicyd** | User-space daemon implementing Gatekeeper policy; writes to `/var/db/SystemPolicy` SQLite database |
| **Sparkle** | Open-source macOS app update framework; appcast RSS + EdDSA signatures + delta patches; used by most direct-download apps |
| **Homebrew Cask** | Homebrew extension for managing GUI `.app` bundles with formula-pinned SHA-256 verification and `--zap` cleanup |
| **Brewfile** | Ruby DSL file declaring an entire software stack (brews, casks, MAS apps); `brew bundle` installs or checks it |
| **mas** | CLI for the Mac App Store; `brew install mas`; `mas install <id>`, `mas upgrade`, `mas list` |
| **AppCast** | Developer-hosted RSS/Atom XML feed that Sparkle polls for available updates; URL in `Info.plist` key `SUFeedURL` |
| **Receipt** | PKCS#7-signed blob at `<App>.app/Contents/_MASReceipt/receipt` proving purchase; hardware-UUID-bound |
| **ad-hoc signing** | `codesign --sign -` — signs with a local ephemeral identity (no Developer ID), satisfies macOS code-signing requirements without notarization |

---

## Further reading

- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — "App security overview" and "Gatekeeper and runtime protection" chapters
- [Howard Oakley — Gatekeeper and notarization in Sequoia](https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/) — authoritative deep dive, updated through Sequoia
- [Howard Oakley — Quarantine, MACL and provenance](https://eclecticlight.co/2025/12/05/quarantine-macl-and-provenance-what-are-they-up-to/) — the three xattrs that track file origins in modern macOS
- [Sparkle Project documentation](https://sparkle-project.org/documentation/) — EdDSA key setup, appcast format, delta updates
- [Homebrew Bundle documentation](https://docs.brew.sh/Brew-Bundle-and-Brewfile) — official Brewfile syntax reference
- [mas-cli on GitHub](https://github.com/mas-cli/mas) — source, supported commands, known limitations
- [[02-filesystem-layout]] — where all these app artifacts live on disk
- [[05-security-gatekeeper-sip]] — Gatekeeper deep dive: SIP, quarantine propagation, translocation
- [[03-package-management]] — Homebrew formula internals, taps, and CLI tool management
