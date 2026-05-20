# Installing Molly

Two audiences for this doc:

1. **Sallie — getting Molly running on her Windows machine.** Step-by-step, screenshots-friendly, no jargon. Start at "Windows install" below.
2. **Robert — building from source / importing a user export.** Skip down to "Developer setup".

---

# Sallie's installation guide

## What you need

- Your Windows laptop. ✓
- Internet to download the installer. ✓
- 5 minutes.

That's it.

## Step 1 — Download Molly

1. Open this link in your browser: **<https://github.com/bronty13/PhantomLives/releases>**
2. Find the **newest** release at the top — it'll say "**Molly molly-v…**" with the most recent date.
3. Scroll down to **Assets** and click the file that ends in **`x64-setup.exe`**. It'll be called something like `Molly_1.0.0_x64-setup.exe`.
4. The browser will download it. It might warn you because it's not from the Microsoft Store — that's normal, click **Keep** if asked.

## Step 2 — Run the installer

1. Open your **Downloads** folder.
2. Double-click **Molly_1.0.0_x64-setup.exe** (or whatever version you downloaded).
3. **Windows may show a blue "Windows protected your PC" screen.** This happens with any new app the first time. Click **More info** → **Run anyway**.
4. The installer opens — click through the wizard. The default options are fine. It takes about 10 seconds.

When it finishes, **Molly** is on your Start menu and the Desktop. Done.

## Step 3 — Open Molly for the first time

Double-click the **Molly** shortcut on your Desktop, or tap the Windows key and type "Molly".

On first launch she does three quick things you won't see:

- Sets up her little database in `%APPDATA%\com.phantomlives.molly\`.
- Auto-creates her backup folder at `Downloads\Molly backup\`.
- Loads your three personas (CoC, PoA, Sa) and all your preloaded sites.

The window opens. You'll see a soft pastel pink screen with a saying at the top. **Tap the persona pills** (CoC / PoA / Sa / ★ All) in the top right — the whole app recolors. That's Molly working.

## Where things are

| Inside Molly | Real folder on your laptop |
|---|---|
| Your data (DB + receipts + settings) | `%APPDATA%\com.phantomlives.molly\` — don't touch unless asked |
| Auto-backups (one per launch, kept 14 days) | `Downloads\Molly backup\` |
| Full exports to send Robert | `Downloads\Molly export\` |

You never need to dig into the first one. The other two are visible in your normal Downloads folder.

## When updates land

Molly checks for updates on every launch. If a new version exists, **Settings → Updates** shows a `⬇️ Download` button — click it, then close + reopen Molly. The new version installs automatically. Your data stays put.

You can also check manually any time from **Settings → Updates → 🔍 Check for updates**.

## Exporting your data (when Robert asks)

After you've used Molly for a few days, Robert may ask for a copy of your data to look at how it's being used. Here's how:

1. Open Molly.
2. Click **Settings** in the sidebar (the gear icon at the bottom).
3. Click the **Data** tab at the top.
4. Click **📦 Export everything**. Wait 1–2 seconds.
5. You'll see a card appear with the file path — something like `C:\Users\Sallie\Downloads\Molly export\Molly-export-2026-05-20-153022.zip`.
6. Click **🗂 Reveal in Explorer** to open the folder.
7. **Drag that .zip file into our Slack DM.** That's it!

The zip contains everything Molly knows about your work (database + every receipt you've attached + settings). It's about 1–10 MB depending on how many receipts you've added.

You can re-export any time. Each export makes a new file — nothing is overwritten. Old exports stay in `Downloads\Molly export\` until you delete them manually.

## If something goes wrong

- **Molly won't open**: Restart your laptop, double-click Molly again. If it still won't open, send Robert a Slack with what happens (a screenshot is gold).
- **A button does nothing**: Try clicking the button once and waiting 2 seconds. If still nothing, restart Molly.
- **The Test or Restore buttons in Backup say something weird**: Slack Robert with a screenshot, don't click Restore.
- **You see the word "undefined" or "NaN"** anywhere: This is a bug. Screenshot + Slack Robert.

You can't break Molly by clicking. Worst case, the auto-backup in `Downloads\Molly backup\` is one click away from being restored.

## Auto-backup safety net

Every time you open Molly she takes a snapshot of your data and saves it as `Molly-YYYY-MM-DD-HHmmss.zip` in your Downloads. If anything ever goes wrong, the most recent one is right there in your Downloads → Molly backup folder, ready to restore from Settings → Backup → Recent backups → **Restore**.

---

# Developer setup (Robert)

## Building from source

```sh
brew install rust pnpm librsvg imagemagick     # one-time
cd Molly
pnpm install
pnpm tauri dev                                  # hot reload
```

`build-app.sh` builds the macOS bundle and installs to `/Applications/Molly.app` via `install.sh`.

## Cutting a release

```sh
git tag -a molly-vX.Y.Z -m "Molly vX.Y.Z — <summary>"
git push origin molly-vX.Y.Z
```

The GitHub Actions workflow `.github/workflows/release-molly.yml` will build signed `.dmg` + `.exe` + `latest.json` and publish to a **draft** GitHub release. From the Releases page, **edit → publish** when you're ready to roll the update out to Sallie.

## Updater key

Private key: `~/.config/molly-secrets/updater.key` (do NOT commit).
Public key: in `tauri.conf.json::plugins.updater.pubkey`.
GitHub secret: `TAURI_SIGNING_PRIVATE_KEY` (set once via `gh secret set ... < ~/.config/molly-secrets/updater.key`).

## Importing Sallie's export

When Sallie drops a `Molly-export-…zip` into Slack:

1. Save it locally, e.g. `~/Downloads/Sallie-Molly-export-2026-05-20.zip`.
2. **Launch Molly in dev mode with the dev flag set**:
   ```sh
   cd Molly
   VITE_MOLLY_DEV=1 pnpm tauri dev
   ```
3. In the running app: **Settings → Data**. A new section appears at the bottom labelled **🛠 Dev import (VITE_MOLLY_DEV=1)**.
4. Click **📥 Import a Molly-export-*.zip…**, pick the file.
5. Molly writes a pre-import safety backup at `~/Downloads/Molly backup/Molly-pre-restore-….zip`, wipes the app-data dir, and unpacks the import.
6. The status panel shows where the safety archive lives. **Quit and relaunch** Molly to load the new data cleanly.

To restore your *own* dev data afterward, the safety archive is right there — Settings → Backup → Restore on it.

## Running tests

```sh
./run-tests.sh         # cargo test --lib (backup + camelCase contract)
pnpm build             # tsc -b + vite build (frontend type-check + bundle)
```

12 Rust unit tests today. Frontend test suite is deferred to a future quality pass.

## Useful Tauri commands you'll grep for

```rs
backup::test_backup       // verify a zip without restoring
backup::restore_backup    // restore with safety pre-archive
export::export_full_data  // user-visible zip to ~/Downloads/Molly export/
export::import_full_export // dev-only inverse
attachments::save_attachment  // user-picked file → app_data/attachments/...
```

All boundary types are camelCase-serialized; see `lib.rs::camel_case_contract` for the regression tests pinning that contract.
