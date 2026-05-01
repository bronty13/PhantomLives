# Changelog

All notable changes to PurpleIRC are recorded here. The bundle's
`CFBundleShortVersionString` is derived automatically from the git commit
count (`1.0.<count>`); CHANGELOG entries use the same scheme so the
version on the About panel matches the entry that introduced it.

## [1.0.95] — 2026-05-01

### Changed (Phase 3 — Setup reorganization)

- **Setup sidebar regrouped into 6 sections × 20 tabs** (was 3 × 11),
  mirroring the macOS System Settings layout so adding more in later
  phases doesn't crowd anything:
  - **Connections** — Servers, Identities, Proxy & DCC *(new)*
  - **People & places** — Address Book, Channels, Ignore, Highlights
  - **Behavior** — Behavior, Notifications *(new)*, Logging *(new)*
  - **Personalization** — Appearance, Themes *(new)*, Fonts *(new)*,
    Sounds *(new)*
  - **Power-user** — Bot, PurpleBot, Assistant *(new)*,
    Shortcuts & Aliases *(new)*, Backup *(new)*
  - **Security** — Security
- **Behavior** trimmed to its functional core (Quit, Session restore,
  CTCP, Away) with a "where to find moved settings" pointer block.
- **Appearance** trimmed to meta-knobs (Timestamp, Density picker,
  Bold / Relaxed / Collapse toggles); a new Density picker is wired
  to `settings.chatDensity` and matches the View → Density submenu
  added in 1.0.94.
- **Notifications** consolidates every alert channel (sound / dock /
  banner) for watchlist hits and own-nick mentions into one tab,
  rather than scattering them across Behavior + Appearance + Highlights.
- **Logging** lifts persistent-log toggles, retention, and the legacy
  plaintext conversion path out of Behavior so a user worried about
  disk usage or compliance has one tab to audit.
- **Themes / Fonts / Sounds** promoted from sections to their own tabs
  so they have room to grow into the Theme Builder (Phase 4) and
  custom font picker (Phase 5).
- **Shortcuts & Aliases** is the home for `userAliases` (list / add /
  remove); ships with built-in keyboard-shortcut documentation, with
  user-customizable shortcuts deferred.
- **Backup** surfaces `BackupSettingsRow` + `FactoryResetRow` plus a
  pointer to the `/nuke` destructive reset.

## [1.0.94] — 2026-05-01

### Added (Phase 2 — Full macOS menu system)

