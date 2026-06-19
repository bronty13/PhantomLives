# Original Ircle → our clone: feature-parity gap checklist

A scoping inventory of the **original Ircle** (Onno Tijdgat / Sembwever) — final
documented build **3.5a6**, a Carbon Mach-O Universal Binary (PPC+Intel);
discontinued 2009; **no 4.0 ever shipped as final** — mapped against what our
clean-room **Ircle** (this subproject) has built so far. Use it as a build
backlog.

> Researched 2026-06-19 via a multi-source deep-research pass (20 confirmed
> claims, 5 refuted). **Primary sources:** the official
> `irc.org/.../ircle/betareadme.html` changelog and Atomik's SourceForge page.
> **Secondary:** IRChelp, the CSUN ircle tutorial, Mac Orchard, Wikipedia,
> Macanics, preterhuman, Macintosh Repository.
>
> **Visually verified (2026-06-19):** the Macintosh Garden Ircle page
> (`macintoshgarden.org/apps/ircle`) hosts two screenshots — a classic (OS 8/9)
> build and a **Mac OS X / Aqua build** — which were inspected directly in a
> browser. These confirm the menu bar and several windows the prose sources
> couldn't (marked "👁 seen" below).

**Caveats baked into this list:**
- The **complete menu-bar inventory** (every menu + item) was *not* recoverable
  from any source — only `File > Preferences` and the `Windows` menu items are
  confirmed. Treat menu specifics as TODO-verify.
- The **full AppleScript dictionary** object model is unverified; a circulated
  claim that scripts can add custom slash commands was *refuted*.
- Some of the richest detail (DCC window, faces, AppleScript handlers) is from
  the 2.6b/3.0b changelog (1996–97); confirmed present in 3.0, almost certainly
  persisted, but not re-confirmed line-by-line for 3.5.
