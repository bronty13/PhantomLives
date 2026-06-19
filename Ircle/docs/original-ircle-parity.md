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
> Macanics, preterhuman, Macintosh Repository. Screenshots live on the CSUN
> tutorial, Macintosh Garden, and Mac Orchard pages (archive.org copies couldn't
> be fetched headlessly — open them in a browser for the visual reference).

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

## 1. Windows & panels

| Feature | Type | Original | Ours | Notes |
|---|---|---|---|---|
| Channelbar | win | ✅ | ✅ | Ours is grouped by server. |
| Userlist (nick list; ops in red) | win | ✅ | ✅ | Ours shows mode-prefix ordering. |
| Inputline | win | ✅ | ✅ | |
| Console (server/system messages, identd) | win | ✅ | 🟡 | We have a per-server buffer ≈ Console; no identd UI. |
| Connections (server list + live status) | win | ✅ | 🟡 | We have Channelbar-by-server + a Servers settings manager, but no dedicated connection-status window. |
| Faces window | win | ✅ | 🟡 | **We have the window** (assigned image or generated monogram) but **not the IRC face-exchange protocol** — see §4. |
| DCC Status window (icons, ETA, bytes ack'd) | win | ✅ | ❌ | No DCC at all. |
| Notify / friends list panel | win | ❓ | ❌ | Asked-for; no source confirmed the original had a dedicated panel. |
| Ignore/silence list panel | win | ❓ | ❌ | Original had an `on silence()` handler; no UI panel documented. |
| Log viewer | win | ❓ | ❌ | No chat logging in our clone at all. |

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

## 3. DCC / file transfer  — **entirely missing in our clone (❌)**

| Feature | Type | Original |
|---|---|---|
| DCC Chat (`/dcc chat nick`) | cmd/eng | ✅ |
| DCC Send / Get, modes Text / Binary / MacBinary | cmd/eng | ✅ |
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
| Notifications (Growl in 3.5) | — | ✅ | ❌ → 🆕 | We have none yet; modern target = `UNUserNotificationCenter`. |
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
| `/away` (+ away UI) | cmd | ✅ | ❌ | |
| `/ignore` + ignore list | cmd/win | ✅ | ❌ | |
| Auto-ops | pref | ✅ | ❌ | |
| Chat logging | eng/win | ✅ | ❌ | |
| URL handling (clickable links) | eng | ✅ | ❌ | mIRC renderer does not linkify URLs yet. |

---

## Open questions to resolve before building (from the research)

1. **Full menu-bar map** — exact menus and every item. No source enumerated it.
2. **Full AppleScript dictionary** — real object model + whether scripts can add
   commands (circulated claim refuted).
3. **Final 3.5-alpha preference panes** — did SSL/Growl/MP3 restructure the tabs?
4. **Confirm dedicated panels existed** for notify/ignore/log/server-setup
   beyond the Connections window.

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
