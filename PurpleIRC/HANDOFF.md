# PurpleIRC — Handoff

Snapshot of where the project stands so a future session (human or AI)
can pick up without re-deriving everything from the commit history.
Last updated: 2026-04-25, at commit `08e85bd`.

## What it is

Native macOS IRC client, SwiftUI + Apple Network framework. SwiftPM
package; ships as a real `.app` bundle via `build-app.sh` (needed so
`UNUserNotificationCenter` authorization works, AppleScript dictionary
loads, etc.).

```
swift build                        # debug build
./build-app.sh                     # release build → PurpleIRC.app
./run-tests.sh                     # 83 tests via swift-testing
open PurpleIRC.app
```

Requires macOS 14+, Swift 5.9+. Tests run via Command Line Tools' bundled
`Testing.framework`; the wrapper script handles the rpath dance.

## Architecture at a glance

- `ChatModel` — `@MainActor` top-level store. Holds the connection list,
  the shared `WatchlistService`, `SettingsStore`, `LogStore`, `BotHost`,
  `BotEngine`, `KeyStore`, `DCCService`, and `SessionHistoryStore`.
- `IRCConnection` — one per network. Owns an `IRCClient`, its buffers,
  reconnect state, and a `PassthroughSubject<(UUID, IRCConnectionEvent), Never>`.
  Multiple connections per profile are supported.
- `IRCClient` — RFC 1459 parsing + `NWConnection` transport. SASL
  (PLAIN / EXTERNAL) and full IRCv3 CAP negotiation live here. The proxy
  (`ProxyFramer`) plugs in at the bottom of the protocol stack.
- `BotHost` — JavaScriptCore scripting host (PurpleBot, user-installable
  scripts). Subscribes to merged events at `ChatModel.events`.
- `BotEngine` — native bot: trigger rules + seen-tracker.
- `KeyStore` + `EncryptedJSON` — passphrase-derived KEK wrapping a per-
  install DEK; AES-256-GCM seals every persistence file.
- `DCCService` — file transfers and direct chats (`NWListener` outgoing,
  `NWConnection` inbound).
- `SessionHistoryStore` — per-network archive of recent chat lines; replayed
  into channel/query buffers on relaunch.
- `AppLog` — process-wide diagnostic log (debug → critical), encrypted on
  disk when keystore is unlocked.

Event fan-out: every inbound/outbound line, state change, PRIVMSG,
NOTICE, JOIN, etc. flows through `IRCConnectionEvent`. `Sendable` enum
so off-main-actor consumers are safe. `ChatModel.events` is the merged
stream across every connection, UUID-tagged so listeners can scope.

## Tier status

| # | Tier                                       | Status     | Commit |
|---|--------------------------------------------|------------|--------|
| 1 | Biggest daily-use gaps                     | Done       | `142698d` |
| 2 | Logs, ignore, CTCP, away                   | Done       | `42fa050` |
| 3 | Icon, PurpleBot, sounds/themes, proxy, DCC | Done (DCC experimental) | `44c495b` / `9491157` |
| 4 | mIRC scripting-lang, DLLs, identd, UPnP    | Skipped — questionable ROI | — |
| 5 | Encryption + identities + tests            | Done       | `516fa48` / `a58205d` / `d0cc021` |
| 6 | UX polish + appearance                     | Done       | `330dc50` / `4fa8501` / `cf9d37d` |
| 7 | IRCv3 modernization + bigger features      | Done       | `3715298` / `08e85bd` / `d457cf8` |
| 8 | Multi-network UX                           | Done       | `d457cf8` / `567a7e7` |

## What shipped since the last handoff (`9491157` → `08e85bd`)

This is most of the surface area worth a future-session brief. Grouped by
theme rather than chronologically.

### Encryption at rest (`a58205d`, `d0cc021`)
- `KeyStore` + `EncryptedJSON` envelope. PBKDF2-HMAC-SHA256 (300k
  iterations) derives a KEK from the user's passphrase; AES-256-GCM
  wraps a per-install DEK; the DEK seals every persistence file.
