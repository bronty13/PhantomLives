# Changelog

All notable changes to PurpleIRC are recorded here. The bundle's
`CFBundleShortVersionString` is derived automatically from the git commit
count (`1.0.<count>`).

> **Versioning note (2026-05-24):** PurpleIRC lives in the polyglot
> `PhantomLives` monorepo, so `<count>` is the *whole repo's* commit
> count — commits to sibling projects (SideMolly, PurpleReel, …) bump
> PurpleIRC's reported version too. The About-panel number therefore
> runs **ahead** of the latest CHANGELOG heading and no longer maps
> 1:1 to the entry that introduced a change. Read the **dates**, not
> the patch numbers, as the source of truth for "what shipped when."

## [Unreleased] — 2026-06-03

### Fixed

- **Switching buffers no longer jumps to the top of the scrollback**
  (`BufferView.swift`). When you click from one channel/query to
  another, the messages pane now scrolls to the latest message as
  expected. The `bufferIndex` `onChange` (added in the 1.0.234 perf
  sweep, when `renderedRows` became cached) refreshed the row list but
  never re-anchored the scroll, so the `ScrollViewReader` kept the prior
  buffer's offset and opened the new buffer scrolled to the top.
  Previously a scroll-to-bottom only happened by coincidence — as a side
  effect of `buffer.lines.count` differing between the two buffers — so
  same-length buffers landed at the top. The switch now explicitly
  scrolls to the `"bottom"` anchor (deferred one runloop so the new rows
  are laid out first; no animation, since an animated jump on switch
  reads as jank). Skipped while the Find bar is open, matching the
  new-message path.
- **Follow-up: returning to a conversation no longer lands part-way up
  the scrollback** (`BufferView.swift`). The prior fix scrolled to
  `"bottom"` after a single `DispatchQueue.main.async` hop, but because
  `BufferView` (and its `ScrollView`) is *reused* across buffer switches
  — `ContentView` builds `BufferView(bufferIndex:)` with no `.id()`, so
  switching only mutates `bufferIndex` — the `LazyVStack` hadn't realized
  the rows below the fold one runloop later, so the scroll landed short
  and the buffer opened "scrolled up to an earlier point in time." Now:
  (1) the `ScrollView` carries `.defaultScrollAnchor(.bottom)` so it
  natively rests at, and re-anchors to, the newest line when the content
  size changes; and (2) a `jumpToBottom(_:)` helper re-asserts the
  `scrollTo("bottom")` across the next couple of runloops (immediate +
  `async` + `+0.06 s`) so the final resting position is the true bottom
  once the off-screen rows realize. Used by both the buffer-switch
  `onChange` and `onAppear`.

## [1.0.603] — 2026-06-02

### Security (audit follow-up — #36, KDF hardening)

Strengthens the passphrase key-derivation that protects the on-disk
keystore. No user data is re-encrypted, and your passphrase is unchanged.

- **PBKDF2 is now calibrated, not a fixed 300k** (`Crypto.swift`). At
  setup/passphrase-change the iteration count is timed to ~300 ms on this
  Mac and clamped up to an OWASP-2023 floor of 600,000 — so a copied
  keystore is markedly more expensive to brute-force, while interactive
  unlock stays snappy.
- **Versioned envelope + lazy upgrade** (`KeyStore.swift`). The keystore
  file is now v2 and records its KDF algorithm. On a passphrase unlock,
  an envelope wrapped at a materially weaker count (an old 300k file, or
  one made on slower hardware) is transparently re-wrapped at the
  stronger count — the same DEK, re-derived KEK, fresh salt; never
  downgraded, never re-encrypting your messages. A pre-v2 file decodes
  and upgrades seamlessly.

A memory-hard KDF (Argon2id) would close the finding fully but requires a
libsodium dependency; it's deliberately deferred, and the versioned
envelope makes adding it later a clean drop-in. Tracked in `AUDIT.md`.

### Tests

- +3 (380 → 383): calibration respects the floor; the upgrade decision
  never downgrades and ignores sub-1.5× timing noise; setup writes a v2
  envelope at/above the floor with the algorithm recorded.

## [1.0.602] — 2026-06-02

### Fixed (audit follow-ups — batch 13, last safe LOW nits)

- **Address-book matcher stops false-positiving on short nicks**
  (`ContactMatchesView.swift`). The fuzzy (substring) match had no
  minimum needle length, so a 1–2 char nick ("al") matched every contact
  that merely contained those letters. Fuzzy matching now requires a
  needle of at least 3 characters; exact (case-insensitive) matches still
  count at any length.
- **Address-book list skips needless work per render**
  (`AddressBookContactList.swift`). The visible-entries computation ran a
  cross-network sighting fold for every contact on every render even
  though the result is only used by the recency filter. It's now computed
  only when the recency filter is active (it's `.any` by default).

### Tests

- +4 (376 → 380): `Contact matcher` suite — exact match at any length,
  short needle no longer fuzzy-matches, long needle still does (both
  directions), empty needle never matches.

## [1.0.601] — 2026-06-02

### Security & correctness (audit follow-ups — batch 12, persistence + masking)

Closes the safe persistence/security LOW findings and two test-gaps.

- **Credential masking survives a tags/prefix lead** (`IRCMessage.swift`).
  `maskForDisplay` anchored `PASS`/`AUTHENTICATE` at column 0, so a
  credential line carrying an IRCv3 tags segment or a source prefix would
  slip through unmasked in logs. It now strips an optional `@tags`/`:prefix`
  lead before matching — without masking the words inside a chat body.
- **Decrypted blob exports aren't left at a guessable world-readable path**
  (`BlobStore.swift`). `writeToTempFile` now writes into a random per-export
  subdir with `0600` perms and sweeps exports older than an hour.
- **A nested backup dir isn't recursively archived** (`BackupService.swift`).
  If the backup directory lives inside the support dir (non-default), the
  zip now excludes it so backups don't grow into each other.
- **Sound defaults have one source of truth** (`SettingsStore.swift`). The
  `init(from:)` fallback for `eventSounds` diverged from the stored-property
  default (it omitted `highlight`); both now use `defaultEventSounds`.

### Tests

- +7 (369 → 376): new `EncryptedJSON` suite (plaintext passthrough,
  encrypted round-trip, unwrap-without-key throws, safeWrite
  refuse-to-clobber, 0600 perms); `maskForDisplay` tag/prefix masking +
  chat-body non-masking; `eventSounds` default parity on minimal decode.

## [1.0.600] — 2026-06-02

### Fixed (audit follow-ups — batch 11, the remaining MEDIUM findings)

Closes the five MEDIUM findings that were still open. With this, every
HIGH and MEDIUM finding from the audit is resolved.

- **A recursive alias can't crash the app** (`ChatModel.swift`).
  `/alias foo /foo` (or a mutual pair) expanded forever and overflowed
  the stack — and since aliases persist, it crashed on the next launch
  too. Alias expansion now stops after a depth limit with a clear notice.
- **Find-bar cursor holds its place in a busy channel** (`BufferView.swift`).
  Every incoming line snapped the match cursor back to 1/N, making ⌘G
  cycling unusable; recompute now preserves the focused match by id.
- **Channel messages honour the chat-font setting** (`BufferView.swift`).
  PRIVMSG/ACTION bodies were hardcoded to the system body font, so Cmd-+/-
  and the Appearance font size didn't affect the text you actually read.
  They now use the configured `chatFont`, matching nicks and notices.
- **Avatar drag-drop no longer draws off the main thread**
  (`ContactDetailView.swift`, `PhotoUtilities.swift`). Downscaling used
  `NSImage.lockFocus` (AppKit drawing) on the background queue an
  `NSItemProvider` completion fires on — undefined behaviour. The drop
  handlers now hop to the main actor before downscaling.
- **Theme opacity is preserved** (`SoundsAndThemes.swift`,
  `ThemeBuilderView.swift`). Colour slots serialized via `hexRGB`, which
  drops the alpha channel, so any opacity you set (and the built-in
  ~0.18 mention/watch/find highlight backgrounds when duplicating a
  theme) flattened to solid blocks over the text. Added an alpha-aware
  `hexARGB` and use it for the builder bindings and the translucent
  highlight slots.

### Tests

- +4 (365 → 369): `Color hex` suite — `hexARGB` preserves alpha and
  round-trips, `hexRGB` still drops it, 6/8-digit parsing.

## [1.0.599] — 2026-06-02

### Security & correctness (audit follow-ups — batch 10, DCC robustness)

Four LOW findings in DCC file transfer.

- **A sender can't fill your disk** (`DCC.swift`). The receiver wrote
  every byte it received, ignoring the advertised file size — a peer
  could advertise 1 KB and stream gigabytes. Writes are now capped at
  the advertised size (size 0 = "unknown" stays uncapped).
- **Accept no longer clobbers an existing file on a dead connection**
  (`DCC.swift`). The destination was truncated/created up-front, so a
  connection that never established left an existing same-named file
  emptied (TOCTOU). The file is now created only once the peer is
  actually connected.
- **Bad DCC port-range settings can't crash or silently disable
  transfers** (`DCC.swift`). An inverted range (`start > end`) trapped
  forming the `Range`, and an out-of-bounds value crashed the port
  conversion; the range is now validated first.
- **A malformed advertised IP can't encode a garbage integer**
  (`DCC.swift`). `ipv4StringToInt` now requires four in-range octets.

### Tests

- +1 (364 → 365): `ipv4StringToInt` round-trips valid IPv4 and returns 0
  for out-of-range / malformed input.

## [1.0.598] — 2026-06-02

### Fixed (audit follow-ups — batch 9, state/concurrency)

Three LOW findings; no visible change.

- **Log-index backfill no longer fires per message** (`ChatModel.swift`).
  It was wired to `conn.$buffers`, which — because `Buffer` is a value
  type — publishes on every line append, spawning a Task and full
  re-scan each time. It now skips (no Task) unless the set of
  (network, buffer) pairs actually changed.
- **Session-history reads are size-bounded** (`SessionHistoryStore.swift`).
  `load` read and JSON-decoded the whole file before trimming per-buffer,
  so a bloated/tampered file could be fully materialized in memory. A
  32 MB file-size check now rejects oversized files before reading.
- **Backup debounce is per-instance** (`ChatModel.swift`). `lastBackupAt`
  was a process-global `static` shared across every `ChatModel` (e.g.
  test instances), so one model's backup suppressed another's debounce.
  Now an instance property.

Not changed: the three `events.sink` `Task { @MainActor }` hops are
technically redundant (events fire on the main actor) but removing them
makes the work run reentrantly mid-emission; the deferral is plausibly
intentional, so it's left as-is (tracked in `AUDIT.md`).

### Tests

- +1 (363 → 364): `SessionHistoryStore` ignores an oversized (sparse-
  truncated) file.

## [1.0.597] — 2026-06-02

### Fixed (audit follow-ups — batch 8, backup / log robustness)

Three LOW correctness findings.

- **Log purge no longer orphans the index** (`LogStore.swift`). The
  age-based purge removed *any* regular file older than the cutoff,
  including `index.json` — which would orphan every log. It now only
  deletes log-shaped files (`*.log`, `*.log.plain`, `*.log.1`).
- **The `/seen` table is bounded** (`SeenStore.swift`). Only per-nick
  history was capped; the number of distinct nicks per network grew
  forever. Added a 5,000-nick-per-network cap that evicts the
  oldest-seen entries, bounding both memory and the on-disk JSON.
- **Restore refuses an unexpected directory loudly** (`BackupService.swift`).
  Restoring into a support dir not named `PurpleIRC` silently no-op'd
  while the caller reported success; it now throws
  `unexpectedSupportDir` so the user learns nothing was restored. The
  directory is left untouched.

### Tests

- +2 (361 → 363): `LogStore` purge keeps `index.json` while removing old
  logs; `BackupService` restore throws on (and leaves untouched) a
  non-`PurpleIRC` destination — also chipping at the backup test-gap.

## [1.0.596] — 2026-06-02

### Performance (audit follow-ups — batch 7, chat-row rendering)

Three LOW findings in `BufferView`'s per-row rendering. No visible
change — purely fewer allocations per row on every render/hover.

- **Timestamps reuse a cached `DateFormatter`** (`BufferView.swift`).
  Each row allocated a fresh `DateFormatter` (expensive) on every body
  re-evaluation. A small process-wide cache keyed by the pattern reuses
  one formatter; patterns change rarely.
- **Watched-user check no longer rebuilds a Set per row**
  (`BufferView.swift`, `WatchlistService.swift`). The "is this line from
  a watched user?" test rebuilt a lowercased `Set` from the whole watched
  list for every row. `WatchlistService` now keeps a cached lowercased
  membership set (updated only when the list changes) behind a new
  `isWatched(_:)`; the row extracts its nick and does a single O(1) check.
- **Collapse grouping extracted + tested** (`BufferView.swift`). The
  join/part/quit/nick coalescing was inline and untested; pulled it into
  a pure `groupRows(_:collapse:window:)` (behaviour unchanged) and added
  coverage.

### Tests

- +5 (356 → 361): new `BufferView row grouping` suite — collapse off,
  3-event run → one summary, single-event run stays raw, a non-membership
  line breaks the run, and events outside the 300s window don't group.

## [1.0.595] — 2026-06-02

### Fixed (audit follow-ups — batch 6, LOW correctness/robustness cluster)

Six LOW findings; no behavioural change for well-formed data.

- **`EncryptedJSON.unwrap` no longer mis-slices a `Data` slice**
  (`EncryptedJSON.swift`, `BackupService.swift`). It used
  `suffix(from: magic.count)`, which treats the count as an *absolute*
  index and reads the wrong bytes (or traps) when handed a `Data` whose
  `startIndex` isn't 0. Switched to the index-agnostic `dropFirst`.
- **The cached DEK must be exactly 32 bytes** (`KeyStore.swift`). A
  truncated/corrupt 16-byte cache slot was accepted, silently building an
  AES-128 key from half a DEK; now anything but a full 256-bit key is
  rejected (→ passphrase unlock).
- **IRCv3 tag values can't smuggle CR/LF** (`IRCMessage.swift`). The
  `\r` / `\n` tag escapes were decoded back into raw line terminators,
  undoing the parser's no-control-chars-from-the-wire guarantee; they're
  now dropped (the tags we consume never carry line breaks). Other
  escapes (`\:`, `\s`, `\\`) are unchanged.
- **Appearance settings are clamped on load** (`SettingsStore.swift`).
  A corrupt/hand-edited file can no longer set `chatFontSize` to 0 or an
  absurd value (clamped 8–48) or a negative `purgeLogsAfterDays`
  (clamped ≥ 0). `viewZoom` is ephemeral and already clamped at `/zoom`.
- **Dead code removed:** the unused `runOnMain` helper
  (`AppleScriptCommands.swift`) and a no-op ternary in the RPL_NOWAWAY
  (306) handler (`IRCConnection.swift`).

### Tests

- +5 (351 → 356): new `LOW cluster fixes` suite — `unwrap` on a
  non-zero-`startIndex` slice, IRCv3 tag CR/LF stripping (+ other escapes
  preserved), and `chatFontSize` / `purgeLogsAfterDays` clamping. Updated
  the existing tag-escape test for the new CR/LF behaviour.

## [1.0.594] — 2026-06-02

### Security (audit follow-up — #7 completed, biometric-gated DEK read)

Finishes finding #7. Batch 2 (1.0.591) made the cached DEK device-only,
closing the off-device exfiltration vector and correcting the UI copy.
This change makes "Require Touch ID on launch" a real cryptographic gate
on the cached key, not just a UI overlay.

- **The cached DEK now sits behind a user-presence Keychain ACL**
  (`KeychainStore.swift`, `KeyStore.swift`). When the toggle is on, the
  key is stored with `SecAccessControlCreateWithFlags(...
  ThisDeviceOnly, .userPresence)`, so even a process reading the Keychain
  directly must pass Touch ID (or the device password) — the gate no
  longer lives only in the app's blur overlay.
- **Launch flow reworked around a no-prompt probe** (`KeyStore.refreshState`,
  `ContentView.swift`). The encrypted `requireBiometricsOnLaunch`
  preference can't be read until the DEK is unlocked (chicken-and-egg),
  so launch now keys off a non-interactive Keychain probe
  (`hasBiometricCache`): a gated cache triggers one Touch ID prompt whose
  authenticated `LAContext` is reused for the key read (no double
  prompt). Existing installs upgrade to a gated cache automatically on
  the next unlock.
- **No lockout, by construction.** If the ACL can't be created (ad-hoc
  build / no biometry hardware) the key falls back to plain device-only
  storage; if the prompt is cancelled or fails, the passphrase sheet
  takes over. The passphrase + on-disk envelope always recover the DEK.
  Verified on hardware: single prompt on launch, cancel → passphrase
  fallback, toggle-off → silent unlock.

