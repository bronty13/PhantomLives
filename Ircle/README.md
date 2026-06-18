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
  highlighting.
- **Topic bar** — the channel topic, in an inset Platinum well.
- **Message area** — monospaced (Monaco), colored by line kind the way Ircle
  did: blue server/MOTD text, purple topics/actions, green joins, etc.
- **Nick list** — the right-hand "*N* users" roster with mode prefixes and a
  row of action buttons (Query / Whois / Op / DeOp).
- **Input line** — formatting buttons (B/I/U), a "talking to …" status, and
  the field. Return sends; `/commands` supported.
- **Status bar** — connection state, your nick, the server.

Two themes: **Platinum** (classic Mac OS 8/9 light grey, the default) and
**Graphite** (a modern dark variant). Toggle in Settings → Appearance.

## Features

- TLS, SASL (PLAIN / EXTERNAL), server password, and SOCKS5 / HTTP-CONNECT
  proxies — all via IRCKit's IRCv3-aware engine (CAP negotiation, `server-time`,
  `echo-message`, `account-tag`, …).
- Channels, queries, auto-join, nick list with op/voice ranking, topic
  tracking, CTCP (VERSION/PING/TIME + `/me` actions), PING/PONG keepalive.
- Slash commands: `/join /part /msg /query /me /nick /topic /whois /quit /raw`
  (anything else is passed through to the server).
- Auto-backup-on-launch of your settings (server profiles, credentials,
  appearance) — `~/Downloads/Ircle backup/`, 14-day retention. Full
  Settings → Backup UI (run now, test, restore, reveal).

## Build / run / test

```sh
./build-app.sh        # release → Ircle.app → /Applications → relaunch (+verify fresh)
./build-app.sh --no-install   # build only
./run-tests.sh        # swift-testing (18 tests: backup, buffers, session plumbing)
swift build           # debug build
```

Requires macOS 14+, Swift 5.9+. Ircle depends on the sibling `../IRCKit`
package (a local SwiftPM path dependency).

## Default locations

- Settings / config: `~/Library/Application Support/Ircle/settings.json`
- Backups: `~/Downloads/Ircle backup/`
- User-visible output (logs, future DCC): `~/Downloads/Ircle/`

## Status & roadmap

MVP: connect, join, chat, queries, nick list, the Platinum/Graphite themes,
backup. Planned: mIRC color *rendering* in the message area (codes are stripped
to plain text today), the Faces window (per-user avatars), a multi-server
Connections manager, Keychain-backed credentials, optional Sparkle
auto-update, and AppleScript.

## Naming

"Ircle" is an existing (discontinued, 2009) product name; this is a personal
nostalgic recreation kept inside the PhantomLives monorepo. Flag before any
public distribution.
