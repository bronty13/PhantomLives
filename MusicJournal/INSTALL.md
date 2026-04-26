# Music Journal — Installation Guide

## Prerequisites

Before building Music Journal you need:

1. **macOS 14 Sonoma or later**
2. **Xcode 15+** (Xcode 16 recommended) — install from the Mac App Store
3. **XcodeGen** — generates the Xcode project from `project.yml`
4. **A Spotify Developer account** — to register the app and obtain a Client ID

---

## Step 1 — Register a Spotify app

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and log in.
2. Click **Create app**.
3. Fill in any name and description (e.g. "Music Journal").
4. Under **Redirect URIs** add: `musicjournal://callback`
5. Set **APIs used** to *Web API*.
6. Save. Copy the **Client ID** from the app dashboard.

> **Development mode**: A newly created app is in development mode, which allows up to 25 users. Track fetching only works for playlists you own. To remove this restriction you would need to apply for Extended Quota — not required for personal use.

---

## Step 2 — Add your Spotify user as a test user

1. In the Spotify Developer Dashboard, open your app → **User Management**.
2. Add the email address associated with your Spotify account.

This is required for development-mode apps to grant your account OAuth access.

---

## Step 3 — Install XcodeGen

Using Homebrew:

```bash
brew install xcodegen
```

Or download a release binary from [github.com/yonaskolb/XcodeGen](https://github.com/yonaskolb/XcodeGen).

---

## Step 4 — Clone or open the project

```bash
cd /path/to/MusicJournal
```

---

## Step 5 — Set your Client ID

Open `Sources/MusicJournal/Services/SpotifyAuthService.swift` and update line 17:

```swift
private let clientId = "YOUR_CLIENT_ID_HERE"
```

Replace `YOUR_CLIENT_ID_HERE` with the Client ID you copied in Step 1.

---

## Step 6 — Generate the Xcode project

```bash
xcodegen generate
```

This reads `project.yml` and creates `MusicJournal.xcodeproj`. You must re-run this whenever `project.yml` changes (e.g. after adding new source files).

---

## Step 7 — Open and build

```bash
open MusicJournal.xcodeproj
```

In Xcode:

1. Select the **MusicJournal** scheme in the toolbar.
2. Choose **My Mac** as the run destination.
3. Press **⌘R** to build and run.

Xcode will automatically resolve the GRDB Swift Package dependency on first build (requires internet access).

---

## Step 8 — First launch

1. The app opens to the **Welcome** screen.
2. Click **Connect Spotify**.
3. A browser sheet opens; log in with your Spotify account and click **Agree**.
4. The app loads your playlists from any previously cached data immediately.
5. Click the **↻ sync** button in the toolbar (or press **⌘⇧R**) to fetch all playlists and tracks.

> The initial sync can take several minutes depending on how many playlists you have. A status bar at the bottom of the window shows progress.

---

## Database location

The SQLite database is stored at:

```
~/Library/Application Support/MusicJournal/journal.sqlite
```

You can open this file with any SQLite browser (e.g. [DB Browser for SQLite](https://sqlitebrowser.org)) to inspect or back up your data directly.

---

## Updating the app

There is no auto-updater. To update:

1. Pull or copy the new source files.
2. Re-run `xcodegen generate` if `project.yml` changed.
3. Build and run in Xcode.

Your database is not affected by rebuilds — it lives in Application Support, not the app bundle.

---

## Uninstalling

1. Delete `MusicJournal.app` from wherever Xcode placed the build product.
2. To remove all data: `rm -rf ~/Library/Application\ Support/MusicJournal`
3. To remove Keychain tokens: open **Keychain Access**, search for `com.bronty.MusicJournal`, delete the entries.
