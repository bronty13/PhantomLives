# Changelog

All notable changes to IRCKit are documented here.

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
