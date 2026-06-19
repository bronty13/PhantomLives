# Ircle

A **nostalgic recreation** of the classic Mac OS *Ircle* IRC client, rebuilt
for current macOS — Platinum chrome, modern comfort. Native SwiftUI, built on
the shared **[IRCKit](../IRCKit)** wire engine.

> **Not a port.** The iconic Ircle 3.x (Onno Tijdgat) is closed-source; only
> Olaf Titz's 1993 THINK Pascal ≤1.56 was ever GPL, and it's uncompilable on
> modern macOS. Ircle is a **clean-room** recreation of the *look and feel*
> from observation — no GPL Pascal lifted, no proprietary art/fonts/resources
> copied. It uses macOS's own Monaco/Geneva fonts for the period feel.

## What it looks like

The classic single-window arrangement, consolidated and resizable:

- **Channelbar** — the signature horizontal strip of beveled buffer buttons
  (server console, channels `#`, queries `@`), with unread badges and mention
  highlighting. With **multiple servers** connected, buffers are grouped by
  network with a divider between them.
- **Topic bar** — the channel topic, in an inset Platinum well.
- **Message area** — monospaced (Monaco), colored by line kind the way Ircle
  did: blue server/MOTD text, purple topics/actions, green joins, etc. Message
  bodies render **mIRC formatting** — bold/italic/underline/strikethrough, the
  16-color palette, and IRCv3 hex colors.
- **Faces window** — a separate window with a grid of per-user avatars
  (assigned image or generated monogram), opened with ⌘⇧F / the Window menu /
  the nick-list "Faces" button. Small avatars also show beside names in the
  nick list.
- **Nick list** — the right-hand "*N* users" roster with mode prefixes and a
  row of action buttons (Query / Whois / Op / DeOp).
- **Input line** — formatting buttons (B/I/U), a "talking to …" status, and
  the field. Return sends; `/commands` supported.
- **Status bar** — connection state, your nick, the server.

Two themes: **Platinum** (classic Mac OS 8/9 light grey, the default) and
**Graphite** (a modern dark variant). Toggle in Settings → Appearance.

## Features

- **Multiple servers at once** — each network is its own session; manage saved
  servers in Settings → Servers, connect from the Servers menu. Ships a built-in
  list of common networks (Libera, OFTC, Undernet, DALnet, Rizon, …) with
  network-correct TLS defaults; "Add Common Servers" pulls in any you're missing.
- TLS, SASL (PLAIN / EXTERNAL), server password, and SOCKS5 / HTTP-CONNECT
  proxies — all via IRCKit's IRCv3-aware engine (CAP negotiation, `server-time`,
  `echo-message`, `account-tag`, …).
- Channels, queries, auto-join, nick list with op/voice ranking, topic
  tracking, CTCP (VERSION/PING/TIME + `/me` actions), PING/PONG keepalive.
- mIRC formatting rendering (colors, bold/italic/underline/strike, hex colors).
- Slash commands: `/join /part /msg /query /me /nick /topic /whois /quit /raw`
  (anything else is passed through to the server).
- **AppleScript** — `connect`, `join channel "#x"`, `say "…" [to "#x"|"nick"]`,
  `current nickname` (e.g. `tell application "Ircle" to say "hi" to "#ircle"`).
- **Passwords stored in the macOS Keychain** (device-only), never in
  `settings.json`; legacy plaintext is migrated out automatically.
- Auto-backup-on-launch of your settings (server profiles, appearance) —
  `~/Downloads/Ircle backup/`, 14-day retention. Full Settings → Backup UI
  (run now, test, restore, reveal). (Passwords live in the Keychain, so they're
  not in the backup zip.)

## Build / run / test

```sh
./build-app.sh        # release → Ircle.app → /Applications → relaunch (+verify fresh)
./build-app.sh --no-install   # build only
./run-tests.sh        # swift-testing (59 tests: backup, buffers, dispatch, mIRC, faces, multi-server, presets, credentials)
swift build           # debug build
```

Requires macOS 14+, Swift 5.9+. Ircle depends on the sibling `../IRCKit`
package (a local SwiftPM path dependency).

## Default locations

- Settings / config: `~/Library/Application Support/Ircle/settings.json`
- Backups: `~/Downloads/Ircle backup/`
- User-visible output (logs, future DCC): `~/Downloads/Ircle/`

## Status & roadmap

Working: connect, multiple servers at once, join, chat, queries, nick list,
mIRC color/formatting rendering, the Faces window (per-user avatars), the
Platinum/Graphite themes, Keychain-backed passwords, AppleScript, Sparkle
auto-update, backup. See `RELEASING.md` for cutting a release.

## Naming

"Ircle" is an existing (discontinued, 2009) product name; this is a personal
nostalgic recreation kept inside the PhantomLives monorepo. Flag before any
public distribution.
