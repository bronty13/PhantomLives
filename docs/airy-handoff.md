# airy handoff — install & configure the runner services

> **Why this doc:** the code for airy's three new roles (PeekServer host, Swift CI, release runner)
> plus the Xcode install is merged (PR #33), but the **on-airy** steps can't be done from a cloud
> sandbox — they need airy's network, its keychains/secrets, and two **GUI-only** actions. Run this
> on airy itself (Screen Sharing or your own SSH), or from a Claude Code session on a machine that can
> reach airy. Steps are ordered; each ends with a verification. **🖱️ GUI-GATE** marks a step that
> cannot be scripted (Apple ID / System Settings) — do it by hand, then continue.
>
> Companion docs (the "why" behind each): `docs/airy-services-plan.md` (the plan + 256GB budget),
> `docs/dev-id-signing-airy.md` (signing keychain — assumed already done), `docs/releasing-on-airy.md`,
> `docs/archive-runner-setup.md` (base runner setup). This doc is the execution checklist.

## Assumptions (from archive-runner-setup.md Workstream B — do those first if not)

- macOS on airy, `~/dev/PhantomLives` cloned (NOT under `~/Documents`), `git pull` current.
- Homebrew installed; `~/.zprofile` has `eval "$(/opt/homebrew/bin/brew shellenv)"`.
- Remote Login (SSH) on; Vortex's + MB14's public keys in `~/.ssh/authorized_keys`.
- The **signing keychain** is set up (`docs/dev-id-signing-airy.md`): `purple-signing.keychain-db`
  + `~/.config/purple-signing/keychain-pw`. Verify:
  ```sh
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```

---

## 1 — Xcode (Workstream 0)

Needed by the XcodeGen apps + `#Preview` macros and to build/notarize on airy. **Watch the 256GB
budget** — skip simulators (macOS-only apps).

```sh
brew install xcodesorg/made/xcodes
```

**🖱️ GUI-GATE — Apple ID:** `xcodes install` prompts for your Apple ID + 2FA (interactive):
```sh
xcodes install --latest --experimental-unxip     # prompts for Apple ID; downloads + installs
```

Then the scriptable tail:
```sh
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch                        # installs components; no simulators
```

**Verify:**
```sh
xcodebuild -version
( cd ~/dev/PhantomLives/PurpleIRC && ./build-app.sh --no-install )   # should Dev-ID-sign an .app
df -h /                                            # sanity-check remaining free space
```

---

## 2 — PeekServer headless host (Workstream 3)

```sh
cd ~/dev/PhantomLives/PeekServer
brew install ffmpeg                                # video proxies (else it serves originals)
cp -n config.example.json config.json
```

Edit `config.json`:
- `roots` → the actual review trees on airy's drives (e.g.
  `/Volumes/ROG_WHITE/PurpleAttic/NEW PHOTOS TO REVIEW`), correct `label`/`kind`.
