# Ircle — User Manual & History

*A nostalgic, clean-room recreation of the classic Mac IRC client, rebuilt for
modern macOS. This manual covers everything: getting connected, every feature,
the full command and shortcut reference, where your files live, troubleshooting,
and the history and research behind the app.*

---

## Contents

- **Getting started** — first launch, connecting, the window
- **Servers & identity** — adding networks, TLS/SASL/proxy, auto-join
- **Channels & conversations** — joining, queries, topics, switching
- **The nick list** — prefixes, hostnames, right-click actions
- **Sending messages & formatting** — colours, actions, links
- **Interface styles** — Clean, Classic, Floating (windows)
- **Connections window** — connecting to multiple servers
- **Modern mode** — themes & custom fonts (opt-in)
- **Faces**, **Notify (friends)**, **Ignore**
- **DCC** — files & chat, sending & receiving, security
- **Sounds**, **Logging**, **Notifications**
- **Command aliases**
- **Command reference** (every slash command)
- **Keyboard shortcuts**
- **Settings reference**
- **Where Ircle stores things**
- **Auto-update & backups**
- **Troubleshooting & FAQ**
- **History of Ircle** and **the research behind this app**

---

## About this recreation

This app is **not** a port of the original Ircle's code. The Ircle most people
remember — the 3.x line — was closed-source and its source was never released;
the only ever open-sourced Ircle was Olaf Titz's 1993 THINK Pascal version,
which is uncompilable on modern systems. So this is a **clean-room
recreation**: the *look and feel* of Ircle was rebuilt from observation
(screenshots, the online manual, contemporaneous reviews) on a brand-new, modern
foundation. **No GPL Pascal source and no proprietary Ircle art, fonts, or
resources were used.** Classic Mac system fonts (Monaco, Geneva) and a
code-generated icon provide the period feel. "Ircle" is an existing
(discontinued) product name; this is a personal, affectionate homage.

---

## Getting started

### First launch
On first launch Ircle opens its single main window and seeds a default server
profile. Nothing connects automatically until you tell it to.

### Connecting
1. Open **Settings** (**⌘,**) and select **Servers**. Pick a network from the
   built-in list (Libera.Chat, OFTC, and friends) or edit the default.
2. Set your **nickname** (and, if the network supports it, SASL account details
   — see *Servers & identity*).
3. Add any channels you want to **auto-join** on connect.
4. Close Settings and press **⌘K** (Connect), or use the **Servers** menu →
   *Connect to <network>*.

You'll see the connection progress and the server's welcome text (the MOTD) in
the **server console** buffer. Once registered, your auto-join channels open.

> **Tip:** if you copied Ircle to a second Mac, give each machine a **different
> nickname** — two clients can't share one nick on the same network (the second
> gets renamed), which also matters for DCC (see that section).

### The window at a glance
One resizable window consolidates what the original Ircle spread across many
windows:
- **Channelbar** (top) — a horizontal strip of buttons, one per open buffer
  (server console, channels `#`, private queries `@`), grouped by network. Click
  to switch; unread counts show as badges; mentions turn the button red.
- **Topic bar** — the current channel's topic.
- **Message area** — the conversation, monospaced, auto-scrolling.
- **Nick list** (channels only, right side) — who's in the channel.
- **Input line** (bottom) — type here; **Return** sends.
- **Status bar** — connection state, your nick, server count.

---

## Servers & identity

Open **Settings → Servers**. Each **server profile** has:
- **Name** — a label for the network.
- **Host & port** — e.g. `irc.libera.chat` / `6697`.
- **Use TLS (SSL)** — encrypts the connection (port 6697 is the usual TLS port;
  6667 is usually plaintext). If a connection times out, the most common cause
  is TLS on a plaintext port or vice-versa.
- **Identity** — nickname, username, and real name.
- **Authentication (SASL)** — *None*, *PLAIN* (account + password), or
  *EXTERNAL* (client certificate). Passwords are stored in the **macOS
  Keychain**, never in the settings file.
- **Proxy** — optional SOCKS5 / HTTP-CONNECT.
- **Auto-join** — channels to join automatically once connected.

**Multiple networks:** connect to several at once (the original supported up to
ten). Each network is its own session; the Channelbar groups buffers by network,
and the **Servers** menu lists each profile. Editing a profile while
disconnected and reconnecting uses the new settings.

**"Nickname is in use":** during sign-on Ircle automatically tries
`yournick_`, then `yournick__`, etc., so a collision doesn't stall the
connection. Set a unique nick to avoid it.

