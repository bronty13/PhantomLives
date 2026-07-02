# airy as a build/CI/media node — Xcode install + three services

> Status: **planned, not yet executed.** Builds on `docs/archive-runner-setup.md` (airy = the
> always-on M1 Air runner). This doc adds the three roles decided on top of the archive/scheduler
> base: **(1) release/notarization runner**, **(2) self-hosted Swift CI**, **(3) permanent PeekServer
> host** — all of which want a real toolchain, so it starts by putting **Xcode** on airy.

## What changes vs. the archive-runner plan

`docs/archive-runner-setup.md` **Decision #2** said: *"build PurpleAttic + PurpleMirror on Vortex and
`ditto` the signed `.app`s to the runner, to avoid ~15GB of Xcode on the 256GB SSD."* Installing Xcode
here **supersedes that decision** — airy becomes self-contained for **build + sign + notarize + test**,
so nothing has to be built on Vortex and dittoed over. When this plan lands, update Decision #2 in the
archive doc to point here.

The signing half is already done: `docs/dev-id-signing-airy.md` set up the `purple-signing` keychain so
Dev-ID `codesign` works non-interactively over SSH. That same Dev-ID identity is what workstream 1 uses
to notarize.

---

## Workstream 0 — Install Xcode (headless-friendly)

**The disk budget is the one real risk** on a 256GB SSD. Rough steady state:

| Consumer | Approx |
|---|---|
| macOS (Tahoe 26) + system | ~30 GB |
| System Photo Library (Download Originals) | ~97 GB |
| Xcode (macOS platform only, no iOS/watchOS/tvOS simulators) | ~20 GB |
| DerivedData + per-project `.build/` across the Swift subprojects | 20–40 GB |
| **Free headroom** | **~70–90 GB** |

Workable, but Photos-at-97GB **and** Xcode is the squeeze. Mitigations, in order of preference:

1. **Do not download simulator runtimes.** All PhantomLives apps are macOS-only — skip iOS/watchOS/tvOS
   platforms entirely. This is the single biggest saving (~10–20 GB).
2. **Relocate/clear DerivedData aggressively** — `~/Library/Developer/Xcode/DerivedData` and per-project
   `.build/` are disposable; a scheduled cleanup keeps them bounded.
3. **Revisit whether airy needs full Download-Originals Photos.** PurpleAttic exports *from* the library,
   so it needs the originals to seed the archive — but once the append-only steady state is reached, this
   is worth re-checking against actual free space. (Do **not** change this unilaterally; it's the archive
   authority — coordinate before touching.)

**Install method — use `xcodes`, not the App Store**, because airy is headless (SSH):

```sh
brew install xcodesorg/made/xcodes    # already have brew per archive-runner Workstream B
xcodes install --latest --experimental-unxip   # prompts for Apple ID; downloads + installs
sudo xcode-select -s /Applications/Xcode.app   # point the toolchain at full Xcode
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch                      # installs required components, no simulators
```

**Why full Xcode (not just Command Line Tools):** the XcodeGen apps (MusicJournal, Timeliner, PurplePeek's
GRDB build, etc.) and `#Preview` macros need full Xcode — see `docs/swift-build-prerequisites.md`. Also,
`run-tests.sh` wrappers add a Command-Line-Tools `Testing.framework` rpath hack that becomes a **no-op once
full Xcode is present** (plain `swift test` resolves Testing) — so workstream 2 gets simpler, not harder.

**Verify:** `xcodebuild -version` and a throwaway `cd PurpleIRC && ./build-app.sh --no-install` producing a
Dev-ID-signed `.app` (freshness proof per CLAUDE.md).

---

## Workstream 1 — Release / notarization runner

**Goal:** cut Sparkle releases from airy so it doesn't tie up Vortex, reusing the Dev-ID identity already
on the box. Eight apps ship via `Scripts/release.sh` (PurpleMark, PurpleIRC, PurpleDiary, PurpleMirror,
PurpleArchive, Ircle, PurpleDedup) + `PurpleChef/scripts/release.sh`.

`release.sh` already declares itself run-from-either-Mac; its per-machine prerequisites (from the script's
own preflight) are what airy must satisfy:

