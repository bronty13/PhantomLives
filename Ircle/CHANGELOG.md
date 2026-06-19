# Changelog

All notable changes to Ircle are documented here.

## 0.8.3 — 2026-06-18

### Fixed

- **Downloaded releases no longer trip Gatekeeper's "Apple could not verify…"
  malware prompt.** The release zip was built with a plain `ditto -c -k`, which
  stores codesign's `com.apple.provenance` extended attributes as AppleDouble
  (`._name`) entries. macOS's own extractors merge and discard them, but `unzip`
  and several browser/third-party extractors leave them behind — dropping
  `._Autoupdate`, `._Sparkle`, … into `Sparkle.framework`'s root, which a clean
  Mac rejects as *"unsealed contents present in the root directory of an embedded
  framework."* `Scripts/release.sh` now strips xattrs and zips with
  `--norsrc --noextattr`, so the zip carries no AppleDouble and **every**
  extractor yields a Gatekeeper-valid, notarized+stapled bundle. Added an
  extractor-agnostic release gate (unzip → assert no `._*`, staple valid, strict
  codesign) so this can't regress silently. (Incident: 1.0.979.)
- **Release pre-flight tolerates a flaky notary probe.** `Scripts/release.sh`
  probes the notarytool profile with `notarytool history`, which hits Apple's
  API and can fail transiently (printing a misleading "No Keychain password item
  found"). It now retries before declaring the profile missing, so a network
  blip can't abort an otherwise-good release. (Incident: a 1.0.981 attempt died
  here; the next call succeeded.)
- **Channel tabs read "# channel", not "# #channel".** The Channelbar button
  already shows a `#` glyph for a joined channel, so the duplicate leading
  `#`/`&` is now dropped from the channel name in the tab label. Queries and
  server tabs are unaffected.

## 0.8.2 — 2026-06-18

### Fixed

- **First release now actually notarizes.** `build-app.sh` was missing the
  notarization + stapling step, so `Scripts/release.sh` (which builds with
  `NOTARIZE_PROFILE` set and then asserts `stapler validate`) failed at the
  verify gate — the bundle was Developer-ID-signed but never sent to Apple's
  notary. Ported the standard PhantomLives notarize-and-staple block (submit
  via `notarytool --wait`, parse the verdict from the result plist, staple on
  `Accepted`); gated on `NOTARIZE_PROFILE` so routine personal builds still
  skip it. This unblocks cutting the first Ircle release.

## 0.8.1 — 2026-06-18

### Fixed

- **mIRC colors stay legible against the theme background.** `MircRenderer` now
  clamps a code's foreground color for contrast: if it's within ~0.42 luminance
  of the backdrop (the message-area background, or an explicit mIRC background
  for that run) it's blended toward the opposite extreme until it separates,
  preserving hue otherwise. Fixes mIRC white (color 0) washing out on the light
  Platinum theme and black (color 1) on dark Graphite; also tames hard cases
  like yellow-on-white. The renderer now works in an internal `RGBColor` so it
  can reason about luminance. 4 tests added.

## 0.8.0 — 2026-06-18

### Added

- **Sparkle 2 auto-update.** Sparkle dependency in `Package.swift`; an
  `UpdaterController` and a "Check for Updates…" menu item; `build-app.sh`
  bundles `Sparkle.framework`, adds the rpath, signs the nested XPC services /
  Updater.app / Autoupdate inside-out, and embeds the `SU*` Info.plist keys
  (feed `…/Ircle/appcast.xml`, the shared fleet EdDSA public key, daily checks).
  - `UpdaterController` starts the updater **only when a real `SUPublicEDKey` is
    embedded** — a dev build without `SPARKLE_PUBLIC_KEY` keeps updates off and
    launches normally instead of crashing on the placeholder key.
- **Release tooling:** `Scripts/release.sh` (notarize + staple + zip +
  EdDSA-sign + GitHub release + appcast prepend/push, mirrored from PurpleIRC),
  a seeded `appcast.xml`, and `RELEASING.md` (one-time setup + the shared-key
  workflow). Releases are git-derived `1.0.<count>`, tag `ircle-v<version>`.

## 0.7.0 — 2026-06-18

### Added

- **AppleScript support.** A scripting dictionary (`Resources/Ircle.sdef`) with
  four commands — `connect`, `join channel "#x"`, `say "text" [to "#x"|"nick"]`,
  and `current nickname` — implemented as `NSScriptCommand` subclasses
  (`AppleScriptCommands.swift`) that reach the live `IrcleModel` via a weak
  bridge registered at launch. All script input is sanitized through
  `IRCSanitize.field`. Info.plist gains `NSAppleScriptEnabled` +
  `OSAScriptingDefinition`; build-app.sh copies the `.sdef` into the bundle.
  - Note: each command class carries an explicit `@objc(...)` name so Cocoa
    Scripting can resolve the `.sdef`'s `<cocoa class>` (Swift's mangled names
    otherwise yield AppleScript error -1717).

## 0.6.0 — 2026-06-18

### Changed (security)