---

## Channels & conversations

- **Join:** `/join #channel` (or `/j #channel`). The channel opens as a
  Channelbar button and gets a nick list.
- **Leave:** `/part` (current channel) or `/part #channel`. The button stays
  (dimmed) so you can rejoin; close it from its right-click menu.
- **Private message / query:** `/msg nick text` sends a one-off; `/query nick`
  opens a dedicated conversation. Incoming private messages open a query buffer
  automatically.
- **Topic:** `/topic` shows it; `/topic new text` sets it (if you're allowed).
- **Switch buffers:** click in the Channelbar. Unread and mention indicators
  help you spot activity.

---

## The nick list

The right-hand list shows everyone in the channel:
- A **membership prefix** before the name — `~` owner, `&` admin, `@` op, `%`
  halfop, `+` voice — colour-coded, ops first.
- An **avatar** (see *Faces*).
- After Ircle runs a `WHO` on join, **hover a nick** to see its `user@host`, and
  in **Classic** style network operators get a **✪** marker.

**Right-click a nick** for: **Query**, **Whois**, **Start DCC Chat**, **Send
File…**, and **Ignore**.

In **Classic** style the nick list also shows (see *Interface styles*):
- a grid of **action buttons** (Op / DeOp / Whois, Kick / Ban / BanKick, Msg /
  Cping / Query) acting on the selected nick;
- a one-click **channel-mode toggle row** — `t n i p s m l k r` — lit when a
  mode is active (click to toggle; `l`/`k` can be cleared here but need a value
  to set);
- **Users / Notify** tabs.

---

## Sending messages & formatting

- **Talk:** type in the input line and press **Return**.
- **Action:** `/me waves` shows "* yournick waves".
- **A literal leading slash:** start the line with `//` to send a message that
  begins with `/`.
- **mIRC formatting & colour** in incoming (and your outgoing) text is rendered:
  bold, italic, underline, strikethrough, the 16-colour palette, and hex
  colours. Colours are automatically nudged to stay legible against the message
  background.
- **Formatting toolbar** (Classic): buttons above the input line insert
  **B**/**I**/**U**, strikethrough (**S**), reset (**P**), and a **colour menu**
  (the 16 mIRC colours + "end colour").
- **Links** in messages are **clickable** and open in your browser.
- **Custom colours:** Settings → Appearance → Custom colours overrides the
  message **text** and **background** on top of your theme.

---

## Interface styles: Clean, Classic, Floating

**Settings → Interface** chooses the window layout:
- **Clean** *(default)* — the minimal modern single-window layout.
- **Classic** — the dense original-Ircle "power IRC" cockpit in one window: the
  nick-list action grid, the channel-mode toggle row, the Users/Notify tabs, the
  input formatting toolbar, and IRCop ✪ markers.
- **Floating** — a faithful recreation of classic Ircle 3.5's **separate
  windows**: a **Console** window (the active server's messages), a window **per
  channel/query**, a detached **Userlist** (nick list) window, and a floating
  **Inputline** window. Whichever channel window you bring to the front becomes
  the target — the Userlist and Inputline follow it, and the **Window** menu
  lists every buffer so you can reopen a channel window you've closed. (Channels
  and queries each get their own window; the Console window follows whichever
  server you're currently using.)

Switching is instant; everything works in all three styles.

---

## Connecting to multiple servers (the Connections window)

Ircle can hold several networks open at once. The easy way is the **Connections
window** — press **⌘⇧K** or choose **Window → Connections**. It lists every saved
server with live status (online / connecting / offline / error) and buttons to
**Connect**, **Disconnect**, **Edit…** (jumps to Settings), and **Nick…**.
Double-click a row to connect. Bring up as many networks as you like, all from
one window — no need to dig through Settings.

**⌘K** still does the quick thing: with a single saved server it connects right
away; with several, it opens the Connections window so you choose (so it never
silently connects only the first server). The per-server **Servers** menu is
still there too.

---

## Modern mode: themes & custom fonts

Ircle's default look is a faithful recreation of classic Mac *Ircle* — Platinum
(or Graphite) chrome, Monaco/Geneva fonts, two-tone 3D bevels — and it stays
exactly that way unless you ask for more.

**Modern mode** (**Settings → Appearance → Enable Modern mode**, *off by
default*) is an opt-in switch that unlocks modern quality-of-life features. The
first one is full control over how Ircle looks. Turn it off any time to return to
the classic look — nothing is lost.

### The Themes tab

With Modern mode on, a **Themes** tab appears in Settings:

- **20 built-in themes.** Darks (Midnight, Dracula, Nord, Tokyo Night, Graphite
  Pro, Solarized Dark, Gruvbox Dark, Twilight, Carbon), lights (Paper, Solarized
  Light, Sepia, Lavender, Snow, Mint, High Contrast), and a few retro-modern
  looks that keep Ircle's 3D bevels in fresh colours (Platinum Plus, Aqua, Slate,
  Noir). Click any tile to apply it — the whole window re-skins instantly.
- **Flat or beveled.** Each theme is either **flat** (clean panels with a hairline
  border) or **beveled** (Ircle's classic 3D edges, recoloured). It's a per-theme
  choice, so the gallery has both.

### Custom fonts (per element)

A theme can set fonts independently for each part of the window — the **message
body**, **nicknames**, **timestamps**, **system lines** (joins/parts/topics), and
the **interface chrome**. For each you can choose the family (any installed font;
filter to monospaced), size, weight, italic, ligatures, and letter-spacing.
Leave a field on **Inherit** to fall back — the message body falls back to
Monaco, the chrome to the system UI font, and the others inherit the message
body. The global **Font size** (Settings → Appearance) sets the message
baseline.

### Making your own themes

In the Themes tab, under **My themes**:

- **New from current theme** opens the **theme editor** on a copy of whatever's
  active. Right-click any built-in tile → **Duplicate & Edit…** to start from it.
- The **editor** is split: colour wells, the flat/beveled toggle, and the
  per-element font controls on the left; a **live preview** of a mock channel on
  the right that updates as you edit.
- **Save** stores it in *My themes* and makes it active. **Save as Copy** forks
  it. **Duplicate**, rename (just edit the name) and **Delete** are in the list.

### Sharing themes

In the editor, **Export…** writes a small **`.ircletheme`** file you can send to
another Ircle user. They use **Import…** (in *My themes*) to add it to their
library — it comes in with a fresh identity, so it never clobbers a theme they
already have.

> **Custom colours** (Settings → Appearance) still apply on top of any theme, in
> both classic and Modern mode.

---

## Faces

The **Faces** window (**⌘⇧F**) shows a picture for each nick — an image you
assign or an automatically generated monogram — and the same avatars appear in
the nick list. *(This is a modern, local take. The original exchanged 32×32 PICT
faces over IRC; that networked exchange is not implemented here.)*

---

## Notify (friends list)

Track whether specific people are online:
- **Add/remove:** `/notify add <nick>`, `/notify del <nick>`, `/notify list`.
- **See them:** in Classic, the nick list's **Notify** tab lists your friends
  with a green (online) / grey (offline) dot. Click a friend to open a query.
- Presence is polled with `ISON` every ~45 seconds (and right after connecting).
  The list is global across networks and is saved.

---

## Ignore

Silence unwanted users — their messages, CTCP, and DCC offers are dropped:
- **Add/remove:** `/ignore add <mask>`, `/ignore del <mask>`, `/ignore list`,
  or `/unignore <mask>`; or right-click a nick → **Ignore**.
- **Masks** are IRC hostmasks with `*` and `?` wildcards, case-insensitive:
  - `/ignore bob` — ignores the nick **bob** from anywhere (expands to
    `bob!*@*`).
  - `/ignore *!*@spam.host` — ignores **everyone** from `spam.host`.
  - `/ignore bob!*@*.example.net` — ignores bob only from that domain.
- The list is global and saved.

---

## DCC (direct connections)

DCC is peer-to-peer: a direct connection between two clients for **file
transfer** or **chat**, bypassing the IRC server. Open the **DCC Transfers**
window with **⌘⇧D** (or the Window menu).

### Receiving a file (or chat) someone offers you
1. When a peer sends you a DCC offer, it appears in **DCC Transfers** (and a
   notice shows in the console).
2. Click **Accept** to download (or to start the chat) or **Decline**.
3. Files download to **`~/Downloads/Ircle/DCC/`** with a progress bar. Names are
   sanitized and never overwrite an existing file (you get `name (1).ext`).
4. When done, click **Reveal** to show the file in Finder. A DCC chat opens in
   its own window.

### Offering a file or chat yourself
- **Right-click a nick → Send File…** (pick a file) or **Start DCC Chat**.
- Or use **`/dcc send <nick>`** / **`/dcc chat <nick>`**.
- Ircle listens on a port, tells the peer your address, and the transfer/chat
  begins when they accept. You'll see it in DCC Transfers with progress.

### Important: DCC needs reachable addresses
Both peers must be able to reach each other at the advertised IP and port:
- **It will not work to your own machine via localhost** — for safety, Ircle
  refuses loopback/`127.0.0.1` addresses. To test between two of your own Macs,
  put them on the **same Wi-Fi/LAN** (so each advertises a routable LAN address)
  and give them **distinct nicks**.
- Across the internet, both sides generally need reachable public IPs or
  port-forwarding; home routers behind NAT often block incoming DCC.
- If Ircle warns it's "listening on all interfaces (couldn't bind <ip>)", the
  transfer still works on a LAN — it's flagging that, while waiting, any host
  reaching that port could connect.

### Security
Offered peer addresses are **validated** (only real, routable IP literals are
dialed — a guard against being tricked into connecting to internal hosts), and
incoming filenames are **sanitized** so a transfer can't escape the downloads
folder. Ircle never auto-accepts; you approve every transfer.

---

## Sounds

**Settings → Appearance → Sounds.** Put your clips (`.wav`, `.aiff`, `.mp3`) in
**`~/Downloads/Ircle/Sounds/`** (there's a **Reveal Sounds Folder** button).

- **CTCP sounds:** when someone sends a `CTCP SOUND`, Ircle plays the named clip
  and shows the message. Send one with `/sound <file> [text]`.
- **Per-event sounds:** turn on "per-event sounds" and name a clip for each of:
  **mention**, **private message**, **someone joins**, **someone parts**. Leave
  an event blank for silence. (A mention takes precedence over a plain PM.)

---

## Logging & the log viewer

Turn on **Settings → Logging → Save chat logs**. Transcripts are written to
**`~/Downloads/Ircle/Logs/<network>/<channel>.log`**, one file per conversation,
timestamped. Browse them in the **Chat Logs** window (**⌘⇧L**): pick a
conversation on the left, read the transcript on the right (it tails the last
256 KB of long logs). Use **Reveal in Finder** to open the folder.

---

## Notifications

With **"Notify me of mentions & private messages"** on (Settings → Messages),
Ircle posts a macOS notification when you're mentioned or messaged privately
**while you're not looking** at that conversation (different buffer, or the app
in the background). macOS asks permission the first time.

---

## Command aliases

Make your own slash commands — **Settings persists them**:
- **Define:** `/alias <name> <expansion>` — e.g. `/alias j /join`.
- **List:** `/alias` ; **remove:** `/unalias <name>` (or `/alias del <name>`).
- **Templates** can reference arguments: `$1`…`$9` are positional, `$2-` is "the
  2nd argument onward", `$*` is "all arguments". If the expansion has no `$`,
  your arguments are appended.

**Examples:**
- `/alias j /join` → `/j #swift` runs `/join #swift`.
- `/alias wave /me waves at $1` → `/wave bob` runs `/me waves at bob`.
- `/alias slap /me slaps $1 around with $2-` → `/slap bob a large trout`.

An alias can expand to another command (or even another alias); a recursion
guard prevents loops.

---

## Command reference

Type these in the input line. Unknown commands are passed straight to the IRC
server.

- **`/join #channel`** (`/j`) — join a channel.
- **`/part [#channel]`** (`/leave`) — leave a channel (default: the current one).
- **`/msg <nick> <text>`** — send a private message.
- **`/query <nick>`** — open a private conversation.
- **`/me <action>`** — send an action ("* you …").
- **`/nick <newnick>`** — change your nickname.
- **`/topic [new topic]`** — show or set the channel topic.
- **`/whois <nick>`** — look up a user.
- **`/away [message]`** — mark yourself away; bare `/away` clears it.
- **`/quit [message]`** — disconnect.
- **`/raw <line>`** (`/quote`) — send a raw IRC line to the server.
- **`/sound <file> [text]`** — play a clip locally and send a CTCP SOUND.
- **`/notify add|del|list <nick>`** — manage the friends list.
- **`/ignore add|del|list <mask>`**, **`/unignore <mask>`** — manage the ignore
  list.
- **`/dcc chat <nick>`** / **`/dcc send <nick>`** — start a DCC chat or file send.
- **`/alias <name> <expansion>`**, **`/alias`**, **`/unalias <name>`** — manage
  aliases.
- **Anything else** — sent to the server verbatim (e.g. `/mode`, `/kick`,
  `/invite`, `/oper`).
- **`//text`** — send a message that begins with a literal slash.

---

## Keyboard shortcuts

- **⌘K** — Connect (single server) / open Connections (several)
- **⌘⇧K** — Connections window
- **⌥⌘K** — Disconnect current
- **⌘⇧F** — Faces window
- **⌘⇧L** — Chat Logs window
- **⌘⇧D** — DCC Transfers window
- **⌘?** — this Manual
- **⌘,** — Settings
- **Return** — send the input line

---

## Settings reference (⌘,)

- **Servers** — add/edit/remove network profiles: host, port, TLS, identity,
  SASL, proxy, auto-join.
- **Modern mode** — opt-in switch (off by default) that unlocks the Themes tab
  and other modern features; off = the classic look.
- **Classic appearance** — Platinum (classic light) or Graphite (dark); applies
  when Modern mode is off.
- **Interface** — Clean, Classic, or Floating (single window vs. the classic
  floating multi-window layout).
- **Connections** *(⌘⇧K / Window menu)* — the multi-server hub: every saved
  server with status + Connect/Disconnect/Edit/Nick.
- **Themes** *(Modern mode)* — 20 built-in themes, a custom-theme editor with
  per-element fonts and a live preview, and `.ircletheme` export/import.
- **Custom colours** — override message text/background; reset to theme.
- **Sounds** — CTCP sounds on/off, per-event sounds on/off and their clip names,
  Reveal Sounds Folder.
- **Messages** — show timestamps; mention/PM notifications; message font size.
- **Logging** — save chat logs on/off; Open Log Viewer; Reveal Logs Folder.
- **Backup** — automatic on-launch backups (and the backup folder).

---

## Where Ircle stores things

- **Settings:** `~/Library/Application Support/Ircle/` (and the Faces images).
- **Passwords:** the macOS **Keychain** (device-only; never in the settings
  file).
- **Downloads (DCC):** `~/Downloads/Ircle/DCC/`
- **Sounds (you provide):** `~/Downloads/Ircle/Sounds/`
- **Chat logs:** `~/Downloads/Ircle/Logs/<network>/<channel>.log`
- **Backups:** `~/Downloads/Ircle backup/`

---

## Auto-update & backups

- **Auto-update:** Ircle updates itself via **Sparkle**. Builds are notarized,
  stapled, and signed, so a download opens cleanly on any Mac. Use the
  application menu's **Check for Updates…** to check manually.
- **Backups:** on launch Ircle backs up your settings and faces to
  `~/Downloads/Ircle backup/` (older backups are pruned), so a bad edit or a
  lost machine doesn't lose your configuration.

---

## Troubleshooting & FAQ

**A connection times out.** Usually a TLS/port mismatch — try toggling **Use
TLS** (TLS is normally port 6697; plaintext 6667). Ircle's timeout message names
the host/port and suggests which to check.

**"Nickname is in use."** Someone (often your other client) already has that
nick. Ircle auto-tries `nick_`; set a unique nickname in Settings.

**A downloaded build says "Apple could not verify… malware."** Make sure you
**unzipped the official release** (released builds are notarized and open
cleanly). If a third-party unzip tool leaves stray files, re-download and unzip
in Finder, or right-click → Open once.

**DCC won't connect.** Confirm both peers are on the **same LAN** (or have
reachable public IPs) and have **distinct nicks** — DCC to your own nick, or to
`127.0.0.1`, is refused by design. Watch the DCC Transfers window for the status.

