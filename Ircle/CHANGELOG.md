# Changelog

All notable changes to Ircle are documented here.

## [Unreleased]

### Fixed

- **A data race in the shared `IRCKit` engine that could crash the app at
  random** (IRCKit 0.4.0). `IRCClient` touched its connection state from both
  the main thread (Ircle's synchronous `send`/`disconnect`/cap reads via
  `IrcleSession`) and its private socket queue with no synchronization — a
  use-after-free on the hot send path and concurrent mutation of the receive
  buffer on disconnect, firing during connect/disconnect/reconnect (sporadic,
  timing-dependent crashes). IRCKit now confines all connection state to its
  serial queue; the public API is unchanged, so Ircle needed no source changes.
  Proven race-free with a ThreadSanitizer harness (7 races → 0). See
  `IRCKit/CHANGELOG.md` (0.4.0).

## 0.26.0 — 2026-06-20

### Added

- **Connections window** (**⌘⇧K**, or **Window → Connections**) — every saved
  server in one place with live status (online / connecting / offline / error)
  and **Connect / Disconnect / Edit / Nick** buttons. Double-click a row to
  connect. This is the intuitive **multi-server hub**: connect to several
  networks without opening Settings. Available in every interface style.
- **Floating interface style** (**Settings → Appearance → Interface →
  Floating**) — a faithful recreation of classic Ircle 3.5's separate-windows
  layout: a **Console** window (the active session's server messages), a window
  **per channel/query**, a detached **Userlist** window (with the Classic action
  grid + `t n i p s m l k r` mode row), and a floating **Inputline** window
  ("talking to <buffer>"). They coordinate through the selected buffer — focus a
  channel window and the Userlist + Inputline + Console re-target to it. The
  **Window menu** lists every buffer so you can (re)open a channel window you've
  closed. Built on the existing per-value `WindowGroup` machinery; channels and
  queries get their own windows while server consoles share the primary window.
- **Floating Userlist on demand** — **Window → Userlist** (**⌘⇧U**) pops the nick
  list out into its own window in *any* interface style (Clean/Classic too), like
  the Connections window. In the floating window the roster is a classic
  **Nickname | Hostname** table (WHO-derived hosts), with op/voice nicks coloured,
  above the action grid + mode row.

### Changed

- **⌘K "Connect" is no longer confusing with multiple servers.** With one saved
  server it connects directly; with none or several it opens the Connections
  window so you choose, instead of silently connecting only the first server.
  The Welcome screen's "Connect" button behaves the same way.
- **Disconnect** moved to **⌥⌘K** (was ⌘⇧K, now used by Connections).
- The nick-list action grid, channel-mode row, and full input formatting toolbar
  (previously Classic-only) also appear in the Floating style.

### Fixed

- **Connections window — Nick…** now sets the connection's nickname: it updates
  the saved server profile (persists, shows in the list, used on connect) and
  also sends a live `/NICK` when that server is connected. Previously it only
  attempted a live change and did nothing on a disconnected server, so the nick
  appeared to revert to the default.
- **Connections window — Edit… / Server…** now open Settings reliably (via
  `SettingsLink` instead of the unreliable `showSettingsWindow:` selector);
  **Edit…** jumps to the Servers tab and pre-selects the chosen server.
- Connection rows observe their session directly, so **nick + status update
  live**.

### Tests

- 164 total (+8): the `.floating` style (selectable / Codable / displayName),
  the Connections hub (`canQuickConnect`, `connectDefault` 0/1/many branching,
  session dedup), and the Floating invariant that server buffers never get their
  own window.

## 0.25.0 — 2026-06-19

### Added

- **Modern mode** (**Settings → Appearance**, **default OFF**) — an opt-in
  umbrella for modern quality-of-life features that leaves the classic retro
  look completely untouched until you enable it. Its first feature is full UI
  customisation, surfaced in a new **Themes** tab:
  - **20 hand-tuned built-in themes** spanning darks (Midnight, Dracula, Nord,
    Tokyo Night, Graphite Pro, Solarized Dark, Gruvbox Dark, Twilight, Carbon),
    lights (Paper, Solarized Light, Sepia, Lavender, Snow, Mint, High Contrast)
    and recoloured-bevel retro-modern looks (Platinum Plus, Aqua, Slate, Noir).
    Each theme is **flat** or **beveled** — Ircle's signature 3D chrome,
    recoloured, is a per-theme choice.
  - **Rich per-element fonts** — family, size, weight, italic, ligatures and
    tracking, set independently for the **message body**, **nicknames**,
    **timestamps**, **system lines** and **interface chrome**. Empty fields
    inherit (root slots fall back to Monaco / the system UI font).
  - **Custom-theme library** — duplicate, create, rename, edit and delete your
    own themes in a WYSIWYG editor with a live mock-chat preview, and **export /
    import `.ircletheme`** files to share a look with other Ircle users.
  - Implemented through the existing `settingsStore.palette` seam: a Modern
    theme materialises a full `PlatinumPalette`, so every view re-skins with no
    per-view changes. New types: `ModernTheme` (+ 20 built-ins),
    `FontStyle`/`FontSlot`/`ResolvedFont`, `ThemeBuilderView`, `ThemeImporter`,
    `ModernSettingsView`. The flat-vs-beveled switch lives in one place
    (`PlatinumBevel`). 21 new tests (modern themes, fonts, settings round-trip +
    legacy-decode + export/import).

### Unchanged

- With Modern mode **off** (the default, and for every existing
  `settings.json`), Ircle renders byte-identical to before — Platinum/Graphite,
  Monaco/Geneva, and the classic two-tone 3D bevels.

## 0.24.0 — 2026-06-19

### Added

- **In-app manual** (**Help → Ircle Manual**, ⌘?). A comprehensive, themed
  document: a getting-started walkthrough, per-feature how-tos (servers, nick
  list, DCC, sounds, logging, ignore, aliases, …), a **full slash-command
  reference**, **keyboard shortcuts**, a **settings reference**, **where Ircle
  stores files**, a **troubleshooting/FAQ**, plus the **history of the original
  Ircle** (Olaf Titz's 1993 GPL Pascal → Onno Tijdgat's 3.x → the final 3.5a6)
  and the **research findings** about the original's menus/windows/prefs/DCC/
  scripting (with provenance), and how this app differs. Rendered by a small,
  dependency-free in-house Markdown reader (`MarkdownParser` + `ManualView`,
  themed to match the app); ships as `Resources/Manual.md`. 9 parser tests.

## 0.23.0 — 2026-06-19

### Added

- **Per-event sounds.** Optionally play a clip when you're **mentioned**, get a
  **private message**, or someone **joins**/**parts**. Settings → Appearance →
  Sounds: enable "per-event sounds" and name a clip per event (from
  `~/Downloads/Ircle/Sounds/`). Off by default; mention takes precedence over a
  plain PM. (`SoundService` no longer carries its own enable flag — CTCP sound
  and per-event sound are gated independently by their settings.) 2 tests.

## 0.22.0 — 2026-06-19

### Added

- **Nick-list hostnames + IRCop markers.** On joining a channel Ircle now sends
  a `WHO` and parses the replies (numeric 352), so hovering a nick shows its
  `user@host`, and in Classic style network operators get a ✪ marker. (The
  original's wide Userlist had IrcOp/Hostname columns; our narrow list surfaces
  the same data as a tooltip + marker.) 2 tests.

## 0.21.0 — 2026-06-19

### Added

- **Custom message colours.** Settings → Appearance → Custom colours lets you
  override the **message text** and **background** on top of the chosen theme
  (with a "Reset to theme defaults"). A custom background also recomputes the
  contrast luminance so mIRC colours stay legible. Persisted as hex; applied
  app-wide via a shared `settingsStore.palette`. 4 tests.

## 0.20.0 — 2026-06-19

### Added

- **Command aliases.** Define your own slash commands: **`/alias <name>
  <expansion>`** (e.g. `/alias j /join`), `/alias del <name>`, `/alias` to list,
  `/unalias <name>`. Templates support `$1`…`$9` (positional), `$2-`/`$*` (rest);
  with no `$`, args are appended. Typing `/<name> …` expands and re-runs (so an
  alias can map to a command or text), with a recursion guard. Persisted; 6
  tests (expander + management + persistence + an end-to-end alias→command echo).

## 0.19.0 — 2026-06-19

### Added

- **CTCP sound.** Receiving a `CTCP SOUND` plays the named clip from
  `~/Downloads/Ircle/Sounds/` and shows the accompanying text like an action;
  send one with **`/sound <file> [text]`**. The sound name is sanitized (via
  IRCKit's `DCC.sanitizeFilename`) and resolved only within the Sounds folder, so
  a peer can't make Ircle play or probe an arbitrary path. Toggle "Play CTCP
  sound clips" in Settings → Messages (on by default). 4 tests.
  *(CTCP FACE exchange — the classic 32×32-PICT-over-DCC mechanism — is
  intentionally not implemented; our Faces are modern local avatars. It would be
  a separate, modernized feature if wanted.)*

## 0.18.0 — 2026-06-19

### Added

- **Ignore list.** Drop messages (and CTCP/DCC) from unwanted users:
  **`/ignore add|del|list <mask>`** (and `/unignore <mask>`), or **right-click a
  nick → Ignore**. Masks are IRC hostmasks with `*`/`?` wildcards, matched
  case-insensitively by IRCKit's new `IRCMask`; a bare nick expands to
  `<nick>!*@*` (so `/ignore bob` silences bob from anywhere, `*!*@spam.host`
  silences a whole host). The list is global and persisted. 5 tests (Ircle) +
  6 (IRCKit mask matcher).

## 0.17.1 — 2026-06-19

### Fixed

- **DCC to yourself is now refused with a clear message** instead of silently
  binding a listener that no one connects to. This is the trap when two copies
  of Ircle share the default nick `ircle-user` on one network: the server
  renames the second client, so a DCC offer aimed at `ircle-user` targets *your
  own* machine. Ircle now says "You can't DCC yourself — '<nick>' is your own
  nick on this server." (Give each machine a distinct nick in Settings.) 1 test.

## 0.17.0 — 2026-06-19

### Added

- **DCC — Stage 4b: send a file (DCC SEND).** You can now offer a file:
  **right-click a nick → Send File…**, or **`/dcc send <nick>`** (both open a file
  picker). Ircle binds a listener on your real interface, advertises the file via
  a CTCP DCC SEND offer, and streams it with a progress bar once the peer
  connects (draining their acks; warns on a wildcard bind). Runs on IRCKit's new
  `DCCUpload`. **This completes DCC** — accept + initiate, for both files and
  chat. The transfer window shows outgoing items ("to <nick>") alongside
  incoming. 2 engine tests for the offer encoder; the byte transfer itself is
  the two-client smoke test.

## 0.16.0 — 2026-06-19

### Added

- **DCC — Stage 4a: initiate a DCC chat.** You can now *start* a DCC chat:
  **right-click a nick → Start DCC Chat**, or **`/dcc chat <nick>`**. Ircle binds
  a listener (to your real interface, advertising your routable IPv4 via
  `getifaddrs`; warns loudly if it can only bind the wildcard), sends the CTCP
  offer, and opens the chat window when the peer connects. Lifts PurpleIRC's
  hardened port-range/bind logic. `/dcc` is now a recognized command (no more
  "Unknown command" from the server). **DCC SEND from Ircle** (offering a file)
  is the remaining piece — coming next. 2 engine tests for the offer encoders;
  the listen/connect path is covered by the two-client smoke test.

## 0.15.0 — 2026-06-19

### Added

- **DCC — Stage 3: chat.** Incoming `DCC CHAT` offers now appear in the DCC
  Transfers window (⌘⇧D) alongside file offers; **Accept** connects out and
  opens a dedicated DCC chat window (one per conversation) with a live message
  view and an input line; **Decline**/**Close** as well. Runs on IRCKit's new
  `DCCChat` transport (connect-out only, to a vetted address; newline-framed
  line exchange). Initiating a DCC chat/send (listening + advertising your IP)
  is still to come. 2 tests added; the socket exchange is covered by the
  two-client smoke test.

## 0.14.0 — 2026-06-19

### Added

- **DCC — Stage 2: accept & receive files.** A **DCC Transfers** window (⌘⇧D, or
  the Window menu) lists inbound file offers; **Accept** downloads to
  `~/Downloads/Ircle/DCC/` with a live progress bar, **Decline**/**Cancel**, and
  **Reveal** when done. Saves never clobber (auto `name (1).ext`) and the
  filename is re-sanitized so a transfer can't escape the folder. Downloads run
  on IRCKit's new `DCCDownload` (connect-out only, to an address the SSRF guard
  already vetted; sends the classic 4-byte acks; stops at the advertised size so
  a peer can't over-write). **Never auto-accepts.** 6 tests for the save-path /
  offer logic; the socket transfer itself is verified by a two-client smoke test.
  DCC **chat** and **initiating** transfers are still to come.

## 0.13.0 — 2026-06-19

### Added

- **DCC — Stage 1: safe offer detection.** Incoming `DCC SEND` / `DCC CHAT`
  offers are now parsed and surfaced in the server console (filename, size,
  peer address) instead of falling into a generic CTCP dump — backed by IRCKit's
  new audited `DCC` engine, which validates the peer address (SSRF guard;
  hostnames/loopback/link-local refused) and sanitizes the filename
  (path-traversal guard). Unsafe offers are explicitly ignored with a notice.
  **Accepting/transferring is not wired yet** ("coming soon") — that's Stage 2
  (sockets + a transfer manager + a two-client smoke test). 3 tests.

## 0.12.0 — 2026-06-19

### Added

- **Chat logging + a log viewer.** Optionally save channel/query transcripts to
  `~/Downloads/Ircle/Logs/<network>/<channel>.log` (off by default; toggle in
  Settings → Logging). A new **Chat Logs** window (⌘⇧L, or the Window menu /
  Settings) browses saved logs — conversations in a sidebar, the transcript on
  the right (tails the last 256 KB), with Refresh + Reveal-in-Finder. Filenames
  are sanitized so a channel/network name can't escape the logs folder. 6 tests.

## 0.11.0 — 2026-06-19

### Added

- **Clickable links.** URLs in messages are now detected and rendered as
  tappable, underlined links (open in your browser). Applies in both styles.
- **macOS notifications** for mentions and private messages that arrive while
  you're not looking (different buffer, or app in the background). On by default;
  toggle in Settings → Messages ("Notify me of mentions & private messages").
  Requests permission once on first launch; coalesces per conversation.
- **`/away [message]`** marks you away (bare `/away` clears it); the server's
  305/306 replies update a tracked away state and print confirmation.

## 0.10.0 — 2026-06-19

### Added

- **Notify / friends list** — the last major piece of the Classic interface.
  The Classic nick list now has **Users / Notify tabs**; the Notify tab shows
  your friends with a live green/grey online dot, lets you add a nick (field +
  `＋`) and remove one (right-click), and clicking a friend opens a query.
  Presence is tracked by **ISON polling** (universal across networks — every
  ~45s and immediately on connect; numeric **303 RPL_ISON** parsed into
  per-connection presence). The list is **global**, persisted in `settings.json`
  (`notifyNicks`), synced to every connection. Also a **`/notify add|del|list`**
  command (works in any style). 8 tests added (ISON build, 303 parse,
  case-insensitive add/remove dedup, persistence, new-session inheritance).

## 0.9.2 — 2026-06-19

### Added

- **Classic Inputline formatting toolbar.** In Classic style the input bar adds,
  next to the existing Bold/Italic/Underline buttons, a **strikethrough (S)**, a
  **plain/reset (P)** button, and a **16-colour mIRC colour menu** (inserts
  `^C NN`, plus an "End colour" that inserts a bare `^C`). Clean style keeps the
  minimal B/I/U set. The inserted codes render through the existing mIRC
  formatter (already covered by `MircRendererTests`), so no new parsing — this is
  a view-only addition.

## 0.9.1 — 2026-06-19

### Added

- **Classic mode-toggle row** (`t n i p s m l k r`) on the channel nick list —
  the next piece of the Classic interface style. Each cell lights when that
  channel flag is active and clicking toggles it (`+t`/`-t`, …); `l`/`k`, which
  need a value, can be cleared here but not set. Backed by new channel-mode
  state on `IrcleBuffer`: modes are parsed from inbound `MODE` changes and
  requested on join via `MODE #chan` (numeric **324 RPL_CHANNELMODEIS**), with
  parameters and untracked user/list modes (o/v/b/…) ignored. Only shown in
  Classic style, channels only. 5 tests added.

## 0.9.0 — 2026-06-19

### Added

- **Interface Style setting: Clean vs Classic.** Settings → Interface now lets
  you choose between the minimal modern layout (**Clean**, the default — your
  current look is preserved) and **Classic**, which surfaces the dense
  original-Ircle "power IRC" chrome. In Classic, the nick list shows the full
  3×3 action grid — **Op · Kick · Msg / DeOp · Ban · Cping / Whois · BanKick ·
  Query** — instead of the compact Query/Whois/Op/DeOp bar. The choice persists
  in `settings.json` and defaults to Clean for existing installs. 4 tests added.
  (Groundwork toward fuller Classic chrome — channel-mode toggle row, Notify
  tab, Inputline formatting toolbar — tracked in `docs/original-ircle-parity.md`.)

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
