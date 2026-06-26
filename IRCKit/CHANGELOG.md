# Changelog

All notable changes to IRCKit are documented here.

## 0.4.0 — 2026-06-25

### Fixed

- **`IRCClient` data race (use-after-free + value-type heap corruption).**
  `IRCClient` ran its `NWConnection` on a private serial queue but exposed a
  synchronous API the `@MainActor` session layers call from the main thread, so
  its mutable connection state (`connection`, `buffer`, `negotiator`,
  `pendingConfig`, `didBecomeReady`) was read/written from **two threads with no
  synchronization**. The sharp edges: `send()` read `connection` on the hot
  PONG path while the queue could nil it on `.failed`/`.cancelled`/timeout
  (torn reference → use-after-free), and `buffer` (a `Data` value) was
  appended/drained on the queue while `disconnect()` did `removeAll()` on main
  (concurrent value-type mutation → heap corruption) — both firing exactly
  during connect/disconnect/reconnect, i.e. **sporadic, timing-dependent
  crashes on any hardware**. Fixed by **confining all connection state to the
  serial queue**: `connect`/`send` dispatch via `queue.async`; `disconnect` and
  the `host`/`port`/`useTLS`/`enabledCaps`/`serverCapValues` getters read via
  `queue.sync`. The **public API stays synchronous**, so PurpleIRC and Ircle
  need no changes. `disconnect()` deliberately stays synchronous and still
  flushes a best-effort QUIT (≤1s) before closing — the wait now runs on the
  *caller* thread (never on the queue), so it can't deadlock against the send
  completion (which replaces the old `sendSync` semaphore). A per-connection
  `epoch` token makes a superseded socket's late callbacks no-ops, also fixing a
  latent bug where an old connection's `.cancelled` could nil the new one.
  `IRCClient` is now `@unchecked Sendable`. Proven with a new ThreadSanitizer
  loopback harness (`IRCClientLoopbackTests`): **7 races before → 0 after**.

### Added

- **`IRCClientLoopbackTests`** — a loopback `NWListener` harness that drives
  connect/send/disconnect/reconnect (functional reconnect coverage, previously
  none), doubling as the TSan target for the race above
  (`IRCKIT_STRESS=1 swift test --sanitize=thread --filter IRCClientLoopbackTests`).

## 0.3.0 — 2026-06-19

### Added

- **`DCC` pure engine** — the single audited copy of DCC's security-critical
  logic, shared by every PhantomLives IRC app: `parseOffer` (CTCP DCC
  SEND/CHAT → validated `Offer`), `sanitizeFilename` (path-traversal guard),
  `validatedPeerHost` (SSRF guard — only routable IP literals; rejects
  hostnames/loopback/unspecified/link-local; allows RFC1918), `isSafeIPv4`,
  `ipv4StringToInt`. No sockets/UI — transport + orchestration live in the app.
  12 tests ported from PurpleIRC's DCCSecurityTests + offer-parse/sanitize cases.
  (PurpleIRC keeps its own DCCService copy for now; converge later.)
- **`DCCDownload`** — the DCC GET/accept transport: connects out to a vetted
  peer, streams to a destination URL, sends 4-byte big-endian acks, and stops at
  the advertised size (no over-write). Pure Network+Foundation; no listening.
- **`DCCChat`** — the DCC CHAT accept transport: connect-out, newline-framed
  line exchange. Pure Network; no listening.
- **DCC initiate support**: `DCCChat.listen(bindHost:)` (hardened port-range
  bind + wildcard-fallback flag), `DCC.primaryIPv4()` (advertised address), and
  `DCC.chatOfferCommand`/`sendOfferCommand` offer encoders.
- **`DCCUpload`** — the DCC SEND/offer transport: listen on a vetted port,
  accept the peer, stream the file with backpressure, drain acks. Pure Network.
- **`IRCMask`** — IRC hostmask glob matching (`*`/`?`, case-insensitive; bare
  nick → `<nick>!*@*`) for ignore lists. 6 tests.

## 0.2.0 — 2026-06-18

### Changed

- `IRCClient` now has a **connect timeout** (`connectTimeoutSeconds`, default
  20s): if the connection never reaches `.ready`, it fails with an actionable
  message naming the host/port and suggesting a TLS/port check, then cancels —
  instead of hanging.
- `.waiting` (NWConnection's transient "can't reach the endpoint yet, retrying"
  state) is no longer surfaced as a hard `.failed`. It stays `.connecting` and
  leaves a breadcrumb via `onRaw`, letting the connection recover on its own;
  the connect timeout provides the definitive failure. (Previously this showed
  alarming "Waiting: … timed out" errors mid-connect.)

## 0.1.0 — 2026-06-18

Initial release. Extracted the UI-independent IRC wire engine from PurpleIRC
into a standalone SwiftPM library so it can be shared with the new **Ircle**
nostalgic client (and any future PhantomLives IRC app).

### Added

- `IRCMessage` + `IRCSanitize` — RFC 1459 / IRCv3 line parser and CR/LF/NUL
  field/line sanitization + credential masking. Now `public`; `IRCMessage` is
  `Sendable`.
- `IRCClient` — `NWConnection`-backed transport with `onMessage`/`onState`/
  `onRaw` callbacks, TLS-error humanization, and SASL drive-through.
- `IRCConnectionConfig` (with a public memberwise init) and
  `IRCConnectionState` (`Sendable`).
- `SASLMechanism` — relocated from PurpleIRC's settings layer, since it's part
  of the wire contract (`IRCConnectionConfig` + the SASL negotiator depend on
  it).
- `IRCConnectionEvent` — the `Sendable` connection-event vocabulary a session
  layer subscribes to. Relocated so every app speaks the same events.
- `ProxyType` (public) plus the internal SOCKS5 / HTTP-CONNECT
  `ProxyFramer` + `ProxyConfig`, driven by `IRCClient`.
- `IRCText.stripFormatting` — **new**, Foundation-only mIRC formatting-code
  stripper for logs / matching / notifications (the engine-side counterpart to
  an app's `AttributedString` renderer). Covered by a new test suite.

### Notes

- `SASLNegotiator` and `ProxyFramer` are module-internal; the test target
  reaches them via `@testable import`.
- 72 tests (message parser, sanitizer/masker, SASL state machine, formatting
  stripper) — ported verbatim from PurpleIRC where they previously lived.