- Preferences **pane partitioning** is fuzzy (CSUN shows separate DCC/Faces/
  CTCP/Sound/Misc tabs; IRChelp's 3.x guide shows a combined Misc./CTCP).

**Legend:** ✅ have · 🟡 partial · ❌ missing · 🆕 modern equivalent we already do
differently. **Type:** `win`=window/panel · `pref`=preferences option ·
`menu`=menu item · `cmd`=slash command · `eng`=engine/protocol.

---

## 0. Menu bar (👁 seen)

Top-level menus, confirmed from the classic-build screenshot:
**File · Edit · Commands · Shortcuts · Format · Windows · Help**
(Per-item contents still need a clean capture, but `Commands`, `Shortcuts`, and
`Format` are three menus our clone has no equivalent of — `Format` ≈ text styling
inserts, `Commands` ≈ IRC actions, `Shortcuts` ≈ user macros/aliases.)

## 1. Windows & panels

| Feature | Type | Original | Ours | Notes |
|---|---|---|---|---|
| Channelbar | win | ✅ | ✅ | Ours is grouped by server. |
| Userlist (nick list; ops in red) | win | ✅ | ✅ | Ours shows mode-prefix ordering. |
| Inputline | win | ✅ | ✅ | |
| Console (server/system messages, identd) | win | ✅ | 🟡 | We have a per-server buffer ≈ Console; no identd UI. |
| Connections (server list + live status) | win | ✅ | 🟡 | We have Channelbar-by-server + a Servers settings manager, but no dedicated connection-status window. |
| Faces window | win | ✅ | 🟡 | **We have the window** (assigned image or generated monogram) but **not the IRC face-exchange protocol** — see §4. |
| DCC / file transfers | win | ✅ 👁 | ❌ | In the OS X build it's the **"Chat/File transfers" tab of the Connections window**, not a separate window. No DCC at all in ours. |
| Notify / friends list | win | ✅ 👁 | ✅ **in Classic** | Users/Notify tabs on the nick list; ISON-polled online dots; add/remove + `/notify` command; global, persisted. |
| Ignore/silence list panel | win | ❓ | ❌ | Original had an `on silence()` handler; no UI panel seen yet. |
| Log viewer | win | ❓ | ✅ | Chat Logs window (⌘⇧L) browses ~/Downloads/Ircle/Logs; logging is opt-in. |

## 1b. In-window controls (👁 seen in the OS X build — all ❌ in ours)

| Control | Where | Original | Ours |
|---|---|---|---|
| Per-user action buttons: **Op · DeOp · Whois · Kick · Ban · BanKick · Msg · Cping · Query** | Userlist | ✅ 👁 | ✅ **in Classic** (Settings → Interface → Classic; Clean keeps the compact Query/Whois/Op/DeOp bar) |
| One-click **channel-mode toggles** `t n i p s m l k r` | Userlist | ✅ 👁 | ✅ **in Classic** (lit = active; backed by MODE-parsing + 324 on join; `l`/`k` clear-only since they need a value) |
| Userlist columns **IrcOp · Friend · Hostname** | Userlist | ✅ 👁 | 🟡 (we show nick + mode prefix only) |
| **Inputline formatting toolbar** (Plain/Bold/Underline/strike + colour swatches) | Inputline | ✅ 👁 | ✅ (B/I/U always; Classic adds Strike/Plain + a 16-colour mIRC menu) |
| Live **memory readout** bar `[……|……]` | Inputline | ✅ 👁 | ❌ (n/a on modern macOS) |
| Connections buttons **Connect · Disconn · Edit · Nick · Server** + add/remove | Connections | ✅ 👁 | 🟡 (Servers settings manager, not an in-window bar) |
| Topic bar with **set-by / on-date** | Channel | ✅ 👁 | 🟡 (we show topic, not setter/date) |

## 2. Preferences panes (`File > Preferences`, tabbed)

| Pane / option | Type | Original | Ours | Notes |
|---|---|---|---|---|
| Identity (nick / username / real name) | pref | ✅ | ✅ | Our Identities + per-server profiles. |
| Auto-connect, Invisible (+i) | pref | ✅ | 🟡 | Auto-connect yes; invisible mode not exposed. |
| Autoexec (startup commands, e.g. `/join`) | pref | ✅ | 🟡 | We auto-join configured channels; no free-form startup command list. |
| DCC tab: Auto-accept Chat, Auto-GET, Auto-save folder, Enable XDCC/FServe | pref | ✅ | ❌ | No DCC. |
| Faces tab: face folder + exchange options | pref | ✅ | ❌ | We have faces but no prefs/exchange. |
| CTCP tab: Enable CTCP sound, Disable CTCP, finger/userinfo replies, FACE EXIST/GET | pref | ✅ | 🟡 | We answer VERSION/PING/TIME but expose no CTCP prefs and no sound/face. |
| Sound tab (per-event sounds; MP3/AIFF in 3.5) | pref | ✅ | ❌ | No sounds. |
| Text / background **colour pickers** ("whatever colours you wish") | pref | ✅ | 🟡 | We ship Platinum/Graphite themes, not arbitrary user colour pickers. |
| SSL options (3.5a line) | pref | ✅ | ✅ | We do TLS via IRCKit (+ SASL, proxy). |

## 3. DCC / file transfer  — **Stage 1 done: offers parsed + surfaced; transport pending**

> IRCKit's audited `DCC` engine now parses + validates inbound offers (SSRF +
> path-traversal guards) and Ircle surfaces them. Accepting/transferring (sockets,
> a manager window) is Stage 2.

| Feature | Type | Original |
|---|---|---|
| DCC Chat (**accept done** — Stage 3) | cmd/eng | ✅→🟡 |
| DCC Send / Get (**receive/accept done** — Stage 2) | cmd/eng | ✅→🟡 |
| DCC RESUME (incl. with PC clients) | eng | ✅ |
| Drag-and-drop send | win | ✅ |
| MacBinary recognition on GET | eng | ✅ |
| XDCC (`/xdcc <opnick> list`, `… send #`) | cmd | ✅ |
| FServe file-serving (via loaded `fserver` script) | cmd | ✅ |
| SSL DCC Chat (`/DCC SCHAT nick`, 3.5a) | cmd/eng | ✅ |

## 4. CTCP

| Feature | Type | Original | Ours | Notes |
|---|---|---|---|---|
| CTCP responder (VERSION/PING/TIME) | eng | ✅ | ✅ | Ours answers VERSION/PING/TIME; ACTION for `/me`. |
| CTCP **sound** (`/ctcp nick sound file`, sounds folder) | eng/pref | ✅ | ❌ | |
| CTCP **FACE EXIST / FACE GET** (32×32 PICT exchange; big faces; DCC of face) | eng | ✅ | ❌ | This is the *networked* half of the Faces window. |
| finger / userinfo custom replies | pref | ✅ | ❌ | |

## 5. AppleScript / scripting