**Sounds don't play.** Confirm the clip is in `~/Downloads/Ircle/Sounds/`, the
filename in Settings matches exactly, and the relevant toggle (CTCP / per-event)
is on.

**I don't see the Classic buttons / mode row / tabs.** Switch **Settings →
Interface → Classic**.

**Where did my file go?** DCC downloads land in `~/Downloads/Ircle/DCC/`; use the
transfer's **Reveal** button.

---

## A short history of Ircle

### Origins (1993)
Ircle began as an IRC client for the **classic Mac OS** by **Olaf Titz**,
written in **THINK Pascal** for System 6/7. Versions through **1.56** (1993)
were released under the GPL. This early code is pure classic-Mac-Toolbox Pascal
and predates almost every feature Ircle later became known for.

### The era everyone remembers (late 1990s–2000s)
The Ircle that defined Mac IRC was the **3.x line by Onno Tijdgat** (later under
the *Sembwever* name), written in **C with CodeWarrior**. It introduced the
signature interface and a deep feature set: the **Channelbar**, the **Faces**
window, very deep **AppleScript** scriptability (a large third-party script
ecosystem grew around it, e.g. *Atomik*), up to **ten simultaneous server
connections**, and full **DCC**, **XDCC**, and **FServe** file serving.

### Version timeline (researched)
- **3.0.4** (US, 1999) — the standing stable release for years.
- **3.1** (2005) — the next stable line.
- **3.5 alpha** line — added **SSL** server connections and **SSL DCC chat**
  (`/DCC SCHAT`), **MP3/AIFF** custom sounds, **Growl** notifications, and moved
  preferences to a `.plist`. Ircle became a **Carbon Mach-O Universal Binary**
  (PowerPC + Intel), compiled with Xcode.