- Touch ID gate (`BiometricGate`) sits in front of the Keychain-cached
  DEK on relaunch. Biometric availability is detected via
  `LAContext.biometryType != .none` (more honest than
  `canEvaluatePolicy`, which returns false on ad-hoc-signed builds).
- Encrypted: `settings.json`, every channel log line, the seen store,
  the channel-list cache, bot script source, the app debug log, and the
  per-network session history (new this round).
- Sharp edge fixed: the in-init `selectedServerID = ...` mutation used
  to fire `didSet → save()` while the keystore wasn't bound yet, which
  clobbered the encrypted envelope with plaintext defaults at every
  launch. Fixed via `EncryptedJSON.safeWrite`'s `skippedLockedEncrypted`
  guard; it now refuses to overwrite an encrypted file when no key is
  in hand.

### Identities (`516fa48`, `330dc50`)
- Global identity list in `AppSettings.identities`. Each `ServerProfile`
  optionally links one via `identityID`.
- Identity overlays nick / user / realName / SASL creds / NickServ
  password at connect time. Linked identity wins; profile fields stay
  as the fallback.
- Identity is per-`IRCConnection` live state, not per-profile, so two
  connections to the same server can run different identities at once.
- Toolbar `IdentityMenu` switches the active connection's identity;
  reconnect required for SASL/NICK changes to land server-side.
- `pendingSetupTab` one-shot directive routes "Manage identities…"
  straight to the right Setup tab.

### Tests (`516fa48`)
- 83 tests across 6 suites (`swift-testing`, `import Testing`):
  IRC parser, SASL state machine, KeyStore + Crypto, HighlightMatcher,
  TriggerRule, SeenStore.
- `run-tests.sh` injects the Testing.framework rpath so the suite runs
  under Command Line Tools without Xcode.

### Setup overhaul (`2468537`, `4fa8501`, `330dc50`)
- Tabbed sidebar with grouped sections: Connections, People & places,
  Behavior, Personalization, Power-user.
- Tabs: Servers, Identities, Address Book, Channels, Ignores,
  Highlights, Bot, Scripts, Behavior, Appearance, Sounds, Security.
- Each tab is its own struct in `SetupView.swift`; master/detail layout
  for list-heavy tabs (Address Book, Highlights, Bot, etc.).

### Themes + appearance (`cf9d37d`, `4fa8501`, `16201e0`)
- ~10 themes including light/dark/Solarized/Sepia/Dracula/Paper plus
  flagship purple variants. `chatBackground` + `chatForeground` so light
  themes actually look light.
- Live theme grid with previews; immediate apply.
- Configurable timestamp format with 7 presets + custom.
- Font family + size pickers (10–24pt slider), bold-text + relaxed-row-
  spacing accessibility toggles.

### Address Book + Watchlist unification (`d66d712`)
- One ground truth: `AppSettings.addressBook`. Each entry has the
  notify flag and per-contact alert overrides (sound, dock bounce,
  banner, custom message).
- `WatchlistService.setWatchedList(_:)` is fed from the address book
  every settings sync.
- Sidebar Contacts section: double-click → `/query`, right-click full
  menu (open query, WHOIS, WHOWAS, notify toggle, edit entry, remove).
- Same address-book actions on the right-click menu of query rows in
  the Private section, channel user-list pane, and chat-body nicks.

### Seen tracker (`cf9d37d`)
- Per-network JSON file; `SeenEntry.history` rolling array (cap 50)
  records every sighting (msg / join / part / quit / nick).
- `SeenSighting` carries timestamp, kind, channel, detail, user@host.
- Nick-change forwarding: a `/seen alice` lookup follows alice → alice_
  renames so you don't lose the trail.
- `SeenListView` (sheet) shows everyone known on the active network
  with a per-nick history sheet on click.

### Watch Monitor (`1e7382e`, `19b7275`)
- Persistent secondary window, `Window(id: "watch-monitor")`, separate
  from the main window. Shows join/part/quit/nick activity across every
  connected network.
- `ActivityEvent` fed by a second `events.sink` in ChatModel, capped
  at 1000 records via `activityFeedCap`.
- Filter (kind), free-text search, pause/resume, auto-scroll.
- macOS state-restoration was auto-reopening it on launch; now closed
  via `closeWatchMonitorIfAutoRestored()` shortly after the main
  window appears. Toolbar button + IRC-menu item + ⇧⌘M still summon it.

