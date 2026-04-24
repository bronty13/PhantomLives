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
- Automatic `PING`/`PONG`, `433` nick-collision retry, `001` welcome handling
- Channels, private messages (queries), server log buffer
- JOIN / PART / QUIT / NICK / TOPIC / NAMES tracking with a live user list
- Slash commands: `/join`, `/part`, `/msg`, `/me`, `/nick`, `/topic`,
  `/whois`, `/names`, `/close`, `/raw`, `/quit`, `/watch`, `/unwatch`
- Input history (↑ / ↓) and a raw protocol log viewer (IRC → Show Raw Log)
- Auto-join list on the connect form, unread badges in the sidebar
- **Own-nick highlight**: messages mentioning your nick are tinted orange,
  marked with `@`, and fire the same sound / banner / dock-bounce alerts
  used for the watchlist

### Setup window (⌘,)

Three tabs, all persisted to `~/Library/Application Support/PurpleIRC/settings.json`:

- **Servers** — named server profiles (host, port, TLS, nick/user/realname,
  password, auto-join). Each profile also carries its own **SASL**
  mechanism/account/password, a **NickServ** fallback password, a
  **perform-on-connect** script, and an **auto-reconnect** toggle. Pick
  the active profile; Connect uses it.
- **Address Book** — watched contacts with optional notes. Each entry has a
  "watch" toggle that drives the real-time online alerts.
- **Channels** — saved channels with one-click Join from the sidebar; also
  auto-join on connect (on top of the profile's auto-join list).

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