- **3.5a6** — the **final documented release**. Sources disagree on the date
  (Wikipedia: Nov 17 2007; Mac Orchard: May 20 2008) but agree it was the last
  build. There was **no 4.0 final** — a circulated "4.0a5 / Ircle X" being the
  last version is a myth.
- **2009** — the application was **discontinued**.

> **Research provenance.** This history was assembled from the official
> `irc.org` Ircle beta changelog, Atomik's project page, IRChelp.org, the CSUN
> Ircle tutorial, Mac Orchard, Wikipedia, Macanics, and the Macintosh Garden /
> Macintosh Repository archives. Where sources conflicted (e.g. the 3.5a6 date),
> the disagreement is noted rather than papered over.

---

## What the original looked like (the research)

For fidelity, the original was studied from archived screenshots of both a
classic (Mac OS 8/9) build and a Mac OS X (Aqua) build.

### Menu bar
**File · Edit · Commands · Shortcuts · Format · Windows · Help** — note the three
menus a modern client usually lacks: **Commands** (IRC actions), **Shortcuts**
(user macros/aliases), and **Format** (text-styling inserts).

### Signature windows
- **Console** — connection/system messages (and identd confirmation).
- **Connections** — the server list and live status; the OS X build added a
  **"Chat/File transfers"** tab for DCC.
