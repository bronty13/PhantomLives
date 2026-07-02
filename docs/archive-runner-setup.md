# Dedicated archive/scheduler runner — setup & migration plan

> Status: **planned, not yet executed.** Execute when the new Mac ("airy") arrives.
> The maintainer works across Vortex (primary) + MB14 (portable); this stands up a third,
> always-on Mac to own the scheduled background jobs.

## Why

Move the **majority of scheduled background jobs off Vortex** onto a dedicated always-on box
("the runner" / "airy"), so Vortex stays a free, frequently-rebooted workstation and the archive
jobs run unattended. Two things make this clean now:

- The principal Photos library was **purged to ~97GB / 8,489 assets** (was ~929GB), so it now
  **fits the Air's 256GB internal SSD** — PurpleAttic's full 3-copy model runs on the two 2TB
  SSDs with no third drive and no redundancy downgrade.
- The maintainer owns an **Anker 11-in-1 powered dock** (85W PD passthrough, USB-C/USB-A @ 10Gbps,
  Gigabit Ethernet): one cable covers power + both drives + wired networking, with a spare port.

**Hardware:** M1 MacBook Air 16GB/256GB (Amazon Renewed) + the Anker dock.

**Two shaping constraints:**
1. The runner's jobs must be **monitored *and* controlled from both Vortex and MB14 via
   PurpleMirror** — which is local-only today, so this requires building SSH remote-host support
   into it (Workstream A).
2. **Rachel is deferred** — its initial backup isn't finished and PRO-G40 is unavailable, so the
   Rachel pipeline stays on Vortex for now and transitions to the runner later.

## Drive / connectivity layout

| Connection | Role |
|---|---|
| Dock → Air (1× USB-C) | 85W power + peripherals; Air's 2nd port stays free |
| Dock Ethernet → router | wired network (SSH pulls + B2 uploads) |
| ROG_WHITE (2TB) | PurpleAttic archive **primary** (existing ~929GB, untouched) |
| LACIE (2TB) | PurpleAttic archive **mirror** (existing ~929GB, untouched) |
| Internal 256GB | macOS + the 97GB System Photo Library (Download Originals) |
| Backblaze B2 | PurpleAttic off-site copy (existing repo `b2:vortex-photos-archive:photos` — do NOT re-seed) |

## Decisions (locked)
- **TCC consent click:** keep the daily-noon schedule + a once-a-day "Allow" click via Screen
  Sharing (runs are ~minutes now). The `kTCCServiceSystemPolicyAppData` prompt cannot be made
  persistent without MDM — see `PurpleAttic/HANDOFF.md` ("do not re-investigate"). MDM + PPPC is
  the only zero-touch alternative; deferred as overkill for now.
- **Swift apps:** build PurpleAttic + PurpleMirror **on Vortex** and `ditto` the signed `.app`s to
  the runner's `/Applications`, to avoid ~15GB of Xcode on the 256GB SSD. TCC grants are per-machine.
  **SUPERSEDED (see `docs/airy-services-plan.md`):** the decision to install Xcode on airy makes it
  self-contained for build + sign + notarize + CI, so apps can build on airy directly. Watch the
  256GB disk budget (Photos + Xcode + DerivedData) — mitigations are in that plan's Workstream 0.
- **PurpleMirror remote control:** ship **monitor-only first**, then add Run-Now, then enable/disable.

---

## Workstream A — PurpleMirror remote-host support (cross-Mac monitor + control)

Build SSH-based remote monitoring/control so each PurpleMirror instance (Vortex **and** MB14) shows
its own local jobs **plus the runner's**, with the same Run-Now / enable-disable / view-log controls.
**This is code and can be built now, before the Air arrives** (test against localhost, then the Air).

**Why it's a surgical change** — the local/remote difference collapses to three existing seams:
- `JobController.run(launchPath, args, env)` is the *only* place a `Process` shells out → a remote
  call wraps the same argv in `ssh … user@host '<cmd>'` and reuses the same executor.
- `SyncStatusParser` + the per-job log parsers are **pure string functions** → **zero changes**
  (a `launchctl print` / log tail parses identically whether read locally or over SSH).
- `JobRegistry` is pure on the label → reused unchanged on remote-discovered jobs.

**New files** (`Sources/PurpleMirror/`):
- `Host.swift` — `Codable` host: display name, `isLocal`, ssh user/host/port, identity-file path,
  connect timeout.
