# PurpleIRC architecture (the largest subproject)

`PurpleIRC/HANDOFF.md` is the canonical architecture snapshot — read it before non-trivial changes. Quick mental model:

- **`ChatModel`** (`@MainActor`) — top-level store; holds the connection list and shared services (`WatchlistService`, `SettingsStore`, `LogStore`, `BotHost`, `BotEngine`, `KeyStore`, `DCCService`, `SessionHistoryStore`).
- **`IRCConnection`** — one per network. Owns an `IRCClient`, buffers, reconnect state, and a per-connection event subject.
- **`IRCClient`** — RFC 1459 parsing + `NWConnection` transport; SASL (PLAIN/EXTERNAL) and IRCv3 CAP negotiation live here. `ProxyFramer` plugs in at the bottom of the protocol stack.
- **Event fan-out** — every line / state change flows through the `Sendable` `IRCConnectionEvent` enum. `ChatModel.events` merges all connections (UUID-tagged) and is what bots, watchlist, and the assistant subscribe to.
- **Persistence** — `EncryptedJSON` + `KeyStore` wrap a passphrase-derived KEK around a per-install DEK; AES-256-GCM seals every persistence file. Settings live at `~/Library/Application Support/PurpleIRC/`.
- **`build-app.sh`** derives `CFBundleShortVersionString` from git (`1.0.<commit-count>`) and `CFBundleVersion` from `<count>.<short-sha>`. Version-bump rule #1 is satisfied automatically by committing — no manual edit needed for the bundle version.

The app **must** be launched from the `.app` bundle for SwiftUI's `WindowGroup`, `UNUserNotificationCenter` authorization, and the AppleScript dictionary to work; `swift run` alone won't fully activate the UI.