- **Passwords now live in the macOS Keychain, not `settings.json`.** Server
  passwords and SASL passwords are stored via a new device-only Keychain store
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service
  `com.phantomlives.Ircle`, keyed per server profile) and loaded back into
  memory at launch. `ServerProfile` still binds the cleartext in memory (so the
  Settings fields work normally) but its JSON encoder writes the password
  fields empty — secrets never touch disk.
- **Automatic migration:** any plaintext password left in an older
  `settings.json` is read once, moved into the Keychain, and scrubbed from the
  rewritten file.
- `SecretStore` is injectable (`KeychainSecretStore` in production,
  `InMemorySecretStore` in tests), so tests never touch the real Keychain.

### Tests

- 3 new (passwords go to the secret store and not the JSON; reload rehydrates
  from the store; legacy plaintext migrates out and is scrubbed). 59 total.

## 0.5.0 — 2026-06-18

### Added

- **Built-in list of common IRC networks** (Libera Chat, OFTC, EFnet, Undernet,
  DALnet, IRCnet, QuakeNet, Rizon, EsperNet, SwiftIRC, GameSurge, GeekShed,
  Snoonet, Hackint, freenode, 2600net, AfterNET, SorceryNet) — `ServerProfile.
  defaultServers()`, mirroring PurpleIRC. TLS defaults are network-correct:
  modern networks use TLS/6697, older ones that don't reliably offer TLS
  (EFnet, Undernet, IRCnet, QuakeNet, GameSurge) default to plaintext/6667.
  - **Fresh installs** are pre-seeded with the full list.
  - **Existing installs** keep their saved servers and can pull in any they're
    missing via the new **"Add Common Servers"** button (the `list.star` icon)
    in Settings → Servers — idempotent, by-name, never touches existing entries.

## 0.4.3 — 2026-06-18

### Fixed

- **Editing a server's port/host didn't take effect on reconnect.** A session
  captures its connection config when created; the reconnect path reused the
  existing (not-connected) session, so it kept dialing the *old* host/port even
  after you edited the profile — e.g. changing Undernet from 6697 to 6667 still
  tried 6697. Now a not-connected session is dropped and rebuilt from the
  current profile on reconnect (a live connection is still just focused, never
  disrupted). Regression test added.

## 0.4.2 — 2026-06-18

### Fixed

- **Connection attempts could hang / show a scary "Waiting: … timed out".**
  Via IRCKit 0.2.0, a connect now times out cleanly after 20s with an actionable
  message (names the host:port, suggests checking TLS vs. port), and the
  transient `.waiting` state no longer reads as a hard failure. The profile →
  config conversion also trims the host (a stray space or a pasted `host:port`
  was a silent timeout cause) and falls back to the conventional port
  (6697 TLS / 6667 plain) when it's blank.
- **A second server that hit a nick collision never finished connecting.** The
  ERR_NICKNAMEINUSE (433) auto-bump was guarded by `state != .connected ||
  !isConnected`, which is never true during registration (the socket is already
  `.connected` before RPL_WELCOME), so the nick was never bumped and
  registration stalled — common when a new server reuses a nick already taken on
  that network. Now tracked with a proper `registered` flag (set on 001): a 433
  before registration bumps the nick (up to 6 times, appending `_`) and shows
  what it's trying; after registration it just reports the collision.

### Added

- **Copy from the message area.** Right-click any line for **Copy** (that line,
  timestamp + text, mIRC codes stripped) or **Copy All** (the whole buffer) —
  the reliable way to lift an error message out of the console, since SwiftUI
  drag-selection across rows isn't dependable. New `Pasteboard` helper.

## 0.4.1 — 2026-06-18

### Fixed

- **Crash when removing a server in Settings** ("Index out of range",
  EXC_BREAKPOINT). The Servers editor's `Binding<ServerProfile>` captured an
  array *index*; deleting a server shrank the array while SwiftUI still read the
  old binding, indexing past the end. The binding now resolves the profile by
  **id** inside its get/set closures (degrading to a default / no-op if the
  server is gone), never by a captured index. Regression tests added; the
  binding-safety tests also confirm `SettingsStore(directory:)` so tests no
  longer touch the real user `settings.json`.

## 0.4.0 — 2026-06-18

### Added

- **Multi-server** — connect to several IRC networks at once (classic Ircle
  did up to ten), each its own `IrcleSession`. `IrcleModel` went from one
  `session` to `[IrcleSession]`:
  - The **Channelbar groups buffers by server**, with a thin divider between
    networks; selecting any buffer switches context.
  - Selection, **per-session focus** (background servers keep accruing unread),
    input routing, and buffer-close all resolve to the buffer's owning session.
  - Connecting the same saved profile twice **focuses the existing session**
    (and reconnects it if dropped) instead of duplicating it.
  - Closing a **server buffer** disconnects and removes that whole connection.
- **Multi-server Settings** — the "Servers" tab is now a list (add / remove /
  duplicate) plus a per-server editor, a connected indicator, and per-server
  Connect/Disconnect.
- A **Servers menu** listing every saved profile ("Connect to …") plus
  "Disconnect Current". The status bar shows a "*N* servers" badge when more
  than one is open.
