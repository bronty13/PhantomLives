# Molly — User Manual

This guide is written for the creator using Molly day to day, not for developers. If you ever get stuck, send Robert a screenshot in Slack and he can usually figure it out.

> Phase 0 ships only the shell, persona switcher, theme engine, and backup. The other features in the menu (Calendar, Clips, Customers, Helper, Income, Expenses, Reports) are placeholders for now.

## Opening Molly

### macOS

Double-click **Molly** in your Applications folder, or hit ⌘+Space and type "Molly".

### Windows

Double-click the Molly icon on your Desktop or Start menu.

If Windows SmartScreen says "Windows protected your PC", click **More info** → **Run anyway** the first time (the installer is signed by Robert, but it's a new app so SmartScreen hasn't seen many users yet).

## The persona switcher

The pills at the top right are the personas:

- **CoC** — Curse Of Curves (baby pink)
- **PoA** — Princess of Addiction (red & black)
- **Sa**  — Sheer Attraction (tan)
- **★ All** — show everything together

Click a pill. The whole app recolors to match. Your choice is remembered between launches.

## The sidebar

The icons down the left side are the main feature areas. Click any one to jump there. Press **Ctrl+S** (Windows) or **⌘+S** (Mac) to hide / show the sidebar.

## Settings → Backup

This is the most important thing to know about right now. Molly automatically saves a zip of all your data **every time you open it** (with a 5-minute breather between runs so debugging doesn't fill your downloads folder).

### Where backups live by default

- **Mac**: `~/Downloads/Molly backup/`
- **Windows**: `%USERPROFILE%\Downloads\Molly backup\`

The folder is created the first time it's needed.

### What's in Settings → Backup

- **Auto-backup on launch** — leave this on.
- **Backup folder** — change where backups land. Click **Choose…** to pick. Click **Default** to reset.
- **Retention (days)** — Molly deletes backups older than this. Default 14 days. Set `0` to keep forever. Only Molly's own backup files are deleted; anything else in that folder is left alone.
- **Run Backup Now** — make a backup right now (ignores the 5-minute debounce).
- **Reveal in Finder / Explorer** — open the backup folder.
- **Recent backups list** — every backup with three buttons each:
  - **Test** — checks that the backup is valid and the database is inside. Safe to click any time.
  - **Restore** — DANGER. Replaces all your current Molly data with the contents of this backup. Molly always saves a "pre-restore" safety backup first, so if you click Restore by accident, you can Restore the safety one to undo.
  - **Reveal** — show the .zip in Finder / Explorer.

### Sending a backup to Robert

If Robert asks for a copy of your data:

1. Settings → Backup → **Run Backup Now**.
2. Find the new zip in the backup folder (newest at the top of the list).
3. Drag it into our Slack DM.

That's it. He'll import it on his side to look at what's going on.

## Updating Molly

When a new version is ready, Molly checks for it on launch and tells you. You'll see a banner with a **Download update** button. Click it, then close and reopen Molly. The new version installs in place — your data is untouched.

If the banner ever fails, you can always download the latest installer from the [GitHub Releases page](https://github.com/bronty13/PhantomLives/releases) and run it.

## Where Molly stores its actual data

- **Mac**: `~/Library/Application Support/Molly/`
- **Windows**: `%APPDATA%\com.phantomlives.molly\`

You shouldn't ever need to touch this folder — backups handle it. But if your computer is migrating to a new machine, copy this directory to the new machine in the same location and Molly will pick up where it left off.
