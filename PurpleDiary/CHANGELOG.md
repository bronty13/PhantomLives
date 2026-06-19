# Changelog

All notable changes to PurpleDiary are documented here. Versions are
git-derived (`1.0.<commit-count>`), matching what the built app reports.

## [1.0.1012] — 2026-06-19 — Formal releases: notarized DMG (no auto-update, by design)

### Added
- **A real release pipeline — `Scripts/release.sh` + `RELEASING.md`.** PurpleDiary
  can now be cut as a notarized, stapled **`.dmg`** attached to a tagged GitHub
  release (`purplediary-v<version>`), instead of being source-only / build-from-
  checkout. One command: build → notarize+staple the app → build the drag-to-
  Applications DMG → notarize+staple the DMG → `gh release create`. Version stays
  git-derived (`1.0.<commit-count>`); the script refuses a dirty/unpushed tree and
  won't clobber an existing tag.
  - **Two notarization passes on purpose.** The app is stapled *before* it's
    sealed into the read-only DMG, and the DMG is stapled after — so a downloaded
    app is Gatekeeper-clean **offline** even after the user drags it out of the
    DMG (you can only staple a writable bundle). Both artifacts are proven with
    `stapler validate` + an `spctl` assessment; a broken notarization fails the
    release loudly.
  - Reuses the shared PhantomLives signing identity (`Developer ID Application:
    Robert Olen`) and the shared `PurpleDedup-Notary` notary profile — no
    PurpleDiary-specific credential setup.

### Deliberately NOT added
- **No Sparkle / no in-app auto-update.** Sparkle polls an `appcast.xml` over
  HTTPS — that is the exact "update-check" network egress PurpleDiary forbids
  (HANDOFF §6; the same constraint that got WeatherKit reverted). Keeping releases
  download-only is what lets "PurpleDiary makes no network requests" stay
  *literally* true. Updating is: download the newer DMG and re-drag. `RELEASING.md`
  records this reasoning so the constraint isn't quietly bolted over later.

### Docs
- New `RELEASING.md` (one-time per-Mac setup, the run steps, env knobs, the
  no-Sparkle rationale, troubleshooting). README gains a **Releases / install**
  section pointing at the GitHub releases page alongside build-from-source.
- Tests unchanged and green (**156/156**) — this change is build/release tooling
  only; no app code or migrations touched.

## [1.0.588] — 2026-06-01 — Vault hardening + changelog versioning

### Changed
- **A vault now refuses to fall back to plaintext if sealing ever fails.**
  `VaultService.seal` / `sealData` previously returned the *unencrypted*
  title / body / attachment bytes when AES-GCM encryption failed, which would
  silently write cleartext into a vault. They now `throw VaultError.sealFailed`
  and the surrounding write aborts instead — a vault can never persist
  plaintext. The failure path is near-unreachable with CryptoKit on a valid
  key, so this is defense-in-depth, not a fix for an observed leak.
- **The changelog is now versioned.** Every prior section was stacked under a
  single rolling `[Unreleased]` heading; each is now stamped with the
  git-derived version (`1.0.<commit-count>`) and the date it shipped, so a given
  build maps to its notes. No content changed — only the headings.

### Docs
- HANDOFF "last updated" line refreshed to the shipped Phase-9 state; README now
  documents the **Read from file…** recovery-key affordance (already in the
  USER_MANUAL).
- Tests unchanged and green (**156/156**); the existing vault round-trip tests
  now exercise the throwing `seal` / `sealData` signatures.

## [1.0.578] — 2026-06-01 — Vault & recovery: paste-back-tolerant key entry

### Added
- **Read from file…** on both recovery-key fields (vault unlock + app recovery
  screen). Pick the recovery-key file you saved and PurpleDiary loads it straight
  into the field (defaults to `~/Downloads/PurpleDiary/`); the BIP39 extraction
  above pulls the 24 words out of it. So the full loop is now click-only: Make
  Vault → Save to file… → later, Forgot passphrase? → Read from file… → Unlock.

### Fixed
- **Pasting a saved recovery-key file back now works.** The recovery-key fields
  (vault unlock *and* the app-level recovery screen) previously needed exactly 24
  bare space-separated words, so pasting back a **Save to file…** export — which
  is numbered (`1. word`) and wrapped in prose — wasn't recognized as the 24
  words. New `RecoveryKey.candidatePhrases(in:)` tokenizes arbitrary text,
  ignores numbering/punctuation, keeps only BIP39 words, and returns every
  contiguous 24-word window whose checksum passes; the unlock fields try each.
  You can now paste the whole saved file, a numbered list, or a clean line — all
  of them unlock. The fields show a "✓ recovery key detected" affordance.
- **+4 tests** (`RecoveryKeyTests`): candidate extraction from a clean line, a
  numbered list, the full saved-file format (prose header + numbered words), and
  rejection of garbage → **156**.

## [1.0.575] — 2026-06-01 — Phase 9: Vault (attachment sealing — vault is now complete)

### Added
- **Vaults now seal attachment bytes too.** A vault entry's photo / video / audio
  `data` and `thumbnail_data` BLOBs are sealed under the journal's content key
  (AES-256-GCM, raw-bytes `pdvlt1:` prefix) — ciphertext on disk just like the
  title and body, transparently decrypted on read while the vault is unlocked.
  Adding media to a *locked* vault is refused rather than written in the clear.
