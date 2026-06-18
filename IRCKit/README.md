# IRCKit

The UI-independent IRC **wire engine** shared by the PhantomLives IRC apps —
**PurpleIRC** and **Ircle**. Pure `Foundation` + `Network`: no SwiftUI, no
AppKit. One battle-tested protocol layer, two faces.

## What's in it

| Type | Role |
|---|---|
| `IRCMessage` | RFC 1459 / IRCv3 line parser (tags, prefix, command, params; `serverTime`, `account`, `msgID`, `batchRef`). |
| `IRCSanitize` | CR/LF/NUL field + line scrubbing, and credential masking for logs/display. |
| `IRCClient` | Owns the `NWConnection`; connect / disconnect / send; callback fan-out (`onMessage` / `onState` / `onRaw`). TLS-error humanization. |
| `IRCConnectionConfig`, `IRCConnectionState` | Connection inputs and lifecycle states. |
| `SASLMechanism` | `NONE` / `PLAIN` / `EXTERNAL`. |
| `IRCConnectionEvent` | `Sendable` event vocabulary a session layer subscribes to. |
| `IRCText` | Foundation-only mIRC formatting-code stripper (`stripFormatting`) for logs / matching / notifications. |
| `ProxyType` | `NONE` / `SOCKS5` / `HTTP` (the SOCKS5 / HTTP-CONNECT framer is internal; configure via `IRCConnectionConfig`). |

`SASLNegotiator` (CAP + SASL state machine) and `ProxyFramer` (the
`NWProtocolFramer`) are module-internal implementation details driven by
`IRCClient`; the test target reaches them via `@testable import`.

## What's NOT in it

By design, IRCKit is the *wire* layer only. It does **not** model channels,
buffers, nick lists, logging, watchlists, or rendering — those are app
concerns. Each app builds its own session layer on top:

- PurpleIRC: `IRCConnection` (rich, `@MainActor ObservableObject`).
- Ircle: `IrcleSession` (purpose-built for the nostalgic UI).

## Usage

```swift
import IRCKit

let client = IRCClient()
client.onState   = { state in print("state:", state) }
client.onMessage = { msg in print("recv:", msg.command, msg.params) }
client.onRaw     = { line, outbound in print(outbound ? ">>" : "<<", line) }

client.connect(config: IRCConnectionConfig(
    host: "irc.libera.chat", port: 6697, useTLS: true,
    nick: "ircle-user", user: "ircle", realName: "Ircle",
    saslMechanism: .plain, saslAccount: "ircle-user", saslPassword: "••••••"
))
// … later
client.send("JOIN #ircle")
```

`IRCClient` callbacks fire on its internal dispatch queue — hop to your own
actor / main thread before touching UI state.

## Build & test

```sh
swift build
./run-tests.sh      # swift-testing; wrapper adds Testing.framework rpath for CLT setups
```

72 tests across the message parser, sanitizer/masker, SASL state machine, and
the formatting stripper.

## Consuming it

Both apps depend on it as a local path package:

```swift
// Package.swift
dependencies: [ .package(path: "../IRCKit") ],
```

It lives inside the `PhantomLives` monorepo at the repo root (sibling of
`PurpleIRC/` and `Ircle/`).
