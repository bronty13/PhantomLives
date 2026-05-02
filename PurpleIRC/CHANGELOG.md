# Changelog

All notable changes to PurpleIRC are recorded here. The bundle's
`CFBundleShortVersionString` is derived automatically from the git commit
count (`1.0.<count>`); CHANGELOG entries use the same scheme so the
version on the About panel matches the entry that introduced it.

## [1.0.110] — 2026-05-02

### Added (Address Book + Tags — multi-select, auto-naming, duplicate guards)

- **Auto-numbered placeholder names** at create time. The Address Book
  `+` button now seeds new contacts with `New Contact 1`, `New Contact
  2`, … via `AddressEntry.nextDefaultNick(existing:)`, walking the
  list and stopping at the first gap. The Tag Manager `+` button does
  the equivalent with `New Tag 1`, `New Tag 2`, … via
  `ContactTag.nextDefaultName(existing:)`. Both are case-insensitive,
  so the next slot is picked correctly even after a manual rename
  collides with an old default.
- **Duplicate-name guards.**
  - `ContactTag.nameClashes(_:in:excluding:)` and
    `AddressEntry.nickClashes(_:in:excluding:)` power non-blocking
    inline warnings under the name / nickname field in their
    respective editors. The user can keep typing — the warning is
    advisory — but the orange triangle catches accidental duplicates
    the moment they happen.
  - `ContactTagAddPopover.createAndPick` now folds duplicates into
    the existing tag instead of minting a second copy. Type `Friend`
    when there's already a `friend` tag and you get the existing
    tag assigned, not a duplicate.
- **Multi-select + bulk delete.** Both the Address Book contact list
  and the Tag Manager list now use `Set<UUID>` selection so cmd-click
  / shift-click work natively. The `−` button deletes every selected
  row in one pass; the editor pane only renders for single-selection
  (multi-selection shows a "N selected" placeholder so the form is
  never ambiguous about what it's editing). Multi-deletes
  always confirm (tags always confirm regardless of count because
  the deletion cascades across contacts; contacts confirm only when
  N > 1 to preserve the prior 1-click feel for single deletes).
  Both bulk deletes follow the same selection-before-mutation
  discipline as the 1.0.109 crash fix.

## [1.0.109] — 2026-05-02

### Fixed

- **Crash when deleting a tag from "Manage tags…".** The tag editor's
  TextField bindings captured the tag's array index once at body
  computation; when `deleteTag` shrank `contactTags`, a pending
  binding write hit an out-of-range index and crashed the app.
  Replaced every editor binding with id-based safe lookups (returns
  no-op when the tag is gone) and reordered the delete action to
  clear `selection` *before* mutating the array, so the editor
  pane immediately stops referencing the deleted row.
- **Crash when deleting the last address-book entry.** Same root
  cause and same fix in `AddressBookSetup`. The detail pane wrapped
  `AddressEntryEditor` in a `Binding(get:set:)` that captured the
  contact's array index; deleting the last contact (or any contact
  while a TextField had a pending commit) sent the binding's `set`
  out of bounds. Now the binding looks up the row by id every time,
  and the minus button picks the next selection (or `nil` when the
  list is about to be empty) BEFORE calling `removeAddress`.

### Added

- **Per-tag chip color.** `ContactTag.colorHex` (optional `#RRGGBB`)
  joins the existing fields. The Manage Tags editor gains a Color
  section with a "Custom color" toggle and a `ColorPicker` (same
  pattern as `HighlightRuleEditor`) — the live chip rendered next to
  the picker previews the result. Tags without a custom color keep
  the default purple chip everywhere they're rendered. Forward-
  compatible decoder so older settings.json files keep loading.
- **Auto-assigned colors at create time.** Both tag-creation paths
  (Manage Tags `+` and the inline "Create" affordance in the
  per-contact picker) now seed the new tag with the least-used color
  from a 12-entry palette via `ContactTag.nextDefaultColorHex(...)`.
  Purple is first so the very first tag still matches the address
  book's theme color; subsequent tags rotate through blue / green /
  orange / red / pink / teal / amber / brown / indigo / cyan / lime
  before any color is reused. Users can still override via the
  Custom color section.

## [1.0.108] — 2026-05-02

### Added (Address Book — tags + cross-store matches + toolbar shortcut)

- **Contact tags.** New `ContactTag` model (id, name, optional
  description) lives on `AppSettings.contactTags` so it inherits the
  same encrypted-envelope persistence as every other settings field.
  `AddressEntry` gains `tagIDs: [UUID]`; both new fields use a
  forward-compatible decoder so older `settings.json` files keep
  loading. `SettingsStore.upsertTag` / `deleteTag(id:)` are the only
  mutation paths — `deleteTag` cascades through every address-book
  entry and strips the id, so removing a tag never leaves a dangling
  reference behind.
- **Manage tags sheet.** New "Manage tags…" button at the top of
  Setup → Address Book opens a master/detail sheet for adding,
  renaming, editing the description of, and deleting tags. The list
  shows usage counts and the editor surfaces every contact currently
  carrying the selected tag. Delete is confirmation-gated and the
  prompt explains the cascade up front.