| Feature | Type | Original | Ours | Notes |
|---|---|---|---|---|
| Basic verbs (connect / join / say / current nick) | — | ✅ | ✅ | Our `.sdef` has exactly these 4. |
| **All preferences settable** via AppleScript | — | ✅ | ❌ | Big gap. |
| `/load` · `/unload` resident scripts | cmd | ✅ | ❌ | Whole resident-script system. |
| Event handlers: `on join/part/pubmsg/privmsg/nick/mode/kick/ctcp/numerics/wallops/invite/notice/inputline/dns/kill/silence/connectionevent` | — | ✅ | ❌ | The event model that powered the script ecosystem (e.g. Atomik). |
| Third-party script ecosystem | — | ✅ | ❌ | N/A unless we build the host. |

> ⚠️ The exact AppleScript dictionary/object model for the final builds is
> **unverified**; the claim that scripts could add custom slash commands was
> **refuted**. Don't reverse-engineer a dictionary from secondary claims —
> design our own if we pursue this.

## 6. Text / colour / sound / themes / notifications

| Feature | Type | Original | Ours | Notes |
|---|---|---|---|---|
| mIRC colour + formatting rendering | eng | ✅ | ✅ | Ours adds background-contrast clamping. |
| Adjustable text/background colours | pref | ✅ | 🟡 | Theme presets, not free colour pickers. |
| IRC macros (ircII-style) / aliases | cmd | ✅ | ❌ | No user-defined macros/aliases. |
| Per-event sounds (MP3/AIFF in 3.5) | pref | ✅ | ❌ | |
| Notifications (Growl in 3.5) | — | ✅ | ✅ 🆕 | macOS notifications for mentions/PMs; Settings toggle. |
| Themes | — | (colours only) | ✅ | We exceed the original here (Platinum/Graphite). |
| Auto-update | — | manual | 🆕 | We add Sparkle. |
| Credential storage | — | prefs file | 🆕 | We add Keychain. |
| Backup-on-launch | — | — | 🆕 | We add it. |

## 7. Other capabilities

| Feature | Type | Original | Ours | Notes |
|---|---|---|---|---|
| Multiple simultaneous servers | eng | ✅ (cap 10) | ✅ | Ours effectively uncapped. |
| Built-in server list | pref | ✅ | ✅ | Our presets. |
| TLS/SSL, SASL, proxy | eng | 🟡 (SSL in 3.5a) | ✅ | Ours via IRCKit (SASL PLAIN/EXTERNAL, SOCKS5/HTTP). |
| Slash commands | cmd | many | 🟡 | Ours: JOIN/PART/MSG/QUERY/ME/NICK/TOPIC/QUIT/RAW/WHOIS + server passthrough. |
| `/away` (+ away UI) | cmd | ✅ | ✅ (`/away [msg]`; 305/306 tracked) | |
| `/ignore` + ignore list | cmd/win | ✅ | ❌ | |
| Auto-ops | pref | ✅ | ❌ | |
| Chat logging | eng/win | ✅ | ✅ | Opt-in; per-network/channel .log files under ~/Downloads/Ircle/Logs. |
| URL handling (clickable links) | eng | ✅ | ✅ | renderer linkifies URLs (tappable, underlined). |

---

## Open questions to resolve before building (from the research)

1. **Menu items per menu** — top-level menus confirmed (File · Edit · Commands ·
   Shortcuts · Format · Windows · Help 👁); still need each menu's item list.
2. **Full AppleScript dictionary** — real object model + whether scripts can add
   commands (circulated claim refuted).
3. **Final 3.5-alpha preference panes** — did SSL/Growl/MP3 restructure the tabs?
   Need a screenshot of the OS X Preferences window (not yet seen).
4. **Notify/friends list confirmed** (Userlist Users/Notify tabs + Friend column
   👁). Still open: a dedicated **ignore/silence list** UI and a **log viewer**.

## Suggested build priority (highest user value first)

1. **DCC** (chat → send/get → resume) + DCC Status window — the single biggest
   missing pillar; touches engine (IRCKit) + UI.
2. **Chat logging + a log viewer** — low-risk, high utility.
3. **`/away`, `/ignore` (+ ignore list), `/me` already done** — small command/UI wins.
4. **Clickable URLs** in the message renderer.
5. **macOS notifications** (modern Growl) for mentions/queries.
6. **CTCP SOUND + FACE exchange** — completes the nostalgic Faces feature.
7. **User colour pickers / per-event sounds**, **aliases/macros**.
8. **(Stretch) a real AppleScript host** with an event model — large; design
   fresh rather than copying the unverified original dictionary.