- `HostStore.swift` — persist `hosts.json` in `~/Library/Application Support/PurpleMirror/`, seeded
  local-only so existing installs are unchanged.
- `HostContext.swift` — actor caching remote `id -u` + `$HOME`; fetches plists via
  `plutil -convert xml1 -o -` → `PropertyListSerialization`; tails remote logs.
- `SSHCommand.swift` — pure `argv(for:remoteCommand:)`: local argv vs
  `/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=… -o ControlMaster=auto … -- '<shQuoted cmd>'`.
- `HostsSettingsView.swift` — add/edit hosts + a **Test connection** button.

**Changed files:**
- `JobController.swift` — route `run()` local vs ssh; derive home/uid from `HostContext`.
- `JobsModel.swift` — per-host **concurrent** rescan; key jobs by `host/label` (obsidian + brew run
  on both Macs); a slow/asleep host must not stall the 10s tick.
- `LaunchAgentPlist.swift` — add `parse(data:)` for plist bytes fetched over SSH.
- `MenuView.swift` — per-host grouping + aggregate-per-host glyph + offline/"last seen" badge when
  >1 host; **identical to today when only the local host exists.** Eject/Restart stay local-only.

**Resilience:** SSH off-main (existing `Task.detached`); `BatchMode=yes` (fail, never prompt);
`ConnectTimeout` + hard wall-clock cap; ControlMaster multiplexing to amortize handshakes; per-host
fan-out; last-known-state cache + backoff when unreachable.

**Security:** key-only auth; a dedicated key in the runner's `authorized_keys`; Remote Login enabled;
no secrets stored; app already non-sandboxed (no new entitlement).

**Tests** (Swift Testing, existing pattern): `SSHCommand.argv` + `shQuote`; `LaunchAgentPlist.parse(data:)`
(xml + binary); `HostStore` JSON round-trip + seeding; `id -u` / `ls ~/Library/LaunchAgents` output
parsers. Existing parser tests already cover remote data (identical input strings).

**Phasing:** P1 plumbing + host config (no behavior change) → **P2 remote monitor-only (ship first)** →
P3 control (Run-Now → enable/disable → guarded interval-edit) → P4 hardening + docs. Release hygiene
each step (version bump, CHANGELOG, tests, `./build-app.sh`).

**Deploy:** run PurpleMirror on **Vortex and MB14**, each with the runner added as a remote host
(a PurpleMirror on the runner itself is optional).

---

## Workstream B — Runner base setup (when "airy" arrives)

1. **Account/iCloud:** sign into Robert's Apple ID. Photos → **Download Originals** (seeds the 97GB
   library locally; finish before the first archive). Apple Music signed in (for harvest-favorites).
2. **Always-on:** keep it on the dock (plugged in); **auto-login on**; `sudo pmset -a disablesleep 1`;
   confirm it stays up lid-closed. **Enable Remote Login (SSH)** + add Vortex's & MB14's public keys
   to `~/.ssh/authorized_keys` (for Workstream A).
3. **Repo:** `git clone https://github.com/bronty13/PhantomLives.git ~/dev/PhantomLives` (MUST be
   `~/dev/`, never `~/Documents`); run a git-hooks installer (`PurpleTree/scripts/install-git-hooks.sh`).
4. **Deps:** `pipx install osxphotos`; `brew install exiftool restic node`; add
   `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile`.
5. **Reboot-safety:** `sudo ln -s ~/dev/PhantomLives/{eject-externals,reboot-safe}.sh /usr/local/bin/…`;
   adopt **`reboot-safe` before every restart** (Tahoe external-unmount hang — see `docs/reboot-hangs.md`);
   `sudo mdutil -i off -d /Volumes/{ROG_WHITE,LACIE}`.
6. **Drives:** confirm `/Volumes/ROG_WHITE` + `/Volumes/LACIE` mount with their exact labels.

## Workstream C — PurpleAttic on the runner

1. Deploy `PurpleAttic.app` (ditto from Vortex); grant **Full Disk Access + Photos + Automation**.
2. Recreate the **3 Keychain items** (service `PurpleAttic Restic B2`: `restic-password`,
   `b2-account-id`, `b2-account-key`) via the app's **Off-site Settings UI** (sets the
   `-T /usr/bin/security` ACL so the headless read doesn't prompt). Point at the **existing** B2 repo
   — no re-init/seed.