- **Sealing follows the entry through every path.** Converting a journal to a
  vault seals its existing attachments; removing the vault decrypts them in place;
  moving an entry into or out of a vault re-keys its attachment blobs in both
  directions (alongside the title/body re-key already in place).
- **+4 tests** (`VaultAttachmentTests`): insert seals blobs + read decrypts,
  insert-into-locked refused, convert seals existing attachments + remove unseals,
  move-into-vault seals / move-out unseals → **152**.

### Notes
- This closes the Phase-9 vault: titles, bodies, **and** attachment bytes are all
  sealed. Metadata that stays queryable under the single DB key (entry date, mood,
  word count, tags; attachment filename / MIME / dimensions / size) is documented
  in `Docs/SECURITY.md` — a vault hides content, not the existence or rough size
  of entries.

## [1.0.574] — 2026-06-01 — Phase 9: Vault (create / unlock / manage)

### Added
- **Vault journals — the feature is now usable.** Right-click a journal →
  **Make Vault…** to seal its entries under a passphrase of your own. The flow
  takes a passphrase (with confirm) and shows a **freshly-generated 24-word
  recovery key for this vault** in a readable grid — **Copy to clipboard** and
  **Save to file…** (to `~/Downloads/PurpleDiary/`), with a confirm checkbox — so
  a forgotten passphrase is never permanent lockout. Each vault has its own
  independent recovery key (not the app's master key). Even with PurpleDiary open,
  a vault's entries are ciphertext on disk until you unlock it for the session.
- **Unlock / lock from the sidebar.** A locked vault shows a 🛡️ lock glyph;
  clicking it opens a passphrase prompt (with a **Forgot passphrase?** → 24-word
  recovery key path). The context menu adds **Lock Vault Now**, **Change Vault
  Passphrase…**, and **Remove Vault…** (decrypt-in-place back to normal storage).
- **App-lock re-seals vaults.** Locking the app (⌘L / losing focus) now drops all
  vault session keys and session-unlocked hidden journals, so unlocking the app
  doesn't silently reveal a vault.
- **All-or-nothing creation guardrail.** `createVault` verifies both the
  passphrase wrap *and* the recovery wrap unwrap back to the content key before
  persisting the envelope or sealing any entry — a vault you can't reopen is never
  created.
- **+6 tests** (`VaultManagementTests`): create leaves it unlocked + openable both
  ways, make-vault seals existing entries, change-passphrase re-wraps only the
  passphrase side (recovery untouched) + requires unlocked, remove-vault decrypts
  in place + requires unlocked → **148**.

### Changed
- **Docs:** `USER_MANUAL.md` gains a "Vault journals" section + an export note;
  `Docs/SECURITY.md` documents the vault threat model (per-journal CK, dual-wrap,
  session-only key, export/visibility gating, v1 seals title+body not attachments)
  and downgrades the "hidden = visibility only" caveat to point at vaults.

## [1.0.573] — 2026-05-31 — Phase 9: Vault (transparent sealing data path)

### Added (internal — still no UI; foundation for the create/unlock flows)
- **Transparent seal-on-write / unseal-on-read.** `DatabaseService` now seals a
  vault journal's entry **title + body** under its content key before the row
  touches disk, and unseals transparently on fetch when the vault is unlocked
  for the session. On disk a vault entry is `pdvlt1:`-prefixed ciphertext (the
  plaintext and even the title never appear); in memory it reads back normally.
  Word counts are computed from the plaintext *before* sealing, so stats stay
  correct. A write into a **locked** vault is refused (`VaultWriteError`) rather
  than persisting plaintext.
- **Locked-vault visibility gate.** `AppState.visibleEntries` now treats a vault
  journal as hidden whenever its key isn't in the session, so locked vault
  entries are excluded from Timeline / Calendar / Search / Insights — and from
  **export** (export now runs over `visibleEntries`, so a locked vault never
  leaks ciphertext and an unlocked one exports as plaintext).
- **Vault-aware journal moves.** Moving an entry into a vault seals it on the way
  in; moving it out unseals it; cross-vault re-keying is handled. Moving into or
  out of a *locked* vault is refused.
- **`sealEntries(inJournal:using:)`** — the data-layer step the upcoming
  Make-Vault flow uses to seal a journal's existing plaintext entries in one
  transaction (idempotent; already-sealed rows are skipped).
- **+7 tests** (seal-on-disk / unseal-on-read, stays-sealed-when-locked,
  refuse-write-to-locked, move-in-seals / move-out-unseals, refuse-move-into-locked,
  convert-existing-plaintext + no-op re-run, visibility gate) → **142**.

### Notes
- Still **no Make-Vault / unlock UI** — no journal is a vault yet in normal use,
  so this remains behavior-neutral for existing installs. The create/unlock
  flows and sidebar lock glyph are the next step, built on this tested data path.

## [1.0.572] — 2026-05-31 — Phase 9: Vault (cryptographic foundation)

### Added (internal — no behavior change yet)
- **Vault cryptographic core.** Lays the groundwork for per-journal sealed
  journals: a journal can carry an `is_vault` flag and a `vault_envelopes` row
  holding a random 256-bit content key (CK) wrapped two ways — under a
  **passphrase-derived KEK** and under the **24-word recovery key** — so a vault
  journal's text can be ciphertext even with the database open, yet stays
  recoverable if the passphrase is lost. `VaultService` provides the verified
  primitives: `makeEnvelope` (dual-wrap), `unwrap` (by passphrase / recovery),
  `seal`/`unseal` (AES-256-GCM with a `pdvlt1:` sentinel), and a session-only
  unlocked-key store. New `v6_vault` migration (append-only; frozen-set guard
  updated).

### Notes
- This is the **cryptographic foundation only** — there is no UI and no entry is
  sealed yet. The transparent data-path sealing (encrypt/decrypt vault entry text
  on write/read), the Make-Vault / unlock flows, export-skips-locked, and
  app-lock integration are the next focused step, built on this tested core.
  **+7 tests** (passphrase + recovery unwrap, wrong-key rejection, seal/unseal
  round-trip + wrong-key, envelope DB round-trip, session unlock/lock) → 135.

## [1.0.571] — 2026-05-31 — Inline media in entries

### Added
- **Place media inside the body, with a caption and text before/after.** Any
  attachment (photo, video, audio, PDF, file) can now be embedded *within* the
  entry text using a Markdown ref `![caption](pd-attachment://<id>)`. In **Write**
  mode it's plain text you can move or recaption; in **Preview** the media renders
  in place (photo image, video poster + ▶, audio/PDF/file as a labeled tile),
  tappable to open the full viewer. The same attachment still appears in the strip
  for management.
- **Insert into text.** Right-click any attachment in the Media strip →
  **Insert into entry text** drops its ref at the end of the body (reposition or
  caption it in Write). Works for every media kind, including filesystem audio.

### Changed
- **Day One import now keeps the story.** Day One interleaves photos with the
  prose describing them. Instead of stripping those inline refs (which lost the
  placement), import now **rewrites each `dayone-moment://…` ref into an inline
  attachment ref at its original position**, preserving the caption and the text
  before/after. Refs whose media can't be found fall back to a readable marker
  (📷/🎬/🎵/📄) so nothing breaks.

### Notes
- New `InlineMedia` (ref + segment parser + Day One rewrite) and `InlineMediaView`
  (in-place rendering). `MarkdownEditor` preview now renders inline segments;
  `DatabaseService.attachmentThumb(id:)` backs it. **+7 tests** (ref/scheme,
  segment parse incl. consecutive/plain, Day One rewrite map + marker fallback,
  end-to-end Day One inline import) → 128 total.

## [1.0.570] — 2026-05-31 — Fixes: Day One media import + delete-journal choice

### Fixed
- **Day One import now brings in photos & videos.** Day One stores media in
  sibling folders (`photos/`, `videos/`, `audios/`, `pdfs/`) next to
  `Journal.json`, referenced by each entry. Import now resolves those files
  (by `<md5>.<type>`) and attaches them to the imported entries. Point the
  importer at the **extracted** `Journal.json` so the folders sit alongside it.
- **Deleting a journal no longer silently dumps its entries into "Journal".**
  Deleting a non-empty journal now asks: **Move N entries to "Journal"** (the old
  no-data-loss behavior) or **Delete journal and its N entries** (clean removal,
  e.g. after a throwaway test import). Empty journals delete with one confirm.

### Notes
- `DatabaseService.deleteJournal(id:deleteEntries:)` (cascades to
  tags/trackers/attachments); sidebar uses a confirmation dialog.
  `ImportService` gains a file-URL parse path + media resolution; `apply` is now
  async (imports media via `FileImportService`). **+2 tests** (Day One media
  resolve→import; delete-with-entries) → 122 total.

## [1.0.568] — 2026-05-31 — Phase 8: Importers

### Added
- **Import journals** from JSON (File → **Import Journal…**, ⇧⌘I). Four sources:
  - **PurpleDiary** — round-trips our own schema-v4 export: entries return to
    their original journals, with mood and tags. (Trackers, people links, and
    attachments aren't in the JSON export, so they don't round-trip.)
  - **Day One**, **Journey**, **Diarium** — parsed from each app's documented
    JSON entry shape into a journal named for the source. Extract the export's
    `.zip` first and pick the `.json`.
- The import sheet auto-detects the format (or pick it), and reports how many
  entries were added. Import is **additive** — fresh ids, nothing overwritten;
  tags are de-duplicated by name.

### Notes
- New `ImportService` (pure per-format parsers → a normalized bundle; `apply`
  inserts via `DatabaseService`) and `ImportSheet`. No migration. **+6 tests**
  (PurpleDiary export→parse round-trip preserving journals/mood/tags; additive
  apply; Day One / Journey / Diarium synthetic-sample parsers; garbage→throws).
  120 total. Third-party parsers are verified against synthetic samples —
  confirm with a real export.

## [1.0.567] — 2026-05-31 — Phase 7: PDF & file attachments

### Added
- **PDF attachments.** "Add from Files…" now accepts **PDFs** — stored as
  encrypted BLOBs with a first-page thumbnail, and viewed in-app with a real
  PDFKit reader (scroll, zoom). The caption shows the page count.
- **Any-file attachments.** You can now attach **any file** (a `.pages` doc, a
  `.zip`, a ticket — anything). Non-previewable files show a doc icon with the
  name and size; **Save a Copy…** writes the original back out to open elsewhere.

### Changed
- The Media row's "Add from Files…" picker now allows images, video, audio,
  PDFs, and any other file. The strip badges each kind with the right glyph.

### Deferred
- **Drawing/sketch entries** (originally roadmapped for this phase) are **not**
  shipped: PencilKit is iPad-centric and a poor fit for a native (non-Catalyst)
  macOS app, and mouse-drawing is weak. Can revisit with a custom canvas if
  wanted; for now you can draw elsewhere and attach the image/PDF.

### Notes
- New `PDFProcessing` (PDFKit first-page thumbnail + page count) and
  `PDFKitView`. `FileImportService` classifies `.pdf`/`.file`; `Attachment` gains
  `isPDF`/`isFile`. No migration — PDFs/files reuse the `attachments` table.
  **+2 tests** (classify pdf/file, generic-file verbatim, PDF thumbnail/pagecount,
  unreadable→nil). 114 total.

## [1.0.566] — 2026-05-31 — Phase 6: Calendar heatmap + daily reminder

### Added
- **Calendar heatmap.** Calendar days are now shaded by how much you wrote that
  day (five intensity levels in the accent color), instead of a single dot. Days
  with multiple entries show the count; today keeps an accent ring; a small
  Less→More legend sits under the grid. Hover a day for its entry/word counts.
- **Daily reminder.** An opt-in **local** notification nudges you to journal at a
  time you choose (Settings → **Reminders**). It's a repeating on-device
  notification — no account, no network — and authorization is requested only
  when you switch it on.

### Notes
- New `CalendarHeatmap` (pure level/opacity buckets) and `NotificationService`
  (`UNUserNotificationCenter` daily trigger; gentle weekday-rotated copy).
  `AppSettings` gains `reminderEnabled` / `reminderHour` / `reminderMinute`; the
  reminder is re-synced with the OS on every launch. **+4 tests** (heatmap
  levels + monotonic opacity; reminder time clamping + deterministic body).
  112 total.

## [1.0.565] — 2026-05-31 — Phase 5: Templates

### Added
- **Entry templates.** Reusable scaffolds for entries. The toolbar **New Entry**
  button is now a split menu: its arrow lists your templates ("From template"),
  plus **Blank Entry** and **Manage Templates…**. Starting an entry from a
  template fills the body with its scaffold, substituting date/time tokens —
  `{{date}}`, `{{date_long}}`, `{{time}}`, `{{weekday}}`, `{{year}}` — for the
  entry's date.
- **Manage Templates** sheet (master list + body editor) to create, rename,
  edit, and delete templates.
- Two starter templates seeded on first run (Daily check-in, Gratitude).

### Notes
- New `Template` model + `v5_templates` migration (append-only; frozen-set guard
  updated). New `TemplateService.render` (pure token substitution) and
  `TemplatesSheet`. New entries land in the active journal, same as a blank one.
  **+6 tests** (token render: substitute / case-insensitive / unknown-left-alone;
  CRUD; seed; Codable). 108 total.

## [1.0.564] — 2026-05-31 — Phase 4: Reflection (On This Day + writing prompts)

### Added
- **On This Day.** A new sidebar section surfaces entries you wrote on today's
  date in previous years, grouped by "N years ago," newest first. Purely a local
  look-back over your own journal — nothing is fetched. Respects the active
  journal + hidden-journal filter; tap an entry to jump to it.
- **Writing prompts.** When an entry's body is empty, the editor shows a gentle
  prompt card (✨) drawn from a **bundled** library of ~48 prompts across
  categories (reflection, gratitude, memory, growth, …). The prompt is stable for
  the day; **Use** drops it into the body as a quote to write under, and the
  shuffle button cycles to another. Prompts ship in the app — no network, nothing
  generated.

### Notes
- New `PromptService` (bundled `Resources/Prompts.json` + deterministic daily
  rotation) and `OnThisDayService` (pure month/day matching). New
  `Section.onThisDay` + `OnThisDayView`. **+7 tests** (prompt index wrap /
  stability / advance / cycle / bundled-file decodes; On-This-Day matching +
  years-ago label). 102 total.

## [1.0.563] — 2026-05-31 — Phase 3: Journals (multiple + hidden)

### Added
- **Multiple journals.** A new **JOURNALS** section in the sidebar lets you keep
  separate notebooks (Personal, Work, Travel, …). Each entry belongs to one
  journal; pick **All Journals** to see everything or a single journal to focus.
  Create with the **＋**, and right-click a journal to rename, recolor, hide, or
  delete (deleting moves its entries back to the default journal — nothing is
  lost). New entries land in the journal you're currently viewing.
- **Hidden journals.** Mark a journal **Hidden** to lock it out of the Timeline,
  Calendar, Search, and Insights. A hidden journal shows a 🔒 in the sidebar;
  click it and authenticate (Touch ID / device password / passphrase) to reveal
  it **for the session** — it re-locks on relaunch.
- **Move an entry between journals** from a menu in the entry editor header.

### Changed
- New `v4_journals` migration: a `journals` table, a seeded default journal, and
  a back-filled `entries.journal_id`. Append-only — `v1…v3` stay frozen; the
  immutability guard now expects `[…, "v4_journals"]`.
- Export JSON bumps to **`schemaVersion: 4`** with a top-level `journals` array
  and a per-entry `journalId` (full-fidelity, including hidden journals, for
  backup/re-import).

### Security note
- At this phase "hidden" is an **app-level visibility gate** — a hidden journal's
  bytes are still under the single database key, exactly as encrypted as
  everything else, and a full export includes them. Per-journal *cryptographic*
  separation (a journal sealed under its own passphrase, opaque even with the
  app open) is a later phase — see `SCOPING.md` → Phase 9 (Vault).

### Notes
- New `Journal` model + `AppState` journal slices / `visibleEntries` /
  `entryIsVisible` predicate. **+8 tests** (default journal, back-fill,
  move, delete-reassign, can't-delete-default, visibility gate + selection,
  Codable). 95 total.

## [1.0.562] — 2026-05-31 — Phase 2: Import text files into an entry

### Added
- **Import a text file into the entry body.** The Markdown editor's toolbar gains
  an **"Import…"** button that opens a Markdown / plain-text / RTF file and merges
  its contents into the current entry's body. RTF is flattened to plain text. The
  merge is *smart*: an empty body is set to the file's contents; a body that
  already has text gets the file appended after a `---` separator (existing text
  is never overwritten). Unlike "Add from Files…" (which attaches media), this
  brings the text **into the entry itself**.

### Notes
- New `TextImportService` (read Markdown/text/RTF + the pure `mergedBody` rule);
  the button lives in `MarkdownEditor`. Build-verified; **+6 tests** (merge rule
  + Markdown/plain-text/RTF reading).

## [1.0.560] — 2026-05-31 — Phase 2: Discard never-filled-in entries

### Changed
- **A new entry you never fill in is silently discarded.** ⌘N still inserts an
  entry immediately (so it shows in the timeline and the editor can bind to it),
  but on leaving the editor — switching entries, changing sections, or closing —
  an entry that is *completely empty* (blank title **and** body, no mood, no
  tags, no logged trackers, no attachments) is deleted instead of saved. No
  "discard?" prompt — zero friction. The bar is strict, so an entry with any
  content (even just a photo or a mood) is always kept.

### Notes
- New `AppState.entryIsEmpty(…)` (pure predicate) + `discardEntryIfEmpty(…)`;
  `EntryEditorView.onDisappear` runs `leaveEditor()` (discard-if-empty, else
  persist). **+5 tests** over the empty/non-empty predicate. Pre-existing blank
  entries are not swept automatically — this prevents new accumulation.

## [1.0.559] — 2026-05-31 — Phase 2: Audio attachments

### Added
- **Add audio from Files.** The **"Add from Files…"** picker now accepts **audio**
  (mp3, m4a, wav, aiff, …) alongside photos and videos. Audio is stored
  byte-for-byte as an encrypted BLOB inside `diary.sqlite`, like video.
- **Audio playback in the viewer.** Click an audio attachment to open a compact
  player — a waveform card, play/pause (Space), a draggable scrubber, and
  elapsed/remaining time (`AudioPlayerView`, AVKit-backed). Audio thumbnails in
  the strip show a music-note glyph with a ▶ badge (audio has no visual frame).

### Changed
- The editor media section is now labelled **"Media"** (photos, video, **and
  audio**). `Attachment`/`AttachmentThumb` gain `isAudio`; `FileImportService`
  classifies audio and stores it verbatim (no thumbnail). **No new migration** —
  audio is an `attachments` row with `kind = "audio"`.

### Notes
- Build-verified; **76/76 tests** (audio content-type classification + verbatim
  audio-from-file import added). Audio playback verified by hand (AVKit).

## [1.0.558] — 2026-05-31 — Phase 2: Browse-any-day photos, filesystem import, media viewer

### Added
- **Browse beyond the entry's day in the Photos picker.** "Add from Photos"
  (renamed from "Add photos from this day") now has a **date picker** (defaults
  to the entry's date) so you can pull in photos from any day, plus a **"Show all
  recent"** checkbox that browses the most recent photos across your whole
  library (capped at 300, newest first) ignoring the date.
- **Add photos and videos from Files.** A new **"Add from Files…"** button opens
  a standard file panel for images **and videos**. Images are downscaled to JPEG
  like the Photos path; **videos are stored byte-for-byte** as encrypted BLOBs
  with an auto-generated poster-frame thumbnail. No new entitlement (user-chosen
  files; the app stays non-sandboxed). The editor section is now **"Photos &
  Video"**.
- **Full-size viewer.** Click any thumbnail in the strip to open it: a
  fit-to-window image for photos, or an **AVKit player** for video (video
  thumbnails get a ▶ badge). The viewer has a **"Save a Copy…"** action to write
  the original bytes back to disk.

### Changed
- `AttachmentThumb` now carries `kind` + `mimeType` (so the strip can badge video
  and the viewer can choose image-vs-player without loading the BLOB); new
  `DatabaseService.attachment(id:)` fetches one full row for the viewer. **No new
  migration** — videos reuse the existing `attachments` table as `kind = "video"`
  rows, so the frozen migration set is unchanged.
- Export wording generalized: the per-entry count line now reads
  `🖼️ N attachments` (it counts photos **and** videos). The JSON schema is
  unchanged (`attachmentCount` was already generic).

### Notes
- New `FileImportService` (content-type classification + attachment building) and
  `VideoProcessing` (AVFoundation poster frame + dimensions). New
  `AttachmentViewerSheet`.
- Tests: thumb projection carries kind/mime, fetch-by-id round-trip, filesystem
  classification (image/video/unsupported), and image-from-file import. Video
  poster decoding is verified by hand (needs a real movie + AVFoundation),
  consistent with the live PhotoKit import.

## [1.0.556] — 2026-05-31 — Phase 2: Photos import (auto-assembled day)

### Added
- **Photos import** — the first "auto-assembled day" feature. The entry editor
  gains a **Photos** row with **"Add photos from this day"**, which (after a
  one-time Photos permission grant) shows the photos you took on that entry's
  date as a selectable grid; the ones you pick are attached to the entry.
  Attached photos show as a removable thumbnail strip.
- **Encrypted-at-rest attachments.** Imported photos are downscaled (≤2048px
  JPEG) and stored as **BLOBs inside `diary.sqlite`**, so they inherit the
  database's SQLCipher encryption and ride along in the backup zip — there are
  no separate plaintext image files. A small JPEG thumbnail is stored alongside.
  Imports are deduped against the originating `PHAsset` so the same photo isn't
  added twice.
- New `v3_attachments` migration (`attachments` table, `ON DELETE CASCADE` with
  its entry). Append-only — `v1_initial`/`v2_trackers` stay frozen; the
  immutability guard now expects `["v1_initial","v2_trackers","v3_attachments"]`.
- New `Attachment` model, `ImageProcessing` (downscale + thumbnail), and
  `PhotosImportService` (PhotoKit authorization + fetch-by-date + import).
- **Export** now notes photos: JSON bumps to **`schemaVersion: 3`** with a
  per-entry `attachmentCount`; Markdown/HTML show a `🖼️ N photos` line. (Export
  references counts, not the image bytes — those stay encrypted in the DB.)
- `Info.plist` gains `NSPhotoLibraryUsageDescription`. The app stays
  non-sandboxed; no new entitlement required.

### Notes
- Build-verified on macOS: clean Developer-ID Release build; **70/70 tests**
  (64 prior + attachment migration/cascade, attachment CRUD/count/dedupe, and
  four `ImageProcessing` resize tests; the JSON export test now asserts the v3
  `attachmentCount`). The `v3_attachments` migration applied cleanly to the
  existing encrypted database. The editor Photos row and the suggestion sheet
  render; the live PhotoKit grant + import is completed interactively (the macOS
  Photos prompt only surfaces for a user-launched app, not an automation-launched
  one) — see the SECURITY.md update documenting attachments as encrypted BLOBs.

## [1.0.555] — 2026-05-31 — Phase 2: Tracker tags + graphs

### Added
- **Trackers** — define your own quantified metrics (cups of water, hours of
  sleep, "did I exercise?") and log them per entry, then watch the trend in
  Insights. Three kinds: **Number** (with an optional unit), **Duration**
  (minutes, shown as `1h 30m`), and **Yes / No**.
  - New **Trackers** sidebar section to define/recolor/delete metrics.
  - The **entry editor** gains a Trackers row: a numeric field for
    number/duration trackers and a three-state **— / No / Yes** picker for
    booleans. Clearing a field un-logs that tracker for the entry (so an
    un-logged tracker is never silently recorded as zero).
  - **Insights** draws one line chart per tracker that has data — daily-average
    value over time, in the tracker's own color (booleans pinned to a 0…1 axis).
- New `v2_trackers` migration (`tracker_tags` + `tracker_values`, with
  `ON DELETE CASCADE` on both the entry and the tracker definition). Appended,
  not edited — `v1_initial` stays frozen (the immutability guard now expects
  `["v1_initial", "v2_trackers"]`).
- `StatsService.trackerSeries(...)` — pure daily-average time series for a
  tracker (multiple same-day entries are averaged to one point).
- **Export** now includes trackers. The JSON export bumps to
  **`schemaVersion: 2`** with a top-level `trackers` array (definitions) and a
  per-entry `trackers` list of `{tracker, value}`; the Markdown and HTML exports
  show each entry's logged values on a `📊` line.

### Notes
- Build-verified on macOS: clean Developer-ID Release build; **64/64 tests**
  (60 prior + tracker migration/cascade, `TrackerKind` formatting, `TrackerTag`
  Codable round-trip, and `trackerSeries` daily-average ordering; the JSON
  export test now asserts the v2 tracker payload). The `v2_trackers` migration
  applied cleanly to the existing encrypted database, and the full
  define → log → graph flow was exercised in the running app (a "Sleep" tracker
  defined, logged on an entry, and rendered as a point on its Insights chart),
  then removed.

## [1.0.554] — 2026-05-30 — Phase 2: Export (Markdown / HTML / PDF / JSON)

### Added
- **Whole-journal export** in four formats, via **File → Export Journal… (⇧⌘E)**
  and **Settings → General → Export**:
  - **Markdown** — one document, entries grouped by year → month, each with a
    metadata line (date · mood stars · #tags · people · place) and its body
    verbatim. Opens in any editor or note vault.
  - **HTML** — a self-contained, zero-dependency styled page (purple theme,
    inline CSS), entries as cards with mood stars and tag/person chips.
  - **PDF** — the same HTML paginated through an off-screen `WKWebView`
    (US-letter portrait), good for printing or archiving.
  - **JSON** — a versioned (`schemaVersion: 1`), round-trippable dump of every
    entry (with resolved tag names + linked person ids), plus the people roster.
    Lays the groundwork for the Phase-3 importer.
- `ExportService` — `@MainActor enum` with pure `renderMarkdown` / `renderHTML` /
  `encodeJSON` render functions and an `export(format:…:exportDir:)` dispatcher.
  Output lands in the resolved export directory (default
  `~/Downloads/PurpleDiary/`, user-overridable in Settings → General), as a
  stamped `PurpleDiary-Journal-YYYY-MM-DD-HHmmss.<ext>` file. All user content
  is HTML-escaped before embedding; bodies get a small inline-Markdown pass
  (bold/italic/code/line-breaks).
- `ExportSheet` — format picker, destination readout, progress, success +
  **Reveal in Finder**. Reachable from the File menu and from Settings → General
  (which also hosts the persistent export-directory picker).

### Notes
- Build-verified on macOS: clean Developer-ID Release build; **60/60 tests**
  (54 prior + 6 new `ExportService` tests covering Markdown content/grouping,
  self-contained HTML, HTML-escaping of `<script>`/`&`, JSON round-trip +
  schema version, empty-journal, and chronological year/month grouping). All
  four formats were exported from the running app against an 8-entry journal and
  inspected: the Markdown structure, the 8-article HTML, the schema-v1 JSON, and
  the PDF — visually confirmed rendering the purple-themed cards with gold mood
  stars and preserved line breaks (the PDF/`WKWebView` path the unit tests can't
  cover).

## [1.0.553] — 2026-05-30 — Security & Privacy whitepaper + in-app viewer

### Added
- **`Docs/SECURITY.md` — a full Security & Privacy whitepaper.** A read-it-end-
  to-end trust document covering what PurpleDiary protects and how: the
  SQLCipher-encrypted database, the Keychain-held DEK, the optional passphrase
  wrap, the 24-word BIP39 recovery key, the plaintext→SQLCipher upgrade
  migration, the cryptographic-primitives table, and a "verify the claims"
  section with commands anyone can run. Tailored to PurpleDiary's **local-only,
  no-network, no-cloud** model (the whole "in transit / in iCloud" surface that
  PurpleLife's whitepaper covers simply doesn't exist here), and honest about
  limitations — notably that `settings.json` is plaintext (preferences only, no
  journal content) and that the recovery key is a bearer credential.
- **In-app whitepaper viewer.** **Help → Security & Privacy whitepaper…** opens
  a dedicated window (`SecurityDocView`) that renders the bundled `SECURITY.md`
  with a small hand-rolled Markdown block parser (headings, lists, numbered
  items, fenced code, dividers, inline bold/italic/code/links via
  `AttributedString`). The doc is copied into `Contents/Resources` by
  `project.yml` and loaded via `Bundle.main`, so the in-app text always matches
  the repo's canonical authoring copy.

### Notes
- Build-verified on macOS: clean Release build (Developer-ID-signed),
  **54/54 tests** (47 prior + 7 new `SecurityDocView` parser tests covering all
  heading levels, bullet/dash and numbered lists, dividers, verbatim fenced code
  blocks, paragraph-join, and a bundled-`SECURITY.md` parse check). The Help →
  Security & Privacy menu item was confirmed present and reachable; the rendered
  window was not screenshotted this round because the Mac was at the lock screen.

## [1.0.552] — 2026-05-30 — Phase 2: Insights dashboard

### Added
- **Insights** sidebar section — a statistics dashboard built on Swift Charts
  over the entries you already have (no new permissions, no data collection):
  summary cards (total entries, total words, days journaled, average mood,
  current + longest writing streak), a **mood-over-time** line chart (daily
  average, rated entries only), **entries-per-month** and **words-per-month**
  bar charts, and a **tag-usage** breakdown colored by each tag. Empty-state
  when the journal has no entries yet.
- `StatsService` — pure, testable aggregation (totals, monthly buckets,
  daily-average mood series, tag counts, and consecutive-day streaks with an
  injectable calendar/reference date). Streak logic counts back from today and
  falls back to a run ending yesterday so an evening writer isn't punished.

### Notes
- Build-verified on macOS: clean Release build; **47/47 tests** (Phase-1's 39 +
  8 `StatsService` tests covering totals, average-mood-excludes-unset, monthly
  buckets, tag ordering, and all streak cases). Insights dashboard exercised
  visually against a 7-entry journal (7 entries / 137 words / 5 days / avg mood
  3.2, with the mood line + monthly bars rendering).

## [1.0.551] — 2026-05-30 — Phase 1: privacy core (encryption-at-rest + app-lock)

### Added
- **Encryption at rest (SQLCipher).** The whole `diary.sqlite` is now
  SQLCipher-encrypted (AES-256). GRDB + SQLCipher 4.6.1 are vendored under
  `Vendor/` (SQLCipher before GRDB so its `sqlite3_*` symbols win at link time;
  GRDB's `CSQLite` re-exports the vendored header). Every connection sets
  `PRAGMA key`; with no key the build behaves like plain SQLite (the test path).
- **Plaintext→SQLCipher upgrade migration.** On the first launch after this
  ships, an existing plaintext DB is detected (SQLite magic-header probe) and
  copied into a keyed sibling via `sqlcipher_export()`, then atomically renamed.
  The launch backup runs *before* the migration so the plaintext state is
  captured as a safety net.
- **KeyStore + Keychain.** A 256-bit data-encryption key is generated on first
  launch and cached in the login Keychain (local-only — no iCloud/cloud). A
  `boot_state.json` "ever-booted" marker prevents minting a fresh key (and
  orphaning data) if the Keychain entry is lost out-of-band.
- **24-word BIP39 recovery key.** Shown on first launch (mandatory save sheet
  with a 3-word typeback) and stored only inside an encrypted
  `recovery_envelope.json`. Unlocks the DB if the Keychain entry is ever lost.
  Regenerate anytime in Settings → Security.
- **App-lock.** Optional lock screen (Touch ID / device password via
  `LocalAuthentication`, or passphrase), lock-on-launch, lock-on-background
  (focus loss), and a Lock PurpleDiary menu item (⌘L). Recovery screen for the
  key-lost case (enter recovery key, or reset — old data is quarantined, not
  deleted).
- **Optional passphrase** wrapping the DEK (set/change/remove in Settings →
  Security), independent of the recovery key.
- **Settings → Security** tab (replaces the old toggles-only Lock tab):
  encryption status, lock options, Touch-ID-only mode, passphrase management,
  recovery-key regeneration.
- **Sample-data facility (Settings → General):** "Add 100 Sample Entries"
  (bulk, one transaction, spread across ~120 days) and "Remove All Sample
  Entries", tracked precisely via `AppSettings.sampleDataIds` so removal only
  touches app-generated entries.
- New services: `Crypto`, `KeyStore`, `KeychainStore`, `RecoveryKey`,
  `BIP39Wordlist`, `BootState`, `BiometricAuthService`; new views
  `AppLockScreen`, `RecoveryScreen`, `RecoveryKeySaveSheet`.

### Changed
- `BackupService.verifyArchive` now opens the extracted DB with the live key so
  the "Test" button works on encrypted archives.

### Notes
- **Build-verified on macOS (2026-05-30).** `./run-tests.sh` → **37/37 passing**
  (16 prior + Crypto 4, RecoveryKey 8, KeyStore 4, AtRest 3, SampleData 2).
  `./build-app.sh` builds Release clean (no warnings), Developer-ID-signed.
  Exercised end-to-end on a real upgrade: an existing 7-entry plaintext
  `diary.sqlite` migrated to SQLCipher (on-disk header confirmed non-plaintext),
  the pre-migration plaintext DB was captured in the launch backup, the recovery
  sheet appeared, and after a relaunch the timeline read all 7 entries from the
  encrypted DB. Lock screen (⌘L) and Settings → Security verified visually.
- Decisions: SQLCipher whole-DB (per SCOPING §7) over column-wrapping; recovery
  is the user-held BIP39 key only (no iCloud/CloudKit DEK escrow), matching
  PurpleDiary's local-first ethos. `settings.json` stays plaintext (no journal
  content; only non-sensitive prefs).

## [1.0.548] — 2026-05-30 — Phase 1 scaffold

### Added
- Initial project scaffold: SwiftUI + GRDB/SQLite macOS app modeled on
  Timeliner, following PhantomLives conventions (manual-HStack sidebar,
  launch-time auto-backup, git-derived versioning, XcodeGen build).
- **Data model** (`v1_initial` migration): `entries`, `tags`, `entry_tags`,
  `people`, `entry_people`. Entry carries Markdown body, mood (0–5), word
  count, and nullable Phase-2 auto-context columns (lat/long/place/weather/temp)
  created up front so no follow-up migration is needed.
- **Timeline view** — entries grouped by month with an inline Markdown editor
  (debounced autosave), mood stars, and tag chips.
- **Calendar view** — month grid; days with entries are dotted; click to jump
  to or create an entry on that day.
- **Search** — ranked across title / body / tags / people (`SearchService`).
- **People** and **Tags** management views; six default tags seeded on first
  launch.
- **BackupService** — launch-time auto-backup to `~/Downloads/PurpleDiary
  backup/`, 5-minute debounce, 14-day retention, verify + restore. Full
  Settings → Backup UI.
- **SampleDataService** — seeds four sample entries on first launch; restorable
  from Settings → General.
- **WindowStateGuard** — canonical split-view/window-state guard wired via
  `AppDelegate`.
- **Settings** — General, Appearance, Lock (toggles only this phase), Backup.
- Test suite: migrations + cascade, model Codable + word count, search
  ranking, backup debounce/retention/verify.

### Fixed
- **Empty first-launch backup.** `AppState.init` ran the launch backup before
  `DatabaseService.shared` was first touched, so on a brand-new install the
  support directory was still empty when the backup zipped it — producing a
  0-file archive (`zip: Nothing to do!`) on exactly the launch where a fresh
  migration runs. Now the database file and `settings.json` are materialized
  before `BackupService.runOnLaunchIfDue`, so the first backup contains a real
  `diary.sqlite`. Verified by simulating a fresh install: the first launch's
  archive now holds 4 files (DB + WAL/shm + settings) instead of 0.
- Silenced two "result of `try?` is unused" warnings on the `@discardableResult`
  `createEntry`/`createPerson` calls in `CalendarView`/`PeopleView` (`_ = try?`).

### Notes
- **Build-verified on macOS (2026-05-30).** `./run-tests.sh` → **16/16
  passing** (BackupService 5, Migration 3, Model 4, Search 4). `./build-app.sh`
  builds Release clean (no warnings), installs to `/Applications/PurpleDiary.app`,
  and launches. Functionally exercised end-to-end: `v1_initial` migration
  applies, 6 default tags + 4 sample entries seed on first launch, backup-on-
  launch and Run Backup Now both write valid zips to `~/Downloads/PurpleDiary
  backup/` (verified the archive's inner `diary.sqlite` round-trips its rows).
- App-lock was UI-only in the scaffold; the lock screen, passphrase/Keychain
  wiring, and SQLCipher encryption-at-rest landed in the privacy-core milestone
  above.
