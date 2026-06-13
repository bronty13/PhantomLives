# Obsidian vault & sync — canonical setup (READ BEFORE ANY OBSIDIAN WORK)

This is the **single source of truth** for how the maintainer's Obsidian is (to
be) configured. It exists because Obsidian sync has repeatedly caused confusion
and, on **2026-06-13, real note loss**. Follow it exactly; do not improvise.

## The goal

**One** Obsidian vault, seamlessly synced across **four devices**:

- **Vortex** (Mac, user `bronty13`)
- **MB14** (Mac, user `bronty`, `ssh mb14`)
- **iPad**
- **iPhone**

The maintainer has **both** iCloud and a paid **Obsidian Sync** subscription
(prepaid 1 year).

## THE GOLDEN RULE — one sync engine per vault, and it is Obsidian Sync

> **Use Obsidian Sync as the ONLY sync mechanism for the vault. The vault folder
> must NEVER live anywhere iCloud Drive touches. Two engines on one vault =
> corruption and data loss.**

Why Obsidian Sync (not iCloud) is the chosen engine:

- **Cross-platform & reliable.** Purpose-built for macOS + iOS; iCloud-Drive-based
  Obsidian on iOS is notoriously flaky (eviction, placeholder stubs, delayed/again
  reconciliation — exactly the failures seen here).
- **Path-independent.** Obsidian Sync syncs *content*, not a folder path — so the
  two Macs can keep the vault at different local paths (different usernames) and
  still share one remote. iCloud requires the rigid container path.
- **Version history + deleted-file recovery.** Obsidian Sync keeps server-side
  version history, so a bad edit or deletion is recoverable. This is the safety
  net against future data loss. iCloud Drive does not give per-note history.

### What caused the 2026-06-13 data loss

The active vault was `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/
bronty Vault` — i.e. **inside the iCloud container** — while the maintainer also
intended to use Obsidian Sync. iCloud reconciled that container across devices
and propagated an empty/conflicting state down, wiping local files (no `.icloud`
stubs were left — the content was removed, not just evicted). The repo mirror
script was *not* the cause: it only ever writes/prunes inside a `PhantomLives/`
subfolder and cannot delete anything outside it.

## The correct architecture

```
                 ┌──────────────────────────────┐
                 │   Obsidian Sync remote vault  │   (Obsidian's servers, E2E)
                 │            "Main"             │
                 └───────┬───────┬───────┬───────┘
        Obsidian Sync ───┘       │       └─── Obsidian Sync
                 │               │               │
   ┌─────────────┴───┐   ┌───────┴──────┐   ┌────┴─────┐   ┌──────────┐
   │ Vortex (Mac)    │   │ MB14 (Mac)   │   │  iPad    │   │  iPhone  │
   │ ~/ObsidianVault │   │ ~/ObsidianV. │   │ (in-app, │   │ (in-app, │
   │  (NOT iCloud)   │   │ (NOT iCloud) │   │ NOT iCloud)  │ NOT iCloud)
   └─────────────────┘   └──────────────┘   └──────────┘   └──────────┘
```

- **Macs:** vault lives at a plain local path **outside** iCloud — recommended
  `~/ObsidianVault`. **Never** under `~/Documents` or `~/Desktop` (iCloud
  "Desktop & Documents" syncs those) and **never** under
  `~/Library/Mobile Documents/` (the iCloud containers, incl. `iCloud~md~obsidian`).
- **iOS (iPad/iPhone):** when creating/opening the vault, the **"Store in iCloud
  Drive" toggle MUST be OFF.** Let Obsidian keep it in the app's own storage and
  let Obsidian Sync handle it.
- All four devices **Connect to the same remote vault** in Obsidian Sync.

## One-time setup (clean restart — current plan)

The maintainer is OK restarting the vault from scratch (only a couple of notes
existed). Do it in this order:

1. **Pick a "first" device** (e.g. Vortex). In Obsidian:
   - Create/open a vault at `~/ObsidianVault` (a normal local folder — NOT in
     iCloud, NOT in `~/Documents`).
   - Settings → **About → log into your Obsidian account.**
   - Settings → **Sync → Create new remote vault** (name it, e.g. `Main`).
     **Set an end-to-end encryption password and SAVE IT in the password
     manager — if lost, the synced data is unrecoverable.**
   - Connect this vault to `Main`; let it finish "Fully synced".
2. **MB14** (`ssh mb14` is for files, but Sync setup is GUI-only): open Obsidian,
   create a local vault at `~/ObsidianVault`, log in, Settings → Sync →
   **Connect to existing remote vault → `Main`.** It downloads.
3. **iPad** and **iPhone:** open Obsidian → create a vault →
   **turn OFF "Store in iCloud Drive"** → log in → Sync → **Connect to `Main`.**
4. Verify a note created on one device appears on the others within seconds.

## Data-loss prevention — NEVER do these

- ❌ Never put the synced vault under `~/Documents`, `~/Desktop`, or
  `~/Library/Mobile Documents/` (iCloud). iCloud + Obsidian Sync on the same
  vault = corruption.
- ❌ Never enable "Store in iCloud Drive" for the vault on iOS.
- ❌ Never point two different sync tools at one vault.
- ❌ Never run a bulk delete/move across the whole vault without first
  confirming Obsidian Sync version history is current (it's the undo).
- ✅ Keep the Obsidian Sync encryption password in the password manager.
- ✅ Trust Obsidian Sync's version history as the recovery path
  (Settings → Sync → there is deleted-file / version recovery).

## How the PhantomLives docs mirror fits in (optional, secondary)

`sync-md-to-obsidian.sh` mirrors the repo's git-tracked `.md` into a
`PhantomLives/` subfolder of a vault, so the docs (incl. `macos-mastery/`) can be
read in Obsidian. To use it WITH this architecture **safely**:

- Point it at the **local Sync'd vault** on **one** Mac only (Vortex):
  `OBSIDIAN_VAULT="$HOME/ObsidianVault" ./sync-md-to-obsidian.sh --install-agent`
  (the chosen vault is baked into the launchd agent plist). Obsidian Sync then
  propagates `PhantomLives/` to the other devices — do **not** run the mirror on
  more than one device.
- The mirror only ever writes/prunes inside `PhantomLives/` — it cannot harm
  your own notes elsewhere in the vault.
- It only reaches the other devices if Vortex's Obsidian is **running and
  Sync-connected** (it pushes what the mirror wrote). 
- Consider scoping the mirror to just `macos-mastery/` rather than all ~440 repo
  docs, to avoid cluttering the personal vault (a future enhancement —
  not yet implemented).

## For Claude (every session)

When the maintainer mentions Obsidian, sync, or "see it on my iPad", **read this
file first.** Key facts to act on:

- The sync engine is **Obsidian Sync**, not iCloud. Putting files in a vault
  folder only reaches other devices if that device's Obsidian is **logged in,
  Sync-connected, and running**. You **cannot** set up/connect Obsidian Sync from
  the CLI — that's a GUI/account step the maintainer must do; guide them, don't
  fake it.
- The vault must be at a **non-iCloud local path** (`~/ObsidianVault`). If you
  ever find a vault under `~/Documents` or `~/Library/Mobile Documents/`, that is
  the bug — surface it, don't write into it.
- Confirm a vault is actually Sync-connected by checking for
  `<vault>/.obsidian/sync.json` before assuming files will propagate.
- The repo is the source of truth for the `macos-mastery` curriculum; Obsidian is
  a read convenience. Never treat the vault as authoritative over git.
