# Ircle — User Manual & History

*A nostalgic, clean-room recreation of the classic Mac IRC client, rebuilt for
modern macOS.*

---

## About this recreation

This app is **not** a port of the original Ircle's code. The Ircle most people
remember — the 3.x line — was closed-source and its source was never released;
the only ever open-sourced Ircle was Olaf Titz's 1993 THINK Pascal version,
which is uncompilable on modern systems. So this is a **clean-room
recreation**: the *look and feel* of Ircle was rebuilt from observation
(screenshots, the online manual, contemporaneous reviews) on a brand-new,
modern foundation. **No GPL Pascal source and no proprietary Ircle art, fonts,
or resources were used.** Classic Mac system fonts (Monaco, Geneva) and a
code-generated icon provide the period feel.

"Ircle" is an existing (discontinued) product name; this is a personal,
affectionate homage.

---

## A short history of Ircle

### Origins (1993)

Ircle began as an **IRC client for the classic Mac OS** by **Olaf Titz**,
written in **THINK Pascal** for System 6/7. Versions through **1.56** (1993)
were released under the GPL. This early code is pure classic-Mac-Toolbox Pascal
and predates almost every feature Ircle later became known for.

### The era everyone remembers (late 1990s–2000s)

The Ircle that defined Mac IRC was the **3.x line by Onno Tijdgat** (later under
the *Sembwever* name), written in **C with CodeWarrior**. It introduced the
signature interface and a deep feature set:

- The **Channelbar** — a strip of buttons for fast switching between the many
  windows a busy IRC session produced.
- The **Faces** window — per-user images for the people you chatted with.
- **AppleScript** scriptability so deep that essentially the whole client could
  be driven and extended by scripts (a large third-party script ecosystem grew
  around it, e.g. *Atomik*).
- Up to **ten simultaneous server connections**, a long built-in server list,
  and full **DCC** (chat + file transfer), **XDCC**, and **FServe** file
  serving.

### Version timeline (researched)

- **3.0.4** (US, 1999) — the standing stable release for years.
- **3.1** (2005) — the next stable line.
- **3.5 alpha** line — added **SSL** server connections and **SSL DCC chat**
  (`/DCC SCHAT`), **MP3/AIFF** custom sounds, **Growl** notifications, and moved
  preferences into a `.plist`. Ircle became a **Carbon Mach-O Universal Binary**
  (PowerPC + Intel), compiled with Xcode.
- **3.5a6** — the **final documented release**. (Sources disagree on the date —
  Wikipedia says Nov 17 2007, Mac Orchard says May 20 2008 — but agree it was
  the last build. There was **no 4.0 final**; a circulated "4.0a5 / Ircle X"
  being the last version is a myth.)
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

**File · Edit · Commands · Shortcuts · Format · Windows · Help** — note the
three menus a modern client usually lacks: **Commands** (IRC actions),
**Shortcuts** (user macros/aliases), and **Format** (text-styling inserts).

### Signature windows

- **Console** — connection/system messages (and identd confirmation).
- **Connections** — the server list and live status; in the OS X build, a
  second **"Chat/File transfers"** tab held DCC.
- **Userlist** — channel members, with **Users / Notify** tabs and columns for
  **IrcOp**, **Friend**, and **Hostname**, plus a one-click channel-mode toggle
  row (`t n i p s m l k r`) and a grid of per-user action buttons
  (**Op · DeOp · Whois · Kick · Ban · BanKick · Msg · Cping · Query**).
- **Inputline** — the compose field, with a formatting toolbar and a live
  memory readout.
- **Channelbar**, **Faces**, and a **DCC** view.

### Preferences

A tabbed dialog (File → Preferences) with panes for **Identity**, **Autoexec**
(startup commands), **DCC** (auto-accept, auto-get, save folder, Enable
XDCC/FServe), **Faces**, **CTCP** (sounds, finger/userinfo replies, FACE
EXIST/GET), **Sound**, and **Misc**.

### DCC, CTCP, scripting

- **DCC**: chat and file transfer with **Text / Binary / MacBinary** modes,
  **RESUME**, drag-and-drop send, plus **XDCC** and **FServe** (the latter via a
  loaded `fserver` script).
- **CTCP SOUND**: `/ctcp nick sound file` played a clip from the sounds folder.
- **CTCP FACE EXIST / FACE GET**: 32×32 PICT faces exchanged over IRC (a face
  GET was delivered via DCC).
- **AppleScript**: all preferences settable; `/load` and `/unload` managed
  resident scripts; event handlers existed for join/part/pubmsg/privmsg/nick/
  mode/kick/ctcp/numerics/wallops/invite/notice/inputline plus `on dns()`,
  `on kill()`, `on silence()`, `on connectionevent()`.

---

## Getting started (this app)

1. **Connect.** Press **⌘K** (or use the **Servers** menu / Settings) to connect
   to the default network. Configure servers, identity, and auto-join channels
   in **Settings (⌘,) → Servers**.
2. **The window.** One resizable window consolidates the classic multi-window
   layout: a horizontal **Channelbar** of buffer buttons up top, the channel
   topic, the message area beside the nick list, the input line, and a status
   bar.