- **Userlist** — channel members, with **Users / Notify** tabs and columns for
  **IrcOp**, **Friend**, and **Hostname**, plus a channel-mode toggle row
  (`t n i p s m l k r`) and a grid of per-user action buttons
  (Op · DeOp · Whois · Kick · Ban · BanKick · Msg · Cping · Query).
- **Inputline** — the compose field, with a formatting toolbar and a live memory
  readout.
- **Channelbar**, **Faces**, and a **DCC** view.

### Preferences
A tabbed dialog with panes for **Identity**, **Autoexec** (startup commands),
**DCC** (auto-accept, auto-get, save folder, Enable XDCC/FServe), **Faces**,
**CTCP** (sounds, finger/userinfo replies, FACE EXIST/GET), **Sound**, and
**Misc**.

### DCC, CTCP, scripting
- **DCC**: chat and file transfer with **Text / Binary / MacBinary** modes,
  **RESUME**, drag-and-drop send, plus **XDCC** and **FServe** (the latter via a
  loaded `fserver` script).
- **CTCP SOUND**: `/ctcp nick sound file` played a clip from the sounds folder.
- **CTCP FACE EXIST / FACE GET**: 32×32 PICT faces exchanged over IRC (a face GET
  was delivered via DCC).
- **AppleScript**: all preferences settable; `/load` / `/unload` managed
  resident scripts; event handlers existed for join/part/pubmsg/privmsg/nick/
  mode/kick/ctcp/numerics/wallops/invite/notice/inputline plus `on dns()`,
  `on kill()`, `on silence()`, `on connectionevent()`.

---

## How this differs from the original

- **Modernized:** TLS/SASL/IRCv3 throughout, Retina-crisp Platinum + a dark
  Graphite theme, Unicode/emoji, Keychain passwords, Sparkle auto-update, in-app
  logging, and macOS notifications.
- **Deliberately not built (yet):** a full **AppleScript host** (the original's
  scripting object model and event handlers), and **networked faces** (the
  original's CTCP/PICT face exchange). Our Faces are local avatars.

---

## Credits

A personal homage to the original **Ircle** by **Onno Tijdgat** (and the early
GPL work by **Olaf Titz**). Built clean-room from public documentation and
archived screenshots; no original code or art was used.
