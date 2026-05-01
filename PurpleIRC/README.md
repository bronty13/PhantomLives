# PurpleIRC

Native macOS IRC client, written in Swift/SwiftUI. Uses Apple's `Network`
framework for the TCP/TLS transport, a hand-rolled RFC 1459-style parser,
and a SwiftUI + `NavigationSplitView` UI.

## Requirements
- macOS 14 (Sonoma) or newer
- Swift 5.9 / Xcode 15 or newer (ships with Command Line Tools)

## Build & Run

```sh
./build-app.sh            # builds PurpleIRC.app
open PurpleIRC.app           # launch
```

The script produces a release build by default; set `CONFIG=debug` for a
debug build.

You can also iterate with `swift build` + `swift run`, but the UI will only
activate correctly when launched from the `.app` bundle (SwiftUI's
`WindowGroup` needs `Info.plist`).

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
  marked with `@`, and fire the same sound / banner / dock-bounce alerts
  used for the watchlist

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

20 tabs in 6 sidebar groups (mirroring macOS System Settings), all
persisted to `~/Library/Application Support/PurpleIRC/settings.json`:

- **Connections** — Servers, Identities, Proxy & DCC
- **People & places** — Address Book, Channels, Ignore, Highlights
- **Behavior** — Behavior, Notifications, Logging
- **Personalization** — Appearance, Themes, Fonts, Sounds
- **Power-user** — Bot, PurpleBot, Assistant, Shortcuts & Aliases, Backup
- **Security** — Security

The biggest tabs:

- **Servers** — named server profiles (host, port, TLS, nick/user/realname,
  password, auto-join). Each profile also carries its own **SASL**
  mechanism/account/password, a **NickServ** fallback password, a
  **perform-on-connect** script, and an **auto-reconnect** toggle.
- **Address Book** — watched contacts with optional notes. Each entry has a
  "watch" toggle that drives the real-time online alerts.
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

```
Sources/PurpleIRC/
  App.swift            @main SwiftUI app + menu commands
  ContentView.swift    Sidebar + connect form + toolbar
  BufferView.swift     Messages pane, user list, input bar, raw log
  ChatModel.swift      @MainActor ObservableObject state + command dispatch
  IRCClient.swift      NWConnection wrapper, line buffering, send/receive
  IRCMessage.swift     RFC 1459 line parser
  WatchlistService.swift  MONITOR / ISON polling + UNUserNotifications
  WatchlistView.swift  Add/remove watched nicks, presence indicators
```