- 7 model tests (open multiple, dedup per profile, selection+focus tracking,
  owner lookup, remove/reselect, close-server-removes-session, input routing).

## 0.3.0 — 2026-06-18

### Added

- **Faces window** — a separate window (like classic Ircle) showing a grid of
  avatars for the people on the focused channel. Each face is a **locally
  assigned image** (right-click → Assign Image…, persisted) or a generated
  **monogram** (deterministic color + initials from the nick — no network art).
  Per-face actions: Assign/Remove image, Query, Whois; double-click opens a
  query. Open it with ⌘⇧F, the Window menu, or the "Faces" button in the nick
  list. Small avatars now also appear beside each name in the nick list.
- `FaceGraphics` (pure: stable FNV-1a hue + initials), `FacesStore` (nick →
  image, persisted to `Application Support/Ircle/faces.json` + `Faces/`, so
  faces ride along in the launch backup), `AvatarView`, `FacesView`.
- 7 tests (hue determinism + case-folding + range, initials, and the store's
  assign/copy, reassign-replaces-file, clear, and persist-across-instances).

### Fixed

- Window sizing made robust against SwiftUI's unreliable macOS-14 scene sizing:
  the `AppDelegate` now grows any window that comes up degenerate (Spacer-driven
  ~100×110) to a usable size on `didBecomeKey`, guarded by a degeneracy
  threshold so it never disturbs the Settings window. Covers both the main and
  Faces windows.

## 0.2.0 — 2026-06-18

### Added

- **mIRC color & formatting rendering** in the message area — the colored chat
  Ircle was known for. New `MircRenderer` (app-layer, SwiftUI) turns mIRC codes
  into an `AttributedString`: bold, italic, underline, strikethrough, reverse,
  reset, the 16-color palette, and IRCv3 hex (`^D`) colors. `MessageRow` now
  paints message/action/notice/topic/MOTD bodies in color instead of stripping
  codes to plain text; the classic per-kind prefix (`<nick>`, `* nick`,
  `-nick-`, `***`, `!!!`) is drawn separately and nicks are colored.
- 8 renderer tests (visible-text-equals-stripped invariant, base color, color
  code → foreground, reset-to-base, fg/bg pair, hex color, incomplete-hex
  fallback, plain prefix helper).

### Notes

- IRCKit stays Foundation-only; `IRCText.stripFormatting` remains the engine's
  plain-text path (matching/logs). Rendering lives in the app, as designed.
- mIRC colors render literally (e.g. color 0 = white): authentic, but a
  white-on-white edge case exists on the light Platinum theme — theme-aware
  contrast clamping is a possible later refinement.

## 0.1.0 — 2026-06-18

Initial MVP. A clean-room nostalgic recreation of the classic Mac *Ircle* IRC
client on current macOS, built on the shared [IRCKit](../IRCKit) wire engine.

### Added

- **Platinum single-window UI** evoking the classic Ircle arrangement: the
  signature horizontal **Channelbar** of beveled buffer buttons (with unread
  badges + mention highlighting), an inset **topic bar**, the monospaced
  (Monaco) **message area** colored by line kind, the right-hand **nick list**
  ("N users" + mode prefixes + Query/Whois/Op/DeOp actions), the **input line**
  with B/I/U formatting buttons, and a **status bar**.
- **Two themes** — Platinum (classic light grey, default) and Graphite (dark),
  via reusable `PlatinumPalette` + `platinumBevel` 3D-bevel chrome.
- **`IrcleSession`** — a focused session layer over IRCKit's `IRCClient`:
  channel/query buffers, nick-list bookkeeping (JOIN/PART/QUIT/NICK/KICK/NAMES),
  topic tracking, PING/PONG, CTCP (VERSION/PING/TIME + `/me`), mention
  detection, auto-join on RPL_WELCOME, and the slash-command set
  (`/join /part /msg /query /me /nick /topic /whois /quit /raw`).
- TLS / SASL (PLAIN, EXTERNAL) / server-password / proxy support via IRCKit.
- **Settings** (Connection / Appearance / Backup) persisted to
  `~/Library/Application Support/Ircle/settings.json`.
- **Auto-backup-on-launch** per the PhantomLives standard: zips Application
  Support to `~/Downloads/Ircle backup/`, 14-day retention, 5-min debounce,
  never-throws, with the full Settings → Backup UI (run / test / restore /
  reveal).
- Repo-standard tooling: deterministic `Scripts/generate-icon.swift` (a
  Platinum window with a channel `#`), `build-app.sh` (build → /Applications →
  relaunch + freshness proof), the four-step hardened `install.sh`,
  `run-tests.sh`.

### Tests

18 swift-testing tests: the four required backup tests (debounce, retention
trim, target-dir auto-create, list ordering) plus verify/round-trip, nick-list
maintenance, user ordering, case-folding, and session plumbing
(query dedupe, local echo, buffer close).

### Notes

- mIRC color codes are **stripped** to plain text in the message area for the
  MVP; full color rendering is planned.
- "Ircle" is an existing discontinued product name; this is a personal
  nostalgic recreation (see README → Naming).
