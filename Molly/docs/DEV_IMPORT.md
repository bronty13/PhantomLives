# Importing Sallie's export on the dev machine

> Reference for Robert. Pairs with the export instructions in `INSTALL.md`. ~5 minutes start to finish.

## When this fires

Sallie drops a `Molly-export-YYYY-MM-DD-HHmmss.zip` into Slack. Save it locally somewhere accessible — e.g. `~/Downloads/Sallie-Molly-export-2026-05-20.zip`.

## Steps

1. **Kill any running Molly.app** so the DB isn't locked:
   ```sh
   osascript -e 'tell application "Molly" to quit' 2>/dev/null || true
   ```

2. **Launch dev mode with the import flag**:
   ```sh
   cd ~/Documents/GitHub/PhantomLives/Molly
   VITE_MOLLY_DEV=1 pnpm tauri dev
   ```

3. **In the running app**: **Settings → Data**.

4. Scroll down. You'll see an amber-tinted card labeled **🛠 Dev import (VITE_MOLLY_DEV=1)** (only visible when the env var is set).

5. Click **📥 Import a Molly-export-*.zip…**, navigate to her zip, open.

6. **What happens under the hood**:
   - `restore_archive` first verifies the zip contains `molly.db`. If not, abort.
   - It writes a pre-import safety archive to `~/Downloads/Molly backup/Molly-pre-restore-YYYYMMDD_HHMMSS.zip` containing your **current** dev data.
   - It wipes `~/Library/Application Support/com.phantomlives.molly/`.
   - It unpacks the import there.

7. **Quit `pnpm tauri dev`** (Ctrl+C in the terminal).

8. **Relaunch in dev mode** (`VITE_MOLLY_DEV=1 pnpm tauri dev` or just `pnpm tauri dev` — the flag is only needed for the dev-import button itself; subsequent launches against the loaded data don't need it).

   You now have Sallie's full state loaded locally. Poke around as her.

## Reverting to your own data

The pre-import safety archive is in `~/Downloads/Molly backup/Molly-pre-restore-….zip`. To go back:

1. **Settings → Backup → Recent backups**. Find the `pre-restore` archive.
2. Click **Restore** on it. (It'll create another `pre-restore` archive for the current Sallie-data state, which you can use to flip back again if you need.)
3. Quit + relaunch.

You can ping-pong between Sallie-state and your-state as many times as you want; every restore creates a safety archive of the previous state.

## What you might want to look at

Once her data is loaded, the useful entry points:

- **Reports → Export CSV** for a quick numerical summary of how the year is going.
- **Promos** to see what platforms she's actually been posting on. If most rows are missing the linked clip, that's a UX gap (the clip-link dropdown is currently optional + not flagged).
- **Customers** to see how many real records she's added. Note count + product/interest distribution.
- **Reminders → Schedules** to see what she's added beyond the 5 preloaded.
- **Settings → Backup → Recent backups**. Tells you when she last opened Molly + roughly how often.

## What NOT to do

- **Don't commit her data anywhere.** It's in `app_data_dir` only — don't copy it into the repo.
- **Don't run `Molly.app` (production, from `/Applications/`) while dev-mode is loaded with her data.** Both binaries read the same `app_data_dir` — you'd be writing to her data with whichever app is running.
- **Don't restore from one of her own backup zips into your dev environment** — the file name prefix is identical to yours (`Molly-…zip`) and could shadow your real backups. Use the **dev import** flow, not the regular Restore.

## When Sallie's testing is done

If a round of fixes lands and you want to wipe her data + return your dev box to a clean slate:

1. Quit Molly.
2. `rm -rf ~/Library/Application\ Support/com.phantomlives.molly/`
3. Relaunch — the migrations re-create empty tables with preloaded personas/sites/etc.

(Your dev `~/Downloads/Molly backup/Molly-pre-restore-…zip` is still there if you want to revert — just Restore it.)

## If a dev-import surfaces a bug in her data

Most likely you'll see something like:

- Empty fields where there shouldn't be → schema validation gap.
- "undefined" / "NaN" → almost certainly missing `#[serde(rename_all = "camelCase")]` on a return type. Check `lib.rs::camel_case_contract` for the regression net.
- A view crashes → screenshot, find the failing component, defensive null-guard.

For any of these: fix it locally, bump patch version, write a regression test if possible, tag `molly-vX.Y.Z`, push. She gets the update on next launch.