## [1.0.593] — 2026-06-01

### Security & correctness (audit follow-ups — batch 4, assistant / Ollama)

Five LOW findings across the local-LLM assistant, plus the assistant
test-gap.

- **Private chat can't be POSTed to a public host** (`OllamaClient.swift`).
  The assistant is framed as local, but the Ollama URL was used as-is, so
  a mistyped/hostile value could ship your conversation to an arbitrary
  server. The client now requires a well-formed `http(s)` URL with a host
  (a bare `localhost:11434` with no scheme is rejected) AND that the host
  is local/LAN — loopback, RFC1918, link-local, `*.local`/`*.lan`/etc., or
  a single-label intranet name. A public host is refused with a clear
  message. (#21/#22)
- **Requests are bounded** (`OllamaClient.swift`). Explicit timeouts —
  10 s for health/model-list, 60 s for chat — so a stalled Ollama can't
  leave the suggestion strip spinning. (#25)
- **Generations cancel and don't clobber** (`AssistantEngine.swift`).
  Each buffer tracks its in-flight generation Task plus a monotonic
  generation token. A new request (or disengaging / dismissing the strip)
  cancels the previous one, and a completing reply only publishes if it's
  the latest generation for a buffer that's still engaged — so a slow
  earlier reply can't overwrite a newer one, and a reply can't land in a
  buffer you already left. (#23/#24)

### Tests

- +6 (345 → 351): new `Assistant` suite — Ollama URL/local-host
  validation (accept local/LAN, reject malformed + public),
  `isLocalHost` classification, reply `cleanup`, and `buildMessages`
  role mapping. Closes the assistant test-gap finding (#26).

## [1.0.592] — 2026-06-01

### Security (audit follow-ups — batch 3, PurpleBot hardening)

Three scripting-host findings from the 2026-06-01 audit, plus a doc-sync
LOW and the scripting test-gap.

- **PurpleBot scripts can't reach each other's store** (`BotHost.swift`).
  The `irc.store` bridge trusted a script-supplied id, so a script that
  knew another's UUID could `globalThis.irc._storeGet(otherUUID, key)`
  its way into a different script's store. The bridge now resolves an
  **ephemeral capability token** minted fresh per reload and baked only
  into that script's own IIFE scope — a script can't forge or discover
  another's token, so the store id is no longer a trust boundary the
  script controls.
- **A bad trigger regex can't freeze the app** (`BotEngine.swift`).
  User-supplied (raw-regex) `TriggerRule`s ran on every PRIVMSG on the
  main actor with no bound, so a catastrophic-backtracking pattern hung
  the UI. Matches now run under a 200 ms wall-clock budget on a
  background queue; a rule that blows the budget is auto-disabled (with a
  logged + in-buffer notice) so it can't keep stalling. Input is capped
  at 1 KB, and literal/escaped rules skip the watchdog (they aren't
  ReDoS-prone).
- **A script can't spin the main actor with timers** (`BotHost.swift`).
  `irc.setTimer`/`setTimeout` had a 10 ms floor and no count limit, so
  one script could spawn thousands of fast callbacks. Now capped at 64
  concurrent timers with a 50 ms minimum interval; over the cap returns
  `0` and logs.
- **Bot event docs match reality** (`BotHost.swift`). The documented
  event list now includes `nickchange` and `watchedQueryAutoOpened` and
  notes the generic `event` fan-out.

### Tests

- +3 (342 → 345): new `BotHostTests` — tampered-source contentHash
  rejection, per-script store separation, and an end-to-end check that a
  script forging another's UUID through the store bridge gets nothing
  back (closes the scripting test-gap finding).

## [1.0.591] — 2026-06-01

### Security (audit follow-ups — batch 2 from `AUDIT.md`)

Four MEDIUM security findings from the 2026-06-01 audit, plus one LOW
that lived in the same file.

- **DCC offers no longer dial arbitrary hosts** (`DCC.swift`). An
  incoming `DCC SEND`/`CHAT` advertised a peer address that was handed
  straight to `NWEndpoint.Host` on accept — a bare hostname was accepted
  verbatim, an SSRF primitive that could make the client connect to an
  attacker-chosen host (incl. internal services). Offers are now
  validated to a real IP literal (integer or dotted IPv4, or an IPv6
  literal); hostnames are refused, and loopback / link-local /
  unspecified addresses are rejected. RFC1918 ranges stay allowed so
  on-LAN DCC keeps working. Unit-tested (new `DCCSecurityTests`, +
  closes the "no DCC validation tests" LOW finding).
- **DCC wildcard bind is no longer silent** (`DCC.swift`). When the
  listener can't bind the advertised IP and falls back to `0.0.0.0`
  (any host that can reach the port could race the peer), the offer now
  logs a warning and posts a visible ⚠️ notice in the buffer instead of
  binding every interface silently.
- **Keychain items are now device-only** (`KeychainStore.swift`). The
  wrapped DEK and stored credentials were `kSecAttrAccessibleWhenUnlocked`,
  which is eligible for iCloud Keychain sync, Keychain migration, and
  backups — so the key could leave this Mac, and the DEK alone unwraps
  every encrypted file without the passphrase. Switched to
  `…ThisDeviceOnly`; existing caches upgrade on the next launch. The
  Security-tab "Require Touch ID" copy was corrected: it's a launch-time
  screen lock over the app UI, not a cryptographic gate on the cached key
  (the prior copy over-claimed). A real biometric ACL on the DEK read is
  deferred (it touches the critical unlock path) and remains tracked in
  `AUDIT.md`.
- **Proxy configs can't cross connections** (`ProxyFramer.swift`). Two
  proxied connections starting close together could pop each other's
  config out of the shared FIFO — connection A would then authenticate
  to its proxy with B's credentials and tunnel to B's target. The
  hand-off is now single-in-flight (the pending list never holds more
  than one config), with a bounded wait so a connection that fails
  before its stack is built can't wedge setup. The `lastError` static is
  now lock-guarded (`takeLastError`), closing a data-race LOW finding.
- **"Say" automation can't run commands** (`AppIntents.swift`,
  `AppleScriptCommands.swift`). The `SayInActiveBuffer` Shortcut and the
  AppleScript `say in active buffer` verb forwarded text verbatim to the
  slash dispatcher, so a shared/automated "say `/quit`" or "say `/raw …`"
  executed the command. Both now route through a new literal-chat path
  (`ChatModel.sendChatLiteral` → `IRCConnection.sendChatLiteral`) that
  bypasses the dispatcher, so a leading "/" is posted as chat.

### Tests

- +4 (338 → 342): new `DCCSecurityTests` suite covering peer-host
  validation (integer/dotted IPv4, IPv6 literals, hostname rejection,
  loopback/link-local/unspecified rejection, RFC1918 allowance).

## [1.0.590] — 2026-06-01

### Fixed (audit follow-ups — first batch from `AUDIT.md`)

Driven by the multi-agent audit recorded in `AUDIT.md` (2026-06-01).
This batch closes the two HIGH findings and the shared-`WatchlistService`
root cause behind five MEDIUM findings.

- **App Log viewer no longer crashes on launch** (HIGH). The encrypted
  app-log loader read its 4-byte length prefix with `load(as:)`, which
  *traps* on a misaligned access — and after the first record the slice
  base is almost never 4-byte aligned, so opening the App Log viewer (or
  `loadFromDisk` at launch) crashed once `app.log` held more than one
  record. Switched to `loadUnaligned`, matching `LogStore`'s loader.
  (`AppLog.swift`.)
- **Restore now writes a pre-restore safety backup first** (HIGH).
  `BackupService.restore()` wiped Application Support with no snapshot of
  the current state — a wrong/stale archive meant irrecoverable loss of
  live settings/keystore/logs, the exact clobber the backup standard
  exists to prevent. Restore now writes a `PurpleIRC-pre-restore-<stamp>`
  archive into the backup dir and only proceeds once it succeeds (an
  empty support dir, zip exit 12, is tolerated — nothing to lose).
  (`BackupService.restore`, `ChatModel.performRestore`.)
- **Watchlist state is now per-network** (5 MEDIUM). A single shared
  `WatchlistService` held un-namespaced state across every connection,
  so one network could clobber another's watch state. All of these are
  fixed by keying state on `IRCConnection.id`:
  - One network's disconnect no longer wipes every network's presence,
    timers, and MONITOR capability.
  - A nick's absence in one network's ISON reply no longer flips it
    offline (and re-fires "is online") when it's still online elsewhere
    — presence is now the OR across networks, and the online alert fires
    on the *aggregate* transition.
  - MONITOR / ISON lines are written to the socket of the network that
    registered them, not whichever connection happens to be active.
  - Each non-MONITOR network gets its own ISON poll timer instead of a
    single shared timer that only ever polled one socket.
  - `WatchlistDelegate.watchlistSendRaw` now carries the originating
    network id; the old `allWatched` dead parameter and the
    `seenInChannel` re-alert hack are gone (the aggregate-transition
    alert subsumes the latter). (`WatchlistService.swift`,
    `IRCConnection.swift`, `ChatModel.swift`.)

### Tests

- +6 tests (332 → 338): five in a new `WatchlistServiceTests` suite
  (cross-network presence aggregation, disconnect isolation, per-socket
  MONITOR/ISON routing, watched-list-diff routing, per-network
  MONITOR online/offline) and one in `BackupServiceTests` asserting the
  pre-restore safety archive is written and captures the pre-restore
  state.

## [1.0.509] — 2026-05-24

### Changed (sidebar layout + window-state hardening)

- **Top-level sidebar migrated off `NavigationSplitView` to a manual
  `HStack`** with a fixed 220 px column, per the PhantomLives canonical
  pattern (CLAUDE.md). `NavigationSplitView` on macOS 14+ does not
  reliably honor its declared minimum column width at runtime and
  persists a corruptible divider position in both `UserDefaults` and
  `.savedState`; the manual layout owns every pixel. A new toolbar
  button (and ⌃⌘S) toggles sidebar visibility via
  `@AppStorage("sidebarVisible")`.
- **Added `WindowStateGuard` + `AppDelegate`** (wired via
  `@NSApplicationDelegateAdaptor`). On launch it purges stale
  `"NSSplitView Subview Frames *"` keys and the bundle's `.savedState`
  directory, and runs a versioned one-shot wipe (`resetVersion = 1`) so
  every existing install drops any divider position left over from the
  old `NavigationSplitView` chrome.
- **New Window → Reset Window State…** menu item calls
  `WindowStateGuard.forceReset` as a user-facing recovery affordance.

### Fixed (file hygiene)

- **`.gitignore` now ignores Finder-created duplicate bundles**
  (`PurpleIRC 2.app`, `PurpleIRC 3.app`, … via `* [0-9].app/`) so the
  copies Launch Services drops alongside the original stop showing up in
  `git status`. Deleted the stray `PurpleIRC 2.app` that had accumulated.

### Docs

- README: corrected the stale "Layout" section (8 files → current
  architecture map), refreshed Build & Run to document the
  build → `/Applications/` → relaunch `install.sh` chain, fixed the test
  count (267 → 332), and dropped the `NavigationSplitView` description.
- HANDOFF: bumped the build-block test count (245 → 332), updated the
  header date, and logged Tier #18.

## [1.0.247] — 2026-05-12

### Added (cross-network unified search)

- **⌘⇧F opens the new Find Across Networks sheet.** Edit menu's
  "Find Across Networks…" entry routes here too. Searches every
  persisted chat-log file across every network in one pass and
  surfaces the matches in a single list.
- **`LogStore.search(query:caseSensitive:limit:)`** is the new actor
  method. Walks `enumerateAllLogs()` first (named entries) then the
  orphan slug files so a freshly-restored backup still produces
  results before the index gets backfilled. Encrypted log files
  transparently decode through the existing `decodeFile` path. Hits
  cap at 500 per query so a pathologically broad search can't OOM
  the app; the UI surfaces "Showing first N matches" when the cap
  is hit.
- **Each `SearchHit` carries**: network + buffer display names, the
  raw slug pair for routing, 1-based line number, the full line
  text, and a parsed ISO-8601 timestamp (when the prefix matches
  what `LogStore.append` writes). The list view renders relative
  times, network/buffer chips, and a snippet with the timestamp
  stripped.
- **Filter chips along the top** let the user pin the result list
  to a subset of networks. "All networks" is the default.
- **Click-to-jump**: double-click any result (or hit the inline
  Jump button) and the workspace:
  - Switches `activeConnectionID` to the connection matching the
    hit's network slug.
  - Selects an already-open buffer with that name (case-insensitive
    compare).
  - Otherwise routes through `/join` (channels) or `/query`
    (nicks) so the connection's auto-create path materialises a
    fresh buffer for the match.
- **Debounced search execution**: keystrokes throttle the actor
  call at 350 ms trailing — searching is a full disk walk + AES
  decrypt + substring scan, so we don't want to redo it per
  character. The result spinner shows when a search is in flight.

### Data flow

The feature is fully built on existing primitives:
- `LogStore` already keeps a persistent index of (network, buffer)
  pairs + orphan recovery for unindexed slug files (1.0.225 work).
- AES-GCM transparent decryption was already in `decodeFile`.
- `SeenStore.slug(for:)` is the canonical slug derivation reused
  for the click-to-jump network match.
- `ChatModel.sendInput("/join …")` / `("/query …")` provides the
  auto-create routing for buffers that aren't currently open.
- No new persistence path, no new encryption envelope.

### Tests (9 new)

In `LogStoreTests`:
- `searchFindsLineByCaseInsensitiveSubstring`
- `searchHonorsCaseSensitivity`
- `searchFoldsAcrossNetworksAndBuffers`
- `searchEmptyQueryReturnsEmpty`
- `searchNoMatch`
- `searchHonorsResultLimit`
- `searchWorksUnderEncryption`
- `searchParsesIso8601Timestamp`
- `parseLogTimestampHandlesMalformedLines`

Test count: 323 → 332.

## [1.0.243] — 2026-05-12

### Added (world-class Address Book workspace)

Big revamp landing in two commits on the `feat/person-model-workspace`
branch. **Phase A** introduced the Person-model data layer; this entry
covers **Phase B + C** — the workspace UI, deeplink rewiring, and the
Setup-tab removal.

#### New workspace window (⇧⌘B)

- **`AddressBookView` is a non-modal `Window(id: "address-book")`** in
  `App.swift`. Opens via the toolbar Address Book button or ⇧⌘B from
  anywhere in the app. Stays open alongside chat — Mail's address-book
  / Music's Library idiom, not the old modal sheet.
- **Three-pane NavigationSplitView**:
  - **Filters sidebar**: Presence (All / Online / Offline / Unknown),
    Network coverage (Any / Single / Multi / Unlinked), Recency
    (24h / 7d / 30d / Quiet 30d+), Tags (with usage counts +
    chip-color dots), Recent hits (top 10 from
    `WatchlistService.recentHits`).
  - **Contact list** with multi-select, +/− buttons, bulk-tag menu,
    bulk watch-on/off, **Suggest Links** affordance, and a Tags
    button that opens the existing `ContactTagManagerView` sheet.
    Rows show avatar + presence dot + nick + per-contact watch bell
    + coverage badge (count of distinct linked networks) + inline
    tag-color dots.
  - **Sectioned detail pane**: Identity (photo, nick, note, watch
    toggle), Linked Nicks, Alert Overrides, Tags, 14-day Activity
    Sparkline, Activity Timeline (merged across networks), Channels
    in Common, Hostmask History, Cross-store Matches, Attachments,
    Markdown Notes.
- **`pendingAddressBookSelection` deeplink** consumed on `.onAppear`
  + `.onChange` so the sidebar's "Edit address book entry…" and the
  user-list "Add to address book" entry points open the workspace
  pre-selected to the right contact.
- **`.searchable` field in the window toolbar** filters by nick /
  linked-nick / note / rich-note substring.

#### New per-contact UI sections

- **`ContactLinkedNicksSection`** — every (network, nick) pair on
  the contact with a per-row Unlink button (refuses on the last
  binding) and a "Link another nick" form that picks from the live
  connection list (or "All networks" for the legacy any-net
  sentinel). Per-link source badge: manual / auto-migrated / host
  match / account match.
- **`ContactAlertOverridesSection`** — tri-state toggles for
  system banner / play sound / dock bounce (Inherit / On / Off),
  custom sound picker, and a custom banner-message field. Each
  toggle shows what the global value resolves to in its
  "Inherit" label so users know what they're inheriting.
- **`ContactActivityTimelineSection`** — merged `SeenSighting`
  timeline across every linked-nick on every connected network,
  sorted newest-first, capped at 100 rows. Per-row icon by kind
  (msg/join/part/quit/nick), network name, hostmask, channel,
  detail snippet, relative time.
- **`ContactSharedChannelsSection`** — channels you and the contact
  currently share, grouped by network. Each chip jumps you to the
  channel with one click.
- **`ContactHostmaskHistorySection`** — distinct `user@host`
  strings ever seen for this contact, with first/last-seen
  relative timestamps. Spots reconnects from new ISPs / VPNs and
  same-host coincidences that back the auto-link suggestions.

#### Suggest Links

- New **`SuggestLinksSheet`** runs `ContactLinker.suggestLinks` over
  the current address book + every connected network's `SeenStore` +
  IRCv3 `accountByNick` map. Shows candidate (network, nick) pairs
  to link under existing contacts via shared-hostmask or
  shared-services-account heuristics. **Nothing auto-applies** — the
  user clicks Link per row to accept; the new binding is stamped
  with `LinkedNick.Source.hostmask` or `.accountTag`.

#### Surface migrations (Phase C)

- **`Setup → Address Book` tab REMOVED entirely.** `SetupView.Tab.addressBook`
  enum case + its slot in the People & places group + the
  `case .addressBook:` arm of the `content` switch are all gone. The
  People & places group collapses to `[.channels, .ignores, .highlights]`.
- **`Sources/PurpleIRC/Setup/AddressBookSetup.swift` deleted.** Every
  feature it surfaced lives in the workspace now.
- **Helper files moved out of `Setup/` into `AddressBook/`**:
  `AttachmentRow.swift`, `ContactActivitySparkline.swift`,
  `ContactMatchesView.swift`, `AddressBookTagViews.swift` (the chip
  popover / chip row / FlowChips / tag manager set). All four are
  contact-rendering, not Setup-specific.
- **Toolbar Address Book button** now `openWindow(id: "address-book")`
  instead of `pendingSetupTab = .addressBook + showSetup = true`.
  Same icon, same muscle memory.
- **Sidebar ContactRow context menu** — "Edit address book entry…"
  uses the workspace deeplink (one-line change per call site).
- **`BufferRow` query context menu** — same rewiring.
- **`WatchlistView` "Open Address Book…" button** — same rewiring.
  The watchlist sheet stays as the "recent hits" dashboard; the
  workspace is the editing surface.

#### Reuse, not rewrite

Every UI element in the detail pane is either lifted verbatim from
the deleted `AddressEntryEditor` (photo picker / attachment row /
markdown editor / cross-store matches) or composed from helpers
that already existed in 1.0.240 (`ContactActivitySparkline`).
`Contact.swift` from Phase A provides every cross-network read
helper (matches / allSightings / allCurrentHostmasks /
ContactLinker). No new persistence path; no new encryption envelope.

#### Tests + verification

323 tests still green (no regressions; the test surface for the
Person-model layer landed in Phase A and remained intact across
the UI work). Release-signed `.app` builds cleanly and launches.
Smoke tests on the workspace: open via ⇧⌘B, switch contacts in
the list, scroll detail sections, link a nick, unlink a nick,
toggle a per-contact alert override, run Suggest Links, multi-
select and bulk-tag.

#### Risks / migration notes

- Migration from pre-1.0.242 settings.json is idempotent (handled in
  `AppSettings.init(from:)`). Wire format is byte-identical for any
  user who hasn't started editing linked nicks or alert overrides —
  see `AddressEntry.encode(to:)`'s default-omit logic. The
  auto-backup-on-launch + restore flow keeps working with older
  PurpleIRC builds.
- The `networkSlug == ""` any-network sentinel still requires every
  match site to funnel through `AddressEntry.matches(networkSlug:nick:)`
  or `matchesAnyNetwork(nick:)`. Phase A retrofitted every known site
  (PhotoUtilities, BufferView, ContentView). Future contributors:
  do NOT do `entry.nick.caseInsensitiveCompare(target)` — use the
  helpers.

## [1.0.241] — 2026-05-12

### Added (Shortcuts.app + Focus Filter)

- **Five App Intents** discoverable in Shortcuts.app + System Settings
  → Focus → Focus Filters. All run on the main actor and reach the
  live ChatModel via the same `AppleScriptBridge.host` weak ref the
  AppleScript surface uses.
  - **Set Away** — `/away <reason>` on the active network. Reason
    parameter defaults to "Away".
  - **Set Back from Away** — `/back` on the active network.
  - **Send IRC Message** — PRIVMSG to a channel or nick. Both fields
    sanitized through `IRCSanitize.field` so a Shortcuts-supplied
    body can't smuggle a second IRC line.
  - **Say in Active Buffer** — like the Shortcuts version of typing
    in the input bar; no target needed.
  - **PurpleIRC Focus Filter** — assignable to a macOS Focus mode.
    Takes a newline-separated list of network names to hide. The
    sidebar's Networks section filters its rows through
    `ChatModel.focusFilterHiddenNetworks` while the Focus is active;
    the underlying connections stay live, only the sidebar row
    vanishes. When the Focus turns off, `perform()` fires again
    with an empty list and the rows return.
- New `AppShortcutsProvider` (`PurpleIRCShortcuts`) registers all
  four basic intents with Siri / Spotlight invocation phrases ("Set
  away in PurpleIRC", "Say something in PurpleIRC", etc.).
- New `ChatModel.applyFocusFilter(hiddenNetworkNames:)` and
  `.isHiddenByFocusFilter(_:)` helpers. The hidden-names set is
  lowercased at the input boundary so case-only mismatches resolve
  to the same connection.
- Sidebar shows a `"N hidden by Focus"` caption under the Networks
  section while a filter is active, so the user knows why a network
  isn't appearing (and that closing the Focus will bring it back).
- Requires macOS 14 — already the project's deployment target via
  `Package.swift` (`.macOS(.v14)`), so no extra version gating.

## [1.0.240] — 2026-05-12

### Added (contact activity sparkline)

- **Activity sparkline in the Setup → Address Book contact editor.**
  Small 14-day bar chart of message volume from the selected contact,
  folded across every connected network's `SeenStore`. Below the bars:
  the total message count + a hint that the seen tracker has to be on
  in Setup → Bot for the chart to show data.
- Only `kind == "msg"` sightings count — joins / parts / quits are
  activity but not conversation, and including them would make the
  chart spike on every channel hop.
- New `ChatModel.recentMessageDayBins(nick:days:)` is the data
  helper; `ContactActivitySparkline` (in `Setup/`) is the view.
  Both are public so future placements (sidebar row tooltip, contact
  card pop-out) can reuse them.

### Skipped

- **Reciprocal-watch indicator** — turns out not implementable in any
  general protocol-driven way (HANDOFF's `MONITOR L` reading was off;
  that lists OUR targets, not who's watching us). Pulled from the
  quick-wins list rather than ship something misleading.

## [1.0.239] — 2026-05-12

### Added (pop-on-watch)

- **First-message pop-on-watch.** New toggle in Setup → Notifications →
  "Open query when a watched contact first messages me". When enabled,
  an inbound PRIVMSG from an address-book contact with the watch bell
  on that creates a fresh query buffer (first message of session)
  automatically:
  - Switches `activeConnectionID` to the network the message arrived on.
  - Selects the new query buffer.
- Off by default — opt-in because it interrupts the user's current
  focus. The watch-hit banner / sound / dock bounce still fire as
  before; this just adds the optional focus-switch on top.
- Plumbing: new `AppSettings.popQueryBufferOnWatch` (forward-compat
  decode); pushed to each `IRCConnection` via `applySettingsToAll`;
  emits new `IRCConnectionEvent.watchedQueryAutoOpened(bufferID:from:)`
  from inside `handlePrivmsg` only when (a) `isToSelf` is true,
  (b) the sender is on `watchlist.watched`, (c) the buffer was just
  created. ChatModel's event sink does the activation. The PurpleBot
  event dictifier also forwards the event so JS scripts can react.

### Added (PurpleBot `irc.store` persistence)

- **Per-script key/value store.** The PurpleBot JS surface gains
  `irc.store.get(key)`, `.set(key, value)`, `.delete(key)`, and
  `.keys()`. Each script's state lives in its own JSON file at
  `<supportDir>/scripts/<scriptID>.store.json` — two scripts that
  both use `count` see independent values.
- Per-script isolation via IIFE wrap. Each script's source is now
  wrapped in `(function() { 'use strict'; const __PURPLEBOT_SID =
  '<uuid>'; const irc = Object.assign({}, globalThis.irc, { store:
  {...} }); <user source> })();` before evaluation. The `irc` object
  inside the script is a per-script shim whose `store` methods proxy
  to internal `irc._storeGet/Set/Delete/Keys(scriptID, ...)` Swift
  blocks with the baked-in script ID.
- Behaviour change worth knowing: top-level `var x` declarations in
  user scripts are now IIFE-local (no longer leak to globalThis).
  This is the standard JS-module isolation pattern and shouldn't
  affect scripts that don't rely on inter-script global sharing
  (which was never a documented contract).
- Storage envelope identical to every other store: plaintext when the
  keystore is locked, AES-256-GCM-sealed under the per-install DEK
  once unlocked. Reseals on key change via the same `setEncryptionKey`
  path BotHost already uses for index.json + script sources.
- `remove(script)` now also purges that script's `.store.json` so
  deleting a script doesn't leave its persisted state behind on disk.
- NukeService already wipes the `scripts/` subtree, so `/nuke` clears
  these for free — no per-feature change needed.

### Tests

- `ScriptStoreTests` (9 tests): get-on-missing-key, set/get round-trip,
  delete, keys snapshot, **script isolation invariant** (two scripts
  hitting the same key see distinct values), plaintext persistence
  across instances, **encrypted persistence across instances** with
  matching DEK, purge wipes both cache and file, JS `null` write
  semantics. Test count climbs to 303.

## [1.0.238] — 2026-05-12

### Changed (refactor — extract BufferInputState)

- **New `BufferInputState: ObservableObject`** in
  `Sources/PurpleIRC/BufferInputState.swift`. Holds the input-bar
  cluster that previously lived as four `@State` properties on
  `BufferView`:
  - `input: String` — live text in the TextField.
  - `history: [String]` — rolling sent-lines history.
  - `historyPos: Int` — cursor into `history` for ↑/↓ nav.
  - `completion: TabCompletion?` — active tab-completion cycle.
  - `pickerDismissedFor: String?` — Esc-dismiss flag for the
    slash-command picker.
- **`BufferView` now holds one `@StateObject`** instead of five
  per-property `@State`s. SwiftUI preserves the object across
  buffer switches (same shape as the prior `@State` cluster did —
  BufferView identity is keyed by view position, not by
  `bufferIndex`).
- **`TabCompletion` lifted to top level.** Was nested inside
  `BufferView` as `BufferView.TabCompletion`; now in
  `BufferInputState.swift` since the state holder is the natural
  home for its only owner. Shape unchanged.
- **History-mutation invariants centralised.** `pushHistory(_:)`,
  `historyPrev()`, `historyNext()` on `BufferInputState` replace
  three inline triplets in `BufferView` (`sendDraft`, `sendDirect`,
  `submit`) that each open-coded the cap-at-200 + reset-to-end
  dance. The history nav handlers in `.onKeyPress(.upArrow)` /
  `.downArrow` now read as `historyPrev()` / `historyNext()` rather
  than the three-line conditional that was there before.
- **`maxHistory` constant** (`= 200`) replaces a magic number
  scattered across the prior three call sites.

All 294 tests still pass. The input flow is the hottest UX path in
the app and has no test coverage (it's a SwiftUI view), so this
release was smoke-tested by exercising send / history nav (↑/↓) /
slash picker + Esc / tab completion / multi-line paste in the
release `.app` bundle before committing.

## [1.0.237] — 2026-05-12

### Changed (refactor — typed BufferKey)

- **New `BufferKey` struct** in `MessageKindFilter.swift`. Wraps
  `(networkSlug, bufferName)`, lowercases the buffer name at init, and
  exposes the same `"<slug>/<name-lower>"` string via
  `CustomStringConvertible` that `AppSettings.messageFiltersByBuffer`
  has stored on disk since 1.0.130. The dictionary is still
  `[String: MessageKindFilter]` — only the runtime API was retyped.
  Settings.json round-trip is unchanged byte-for-byte.
- **Four `SettingsStore` methods now take `BufferKey`.** Old shape:
  `messageFilter(networkSlug:bufferName:)` /
  `setMessageFilter(_:networkSlug:bufferName:)` /
  `clearMessageFilter(networkSlug:bufferName:)` /
  `hasMessageFilterOverride(networkSlug:bufferName:)`. New shape: each
  takes `for buffer: BufferKey`. Eliminates the four call sites in
  `BufferView.swift` (`effectiveFilter`, `filterButton`, the two
  `MessageFilterPopover` methods, and the popover's "Use defaults"
  button) that previously re-computed the
  `SeenStore.slug(for:) + buffer.name` pair separately. They now
  share a single `BufferView.currentBufferKey` computed property so
  the popover, the effective filter, and the override badge can never
  disagree about which buffer they're addressing.
- **`MessageFilterPopover` takes one `bufferKey: BufferKey` instead of
  two separate strings.** Same change, smaller surface.
- **`MessageKindFilter.key(networkSlug:bufferName:)` static helper
  removed.** Was the lone caller of the manual interpolation /
  lowercase step; the wrapping `BufferKey.init` is now the single
  source of truth for the format.

### Tests

- `MessageKindFilterTests`:
  - `keyIsCaseInsensitiveOnBufferName` / `keySeparatesNetworks`
    replaced with `bufferKeyFoldsCase` (also asserts `hashValue`
    equality) and `bufferKeySeparatesNetworks`.
  - New `bufferKeyDescriptionMatchesOnDiskFormat` pins
    `BufferKey(networkSlug: "libera", bufferName: "#Swift")
    .description == "libera/#swift"`. This is the wire-format
    invariant — anyone changing it would silently drop every
    existing user's per-buffer overrides on the next save.
  - The four SettingsStore CRUD tests updated to construct
    `BufferKey` values instead of passing the two strings.

Test count holds at 294 (293 + new wire-format pin – 1 collapsed key
test; net +1 from the previous round).

## [1.0.236] — 2026-05-12

### Changed (refactor — Setup tab split)

- **`SetupView.swift` is now a 170-line coordinator.** Was 3869 lines
  with 22 view structs piled into one file (the Setup tabs plus their
  editors and helper sheets). Split into 22 sibling files under a new
  `Sources/PurpleIRC/Setup/` subdirectory, one per tab/helper:
  - Tabs: `ServersSetup`, `AddressBookSetup`, `ChannelsSetup`,
    `IgnoreSetup`, `BehaviorSetup`, `ScriptsSetup`, `HighlightsSetup`,
    `BotSetup`, `IdentitiesSetup`, `SecuritySetup`, `AppearanceSetup`,
    `ProxyDccSetup`, `NotificationsSetup`, `LoggingSetup`,
    `ThemesSetup`, `FontsSetup`, `SoundsSetup`, `AssistantSetup`,
    `ShortcutsAliasesSetup`, `BackupSetup`.
  - Helpers split into companion files: `AttachmentRow.swift`,
    `AddressBookTagViews.swift` (the chip / popover / manager set),
    `ContactMatchesView.swift`.
- **`SetupView.swift` keeps only the `Tab` enum, sidebar `groups`
  list, and `content` dispatch switch.** That switch was already the
  single point of routing — every case statement that adds a new tab
  ends up there, and Swift's exhaustiveness check catches a missing
  case at PR time. Nothing else changed about the dispatch contract.
- **No behaviour change.** Every struct kept its name, properties,
  initializer, and body. The only edits were file headers (added
  `import SwiftUI` / `AppKit` / `UniformTypeIdentifiers` to each new
  file) and the MARK comments that previously prefixed each section
  now live at the top of their own file. The `private struct
  FlowChips` retained its access modifier because Swift's top-level
  `private` is file-local; FlowChips ships in the same file
  (`AddressBookTagViews.swift`) as its only caller (`ContactTagChipRow`).
- **HANDOFF updated** to note that new tabs live under `Setup/`
  rather than at the end of `SetupView.swift`.

All 293 tests still pass; the refactor is mechanical and has no
data-format or behaviour implications. The release-signed `.app`
bundle is identical in size + structure to 1.0.235.

## [1.0.235] — 2026-05-12

### Fixed (security)

- **`IRCSanitize.field` no longer lets a clean `\r\n` slip through.** The
  fast-path guard scanned `Character`s, and Swift's grapheme clustering
  collapses `\r\n` into a single extended grapheme cluster that doesn't
  equal `Character("\r")` or `Character("\n")` — so a body containing a
  bare `"hello\r\nworld"` was returned unchanged, and the wire-level
  `+ "\r\n"` terminator in `IRCClient.send` would then smuggle "world"
  to the server as a fresh IRC command. The guard now scans
  `unicodeScalars` (where `\r` and `\n` are distinct scalars regardless
  of cluster context); the filter pass was already correct. Caught by
  the new `IRCSanitizeTests.fieldStripsCRLFNUL` regression test below —
  this would not have been found without the test gap fillers.

### Changed (correctness)

- **`IRCConnection.idx(of:)` returns `Int?` instead of force-unwrapping.**
  Every call site (`logNumeric`, `appendInfo`, `appendError`) now
  `guard let`s the result. Structurally safe under today's callers
  (each passes `ensureServerBufferID()`), but the prior force-unwrap
  was fragile to refactor and not worth the panic surface.
- **Three per-nick maps in `IRCConnection` now bound and clear on
  disconnect.**
  - `lastUserHostByNick` (touched on every inbound prefix-bearing
    message; consumed by BotEngine for seen-tracker host capture)
    caps at 4096 entries; the dict is nuked on overflow and
    repopulates organically.
  - `whoisOriginByNick` (channel routing for `/whois` replies) caps
    at 64 entries; previously relied solely on end-of-whois numerics
    (318/369/401/406) to evict, so a server that swallowed those
    accumulated routes forever. Cap-overflow nuke is safe: worst
    case a pending reply lands in the server buffer rather than the
    originating channel.
  - `lastAwayReplyAt` eviction threshold lowered from 1024 → 256 so
    the recency-based trim kicks in sooner.
  - All three are explicitly cleared on `.disconnected` / `.failed`
    alongside the existing `openBatches` / `chatHistoryFetched` reset,
    so a reconnect to the same network doesn't carry stale routing /
    hostmask / away-reply data from before the link dropped.

### Added (tests — closing HANDOFF's flagged regression-coverage gaps)

26 new tests across 3 files, raising the total from 267 → 293. These
are the four regression suites HANDOFF has called out as "worth adding"
since 1.0.92.

- **`IRCSanitizeTests`** (11 tests) — pins `field(_:)` against bare CR /
  LF / NUL, CRLF combinations, multi-line collapse, and unchanged
  identity on clean input; pins `maskForDisplay(_:)` against PASS,
  AUTHENTICATE (with `+` / `*` control-marker preservation), and
  outbound + echo-message PRIVMSG-NickServ-IDENTIFY masking; pins
  that unrelated lines (including `PRIVMSG <not-NickServ> :IDENTIFY ...`
  song lyrics) pass through unchanged; pins that masking is pure
  (input unchanged) so an inadvertent send of the input doesn't leak.
- **`SASLNegotiatorTests` — chunkedAuthenticate suite** (+6 tests) —
  pins empty → `AUTHENTICATE +`, 1..399 bytes → single line no
  terminator, exactly 400 → split + trailing `+`, 401 → 400-byte + 1
  byte (last short chunk implicitly terminates, no `+`), exact
  multiples of 400 always append `+`. RFC-correctness regression.
- **`IRCConnectionRobustnessTests`** (9 tests) — 433 retry cap
  increments on each 433, caps at 4 and self-disconnects, resets on
  001 (with 001 also picking up the authoritative nick); BATCH +id
  open / -id close, orphan -id no-op, duplicate +id replaces, cap
  evicts oldest at the 256 boundary, and dict clears on both
  `.disconnected` and `.failed` state transitions. Required lowering
  access on `IRCConnection.handle(_:)` and `handleState(_:)` from
  `private` to internal, plus a narrow set of `_test*` read-only
  accessors at the bottom of `IRCConnection.swift` so the new suite
  can observe state without granting blanket internal access.
- `WatchlistService` gained an `init(skipAuthRequest:)` overload so
  the test harness can construct one without tripping
  `UNUserNotificationCenter.requestAuthorization` (raises an
  NSException under xctest — no bundle).

## [1.0.234] — 2026-05-12

### Performance

A four-part hot-path pass, surfaced by a code-review agent sweep. No
user-visible feature changes; everything below is silent under normal
use. Existing 267 tests still pass — no regression coverage added since
the changes are wholly perf and the invariants (data lands on disk,
filter and find still work) are already test-pinned.

- **`SettingsStore.save()` no longer runs per keystroke.** Was: every
  `didSet` on `settings` (so every TextField edit in Setup) fired a full
  `JSONEncoder` + AES-GCM seal + atomic write on the MainActor. Now:
  - `didSet` calls `scheduleSave()` which debounces 400 ms and hands
    the encrypted-envelope write to a detached background `Task`.
    `isEncryptedOnDisk` hops back to MainActor on completion so the
    Security tab stays in sync.
  - `withoutSaving { … }` batch helper folds back-to-back mutations
    (e.g. `deleteTag` writing both `contactTags` and every
    `addressBook[i].tagIDs`) into a single trailing save.
  - `flushPendingSave()` is called from the existing
    `willTerminateNotification` sink in `ChatModel.init`, so a
    mutation made seconds before Cmd-Q still lands synchronously.
  - The synchronous `save()` is preserved for the two explicit
    callers (passphrase setup, keystore reset) that need the
    envelope on disk before continuing — they observe sync write
    behaviour unchanged.
- **`BufferView.renderedRows` is now cached.** Was a computed var that
  re-filtered + re-collapsed up to 5000 lines on *every* body recompute
  — every keystroke in the input field, every hover, every theme tick.
  Now `@State`, invalidated only by `.onChange` of `buffer.lines.count`,
  `bufferIndex`, `effectiveFilter`, and `model.settings.settings
  .collapseJoinPart`. `MessageKindFilter` was already `Equatable`, so
  the filter `.onChange` works without further plumbing.
- **Find bar is debounced.** Was: `recomputeFindMatches()` (a full
  `buffer.lines` scan with mIRC-code strip + lowercase + substring
  search) on every keystroke AND on every new line that arrived while
  the bar was open. Now: a shared 250 ms `findDebounceTask` cancels
  prior work and reschedules — the trailing edge runs once after the
  user stops typing / the channel quiets down. Empty-query path
  bypasses the debounce so clearing the highlight stays instant.
  `closeFind()` cancels the task.
- **`settings.$settings` consumer is debounced 300 ms.** Was:
  `onSettingsChanged()` → `applySettingsToAll()` (which walks every
  connection writing alert flags, log toggles, ignore matchers,
  identity bindings, DCC params, watchlist sound) fired per keystroke.
  Now: 300 ms of quiet before it runs. SwiftUI's `objectWillChange`
  forwarding stays instant (debouncing it would make TextFields lag),
  and the regex-cache invalidation also stays instant since clearing
  is O(1) and stale matches would be wrong.

Notable non-finding: an agent flagged `isFindMatch(_)` as O(n) per row.
It's actually a single index compare against `findMatchIDs[findMatch
Cursor]` — only the cursored match is highlighted, by design — so no
change there.

## [1.0.130] — 2026-05-07

### Added (per-channel + app-wide message-kind filters)

- **Funnel button in every buffer header** opens a popover with a
  checkbox grid: System / info, Errors, MOTD, Notices, Joins, Parts,
  Quits, Nick changes, Topic changes. Toggling a checkbox writes a
  per-buffer override into `AppSettings.messageFiltersByBuffer`,
  keyed by `<network-slug>/<buffer-name-lower>` (case-insensitive),
  and `BufferView.renderedRows` re-runs through
  `MessageKindFilter.includes(_:)` so the suppressed kind disappears
  immediately. The funnel icon switches to its filled variant when
  the active buffer has an override, so the user can see at a glance
  whether they're looking at customized rendering.
- **"Use defaults" / "Save as default"** buttons in the popover.
  The first drops the per-buffer override (back to the app-wide
  defaults); the second promotes the current toggles into
  `AppSettings.messageFilterDefaults` so other un-overridden buffers
  pick them up immediately.
- **Setup → Behavior → "Default message filter"** mirrors the same
  checkbox grid for editing the app-wide defaults directly. A
  "Reset to show everything" button restores the permissive
  baseline; "Clear every per-buffer override" wipes the
  `messageFiltersByBuffer` map in one click.
- **PRIVMSG, ACTION, and RAW always render**, regardless of any
  filter — those are the user's actual chat. Suppressing them
  would feel like data loss; the popover footer flags this so
  nobody goes looking for the missing toggle.
- Forward-compatible decode: a payload missing
  `messageFilterDefaults` / `messageFiltersByBuffer` falls back to
  the permissive baseline, and a `MessageKindFilter` payload missing
  any field defaults each missing toggle to `true` so a category we
  add later doesn't accidentally hide existing lines.

## [1.0.129] — 2026-05-07

### Changed (sidebar reorder is item-level, not section-level)

- **Drag-to-reorder individual rows in every sidebar section.**
  Replaces the section-header reorder shipped in 1.0.128 — that
  was the wrong axis. Now each `ForEach` carries `.onMove`:
  - **Networks**: drag a network row to reorder live connections
    via `ChatModel.moveConnection(from:to:)`. In-memory only;
    next launch re-seeds from the selected profile in
    `settings.servers`.
  - **Channels**: drag a channel buffer; routed through
    `IRCConnection.moveBuffers(kind: .channel, from:to:)`. Other
    buffer kinds (queries, server) keep their underlying
    positions.
  - **Private**: drag a query buffer; `kind: .query` variant of
    the same `moveBuffers` call. Server-console rows below the
    divider are unaffected.
  - **Saved**: drag a saved channel; routed through
    `SettingsStore.moveSavedChannels(from:to:selectedServerID:)`.
    Saved channels scoped to a different server are left where
    they were.
  - **Contacts**: drag an address-book entry;
    `SettingsStore.moveAddressBook(from:to:)`.
- **`Array.moveFiltered(from:to:where:)`** is the shared
  primitive: pull the predicate-matching subset out in order,
  apply standard `Array.move(fromOffsets:toOffset:)`, write back
  to the same underlying indices. Non-matching elements never
  shift.
- **The 1.0.128 section-header reorder is removed** —
  `SidebarSection`, `AppSettings.sidebarSectionOrder`,
  `SettingsStore.moveSidebarSection` and the related tests are
  deleted. A 1.0.128 user upgrading sees their custom section
  order revert to the factory default; the
  `sidebarSectionOrder` key in their `settings.json` is simply
  ignored on decode (Codable's `decodeIfPresent` shape).

## [1.0.128] — 2026-05-07

### Added (sidebar section reordering — superseded by 1.0.129)

- **Drag-to-reorder sidebar sections.** Each of the five sidebar
  groups — Networks, Channels, Private, Saved, Contacts — now has a
  drag-handle on its header (`line.3.horizontal` glyph). Pick up any
  header, drop it on another section's header, and the dragged
  section lands immediately before the drop target. The new order
  persists in `AppSettings.sidebarSectionOrder` and survives
  relaunches.
- **Right-click → "Reset sidebar order"** on any section header
  restores the factory order without having to drag five times.
- **Forward-compatible decode**: an unknown raw value in
  `sidebarSectionOrder` (saved by a future build) is silently
  dropped at decode time; missing entries are appended in
  `SidebarSection.defaultOrder` order. The user's working list
  is never truncated by a partial / pathological payload.

### Changed (Private section starts clean every launch)

- **Server console rows purged at app launch.** The per-network
  `*server*` buffer that accumulates MOTDs / NOTICEs / connection
  diagnostics is removed from every connection at boot via
  `ChatModel.purgeServerBuffersOnLaunch`. The buffer is in-memory
  only — `IRCConnection.ensureServerBufferID` re-creates it the
  moment something needs to log to it — so this is purely
  cosmetic and does not lose any persisted state.

## [1.0.110] — 2026-05-02

### Added (Address Book + Tags — multi-select, auto-naming, duplicate guards)

- **Auto-numbered placeholder names** at create time. The Address Book
  `+` button now seeds new contacts with `New Contact 1`, `New Contact
  2`, … via `AddressEntry.nextDefaultNick(existing:)`, walking the
  list and stopping at the first gap. The Tag Manager `+` button does
  the equivalent with `New Tag 1`, `New Tag 2`, … via
  `ContactTag.nextDefaultName(existing:)`. Both are case-insensitive,
  so the next slot is picked correctly even after a manual rename
  collides with an old default.
- **Duplicate-name guards.**
  - `ContactTag.nameClashes(_:in:excluding:)` and
    `AddressEntry.nickClashes(_:in:excluding:)` power non-blocking
    inline warnings under the name / nickname field in their
    respective editors. The user can keep typing — the warning is
    advisory — but the orange triangle catches accidental duplicates
    the moment they happen.
  - `ContactTagAddPopover.createAndPick` now folds duplicates into
    the existing tag instead of minting a second copy. Type `Friend`
    when there's already a `friend` tag and you get the existing
    tag assigned, not a duplicate.
- **Multi-select + bulk delete.** Both the Address Book contact list
  and the Tag Manager list now use `Set<UUID>` selection so cmd-click
  / shift-click work natively. The `−` button deletes every selected
  row in one pass; the editor pane only renders for single-selection
  (multi-selection shows a "N selected" placeholder so the form is
  never ambiguous about what it's editing). Multi-deletes
  always confirm (tags always confirm regardless of count because
  the deletion cascades across contacts; contacts confirm only when
  N > 1 to preserve the prior 1-click feel for single deletes).
  Both bulk deletes follow the same selection-before-mutation
  discipline as the 1.0.109 crash fix.

## [1.0.109] — 2026-05-02

### Fixed

- **Crash when deleting a tag from "Manage tags…".** The tag editor's
  TextField bindings captured the tag's array index once at body
  computation; when `deleteTag` shrank `contactTags`, a pending
  binding write hit an out-of-range index and crashed the app.
  Replaced every editor binding with id-based safe lookups (returns
  no-op when the tag is gone) and reordered the delete action to
  clear `selection` *before* mutating the array, so the editor
  pane immediately stops referencing the deleted row.
- **Crash when deleting the last address-book entry.** Same root
  cause and same fix in `AddressBookSetup`. The detail pane wrapped
  `AddressEntryEditor` in a `Binding(get:set:)` that captured the
  contact's array index; deleting the last contact (or any contact
  while a TextField had a pending commit) sent the binding's `set`
  out of bounds. Now the binding looks up the row by id every time,
  and the minus button picks the next selection (or `nil` when the
  list is about to be empty) BEFORE calling `removeAddress`.

### Added

- **Per-tag chip color.** `ContactTag.colorHex` (optional `#RRGGBB`)
  joins the existing fields. The Manage Tags editor gains a Color
  section with a "Custom color" toggle and a `ColorPicker` (same
  pattern as `HighlightRuleEditor`) — the live chip rendered next to
  the picker previews the result. Tags without a custom color keep
  the default purple chip everywhere they're rendered. Forward-
  compatible decoder so older settings.json files keep loading.
- **Auto-assigned colors at create time.** Both tag-creation paths
  (Manage Tags `+` and the inline "Create" affordance in the
  per-contact picker) now seed the new tag with the least-used color
  from a 12-entry palette via `ContactTag.nextDefaultColorHex(...)`.
  Purple is first so the very first tag still matches the address
  book's theme color; subsequent tags rotate through blue / green /
  orange / red / pink / teal / amber / brown / indigo / cyan / lime
  before any color is reused. Users can still override via the
  Custom color section.

## [1.0.108] — 2026-05-02

### Added (Address Book — tags + cross-store matches + toolbar shortcut)

- **Contact tags.** New `ContactTag` model (id, name, optional
  description) lives on `AppSettings.contactTags` so it inherits the
  same encrypted-envelope persistence as every other settings field.
  `AddressEntry` gains `tagIDs: [UUID]`; both new fields use a
  forward-compatible decoder so older `settings.json` files keep
  loading. `SettingsStore.upsertTag` / `deleteTag(id:)` are the only
  mutation paths — `deleteTag` cascades through every address-book
  entry and strips the id, so removing a tag never leaves a dangling
  reference behind.
- **Manage tags sheet.** New "Manage tags…" button at the top of
  Setup → Address Book opens a master/detail sheet for adding,
  renaming, editing the description of, and deleting tags. The list
  shows usage counts and the editor surfaces every contact currently
  carrying the selected tag. Delete is confirmation-gated and the
  prompt explains the cascade up front.
- **Per-contact tag picker.** `AddressEntryEditor` gains a Tags
  section with chip rows (remove via the chip's ✕) and an "Add tag…"
  popover that lists every defined tag (already-assigned ones grey
  out) plus an inline "Create" field so users can mint a new tag
  without context-switching. Tag chips also render on the contact
  list rows so users can scan tagged contacts at a glance.
- **Cross-store match panel inside the contact editor.** New
  `ContactMatchesSection` walks every connected network's
  `SeenStore` plus the `LogStore` index for the contact's nick.
  Exact and fuzzy (case-insensitive substring) matches are
  surfaced separately, with action buttons that open the seen log
  on the right network, jump to the chat-log viewer, or open a
  `/query` buffer with the matched nick. The panel reruns whenever
  the user edits the nickname; log lookups are awaited off-actor
  since `LogStore` is an actor.
- **Toolbar shortcut.** New Address Book toolbar button
  (`person.crop.rectangle.stack`) opens Setup straight to the
  Address Book tab via the existing `pendingSetupTab` plumbing — no
  more "Setup → sidebar → Address Book" three-click landing.

## [1.0.103] — 2026-05-01

### Changed (build-app.sh)

- **Real Developer ID signing**, with auto-detection. The script now
  scans `security find-identity -v -p codesigning` for a
  `Developer ID Application:` cert and signs with it when found,
  falling back to ad-hoc (`-`) signing otherwise so the script
  keeps working in CI / on machines without your cert. Override
  via `CODESIGN_IDENTITY=...` (use `-` to force ad-hoc, or pass a
  full common-name to pin a specific cert when multiple are
  installed).
- **`--options runtime --timestamp` added** when a real cert is
  used. Hardened runtime + Apple-issued timestamp are both
  prerequisites for `notarytool submit`; without them Apple
  notary rejects the bundle.
- **Build moved to `/tmp` to dodge iCloud Drive's xattr races.**
  PhantomLives lives under `~/Documents` which is iCloud-synced;
  iCloud re-attaches `com.apple.FinderInfo` to fresh files at
  unpredictable moments, and `codesign --strict` refuses to sign
  or verify any bundle carrying that xattr. Assembly + sign +
  verify all happen in `mktemp -d` (which iCloud doesn't watch),
  then `ditto --noextattr` copies the finished bundle back into
  the project directory. The signature is embedded in the bundle
  contents so iCloud's eventual FinderInfo reattach in the
  project-dir copy doesn't disturb it.
- **xattr cleanup expanded** — explicit `xattr -d` calls for
  `com.apple.FinderInfo`, `com.apple.fileprovider.fpfs#P`,
  `com.apple.provenance`, and `com.apple.quarantine` in addition
  to the recursive `xattr -cr` clear, so any one of them
  surviving the recursive sweep can't block the sign.
- **Verify step uses exit code, not output parsing.** Previous
  `tail -1 | grep "valid on disk"` was looking at the second
  line of `codesign --verify --verbose=2` output ("satisfies
  its Designated Requirement"), so the check always reported
  failure even on success. Now uses `codesign`'s exit code
  directly, with the failure log captured to `/tmp/codesign-
  verify.log` for diagnostic.

## [1.0.102] — 2026-05-01

### Tests

- **+58 tests across 4 new suites** — covers the components added in
  Phases 1-8 (UserTheme, BlobStore, FontStyle, PhotoUtilities). Total
  now 222 tests across 16 suites.
- **`UserThemeTests` (16 tests)** — `duplicate(of:name:)` snapshots
  every color slot and produces a fresh UUID; `materialised`
  tolerates missing palette slots, oversized palettes, and garbage
  hex values; `kindOverridesMaterialised` parses good entries and
  drops bad keys / values; `Theme.resolve(id:userThemes:)` lets
  built-ins win on id collision and falls back to `.classic` on
  miss; UserTheme round-trips through JSON; ChatLineKindTag
  rawValues are pinned (renaming any of the 14 tags would break
  every existing user theme on disk).
- **`BlobStoreTests` (10 tests)** — store + read round-trip for
  both plaintext and AES-GCM-sealed payloads; `delete` is
  idempotent and removes both file + index row; `writeToTempFile`
  produces a readable file with the right name; index survives
  across BlobStore instances pointed at the same dir; encrypted
  index loads empty without a key, then re-loads when the key
  arrives via `setEncryptionKey`; `allRecords` sorts newest first;
  `store(fileURL:)` auto-guesses MIME from the file extension.
- **`FontStyleTests` (16 tests)** — root resolution from legacy
  fields produces the right family/size/weight; built-in tokens
  (`system-mono`, `system-proportional`) flag correctly;
  FontStyle fields override legacy fields when set, and inherit
  when at the sentinel; slot inheritance from the chat-body
  parent leaves unset fields untouched; partial overrides only
  affect the set fields; FontStyle round-trips through JSON;
  Weight rawValues are pinned (saved per-element fonts would
  break otherwise).
- **`PhotoUtilitiesTests` (16 tests)** — `initials(for:)` picks
  the first alphanumeric (uppercased), skips leading non-letters,
  falls back to "?" for empty / punctuation-only nicks;
  `avatarTint(for:)` is deterministic and case-insensitive across
  calls (compared by sRGB component triplet — SwiftUI Color
  equality returns identity for catalog wrappers, not value
  equality), and produces visibly distinct colors across 10
  arbitrary nicks; `downscale` is a no-op for already-small
  images, preserves aspect ratio for both landscape and portrait,
  handles zero-sized images gracefully; `downscaleAndEncode`
  produces a decodable JPEG with dimensions ≤ 256 px;
  `loadDownscaled(from:)` returns nil for missing or
  non-image files.

### Notes

`UserThemeTests`, `FontStyleTests`, and `BlobStoreTests` exercise
shaped fields whose stability is part of the on-disk file format.
Renaming any of those rawValues / property names will surface as
test breakage, which is the intended early-warning signal.

## [1.0.101] — 2026-05-01

### Added (Phase 8 — Visual polish)

- **Animated network state dot** in the sidebar Networks section.
  Pulses (1.0× ↔ 1.3× scale) while the connection is in
  `.connecting`. A soft blurred halo glows behind the dot while
  `.connected`. Both effects suppressed under
  `accessibilityReduceMotion` so motion-sensitive users still get
  the static colour cue without the animation.
- **Hover halo on chat rows** — `MessageRow` gains a 4% primary
  overlay when hovering, layered above the existing
  highlight/mention/watch-hit background so loud rows still take
  precedence. Suppressed under reduce-motion.
- **Density-aware row padding wired in** — `MessageRow` now reads
  `chatDensity.rowPadding / 2` as the vertical padding baseline,
  with the existing `relaxedRowSpacing` toggle stacking on top so
  accessibility-conscious users can combine both. Compact ≈ 0.5 pt,
  Cozy ≈ 1.5 pt, Comfortable ≈ 3 pt.
- **Subtle gradient on the buffer header title** —
  `LinearGradient(.primary → .primary.opacity(0.7))` from top to
  bottom. Adds depth without compromising legibility on either
  light or dark themes.

### Changed

- `MessageRow` now consumes `Environment(\.accessibilityReduceMotion)`
  in two places (hover halo, animation). When new visual effects
  land, follow the same pattern.

## [1.0.100] — 2026-05-01

### Added (Phase 7 — Encrypted blob attachment store)

- **`BlobStore` actor (new file)** — encrypted file-attachment
  storage at `<supportDir>/blobs/<uuid>.bin`. Each payload sealed
  via the keystore-derived DEK through `EncryptedJSON.safeWrite`;
  metadata index at `blobs/index.json`. Mirrors the LogStore
  pattern (single off-main actor, set-key push, encrypted
  envelope). Init inlines the index load — calling actor-isolated
  `loadIndex()` from init triggers a Swift 6 isolation
  diagnostic.
- **`BlobStore.BlobRecord`** — Codable on-disk metadata (id,
  filename, contentType, sizeBytes, createdAt, attachedTo).
- **`BlobStore.AttachmentRef`** — lightweight (id, filename,
  contentType, sizeBytes) inlined on owners (`AddressEntry
  .attachments` today; future channels / messages later) so the
  editor renders lists without round-tripping through the store.
  The store is the source of truth for the bytes; inline refs
  are a denormalised view.
- **API surface**: `store(data:filename:contentType:attachedTo:)`,
  `store(fileURL:attachedTo:)` (auto-guesses MIME via UTType),
  `read(_:)`, `delete(_:)`, `writeToTempFile(_:)` (materialises
  to `~/tmp/PurpleIRC-blobs/` for Open / Reveal handoffs to
  NSWorkspace), `setEncryptionKey(_:)` (reloads index when
  key transitions).
- **Why a separate store rather than inline like profile photos?**
  Photos are tiny (~10 KB). Documents are routinely 5+ MB.
  Inlining 5 MB of base64 in `settings.json` forces every save
  to rewrite the whole encrypted envelope and every load to
  decrypt it. The blob store keeps `settings.json` small —
  only the metadata lives there — and pays the encrypt /
  decrypt cost only when the user opens the attachment.
- **`AddressEntry.attachments`** — new array; `decodeIfPresent`
  for backward compat.
- **`ChatModel.blobStore: BlobStore`** — initialised against the
  support directory; receives keystore-key pushes via the same
  `pushKeyToLogStore` path that feeds the seen / session-history /
  bot stores.
- **AddressEntryEditor → new "Attachments" section** between
  Contact and Notes:
  - "Attach file…" button (NSOpenPanel, multi-select, no type
    filter — any file is fair game).
  - Drop target accepting file URLs from Finder, routed through
    the same store path.
  - **`AttachmentRow`** view: SF Symbol icon resolved from MIME
    prefix (`image/*` → photo, `video/*` → film, `audio/*` →
    music.note, `text/*` → doc.text, `pdf` → doc.richtext, `zip`
    → archivebox, `json`/`xml` → curlybraces, otherwise → doc),
    filename + contentType + ByteCountFormatter size, three
    buttons: Open (NSWorkspace.open via temp file), Reveal
    (Finder reveal via temp file), Remove (drops both the inline
    ref AND the blob-store payload).
- **`/nuke` already covered** — `NukeService.wipeSupportDirectory`
  enumerated `blobs/` in its subtree list back in Phase 1
  (forward-compat), so attachments wipe cleanly with no
  NukeService change this round.

## [1.0.99] — 2026-05-01

### Added (Phase 6 — Address book profile photos)

- **`AddressEntry.photoData: Data?`** — optional inline JPEG bytes,
  decoded with `decodeIfPresent` for backward compat. Storage round-
  trips through the existing encrypted-settings envelope, so photos
  inherit the keystore-derived AES-GCM seal alongside contact notes.
- **`PhotoUtilities` module (new file)** — downscaling pipeline
  (`maxDimension = 256` px on the longest side, JPEG re-encode at
  quality 0.85), `loadDownscaled(from:)` / `downscaleAndEncode(_:)`
  helpers, `initials(for:)` (first alphanumeric, uppercased, "?"
  fallback), and `avatarTint(for:)` (deterministic Color from
  SHA-256 hash of the lowercased nick → palette of 11) so the
  same nick always lands on the same swatch.
- **`ContactAvatar` view** — single configuration knob (`size` in
  points). Renders the entry's photo when present (Image
  scaledToFill + Circle clip) or a tinted-gradient circle with
  the deterministic initial. Initials font auto-scales at ~46% of
  size; 0.5 px outer stroke at primary.opacity(0.08) for definition
  against any background.
- **`ContactAvatarByNick`** — convenience wrapper that resolves a
  nick against `settings.addressBook` (case-insensitive). When no
  match exists, synthesises an empty entry so the placeholder
  still renders the deterministic tint + initial. Nicks not yet
  in the address book share the visual identity.
- **AddressEntryEditor → new Photo section at top:** 72-pt avatar
  preview, "Choose photo…" button (NSOpenPanel filtered to `.image`),
  Remove button when one is set, plus a drop target accepting both
  `.image` (raw bitmap from another app) and `.fileURL` (Finder
  drag) — both resolve through PhotoUtilities so the inline
  storage invariant holds regardless of source.
- **Sidebar Contacts row** now leads with a 22-pt `ContactAvatar`
  overlaid with the existing presence dot in the bottom-right
  corner (haloed with a 1.5 px stroke against the control
  background so the dot reads against any avatar tint). Identity
  + presence both visible without enlarging the row.

## [1.0.98] — 2026-05-01

### Added (Phase 5 — Fonts: per-element slots + advanced typography)

- **`FontStyle` data model** (new file `FontStyle.swift`) — sparse
  Codable container with "inherit" sentinels on every field
  (empty `family`, zero `size`, `.inherit` weight, nil `italic` /
  `ligatures` / `tracking` / `lineHeightMultiple`). Walks an
  inheritance chain so a slot can override only what it cares about
  while everything else falls back to its parent.
- **`ResolvedFont`** — materialised concrete-value bag the renderer
  reads (family, size, weight, italic, ligaturesEnabled, tracking,
  lineHeightMultiple, plus `isBuiltInMonoToken` / `isBuiltInPropToken`
  flags so the SwiftUI Font factory routes to `.system(...)` vs
  `.custom(...)` correctly).
- **Four `FontSlot`s** on `AppSettings` — `chatBodyFont`, `nickFont`,
  `timestampFont`, `systemLineFont`, all defaulting to pure inherit
  so old `settings.json` files render unchanged. The chat-body slot
  inherits from the legacy `chatFontFamily` / `chatFontSize` /
  `boldChatText` fields.
- **`ChatModel.font(for: FontSlot) -> ResolvedFont`** — single resolver
  every renderer reads. `chatFont` now goes through it; `chatCaptionFont`
  honours the system-line slot and recomposes at 78% the slot's
  configured size.
- **`View.purpleFont(_:)` modifier** — applies SwiftUI Font + tracking
  + lineSpacing in one call so call sites don't reimplement the
  `(multiplier - 1.0) * size` line-spacing math.
- **`purpleText(_:_:)` helper** — wraps a string in an
  `AttributedString` with `.ligature = 0` when the resolved font has
  ligatures off, since SwiftUI's `Text` doesn't expose a ligature
  toggle on macOS.
- **`InstalledFonts` cache** — `NSFontManager.shared.availableFontFamilies`
  fetched once at first use, plus a monospaced-only subset filtered
  via `NSFontManager.traits(of:).contains(.fixedPitchFontMask)`.
- **`FontFamilyPickerSheet`** — searchable list of every installed
  family (~500 on a typical Mac), with a "Monospaced only" toggle
  (defaults ON when picking for the chat body). Each row renders the
  family name + "AaBb 123" sample in that family so users pick by
  visual feedback rather than guessing from PostScript names.
- **Fonts tab rebuilt** — three sections:
  - **Chat font (root)**: legacy enum picker + "Pick installed font…"
    button that overrides the enum at resolve time, plus a "Clear"
    affordance to drop back. Size slider, bold toggle, /font slash-
    command pointer.
  - **Chat body — advanced**: ligatures, tracking (-2 → +4 pt),
    line-height (0.8× → 2.0×), weight, italic.
  - **Per-element overrides**: collapsible DisclosureGroups for Nick /
    Timestamp / System-line slots. Each has its own family picker,
    size slider with an "inherit" sentinel at 0 pt, weight, italic,
    ligatures, tracking, and line-height. Everything inherits from
    the chat body unless overridden.

## [1.0.97] — 2026-05-01

### Added (Phase 4 — Theme system: UserTheme + per-event colors + WYSIWYG builder)

- **`UserTheme` model** in `SoundsAndThemes.swift` — Codable struct
  mirroring `Theme`'s shape with hex strings for every color slot,
  plus a sparse `kindOverrideHex: [String: String]` map keyed by
  `ChatLineKindTag.rawValue` for per-event overrides. `materialised`
  produces a runtime `Theme`; `kindOverridesMaterialised` produces
  the typed `[Tag: Color]` dict. `UserTheme.duplicate(of:name:)`
  snapshots a built-in or user theme as the starting point.
- **`ChatLineKindTag` enum** — 14 stable string tags (info, error,
  privmsg, privmsgSelf, action, notice, join, part, quit, nick,
  topic, raw, mention, watchlist) so per-event overrides survive
  Codable round-trips and rename-resilient over time.
- **`Theme.resolve(id:userThemes:)`** — built-ins win on id collision,
  then user themes by uuid, then `.classic` fallback.
- **`AppSettings.userThemes: [UserTheme]`** — persisted alongside
  `themeID`.
- **`ServerProfile.themeOverrideID: String?`** — per-network theme
  override, decoded with `decodeIfPresent` so old `settings.json`
  files don't fail.
- **`ChatModel.theme`** rewritten to consult
  `activeConnection.profile.themeOverrideID` first, then
  `settings.themeID`, both via the resolver.
- **`ChatModel.kindColor(for:)`** — overlay lookup; nil means
  "inherit", letting MessageRow fall back to the typed slot
  (`infoColor`, `joinColor`, etc.).
- **MessageRow rewired** — every kind (info, error, privmsg, action,
  notice, join, part, quit, nick, topic, raw, motd) reads
  `model.kindColor(for: tag) ?? theme.someColor`, so a UserTheme
  paints each event independently.
- **`ThemeBuilderView` (new file)** — WYSIWYG sheet with HSplitView:
  editor on the left (Theme name; Surface bg/fg; Per-event base
  palette; Backgrounds; 8-slot Nick palette; Per-event color
  overrides with + to add and ↺ to drop), live preview on the
  right (15 sample rows covering every kind a UserTheme can
  repaint, painted against the draft's `chatBackground` /
  `chatForeground`). Save / Save As / Delete / Export to
  `.purpletheme` JSON via `NSSavePanel`.
- **`ThemeImporter.importTheme(from:into:)`** — reads a `.purpletheme`
  file, decodes UserTheme, fresh-stamps UUID + createdAt so multiple
  imports don't collide, appends to `settings.userThemes`.
- **Themes tab rebuilt** — new "Custom themes" section above the
  built-in grids: per-row swatch tile, name + basedOn caption,
  Use / Edit / Duplicate / Delete affordances. Plus "+ New theme"
  (snapshots active theme and opens the builder) and "Import…"
  (NSOpenPanel → ThemeImporter).
- **ServerEditor → Theme override picker** — "Use global theme"
  sentinel, divided list of built-ins and user themes, persisted via
  `themeOverrideID`.
- **`/theme` command refactored** into a real subcommand parser:
  - `/theme` — list built-ins + user themes + show current
  - `/theme <id-or-name>` — switch (handles uuid prefix matching)
  - `/theme builder` (also `edit`, `new`) — open the WYSIWYG sheet
  - `/theme import <path>` — load a `.purpletheme` file
  - `/theme export <user-theme-name-or-id> <path>` — write to disk
- **`ChatModel.themeBuilderDraft` + `themeBuilderIsNew`** —
  `@Published` state surfaced by ContentView via
  `.sheet(item: $model.themeBuilderDraft)` so the slash command and
  the Setup tab share one presentation path.

## [1.0.96] — 2026-05-01

### Documentation

Captured Phases 1–3 in CHANGELOG / HANDOFF / README. No code change.

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