- **Set Basic Auth** (don't serve the archive open, even on LAN/Tailscale):
  ```sh
  # generate the hash, then paste into authPasswordSHA256 (and set authUser):
  python3 -c 'import hashlib,getpass;print(hashlib.sha256(getpass.getpass().encode()).hexdigest())'
  ```

**🖱️ GUI-GATE — Full Disk Access:** if a root is on an external/TCC-protected volume, grant FDA to
the interpreter the agent runs as: System Settings ▸ Privacy & Security ▸ Full Disk Access ▸ **+** ▸
⇧⌘G ▸ `/bin` ▸ select **bash** ▸ enable.

Warm the cache once (slow drives), then install the agent:
```sh
./run.sh --warm                                    # one-time cold-cache pass (optional but recommended)
./install-agent.sh --install-agent
./install-agent.sh --status
```

**Verify:**
```sh
curl -u USER:PASS "http://$(hostname -s).local:8788/api/roots"      # 200 + roots JSON
curl -o /dev/null -s -w '%{http_code}\n' "http://$(hostname -s).local:8788/api/roots"  # 401 without auth
tail -n 20 ~/Library/Logs/phantomlives-peekserver.log
# reboot-safe releases the drive: eject-externals boots the agent out first
~/dev/PhantomLives/eject-externals.sh --list
```

---

## 3 — Self-hosted Swift CI runner (Workstream 2)

Registers airy as an Actions runner for `bronty13/PhantomLives`, labeled so `swift-ci.yml` targets it.

**🖱️ (semi-GUI) — registration token:** get a token from GitHub ▸ repo **Settings ▸ Actions ▸
Runners ▸ New self-hosted runner** (macOS/arm64), or via API if you have a PAT. Then:

```sh
mkdir -p ~/actions-runner && cd ~/actions-runner
# download URL/version from that same GitHub page:
curl -o actions-runner-osx-arm64.tar.gz -L <URL_FROM_GITHUB>
tar xzf actions-runner-osx-arm64.tar.gz
./config.sh --url https://github.com/bronty13/PhantomLives \
            --token <REG_TOKEN> \
            --labels self-hosted,macos,xcode \
            --name airy --unattended
./svc.sh install        # launchd service → survives reboot
./svc.sh start
```

**reboot-safe note:** the runner should come back after the `reboot-safe` external-unmount restart —
`svc.sh install` handles RunAtLoad; just confirm it's `Started` after a test reboot.

**Verify:** the runner shows **Idle** on the GitHub Runners page. Then exercise it — push a trivial
change under a CI'd Swift project (e.g. touch a comment in `IRCKit/`) on a branch; `swift-ci.yml`'s
`discover` job should select it and the `test` job should run on airy and go green. (Leave it
**monitor-only** — don't make it a required check until it's proven across a few PRs.)

---

## 4 — Release runner (Workstream 1)

So `release-on-airy.sh` can cut notarized Sparkle releases. Three secrets must be reachable over SSH.

```sh
# 4a. notarytool profile (shared PhantomLives profile). Uses an APP-SPECIFIC password.
xcrun notarytool store-credentials PurpleDedup-Notary \
  --apple-id <APPLE_ID> --team-id SRKV8T38CD --password <APP_SPECIFIC_PW>

# 4b. Sparkle EdDSA key — import the canonical shared PRIVATE key (same one every install trusts):
cd ~/dev/PhantomLives/PurpleMirror && swift package resolve >/dev/null
SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -type d | head -1)"
"$SPARKLE_BIN/generate_keys" -f /path/to/canonical_sparkle_private_key
# export the matching public key in ~/.zprofile so release.sh sees it:
echo 'export SPARKLE_PUBLIC_KEY="<CANONICAL_PUBLIC_KEY>"' >> ~/.zprofile

# 4c. gh auth (for the GitHub release upload):
gh auth login    # or set GH_TOKEN in ~/.zprofile
```

**Login-keychain unlock over SSH.** The notary profile + Sparkle key live in the **login** keychain,
which a fresh SSH session leaves locked. Pick one:
- Simplest — store its password for the wrapper:
  ```sh
  printf '%s' '<LOGIN_KEYCHAIN_PW>' > ~/.config/purple-signing/login-pw && chmod 600 ~/.config/purple-signing/login-pw
  ```
  and pass `LOGIN_KC_PW_FILE=~/.config/purple-signing/login-pw` when releasing.
- Or store the notary profile + Sparkle key in `purple-signing` instead and skip the login-keychain
  password on disk (more setup; see `docs/releasing-on-airy.md`).

**Verify (from Vortex/MB14, or on airy):**
```sh
# dry-ish: builds + skips notarization, proves keychains unlock and env loads
AIRY_SSH=you@airy.local LOGIN_KC_PW_FILE=~/.config/purple-signing/login-pw \
  ALLOW_UNNOTARIZED=1 ~/dev/PhantomLives/release-on-airy.sh PurpleMirror --no-install
# inspect the exact remote script without connecting:
~/dev/PhantomLives/release-on-airy.sh --print-remote PurpleMirror
```

---

## Done-when

- [ ] `xcodebuild -version` works; a `build-app.sh --no-install` Dev-ID-signs; disk has headroom.
- [ ] PeekServer reachable with auth; agent survives an `eject-externals` + reboot cycle.
- [ ] Actions runner **Idle**; a real Swift-project change turns `swift-ci.yml` green on airy.
- [ ] `release-on-airy.sh` completes a notarized release end-to-end (GitHub release URL + appcast push).

## Deferred / see other docs
- Photos Download-Originals seeding, PurpleAttic + Obsidian + brew-autoupdate jobs, Rachel migration,
  Tailscale, PurpleMirror remote-host control → `docs/archive-runner-setup.md`.
- The daily-noon PurpleAttic TCC "Allow" click stays manual (per that doc; not made persistent).