- **Per-contact tag picker.** `AddressEntryEditor` gains a Tags
  section with chip rows (remove via the chip's ✕) and an "Add tag…"
  popover that lists every defined tag (already-assigned ones grey
  out) plus an inline "Create" field so users can mint a new tag
  without context-switching. Tag chips also render on the contact
  list rows so users can scan tagged contacts at a glance.
- **Cross-store match panel inside the contact editor.** New
  `ContactMatchesSection` walks every connected network's
  `SeenStore` plus the `LogStore` index for the contact's nick.
  Exact and fuzzy (case-insensitive substring) matches are
  surfaced separately, with action buttons that open the seen log
  on the right network, jump to the chat-log viewer, or open a
  `/query` buffer with the matched nick. The panel reruns whenever
  the user edits the nickname; log lookups are awaited off-actor
  since `LogStore` is an actor.
- **Toolbar shortcut.** New Address Book toolbar button
  (`person.crop.rectangle.stack`) opens Setup straight to the
  Address Book tab via the existing `pendingSetupTab` plumbing — no
  more "Setup → sidebar → Address Book" three-click landing.

## [1.0.103] — 2026-05-01

### Changed (build-app.sh)

- **Real Developer ID signing**, with auto-detection. The script now
  scans `security find-identity -v -p codesigning` for a
  `Developer ID Application:` cert and signs with it when found,
  falling back to ad-hoc (`-`) signing otherwise so the script
  keeps working in CI / on machines without your cert. Override
  via `CODESIGN_IDENTITY=...` (use `-` to force ad-hoc, or pass a
  full common-name to pin a specific cert when multiple are
  installed).
- **`--options runtime --timestamp` added** when a real cert is
  used. Hardened runtime + Apple-issued timestamp are both
  prerequisites for `notarytool submit`; without them Apple
  notary rejects the bundle.
- **Build moved to `/tmp` to dodge iCloud Drive's xattr races.**
  PhantomLives lives under `~/Documents` which is iCloud-synced;
  iCloud re-attaches `com.apple.FinderInfo` to fresh files at
  unpredictable moments, and `codesign --strict` refuses to sign
  or verify any bundle carrying that xattr. Assembly + sign +
  verify all happen in `mktemp -d` (which iCloud doesn't watch),
  then `ditto --noextattr` copies the finished bundle back into
  the project directory. The signature is embedded in the bundle
  contents so iCloud's eventual FinderInfo reattach in the
  project-dir copy doesn't disturb it.
- **xattr cleanup expanded** — explicit `xattr -d` calls for
  `com.apple.FinderInfo`, `com.apple.fileprovider.fpfs#P`,
  `com.apple.provenance`, and `com.apple.quarantine` in addition
  to the recursive `xattr -cr` clear, so any one of them
  surviving the recursive sweep can't block the sign.
- **Verify step uses exit code, not output parsing.** Previous
  `tail -1 | grep "valid on disk"` was looking at the second
  line of `codesign --verify --verbose=2` output ("satisfies
  its Designated Requirement"), so the check always reported
  failure even on success. Now uses `codesign`'s exit code
  directly, with the failure log captured to `/tmp/codesign-
  verify.log` for diagnostic.

## [1.0.102] — 2026-05-01

### Tests

- **+58 tests across 4 new suites** — covers the components added in
  Phases 1-8 (UserTheme, BlobStore, FontStyle, PhotoUtilities). Total
  now 222 tests across 16 suites.
- **`UserThemeTests` (16 tests)** — `duplicate(of:name:)` snapshots
  every color slot and produces a fresh UUID; `materialised`
  tolerates missing palette slots, oversized palettes, and garbage
  hex values; `kindOverridesMaterialised` parses good entries and
  drops bad keys / values; `Theme.resolve(id:userThemes:)` lets
  built-ins win on id collision and falls back to `.classic` on
  miss; UserTheme round-trips through JSON; ChatLineKindTag
  rawValues are pinned (renaming any of the 14 tags would break
  every existing user theme on disk).
- **`BlobStoreTests` (10 tests)** — store + read round-trip for
  both plaintext and AES-GCM-sealed payloads; `delete` is
  idempotent and removes both file + index row; `writeToTempFile`
  produces a readable file with the right name; index survives
  across BlobStore instances pointed at the same dir; encrypted
  index loads empty without a key, then re-loads when the key
  arrives via `setEncryptionKey`; `allRecords` sorts newest first;
  `store(fileURL:)` auto-guesses MIME from the file extension.
- **`FontStyleTests` (16 tests)** — root resolution from legacy
  fields produces the right family/size/weight; built-in tokens
  (`system-mono`, `system-proportional`) flag correctly;
  FontStyle fields override legacy fields when set, and inherit
  when at the sentinel; slot inheritance from the chat-body
  parent leaves unset fields untouched; partial overrides only
  affect the set fields; FontStyle round-trips through JSON;
  Weight rawValues are pinned (saved per-element fonts would
  break otherwise).
- **`PhotoUtilitiesTests` (16 tests)** — `initials(for:)` picks
  the first alphanumeric (uppercased), skips leading non-letters,
  falls back to "?" for empty / punctuation-only nicks;
  `avatarTint(for:)` is deterministic and case-insensitive across
  calls (compared by sRGB component triplet — SwiftUI Color
  equality returns identity for catalog wrappers, not value
  equality), and produces visibly distinct colors across 10
  arbitrary nicks; `downscale` is a no-op for already-small
  images, preserves aspect ratio for both landscape and portrait,
  handles zero-sized images gracefully; `downscaleAndEncode`
  produces a decodable JPEG with dimensions ≤ 256 px;
  `loadDownscaled(from:)` returns nil for missing or
  non-image files.

### Notes

`UserThemeTests`, `FontStyleTests`, and `BlobStoreTests` exercise
shaped fields whose stability is part of the on-disk file format.
Renaming any of those rawValues / property names will surface as
test breakage, which is the intended early-warning signal.

## [1.0.101] — 2026-05-01

### Added (Phase 8 — Visual polish)

- **Animated network state dot** in the sidebar Networks section.
  Pulses (1.0× ↔ 1.3× scale) while the connection is in
  `.connecting`. A soft blurred halo glows behind the dot while
  `.connected`. Both effects suppressed under
  `accessibilityReduceMotion` so motion-sensitive users still get
  the static colour cue without the animation.
- **Hover halo on chat rows** — `MessageRow` gains a 4% primary
  overlay when hovering, layered above the existing
  highlight/mention/watch-hit background so loud rows still take
  precedence. Suppressed under reduce-motion.
- **Density-aware row padding wired in** — `MessageRow` now reads
  `chatDensity.rowPadding / 2` as the vertical padding baseline,
  with the existing `relaxedRowSpacing` toggle stacking on top so
  accessibility-conscious users can combine both. Compact ≈ 0.5 pt,
  Cozy ≈ 1.5 pt, Comfortable ≈ 3 pt.
- **Subtle gradient on the buffer header title** —
  `LinearGradient(.primary → .primary.opacity(0.7))` from top to
  bottom. Adds depth without compromising legibility on either
  light or dark themes.

### Changed

- `MessageRow` now consumes `Environment(\.accessibilityReduceMotion)`
  in two places (hover halo, animation). When new visual effects
  land, follow the same pattern.

## [1.0.100] — 2026-05-01

### Added (Phase 7 — Encrypted blob attachment store)

- **`BlobStore` actor (new file)** — encrypted file-attachment
  storage at `<supportDir>/blobs/<uuid>.bin`. Each payload sealed
  via the keystore-derived DEK through `EncryptedJSON.safeWrite`;
  metadata index at `blobs/index.json`. Mirrors the LogStore
  pattern (single off-main actor, set-key push, encrypted
  envelope). Init inlines the index load — calling actor-isolated
  `loadIndex()` from init triggers a Swift 6 isolation
  diagnostic.
- **`BlobStore.BlobRecord`** — Codable on-disk metadata (id,
  filename, contentType, sizeBytes, createdAt, attachedTo).
- **`BlobStore.AttachmentRef`** — lightweight (id, filename,
  contentType, sizeBytes) inlined on owners (`AddressEntry
  .attachments` today; future channels / messages later) so the
  editor renders lists without round-tripping through the store.
  The store is the source of truth for the bytes; inline refs
  are a denormalised view.
- **API surface**: `store(data:filename:contentType:attachedTo:)`,
  `store(fileURL:attachedTo:)` (auto-guesses MIME via UTType),
  `read(_:)`, `delete(_:)`, `writeToTempFile(_:)` (materialises
  to `~/tmp/PurpleIRC-blobs/` for Open / Reveal handoffs to
  NSWorkspace), `setEncryptionKey(_:)` (reloads index when
  key transitions).
- **Why a separate store rather than inline like profile photos?**
  Photos are tiny (~10 KB). Documents are routinely 5+ MB.
  Inlining 5 MB of base64 in `settings.json` forces every save
  to rewrite the whole encrypted envelope and every load to
  decrypt it. The blob store keeps `settings.json` small —
  only the metadata lives there — and pays the encrypt /
  decrypt cost only when the user opens the attachment.
- **`AddressEntry.attachments`** — new array; `decodeIfPresent`
  for backward compat.
- **`ChatModel.blobStore: BlobStore`** — initialised against the
  support directory; receives keystore-key pushes via the same
  `pushKeyToLogStore` path that feeds the seen / session-history /
  bot stores.
- **AddressEntryEditor → new "Attachments" section** between
  Contact and Notes:
  - "Attach file…" button (NSOpenPanel, multi-select, no type
    filter — any file is fair game).
  - Drop target accepting file URLs from Finder, routed through
    the same store path.
  - **`AttachmentRow`** view: SF Symbol icon resolved from MIME
    prefix (`image/*` → photo, `video/*` → film, `audio/*` →
    music.note, `text/*` → doc.text, `pdf` → doc.richtext, `zip`
    → archivebox, `json`/`xml` → curlybraces, otherwise → doc),
    filename + contentType + ByteCountFormatter size, three
    buttons: Open (NSWorkspace.open via temp file), Reveal
    (Finder reveal via temp file), Remove (drops both the inline
    ref AND the blob-store payload).
- **`/nuke` already covered** — `NukeService.wipeSupportDirectory`
  enumerated `blobs/` in its subtree list back in Phase 1
  (forward-compat), so attachments wipe cleanly with no
  NukeService change this round.

## [1.0.99] — 2026-05-01

### Added (Phase 6 — Address book profile photos)

- **`AddressEntry.photoData: Data?`** — optional inline JPEG bytes,
  decoded with `decodeIfPresent` for backward compat. Storage round-
  trips through the existing encrypted-settings envelope, so photos
  inherit the keystore-derived AES-GCM seal alongside contact notes.
- **`PhotoUtilities` module (new file)** — downscaling pipeline
  (`maxDimension = 256` px on the longest side, JPEG re-encode at
  quality 0.85), `loadDownscaled(from:)` / `downscaleAndEncode(_:)`
  helpers, `initials(for:)` (first alphanumeric, uppercased, "?"
  fallback), and `avatarTint(for:)` (deterministic Color from
  SHA-256 hash of the lowercased nick → palette of 11) so the
  same nick always lands on the same swatch.
- **`ContactAvatar` view** — single configuration knob (`size` in
  points). Renders the entry's photo when present (Image
  scaledToFill + Circle clip) or a tinted-gradient circle with
  the deterministic initial. Initials font auto-scales at ~46% of
  size; 0.5 px outer stroke at primary.opacity(0.08) for definition
  against any background.
- **`ContactAvatarByNick`** — convenience wrapper that resolves a
  nick against `settings.addressBook` (case-insensitive). When no
  match exists, synthesises an empty entry so the placeholder
  still renders the deterministic tint + initial. Nicks not yet
  in the address book share the visual identity.
- **AddressEntryEditor → new Photo section at top:** 72-pt avatar
  preview, "Choose photo…" button (NSOpenPanel filtered to `.image`),
  Remove button when one is set, plus a drop target accepting both
  `.image` (raw bitmap from another app) and `.fileURL` (Finder
  drag) — both resolve through PhotoUtilities so the inline
  storage invariant holds regardless of source.
- **Sidebar Contacts row** now leads with a 22-pt `ContactAvatar`
  overlaid with the existing presence dot in the bottom-right
  corner (haloed with a 1.5 px stroke against the control
  background so the dot reads against any avatar tint). Identity
  + presence both visible without enlarging the row.

## [1.0.98] — 2026-05-01

### Added (Phase 5 — Fonts: per-element slots + advanced typography)

- **`FontStyle` data model** (new file `FontStyle.swift`) — sparse
  Codable container with "inherit" sentinels on every field
  (empty `family`, zero `size`, `.inherit` weight, nil `italic` /
  `ligatures` / `tracking` / `lineHeightMultiple`). Walks an
  inheritance chain so a slot can override only what it cares about
  while everything else falls back to its parent.
- **`ResolvedFont`** — materialised concrete-value bag the renderer
  reads (family, size, weight, italic, ligaturesEnabled, tracking,
  lineHeightMultiple, plus `isBuiltInMonoToken` / `isBuiltInPropToken`
  flags so the SwiftUI Font factory routes to `.system(...)` vs
  `.custom(...)` correctly).
- **Four `FontSlot`s** on `AppSettings` — `chatBodyFont`, `nickFont`,
  `timestampFont`, `systemLineFont`, all defaulting to pure inherit
  so old `settings.json` files render unchanged. The chat-body slot
  inherits from the legacy `chatFontFamily` / `chatFontSize` /
  `boldChatText` fields.
- **`ChatModel.font(for: FontSlot) -> ResolvedFont`** — single resolver
  every renderer reads. `chatFont` now goes through it; `chatCaptionFont`
  honours the system-line slot and recomposes at 78% the slot's
  configured size.
- **`View.purpleFont(_:)` modifier** — applies SwiftUI Font + tracking
  + lineSpacing in one call so call sites don't reimplement the
  `(multiplier - 1.0) * size` line-spacing math.
- **`purpleText(_:_:)` helper** — wraps a string in an
  `AttributedString` with `.ligature = 0` when the resolved font has
  ligatures off, since SwiftUI's `Text` doesn't expose a ligature
  toggle on macOS.
- **`InstalledFonts` cache** — `NSFontManager.shared.availableFontFamilies`
  fetched once at first use, plus a monospaced-only subset filtered
  via `NSFontManager.traits(of:).contains(.fixedPitchFontMask)`.
- **`FontFamilyPickerSheet`** — searchable list of every installed
  family (~500 on a typical Mac), with a "Monospaced only" toggle
  (defaults ON when picking for the chat body). Each row renders the
  family name + "AaBb 123" sample in that family so users pick by
  visual feedback rather than guessing from PostScript names.
- **Fonts tab rebuilt** — three sections:
  - **Chat font (root)**: legacy enum picker + "Pick installed font…"
    button that overrides the enum at resolve time, plus a "Clear"
    affordance to drop back. Size slider, bold toggle, /font slash-
    command pointer.
  - **Chat body — advanced**: ligatures, tracking (-2 → +4 pt),
    line-height (0.8× → 2.0×), weight, italic.
  - **Per-element overrides**: collapsible DisclosureGroups for Nick /
    Timestamp / System-line slots. Each has its own family picker,
    size slider with an "inherit" sentinel at 0 pt, weight, italic,
    ligatures, tracking, and line-height. Everything inherits from
    the chat body unless overridden.

## [1.0.97] — 2026-05-01

### Added (Phase 4 — Theme system: UserTheme + per-event colors + WYSIWYG builder)

- **`UserTheme` model** in `SoundsAndThemes.swift` — Codable struct
  mirroring `Theme`'s shape with hex strings for every color slot,
  plus a sparse `kindOverrideHex: [String: String]` map keyed by
  `ChatLineKindTag.rawValue` for per-event overrides. `materialised`
  produces a runtime `Theme`; `kindOverridesMaterialised` produces
  the typed `[Tag: Color]` dict. `UserTheme.duplicate(of:name:)`
  snapshots a built-in or user theme as the starting point.
- **`ChatLineKindTag` enum** — 14 stable string tags (info, error,
  privmsg, privmsgSelf, action, notice, join, part, quit, nick,
  topic, raw, mention, watchlist) so per-event overrides survive
  Codable round-trips and rename-resilient over time.
- **`Theme.resolve(id:userThemes:)`** — built-ins win on id collision,
  then user themes by uuid, then `.classic` fallback.
- **`AppSettings.userThemes: [UserTheme]`** — persisted alongside
  `themeID`.
- **`ServerProfile.themeOverrideID: String?`** — per-network theme
  override, decoded with `decodeIfPresent` so old `settings.json`
  files don't fail.
- **`ChatModel.theme`** rewritten to consult
  `activeConnection.profile.themeOverrideID` first, then
  `settings.themeID`, both via the resolver.
- **`ChatModel.kindColor(for:)`** — overlay lookup; nil means
  "inherit", letting MessageRow fall back to the typed slot
  (`infoColor`, `joinColor`, etc.).
- **MessageRow rewired** — every kind (info, error, privmsg, action,
  notice, join, part, quit, nick, topic, raw, motd) reads
  `model.kindColor(for: tag) ?? theme.someColor`, so a UserTheme
  paints each event independently.
- **`ThemeBuilderView` (new file)** — WYSIWYG sheet with HSplitView:
  editor on the left (Theme name; Surface bg/fg; Per-event base
  palette; Backgrounds; 8-slot Nick palette; Per-event color
  overrides with + to add and ↺ to drop), live preview on the
  right (15 sample rows covering every kind a UserTheme can
  repaint, painted against the draft's `chatBackground` /
  `chatForeground`). Save / Save As / Delete / Export to
  `.purpletheme` JSON via `NSSavePanel`.
- **`ThemeImporter.importTheme(from:into:)`** — reads a `.purpletheme`
  file, decodes UserTheme, fresh-stamps UUID + createdAt so multiple
  imports don't collide, appends to `settings.userThemes`.
- **Themes tab rebuilt** — new "Custom themes" section above the
  built-in grids: per-row swatch tile, name + basedOn caption,
  Use / Edit / Duplicate / Delete affordances. Plus "+ New theme"
  (snapshots active theme and opens the builder) and "Import…"
  (NSOpenPanel → ThemeImporter).
- **ServerEditor → Theme override picker** — "Use global theme"
  sentinel, divided list of built-ins and user themes, persisted via
  `themeOverrideID`.
- **`/theme` command refactored** into a real subcommand parser:
  - `/theme` — list built-ins + user themes + show current
  - `/theme <id-or-name>` — switch (handles uuid prefix matching)
  - `/theme builder` (also `edit`, `new`) — open the WYSIWYG sheet
  - `/theme import <path>` — load a `.purpletheme` file
  - `/theme export <user-theme-name-or-id> <path>` — write to disk
- **`ChatModel.themeBuilderDraft` + `themeBuilderIsNew`** —
  `@Published` state surfaced by ContentView via
  `.sheet(item: $model.themeBuilderDraft)` so the slash command and
  the Setup tab share one presentation path.

## [1.0.96] — 2026-05-01

### Documentation

Captured Phases 1–3 in CHANGELOG / HANDOFF / README. No code change.

## [1.0.95] — 2026-05-01

### Changed (Phase 3 — Setup reorganization)

- **Setup sidebar regrouped into 6 sections × 20 tabs** (was 3 × 11),
  mirroring the macOS System Settings layout so adding more in later
  phases doesn't crowd anything:
  - **Connections** — Servers, Identities, Proxy & DCC *(new)*
  - **People & places** — Address Book, Channels, Ignore, Highlights
  - **Behavior** — Behavior, Notifications *(new)*, Logging *(new)*
  - **Personalization** — Appearance, Themes *(new)*, Fonts *(new)*,
    Sounds *(new)*
  - **Power-user** — Bot, PurpleBot, Assistant *(new)*,
    Shortcuts & Aliases *(new)*, Backup *(new)*
  - **Security** — Security
- **Behavior** trimmed to its functional core (Quit, Session restore,
  CTCP, Away) with a "where to find moved settings" pointer block.
- **Appearance** trimmed to meta-knobs (Timestamp, Density picker,
  Bold / Relaxed / Collapse toggles); a new Density picker is wired
  to `settings.chatDensity` and matches the View → Density submenu
  added in 1.0.94.
- **Notifications** consolidates every alert channel (sound / dock /
  banner) for watchlist hits and own-nick mentions into one tab,
  rather than scattering them across Behavior + Appearance + Highlights.
- **Logging** lifts persistent-log toggles, retention, and the legacy
  plaintext conversion path out of Behavior so a user worried about
  disk usage or compliance has one tab to audit.
- **Themes / Fonts / Sounds** promoted from sections to their own tabs
  so they have room to grow into the Theme Builder (Phase 4) and
  custom font picker (Phase 5).
- **Shortcuts & Aliases** is the home for `userAliases` (list / add /
  remove); ships with built-in keyboard-shortcut documentation, with
  user-customizable shortcuts deferred.
- **Backup** surfaces `BackupSettingsRow` + `FactoryResetRow` plus a
  pointer to the `/nuke` destructive reset.

## [1.0.94] — 2026-05-01

### Added (Phase 2 — Full macOS menu system)

- **8 native menus** replace the single "IRC" menu, each backed by a
  small private View struct so `App.body`'s `.commands` block stays
  scannable.
  - **File** — New Network… (⌘N), Close Buffer (⌘W), Export Current
    Buffer…, Export All Buffers…
  - **PurpleIRC** (after Settings…) — Lock Keystore (⇧⌘L), Reset
    Everything (NUKE)…
  - **Edit** (after Pasteboard) — Find in Buffer… (⌘F)
  - **View** — Show Raw Log toggle, Increase / Decrease / Reset Font
    Size (⌘= / ⌘- / ⌘0), Density submenu (Compact / Cozy /
    Comfortable), Theme submenu (every `Theme.all` entry, with a
    checkmark on the current selection)
  - **Buffer** — Next / Previous Buffer (⌘⌥→/←), Next / Previous
    Network (⌘⌥↓/↑), Mark All as Read (⌃⌘M), Clear Buffer
  - **Network** — Connect (⌘K), Disconnect (⇧⌘D), Reconnect (⇧⌘R),
    Channel List… (⇧⌘L), Watchlist… (⇧⌘A — moved from ⇧⌘W since
    that's the system "Close Window"), Watch Monitor… (⇧⌘M),
    DCC Transfers… (⇧⌘T), Seen Log…
  - **Conversation** — Join Channel… (⇧⌘J), Open Query… (⇧⌘Q),
    Set Topic…, Invite User…, WHOIS…, WHOWAS…
  - **Help** (after system Help) — Slash Command Reference… (⇧⌘?),
    App Diagnostic Log…, Chat Logs…
- **Menu state derives from live model state** (active connection
  presence, connection state, current buffer kind) so menu items
  reflect what's possible without manual refreshes.
- **Theme + Density submenus generate from `Theme.all` /
  `ChatDensity.allCases`**, so adding a theme picks up automatically.
- **Generic `InputPromptSheet`** backed by `ChatModel.inputPrompt`
  for menu-driven dialogs (Set Topic, Join Channel, Open Query,
  Invite, WHOIS, WHOWAS) — one sheet, many uses, instead of a forest
  of one-off modals.

### Added (model surface for menus)

- `ChatModel.reconnect()` → `IRCConnection.handleReconnectFromMenu()`
- `ChatModel.cycleNetwork(forward:)`
- `ChatModel.clearCurrentBuffer()`, `markAllReadEverywhere()`,
  `cycleBuffer(forward:)`
- `ChatModel.incrementFontSize()` / `decrementFontSize()` / `resetFontSize()`
- `ChatModel.setTheme(byID:)` / `setDensity(_:)`
- `ChatModel.requestInput(...)` wrapper around the new
  `InputPrompt` struct.

## [1.0.93] — 2026-05-01

### Added (Phase 1 — Slash command surface + `/nuke`)

- **`/nuke`** — two-step destructive reset. Routes through
  `NukeService` which disconnects every network, locks the keystore,
  wipes `settings.json` + `keystore.json` + every encrypted subtree
  (`channels/`, `history/`, `scripts/`, `seen/`, `logs/`, `downloads/`,
  `backups/`, `blobs/`, `photos/`, `app.log`), clears every Keychain
  item under `com.purpleirc`, then quits. Sanity rail refuses to run
  if `supportDirectoryURL` doesn't look like an Application Support /
  `.config` path. The confirmation sheet (`NukeConfirmationSheet`)
  enumerates exactly what will be wiped and disables the destructive
  button until the user types the literal phrase **NUKE**.
- **21 new model-level slash commands**: `/clear` (`/cls`), `/find`
  (`/search`), `/markread` (`/markallread`), `/next` (`/nextbuffer`),
  `/prev` (`/previous`, `/prevbuffer`), `/goto` (`/switch`),
  `/network`, `/theme`, `/font`, `/density`, `/zoom`, `/timestamp`
  (`/ts`), `/lock`, `/backup`, `/export`, `/alias`, `/repeat`,
  `/timer`, `/summary`, `/translate`.
- **11 new connection-level slash commands**: `/reconnect`, `/rejoin`
  (`/cycle`), `/invite`, `/knock`, `/motd`, `/lusers`, `/admin`,
  `/info`, `/version`, `/silence`, `/unsilence`.
- **User-defined aliases** (`AppSettings.userAliases`). Resolved
  *before* built-in commands so the user can shadow built-ins on
  purpose. Editable inline via `/alias <name> <expansion>` and
  `/alias -<name>`, or in the new Setup → Shortcuts & Aliases tab.
- **`ChatDensity` enum** (`.compact` / `.cozy` / `.comfortable`)
  with a `.cozy` default, plus an integrated row-padding
  multiplier consumed at draw time.
- **`AppSettings.viewZoom`** — 0.5–2.0 multiplier on top of the
  configured chat font size, switchable live with `/zoom`.

### Changed

- **`CommandCatalog` synced**. Every working command (the new ones
  plus the existing-but-hidden `/watch`, `/unwatch`, `/dcc`, `/log`,
  `/logs`, `/assist`, `/reloadbots`, etc.) is now an entry, so they
  show in `/`-autocomplete and the `/help` sheet. Categories grew
  from 8 to 15 (Connection, Channels, Messages, Identity, Moderation,
  User lookup, Server info, DCC, Window & buffer, Appearance, Logs,
  Bot, Automation, Dangerous, App) so the list stays scannable.
- **`BufferView` body extracted into a `BufferViewObservers` modifier**
  to keep Swift's "expression too complex" type-checker happy after
  `/find` and `/clear` bridges joined the existing focus-restore
  observers. Behaviourally identical.
- **`IRCConnection` gained four buffer helpers**: `clearBufferLines(id:)`,
  `markAllBuffersRead()`, `cycleBuffer(forward:)`, and
  `selectBufferByName(_:)` (exact > prefix > contains match).

## [1.0.92] — 2026-04-30

### Security

- **CRLF injection blocked at every outbound seam.** `IRCSanitize.field`
  scrubs CR / LF / NUL from script-supplied and AppleScript-supplied
  fields (`target`, `text`, `chan`, `reason`, `body`) before they reach
  the IRC line assembler, and `IRCSanitize.line` re-scrubs the assembled
  line at `IRCClient.send` as defence in depth. Without this, an
  AppleScript like `send message "hi\r\nQUIT :pwn" to "#x"` (or a
  PurpleBot `irc.msg(target, text)` with embedded newlines) could
  smuggle a second IRC command after the message body. Affected sites:
  `AppleScriptCommands.swift` (Send / Join / Part / Say), `BotHost.swift`
  (`irc.send`, `irc.sendActive`, `irc.msg`, `irc.notice`), and
  `IRCClient.send` / `IRCClient.sendSync`.
- **Credentials masked in raw log + AppLog.** `IRCSanitize.maskForDisplay`
  rewrites `PASS <pw>`, `AUTHENTICATE <b64>` (control markers `+` / `*`
  preserved), and `PRIVMSG NickServ :IDENTIFY [acct] <pw>` to `****` in
  both the outbound raw-log path and the inbound echo path (echo-message
  cap can replay our own IDENTIFY back to us). Wire bytes are unchanged.
- **DCC listener bound to the advertised IP.** The active-DCC listener
  (`DCC.swift`) used to bind `0.0.0.0`, letting any host that could
  route to the listening port race the legitimate peer to grab the
  file/chat. The listener now binds to the same IP we advertise in the
  `DCC SEND` / `DCC CHAT` offer, with a wildcard fallback only when the
  bind fails (LAN-only setups whose advertised address can't be bound).
- **DCC filename hardening.** `sanitizeFilename` now strips control
  bytes (≤0x1F + 0x7F) and `\` / `/` / `:`, collapses `..` segments,
  takes only the last path component, drops leading dots (hidden files),
  caps at 255 chars, and rejects collapse-to-empty / dot-only names
  with a `dcc-file` fallback.
- **POSIX `0600` perms on every encrypted-at-rest file.**
  `EncryptedJSON.safeWrite` and `KeyStore.persist` set owner-only file
  modes after the atomic write. The contents are already AES-GCM
  sealed when a DEK is in hand, but tightening the file mode protects
  unencrypted-mode users (whose JSON would otherwise inherit the
  user's umask, typically `0644`).
- **Full SHA-256 for the keystore Keychain account.** Previously
  truncated to a 6-byte (48-bit) prefix, which made colliding-path
  attacks plausible (~2²⁴ expected attempts). The Keychain account
  name is no longer length-constrained, so there's no reason to
  truncate.
- **PurpleBot script integrity hash.** `BotScript` now carries a
  `contentHash` (SHA-256 hex) captured at write time and verified
  before the source is handed to JavaScriptCore. Disk-tampered or
  partially-decrypted scripts surface as a script-log error instead of
  silently executing.
- **HTTP CONNECT proxy parser tightened.** Now requires a literal
  `HTTP/1.x` version line, a strict `200` status, refuses any
  `Content-Length: N` (`N > 0`) — which would smuggle bytes the tunnel
  would otherwise mistake for application data — and caps response
  headers at 16 KiB so a hostile proxy can't grow the accumulator
  forever.
- **SASL PLAIN AUTHENTICATE chunked at 400 bytes** (`SASLNegotiator
  .chunkedAuthenticate`). Long credentials would previously produce a
  single `AUTHENTICATE <b64>` line over the 512-byte IRC limit and
  silently fail SASL. Multi-chunk payloads end with `AUTHENTICATE +`
  per spec.
- **`IRCMessage.parse` rejects lines containing NUL.** Server-supplied
  nick / channel / target fields can no longer carry forbidden bytes
  into buffer keys or file slugs.

### Fixed

- **Reconnect Task lifecycle race.** The delayed reconnect now captures
  the connection's UUID and re-checks `Task.isCancelled`,
  `userInitiatedDisconnect`, and the connection state inside
  `MainActor.run`. Without this, a disconnect issued during the backoff
  sleep (or a manual reconnect that already started a new attempt)
  could trigger a phantom reconnect on top.
- **433 nick collision now bounded.** Capped at 4 retries with state
  reset on `001` welcome and on each fresh `connect()`. The previous
  loop appended `_` forever, eventually tripping `NICKLEN` and
  cascading 432/433 with no path to registration.
- **Watchlist alert dedupe window.** Per-nick `lastAlertAt` timestamp
  suppresses duplicate banners when MONITOR / ISON / observed-activity
  fire for the same sighting in the same instant. 3-second window;
  manual test alerts skip the gate.
- **`lastAwayReplyAt` no longer grows without bound.** Long-running
  connections in busy networks would otherwise accumulate one entry
  per unique sender forever. Entries older than the throttle window
  are pruned when the dict exceeds 1024 keys.
- **Restore-buffer selection is deterministic.** Replaces the
  fire-and-forget 800 ms Task that left a blank pane on screen when
  JOIN took longer than expected. The desired buffer name is captured
  in `pendingRestoreSelectName` and `indexOfOrCreateBuffer` resolves it
  the moment a matching buffer materializes.
- **`closeBuffer` selects the next buffer before mutating the array.**
  Eliminates the one-frame placeholder render that used to flash when
  closing the active buffer.
- **`SessionHistoryStore.load` trims each buffer to `linesPerBuffer`
  immediately after decode.** Defensive against a tampered or bloated
  history file blowing up memory at restore time.
- **BATCH bracket safety.** `openBatches` is capped at 256 entries
  (warns + evicts oldest beyond that), duplicate `+id` overwrites log
  a warning, and the dict (plus `chatHistoryFetched`) clears on
  disconnect / failed so reconnects don't see ghosts.
- **IRCv3 dangling backslash preserved.** A tag value ending in `\`
  is malformed per spec; preserving the backslash makes a buggy
  server's behaviour visible instead of silently truncating the
  value.

### Changed

- **Buffer scrollback (`5000` lines) emits a one-shot info notice on
  first overflow.** No longer silent; the user sees `— Scrollback
  exceeded 5000 lines; older history is being trimmed —` once per
  buffer per session.
- **Message-box focus is restored on every modal-sheet dismissal.**
  Sheet dismissal doesn't fire `NSWindow.didBecomeKey` (the same
  window stays key), so the existing app-activate / window-activate
  refocus path missed it. Added `.onChange(of:)` handlers for
  `model.showSetup` / `showHelp` / `showWatchlist` / `showDCC` /
  `showChannelList` / `showSeenList` / `showRawLog` / `showAppLog` /
  `showChatLogs` and the local multi-line editor sheet, plus a
  `refocusInput()` call when the Find bar closes. App-activate,
  window-activate, buffer-switch, and scene-phase paths were already
  wired correctly.

### Verified — no change required

These items were flagged in the security/correctness review but turned
out to be already correct on inspection; recorded here so future
reviews don't re-litigate them.

- TLS validation: `NWParameters(tls: .init())` enables certificate
  and hostname validation by default on Apple platforms; no
  override is in effect.
- Per-connection Combine subscribers: the `IRCConnection` instance
  persists across disconnect/reconnect, and its subscribers are
  intentionally long-lived. `removeConnection` releases everything
  together.
- Highlight + trigger regex validation: `HighlightRuleEditor` and
  `TriggerRuleEditor` already display compile errors inline as
  orange caption text under the field.
- Proxy credentials: `proxyPassword` already routes through the
  `persistCredentials` Keychain-backed pipeline.
- SOCKS5 user/pass length: `sendSOCKS5UserPass` and
  `sendSOCKS5Connect` already enforce the 255-byte field limit and
  `fail()` gracefully on overflow.

### Tests

164 tests across 12 suites all pass (`swift test` / `./run-tests.sh`).
The build (`./build-app.sh`) produces `PurpleIRC.app` bundled with the
git-derived version stamps in Info.plist.
