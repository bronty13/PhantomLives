# PurpleIRC — Handoff

Snapshot of where the project stands so a future session (human or AI)
can pick up without re-deriving everything from the commit history.
Last updated: 2026-04-24, at commit `9491157`.

## What it is

Native macOS IRC client, SwiftUI + Apple Network framework. SwiftPM
package; ships as a real `.app` bundle via `build-app.sh` (needed so
`UNUserNotificationCenter` authorization works).

```
swift build                        # debug build
./build-app.sh                     # release build → PurpleIRC.app
open PurpleIRC.app
```

Requires macOS 14+, Swift 5.9+.

## Architecture at a glance

- `ChatModel` — `@MainActor` top-level store. Holds the active connection
  list, the shared `WatchlistService`, `SettingsStore`, `LogStore`,
  `BotHost`, and `DCCService`.
- `IRCConnection` — one per network. Owns an `IRCClient`, its buffers,
  reconnect state, and a `PassthroughSubject<(UUID, IRCConnectionEvent), Never>`.
- `IRCClient` — RFC 1459 parsing + `NWConnection` transport. SASL
  (PLAIN / EXTERNAL) and CAP negotiation live here. The proxy
  (`ProxyFramer`) plugs in at the bottom of the protocol stack.
- `BotHost` — JavaScriptCore scripting host (PurpleBot). Subscribes to
  merged events at `ChatModel.events`.
- `DCCService` — file transfers and direct chats (`NWListener` for
  outgoing offers, `NWConnection` for inbound pulls).

Event fan-out: every inbound/outbound line, state change, PRIVMSG,
NOTICE, JOIN, etc. flows through `IRCConnectionEvent` (defined in
`IRCConnection.swift`). `Sendable` enum so off-main-actor consumers are
safe. `ChatModel.events` is the merged stream.

## Tier status

| # | Tier                        | Status                        | Commit    |
|---|-----------------------------|-------------------------------|-----------|
| 1 | Biggest daily-use gaps      | Done                          | `142698d` |
| 2 | Logs, ignore, CTCP, away    | Done                          | `42fa050` |
| 3 | Icon, PurpleBot, sounds/themes, proxy, DCC | Done (DCC experimental) | `44c495b`, `9491157` |
| 4 | mIRC scripting-lang, DLLs, identd, UPnP | Skipped — questionable ROI | — |

### Tier 1 (shipped)
1. SASL (PLAIN + EXTERNAL) + NickServ auto-identify.
2. Auto-reconnect + perform-on-connect lines.
3. Own-nick highlight detection with its own alert channel.
4. Clickable URLs + tab completion.
5. mIRC color/format rendering.
6. Multi-network foundation (one active in the UI at a time).

### Tier 2 (shipped)
7. Persistent logs (4 MB rotation per channel) + find-in-buffer (⌘F).
8. Ignore list (`/ignore`, `/unignore`) + CTCP replies.
9. Away system (`/away`, `/back`) with per-sender throttled auto-reply.
10. Channel topic/mode clickable UI, user list context menu.

### Tier 3 (shipped)

**Icon.** Purple dinosaur generated at build time via
`Scripts/generate-icon.swift` → `iconutil -c icns` → `AppIcon.icns`.
Regenerated every `./build-app.sh` run.

**PurpleBot (JavaScriptCore host).** Scripts live at
`~/Library/Application Support/PurpleIRC/scripts/<name>.js`, indexed in
`scripts/index.json`. The host injects `irc`, `console`, and a timer
API. Reloadable via `/reloadbots` or the Scripts tab in Setup.

Script API surface:
- `irc.on(event, handler)` — event names: `privmsg`, `notice`, `join`,
  `part`, `quit`, `topic`, `ctcpRequest`, `awayChanged`, `state`,
  `inbound`, `outbound`, `ownNickChanged`, `ignoredMessage`, or `event`
  (generic firehose).
- `irc.onCommand(name, handler)` — claim a `/alias`.
- `irc.send(rawLine)`, `irc.sendActive(rawLine)`.
- `irc.msg(target, text)`, `irc.notice(target, text)`.
- `irc.setTimer(ms, fn)`, `irc.setTimeout(ms, fn)`, `irc.clearTimer(id)`.
- `irc.networks()` → `[{id, name}]`, `irc.activeNetwork()`.
- `irc.notify(title, body)`.
- `console.log(...)` → bot log panel.

Each event handler receives a plain JS object: `{networkId,
networkName, ...event-specific fields...}`. Raw mIRC codes are
preserved — scripts see `.text` as-is.

Forward-compat rules enforced by the host:
- `ChatLine.text` stays raw; stripping happens at render time via
  `IRCFormatter.stripCodes`.
- All bot-visible events are `Sendable`, UUID-tagged by connection.
- `PassthroughSubject` has no replay buffer; scripts loaded later miss
  older events. Re-loading is idempotent per script file.
- `IRCConnection.sendRaw(_:)` is the bot's outbound entry point —
  `IRCClient` stays per-instance so scripts can spin up new networks
  later.

**Sounds + themes.** Per-event sound pack (mention, watchlist hit, PM,
connect/disconnect, CTCP) with built-in NSSound name picker and a ▶
preview. Three themes (`classic`, `midnight`, `candy`) drive nick
palette + highlight/mention/watchlist row backgrounds via
`ChatModel.theme` read at render time by `MessageRow`.