### Highlight rules (`516fa48`)
- `HighlightMatcher` compiles regex / literal patterns once with a per-
  rule cache; invalidates on rule edit.
- Per-rule custom row color, matched-word tinting, plus per-rule sound
  / dock bounce / system notification toggles.
- `MessageRow.highlightBackground` honors rule color over the theme's
  `mentionBackground` fallback.

### IRCv3 modernization (`3715298`)
- `IRCMessage` parses IRCv3 `@key=value;…` tag block with full escape
  table. Helpers: `serverTime`, `msgID`, `account`, `batchRef`.
- CAP wishlist requests:
  `sasl server-time multi-prefix echo-message away-notify
  account-notify extended-join account-tag message-tags batch
  chathistory labeled-response msgid`. Multi-frame `CAP LS` is buffered
  before sending one combined `REQ`.
- Handlers wired: `AWAY` (away-notify, drives userlist away
  indicator), `ACCOUNT` (account-notify), `CHGHOST` (refresh user@host),
  `BATCH` +/- (chathistory replay brackets), extended-join account
  capture, server-time honored on chat lines, echo-message dedupe of
  self-PRIVMSGs.
- `CHATHISTORY LATEST <chan> * N` issued on self-JOIN when the cap is
  granted, capped at 20–100 per server-advertised limit.
- 9 new tag-parser tests; existing SASL tests rewritten for the new
  multi-cap negotiation contract.

### Multi-line paste + collapsible join/part (`3715298`)
- Multi-line paste detected in the input field's `onChange`, surfaces
  a confirmation dialog with "Send N lines / Open editor / Cancel."
  Editor is a `SpellCheckedTextEditor` with live line count.
- Consecutive join/part/quit/nick lines collapse into a
  `JoinPartSummaryRow` (5-min window). Click to expand; `collapseJoinPart`
  setting in Behavior. Single-event runs render normally — the pill
  is more noise than the raw line for one event.

### Right-click on nicks in chat body (`3715298`)
- `nickTag(_:)` helper renders nicks in privmsg/action/notice/join/part/
  quit/nick rows with their own context menu. Suppressed for the user's
  own nick on their own messages.
- Menu: open query, WHOIS, WHOWAS, CTCP VERSION/PING, op/voice/kick/
  ban, ignore, copy nick.

### AppleScript dictionary (`3715298`)
- `Resources/PurpleIRC.sdef` defines: `connect`, `disconnect [with reason]`,
  `send message <text> to <target>`, `join channel`, `part channel`,
  `current nickname`, `say in active buffer`.
- `AppleScriptCommands.swift` `NSScriptCommand` subclasses route through
  `AppleScriptBridge.host` (set in ChatModel.init).
- `build-app.sh` copies the .sdef into Contents/Resources and adds
  `NSAppleScriptEnabled` + `OSAScriptingDefinition` to Info.plist.

### App debug log (`3715298`)
- `AppLog.shared` with debug/info/notice/warn/error/critical levels;
  5000-record in-memory ring; encrypted file at `supportDir/app.log`.
- `LogViewerView` — modal sheet with level floor picker, search across
  level/category/message, autoscroll, copy-to-clipboard, refresh, clear.
- Reachable via `/log`, `/applog`, `/debuglog`, or Files menu.
- Connection state transitions and CAP-completion events seed the log
  with useful content.

### Spell-check (`d88c145` reverted, `21ee49e`/`d0bd63b` shipped)
- `SpellCheckBootstrap.installOnAllWindows()` registers a single
  `NSControl.textDidBeginEditingNotification` observer at app start.
  When ANY NSControl-backed text edit begins, the live field editor
  comes through `userInfo["NSFieldEditor"]` and we flip
  `isContinuousSpellCheckingEnabled = true` on it.
- Long-form editors use `SpellCheckedTextEditor` (NSViewRepresentable
  wrapping NSTextView): address book Markdown notes, away auto-reply,
  trigger-rule response, multi-line paste editor.
