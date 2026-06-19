# Changelog

All notable changes to IRCKit are documented here.

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