3. Copy `~/Library/Application Support/PurpleAttic/profile.json` from Vortex; verify
   `primaryDestination=/Volumes/ROG_WHITE`, `mirrorDestinations=["/Volumes/LACIE"]`,
   `photosLibraryPath`=null, `downloadMissingFromICloud=false`, `reviewNewItems=true`,
   `purgeAutoStage=false` (no ongoing purge — append-only archive + review folder is the steady state).
4. Set the schedule in the app's Schedule UI (regenerates `com.bronty13.PurpleAttic.archive.plist`
   with the new user/UID) — **noon** (waking hours).
5. Recreate by hand (not app-generated): `restic-datacheck.sh` (fix `/Users/<newuser>/` paths) +
   `com.bronty13.PurpleAttic.restic-check.plist` → `launchctl bootstrap gui/<uid>`.
6. **Verify:** a run appends new items to ROG_WHITE → rsync LACIE → restic B2, the "NEW PHOTOS TO
   REVIEW" folder populates (`~/Downloads/PurpleAttic/NEW PHOTOS TO REVIEW/<ts>/`), `restic check` clean.

## Workstream D — Lighter jobs (on the runner)

- **ATW bot:** copy `~/Library/Application Support/atw-repost-bot/`; `npm install` (rebuild arm64
  Chromium — don't copy `node_modules`); re-add Keychain item `ATW Repost Bot`; install
  `com.bronty13.atw-repost-bot` (needs an Aqua login session).
- **harvest-favorites:** `./applemusic-complete-playlist/harvest_favorites.sh --install-agent`; needs
  **Music.app running** + the **`My Picks [PL]`** playlist; auto-launch Music at login.
- **Obsidian mirror:** **uninstall on Vortex first** (`./sync-md-to-obsidian.sh --uninstall-agent` —
  one-writer rule, data-loss-sensitive, see `docs/obsidian-setup.md`); on the runner ensure
  `~/ObsidianVault/Cheetah` is the real Sync-connected vault (non-iCloud, `.obsidian/sync.json` present),
  grant FDA on `/bin/bash`, then `OBSIDIAN_VAULT=~/ObsidianVault/Cheetah ./sync-md-to-obsidian.sh
  --install-agent`; Obsidian app running + Sync-connected.
- **brew-autoupdate:** `cd brew-autoupdate && bash install.sh` (per-machine; Vortex keeps its own).

## Deferred — Rachel migration (later, once the initial backup completes)

Stays on **Vortex** for now (PRO-G40 unavailable; initial backup unfinished). When ready: copy the
local-only scripts (`external-*-sync.sh`, `source-vars.py`, `external-sources.json`) + the SSH key
`~/.ssh/purpleattic_rachel` from Vortex; repoint the Rachel archive destination to a drive available
on the runner then; install the 14 `com.bronty13.external-*-sync.rachel` agents; verify SSH to
`rachelkapuscinski@10.0.0.227` + a sync run + review staging; decommission on Vortex.

## Monitoring & decommission

- PurpleMirror runs on **Vortex + MB14**, each with the runner configured as a remote host → one pane
  to monitor/control the runner's jobs from either machine.
- **Decommission migrated jobs on Vortex** (`launchctl bootout` + `disable`) so nothing double-runs
  (PurpleAttic's schedule is already disabled on Vortex — keep it). Rachel agents stay on Vortex until
  transition.
- Vortex may switch Photos to "Optimize Storage" to reclaim space (optional) — the runner becomes the
  archive authority.

## What else the runner can do (future)
- **Tailscale node** → Screen-Share/SSH in from anywhere (incl. the daily TCC click).
- **restic / Time Machine target** for other Macs (spare dock port for a drive).
- Syncthing, local Git mirror, future account-bound automation (Spotify/Soundiiz), etc.

## Verification (end-to-end)
- PurpleMirror on Vortex/MB14 shows the runner's jobs with live status; Run-Now works remotely.
- PurpleAttic full run → new items on ROG_WHITE + LACIE + a B2 snapshot + review folder + `restic check` OK.
- Each light agent runs clean (`launchctl kickstart -k gui/<uid>/<label>`) and appears in PurpleMirror.
- `reboot-safe` ejects both drives and restarts the runner without a hang.