- Auto-correct, smart quotes, smart dashes, automatic text replacement
  stay OFF everywhere — IRC nicks and channel names look enough like
  English to repeatedly trip those.
- **Cautionary tale (`d88c145` → `3f6383b`):** an earlier attempt
  installed a global `NSWindowDelegate` to intercept
  `windowWillReturnFieldEditor:`. That hijacked SwiftUI's own delegate-
  driven window lifecycle (sheet dismissal, restoration callbacks) and
  prevented launch on some setups. **Don't go there again** — the
  notification-based path is the safe pattern.

### Buffer + history persistence (`a7f9868`, `d0bd63b`, `08e85bd`)
- `AppSettings.lastSession` (keyed by stable profile UUID) records open
  channels, queries, and last-selected name per network.
- `ChatLine` + `ChatLine.Kind` are now `Codable`. `NSRange` packs as
  flat `[loc, len]` int pairs.
- `SessionHistoryStore` (new file: `Sources/PurpleIRC/SessionHistoryStore.swift`)
  archives the trailing 200 lines of each open buffer per network as
  `supportDir/history/<networkSlug>.json`, sealed with the keystore DEK.
  Saved on `NSApplication.willTerminateNotification`.
- `IRCConnection.applyPendingRestore` (called from `runPostWelcome`
  after `autoJoinIfNeeded`):
  - Pre-creates query buffers (so the sidebar reflects the previous
    session before the other party messages back).
  - Pre-creates channel buffers AND prepopulates them with restored
    history, then sends JOIN. The handleJoin path reuses the buffer
    when the server confirms; "You joined" appends after the history.
  - Restored lines are bracketed by `── N lines from previous
    session ──` and `── live ──` info markers. Markers are filtered
    out at next save so they don't accumulate across launches.
- Snapshot save is gated on `conn.state == .connected` — the empty
  `[]` initial Combine emission was wiping the saved snapshot before
  restore could read it.
- Encrypted-keystore users use `sessionSnapshotResolver` +
  `sessionHistoryResolver` callbacks: `addConnection` runs before
  unlock, so the eager load comes up empty; the resolvers re-fetch at
  welcome time once `lastSession` is populated.
- "Restore open channels and queries on launch" toggle in Setup →
  Behavior → Session restore. On by default.

### Multi-network UI (`d457cf8`, `567a7e7`)
- Sidebar `Networks` section, always visible, lists every live
  `IRCConnection` with state dot, network name, identity name, hover-
  only disconnect button, right-click menu (Connect / Disconnect /
  Remove). Single-click = make active; the rest of the sidebar
  refreshes to that connection's state.
- `+ Add network` menu lists every saved profile; selecting one spawns
  a fresh `IRCConnection` via `connectAdditionalProfile(_:)` —
  including a second connection to a profile already in use, since
  some workflows (multi-identity, ZNC-attached + direct, etc.) need it.
- `BufferView` header surfaces "<buffer> on <network>" when more than
  one connection is live, so `alice` on Undernet vs `alice` on Dalnet
  read distinctly.

### Sidebar restructure (`16201e0`, `a7f9868`, `34eac06`)
- Channels, then a "Private" section that bundles user queries above a
  divider and server-console rows below (smaller / secondary type so
  the network rows read as "the network itself").
- Saved channels and Contacts (address book) sections persist below.
- Contacts: double-click → `/query`, full right-click menu mirroring
  the query/channel-row menus.

### Touch ID UX fix (`567a7e7`)
- `BiometricGate.isAvailable` keys on `biometryType != .none`. Old
  `canEvaluatePolicy` check returned false on ad-hoc-signed builds even
  when Touch ID was set up.
- `availabilityDetail` translates LAError codes into actionable text
  ("no fingerprints enrolled", "locked out", "passcode not set", etc.)
  shown under the toggle in Setup → Security.

### Smaller polish
- WHOIS/WHOWAS results route to the originating channel/query buffer
  via `whoisOriginByNick` (`1e7382e`).
- Sidebar Leave-channel crash fixed via bounds-check + deferred
  closeBuffer (`0a575f8`).
- Reliable input refocus on app/window activation: false→true bounce
  on `@FocusState` + AppKit notifications because macOS scenePhase is
  iOS-flavoured and unreliable (`09469e1`).