- **8 native menus** replace the single "IRC" menu, each backed by a
  small private View struct so `App.body`'s `.commands` block stays
  scannable.
  - **File** — New Network… (⌘N), Close Buffer (⌘W), Export Current
    Buffer…, Export All Buffers…
  - **PurpleIRC** (after Settings…) — Lock Keystore (⇧⌘L), Reset
    Everything (NUKE)…
  - **Edit** (after Pasteboard) — Find in Buffer… (⌘F)
  - **View** — Show Raw Log toggle, Increase / Decrease / Reset Font
    Size (⌘= / ⌘- / ⌘0), Density submenu (Compact / Cozy /
    Comfortable), Theme submenu (every `Theme.all` entry, with a
    checkmark on the current selection)
  - **Buffer** — Next / Previous Buffer (⌘⌥→/←), Next / Previous
    Network (⌘⌥↓/↑), Mark All as Read (⌃⌘M), Clear Buffer
  - **Network** — Connect (⌘K), Disconnect (⇧⌘D), Reconnect (⇧⌘R),
    Channel List… (⇧⌘L), Watchlist… (⇧⌘A — moved from ⇧⌘W since
    that's the system "Close Window"), Watch Monitor… (⇧⌘M),
    DCC Transfers… (⇧⌘T), Seen Log…
  - **Conversation** — Join Channel… (⇧⌘J), Open Query… (⇧⌘Q),
    Set Topic…, Invite User…, WHOIS…, WHOWAS…
  - **Help** (after system Help) — Slash Command Reference… (⇧⌘?),
    App Diagnostic Log…, Chat Logs…
- **Menu state derives from live model state** (active connection
  presence, connection state, current buffer kind) so menu items
  reflect what's possible without manual refreshes.
- **Theme + Density submenus generate from `Theme.all` /
  `ChatDensity.allCases`**, so adding a theme picks up automatically.
- **Generic `InputPromptSheet`** backed by `ChatModel.inputPrompt`
  for menu-driven dialogs (Set Topic, Join Channel, Open Query,
  Invite, WHOIS, WHOWAS) — one sheet, many uses, instead of a forest
  of one-off modals.

### Added (model surface for menus)

- `ChatModel.reconnect()` → `IRCConnection.handleReconnectFromMenu()`
- `ChatModel.cycleNetwork(forward:)`
- `ChatModel.clearCurrentBuffer()`, `markAllReadEverywhere()`,
  `cycleBuffer(forward:)`
- `ChatModel.incrementFontSize()` / `decrementFontSize()` / `resetFontSize()`
- `ChatModel.setTheme(byID:)` / `setDensity(_:)`
- `ChatModel.requestInput(...)` wrapper around the new
  `InputPrompt` struct.

## [1.0.93] — 2026-05-01

### Added (Phase 1 — Slash command surface + `/nuke`)

- **`/nuke`** — two-step destructive reset. Routes through
  `NukeService` which disconnects every network, locks the keystore,
  wipes `settings.json` + `keystore.json` + every encrypted subtree
  (`channels/`, `history/`, `scripts/`, `seen/`, `logs/`, `downloads/`,
  `backups/`, `blobs/`, `photos/`, `app.log`), clears every Keychain
  item under `com.purpleirc`, then quits. Sanity rail refuses to run
  if `supportDirectoryURL` doesn't look like an Application Support /
  `.config` path. The confirmation sheet (`NukeConfirmationSheet`)
  enumerates exactly what will be wiped and disables the destructive
  button until the user types the literal phrase **NUKE**.
- **21 new model-level slash commands**: `/clear` (`/cls`), `/find`
  (`/search`), `/markread` (`/markallread`), `/next` (`/nextbuffer`),
  `/prev` (`/previous`, `/prevbuffer`), `/goto` (`/switch`),
  `/network`, `/theme`, `/font`, `/density`, `/zoom`, `/timestamp`
  (`/ts`), `/lock`, `/backup`, `/export`, `/alias`, `/repeat`,
  `/timer`, `/summary`, `/translate`.
- **11 new connection-level slash commands**: `/reconnect`, `/rejoin`
  (`/cycle`), `/invite`, `/knock`, `/motd`, `/lusers`, `/admin`,
  `/info`, `/version`, `/silence`, `/unsilence`.
- **User-defined aliases** (`AppSettings.userAliases`). Resolved
  *before* built-in commands so the user can shadow built-ins on
  purpose. Editable inline via `/alias <name> <expansion>` and
  `/alias -<name>`, or in the new Setup → Shortcuts & Aliases tab.
- **`ChatDensity` enum** (`.compact` / `.cozy` / `.comfortable`)
  with a `.cozy` default, plus an integrated row-padding
  multiplier consumed at draw time.
- **`AppSettings.viewZoom`** — 0.5–2.0 multiplier on top of the
  configured chat font size, switchable live with `/zoom`.

### Changed

- **`CommandCatalog` synced**. Every working command (the new ones
  plus the existing-but-hidden `/watch`, `/unwatch`, `/dcc`, `/log`,
  `/logs`, `/assist`, `/reloadbots`, etc.) is now an entry, so they
  show in `/`-autocomplete and the `/help` sheet. Categories grew
  from 8 to 15 (Connection, Channels, Messages, Identity, Moderation,
  User lookup, Server info, DCC, Window & buffer, Appearance, Logs,
  Bot, Automation, Dangerous, App) so the list stays scannable.
- **`BufferView` body extracted into a `BufferViewObservers` modifier**
  to keep Swift's "expression too complex" type-checker happy after
  `/find` and `/clear` bridges joined the existing focus-restore
  observers. Behaviourally identical.
- **`IRCConnection` gained four buffer helpers**: `clearBufferLines(id:)`,
  `markAllBuffersRead()`, `cycleBuffer(forward:)`, and
  `selectBufferByName(_:)` (exact > prefix > contains match).

## [1.0.92] — 2026-04-30

### Security

- **CRLF injection blocked at every outbound seam.** `IRCSanitize.field`
  scrubs CR / LF / NUL from script-supplied and AppleScript-supplied
  fields (`target`, `text`, `chan`, `reason`, `body`) before they reach
  the IRC line assembler, and `IRCSanitize.line` re-scrubs the assembled
  line at `IRCClient.send` as defence in depth. Without this, an
  AppleScript like `send message "hi\r\nQUIT :pwn" to "#x"` (or a
  PurpleBot `irc.msg(target, text)` with embedded newlines) could
  smuggle a second IRC command after the message body. Affected sites:
  `AppleScriptCommands.swift` (Send / Join / Part / Say), `BotHost.swift`
  (`irc.send`, `irc.sendActive`, `irc.msg`, `irc.notice`), and
  `IRCClient.send` / `IRCClient.sendSync`.
- **Credentials masked in raw log + AppLog.** `IRCSanitize.maskForDisplay`
  rewrites `PASS <pw>`, `AUTHENTICATE <b64>` (control markers `+` / `*`
  preserved), and `PRIVMSG NickServ :IDENTIFY [acct] <pw>` to `****` in
  both the outbound raw-log path and the inbound echo path (echo-message
  cap can replay our own IDENTIFY back to us). Wire bytes are unchanged.
- **DCC listener bound to the advertised IP.** The active-DCC listener
  (`DCC.swift`) used to bind `0.0.0.0`, letting any host that could
  route to the listening port race the legitimate peer to grab the
  file/chat. The listener now binds to the same IP we advertise in the
  `DCC SEND` / `DCC CHAT` offer, with a wildcard fallback only when the
  bind fails (LAN-only setups whose advertised address can't be bound).
- **DCC filename hardening.** `sanitizeFilename` now strips control
  bytes (≤0x1F + 0x7F) and `\` / `/` / `:`, collapses `..` segments,
  takes only the last path component, drops leading dots (hidden files),
  caps at 255 chars, and rejects collapse-to-empty / dot-only names
  with a `dcc-file` fallback.
- **POSIX `0600` perms on every encrypted-at-rest file.**
  `EncryptedJSON.safeWrite` and `KeyStore.persist` set owner-only file
  modes after the atomic write. The contents are already AES-GCM
  sealed when a DEK is in hand, but tightening the file mode protects
  unencrypted-mode users (whose JSON would otherwise inherit the
  user's umask, typically `0644`).
- **Full SHA-256 for the keystore Keychain account.** Previously
  truncated to a 6-byte (48-bit) prefix, which made colliding-path
  attacks plausible (~2²⁴ expected attempts). The Keychain account
  name is no longer length-constrained, so there's no reason to
  truncate.
- **PurpleBot script integrity hash.** `BotScript` now carries a
  `contentHash` (SHA-256 hex) captured at write time and verified
  before the source is handed to JavaScriptCore. Disk-tampered or
  partially-decrypted scripts surface as a script-log error instead of
  silently executing.
- **HTTP CONNECT proxy parser tightened.** Now requires a literal
  `HTTP/1.x` version line, a strict `200` status, refuses any
  `Content-Length: N` (`N > 0`) — which would smuggle bytes the tunnel
  would otherwise mistake for application data — and caps response
  headers at 16 KiB so a hostile proxy can't grow the accumulator
  forever.
- **SASL PLAIN AUTHENTICATE chunked at 400 bytes** (`SASLNegotiator
  .chunkedAuthenticate`). Long credentials would previously produce a
  single `AUTHENTICATE <b64>` line over the 512-byte IRC limit and
  silently fail SASL. Multi-chunk payloads end with `AUTHENTICATE +`
  per spec.
- **`IRCMessage.parse` rejects lines containing NUL.** Server-supplied
  nick / channel / target fields can no longer carry forbidden bytes
  into buffer keys or file slugs.

### Fixed

- **Reconnect Task lifecycle race.** The delayed reconnect now captures
  the connection's UUID and re-checks `Task.isCancelled`,
  `userInitiatedDisconnect`, and the connection state inside
  `MainActor.run`. Without this, a disconnect issued during the backoff
  sleep (or a manual reconnect that already started a new attempt)
  could trigger a phantom reconnect on top.
- **433 nick collision now bounded.** Capped at 4 retries with state
  reset on `001` welcome and on each fresh `connect()`. The previous
  loop appended `_` forever, eventually tripping `NICKLEN` and
  cascading 432/433 with no path to registration.
- **Watchlist alert dedupe window.** Per-nick `lastAlertAt` timestamp
  suppresses duplicate banners when MONITOR / ISON / observed-activity
  fire for the same sighting in the same instant. 3-second window;
  manual test alerts skip the gate.
- **`lastAwayReplyAt` no longer grows without bound.** Long-running
  connections in busy networks would otherwise accumulate one entry
  per unique sender forever. Entries older than the throttle window
  are pruned when the dict exceeds 1024 keys.
- **Restore-buffer selection is deterministic.** Replaces the
  fire-and-forget 800 ms Task that left a blank pane on screen when
  JOIN took longer than expected. The desired buffer name is captured
  in `pendingRestoreSelectName` and `indexOfOrCreateBuffer` resolves it
  the moment a matching buffer materializes.
- **`closeBuffer` selects the next buffer before mutating the array.**
  Eliminates the one-frame placeholder render that used to flash when
  closing the active buffer.
- **`SessionHistoryStore.load` trims each buffer to `linesPerBuffer`
  immediately after decode.** Defensive against a tampered or bloated
  history file blowing up memory at restore time.
- **BATCH bracket safety.** `openBatches` is capped at 256 entries
  (warns + evicts oldest beyond that), duplicate `+id` overwrites log
  a warning, and the dict (plus `chatHistoryFetched`) clears on
  disconnect / failed so reconnects don't see ghosts.
- **IRCv3 dangling backslash preserved.** A tag value ending in `\`
  is malformed per spec; preserving the backslash makes a buggy
  server's behaviour visible instead of silently truncating the
  value.

### Changed

- **Buffer scrollback (`5000` lines) emits a one-shot info notice on
  first overflow.** No longer silent; the user sees `— Scrollback
  exceeded 5000 lines; older history is being trimmed —` once per
  buffer per session.
- **Message-box focus is restored on every modal-sheet dismissal.**
  Sheet dismissal doesn't fire `NSWindow.didBecomeKey` (the same
  window stays key), so the existing app-activate / window-activate
  refocus path missed it. Added `.onChange(of:)` handlers for
  `model.showSetup` / `showHelp` / `showWatchlist` / `showDCC` /
  `showChannelList` / `showSeenList` / `showRawLog` / `showAppLog` /
  `showChatLogs` and the local multi-line editor sheet, plus a
  `refocusInput()` call when the Find bar closes. App-activate,
  window-activate, buffer-switch, and scene-phase paths were already
  wired correctly.

### Verified — no change required

These items were flagged in the security/correctness review but turned
out to be already correct on inspection; recorded here so future
reviews don't re-litigate them.

- TLS validation: `NWParameters(tls: .init())` enables certificate
  and hostname validation by default on Apple platforms; no
  override is in effect.
- Per-connection Combine subscribers: the `IRCConnection` instance
  persists across disconnect/reconnect, and its subscribers are
  intentionally long-lived. `removeConnection` releases everything
  together.
- Highlight + trigger regex validation: `HighlightRuleEditor` and
  `TriggerRuleEditor` already display compile errors inline as
  orange caption text under the field.
- Proxy credentials: `proxyPassword` already routes through the
  `persistCredentials` Keychain-backed pipeline.
- SOCKS5 user/pass length: `sendSOCKS5UserPass` and
  `sendSOCKS5Connect` already enforce the 255-byte field limit and
  `fail()` gracefully on overflow.

### Tests

164 tests across 12 suites all pass (`swift test` / `./run-tests.sh`).
The build (`./build-app.sh`) produces `PurpleIRC.app` bundled with the
git-derived version stamps in Info.plist.
