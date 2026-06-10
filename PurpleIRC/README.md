# PurpleIRC

Native macOS IRC client, written in Swift/SwiftUI. Uses Apple's `Network`
framework for the TCP/TLS transport, a hand-rolled RFC 1459-style parser,
and a SwiftUI UI built on a manual fixed-width sidebar (a plain `HStack`,
not `NavigationSplitView` — see the layout note at the bottom).

## Requirements
- macOS 14 (Sonoma) or newer
- Swift 5.9 / Xcode 15 or newer (ships with Command Line Tools)

## Build & Run

```sh
./build-app.sh            # build + install to /Applications + relaunch
./build-app.sh --no-open  # build + install, no focus-stealing relaunch
./build-app.sh --no-install   # build only (legacy behavior)
./install.sh              # re-install the last-built bundle
./run-tests.sh            # 332 tests via swift-testing
```

`build-app.sh` defaults to **build + install + relaunch**: it builds
`PurpleIRC.app`, replaces `/Applications/PurpleIRC.app` via `install.sh`
(`ditto --noextattr`, after quitting the running copy), and reopens it.
Installing to `/Applications/` keeps TCC grants, Launch Services, and the
AppleScript dictionary bound to a stable bundle path across rebuilds.

The script produces a release build by default; set `CONFIG=debug` for a
debug build.

You can also iterate with `swift build` + `swift run`, but the UI will only
activate correctly when launched from the `.app` bundle (SwiftUI's
`WindowGroup` needs `Info.plist`).

### Code signing

`build-app.sh` auto-detects a **Developer ID Application** certificate
in your login keychain (via `security find-identity -v -p codesigning`)
and signs with it when found, falling back to ad-hoc signing
otherwise. When a real cert is used the script also enables the
hardened runtime and embeds an Apple-issued timestamp so the bundle
is eligible for `xcrun notarytool submit`.

Override the auto-detection via env var:

```sh
# Force ad-hoc (CI / fresh contributor without a cert)
CODESIGN_IDENTITY="-" ./build-app.sh

# Pin to a specific cert when multiple are installed
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

The script builds + signs in `mktemp -d` and `ditto`s the finished
bundle back into the project directory. This sidesteps an iCloud
Drive race where `com.apple.FinderInfo` re-attaches to fresh files
under `~/Documents` and breaks `codesign --strict`. See HANDOFF.md
for the full architecture.

### Auto-updates (Sparkle) + releasing

PurpleIRC auto-updates via [Sparkle 2](https://sparkle-project.org/): it
checks its release feed on launch and roughly every 24 hours, and you can
check any time via **PurpleIRC ▸ Check for Updates…** or **Setup ▸ Updates**.
Updates are EdDSA-signed and verified against a key embedded in the app
before installing.

A formal, machine-independent release process produces a **notarized,
stapled, EdDSA-signed** zip, a tagged GitHub release, and a new `appcast.xml`
entry — so existing installs are offered the update and a direct download
still opens cleanly on any Mac:

```sh
./Scripts/release.sh
```

It pre-flights signing/notary/`gh`/Sparkle-key state, builds with
notarization on, verifies the staple (`stapler validate` + `spctl -a`), zips
to `~/Downloads/PurpleIRC release/PurpleIRC-<version>.zip`, signs it with
`sign_update`, tags + publishes `purpleirc-v<version>` via `gh`, then
prepends an `<item>` to `appcast.xml` and pushes it. Runs identically from
either dev machine (Vortex / MB14) using that Mac's own keychain credentials.

→ One-time per-machine setup (Developer ID cert, notary profile, `gh auth`,
the shared Sparkle EdDSA key), the per-release flow, and troubleshooting are
in **[RELEASING.md](RELEASING.md)**.

`build-app.sh` also notarizes on its own when `NOTARIZE_PROFILE` is set
(routine personal builds leave it unset and skip notarization); the Sparkle
public key comes from `SPARKLE_PUBLIC_KEY` (placeholder when unset, so
personal builds embed a safe non-installing key).

## Features
- TLS & plain-text TCP (defaults to `irc.libera.chat:6697` over TLS)
- Connect form with nick / user / real name / server password
- **SASL PLAIN / EXTERNAL** via CAP LS 302, plus **NickServ IDENTIFY** fallback
- **Perform-on-connect** lines (raw IRC or slash commands, per server profile)
- **Auto-reconnect** with exponential backoff when the connection drops
- Automatic `PING`/`PONG`, bounded `433` nick-collision retry (4 fallback
  attempts before surfacing an error), `001` welcome handling
- Channels, private messages (queries), server log buffer
- JOIN / PART / QUIT / NICK / TOPIC / NAMES tracking with a live user list
- Slash commands: 60+ entries in `Commands.swift`, surfaced in the
  `/`-autocomplete strip and the `/help` sheet. Highlights:
  - Channels: `/join` `/part` `/rejoin` `/topic` `/names` `/mode`
    `/list` `/close` `/invite` `/knock`
  - Messages: `/msg` `/query` `/me` `/notice` `/ctcp` `/raw`
  - Identity: `/nick` `/away` `/back` `/identity`
  - Moderation: `/op` `/deop` `/voice` `/devoice` `/kick` `/ban`
    `/unban` `/ignore` `/silence`
  - User lookup: `/whois` `/whowas` `/seen` `/watch` `/unwatch`
  - Server info: `/motd` `/lusers` `/admin` `/info` `/version`
  - Window & buffer: `/clear` `/find` `/markread` `/next` `/prev`
    `/goto` `/network`
  - Appearance: `/theme` `/font` `/density` `/zoom` `/timestamp`
  - Logs: `/log` `/logs` `/export`
  - Automation: `/alias` `/repeat` `/timer` `/summary` `/translate`
  - Dangerous: `/lock` `/backup` `/nuke` (the last is a two-step
    typed-confirmation destructive reset)
- **Full macOS menu system** — File, Edit, View, Buffer, Network,
  Conversation, Help — backed by typed `ChatModel` methods and the
  same slash dispatcher, with built-in keyboard shortcuts for every
  menu action.
- Input history (↑ / ↓) and a raw protocol log viewer (IRC → Show Raw Log)
- Auto-join list on the connect form, unread badges in the sidebar
- **Own-nick highlight**: messages mentioning your nick are tinted orange,
  marked with `@`, play the *mention* event sound, and fire the banner /
  dock-bounce alert channels. Alerts are **deduped per sender** (one alert
  per person per few seconds, shared across the mention / highlight-rule /
  watchlist paths) and **quiet mode** (on by default, Setup → Notifications
  & Sounds) skips the sound + banner + bounce entirely when you're already
  looking at the buffer the message landed in
- **Right-click a nick → “Find … in logs”** — a dedicated sheet that surfaces
  every persisted log line *authored by* that nick, with **fuzzy variant
  matching** (finding `john_doe` also turns up `johndoe1`, `johnny1`, …). A
  live fuzziness slider tunes how far variants reach, and clicking a result
  jumps to its buffer. Keys off the line's author, so mention-only lines are
  excluded (unlike the ⌘⇧F substring search)
- **Per-contact message sounds** — each Address Book contact can name its own
  sound (Address Book → Alert overrides → *Message sound*) that plays on **any**
  message from that person, a private query or a channel line. Contacts without
  one fall back to the global per-event sounds in Setup → Notifications &
  Sounds (which carry the customizable defaults for own-nick mentions, private
  messages, etc.). A configurable **per-nick throttle** (same tab, default 5s) keeps a
  chatty contact from stuttering the sound — at most one play per contact per
  window
- **Query scrollback from logs** — opening a private conversation pre-loads the
  last *N* lines from that person's saved log as scrollback, framed by `── N
  lines from logs ──` / `── end of history ──` markers, so you pick up with
  context instead of an empty window. On by default; toggle and line count live
  in Setup → Logging → *Query history*. Reads existing logs only — nothing new
  is recorded unless persistent logging is on

### Security posture

- **Credentials are masked in the raw IRC log and the in-app debug log.**
  `PASS …`, `AUTHENTICATE …` (control markers `+`/`*` preserved), and
  `PRIVMSG NickServ :IDENTIFY [acct] …` all render as `****` in the
  viewer. The bytes on the wire are unchanged.
- **Outbound IRC lines are scrubbed for CR / LF / NUL** at every API
  boundary (slash commands, AppleScript, PurpleBot scripts) and again
  at the wire seam. A multi-line PRIVMSG body is collapsed into one
  line rather than smuggling a second IRC command.
- **Settings, logs, the keystore, and PurpleBot scripts are written
  with owner-only POSIX perms (`0600`).** When the user has set up a
  passphrase, every persistence file is also AES-256-GCM sealed with
  a per-install DEK.
- **DCC listener binds to the IP it advertises**, not `0.0.0.0`,
  so a peer on the same LAN can't race the legitimate recipient
  to grab the file. Passive (reverse) DCC is still on the roadmap
  for full NAT-friendly transfers — see HANDOFF.md.

### Setup window (⌘,)

Open it from **PurpleIRC → Settings…** (⌘,) or the toolbar gear.
19 tabs in 6 sidebar groups (mirroring macOS System Settings), all
persisted to `~/Library/Application Support/PurpleIRC/settings.json`:

- **Connections** — Servers, Identities, DCC Transfers
- **People & places** — Channels, Ignore, Highlights
- **Behavior** — Behavior, Notifications & Sounds, Logging
- **Personalization** — Appearance, Themes, Fonts
- **Power-user** — Bot, PurpleBot, Assistant, Shortcuts & Aliases, Backup, Updates
- **Security** — Security

Every alert-related knob — quiet mode, watch-hit channels, own-nick
mention, per-event sounds, the per-contact sound throttle — lives in the
single **Notifications & Sounds** tab (the old separate Sounds tab was
merged into it). The only alert settings elsewhere are deliberately
scoped: per-rule overrides on the Highlights rule editor, per-contact
overrides on the Address Book contact card.

The biggest tabs:

- **Servers** — named server profiles (host, port, TLS, nick/user/realname,
  password, auto-join). Each profile also carries its own **SASL**
  mechanism/account/password, a **NickServ** fallback password, a
  **perform-on-connect** script, and an **auto-reconnect** toggle.
- **Address Book** — watched contacts with optional notes, **profile
  photos** (auto-downscaled to ≤256 px JPEG), **encrypted file
  attachments** (any size, stored in the per-install AES-GCM-sealed
  blob store), and **user-defined tags** (any number per contact,
  optional per-tag color from a 12-entry rotating palette;
  deleting a tag cascades across every contact). Each contact editor
  also surfaces **exact + fuzzy matches** of the nick against every
  connected network's seen log and the chat-log archive, with
  one-click jumps to the seen list, the chat-log viewer, or `/query`.
  Both the contact list and the Tag Manager support **cmd-click /
  shift-click multi-select with bulk delete**; new contacts and tags
  are seeded with auto-numbered placeholder names (`New Contact 1`,
  `New Tag 1`, …) that walk forward and stop at the first gap, and
  duplicate names / nicknames trigger a non-blocking warning under
  the field. A toolbar shortcut (`person.crop.rectangle.stack`)
  opens the tab in one click.
- **Channels** — saved channels with one-click Join from the sidebar; also
  auto-join on connect (on top of the profile's auto-join list).
- **Themes** — 16 built-in themes (Classic, Midnight, Solarized
  light/dark, Nord, Dracula, Tokyo Night, Lavender, Royal Purple,
  Twilight, …) plus a **WYSIWYG Theme Builder** with a live preview
  pane, per-event color overrides (paint joins / parts / kicks /
  notices independently), and `.purpletheme` JSON import/export.
  Per-network theme overrides on each `ServerProfile` so different
  networks look visually distinct at a glance.
- **Fonts** — pick any installed family via the searchable picker
  (with a Monospaced-only filter for the chat body). Per-element
  fonts: chat body, nick column, timestamp column, system lines —
  each with its own family / size / weight / italic / ligatures /
  letter-spacing / line-height. The chat-body slot is the
  inheritance root; per-element slots only override what they
  care about.
- **Shortcuts & Aliases** — define `/alias <name> <expansion>` entries;
  resolved before built-in commands, so you can shadow them on purpose.

The sidebar exposes a **Saved** section (quick-join) and a **Contacts**
section (click to open a `/msg` draft; bell icon + dot show watch + presence).

**Drag-to-reorder individual rows** is wired into every sidebar group:
networks, channels, private queries, saved channels, and contacts. Each
section's `ForEach` is `.onMove`-enabled, so picking up a row and dragging
it to a new position within the same section reorders the underlying
list. Reorders within a kind (e.g. channel buffers) preserve the
positions of other kinds in the underlying array, so a channel reorder
doesn't disturb queries or the (hidden) server-console buffer.

**Per-buffer message-kind filter.** The funnel icon in any buffer header
opens a checkbox grid for system info, errors, MOTD, notices, joins,
parts, quits, nick changes, and topic changes. Toggles write a per-buffer
override into `AppSettings.messageFiltersByBuffer`; "Use defaults" drops
the override, "Save as default" promotes it into the app-wide defaults
edited in Setup → Behavior → "Default message filter". PRIVMSG / ACTION
lines always render — the popover footer flags this so the user doesn't
go looking for a toggle that would silently swallow the conversation.

**The per-network `*server*` console has no sidebar row of its own.** The
**Networks** row *is* the server: click the already-active network's row
(or right-click → **Server Console**) to open the console with the MOTD,
notices, and raw server replies; unread console traffic badges on the
network row. The console buffer is in-memory only and **purged at app
launch** so each session starts clean — the connection re-creates it the
moment something needs to log to it, so the purge never loses persisted
state.

### Watchlist / online alerts
- Who is watched comes from Setup → Address Book (entries with the bell
  toggle enabled). `/watch <nick>` and `/unwatch <nick>` edit the same
  address book on the fly.
- When the server supports the IRCv3 `MONITOR` capability (Libera, most
  modern solanum/inspircd servers), PurpleIRC registers the list and
  receives `730` (online) / `731` (offline) numerics in real time.
- Otherwise it falls back to `ISON` polling every 30 seconds.
- Watched users that JOIN a channel you're in or PRIVMSG anywhere also
  count as a sighting, so you're alerted even when `MONITOR` isn't
  available for that user.
- Prominence: each hit fires a macOS banner (UNUserNotificationCenter),
  plays a sound, bounces the Dock icon (critical), shows a persistent
  purple banner at the top of the main window, stars + tints that user's
  PRIVMSG lines, appends a line to the server buffer, and is recorded in
  the "Recent hits" list inside the Watchlist sheet. Each alert channel
  has its own toggle in Setup.
- A **Test notification** button in the Watchlist sheet fires a synthetic
  hit so you can confirm macOS has granted permission.
- The first time you launch, macOS will ask for notification permission.

## Layout

`HANDOFF.md` is the canonical architecture snapshot — read it before any
non-trivial change. The high-level map of `Sources/PurpleIRC/`:

```
App.swift / AppDelegate.swift   @main scene, menu commands, launch hooks
ContentView.swift               Manual HStack sidebar + toolbar + sheets
WindowStateGuard.swift          Purges stale persisted window/split state
BufferView.swift                Messages pane, user list, input bar, raw log
ChatModel.swift                 @MainActor store + slash-command dispatch
IRCConnection.swift             One per network: client + buffers + reconnect
IRCClient.swift                 NWConnection transport, line buffering, SASL/CAP
IRCMessage.swift                RFC 1459 line parser  ·  IRCFormatter / IRCSanitize
SASLNegotiator.swift            SASL PLAIN / EXTERNAL state machine
ProxyFramer.swift               SOCKS/HTTP proxy at the bottom of the stack
DCC.swift / DCCView.swift       File transfers + direct chats
Crypto.swift / KeyStore.swift / EncryptedJSON.swift / BlobStore.swift
                                AES-256-GCM at-rest encryption + key wrapping
SettingsStore.swift             settings.json model + persistence
LogStore.swift / SeenStore.swift / SessionHistoryStore.swift / AppLog.swift
                                Chat logs, seen tracker, replay archive, diag log
BotHost.swift / BotEngine.swift / ScriptStore.swift
                                PurpleBot (JavaScriptCore) + native trigger bot
AssistantEngine.swift / OllamaClient.swift   Local-LLM assistant
WatchlistService.swift / WatchlistView.swift  MONITOR/ISON + notifications
Commands.swift                  60+ slash-command table + /help metadata
AddressBook/                    Contacts workspace (linked nicks, timeline, tags)
Setup/                          20-tab Setup window, one file per tab group
```

### Sidebar layout note

The top-level sidebar is a plain `HStack` with a fixed-width column, **not**
`NavigationSplitView`. `NavigationSplitView` on macOS 14+ doesn't reliably
honor its declared minimum column width at runtime and persists a corruptible
divider position; the manual layout owns every pixel. `WindowStateGuard`
(wired from `AppDelegate`) sanitizes any stale persisted window/split state on
launch, and **Window → Reset Window State…** is the user-facing recovery
affordance. See CLAUDE.md for the full incident history.