- Watchlist "Manage in Setup" button: dismiss-then-delay-then-open
  pattern because SwiftUI can't show two sheets at once (`516fa48`).
- User list: long nicks no longer wrap; `lineLimit(1)` + tail
  truncation + `help()` tooltip (`19b7275`).
- `/list` channel browser: same single-line treatment on the Channel
  column.
- Bundle bumped to ad-hoc-signed `.app` with full Info.plist
  (`NSAppleScriptEnabled`, `OSAScriptingDefinition`).

## Repo layout (current)

```
PurpleIRC/
├── HANDOFF.md                  This file
├── build-app.sh                Release build + icon + sdef + .app packaging
├── run-tests.sh                Test runner (injects Testing.framework rpath)
├── Package.swift
├── Resources/
│   └── PurpleIRC.sdef          AppleScript dictionary
├── Scripts/
│   └── generate-icon.swift     Runs during build-app.sh
├── Sources/PurpleIRC/
│   ├── App.swift               @main, scenes, CommandMenu
│   ├── AppLog.swift            Diagnostic logger (debug → critical)
│   ├── AppVersion.swift        Bundle-derived version strings
│   ├── AppleScriptCommands.swift  NSScriptCommand subclasses
│   ├── BiometricGate.swift     Touch ID wrapper
│   ├── BotEngine.swift         Native trigger bot + seen tracker integration
│   ├── BotHost.swift           PurpleBot (JavaScriptCore)
│   ├── BufferView.swift        Messages pane + find bar + user list
│   ├── ChannelListService.swift   /LIST cache
│   ├── ChannelListView.swift   /LIST browser sheet
│   ├── ChatModel.swift         @MainActor top-level store + ChatLine + Buffer
│   ├── Commands.swift          Slash-command catalog + matcher
│   ├── ContentView.swift       NavigationSplitView + sidebar + Networks panel
│   ├── Crypto.swift            AES-256-GCM helpers
│   ├── DCC.swift               DCCService / DCCTransfer / DCCChatSession
│   ├── DCCView.swift           Transfers sheet
│   ├── EncryptedJSON.swift     "PIRC\x01" envelope helper
│   ├── HelpView.swift          /help sheet
│   ├── HighlightMatcher.swift  Regex/literal rule engine
│   ├── IRCClient.swift         NWConnection transport
│   ├── IRCConnection.swift     Per-network orchestrator
│   ├── IRCFormatter.swift      mIRC codes → AttributedString
│   ├── IRCMessage.swift        RFC 1459 + IRCv3 tag parser
│   ├── KeyStore.swift          KEK/DEK, passphrase, biometric gate
│   ├── KeychainStore.swift     macOS Keychain wrapper
│   ├── LogStore.swift          Off-main-actor log writer
│   ├── LogViewerView.swift     AppLog viewer sheet
│   ├── ProxyFramer.swift       SOCKS5 / HTTP CONNECT framer
│   ├── SASLNegotiator.swift    CAP + SASL state machine
│   ├── SecuritySheets.swift    Setup-time and unlock sheets
│   ├── SeenListView.swift      Seen-tracker UI
│   ├── SeenStore.swift         Per-network seen DB
│   ├── SessionHistoryStore.swift  Per-network chat archive (new)
│   ├── SettingsStore.swift     AppSettings + JSON/encrypted persistence
│   ├── SetupView.swift         Tabbed preferences
│   ├── SoundsAndThemes.swift   Sound pack + theme presets + timestamps
│   ├── SpellCheck.swift        Spell-check observer + SpellCheckedTextEditor
│   ├── WatchHitBanner.swift
│   ├── WatchMonitorView.swift  Cross-network activity window
│   ├── WatchlistService.swift
│   └── WatchlistView.swift
└── Tests/PurpleIRCTests/
    ├── HighlightMatcherTests.swift
    ├── IRCMessageTests.swift
    ├── KeyStoreTests.swift
    ├── SASLNegotiatorTests.swift
    ├── SeenStoreTests.swift
    └── TriggerRuleTests.swift
```

Support directory (everything optionally encrypted):