**Proxy (SOCKS5 / HTTP CONNECT).** `ProxyFramer` is an
`NWProtocolFramer` inserted at the bottom of the protocol stack so
TLS-through-proxy works end-to-end. Per-server config under Setup ▸
Servers ▸ Proxy. Config is passed to framer instances via a FIFO
static registry (the framer init can only see the framer instance,
not its options payload). Failures propagate via
`ProxyFramer.lastError` which `IRCClient` reads when the connection
state flips to `.failed`.

**DCC SEND / GET / CHAT (experimental).** Transfers sheet at ⌘⇧T.
`/dcc send <nick> [path]` offers a file (NSOpenPanel if no path).
`/dcc chat <nick>` opens a chat listener. Inbound CTCP `DCC SEND` /
`DCC CHAT` offers surface in the sheet for accept/reject.
Receiver sends cumulative 4-byte big-endian ACKs per chunk.
External IP + port range configurable under Setup ▸ Behavior ▸ DCC.

## Known gaps (good "pick up here" work)

### DCC — end-to-end validation
The protocol wire-up compiles and looks right, but two-client
validation has not been done. If you pick this up:

1. Test on-LAN between two Macs (one offers, one accepts) — simplest
   signal the `NWListener` + ACK loop works.
2. Test inbound `DCC SEND` from a well-known client (HexChat, mIRC) —
   confirms the CTCP tokenizer handles quoted filenames and the
   int-form IP.
3. Test inbound `DCC CHAT` from HexChat — confirms the chat line
   framing (`\n`-terminated) is right.
4. Add RESUME (client sends `DCC RESUME filename port offset`, peer
   replies `DCC ACCEPT …`).
5. Add passive/reverse DCC (port=0 + token). Needed for NAT'd peers.

All the byte-handling is in `Sources/PurpleIRC/DCC.swift`; the
UI-only surface is `DCCView.swift`. Port range + external IP live in
`AppSettings.dcc*` fields.

### Proxy — surface auth
TLS-through-proxy is wired up, but the proxy auth failure paths only
surface through `ProxyFramer.lastError` appended to the underlying
NWConnection error. Consider promoting this to an inline info line in
the server buffer.

### PurpleBot — no persistence for script state
Scripts can compute state but the host doesn't provide a key/value
store. Cheap to add: a `irc.store.get(key)` / `irc.store.set(key, v)`
backed by a JSON file under the support dir, scoped per-script.

### Multi-network UI
`ChatModel.connections: [IRCConnection]` exists, but the sidebar only
shows the active connection's buffers. A picker at the top of
`SidebarView` to switch connections would light this up — the
underlying machinery already works.

### Tier 4 items (deferred intentionally)
Full mIRC scripting-language compat (`/variable`, `$identifier`,
aliases files), DLL loading, identd server, UPnP. Low ROI; PurpleBot
supersedes the scripting motivation.

## Repo layout

```
PurpleIRC/
├── build-app.sh                Release build + icon gen + .app packaging
├── Package.swift
├── Scripts/
│   └── generate-icon.swift     Runs during build-app.sh
└── Sources/PurpleIRC/
    ├── App.swift               @main, CommandMenu
    ├── ChatModel.swift         @MainActor top-level store
    ├── ContentView.swift       NavigationSplitView, sheets
    ├── SidebarView             (in ContentView.swift)
    ├── BufferView.swift        Messages pane + find bar + user list
    ├── MessageRow              (in BufferView.swift) — theme-aware
    ├── SetupView.swift         Tabbed preferences sheet
    ├── WatchlistView.swift
    ├── WatchHitBanner.swift
    ├── IRCConnection.swift     Per-network orchestrator
    ├── IRCClient.swift         NWConnection transport
    ├── IRCMessage.swift        RFC 1459 parser
    ├── IRCFormatter.swift      mIRC codes → AttributedString
    ├── SettingsStore.swift     AppSettings + JSON persistence
    ├── LogStore.swift          Off-main-actor log writer
    ├── WatchlistService.swift
    ├── BotHost.swift           PurpleBot (JavaScriptCore)
    ├── SoundsAndThemes.swift   Event sound pack + theme presets
    ├── ProxyFramer.swift       SOCKS5 / HTTP CONNECT framer
    ├── DCC.swift               DCCService / DCCTransfer / DCCChatSession
    └── DCCView.swift           Transfers sheet
```

Support directory (app settings + scripts + logs + downloads):

```
~/Library/Application Support/PurpleIRC/
├── settings.json
├── scripts/
│   ├── index.json
│   └── *.js
├── logs/
│   └── <network>/<buffer>.log
└── downloads/                  Default DCC GET destination
```

## Upstream mirror

Repo mirror: <https://github.com/bronty13/PhantomLives> (monorepo).
PurpleIRC lives under `PurpleIRC/`. The working tree at the dev path
below is the authoritative source; `build-app.sh` runs from there and
sync-to-mirror is a manual `cp -R Sources` + commit from `/tmp/PhantomLives`.

## Tip for the next pickup

`memory/purpleirc_tiers.md` in the Claude session store tracks the
tier plan across conversations. The commit log is the other source
of truth — `git log PurpleIRC/` is concise and has the motivation for
each tier in the commit bodies.
