# airy — the runner: source of truth

> **What this doc is.** The single authoritative record of what **airy** (the always-on M1 Air
> runner) *is* and what is *actually configured on it right now* — the **as-built** state, not the
> plan. The other `docs/airy-*.md` files are the *plans and runbooks* (how/why to set each thing up);
> this file is the *index to them* plus the *current reality*. When you change airy, update this file.
>
> Last verified: **2026-07-02**. Keep the "Last verified" date current when you re-check state.

---

## 1 — What airy is

| | |
|---|---|
| **Machine** | 2020 MacBook Air 13", Apple **M1**, **16 GB** RAM |
| **Serial** | `FVFFH3G2Q6LR` |
| **OS** | macOS **26.5.2** (build 25F84) |
| **Xcode** | **26.6** (full Xcode at `/Applications/Xcode.app`, license accepted) |
| **User** | `bronty` (Administrator) |
| **Internal disk** | 228 GB total, **~160 GB free** (7% used) — budget is real; see `airy-services-plan.md` |
| **FileVault** | **ON** (user's choice) → not fully headless: needs one GUI unlock+login per boot |
| **Role** | Always-on PhantomLives **runner**: media-review host, backup puller, build/CI/release node |

airy is **not** a PhantomLives subproject — it's infrastructure. It runs services *for* the repo.

## 2 — Access

- **SSH:** `ssh airy` — alias in `~/.ssh/config` (Vortex + MB14), key `~/.ssh/airy_ed25519`, user `bronty`.
  **Always use the alias, never the raw IP.**
- **Current IP:** `10.0.0.59` — **DHCP, not stable** (has moved before). If `ssh airy` fails, find the
  new IP (`arp -a` / router DHCP table) and update `~/.ssh/config` only — every caller uses the alias.
- **Screen Sharing + Remote Login (SSH):** both ON.
- **PurpleMirror host entry:** registered (Settings ▸ Hosts) so Vortex/MB14 monitor + control airy's jobs.
- Full detail + setup gotchas: **`reference` memory `airy-ssh`** and this repo's session history.

> **The one rule that explains most airy friction:** the **SSH context ≠ the GUI login context.**
> TCC/Full-Disk-Access grants, **login-keychain** writes (Sparkle key, notary profile), and menu-bar
> apps all require airy's **Aqua (GUI) session**. A fresh SSH session sees the login keychain *locked*
> (`errSecInteractionNotAllowed` / `-25308`). The **dedicated `purple-signing` keychain** is the
> workaround for signing; login-keychain secrets must be seeded from airy's own Terminal.

## 3 — Document map (read order)

| Doc | Purpose |
|---|---|
| **`airy.md`** (this file) | Source of truth: what airy *is* + current as-built state. Start here. |
| `airy-services-plan.md` | The plan + rationale for the build/CI/release roles + the 256 GB disk budget. |
| `airy-handoff.md` | Ordered **execution checklist** for the on-airy install/config steps (GUI-gated). |
| `archive-runner-setup.md` | Base runner setup (archive/scheduler, Rachel migration, Photos, Tailscale). |
| `dev-id-signing-airy.md` | The dedicated signing keychain so Dev-ID `codesign` works over SSH. |
| `releasing-on-airy.md` | `release-on-airy.sh` — cut notarized Sparkle releases on airy over SSH. |

## 4 — As-built service state

Status legend: ✅ done & verified · 🟡 in progress · ⬜ not started · ⚠️ needs attention

| # | Service / capability | Status | Notes |
|---|---|---|---|
| WS0 | **Xcode toolchain** | ✅ | Xcode 26.6, license accepted, `xcodebuild` works, Dev-ID sign OK. |
| WSB | **Repo checkout** | ✅ | `~/dev/PhantomLives` (HTTPS, public), kept current with `git pull --rebase`. |
| — | **Homebrew** | ✅ | `/opt/homebrew`, wired into `~/.zshenv` (so `ssh airy 'brew …'` works). |
| — | **brew-autoupdate** | ✅ | launchd job, verified `LastExitStatus = 0`. |
| WS3 | **PeekServer host** | ✅ | `com.bronty13.peekserver` under launchd (KeepAlive+RunAtLoad), `config.json` present, serving `10.0.0.59:8788`. |
| — | **Rachel backup pull** | ✅ | 13 `com.bronty13.external-*-sync.rachel` jobs loaded, exiting clean. |
| — | **Dev-ID signing** | ✅ | `purple-signing.keychain-db` holds `Developer ID Application: Robert Olen (SRKV8T38CD)`; pw at `~/.config/purple-signing/keychain-pw`. |
| WS1 | **Release/notary runner** | ✅ | Notary profile + Sparkle key seeded in login keychain, `gh` authed, `~/.config/purple-signing/login-pw` unlocks it over SSH, `~/.zprofile` exports the env. **Proven:** cut **PurpleMirror 1.18.0** (notarized + stapled + appcast live). Headless `sign_update` over SSH works after a one-time "Always Allow". |
| WS2 | **Self-hosted Swift CI** | ✅ | `~/actions-runner` registered as **`airy`** (labels `self-hosted,macOS,ARM64,xcode`), launchd service. **Proven green:** a PurpleMirror push ran `test (PurpleMirror)` on airy → success. Still monitor-only (not a required check). |
| — | **Secrets → 1Password** | ✅ | `release-secrets-backup.sh`/`restore.sh` shipped; the Sparkle key + Dev-ID `.p12` + notary/gh refs backed up to 1Password. |
| — | **PurpleAttic archive** | ⬜ | osxphotos/exiftool/restic installed; app + 3-copy run (LACIE+ROG_WHITE) + TCC grants pending. |
| — | **PurpleMirror app** | ✅ | Installed + run-at-login (`org.purplemirror.autostart`); Dev-ID-signed. |
| — | **Sleep/power profile** | ⚠️ | `pmset` still `sleep 1 / disksleep 10`; server profile (`-c sleep 0 disksleep 0 womp 1 autorestart 1`) **not yet applied** (needs sudo at airy). |

## 5 — Config record (as-built)

**Drives** (see `reference` memory `airy-drives` for the full topology/benchmarks):

| Volume | Role | Spotlight |
|---|---|---|
| `Macintosh HD` | internal system + Photos library | enabled (correct) |
| `ROG_AIRY` | local fast scratch SSD | disabled ✅ |
| `REDONE` | 4TB SMR archive (Rachel + PurpleAttic review) | disabled ✅ |
| `ROG_WHITE` | PurpleAttic 3-copy archive (primary) | disabled ✅ |
| `LACIE` | PurpleAttic 3-copy archive (mirror) | disabled ✅ |

> **Rule:** every new external gets `sudo mdutil -i off -d /Volumes/<name>` immediately (Tahoe
> shutdown-hang avoidance). Run **`reboot-safe`** before any reboot (symlinked in `/opt/homebrew/bin`).

**launchd jobs** (`launchctl list | grep -E 'bronty13|purplemirror'`):
- `com.bronty13.peekserver` · 13× `com.bronty13.external-*-sync.rachel` · brew-autoupdate ·
  `org.purplemirror.autostart` (run-at-login launcher, deliberately outside the managed-job namespace).

**Installed tooling:** `osxphotos`, `exiftool`, `restic`, `gh`, ffmpeg (PeekServer), Homebrew, Xcode.
**Missing:** `node` (install if a JS/Electron subproject is ever run on airy).

**Secrets & config locations:**

| Path | Holds |
|---|---|
| `~/Library/Keychains/purple-signing.keychain-db` | Dev-ID Application identity (SRKV8T38CD) |
| `~/.config/purple-signing/keychain-pw` (600) | signing-keychain password (for SSH unlock) |
| login keychain | notarytool profile `PurpleDedup-Notary` + Sparkle EdDSA private key (seeded; Sparkle key has a one-time "Always Allow" so `sign_update` works over SSH) |
| `~/.config/purple-signing/login-pw` (600) | login-keychain password for SSH unlock (notary + Sparkle) |
| `~/dev/PhantomLives/PeekServer/config.json` | PeekServer roots + Basic Auth hash |
| `~/actions-runner/` | GitHub self-hosted CI runner (`airy`) + launchd service |

**All release secrets are backed up to 1Password** via `release-secrets-backup.sh` — restore a fresh
Mac with `release-secrets-restore.sh` (see `docs/release-secrets-backup.md`).

**Shared release identity** (see `reference` memory `apple-release-creds`):
- notarytool profile name: `PurpleDedup-Notary` · Apple ID `robert.olen@icloud.com` · Team `SRKV8T38CD`.
- Sparkle public key: `2q4I3WNk7qQbidXEO/Jo/U3+t2ODS9x+e3/Wqt+ClQQ=` (one shared key across all Sparkle apps).

## 6 — Operating rules

- **Before any reboot:** run `reboot-safe` (or `eject-externals` then Restart) — unmounts every external
  first, or Tahoe wedges `diskarbitrationd` at shutdown → hard power-off. See `docs/reboot-hangs.md`.
- **After a reboot/power-loss:** FileVault stops at the disk-unlock screen → someone must unlock+login
  **once** at airy's screen; then all Aqua launchd agents (PeekServer, syncs, PurpleMirror, Amphetamine)
  auto-start. No auto-login is possible with FileVault on.
- **Stays awake while up** via **Amphetamine** (menu-bar; "Launch at login" set) — do not re-flag sleep
  as an open risk once the power profile (§4) is applied.
- **Login-keychain secrets** (Sparkle/notary) must be seeded from airy's **own Terminal**, not over SSH.
- **Rebuilds keep TCC grants** because apps Dev-ID-sign (stable cdhash) — the adhoc-regrant tax is gone.

## 7 — How to cut a release from airy

From Vortex/MB14 (headless, over SSH) — future PurpleMirror/Sparkle releases:
```sh
LOGIN_KC_PW_FILE='$HOME/.config/purple-signing/login-pw' SHORT_VERSION=<x.y.z> \
  AIRY_SSH=airy ./release-on-airy.sh PurpleMirror
```
Set a **semantic** `SHORT_VERSION` and add a matching `## <x.y.z> — <date>` CHANGELOG heading first
(PurpleMirror's release notes come from that heading; build number stays git-derived). Gotchas learned
cutting 1.18.0: the login keychain must be unlocked over SSH (`LOGIN_KC_PW_FILE`), and the Sparkle key
needed a one-time "Always Allow" done by running `Scripts/release.sh` once at airy's own Terminal —
after that, headless SSH releases work.

## 8 — Open items

- [x] ~~**WS1** release/notary — DONE (PurpleMirror 1.18.0 shipped, notarized, appcast live).~~
- [x] ~~**WS2** self-hosted CI — DONE (runner `airy` online; `test (PurpleMirror)` proven green).~~
- [x] ~~**Secrets → 1Password** — DONE (backup/restore scripts + bundle stored).~~
- [ ] **Power profile** — apply `sudo pmset -c sleep 0 disksleep 0 womp 1 autorestart 1` on airy.
- [ ] **Make WS2 a required check** — only after `swift-ci.yml` is proven stable across a few PRs.
- [ ] **PurpleAttic** — install + 3-copy archive run (LACIE+ROG_WHITE) + Photos/FDA TCC grants.
- [ ] **REDTWO** — arriving ~2026-07-02; benchmark vs REDONE (isolated dd+vmtouch), additive not a replacement.
- [ ] **`Notarized:` label** — release.sh now trusts `stapler validate`; consider the same fix in the
      other apps' `Scripts/release.sh` copies (PurpleDedup, PurpleDiary, Ircle, PurpleMark, …).
</content>
</invoke>