3. **Join a channel** with `/join #channel`, switch buffers from the Channelbar,
   and type in the input line (Return sends).

---

## Interface styles: Clean vs Classic

**Settings → Interface** lets you choose how much chrome the windows show:

- **Clean** *(default)* — the minimal modern layout.
- **Classic** — surfaces the dense original-Ircle "power IRC" cockpit:
  - the nick-list **action grid** (Op/DeOp/Whois, Kick/Ban/BanKick,
    Msg/Cping/Query),
  - the one-click **channel-mode toggle row** (`t n i p s m l k r`),
  - the **Users / Notify tabs** on the nick list,
  - the **Inputline formatting toolbar** (bold/italic/underline/strike + a
    16-colour mIRC colour menu),
  - **IRCop ✪ markers** in the nick list.

Both styles share everything else; Clean simply hides the elaborate controls.

---

## Feature reference

### Channels, queries & the nick list
Channels (`#name`) and private queries appear as Channelbar buttons. The nick
list shows membership prefixes (`~ & @ % +`), avatars, and — after a `WHO` on
join — each member's **hostname** (hover to see it) and an **IRCop ✪** marker in
Classic. Right-click a nick for Query, Whois, Start DCC Chat, Send File, and
Ignore.

### Messages & formatting
Messages render **mIRC colours and formatting** (bold/italic/underline/strike,
the 16-colour palette, and hex colours), with colours automatically kept legible
against the message background. URLs are **clickable**. In Classic, the input
line's toolbar inserts formatting codes and colours.

### Custom colours
**Settings → Appearance → Custom colours** overrides the message **text** and
**background** on top of any theme (Platinum or Graphite), with a reset.

### Faces
The **Faces** window (**⌘⇧F**) shows a picture per nick — an image you assign or
a generated monogram. *(This is a local, modern take; the original's networked
PICT face exchange is not implemented.)*

### Notify (friends) list
In Classic, the nick list's **Notify** tab shows friends with a live online dot.
Manage with **`/notify add|del|list <nick>`**; presence is polled via `ISON`.

### Ignore list
Silence unwanted users: **`/ignore add|del|list <mask>`** (or right-click →
Ignore). Masks are IRC hostmasks with `*`/`?` wildcards — `bob` ignores the nick
anywhere; `*!*@spam.host` ignores a whole host.

### DCC (direct connections)
Open the **DCC Transfers** window with **⌘⇧D**.
- **Receive:** when someone offers a file or chat, accept it here. Files save to
  `~/Downloads/Ircle/DCC/` (never overwriting; names sanitized).
- **Send/initiate:** right-click a nick → **Send File…** or **Start DCC Chat**
  (or `/dcc send <nick>` / `/dcc chat <nick>`).
- **Security:** offered peer addresses are validated (only routable IP literals —
  a guard against being made to connect to internal hosts), and filenames can't
  escape the downloads folder.
- **Note:** DCC needs both peers reachable at the advertised IP — use a LAN or
  reachable public addresses (it won't work to your own machine via localhost).

### Sounds
**Settings → Appearance → Sounds.** Play incoming **CTCP sound** clips, and/or
**per-event sounds** (mention / private message / join / part). Drop
`.wav`/`.aiff`/`.mp3` files into **`~/Downloads/Ircle/Sounds/`** and name them in
Settings. Send a sound with `/sound <file> [text]`.

### Logging & the log viewer
Turn on **Settings → Logging** to save transcripts to
`~/Downloads/Ircle/Logs/<network>/<channel>.log`. Browse them in the **Chat
Logs** window (**⌘⇧L**).

### Notifications, links, away
macOS notifications fire for **mentions and private messages** while you're not
looking (toggle in Settings). URLs are clickable. **`/away [message]`** marks you
away (bare `/away` clears it).

### Command aliases
Define your own commands: **`/alias <name> <expansion>`** — e.g.
`/alias j /join`. Templates use `$1`…`$9` (positional), `$2-`/`$*` (the rest);
with no `$`, your arguments are appended. `/alias` lists them; `/unalias <name>`
removes one.

### Slash commands
`/join` (`/j`), `/part` (`/leave`), `/msg` (`/query`), `/me`, `/nick`, `/topic`,
`/quit`, `/whois`, `/away`, `/raw` (`/quote`), `/sound`, plus `/notify`,
`/ignore` (`/unignore`), `/dcc chat|send`, `/alias` (`/unalias`). Unknown
commands are passed straight to the server. Prefix a literal message with `//`.

---

## Under the hood

- **Shared engine.** The IRC wire protocol (parsing, TLS/SASL, the connection
  state machine, DCC security logic, hostmask matching) lives in a shared
  **IRCKit** package, also used by the maintainer's other IRC client.
- **Security.** Passwords are stored in the **macOS Keychain** (device-only),
  never in plaintext settings.
- **Backups.** Settings and faces are auto-backed-up on launch to
  `~/Downloads/Ircle backup/`.
- **Auto-update.** Ships via **Sparkle 2** — notarized, stapled, and signed, so
  it opens cleanly on any Mac.

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
