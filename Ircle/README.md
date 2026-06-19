# Ircle

A **nostalgic recreation** of the classic Mac OS *Ircle* IRC client, rebuilt
for current macOS — Platinum chrome, modern comfort. Native SwiftUI, built on
the shared **[IRCKit](../IRCKit)** wire engine.

> **Not a port.** The iconic Ircle 3.x (Onno Tijdgat) is closed-source; only
> Olaf Titz's 1993 THINK Pascal ≤1.56 was ever GPL, and it's uncompilable on
> modern macOS. Ircle is a **clean-room** recreation of the *look and feel*
> from observation — no GPL Pascal lifted, no proprietary art/fonts/resources
> copied. It uses macOS's own Monaco/Geneva fonts for the period feel.

A full **in-app manual** (Help → Ircle Manual, ⌘?) covers usage, the command
reference, troubleshooting, and the history/research behind the app; it ships as
[`Resources/Manual.md`](Resources/Manual.md).

## What it looks like

The classic single-window arrangement, consolidated and resizable:

- **Channelbar** — the signature horizontal strip of beveled buffer buttons
  (server console, channels `#`, queries `@`), with unread badges and mention
  highlighting. With **multiple servers** connected, buffers are grouped by
  network.
- **Topic bar** — the channel topic, in an inset Platinum well.
- **Message area** — monospaced (Monaco), colored by line kind; bodies render
  **mIRC formatting** (bold/italic/underline/strikethrough, the 16-color palette,
  hex colors), kept legible against the background, with **clickable links**.
- **Nick list** — the right-hand roster with mode prefixes, avatars, and
  WHO-derived **hostnames** (hover) + **IRCop** markers; right-click for Query /
  Whois / DCC / Ignore.
- **Faces window** — per-user avatars (assigned image or generated monogram),
  ⌘⇧F.
- **Input line** + **status bar**.

Two themes — **Platinum** (light, default) and **Graphite** (dark) — plus
**custom text/background colours** (Settings → Appearance).

### Clean vs Classic
A **Clean / Classic** interface toggle (Settings → Interface). Clean is minimal;
**Classic** surfaces the dense original-Ircle cockpit: the nick-list action grid
(Op/DeOp/Whois, Kick/Ban/BanKick, Msg/Cping/Query), the one-click channel-mode
toggle row (`t n i p s m l k r`), the Users/Notify tabs, and the input
formatting toolbar (B/I/U/S + a 16-colour menu).

## Features

- **Multiple servers at once** — each network its own session; saved profiles in
  Settings → Servers; a built-in list of common networks (Libera, OFTC, …) with
  correct TLS defaults.
- **Engine:** TLS, SASL (PLAIN/EXTERNAL), server password, SOCKS5/HTTP-CONNECT
  proxies, full IRCv3 CAP negotiation — via IRCKit.
- **Conversations:** channels, queries, auto-join, op/voice-ranked nick list,
  topic tracking, CTCP (VERSION/PING/TIME + `/me`).
- **DCC** — accept **and** initiate, files **and** chat. Right-click → Send
  File… / Start DCC Chat (or `/dcc send|chat`); a DCC Transfers window (⌘⇧D) with
  progress; downloads to `~/Downloads/Ircle/DCC/`. Security-hardened
  (SSRF-validated peer addresses, path-traversal-safe filenames).
- **Notify (friends) list** — `/notify`; online dots in the Classic Notify tab
  (ISON-polled).
- **Ignore** — `/ignore` (or right-click) with hostmask wildcards; drops
  messages/CTCP/DCC from matches.
- **Sounds** — CTCP sounds + per-event sounds (mention/PM/join/part) from
  `~/Downloads/Ircle/Sounds/`.
- **Logging** — opt-in transcripts to `~/Downloads/Ircle/Logs/`, with an in-app
  log viewer (⌘⇧L).
- **macOS notifications** for mentions & private messages.
- **Command aliases** — `/alias j /join`, with `$1`/`$2-`/`$*` templates.
- **`/away`**, **custom colours**, **in-app manual** (⌘?).
- **AppleScript** — `connect`, `join`, `say [to …]`, `current nickname`.
- **Passwords in the macOS Keychain** (device-only); **auto-backup-on-launch**;
  **Sparkle 2** auto-update (notarized + stapled).

### Slash commands
`/join` (`/j`) `/part` (`/leave`) `/msg` `/query` `/me` `/nick` `/topic`
`/whois` `/away` `/quit` `/raw` (`/quote`) `/sound` `/notify` `/ignore`
(`/unignore`) `/dcc chat|send` `/alias` (`/unalias`) — anything else is passed to
the server; prefix a literal message with `//`.

## Build / run / test

```sh
./build-app.sh        # release → Ircle.app → /Applications → relaunch (+verify fresh)
./build-app.sh --no-install   # build only
./run-tests.sh        # swift-testing (135 tests)
swift build           # debug build
```

Requires macOS 14+, Swift 5.9+. Ircle depends on the sibling `../IRCKit`
package (a local SwiftPM path dependency).

## Default locations

- Settings / config: `~/Library/Application Support/Ircle/settings.json`
- Passwords: macOS **Keychain** (device-only)
- DCC downloads: `~/Downloads/Ircle/DCC/`
- Sounds (you provide): `~/Downloads/Ircle/Sounds/`
- Chat logs: `~/Downloads/Ircle/Logs/<network>/<channel>.log`
- Backups: `~/Downloads/Ircle backup/`

## Status & roadmap

A full-featured client: multi-server, channels/queries, mIRC rendering, DCC
(files + chat, both directions), logging, notifications, ignore, sounds,
aliases, custom colours, the Clean/Classic interface, and an in-app manual.
See `RELEASING.md` for cutting a release.

**Not yet built (deliberately, as future projects):** a full **AppleScript
host** (the original's scripting object model + event handlers + `/load`), and
**networked faces** (the original's CTCP/PICT face exchange — current Faces are
local avatars).

## Naming

"Ircle" is an existing (discontinued, 2009) product name; this is a personal
nostalgic recreation kept inside the PhantomLives monorepo. Flag before any
public distribution.
