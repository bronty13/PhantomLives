# Changelog

All notable changes to Ircle are documented here.

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