```
~/Library/Application Support/PurpleIRC/
├── settings.json               AppSettings + lastSession + identities
├── keystore.json               Wrapped DEK + KDF salt (when encryption is on)
├── app.log                     AppLog records
├── channels/<slug>.json        Per-network /LIST cache
├── history/<slug>.json         Per-network chat history (new)
├── scripts/index.json + *.js   PurpleBot scripts
├── seen/<slug>.json            Seen tracker
├── logs/<network>/<buffer>.log Per-channel logs
└── downloads/                  DCC GET destination
```

## Known gaps (good "pick up here" work)

### DCC — passive mode + RESUME
Active DCC SEND/CHAT works on-LAN. Behind NAT it needs:
1. **Passive (reverse) DCC** — port=0 + token; the receiver listens.
2. **DCC RESUME** — `DCC RESUME filename port offset` →
   `DCC ACCEPT filename port offset`. Critical for big-file retries.
3. **TLS DCC** (TDCC / SDCC) — some networks require it.

All byte-handling is in `DCC.swift`; UI is `DCCView.swift`.

### IRCv3 — what we don't yet do
- `labeled-response` — we request the cap but don't tag outbound
  commands or correlate replies. Would let us drop the
  `whoisOriginByNick` map hack.
- `draft/typing`, `+draft/reply`, `+draft/react` — drafty but a few
  servers (Soju, Ergo) ship them. None of the clients in the gap
  survey support these. Early adoption would actually differentiate.
- `+draft/multiline` — proper multi-line PRIVMSG. We currently split
  client-side via the multi-line paste sheet.

### Inline media + image preview
URLs are detected and clickable, but no inline previews. Textual + The
Lounge expand image URLs — perceived-quality lift, but real complexity
(NSImage caching, sandboxed network access, GIF playback).

### PurpleBot — script storage API
`irc.store.get(key)` / `set(key, v)` backed by per-script JSON under
`supportDir/scripts/<scriptID>.store.json`. Cheap to add; opens up a
bunch of scripts that need state.

### Lua / Python scripting
JS-only today via JavaScriptCore. Embedding wren or lua-c would
double the addressable script ecosystem. Mid-effort.

### Tier 4 items (still deferred)
mIRC scripting-language compat, DLL loading, identd, UPnP. PurpleBot
+ AppleScript supersede the scripting motivation.

## Sharp edges to remember

- **Don't touch window delegates globally.** SwiftUI uses
  `NSHostingWindow.delegate` for sheet dismissal + restoration. Our
  earlier `SpellCheckingWindowDelegate` swap broke launch entirely.
  Use additive patterns (notification observers) instead.
- **Snapshot saves must be state-gated.** Combine's initial `[]`
  emission of `$buffers` fires synchronously on subscribe — before the
  user has connected. Saving unconditionally there wipes the previous
  session's snapshot. Always check `conn.state == .connected`.
- **Encrypted-store load timing.** `addConnection` fires before the
  keystore unlocks decrypted settings. Anything that reads encrypted
  state needs both an eager copy AND a resolver callback that re-fetches
  at welcome time. (See `sessionSnapshotResolver` /
  `sessionHistoryResolver`.)
- **`EncryptedJSON.safeWrite` over plain `wrap` + write.** Refuses to
  overwrite an encrypted file when no key is in hand. This is the only
  thing standing between encrypted-state users and a launch-time
  clobber. Don't bypass.
- **Settings init must not mutate `settings.settings`.** That fires
  `didSet → save()` while the keystore is nil-bound; same clobber as
  above. `selectedServer()` falls back to `.servers.first` on nil.

## Upstream mirror

Repo: <https://github.com/bronty13/PhantomLives> (monorepo). PurpleIRC
lives under `PurpleIRC/`. The working tree at this dev path is the
authoritative source; pushes go straight from here.

## Tip for the next pickup

`memory/purpleirc_tiers.md` in the Claude session store tracks the
tier plan across conversations. The commit log is the other source of
truth — `git log` is concise and has the motivation for each batch in
the commit bodies. The IRC-client gap survey lives in conversation
history (Apr 25); the prioritized punch list is mirrored in the
"Known gaps" section above.