1. **Developer ID Application cert** in a codesigning-visible keychain — airy has this via `purple-signing`.
   ⚠️ `release.sh` reads it from the **login** keychain (`security find-identity -v -p codesigning`), while
   the airy signing setup lives in `purple-signing.keychain-db`. **Reconcile this:** either add
   `purple-signing` to the search list so `find-identity` sees it (it's already added per
   `dev-id-signing-airy.md` step 2's `list-keychains`), or teach `release.sh` to honor `SIGN_KEYCHAIN` like
   `build-app.sh` does. Confirm `security find-identity -v -p codesigning` returns the Dev-ID over SSH before
   trusting a release.
2. **notarytool profile** `PurpleDedup-Notary` (the shared PhantomLives profile) in the login keychain:
   `xcrun notarytool store-credentials PurpleDedup-Notary --apple-id … --team-id SRKV8T38CD --password <app-specific-pw>`.
   Uses an **app-specific password**, not the account password.
3. **`gh` authenticated** — `gh auth login` (or a `GH_TOKEN`).
4. **Sparkle EdDSA key:** `SPARKLE_PUBLIC_KEY` exported in the shell rc **and** the matching private key
   imported into airy's keychain (`generate_keys -f` with the canonical key). `release.sh` hard-fails on a
   key mismatch, so installs would reject an update signed with the wrong key — get this exactly right.
5. **Clean git state** — `release.sh` requires on-`main`, clean, pushed (or `ALLOW_DIRTY=1`). airy's
   `~/dev/PhantomLives` checkout must be current.

**Ergonomics — a thin wrapper:** add `release-on-airy.sh <subproject> [version]` at repo root that SSHes to
airy, `git pull`s, and runs the subproject's `Scripts/release.sh`, mirroring how `build-app.sh` already
Dev-ID-signs over SSH. Then a release from any Mac is one command.

**Built (✅):** `release-on-airy.sh` + `docs/releasing-on-airy.md` + `tests/test_release_on_airy.sh`.
The `release.sh` preflight turned out to be **7 diverged copies**, not one shared file, so rather than a
`SIGN_KEYCHAIN`-aware patch to each (risking the working Vortex/MB14 flow), the wrapper **unlocks the
keychains centrally** before calling the unchanged `release.sh` — `purple-signing` is already in the
keychain search list (`dev-id-signing-airy.md` step 2), so `find-identity` sees the Dev-ID once unlocked.
The keychain/notary/Sparkle-key setup steps remain GUI/account actions that must happen on airy.

---

## Workstream 2 — Self-hosted Swift CI (GitHub Actions runner)

**Goal:** free CI on push/PR for the Swift suites that can only run on macOS — Ircle (135), IRCKit (92),
PurpleMark (66), PurplePeek (21), PurpleIRC, SlackSucker, PurpleAttic, PurpleMirror, Timeliner, etc. Each
has a `run-tests.sh`; with full Xcode present those wrappers reduce to plain `swift test`/`xcodebuild test`.

**Setup on airy:**
1. Register a **self-hosted runner** scoped to `bronty13/PhantomLives`
   (`Settings → Actions → Runners → New self-hosted runner`, macOS/arm64). Install it as a launchd service
   (`svc.sh install && svc.sh start`) so it survives reboot — coordinate with `reboot-safe` (the runner
   should come back up after the external-unmount restart dance).
2. **Label it** `self-hosted, macos, xcode` so workflows can target it and it never competes with
   GitHub-hosted runners.

**Workflow — `.github/workflows/swift-ci.yml`** (I can write this now): on `pull_request` + `push`, a matrix
over the SwiftPM subprojects, each job `cd <proj> && ./run-tests.sh`, `runs-on: [self-hosted, macos, xcode]`.
Key design choices, called out so nothing silently under-runs:
- **`paths:` filters per project** so a change in one subproject doesn't rebuild all ~20 (the monorepo has no
  top-level build — CLAUDE.md). Use per-project path filters or `dorny/paths-filter` to select the matrix.
- **Concurrency = 1** (or a small cap) — one 16GB Air; `concurrency:` group per project + cancel-in-progress.
- **Disk hygiene** — a post-job step clearing `.build/` and old DerivedData so CI doesn't eat the SSD (ties
  back to Workstream 0's budget). **Log what's cleared** — no silent truncation.
- **Secrets:** none needed for `swift test`. The runner must NOT be exposed to untrusted forks (a self-hosted
  runner runs arbitrary PR code) — restrict to `pull_request` from the same repo / trusted actors, not
  `pull_request_target` from forks. PhantomLives is single-maintainer, so this is low-risk but state it.

**Start monitor-only:** land the workflow reporting status checks first; don't gate merges on it until it's
proven stable across a few real PRs.

---

## Workstream 3 — Permanent PeekServer host

**Goal:** run PeekServer (currently 0.7.2 — video proxies, `/display` tier, ffmpeg transcode) headless on
airy, serving the archive **"NEW …TO REVIEW"** trees so triage works from any device over Tailscale — no
Vortex, no drive shuffling. airy already has the drives (ROG_WHITE/LACIE) and the review folders, and
`config.example.json`'s `warmOrder` already anticipates an `ROG_AIRY/Rachel` path.

**What exists / what's missing:**
- ✅ `run.sh` (pure-stdlib `python3 -m peekserver`), `config.example.json`, ffmpeg staging fix already in
  (commit `855ed1e` — stage video to internal disk before ffmpeg to dodge the launchd TCC hang).
- ❌ **No launchd agent** — PeekServer has no `install-agent`/plist yet. This is the main gap: it needs a
  keep-alive service so it runs unattended and restarts on crash/reboot.

**Plan:**
1. **Config** — copy `config.example.json` → `config.json` on airy; point `roots` at the actual review trees
   on airy's drives (`/Volumes/ROG_WHITE/PurpleAttic/NEW PHOTOS TO REVIEW`, the Rachel trees when that
   migrates). `bind: 0.0.0.0`. **Set `authUser` + `authPasswordSHA256`** — even on LAN + Tailscale, don't
   serve the photo archive open. `brew install ffmpeg` for the proxies (archive-runner Workstream B installs
   most deps; add ffmpeg).
2. **launchd agent** (I can build now, mirroring `sync-md-to-obsidian.sh --install-agent` and the PurpleAttic
   plist pattern): a `com.phantomlives.peekserver` plist that `exec`s `run.sh`, `KeepAlive` true,
   `RunAtLoad` true, logs to `~/Library/Logs/PeekServer/`, bootstrapped into `gui/<uid>`. Add
   `--install-agent [--interval]` / `--uninstall-agent` to a small installer next to `run.sh`.
   - **TCC:** reading the external review folders needs Full Disk Access on the launchd-spawned interpreter
     (same class of grant PurpleAttic + the obsidian agent need — `docs/obsidian-sync.md` explains the FDA-on-
     `/bin/bash` pattern). Grant once on airy.
   - **reboot-safe interaction:** PeekServer serving off ROG_WHITE/LACIE means those drives are *in use* —
     `eject-externals`/`reboot-safe` must stop the PeekServer agent **before** unmounting, or the eject fails
     (and re-invites the Tahoe unmount-hang from `docs/reboot-hangs.md`). Add a `launchctl bootout` of the
     PeekServer label to the `eject-externals` preflight.
3. **Access:** reachable at `http://airy.local:8788` on LAN; over Tailscale from anywhere (Tailscale is
   already on the archive-runner "future" list — this is a reason to actually enable it).
4. **Verify:** agent survives a `reboot-safe` cycle; a video proxy warms and plays; Basic Auth rejects an
   unauthenticated request; PurplePeek in remote mode connects and triages.

---

## Sequencing

1. **Workstream 0 (Xcode)** — blocks 1 and 2; do first, watching the disk budget.
2. **Workstream 3 (PeekServer)** — independent of Xcode (pure Python); can proceed in parallel. The
   launchd agent + `eject-externals` hook are the buildable pieces.
3. **Workstream 1 (release runner)** — after Xcode; mostly keychain/notary/Sparkle-key reconciliation.
4. **Workstream 2 (CI)** — after Xcode; land the workflow monitor-only, then consider gating.

## What can be built now (in-repo, no airy access) vs. on-airy steps

The in-repo column below is all ✅ done. The right column — the on-airy install/configure — is written
up as an ordered, copy-pasteable runbook in **`docs/airy-handoff.md`** (run it on airy; GUI-only gates
flagged). This table is the summary; the handoff is the execution checklist.

| Buildable now (this repo) | Requires airy (GUI/account/hardware) |
|---|---|
| ~~`release-on-airy.sh` wrapper~~ ✅ done — unlocks keychains centrally, so no per-app `release.sh` edit was needed | Install Xcode; accept license; skip simulators |
| ~~`.github/workflows/swift-ci.yml` (self-hosted, path-filtered matrix)~~ ✅ done | Register + launchd-install the Actions runner |
| ~~PeekServer launchd plist + `install-agent`/`uninstall-agent` installer~~ ✅ done (`PeekServer/install-agent.sh`) | notarytool profile, Sparkle private key, Apple ID |
| ~~`eject-externals` PeekServer-bootout hook~~ ✅ done | Grant FDA on airy; write `config.json`; Tailscale |
| ~~`docs/releasing-on-airy.md`~~ ✅ done | The daily-noon TCC click stays (per archive doc) |
