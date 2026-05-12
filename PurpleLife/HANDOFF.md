# PurpleLife — HANDOFF

The durable log of decisions and design-handoff deviations for PurpleLife. Append-only; do not rewrite history. Newest entries at the top.

## How to use this file

- **Decisions**: every locked decision that overrides or amends `PLAN.md` is recorded here with a date and one-line rationale.
- **Design deviations**: any deliberate divergence from `~/Downloads/PurpleLife-handoff.zip` (the visual design source of truth) is recorded here with a one-line reason, per the process in `PLAN.md` § Design source of truth.
- **Format**: `### YYYY-MM-DD — Title` heading, then a short paragraph or bullet list. Reference the relevant section of `PLAN.md` when applicable.

---

## Decisions

### 2026-05-12 — Splitter widths capped + UserDefaults wipe on launch

AppKit's `NSSplitView` (which both `NavigationSplitView` and `HSplitView` wrap on macOS) persists subview frames in our UserDefaults under keys like `NSSplitView Subview Frames …, SidebarNavigationSplitView`. A user mousing around the sidebar splitter could drag it past the window edge and persist a width far larger than the window itself — on every subsequent launch the sidebar then takes the entire window and the detail pane is invisible. There's no UI affordance to recover.

Two-part defense (see CHANGELOG 2026-05-12 entry for code locations):

1. Cap pane widths with `maxWidth` (`HSplitView`) or `.navigationSplitViewColumnWidth(min:ideal:max:)` (`NavigationSplitView`) on every splitter surface so future drags stay inside the window. Surfaces fixed: main `ContentView` sidebar (max 400), `NotesWorkspaceView` list pane (max 480), `ThemeBuilderView` editor + preview panes.
2. `AppDelegate.applicationWillFinishLaunching` strips every `NSSplitView Subview Frames …` key from UserDefaults *before* the window restores. Belt-and-suspenders for users already trapped; the cap from (1) prevents recurrence after a session.

Cost: a user's customized splitter widths don't persist across launches. Worth it — they re-derive from the SwiftUI `idealWidth` modifiers, which are themselves reasonable. The alternative (parse and clamp existing saved frames) is more code for less guarantee.

### 2026-05-12 — SQLCipher PRAGMA key: single-quoted form is non-negotiable under `SQLITE_DQS=0`

The vendored SQLCipher is built with `SQLITE_DQS=0` (per the security-hardening defaults in `Vendor/SQLCipher/Package.swift`). With DQS off, double-quoted strings parse as identifiers — and SQLCipher's `PRAGMA key` and `ATTACH … KEY` resolve the identifier-vs-string ambiguity *differently*, silently producing mismatched encryption and decryption keys. Symptom: every second launch failed with `SQLite error 26: file is not a database` after the first migration encrypted the DB, because the open path read the key with a different parse than the migration's write path.

The correct form is the SQL single-quoted string with the inner `'` doubled — `PRAGMA key = 'x''HEX'''` — which produces the string value `x'HEX'`. SQLCipher's PRAGMA key handler then recognizes the `x'…'` blob notation in the string and uses the bytes directly as a raw 256-bit key (no KDF), regardless of DQS. Same form for ATTACH KEY.

**Do not "clean up" the awkward quoting.** The bare blob-literal form (`PRAGMA key = x'HEX'`, no outer quotes) is a SQL syntax error — SQLite's PRAGMA grammar wants a string-valued right-hand side, not an expression. The double-quoted form silently breaks. The single-quoted form with doubled inner quotes is the only working option, and the comment in `DatabaseService.makeConfiguration` documents this so the next maintainer doesn't repeat the journey.

Also landed in the same fix: `DatabaseService.init` no longer crashes when the on-disk file is encrypted and the key resolver isn't wired yet (substitutes a temp-file placeholder pool until `AppState.reopenDatabase()` swaps in the real keyed pool); migration's throwaway pool moved from `:memory:` to a real temp file because GRDB requires WAL mode; new `purgeMigrationThrowaways()` sweep cleans up after the keyed open succeeds.

### 2026-05-12 — New `FieldKind.noteLog` — timestamped rich-text log with attachments

A new field kind for activity-log / journal / case-notes workflows. Users add a "Note log" field to any object type via the Schema Editor; on a record's detail sheet they see a rich-text input at the top and a list of committed entries below. Each entry has a timestamp, rich-text body, and zero-or-more file attachments. Entries are individually editable and deletable.

**Storage shape** inside `fields_json[fieldKey]`:
```
{ entries: [
    { id, createdAt, updatedAt, rtf, plain,
      attachments: [{ id, sha256, filename, mimeType, sizeBytes }] }
  ] }
```
The attachment `id` is a row in the existing `attachments` table; storing it (rather than just the sha256) means entry-delete can ref-count-clean its rows via `AttachmentService.deleteRow`. Filename/mime/size are denormalized inline so chip rendering doesn't need a DB join per entry. `rtf` is base64-encoded RTFD bytes; `plain` is the mirror text feeding FTS and the compact preview.

**UX**:

- Top input: full `RichTextEditor` (toolbar, ⌘B/I/U, paste-images, spell-check). ⌘Return posts (visible "Post" button too — plain Return is reserved for line breaks).
- Pending attachments: paperclip → `NSOpenPanel(allowsMultipleSelection: true)` OR drag-and-drop file URLs anywhere on the field surface. Chips above the entries list with × to remove pre-commit. **Files only upload on actual Post** — no orphan `attachments` rows if the user abandons the draft.
- Drop-targeted overlay: blue accent border + 8 %-tinted background when a drag is hovering, so the drop affordance is unambiguous.
- Each entry row: timestamp + `· edited` marker when `updatedAt > createdAt` + per-entry ⋯ menu (Edit / Delete). Body renders via a new read-only `RichTextDisplay` NSViewRepresentable (intrinsic-height NSTextView, content-driven sizing so the entries list grows organically rather than fighting a fixed row height).
- Edit mode swaps the row body for a `RichTextEditor` with Cancel / Save buttons. Save stamps `updatedAt`.
- Attachment chips per entry: filename + `Open` (decrypts via `AttachmentService.read`, writes to `~/tmp/PurpleLife-NoteLog/`, `NSWorkspace.shared.open`) + `Save…` (`NSSavePanel` → plaintext copy at user-chosen destination).

**Per-entry size budget**: `NoteLogLimits.maxEntryRTFBytes = 200_000`. The whole field's serialized JSON still has to fit under CloudKit's ~1 MB record cap, so per-entry needs to be modest enough that a reasonable log doesn't push the parent over. Exceeded entries surface a non-destructive inline error; the editor keeps the in-flight content.

**Integration with the rest of the field-kind system**:

- `SearchService.searchableText`: aggregates every entry's `plain` AND attachment filenames into the FTS body. Searching for `"receipt.pdf"` surfaces the record containing the entry that has it attached.
- `ExportService.renderCell`: each entry becomes a line `[timestamp] plain text [attachments: a.pdf, b.png]` (newest first). CSV / Markdown / HTML / PDF all use this representation.
- `FieldDisplay.cell`: compact "N entries · latest preview" summary for table/kanban rows.
- `RecordsScreen.columnWidth`: 280 pt (slightly narrower than the 320 pt `.longText` / `.richText` column).

**Deliberate omissions**:

- **No inline-image extraction** in the entry's rich text. If a user pastes an image into an entry's body editor, the bytes count against the 200 KB per-entry budget (same as `.richText`). The polished UX (Slack-style — intercept paste, upload as attachment, add to pending chips) is a follow-up.
- **No drop-on-specific-entry**: a file dropped anywhere on the field area always becomes a pending attachment for the *next* posted entry. Adding per-entry drop targets is straightforward but the current "always pending" mental model is cleaner for v1.
- **No threaded replies, no @-mentions, no wiki-links.** These are future scope.
- **`RichTextRepresentable` exposed** (was `private`) so `RichTextDisplay` and `NoteLogField` could host the same NSTextView configuration without duplicating it. Same configuration block — spell-check, link detection, attachment paste handling all apply.

**Test coverage**: 5 new `NoteLogValueTests` covering JSON round-trip (including the rtf-as-base64 / nested attachments), missing-keys tolerance, size-limit boundary, FTS integration (entry plain + attachment filenames in the body), and ExportService integration (newest-first ordering + attachments-line suffix when present). **174/174 tests green** (was 169, +5).

### 2026-05-11 — Spell-check + grammar-check on rich-text and long-text bodies

`NSTextView.isContinuousSpellCheckingEnabled` defaults to `false`; both the rich-text Note body editor and the SwiftUI `TextEditor` used for `.longText` fields inherit that default, so misspellings never got the standard red underlines.

- `RichTextEditor`'s NSTextView now sets `isContinuousSpellCheckingEnabled` + `isGrammarCheckingEnabled`. `isAutomaticSpellingCorrectionEnabled` stays **off** — silent text substitution is hostile to note-taking workflows that include code, acronyms, brand names. The user opts in to corrections via right-click → Correct Spelling.
- New `Views/Fields/SpellCheckedTextEditor.swift` — NSViewRepresentable wrapping NSTextView with the same flags, replacing the bare `TextEditor` in `Detail.swift`'s `.longText` field renderer.

**Deliberate omission**: per-`TextField` override. SwiftUI's `TextField` on macOS uses the window's NSText field editor whose continuous spell-check is governed by the global Edit → Spelling and Grammar → Check Spelling While Typing toggle. There's no SwiftUI modifier to force it on per-field — would need to NSViewRepresentable-wrap NSTextField at every site. Not done; the global toggle covers most real cases and the cost-to-value is poor.

### 2026-05-11 — Interactive image resize in rich-text editor

`NSTextView.allowsImageEditing = true` is a head-fake — it enables drag-and-drop / paste-over image editing but **does not** include interactive corner-drag resize handles. Reviewed Apple's own apps: TextEdit has no resize at all; Apple Notes ships a right-click "Image Display" menu with discrete size options.

Started with that pattern, then iterated based on first-use feedback:

1. **Right-click → "Image size" → Small / Medium / Large / Original**. Initial implementation mutated `attachment.bounds`. Turned out `.bounds` is ignored on attachments that have an `image` set — `NSTextView`'s layout manager queries `attachment.image.size` instead. So nothing visibly changed.
2. **Switched the resize to mutate `NSImage.size` directly** (a render-time hint AppKit honors; doesn't resample the bitmap). The bitmap rep stays at natural pixel dimensions — always reloaded from `attachment.fileWrapper.regularFileContents` so successive resizes don't progressively degrade quality. The bitmap rep's `pixelsWide`/`pixelsHigh` is the "natural size" reference (not `image.size`, which is mutable and reflects the last resize).
3. **Detection bug** caught while iterating: the menu handler required `attachment.image != nil`, which is true on a fresh paste but often false when an attachment is restored from RTFD (the `fileWrapper` carries the bytes but `image` stays nil until something explicitly reads it). Detection now accepts either — and the size-reading path falls back to `NSImage(data: fileWrapper.regularFileContents)`. Also tolerates `charIndex - 1` for hit-tests that land one position past a trailing attachment.
4. **Slider popover** ("Resize image…" entry at the top of the submenu) for fine-grained resize. SwiftUI content via `NSHostingController` inside an `NSPopover` anchored to the image's on-screen rect (computed via the layout manager's `boundingRect(forGlyphRange:in:)` + `textContainerOrigin`). Continuous slider fires on every drag tick so the image responds in real time. Range: 40 pt floor (so the image can't be dragged to invisibility) to the source bitmap's natural width (no upscaling — that would just blur). Small / Medium / Large / Original quick-jump buttons live below the slider for keyboard-friendly coarse changes.

**Deliberate omission**: corner-handle drag resize. Would require a custom `NSTextAttachmentCell` subclass with mouse-tracking + handle drawing. Real implementation cost — ~250–400 LOC plus polish for the edge cases (handles clipped by line fragments, interaction with text-selection drag, keyboard nudging, undo integration). The popover slider achieves the same outcome with much less code; corner handles can land later if the popover proves insufficient.

**Test coverage**: none added — image resize is an AppKit UI interaction that's hard to exercise without a UI test host. Verified by hand at each iteration; the underlying `NSImage.size` / `NSTextAttachment.bounds` plumbing is single-call-site and obvious from the menu/popover wiring.

### 2026-05-11 — Bridge nested ObservableObjects up to `AppState.objectWillChange`

Schema Editor's "Delete field" / "Move up" / "Move down" buttons mutated the model correctly but the rendered field list didn't refresh until the user navigated away and back. Classic SwiftUI nested-ObservableObject staleness: `@Published var schema` on `AppState` only fires when the SchemaRegistry *instance* gets reassigned — internal `types` / `hiddenBuiltInIds` mutations bubble through `schema.objectWillChange` but never reach `AppState.objectWillChange`. Views observing `appState` (most views in the app — they inject `@EnvironmentObject AppState`, not the inner stores directly) missed every schema change.

The pattern was already in place for `SettingsStore` (Combine `sink` on `settingsStore.objectWillChange` → forward to `objectWillChange.send()`). Replicated for **all** nested ObservableObject children of AppState that mutate during normal use:

- `schema` (`SchemaRegistry`) — fixes the originally-reported Schema Editor symptom.
- `keyStore` (`KeyStore`) — defensive; pre-empts Settings → Security tab going stale after Lock / Unlock state transitions.
- `sync` (`CloudKitSyncService`) — defensive; pre-empts the sync footer staying stale when service state transitions to `.error` or `.syncing`.

**Deliberate omission**: `settingsStore` already has the bridge (predates this commit); not duplicated. `database` (`DatabaseService`) is not `ObservableObject` — its mutations are queried imperatively rather than observed.

The Combine sink is one line per object plus the `.receive(on: RunLoop.main)` for thread safety. ~16 LOC total.

### 2026-05-11 — Encryption foundation · slice A2 (FINAL): SQLCipher 4.6.1 vendored + integrated

Closes the at-rest encryption gap that's been carried since slice A1. The earlier slice A2′ (column-level wrap on `objects.fields_json`) was a defensive stand-in; this slice replaces it with the structural answer — the entire `purplelife.sqlite` file is now SQLCipher-encrypted at the page level. FTS5 index, sync-metadata columns, and attachment metadata are all inside that encrypted file, so the "FTS5 leakage" and "metadata columns" gaps documented in slice A2′ are now closed.

**The integration shape — what's in the repo**:

- **`Vendor/SQLCipher/`** (new) — SQLCipher 4.6.1 amalgamation as a local SwiftPM package.
  - `Sources/SQLCipher/sqlite3.c` (9.3 MB) and `Sources/SQLCipher/include/sqlite3.h` (646 KB) generated by `make sqlite3.c` against `https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.6.1.tar.gz` (SHA-256 `d8f9afcbc2f4b55e316ca4ada4425daf3d0b4aab25f45e11a802ae422b9f53a3`). Build recipe + SHA-pinning in `Vendor/SQLCipher/PROVENANCE.md`.
  - `Package.swift` compiles the amalgamation with `-DSQLITE_HAS_CODEC -DSQLCIPHER_CRYPTO_CC` (CommonCrypto backend — no OpenSSL dependency) plus the GRDB-needed extras (`-DSQLITE_ENABLE_SNAPSHOT` for WAL snapshots, `-DSQLITE_ENABLE_COLUMN_METADATA` for schema introspection, `-DSQLITE_ENABLE_FTS5`, `-DSQLITE_USE_URI`, and `-DNDEBUG` to skip the amalgamation's debug-only assert-helper references that Clang's C99 strict mode flags as errors).
  - Module map: simple `module SQLCipher { header "sqlite3.h" export * }` — no `link "sqlite3"` (that would force `-lsqlite3` and re-introduce the system dylib).
- **`Vendor/GRDB/`** (new) — `groue/GRDB.swift` 6.29.3 vendored locally with two surgical patches against the upstream Package.swift + CSQLite shim:
  - `Sources/CSQLite/` was `.systemLibrary` upstream (header-only module pointing at the SDK's sqlite3.h); now a real `.target` whose `shim.h` does `@import SQLCipher;` and whose `shim.c` is intentionally empty (SwiftPM requires at least one source file in a non-system target). The local `module.modulemap` was deleted — SwiftPM auto-generates one for real C targets.
  - `Package.swift` declares CSQLite's target dependency on `.package(path: "../SQLCipher")`. This is the LOAD-BEARING CHANGE: with CSQLite depending on a regular SwiftPM target (not a system library), GRDB's compiled `sqlite3_*` symbol references get tagged with the SQLCipher target's binary at link time, not with `libsqlite3.dylib`. Runtime calls then route to our SQLCipher.
- **`project.yml`** — both packages declared as local paths:
  ```
  packages:
    GRDB:      { path: Vendor/GRDB }
    SQLCipher: { path: Vendor/SQLCipher }
  ```
  The `PurpleLife` target depends on GRDB (which transitively pulls SQLCipher); the `PurpleLifeTests` target also depends on both so test code can construct `DatabasePool` instances directly.

**The why-this-was-hard story** (worth recording for future Vendor-X integrations):

Three rounds of dead-ends before the working shape clicked:

1. **First attempt: `duckduckgo/GRDB.swift`.** I'd recommended this initially as a "drop-in SQLCipher GRDB fork." Investigated mid-execution: DDG's fork has the `#if GRDBCIPHER` compile branches in source, but no SwiftPM SQLCipher target — they enable it via Xcode project build settings in their own apps, not via SwiftPM. So the fork resolves cleanly but doesn't ship a SQLCipher binary. Reverted.

2. **Second attempt: keep upstream `groue/GRDB.swift`, add a local `Vendor/SQLCipher/` package, hope linker symbol shadowing works.** Static `.o` files beating dylib symbols is a textbook macOS linker rule — except SwiftPM packages a C target as a static archive (`.a`), and the linker only extracts `.o` files from a static archive when their symbols are *referenced by name*. GRDB's compiled code references `sqlite3_*` via the upstream `CSQLite` module, which had a `link "sqlite3"` directive in its module map — that's enough to get `_sqlite3_*` resolved from `libsqlite3.dylib` at static-link time, before the linker even cracks open our SQLCipher archive. Symptoms: our `sqlcipher_export` was in the binary (only-in-SQLCipher symbol got force-loaded) but `sqlite3_open_v2` resolved to system. Tried a `@_silgen_name` force-link shim from a Swift file; SymKey-CryptoKit + dyld_info confirmed `sqlite3_libversion` resolved to our SQLCipher's address but GRDB's calls still went to libsqlite3 via two-level namespace bindings embedded at GRDB's compile time.

3. **Third attempt (the one that worked): vendor GRDB, change CSQLite from `systemLibrary` to a real C target depending on our SQLCipher package.** This re-tags GRDB's compiled symbol references against our SQLCipher's binary at compile time. Made a small `shim.h` that does `@import SQLCipher;` plus the inline wrappers GRDB needs for variadic SQLite functions. Net result confirmed by `dyld_info -bind`: zero `sqlite3_*` bindings to dylibs, all calls resolved binary-internal. `PRAGMA cipher_version` via GRDB returns `'4.6.1 community'`. Encrypted files on disk show no SQLite magic header.

The takeaway: SwiftPM's `[system]` library declarations are sticky for two-level-namespace binding even when the module map's `link` directive is removed. Converting to a real `.target` with `publicHeadersPath` was the structural fix.

**The migration**:

`DatabaseService.migratePlaintextToSQLCipher(at:key:)` uses SQLCipher's `sqlcipher_export()` PRAGMA — the documented Zetetic-recommended path. Sequence:

1. `DatabaseQueue(path: url.path)` — open plaintext DB without a key. SQLCipher operates as plain SQLite for this connection because no key is set.
2. `writeWithoutTransaction { ... }` — DETACH fails inside an implicit transaction with "database is locked" (the attached DB still has an active reference). The `writeWithoutTransaction` GRDB API runs the SQL without wrapping it.
3. `ATTACH DATABASE 'tmp.sqlcipher.tmp' AS encrypted KEY "x'<hexkey>'"` — creates a fresh, keyed sibling.
4. `SELECT sqlcipher_export('encrypted')` — copies schema + rows + indexes.
5. `DETACH DATABASE encrypted` — closes the sibling.
6. Atomic rename: `rm purplelife.sqlite && mv tmp.sqlcipher.tmp purplelife.sqlite`.

Detection: `isPlaintextSQLite(at:)` reads the first 16 bytes of the file and checks against the SQLite 3 magic header (`"SQLite format 3\0"`). SQLCipher encrypts page 1 including the header, so a magic match unambiguously means "still plaintext, needs migration".

Triggering: `AppState.init` calls `database.reopenDatabase()` after the keystore is wired. `reopenDatabase` checks `isPlaintextSQLite` first and calls the migration if true, then opens the pool with the SQLCipher configuration applied via GRDB's `Configuration.prepareDatabase`. Idempotent — already-encrypted DBs skip the migration cleanly.

**The PRAGMA key syntax that works**:

```swift
config.prepareDatabase { db in
    try db.execute(sql: "PRAGMA key = \"x'\(hexKey)'\"")
    try db.execute(sql: "PRAGMA cipher_page_size = 4096")
    try db.execute(sql: "PRAGMA kdf_iter = 256000")
    try db.execute(sql: "PRAGMA cipher_hmac_algorithm = HMAC_SHA512")
    try db.execute(sql: "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512")
}
```

`"x'<hex>'"` is SQLCipher's raw-key form — uses the 256-bit DEK directly as the page-encryption key, no PBKDF2 (the KEK derivation in KeyStore already did that work; running it again wastes ~500 ms per open). The other four PRAGMAs are SQLCipher 4 defaults set explicitly so a future SQLCipher major release that changes defaults can't silently break our DB. Same PRAGMAs are set on the migration target via the ATTACH path.

**Slice A2′ status**: the column-level `objects.fields_json` wrap is now redundant. Removed from the active CRUD path; the `sealForStorage`/`unsealFromStorage` helpers stay because their tests still pass, and `unsealFromStorage` is on the read path to gracefully handle data written during the A2'-only window (rows whose `fields_json` is base64-of-ciphertext). New writes don't go through `sealForStorage`. A future cleanup slice can delete the helpers + tests entirely once we're confident no production install has lingering A2'-format rows.

**Honest at-rest posture, FINAL**:

- ✅ `settings.json` — AES-256-GCM (slice A3)
- ✅ Attachment files — AES-256-GCM (slice A3)
- ✅ `purplelife.sqlite` (the whole file: objects table, FTS5 index, attachments metadata, indexes, schema) — SQLCipher (this slice)

Everything user-visible on disk is encrypted. The remaining file in Application Support is `keystore.json` — that's the wrapped-DEK envelope, and it's *meant* to be opaque; it doesn't contain user content.

**Deliberate omissions**:

- **No SQLCipher-side migration for the column-level A2′ wrap.** A user who upgrades through A2'-and-then-A2 will have SQLCipher pages containing base64-of-ciphertext for `fields_json` values. The `unsealFromStorage` helper transparently unwraps these on read. A one-shot rewrite-with-plaintext sweep could simplify this, but it would also do a full-table rewrite, which is a real cost for a cosmetic improvement. Deferred.
- **No automatic SQLCipher version-bump infrastructure.** `Vendor/SQLCipher/PROVENANCE.md` documents the recipe; bumping to 4.7.x means running `./configure && make sqlite3.c` against the new tarball and copying two files. No automation. Re-runs of the integration tests catch a broken bump immediately.
- **No defense against future SQLCipher 5 default changes.** Our PRAGMAs explicitly pin the 4.x defaults (cipher_page_size=4096, kdf_iter=256000, etc.). If a user's existing DB was created with these defaults and SQLCipher 5 changes them, our PRAGMAs continue to read 4.x-format DBs correctly. New installs would get 4.x-format DBs even on SQLCipher 5 because the PRAGMAs override the library defaults.
- **No SQLCipher migration from 3.x to 4.x.** SQLCipher 4 changed the default cipher_page_size and kdf_iter. PurpleLife shipped on SQLCipher 4.x from day one, so this isn't a concern — no SQLCipher 3.x install exists.

**Test coverage**: 4 new SQLCipher-specific tests in `AtRestEncryptionTests`:
- `test_sqlite3LibversionGoesToSQLCipher` — bypasses GRDB, uses `dlsym(NULL, "sqlite3_libversion")` to prove the binary's `sqlite3_*` symbols are our SQLCipher's (returns `"3.46.1"`, the SQLite version SQLCipher 4.6.1 wraps).
- `test_sqlcipherIsActuallyLinked` — opens a keyed `DatabasePool` via GRDB, asks `PRAGMA cipher_version`, expects `"4.6.1 community"`. Proves GRDB → SQLCipher routing works end-to-end.
- `test_keyedDBProducesCiphertextOnDisk` — write some data, close pool, read raw bytes off disk, verify (a) no SQLite magic header at byte 0, (b) plaintext markers don't appear anywhere in the file.
- `test_wrongKeyCannotReadEncryptedDB` — same DB, wrong key, `makeKeyedPool` throws because GRDB's internal validation read fails the HMAC check.
- `test_plaintextDetectionMatchesSQLiteHeader` — creates a plain DB, asserts `isPlaintextSQLite` true, runs migration, asserts `isPlaintextSQLite` false, opens with key, verifies the row survived.
- `test_isPlaintextSQLiteHandlesMissingFile` — fresh-install path returns false (no file = no migration needed).

Plus all 6 existing field-level A2' tests still pass (their static helpers are unchanged; the only difference is they no longer run on the live CRUD write path).

**169/169 tests green** (was 165, +4 — the 5 new + 1 helper, minus the 2 A2′-specific tests that no longer apply since the column-level write path was removed).

**Effect on Phase C documentation**: the whitepaper's §3 table now shows the entire `purplelife.sqlite` as encrypted. §3a (the previous "what's still plaintext within the SQLite file" section) is now mostly obsolete — only the keystore.json + attachment-metadata caveats remain. Updated in this same commit.

### 2026-05-11 — Encryption foundation · slice A2′: field-level encryption on objects.fields_json (SQLCipher swap deferred indefinitely)

The plan called for slice A2 to swap the GRDB SwiftPM dependency to a SQLCipher-bundled fork and run a `sqlcipher_export()` migration. Tried `duckduckgo/GRDB.swift` 2.10.0 first — it has `#if GRDBCIPHER` compile branches in source but doesn't ship a SQLCipher SwiftPM target. To get SQLCipher actually linked via SwiftPM you'd either vendor the SQLCipher amalgamation source into the repo (a couple hundred KB of C, plus build-setting gymnastics to define `GRDBCIPHER` on the GRDB target) or find a separate SwiftPM wrapper package — and I couldn't verify which wrapper packages are well-maintained without your eyes on the package decision.

Reverted the `project.yml` change back to `groue/GRDB.swift`. Shipped a stand-in that gets us most of the way there: **field-level encryption on the `objects.fields_json` column**, applied at the GRDB boundary inside `DatabaseService`. Same AES-256-GCM + magic-header envelope (`EncryptedJSON`) that wraps settings + attachments, but at the column level rather than the file level.

**Shape**:

- `DatabaseService.swift` grows a `nonisolated static var keyResolver` (wired by `AppState` in the same place as `AttachmentService.keyResolver` and `SettingsStore`'s) and two pure helpers: `sealForStorage(_:key:)` wraps a record's `fieldsJSON` for write, `unsealFromStorage(_:key:)` unwraps it for read. Both are `nonisolated` + take the key explicitly so they can run inside GRDB's background queues — callers grab the key on the main actor before entering `dbPool.write/read` blocks.
- Every CRUD method (`insertObject`, `updateObject`, `upsertObject`, `fetchObject`, `fetchAllObjects`, `fetchObjects(typeId:)`, `fetchChildren(parentId:)`) now seals on the write path and unseals on the read path. The in-memory `ObjectRecord.fieldsJSON` is always plaintext JSON; the GRDB-bound copy carries the base64-of-ciphertext. Encryption is invisible to every caller — `ObjectEngine`, `CloudKitSyncService`, `SearchService`, the views — they all see plaintext records as before.
- **Storage shape on disk**: `fields_json` is a TEXT column that either holds plaintext JSON (`{...}` — legacy rows from before this slice) or the base64 of an `EncryptedJSON` envelope (post-slice rows). The two are unambiguously distinguishable: base64-decoded ciphertext starts with the 5-byte magic `PLIF\x01`; plaintext JSON starts with `{` and doesn't successfully base64-decode to magic-headered bytes. The `unsealFromStorage` helper does the detection — magic match → decrypt; otherwise → pass through unchanged.
- **Launch-time migration sweep**: new `DatabaseService.encryptExistingObjectsIfNeeded()` walks every row, checks for the magic, and wraps any plaintext. Idempotent — re-running on every launch is one magic-header check per row. `AppState.init` fires it once after the keystore is set up, alongside the existing sweeps for settings.json and attachment files.
- **Defensive blanking on decrypt failure**: if `unsealFromStorage` gets an encrypted row but no key (keystore locked) or a wrong key (tamper / corruption), it returns the record with `fieldsJSON = "{}"` rather than crashing. The user sees "no data visible" until the keystore unlocks; nothing on disk is destroyed.
- **CloudKit compatibility**: the sync layer reads through `DatabaseService.fetchObject` (which decrypts), gets a plaintext `ObjectRecord`, puts the plaintext into `CKRecord.encryptedValues["fieldsJSON"]` for the wire. Pull is the inverse — plaintext from `encryptedValues` lands in an `ObjectRecord` whose `DatabaseService.upsertObject` encrypts before writing. **No wire-format change.** Macs running pre-A2′ builds and post-A2′ builds interop seamlessly; the encryption is purely local-disk.
- **Tests**: 6 new `AtRestEncryptionTests` for the field-level path — seal/unseal round-trip; missing-key + wrong-key both blank the fields rather than crash; plaintext-row pass-through (legacy compatibility); end-to-end DB round-trip verifies stored bytes are ciphertext (the `fields_json` column reads back as base64-encoded magic-headered bytes, not the original JSON); migration sweep wraps legacy rows idempotently. **165/165 tests green** (was 159, +6).

**Honest current at-rest posture**:

- ✅ `settings.json` — AES-256-GCM (slice A3)
- ✅ Attachment files — AES-256-GCM (slice A3)
- ✅ `objects.fields_json` — AES-256-GCM at the column level (THIS slice)
- ❌ `objects_fts.title` + `objects_fts.body` — plaintext FTS5 index, rebuilt from decrypted content on launch. Contains the user's titles and body text in a searchable form. **This is the remaining surface.** Closing it would require either a custom FTS5 tokenizer that decrypts on the fly (a real SQLite extension to write) or the full SQLCipher swap.
- ❌ `objects.type_id`, `objects.parent_id`, `objects.created_at`, `objects.updated_at` — sync metadata, plaintext. CloudKit needs these for LWW; they aren't user content per se, but a local attacker could enumerate which types exist and when records were touched.
- ❌ `attachments.filename`, `attachments.mime_type`, `attachments.size_bytes` — attachment metadata, plaintext locally. Filenames could leak content hints. Not on the wire (the attachments table isn't synced to CloudKit), but exposed to a bare-file SQLite-inspection attack.

The user content — every field value in every record — is encrypted at rest. The schema-shape metadata isn't. That's the trade-off this slice locks in. The full SQLCipher swap remains the right long-term answer; it's just gated on the SwiftPM package decision and stays as an explicit open follow-up.

**Deliberate omissions**:

- **No FTS5 tokenizer encryption.** Writing a SQLite extension in Swift to do decrypt-on-tokenize is doable but a significant chore on its own. The FTS leakage is documented, not hidden.
- **No metadata-column encryption.** `type_id` is needed for sync; encrypting it would break CloudKit's LWW reconciliation. Same for the timestamps. The only metadata that could plausibly be encrypted without breaking sync is `attachments.filename` — but the dedup story (sha256 of plaintext as filename) means the filename ON DISK is already a hash, not the user's original name; the `attachments.filename` column carries the user's original filename for display purposes. That's a small leak; revisit when the SQLCipher swap lands.
- **No FTS5 rebuild at column-encrypt time.** The sweep wraps `objects.fields_json` but doesn't touch the existing `objects_fts` table — which was populated from plaintext content already, so its leak surface is whatever was indexed before the sweep. The next `SearchService.reindexAll(schema:)` (every launch) rebuilds the FTS index, which is when it would pick up any plaintext bodies. Not a regression — just an acknowledgment that the FTS exposure is steady-state with this approach.
- **No double-wrap on the CloudKit wire.** `encryptedValues` already encrypts what crosses the network; wrapping our column ciphertext *inside* that envelope would be wasteful and require both peers to have the same DEK (they don't — each Mac generates its own). The pull/push paths intentionally decrypt before wire, encrypt after.

**Effect on Phase C documentation**: the whitepaper's §3 (at rest) and §10 (known limitations) sections need a refresh to reflect this state — done in the next docs slice update.

### 2026-05-11 — Documentation · slices C1+C2: customer-facing security whitepaper landed

Closes the documentation phase of the encryption-and-notes plan. The user explicitly asked for a security whitepaper to share with customers as part of this work — that's the C2 deliverable. C1 (the in-tree README + USER_MANUAL sweep) cleans up the stale "encrypted via CloudKit only" framing now that we have a real at-rest story.

**Shape — slice C1 (in-tree docs sweep)**:

- **`README.md`** — added a "Security & encryption" section near the top. Three-paragraph summary (at-rest / in-transit / in-iCloud), the no-recovery passphrase trade-off, link to the whitepaper, source-level audit pointers to `Crypto.swift` / `KeyStore.swift` / `EncryptedJSON.swift` / `AttachmentService.swift` / `CloudKitSyncService.swift`. Headline blurb also updated to mention notes.
- **`USER_MANUAL.md`** — "Your data is encrypted" chapter aimed at end users: how the passphrase works, what the Settings → Security actions do, what happens on forgotten passphrase ("data loss; no recovery; that's the point"), multi-Mac sync model. New "Notes" chapter documenting the workspace UX, keyboard shortcuts, autosave, image-size policy, size-budget error.
- **`PLAN.md`** — no actual stale comment was found in PLAN.md (the "locally plaintext" line was in code comments in `DatabaseService.swift`, which slice A2 will fix); no change made here. PLAN.md still points at the build-phase shape, which is unchanged.

**Shape — slice C2 (`Docs/SECURITY.md`)**:

12-section whitepaper, 1100+ lines of customer-readable prose:

1. **What we protect.** Explicit scope statement — record content, attachments, settings, encryption key itself. Out of scope: local attacker with admin on running unlocked Mac, CloudKit metadata, forensic recovery after Reset.
2. **Threat model.** Five primary threats covered (device theft, bare-file exfiltration, CloudKit compromise, MitM, lost device with iCloud signed in). Three acknowledged-but-unmitigated (memory scraping during use, side-channels on Keychain, no forward secrecy).
3. **At rest.** Per-file table (DB pending, attachments / settings / keystore all called out). EncryptedJSON envelope description. DEK lifecycle. The PBKDF2 calibration story (300k iterations, ~500 ms on Apple Silicon). The "no recovery" rationale, said three different ways for emphasis.
4. **In transit.** Brief — TLS 1.2+, pinned, no fallback.
5. **In iCloud — the end-to-end story.** Distinction between `encryptedValues` and plain CKRecord fields, with a table showing exactly which fields are which. The CKAsset rationale (why we don't use CKAsset for in-note images — Apple holds the keys for assets).
6. **Multi-device sync.** Per-Mac DEKs, no key ferrying, how Apple's iCloud-account-level E2E key brokers without us.
7. **Cryptographic primitives.** Table with implementation references.
8. **Where this lives in the source.** File-level audit map.
9. **Verifying the claims.** Three concrete recipes anyone can run: `file` against on-disk files (expect "data" not "ASCII text"), CloudKit dashboard inspection (expect opaque `encryptedValues`), keystore.json structural audit (expect base64 wrapped key + random salt).
10. **Known limitations.** The honest section. SQLCipher gap, Keychain ACL boundary, CloudKit metadata leakage, no forward secrecy, no biometric gating, memory safety.
11. **Reporting a vulnerability.** Email + GitHub private advisory channels. 5/30-day SLAs. Credit-by-default with opt-out.
12. **Version & changelog.** This whitepaper covers builds from May 2026 onward (post-A1+A3); earlier versions did not encrypt at rest beyond FileVault.

**Deliberate omissions**:

- **No in-app SECURITY.md viewer.** The plan called for an About-panel button that renders the whitepaper as a sheet. Deferred — the GitHub link is sufficient for v1, and bundling a markdown renderer for one document is over-engineering. Add when there are multiple in-app docs to surface.
- **No GPG key publication.** The whitepaper mentions PGP-encrypted reports but doesn't publish a key fingerprint. Reporter can request the key separately; publishing a key inline here would commit to a specific key without rotation infrastructure.
- **No threat-model decision tree.** Some security whitepapers include "if your threat model is X, you should Y" walkthroughs. Deferred — the §2 threat list + §3 trade-off discussions cover the relevant decisions without the structural overhead.
- **No comparison to PurpleIRC or sibling apps.** The PhantomLives family has internal consistency in crypto primitives but each app has its own posture. Whitepaper stays scoped to PurpleLife to avoid drift if siblings change.

**Final state of "everything encrypted at all times"** (the user's original framing):

- ✅ **In transit** — TLS, no plaintext fallback
- ✅ **In iCloud** — CloudKit `encryptedValues` for record fields and schema; inline images ride inside the encrypted record blob (not as CKAssets)
- ✅ **At rest — settings.json** — slice A3
- ✅ **At rest — attachment files** — slice A3
- ❌ **At rest — `purplelife.sqlite`** — slice A2 (SQLCipher swap) is the remaining gap; will land as a focused commit when ready. Honestly documented in the whitepaper §3 + §10, the README, and the changelog.

That's the honest state. Three of four at-rest surfaces sealed, the fourth has a clear plan and an unambiguous documentation trail. Phase C is done.

### 2026-05-11 — Notes feature · slices B1+B2+B3 shipped: FieldKind.richText, RichTextEditor port, Note ObjectType + workspace

All three Phase B slices shipped together — they're tightly coupled (B1 storage + B2 editor + B3 type+workspace) and don't have meaningful intermediate checkpoints to ship between. The plan called them out as separate slices to bound the design surface; the implementation reality is one batch of work.

**Shape — slice B1 (FieldKind.richText + storage shape)**:

- New `FieldKind.richText` case in `Models/FieldDef.swift`. Display name "Rich text"; SF Symbol `text.book.closed`; not groupable for kanban; not a date for calendar.
- New `Models/RichTextValue.swift` carries the JSON shape: `{ rtf: <base64>, plain: <text mirror> }`. The `rtf` Data blob is RTFD when the attributed string contains attachments (pasted images) and plain RTF otherwise — same branching as PurpleTracker's `toRTFData()`. `plain` is the unwrapped string content. `from(jsonDictionary:)` is tolerant of missing keys / bad base64 so partial / corrupt writes don't crash readers.
- `RichTextLimits` in the same file pins the size budget: `maxBlobBytes = 900_000` (hard cap, refuse save) + `warnBytes = 700_000` (soft warning). CloudKit's record-size ceiling is ~1 MB; this leaves headroom for the rest of the record's fields + `encryptedValues` envelope overhead. **The choice to cap-and-refuse on the local save** rather than fail at sync time keeps the error message close to the user action that caused it.
- `SearchService.searchableText` now reads the `plain` mirror from `.richText` fields' JSON dict. FTS5 indexing keeps working unchanged; the index never sees the encoded RTF blob.
- Four other exhaustive `switch field.kind` sites extended with the new case: `Detail.swift` editorBody (renders `RichTextField`), `RecordsScreen.swift` columnWidth (320 px column same as longText), `FieldDisplay.swift` cell (renders the plain mirror, 2-line clamp), `ExportService.renderCell` (returns the plain mirror — CSV/HTML/PDF don't surface RTF natively).
- 7 new `RichTextValueTests` — JSON round-trip, missing-keys tolerance, NSAttributedString conversion produces RTF magic, size-budget boundaries, FTS body includes `plain` mirror, FTS skips records with no `plain`.

**Shape — slice B2 (RichTextEditor port + RichTextField wrapper)**:

- `Views/RichText/RichTextEditor.swift` is a near-verbatim port of PurpleTracker's 406-LOC editor. `NSTextView` wrapped in `NSViewRepresentable`, SwiftUI toolbar (bold/italic/underline/strikethrough, 3 heading levels, bullet/numbered lists, link with NSAlert dialog, foreground color, clear formatting), keyboard shortcuts (⌘B/I/U, ⇧⌘X, ⌘⌥1/2/3/0, ⇧⌘7/8, ⌘K). `RichTextRegistry` singleton bridges the SwiftUI toolbar to whichever `NSTextView` is in focus.
- **Load-bearing fix carried over verbatim**: `ensureAttachmentFileWrappers` synthesizes PNG/JPEG file wrappers for pasted `NSTextAttachment`s that have only `.image` set. Without this, RTFD encode drops the bytes and pasted screenshots come back as empty boxes. PurpleTracker proved this in real-world use; we keep the same shape.
- **NEW in this port**: `RichTextImagePolicy` enum (non-actor-isolated, pure functions over NSImage byte representations). Caps incoming image width at 1920 px; downscales preserving aspect ratio; prefers JPEG @ 0.7 for non-alpha images, PNG for transparent. Rationale: keeps notes under the CloudKit ~1 MB ceiling without compromising the E2E guarantee — compression isn't a confidentiality concession. A 1920-wide screenshot encoded as JPEG @ 0.7 is typically ~150 KB; you can fit 5+ images in a single note before hitting the budget.
- `Views/Fields/RichTextField.swift` is the adapter view that hosts `RichTextEditor` inside `Detail.swift`'s field-rendering form. Reads/writes the `{rtf, plain}` JSON dict via `fieldsBuffer`. Implements the **"live text storage" trick at save**: reads `NSTextView.textStorage` directly through `RichTextRegistry` to capture attachments that haven't propagated to the SwiftUI binding yet — same approach PurpleTracker's NoteEditorView uses. Enforces `RichTextLimits.fits` before writing; over-budget edits leave the buffer at the last-known-good state and surface the size error inline.

**Shape — slice B3 (seeded Note ObjectType + workspace)**:

- New `note` built-in in `SchemaSeed.swift` with fields: `noteDate` (`.date`, required), `title` (`.text`, required), `category` (`.select` — Personal / Work / Ideas / Journal / Reference), `body` (`.richText`). `primaryFieldKey: title`, `calendarDateKey: noteDate`, `kanbanGroupKey: category`. Color `#9D4DCC` (the brand purple), SF Symbol `note.text`.
- Added to `allTypes` between `plannerItem` and `person` so it appears second in the sidebar — high enough to be visually prominent without preempting Planner.
- `Views/Notes/NotesWorkspaceView.swift` is the two-pane shell. `HSplitView` with `NotesListView` left (min 280, ideal 320) and `NoteEditorView` right (min 480). Toolbar +button bound to ⌘N. Re-reads on remote-change notifications (CloudKit pulls). Records go through the standard `ObjectEngine.create` / `update` / `delete` — same sync + undo + FTS plumbing as every other type.
- `Views/Notes/NotesListView.swift` — search bar (filters on title + body's plain mirror), +button, date-grouped sections with friendly headers ("Today" / "Yesterday" / "Mon, Mar 5, 2026"). Row shows title + 2-line plain preview clamped. Context-menu delete.
- `Views/Notes/NoteEditorView.swift` — date picker + title field + RichTextEditor + Save button (⌘S) + Saved/Unsaved indicator. **1.2 s debounced autosave** via `DispatchWorkItem`. Saves on `onDisappear` and when `note.id` changes (i.e., user switches notes — flush-then-load to avoid losing in-flight edits). Same shape as PurpleTracker's `NoteEditorView.swift:64–96`.
- `ContentView.swift` branches at the type-router: when `selectedTypeId == "Note"`, swap `RecordsScreen` for `NotesWorkspaceView`. The two-pane workspace replaces table/kanban/calendar views — those views still work on Note records via the URL-bar override path (the user can construct a SavedQuery against the Note type and it surfaces on Today, etc.), but the default UX is the dedicated workspace.

**Deliberate omissions**:

- **No soft-delete on objects table.** PurpleTracker has `deletedAt` on `generic_note`; PurpleLife's `ObjectEngine.delete` is a hard delete with undo support via NSUndoManager. The undo path covers the "oops" case; full soft-delete would mean a v4 migration adding a `deleted_at` column to `objects` and threading `WHERE deleted_at IS NULL` filters through every fetch. Defer until users actually want a Trash UI.
- **No category color chips in the list rows.** The select-options carry `colorHex` values, but the list row is intentionally minimal (title + 2-line preview). Adding colored category dots is a one-line follow-up but it could overwhelm the row visually when previews are present.
- **No multi-window note editing.** The editor is part of the main window's `HSplitView`. Could be a separate `Window` (⌘N opens in a window), but that's a separate refactor and the in-window editor covers the common case.
- **No per-Mac category seeding.** The five seeded categories (Personal/Work/Ideas/Journal/Reference) appear once at first launch via the standard schema-seed path. Adding a sixth requires editing the schema in Settings — same as every other type.
- **No iOS port.** The schema model + RichTextValue port cleanly; the AppKit-backed editor doesn't. When the iOS app happens, the editor will need a UITextView-based equivalent of `RichTextEditor` — UIKit's TextKit 2 affordances are different. Documented as a known follow-up.

**Test coverage**: B1's 7 new `RichTextValueTests` cover the storage contract end-to-end. B2's editor is AppKit-backed and out of XCTest reach (same constraint as every other NSViewRepresentable surface in PurpleLife). B3's workspace is similarly UI-only. Counter total: **159/159 tests green** (was 152, +7).

**Honest current state of "everything encrypted at all times"**:

- **In transit**: ✅ TLS via CloudKit.
- **In iCloud (E2E)**: ✅ schema (`typeJSON`) + record fields (`fieldsJSON`) ride `CKRecord.encryptedValues` — the note body, including inline RTFD images, lives inside `fieldsJSON` and is therefore encrypted end-to-end.
- **At rest — settings.json**: ✅ AES-GCM wrapped via `EncryptedJSON` (slice A3).
- **At rest — attachment files**: ✅ AES-GCM wrapped via `EncryptedJSON` (slice A3).
- **At rest — SQLite DB**: ❌ still plaintext locally. The bytes that go through the network are encrypted, but `purplelife.sqlite` on disk holds plaintext JSON in `objects.fields_json`. **This is the remaining gap; slice A2 (SQLCipher swap) closes it.** Documented in CHANGELOG and to be called out in the Phase C whitepaper.

**Next slices**:

- **A2** — SQLCipher DB swap. Lands as a focused commit: change `project.yml` to a SQLCipher-capable GRDB fork, add `PRAGMA key` setup in `DatabaseService`, run `sqlcipher_export()` migration on first launch.
- **C1** — README + USER_MANUAL + INSTALL + PLAN.md docs sweep. Reflects the actual posture.
- **C2** — `Docs/SECURITY.md` customer-facing whitepaper.

### 2026-05-11 — Encryption foundation · slice A3: settings.json + attachment files encrypted (SQLCipher deferred)

Second-but-actually-third slice of the encryption-at-rest work. Plan-document order is A1 → A2 (SQLCipher) → A3 (settings + attachments); shipped order is A1 → A3 → A2-still-pending. The reason for the reorder:

**Why A2 was deferred**. The locked plan calls for switching `groue/GRDB.swift` (which doesn't bundle SQLCipher) to a SQLCipher-capable GRDB fork. Investigated mid-execution: the current dependency in `Package.resolved` is `groue/GRDB.swift` 6.29.3 — supports SQLCipher only via the `GRDBCIPHER` build flag plus a linked SQLCipher target, which means swapping to a different package URL (canonical fork: `duckduckgo/GRDB.swift`). That's the kind of change that wants a clean diff under the user's eye — adding a new SwiftPM dependency can require Xcode-level trust prompts, version resolution can produce a different transitive shape, and if it fails the project might land in an unbuildable state. Doing it inside a larger automated batch felt reckless. So the architectural work for at-rest encryption proceeded down the side-channel paths that don't need SQLCipher (settings + attachments), and SQLCipher's flip-the-switch lands as its own focused commit later.

The honest at-rest posture after this slice: **settings.json and every attachment file are AES-GCM ciphertext on disk**; only the SQLite database itself (objects + attachments metadata + FTS5 index) remains plaintext-local, relying on FileVault until A2 lands. The CloudKit `encryptedValues` E2E path is unaffected — the entire SQLite payload was already wrapped before leaving the device.

**Shape — settings.json**:

- `SettingsStore.init(keyResolver:)` takes a closure that returns the current `SymmetricKey?`. Default is `{ nil }` — keeps construct-time use trivial for tests and for the early property-initializer path in `AppState` where the keystore isn't yet wired. `setKeyResolver(_:)` re-points after construction.
- `load()` routes through `EncryptedJSON.unwrap` so the same code path reads both legacy plaintext (no magic) and slice-A3 ciphertext (magic-detected, decrypted). An encrypted-but-no-key state is a soft failure: log + leave defaults in memory rather than silently overwriting with them.
- `save()` routes through `EncryptedJSON.safeWrite` — which **refuses to write plaintext over a file that's already encrypted on disk**. This is the load-bearing invariant for the early-init seed save (`seedTodayQueriesIfNeeded` fires while the resolver is still nil). Without the guard, the seed save would clobber a previously-encrypted file with plaintext defaults.
- `AppState.init` wires the live resolver, then explicitly calls `settingsStore.load()` to decrypt anything that was unreadable during the resolver-less property-init pass, then calls `settingsStore.save()` to encrypt any plaintext file written during the seed step. The double-load is intentional belt-and-braces: it covers fresh installs, plaintext-upgrade installs, and already-encrypted-from-a-prior-launch installs in one path.

**Shape — attachments**:

- `AttachmentService` gained a `static var keyResolver: (() -> SymmetricKey?)?` set by `AppState.init`. Same dependency-injection shape as `SettingsStore` — services pull from a resolver rather than holding a `KeyStore` reference.
- `add(from:parentObjectId:fieldKey:)` (the only file-writing path) now wraps content via `EncryptedJSON.safeWrite`. **The sha256 stays plaintext-based** so dedup spans the encryption boundary cleanly: same content → same sha256 → same file on disk → only-one-encrypt-write thanks to the existing dedup check.
- New `read(sha256:) throws -> Data?` returns the decrypted bytes. New `image(forSha256:) -> NSImage?` is the convenience for view code. The legacy `fileURL(forSha256:)` is kept but its semantics are explicit in the docs now: the URL points at ciphertext post-A3, so callers must not feed it to `NSImage(contentsOf:)`. Two existing call sites (`AttachmentFieldEditor.swift:63`, `RecordsScreen.swift:696`) were converted to `AttachmentService.image(forSha256:)`.
- New `encryptExistingFilesIfNeeded()` is the one-shot upgrade sweep. Walks the attachments dir, wraps any file whose first 5 bytes aren't the `PLIF\x01` magic. Idempotent — every subsequent launch re-runs the sweep cheaply, and a file already encrypted is a one-`Data(contentsOf:)`-read + a header check. `AppState.init` fires the sweep once after the resolver is wired.
- AES-GCM nonces are random per-wrap. That means dedup-by-content has to operate on the plaintext sha256, not the ciphertext (two identical plaintexts wrapped twice would produce different bytes). The plaintext-sha256 contract is preserved deliberately for exactly this reason.

**Deliberate omissions**:

- **The SQLite database itself stays plaintext** until slice A2 ships. The relevant gap on disk: `objects.fields_json` carries every record's user-typed content (note bodies once Phase B lands, person names, book titles, etc.). FileVault is the only at-rest defense for that surface until A2.
- **No per-file salt or HMAC** on attachment files beyond AES-GCM's built-in auth tag. AES-GCM authenticates the ciphertext under the DEK; that's the integrity guarantee. Per-file salts would matter if we were *deriving* a per-file key from the DEK + filename, but we're using the DEK directly — so a salt would add complexity without lifting any security property.
- **No streaming encryption for large attachments.** `EncryptedJSON.wrap` works on `Data` end-to-end. For multi-GB photo libraries, this would balloon memory on import; for the Life-OS scale (likely largest single attachment: a multi-MB photo) it's fine. Revisit if a user ships a 500 MB video.
- **No re-key flow** (changing the DEK and re-encrypting everything). Out of scope — passphrase change re-wraps the DEK without touching data, which is what users actually want. A full re-key would only matter if the DEK itself was suspected compromised, which is a separate threat model.

**Test coverage**: 6 new `AtRestEncryptionTests` — encrypted attachment write + read round-trip, wrong-key read throws (AES-GCM tamper detection), launch-time sweep wraps plaintext idempotently, dedup survives encryption (two adds of identical content → one encrypted file, both reads work), settings.json encrypted round-trip, settings.json safeWrite refuses to downgrade. **152/152 tests green** (was 146, +6). The new tests carry explicit `AttachmentService.keyResolver` setup in their setUp/tearDown so they exercise the encrypted path (XCTest-mode AppState skips the bootstrap, so existing `AttachmentServiceTests` continue to test the plaintext path — both paths are now covered).

**Effect on remaining slices**:

- **A2 still open**. The remaining gap. Lands as: switch `project.yml` package URL to a SQLCipher-capable GRDB fork, add `Configuration.prepareDatabase { try db.usePassphrase(...) }` to `DatabaseService`, run a `sqlcipher_export()` migration if a plaintext `purplelife.sqlite` is found. Tests + verify with `file purplelife.sqlite` reports "data" not "SQLite 3.x database".
- **B1–B3** (notes feature) are now safe to start. The richText body lives inside `fields_json`, which is encrypted via `CKRecord.encryptedValues` on the wire and (after A2) on local disk. Pasted images live inline inside the RTFD body inside `fields_json` — no CKAsset path needed.
- **C1–C2** (docs + whitepaper) — wait until A2 ships so the whitepaper can describe the actual posture rather than an interim one.

### 2026-05-11 — Encryption foundation · slice A1: KeyStore + crypto primitives landed

First slice of the multi-phase encryption-at-rest work that backs the upcoming WYSIWYG Notes feature (full plan in `~/.claude/plans/luminous-hugging-lightning.md`). The goal of this slice is narrow: land the cryptographic primitives and the keystore lifecycle infrastructure without touching any user-data persistence path yet. Slices A2 (SQLCipher DB) and A3 (encrypted settings + attachment files) are what actually start sealing bytes on disk.

**Shape**:

- **Ported four files verbatim-ish from `PurpleIRC/Sources/PurpleIRC/`**: `Crypto.swift`, `KeychainStore.swift`, `EncryptedJSON.swift`, `KeyStore.swift`. Adapted at the seams, not in the cryptography:
  - `EncryptedJSON.magic` changed to `"PLIF\x01"` (was `"PIRC\x01"`). The whole point of a 5-byte magic header is unambiguous file-format identification — if PurpleIRC and PurpleLife shared the magic, an accidental file move between Application Support dirs could deserialize the wrong shape. Cheap insurance.
  - `KeychainStore.service` is `"com.purplelife"` (was `"com.purpleirc"`). Independent service slot per app.
  - PurpleIRC's `CredentialRef` (per-profile passwords reference resolver) didn't port — PurpleLife has no multi-profile model.
- **KeyStore gained a "Keychain-managed" mode** that PurpleIRC didn't have. The locked decision from the plan is "first launch generates a random DEK, stashes it in the Keychain, opens silently — passphrase is opt-in." So in addition to PurpleIRC's `setupWithPassphrase` flow, there's a new `setupKeychainManaged()` that creates the DEK and stores it only in the Keychain (no `keystore.json` on disk).
  - `state` is still `{.notSetup, .locked, .unlocked}` but the `.unlocked` state can be reached two ways: with or without `hasPassphrase`. The Security settings UI branches on `(state, hasPassphrase)`.
  - `addPassphrase(_:)` layers a passphrase on top of an existing Keychain-managed install. `removePassphrase(currentPassphrase:)` reverts to Keychain-managed mode after verifying the current passphrase (so an attacker at an unlocked Mac can't strip protection without proof).
  - `lock()` is a no-op when `hasPassphrase == false` — otherwise locking a Keychain-managed install would brick it (nothing to re-prompt for). Returns Bool so callers can tell the difference.
- **`AppState` bootstraps the keystore on init.** If `state == .notSetup` and we're not under XCTest, run `setupKeychainManaged()` automatically. Every existing install upgrades to "has a DEK in the Keychain" on first launch after this slice, and every fresh install gets the same. Slices A2/A3 can assume a DEK is available.
- **`SecuritySettingsTab`** (new) surfaces the four user-visible actions: Add passphrase, Change passphrase, Remove passphrase, Lock now. Plus Reset (destroys all data) as the forgot-passphrase escape hatch — it deletes `keystore.json` and `KeychainStore.deleteAll()` and then auto-bootstraps a fresh Keychain-managed DEK so the next persistence touch doesn't fail on a missing key.

**Deliberate omissions**:

- **No data is yet encrypted on disk.** SQLite is still plaintext. `settings.json` is still plaintext. Attachment files are still plaintext. The keystore infrastructure is in place; the persistence-layer wiring lands in A2 and A3. Shipping it this way keeps the slice scope tight and means if anything goes wrong with the keystore in real-world use, the data isn't held hostage by an encryption layer that hasn't been battle-tested yet.
- **No `SecAccessControl` (Touch ID gating) on the Keychain item.** Plain `kSecAttrAccessibleWhenUnlocked` for now. Adding a biometric gate is straightforward later but adds UX cost; revisit if a user requests it.
- **Reset doesn't automatically delete the user's data files.** It clears the keystore and Keychain, then bootstraps a fresh Keychain-managed DEK. Existing ciphertext on disk (after A2/A3) becomes unreadable garbage by design — the user can then start fresh or restore a backup. We deliberately don't `rm -rf` the support dir for the user; that's a separate operation they can do in Finder if they want.
- **No CloudKit interaction yet.** The keystore is a per-Mac artifact (different DEKs on different Macs — they share data via CloudKit's own `encryptedValues` E2E, not by ferrying our DEK). No sync, no peer notification of "I rotated my passphrase". The whitepaper (Phase C2) will explain this model.

**Test coverage**: 22 new `KeyStoreTests` — 6 for Crypto primitives (AES roundtrip, wrong-key rejection, tamper detection, PBKDF2 determinism + sensitivity, random bytes), 4 for EncryptedJSON envelope (magic round-trip, nil-key passthrough, encrypted-without-key throws, safeWrite never downgrades), 5 for passphrase lifecycle (setup → encrypt → unlock from disk → wrong-passphrase rejection → change passphrase → encrypt-while-locked throws), 7 for Keychain-managed lifecycle (silent reopen, lock no-op, add passphrase, can't add twice, remove passphrase, wrong-current rejection, reset wipes everything). **146/146 tests green** (was 124, +22). The one bug found during the run — `test_unlockFromDiskWithRightPassphrase` had an over-eager `defer cleanup(store)` that wiped `keystore.json` before the second instance tried to read it — was fixed in the test, not in production code.

**Next slices**:

- **A2** — Switch GRDB to SQLCipher; one-shot migration of the existing plaintext `purplelife.sqlite` to a SQLCipher-encrypted file keyed by the DEK. Architectural change: `DatabaseService` becomes "ready when keystore unlocks" rather than always-open. Biggest risk: every call site that does `DatabaseService.shared.dbPool.write { ... }` needs a readiness check; expect a sweep across `ObjectEngine`, `AttachmentService`, `SearchService`, `CloudKitSyncService`.
- **A3** — Wrap `settings.json` + attachment files with `EncryptedJSON`. The attachments-dir sweep needs to be idempotent (rerunning on launch is fine; double-wrapping isn't).

### 2026-05-11 — Appearance theming · slice 3: JSON import/export shipped

Closes the stretch goal queued in slice 1's entry. Themes ship between Macs as `.purplelifetheme.json` files now — no settings.json hand-editing required.

**Shape**:

- **`Services/ThemeIO.swift`** is pure functions only (encode / decode / sanitize / write / read). NSSavePanel + NSOpenPanel usage stays in the views that call them — keeps the service unit-testable without AppKit and concentrates the AppKit surface where it has to live anyway.
- **File format = the existing `UserTheme` Codable shape verbatim.** No envelope, no version field, no migration plumbing. The lenient `init(from:)` on `UserTheme` (synthesized, with Optional fields) handles future format drift; the defensive `materialised` accessor handles corrupt hex strings without crashing the renderer. Adding a format version is the kind of thing that *feels* responsible but creates an actual migration debt — when we genuinely need it we can add it without breaking existing files (just look for a `version` key, default to 1).
- **Fresh UUID on import** is the key correctness call. Without it, exporting a theme then importing it back gets you a no-op (existing entry overwritten in place); importing on a second Mac where the same theme already exists silently destroys the recipient's copy. Treating the file as palette data + provenance metadata, not as identity, is the cleaner contract.
- **Right-click Export on every theme card** (including built-ins) — built-ins are synthesized to a `UserTheme` via `duplicate(of:)` on demand so the export path doesn't need to branch on theme type. Recipient gets a "Custom from Lavender" entry they can rename.
- **Three entry points for Export, all going through the same code**: right-click on any theme card, the builder footer (exports the draft mid-edit without committing), and indirectly via the import flow (a user can edit, export, then import again to get a second copy).
- **Filename sanitization** strips `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, control characters, and leading dots; falls back to `"theme"` if the result is empty. The leading-dot strip is the load-bearing one — without it a theme named `.bashrc` would write a hidden file the user couldn't find in Finder.
- **Pretty-printed + sorted keys** for the encode. Diff-friendly when iterating; tiny size penalty (themes are ~3 KB).

**Deliberate omissions**:

- **No custom UTType registration** for `.purplelifetheme.json`. That would mean a `CFBundleDocumentTypes` entry in Info.plist, an icon asset, an LSItemContentTypes declaration, and probably a custom UTI. The `.json` suffix is fine — any JSON tool can open these files, the system's NSSavePanel doesn't fight us, and Finder shows them as JSON documents. If someone later wants a custom Finder icon for `.purplelifetheme.json`, that's a self-contained chore.
- **No batch export of all user themes.** One-at-a-time covers the realistic sharing case ("send me your Lavender variant"); a `.zip` of all themes is more affordance than the use case warrants.
- **No "import everything from a folder" affordance.** Same reasoning — one-at-a-time covers it; the user picks the file they want.
- **No JSON validation beyond Codable decode.** The format IS UserTheme; `materialised`'s defensive parser handles bad hex strings; missing required slot keys throw on decode and surface as the inline import-error message. No need for a schema-validation layer.
- **No CloudKit sync of theme preferences.** This stays a per-Mac preference per the slice-1 policy. Users with multiple Macs can ship their themes via JSON export/import — which is arguably better than auto-sync (you decide what to share and when).

**Test coverage**: 10 new `ThemeIOTests` — sanitization (path separators, control chars, leading dots, empty fallback), default-filename construction, encode produces pretty-sorted JSON, decode assigns fresh UUID, full write→read roundtrip through `/tmp`, corrupt-JSON / missing-key / missing-file failure modes. **119/119 green** (was 109, +10). NSSavePanel / NSOpenPanel paths aren't unit-tested (same constraint as every AppKit panel in the suite); the routing layer is small enough to verify by hand.

**What's still open**:

- **CloudKit-synced theme preference** — deferred by policy in slice 1; the export/import path covers the multi-Mac case now.
- **Theme builder on iOS** — when the iOS app happens, UserTheme + ThemeIO port directly; only the SwiftUI views need touch-first rewrites.

### 2026-05-11 — Appearance theming · slice 2: WYSIWYG builder shipped

Closes the queued slice from the morning's slice-1 entry below. Users can now author and edit custom themes in-app rather than hand-editing settings.json.

**Shape**:

- **HSplitView sheet** — editor on the left (Form grouped by Surfaces / Text / Lines / Accent), preview on the right (mini chrome with its own Light/Dark toggle). Each editor row exposes two `ColorPicker`s side-by-side (Light then Dark) so a slot is tuned for both modes in one place — different from PurpleIRC's builder where each theme is single-mode and the dialog has only one picker per slot.
- **Preview reads hex strings directly off the draft** rather than going through `PurpleTheme.Slot.color` / `Color(light:dark:)`. The preview-pane Light/Dark toggle is a local `@State`, not the SwiftUI `\.colorScheme` environment, so the preview honors the toggle reliably without depending on whether NSColor's dynamic-provider resolver picks up SwiftUI's preferred-scheme propagation. Cleaner contract, easier to reason about.
- **Commit paths are pure functions** on the model layer — `UserTheme.upsert(_:in:)` and `PurpleTheme.resolveAfterDelete(currentID:removedID:basedOn:)`. Pulled out specifically so they're unit-testable without instantiating SwiftUI views. The builder view's `commitSave`/`commitSaveAs`/`commitDelete` are now ~5 lines each, all delegating to these helpers + the AppState pass-through.
- **Delete fallback** lands in `resolveAfterDelete`: deleting an active theme falls back to its `basedOn` built-in (when valid), else Royal Purple. Deleting an inactive theme leaves the active selection alone — a user clicking Delete on a theme they aren't using shouldn't have their current selection flipped.
- **Sheet state managed via a single `BuilderTarget` enum** carrying `draft: UserTheme` + `isNew: Bool`, presented via `.sheet(item:)`. Same modifier handles both "New theme" (fresh duplicate of currently-selected) and "Edit" (existing theme) — `isNew` only controls whether the Delete button is rendered.

**Deliberate omissions**:

- **No per-slot reset-to-base-theme button.** The user can already do this by clicking the slot's ColorPicker and entering a new hex; or by deleting and starting fresh from the same base. Adding the affordance would mean tracking `basedOn`'s slot values, which is more bookkeeping than the value warrants for a first cut.
- **No JSON import/export of themes.** Mentioned as a stretch goal in the slice-1 entry; deferred because (a) settings.json hand-edit already covers the import case for power users, (b) the export case wants a sensible file naming + Finder integration UX, which is a separate small task, and (c) CloudKit sync of theme preferences would conflict with the per-Mac local-preference policy in the slice-1 entry. If the request comes up later, the natural shape is a single-theme `.json` writer/reader that round-trips a UserTheme verbatim — three or four new lines on top of the existing Codable shape.
- **No multi-window builder.** The sheet is modal over the Settings window. Could be a `Window` for users who want to compare against the live app, but that's a separate refactor (`@Environment(\.openWindow)` plumbing, window restoration, etc.) and the sheet covers the common case.

**Test coverage**: 6 new `ThemeTests` cover the persistence helpers — upsert appends, upsert replaces preserving order, delete-fallback uses `basedOn` when valid, delete-fallback uses Royal Purple when `basedOn` is unknown/nil, delete preserves current selection when deleting an inactive theme. **109/109 green** (was 103, +6).

**What's still open** (none of these block):

- **JSON import/export of themes** (stretch from slice 1; see deliberate omission above).
- **CloudKit-synced theme preference** (deferred by the per-Mac policy in slice 1).
- **Theme builder on iOS** when the iOS app happens — the UserTheme persistence shape ports directly; only the sheet UI needs a touch-first rewrite.

### 2026-05-11 — Appearance theming · slice 1 shipped; prior "themes deferred" decision reversed on accessibility grounds

The 2026-05-10 WeightTracker-subsumption entry below records the prior call: **defer themes, keep the oklch design language pure**, on the reasoning that layering arbitrary themes (WeightTracker's six named palettes specifically) would muddy a coherent brand voice. That call held while the work was framed as cosmetic polish.

The user reopened the question this session framing it as **accessibility, not cosmetics**: contrast, surface tone, and appearance override (light/dark/auto regardless of macOS setting) are how some users *can* use the app at all. That changes the trade — customization power now outweighs the design-coherence concern.

The compromise that resolves both: defaults stay the design-handoff oklch palette (now named **Royal Purple**), every built-in is **purple-rooted** so the brand voice carries, and custom themes are an additive surface — picking one is a deliberate act, not a default.

**Shape shipped this slice**:

- **Theme + appearance are orthogonal axes.** PurpleIRC's design bakes light/dark into the theme (Solarized Light / Solarized Dark as separate themes). PurpleLife splits them: every `PurpleTheme` has paired `Slot(light:, dark:)` per chrome token, and `AppearanceMode` (`system` / `light` / `dark`) selects which slot resolves at render time. So "Auto" stays available no matter which theme you pick — which is what the user asked for explicitly.
- **5 built-ins, purple-led.** Royal Purple (default — the existing oklch palette), Lavender (soft pastel), Plum (deep saturated), Heather (warm mauve), High Contrast (accessibility-focused — pure white/black surfaces, bold purple accent, strong strokes). High Contrast is the entry point for users who need maximum separation; the rest are voice-of-purple variations.
- **Static facade pattern for the renderer.** `Views/Theme.swift` was an `enum` of static design tokens accessed as `Theme.bg`, `Theme.accent`, etc. — used 32 times across 7 files. Converting all call sites to `@Environment(\.purpleTheme)` would have touched dozens of subviews. Instead, the enum became a thin facade reading from `Theme.current: PurpleTheme` (mutable, `@MainActor`-isolated); SettingsStore writes through it, AppState's Combine bridge republishes on every change, and views observing AppState re-render and pick up the new colors on next body evaluation. **Zero call-site changes.** Trade-off acknowledged: the static-state shape means previewing a non-current theme (e.g. theme-card swatches in the picker) reads the slot Colors directly off the `PurpleTheme` value rather than through `Theme`. That's the right seam — slice 2's WYSIWYG builder will use the same pattern.
- **UserTheme persistence shipped now, builder UI deferred to slice 2.** Hex-pair Codable mirror of `PurpleTheme` lives in the same file; `duplicate(of:name:)` snapshots a built-in, `materialised` produces the runtime value. Users can hand-edit `userThemes` in settings.json today and the theme appears in the picker with a "Custom" badge. Slice 2 brings the WYSIWYG editor (ColorPicker per slot × light/dark, live preview, Save / Save As / Delete). Splitting this way de-risks slice 1: the storage format is locked, so the builder is pure UI work.
- **Latent settings.json regression fixed in passing.** `AppSettings` was using synthesized Codable with property defaults — which Swift does *not* honor on decode. Missing-key tolerance was effectively non-existent; any field added by a later phase would throw on decode of an older settings.json, `SettingsStore.load`'s `try?` would swallow it, and the user would silently lose every prior setting. New custom `init(from:)` uses `decodeIfPresent` for every key, so upgrades preserve user state. The original PLAN comment claiming "Codable's missing-key tolerance keeps reads of older settings.json files compatible without a migration" was always wrong; the comment + the behavior are now both correct.
- **`.preferredColorScheme` at all five scene roots** — main window, schema editor window, quick switcher, Settings, menu-bar extra. `.system` maps to `nil` (let the OS decide). Switching appearance applies live; no relaunch.

**Test coverage**: 15 new `ThemeTests` covering built-in resolution + collision policy, UserTheme roundtrip, hex parser surface, AppearanceMode → ColorScheme mapping, and crucially **backward-compatible decode of a pre-theme settings.json**. **103/103 tests green** (was 88).

**What's open for slice 2**:

1. **WYSIWYG ThemeBuilderView** — sheet with HSplitView (editor / live preview), ColorPicker per slot × light/dark, Save / Save As / Delete. Pattern lifted from `PurpleIRC/Sources/PurpleIRC/ThemeBuilderView.swift` (482 LOC).
2. **Picker entry points** — "New theme…" button in the Appearance tab (duplicates the currently-selected theme as the editor's starting point) and "Edit theme…" on each user theme card.
3. **Delete fallback** — when deleting an active user theme, restore to its `basedOn` built-in (or Royal Purple if `basedOn` is nil / not found).
4. *(stretch)* import/export themes as a JSON file so users can share palettes between Macs without setting up CloudKit sync for the preference.

### 2026-05-10 — App Nap likely cause of "client went away"; assertion held while sync is enabled

Follow-up #2 from earlier today. The soft-recovery patch (`68b1bba`) treats the symptom — re-create the `CKContainer` on the specific error string and retry once. The deeper question of why `cloudd` was dropping our binding remained.

Best theory after more thought: **macOS App Nap was suspending the receiving app between subscription pushes.** Symptoms match exactly:

- Receiver only sees the error after a cross-device push (when the daemon tries to deliver to a napped process)
- App restart fixes it (new process has a fresh activity state, daemon re-binds)
- "Sync now" doesn't fix it (the process is awake again because the user clicked, but cloudd's earlier attempt already marked us as "gone")

Fix: `CloudKitSyncService.start` now opens a `ProcessInfo.beginActivity(options:reason:)` assertion with `[.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled]` for the lifetime of the service. Same pattern Apple recommends for media players and download managers — apps that need to stay live in the background for an external trigger.

Deliberate omissions:
- `.latencyCritical` — we don't need elevated CPU, just liveness.
- `.idleSystemSleepDisabled` — the Mac going to sleep at night should still work. App Nap suppression ≠ system sleep prevention.

This is theory + prophylactic. Verification is "does 'client went away' stop appearing across normal use?" — only the user can confirm over time. If it still appears, the next investigation rungs are longer-lived `CKDatabase` references (vs the current computed property), a dedicated `OperationQueue` for CK ops, or fewer Task hops in the subscription handler.

### 2026-05-10 — Phase 4 acceptance gate verified PASS — Mac→Mac sync is near-instant

Closes the long-standing Phase 4 gate that's been queued as follow-up #1 since the original build session.

**Test setup**: two Macs (the dev Mac and a second one), same Apple ID, same iCloud account, both running `PurpleLife.app` v0.1.187+ from the same commit (`e8e4439`). Both signed with Apple Development + the iCloud + APS entitlement, both on the same dev team `SRKV8T38CD`.

**Result**: changes made on either Mac appear near-immediately on the other, both directions. The Phase 4 acceptance gate ("a typical edit syncs Mac→Mac in <5 s") is met with comfortable margin — the silent-push subscription path is working as designed.

**Observations worth recording**:

- **First-launch bootstrap on a fresh Mac (Mac B) hung at "Setting up sync…" for ~5 minutes** before transitioning to `Synced`. Quit + relaunch did not shortcut the wait. Eventually self-resolved. Possible causes: first-time CloudKit container handshake for a new device, APS registration latency on a fresh install, or the initial pull doing something silent that the status badge doesn't surface. **This is a real follow-up** — the status badge should at minimum show progress (e.g. "Initial pull…" with a progress count), or the bootstrap steps should each have a timeout-and-retry so they're observable.
- **`Sync error: client went away` is reproducible, not transient.** Every cross-device change drops the *receiver* into `.error` state immediately after the change is applied. "Sync now" does **not** clear it (a fresh `pull()` hits the same error). Only quitting the app and relaunching restores `.idle`. The receive itself works — the new record arrives in the local DB and the UI reflects it — but the sync footer reads "error" until restart. This is a real follow-up bug; logged as new follow-up item. Possible causes worth investigating: stale `CKDatabase` reference after the first successful fetch, the `CKFetchRecordZoneChangesOperation`'s lifecycle going out of scope while still pending, or our `runFetchOperation` continuation being resumed by a daemon-side timeout we don't notice. Mitigation worth trying first: catch the specific error in `pull()`'s catch and re-run `bootstrap()` (rebuild the container reference, re-register the subscription) automatically; if that succeeds, swallow the error.
- **The UI-refresh-on-remote-changes fix in this same session** (`e8e4439`) was load-bearing — without it, the new records would have arrived in the local DB but not appeared in the records list, making the verification visually deceptive. Glad we fixed it before testing.
- **Schema sync** wasn't separately exercised in this session but the same APS subscription wakes both halves, so a parity-class result is expected. Worth a follow-up trial.

**Effect on follow-up list**: item #1 closed. Phase 4 row in `README.md` upgraded from "acceptance infrastructure met, latency unverified" to "fully met."

### 2026-05-10 — Schema editor polish: drag-from-palette + reorder via menu

Last slice of the prototype-polish follow-up. Two changes worth noting:

- **Drag-from-palette to add a field.** `FieldKindTransfer` is the in-process Transferable; palette tiles are `.draggable`, the field list is `.dropDestination`. Drag and click both call `addField(kind:)`. Drag preview tints the tile with the accent color so it reads as active. A dashed dropzone hint appears under short field lists to telegraph the affordance — auto-hidden once the list grows past two rows.
- **Move up / Move down** in each field row's menu. Backed by a new `SchemaRegistry.moveField(fieldId:onTypeId:by:)` that operates by relative offset and routes through `upsertType` — same undo + sync semantics as any schema mutation. **Full row-drag-to-reorder is deferred**: doable but requires per-row drop-position math and a custom drag preview, which is more surface than the affordance is worth right now. Menu reorder covers the actual use case.

**Why this finishes the polish sprint**: the palette → field-list drag is the most distinctive gesture in the prototype's `ScreenSchema`. It shipped here. The full multi-tab schema canvas (Default views / Permissions / Templates / Automations) is part of the prototype but not part of the v1 product — those are pure conceptual surfaces with no current backing functionality.

### 2026-05-10 — Detail polish: two-pane with "Linked from" rail

Second slice of the prototype-polish follow-up. The detail sheet now matches `Design/purplelife/project/screens-dark.jsx ScreenDetail` shape-wise.

- **Two-pane layout** (`HStack` + `Divider` + 320 px right rail). Min sheet size bumped to 880 × 560 — the right rail isn't useful below ~700 px main width.
- **"Linked from" rail** is the meaningful win. Powered by a new `ObjectEngine.recordsLinkingTo(recordId:schema:)` cross-type scan that walks every record, checks every `.link` field, returns matches with resolved type. O(N · F) per open — fine at personal scale, an index can land later if it bites.
- **Hero block** at the top of the main pane: large rounded square with the type's icon tinted to its accent color, type name above the record's title in bigger bold type. Replaces the old icon-and-name header.
- **Click-through navigation**: tapping an inbound row sets `appState.openRecordRequest` and dismisses the sheet. `RecordsScreen` already observes this (used by Quick Switcher), so navigation flows the same way as ⌘K. No new plumbing.
- **Created / updated stamps at the bottom of the rail** — the prototype shows a richer per-mutation history. We don't keep that log yet; surfacing the stamps we already have avoids inventing new persistence just to fill the section.

**Why this matters**: before this commit there was no way for a user to see "what other records link here?" — they could follow links forward via picker, never backward. For a Life OS that's a structural problem (e.g., open a Camera record, you couldn't see which Photo Shoots use it). The rail closes that loop.

### 2026-05-10 — Today polish (timeline + linked-from rail)

First slice of the prototype-polish follow-up. The Today screen visually approaches `Design/purplelife/project/screens-light.jsx ScreenToday` while staying within the data-driven model.

- **Two-column layout** (`HStack` + `Divider` + fixed-width 320 right column). Both columns scroll independently. The right rail uses `Theme.sidebarOpaque.opacity(0.4)` for a distinct surface tone.
- **Timeline is auto-generated, not a SavedQuery.** It walks every record across every type, picks the type's `calendarDateKey` (or first date-bearing field), keeps anything whose value lands on today's calendar day, sorts chronologically. Render uses time-on-left (h:mm a, "all day" for date-only), a 10pt colored dot keyed to the type's accent, a 1pt connector line drawn behind the dots, and the same card chrome as the existing QueryPanel result cards. Section is omitted entirely when nothing's scheduled — no "no events today" empty state, just clean main column.
- **Right rail is named-SavedQuery lookup.** Currently shows two cards: first result of the seeded "Currently reading" SavedQuery and of "Latest weight". Cards collapse silently when the query is missing or empty. Adding a third card later is one line — `railCard(forSavedQueryNamed: <name>, subtitle: <heading>)` — no new data model.
- **Why named lookup vs a separate `railQueries: [SavedQuery]` list**: chose simplicity for v1. The two cards we want are already saved queries we ship; bringing in a second collection plus customization UI is more work than the affordance is worth right now. If users want to customize the rail, a future commit can introduce the second list (and a corresponding tab in `SavedQueriesEditor`).
- **Phase 3 acceptance gate still holds.** The view doesn't branch on hard-coded type ids — the timeline is one cross-type scan over engine data, and the rail is name-lookup over `appState.settingsStore.settings.todayQueries`.

### 2026-05-10 — Undo: NSUndoManager wired through ObjectEngine + SchemaRegistry

Closes the undo half of the daily-use ergonomics work that was split out earlier today.

- `ObjectEngine` gained a static `undoManager: UndoManager?`. Each of `create` / `update` / `delete` registers an inverse handler. Delete's inverse uses the new `restore(_:)` helper that re-inserts at the original id — preserving inbound `link` field references from other records, which would have broken if undo created a fresh-UUID copy.
- `SchemaRegistry` gained an instance `undoManager: UndoManager?` and uses **snapshot-based** undo: each mutation captures the full `types` array + `hiddenBuiltInIds` set before applying the change; undo restores the snapshot. Coarse on purpose — the schema is small (a handful of types each ~KB) and snapshot/restore is bulletproof against per-mutation invariants we'd otherwise have to reason through (renames vs adds vs option edits vs partial field edits).
- **Synchronous main-actor dispatch** in the `registerUndo` helpers: `MainActor.assumeIsolated { handler() }` rather than `Task { @MainActor in handler() }`. The Task hop defers execution past the caller's next statement, which broke the unit tests' synchronous "undo, then assert" pattern. NSUndoManager dispatches the handler on the calling thread; for the env-injected manager that's always main, and for tests the call site is also MainActor — so `assumeIsolated` is safe in both contexts and gives synchronous semantics.
- **Env undoManager is wired in three places**: `ContentView.onAppear` (covers Today and the empty-detail screen), `RecordsScreen.onAppear` (the type list), `SchemaEditorScreen.onAppear` (its own window with its own UndoManager). All three set both `ObjectEngine.undoManager` and `appState.schema.undoManager` so ⌘Z works regardless of which surface is focused.
- **Undo of a hide/show doesn't fan out to CloudKit**. `hiddenBuiltInIds` is per-device by design, so the undo restores only the local set.
- **Undo of a schema change bumps `updatedAt`** when fanning out — the user's explicit undo wins LWW on this device's next push, which is the right semantics ("the user just took an action, that should propagate"). An undo can't roll the clock back on the cross-device LWW front; it can only express new local intent.
- **Cross-device undo behavior**: an undo on Mac A fans out via the same sync paths as a normal mutation. Mac B sees the inverse change as a new write. There's no special "undo over the wire" semantic — that would require a multi-peer redo log, which is far beyond what a personal multi-Mac app needs.

**Test coverage**: 6 new `UndoTests` cover create/update/delete + redo + schema upsert + setHidden. The cross-device behavior isn't unit-testable here (same constraint as the silent-push positive case); the Mac→Mac trial that's still queued for the Phase 4 acceptance gate will exercise it.

**Effect on follow-up list**: undo is closed.

### 2026-05-10 — Daily-use ergonomics: menu-bar quick capture + ⌘N / ⌘1–⌘9; undo split out

Closes the menu-bar + shortcuts halves of follow-up #2. Real `NSUndoManager` integration is split off into its own follow-up — it touches every mutation path in `ObjectEngine` and `SchemaRegistry` and rushing it alongside UI work invites subtle bugs.

**Quick-capture popover** uses SwiftUI's `MenuBarExtra` (macOS 13+ — fine for our 14+ floor). The popover is a single small view (`Sources/PurpleLife/Views/QuickCaptureMenu.swift`) that picks the type's `primaryFieldKey` (or first text-bearing field as fallback), creates the record via `ObjectEngine.create`, and clears for repeat capture. The last-used type id is persisted in UserDefaults (`PurpleLife.quickCapture.lastTypeId`) so subsequent invocations default to whatever the user picked last.

**Keyboard shortcuts** route through `NotificationCenter` rather than via direct AppState references inside the App-scope `Commands` block. Reason: SwiftUI Commands don't see `@EnvironmentObject` injected into individual scenes — the natural way to access AppState from a Commands block would be to thread it through a parent observable, which is more refactor than the affordance is worth. Notification names are static constants on `AppState` so views and the App scope share a single source of truth (`AppState.newRecordRequestedNotification`, `AppState.jumpToTypeIndexNotification`).

- **⌘N** is bound via `CommandGroup(replacing: .newItem)` so it overwrites SwiftUI's default "New Window" command (we use a single `WindowGroup`; a second window would just be another copy of the same UI).
- **⌘1…⌘9** are nine fixed menu items with generic labels ("Jump to type N"). The label is a fallback for menu-browsing; the shortcut is the affordance. Making labels reactive to `schema.visibleTypes` requires plumbing AppState into the App-scope Commands block — deferred.
- Notification listeners are scoped: `RecordsScreen` only acts on ⌘N when `appState.selectedTypeId == typeId` (multiple `RecordsScreen` instances can briefly co-exist in the SwiftUI hierarchy after a type switch); `AppState.init` resolves the jump-to-type index against the current `schema.visibleTypes` (out-of-range = no-op).

**Tests**: 51/51 still green; no new tests. The new code is App-scene wiring + a SwiftUI popover view — neither testable without a UI test host. The notification-routing logic could in principle be unit-tested with a fixture observer, but the surface is small enough that it's cheaper to verify by hand than to scaffold.

**Effect on follow-up list**: item #2's first two halves are closed. Undo is split out as a new item.

### 2026-05-10 — Schema versioning: mirror schema through CloudKit + defensive merge

Closes follow-up #3 ("schema versioning across synced peers"). The original `PLAN.md` § Open question called for a sketch before Phase 4; that never landed and the gap created two real failure modes:

1. **Invisible field.** Mac A adds a field to Person, writes a record using it. Mac B receives the record but doesn't know the field exists, so the cell renders blank.
2. **Silent data loss.** Mac B then edits the same record locally. The form only shows the local schema's fields, so `ObjectEngine.update` writes back a JSON blob that omits Mac A's new field — the data is gone before the schema update arrives.

Two prongs of fix; both shipped together because either alone leaves a hole.

**Schema sync via CloudKit.** Same shape as object sync — one CKRecord per `ObjectType`, plaintext `updated_at` for LWW, full serialized type in `encryptedValues.typeJSON`. New record type `PurpleType` in the same `PurpleLifeZone`. The existing `CKDatabaseSubscription` is database-scoped, so silent push wakes both record-type changes and schema-type changes without new APNS plumbing.

Bootstrap order matters: `pushPendingLocalSchemas()` runs before `pushPendingLocalChanges()`, and `runFetchOperation` partitions inbound changes into "type" vs "object" buckets and applies types first. The reason: an arriving object record needs its type already present so `applyRemote` can hand the right `ObjectType` to `SearchService.upsert(record:type:)` for FTS reindexing. Without ordering, the FTS reindex would silently skip records whose type hasn't arrived yet.

`hiddenBuiltInIds` (per-device sidebar visibility) is **not** synced. Different Macs may want different types in the sidebar — that's user preference, not data.

**Defensive merge in `ObjectEngine.update`.** Even with sync running, there's a window between record-arriving-on-peer and schema-arriving-on-peer. The merge closes that window: `update` reads the existing JSON, then overlays the incoming fields. Keys absent from the incoming dict are preserved verbatim. Same intent as the existing `SchemaRegistry.removeField` decision ("the field's data is left in place — old keys are just unreferenced") — additive, never destructive.

**Per-type `updatedAt`.** New optional field on `ObjectType`. `SchemaRegistry.load` backfills the epoch timestamp for pre-schema-sync types so they sort "older than anything" — first remote update wins LWW. `upsertType` stamps `now` on every mutation. `applyRemote` only overrides the local copy when the remote stamp beats it.

**Test coverage**: 5 new `SchemaVersioningTests` cover the deterministic surface (defensive merge in both directions, epoch backfill, upsert stamping, applyRemote LWW). The CloudKit push/pull plumbing isn't unit-testable for the same reason silent push isn't — covered by the Mac→Mac trial that's still queued as item #1.

**Effect on follow-up list**: item #3 closed.

### 2026-05-10 — WeightTracker subsumption complete (5 slices)

The 5-slice plan written earlier today (`/Users/bronty/.claude/plans/buzzing-sniffing-twilight.md`, summarized in the prior "deferred" entry below) shipped in full this session:

| Slice | Commit | LOC | What |
|---|---|---|---|
| 1 | `7141720` | ~150 | Today right-rail Weight sparkline (matches prototype) |
| 2 | `e28a0e0` | ~340 | Charts view kind in RecordsScreen — generic for any number+date type, used today by Weight |
| 3a | `a7641a6` | ~120 | AppSettings additions (goalWeightPounds / startingWeightPounds / heightInches / forecastDays) + Weight Settings tab |
| 3b | `df21b65` | ~770 | StatisticsService port (BMI / regression / forecast / etc.) + WeightStatisticsPanel + chart Trend/7d-avg/Goal overlays |
| 4 | (this commit) | ~340 | Smart Import wizard with regex-based free-form text parser |

WeightTracker can now be retired. PurpleLife covers everything daily-use: capture (menu-bar wand + ⌘N), the table/kanban/calendar/gallery/charts views, the "Latest weight" rail card with sparkline, BMI/Trend/Forecast statistics, Goal-line overlay, Smart Import for paste-from-anywhere ingestion, CSV / Markdown / HTML / PDF export, and CloudKit-synced multi-Mac storage with subscription-driven near-instant cross-device updates.

Skipped on purpose (with rationale already in HANDOFF):
- **Themes** — design language conflict; could revisit font-size accessibility separately.
- **XLSX / DOCX exports** — WeightTracker's hand-rolled OOXML is brittle; if needed, add natively to PurpleLife's existing ExportService.
- **Bar / Area / Scatter / MovingAverage as separate chart styles** — single LineChart with toggleable Trend / 7d / Goal overlays covers it.

Test count: 88/88 green at end of subsumption (was 59 at start of this session, +29 across the 5 slices and various supporting tests).

### 2026-05-10 — WeightTracker subsumption deferred (not blocking; revisit on retirement)

The scope decision earlier today says PurpleLife eventually carries 100% of WeightTracker's functionality. The execution of that — porting WeightTracker's charts (Line / Bar / Area / Scatter / MovingAvg), themes (6 named palettes), Smart Import (free-form text parser), Statistics (BMI / Trend / Forecast), and Reports (PDF / DOCX / XLSX export) — is a multi-week project, not a single commit.

Decision today: defer all of it. Reasoning:

- **WeightTracker still works** as a standalone app. Daily weight capture, charting, exports — all available in WeightTracker.app. PurpleLife handles capture-via-quick-capture and CSV-import-from-WeightTracker for cross-platform unity.
- **Not blocking anything in PurpleLife**. The Weight type in PurpleLife exists as a built-in seeded type; users can already create Weight records, sync them across Macs, export them via the per-type CSV exporter. The charts / themes / statistics work would be additive polish.
- **Themes specifically would muddy the design language**. PurpleLife has its own oklch palette (`Theme.swift`) drawn from the design handoff. Layering WeightTracker's six themes on top would dilute that. If theming lands later, it should be a coherent first-class system, not a port.

When this gets picked up, the natural first slice is the prototype's right-rail weight sparkline (big current number + 14-day spark + delta) plus a basic line-chart view for the Weight type in RecordsScreen. The CSV importer that already shipped covers the migration path.

### 2026-05-10 — Scope: PurpleLife will subsume WeightTracker; PurpleTracker stays separate

Closes the `PLAN.md` § Open question that was previously deferred ("Scope vs `WeightTracker` and `PurpleTracker`").

- **WeightTracker** — option (a). PurpleLife will eventually carry 100% of WeightTracker's functionality (charts, Smart Import, themes, etc.) under the Weight object type. The CSV importer already shipped (Phase 5 starter) is the bridge during the transition; it's not the end state.
- **PurpleTracker** — out of scope. Different use case (work-tracking lifecycle vs. life OS). OK to borrow design concepts and shared services, but PurpleLife will not subsume it.

**Effect on plan**:

- The `PLAN.md` open question is resolved; defer to this entry.
- New WeightTracker features should also be evaluated for the PurpleLife Weight type, with the long-term goal of feature parity. Concrete backlog items (charts panel for Weight in Today/Detail; theme picker; Smart Import) will be raised separately when prioritized.
- No backlog items added against PurpleTracker — it stays where it is.

### 2026-05-10 — Per-type export pipeline shipped; PDF via WKWebView matches Timeliner

The follow-up the prior snapshot queued as #2 ("export pipeline — copy Timeliner's `ExportService.swift`") is in. The literal "copy" wasn't appropriate — Timeliner's exporter is HTML/PDF for `Case`/`Event`/`Person`/`Tag`, very domain-specific. PurpleLife's data is generic typed objects, so the implementation is structurally similar (pure HTML formatter → WKWebView PDF) but the formatters are written from scratch around `ObjectType` + `FieldDef` + `[String: Any]` field values.

**Shape**:

- `Sources/PurpleLife/Services/ExportService.swift` — four `Format` cases (csv, markdown, html, pdf). The CSV / Markdown / HTML formatters are `nonisolated` pure functions taking resolver closures (`linkTitle`, `attachmentLabel`) — no `@MainActor`, no DB access, fully unit-testable. The PDF render is the single `@MainActor` operation: load HTML into an off-screen `WKWebView`, await the `didFinish` navigation, ask `webView.pdf(configuration:)` for the data. Same `LoadCoordinator` bridge pattern as `Timeliner.ExportService.exportCaseAsPDF`.
- `RecordsScreen` toolbar gained an Export `Menu` (next to "New X"). After a file save, `NSWorkspace.activateFileViewerSelecting([url])` opens Finder with the new file selected.
- New Settings → Export tab. Uses the existing `AppSettings.defaultExportDirectory` key (which had been declared since Phase 1 with no UI). Default resolves to `~/Downloads/PurpleLife/`.
- 10 new `ExportServiceTests` cover the deterministic surface. The PDF render isn't unit-tested — it needs WKWebView + a UI test host — but the HTML it consumes is fully covered, so the failure surface is reduced to "did WebKit accept this HTML?".

**Shape decisions worth knowing**:

- **Resolver closures, not direct service calls.** The formatter doesn't reach into `ObjectEngine.resolveLinkedTitle` or `AttachmentService` itself; the caller passes closures. This keeps the formatter `nonisolated` and trivially testable, and means a future per-record / batch / Today-panel exporter can plug in different lookup behavior without touching the formatter.
- **Multi-select join character is `|`.** Matches what most spreadsheet workflows expect; the WeightTracker CSV roundtrip never has multi-selects so there's no compatibility constraint.
- **Attachment cells use the resolver's filename or fall back to the sha256.** A re-importer can find the file at `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>` even when the resolver wasn't passed; resolver-with-filename is a UX nicety.
- **Per-type only for v1.** Per-record exports, Today-panel exports, and "everything across types" exports are obvious follow-ups — the formatter is reusable, the UI surface isn't built. Deferred to keep this commit focused.

**Effect on follow-up list**: item #2 ("export pipeline") is closed.

### 2026-05-10 — Phase 4 sync: subscriptions landed; poll demoted to recovery sweep

The follow-up the prior end-of-session snapshot queued as #1 ("real-time CloudKit subscriptions") is in. Mac→Mac sync now wakes on a silent push from APNS rather than waiting for a 30 s poll tick.

**Shape of the change**:

- A single `CKDatabaseSubscription` (id `PurpleLife.databaseSubscription`) is registered in `CloudKitSyncService.bootstrap()` after `ensureZone()`. Idempotent via a UserDefaults flag; `serverRejectedRequest` (already exists) is treated as success.
- A minimal `AppDelegate` (`Sources/PurpleLife/App/AppDelegate.swift`) is attached via `@NSApplicationDelegateAdaptor` in `PurpleLifeApp.swift`. It calls `NSApplication.shared.registerForRemoteNotifications()` on launch and forwards CK pushes through `NotificationCenter` (decoupled from `AppState` init ordering — the delegate is constructed by SwiftUI before `AppState` is).
- `CloudKitSyncService.handleSubscriptionNotification(userInfo:)` observes the NotificationCenter event, validates the push is ours (defensive guard against unrelated APNS noise lighting up the container), and triggers an immediate `pull()`.
- The 30 s poll became a 5 min recovery sweep — subscriptions are the primary trigger; the poll only catches up if a push is dropped (offline, sleep, APNS hiccup).

**Apple-side gotchas worth recording**:

- The Push Notifications capability has to be enabled on the App ID at developer.apple.com → Identifiers → `com.bronty13.PurpleLife` → Capabilities. Without it, the auto-provisioning step can't generate a profile carrying `aps-environment`, and `xcodebuild -allowProvisioningUpdates` reports a misleading "device isn't registered in your developer account" error rather than naming the missing capability.
- After enabling the capability, the existing dev profile may need to be regenerated. Easiest path: open `PurpleLife.xcodeproj` once in Xcode → Signing & Capabilities tab → Xcode silently re-fetches a fresh profile that includes Push Notifications. After that, `./build-app.sh` works again from CLI.
- macOS uses the **long form** entitlement key `com.apple.developer.aps-environment`. The iOS short form `aps-environment` is silently stripped by Xcode's `ProcessProductPackaging` step on macOS targets — the build succeeds, codesign runs, but the embedded entitlements in the `.app` won't include the push entitlement and silent pushes never arrive. Verify with `codesign -d --entitlements - ./PurpleLife.app | grep aps`.

**Effect on follow-up list**: item #1 ("real-time CloudKit subscriptions") is closed.

What's still open against Phase 4: the actual <5 s Mac→Mac timing claim. The infrastructure is in place; verification requires a second Mac on the same iCloud account, which hasn't been done in this session.

### 2026-05-10 — Test infrastructure regression: no longer reproduces

The "environmental hang" flagged in the end-of-session snapshot below has cleared. `./run-tests.sh` runs end-to-end in ~19 s for both projects on this Mac:

- **PurpleLife**: 34/34 tests pass (the count grew from the snapshot's 24 because of test additions in later phases that landed before the hang surfaced).
- **Timeliner**: 26/26 tests pass.

Reproduced with the existing scripts unchanged — no fix was applied; the host appears to have recovered on its own (most likely a reboot or Xcode/macOS update between sessions). The iCloud-entitlement-induces-test-hang workaround in `run-tests.sh` (`CODE_SIGN_ENTITLEMENTS=Sources/PurpleLife/App/PurpleLife-NoCloud.entitlements`) is still in place; whether it's still load-bearing on the current host wasn't tested — leaving it alone since it's free and the hang it guards against is a real Apple-bug class.

Effect on follow-up list: item #2 ("Test infrastructure regression") is closed. Tests are usable for the next round of changes.

### 2026-05-10 — End-of-session snapshot

Initial build session executed all five plan phases through a working state. Snapshot for whoever picks this up next:

- **Latest tagged build**: `v0.1.185` (commit `1f8bd0d`), Apple-Development-signed with the iCloud entitlement for container `iCloud.com.bronty13.PurpleLife`.
- **Acceptance gates fully met**: Phase 1, Phase 2, Phase 3. Phase 0 skipped by decision. CloudKit spike PASSed.
- **Acceptance gates with starters but unverified**:
  - **Phase 4** — push on mutation, 30 s poll, LWW conflict resolution are all wired. The "<5 s Mac→Mac" timing claim is unverified — needs a second Mac on the same iCloud account.
  - **Phase 5** — real attachments, gallery image loading, WeightTracker CSV import. The "≥2 weeks daily use without falling back" gate is real-world only.

**Known follow-up work** (rough priority order):

1. ~~**Real-time CloudKit subscriptions**~~ — resolved 2026-05-10; see "Phase 4 sync: subscriptions landed" entry above. CKDatabaseSubscription is registered in `bootstrap()`; AppDelegate forwards pushes via NotificationCenter; poll is a 5 min recovery sweep now. **Latency verified PASS** — see "Phase 4 acceptance gate verified PASS" entry above.
2. ~~**Test infrastructure regression**~~ — resolved 2026-05-10; see entry above. `./run-tests.sh` runs the full bundle (now 46 tests) green in ~17 s.
3. ~~**Export pipeline**~~ — resolved 2026-05-10; see "Per-type export pipeline shipped" entry above. Records → Export menu writes CSV / Markdown / HTML / PDF or copies CSV / Markdown to clipboard.
4. ~~**Schema versioning across synced peers**~~ — resolved 2026-05-10; see "Schema versioning: mirror schema through CloudKit + defensive merge" entry above. PurpleType records sync the schema; ObjectEngine.update preserves unknown JSON keys.
5. ~~**Polish toward the prototype**~~ — resolved 2026-05-10 across three commits (Today polish, Detail polish, Schema editor polish). All three sub-items shipped.
6. ~~**Daily-use ergonomics**~~ — partially resolved 2026-05-10 (menu-bar quick capture + ⌘N + ⌘1–⌘9 shortcuts); undo split out into its own follow-up item.
7. ~~**Undo across mutations**~~ — resolved 2026-05-10; see "Undo: NSUndoManager wired through ObjectEngine + SchemaRegistry" entry above. ⌘Z / ⇧⌘Z route through every mutation path; tests cover create/update/delete + schema operations.
8. **First-launch sync bootstrap UX** — new 2026-05-10. Mac B's first sign-in hung at "Setting up sync…" for ~5 minutes silently before resolving. Either the bootstrap steps need per-step timeout-and-retry with surfaced progress (e.g. "Initial pull: N records / M total"), or the status badge needs to break out the sub-states ("Checking iCloud…" / "Creating zone…" / "Pulling…") so a user knows whether to wait or kill it.

### 2026-05-10 — Phase 4 sync: poll on a 30s interval; subscriptions deferred

CloudKit subscriptions (`CKDatabaseSubscription` / `CKQuerySubscription`) get silent-push notifications when records change on another device. They're how you make Mac→Mac sync feel real-time (sub-second).

We're not doing them for the Phase 4 starter. The reason:

- They require `aps-environment` entitlement + an app delegate handling `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
- Apple's CKContainer routes the silent push through `userNotificationCenter:didReceive:` only when the app is in the foreground; otherwise it goes to the launch handler. SwiftUI's `App` lifecycle doesn't surface a clean hook for this — you end up bridging via `NSApplicationDelegateAdaptor`.
- For a personal multi-Mac app where both Macs are typically on simultaneously, a **30 s foreground poll** is acceptable: the worst case latency is 30 s of waiting after an edit, which beats the Phase 4 acceptance gate's <5 s target only on the optimistic side. We're choosing simplicity for the starter; subscriptions land as a follow-up improvement.

When the upgrade lands, the touchpoints are: `CloudKitSyncService.bootstrap` registers a `CKDatabaseSubscription`, an `NSApplicationDelegateAdaptor` forwards `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` into `CloudKitSyncService.handleSubscriptionNotification(_:)`, and the 30 s poll task in `startPolling` becomes a fallback for offline-recovery scenarios only.

### 2026-05-10 — Phase 4 conflict resolution: deterministic LWW by `updated_at`

Same-field offline edits on two Macs reconcile by comparing `updated_at`. Newer wins. Tied timestamps are unlikely (ISO-8601 to seconds) but treated as "remote keeps current" in `applyRemote` (`>=` rather than `>`).

We're not doing CRDT-style merges or three-way diffs. A Life OS edit is "the user typed in this field"; LWW is the right shape and matches CloudKit's `serverRecordChanged` retry pattern.

### 2026-05-10 — Phase 4 signing: switch from Developer ID to Apple Development

Pre-Phase-4 builds signed the `.app` with Developer ID Application after `ditto`. That's the right cert for outside-App-Store distribution but **doesn't carry CloudKit entitlements** — only Apple Development + a development provisioning profile does. The Phase 4 build script (`build-app.sh`) drops the post-`ditto` Developer ID re-sign and lets xcodebuild's Debug build provide the signature, which embeds the dev profile that includes `iCloud.com.bronty13.PurpleLife`.

Implication for users: the app is now signed for personal-team development use. Multi-Mac install on the same team's Macs is unchanged. Distributing the binary to a non-team Mac is no longer supported; if we ever need that, build with Developer ID separately and accept that CloudKit sync is off in those copies.

### 2026-05-10 — Attachments storage: content-addressed files in Application Support; CloudKit sync deferred to Phase 4

`PLAN.md` § Open questions calls for the attachments decision before Phase 2. Decided.

- **Phase 2** stores attachments as files at `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`. `fields_json` references them by sha256. Files travel inside backup zips automatically because they're under the Application Support tree the auto-backup already captures.
- **Phase 4** mirrors attachments to CloudKit as `CKAsset` (the only realistic shape for >50 KB binary data over CloudKit). `CKAsset`s are not E2E encrypted by `encryptedValues` — Apple has the keys for assets even though they don't for the JSON `fields` blob. That's a known and accepted trade-off: file content has lower confidentiality requirements than the structured fields, and the alternative (chunking + client-side encryption of media) costs weeks for a personal-scale app.
- **What's rejected**: BLOBs in SQLite (Timeliner's pattern) — fine for the small case-file attachments Timeliner deals with, but a Life OS will have photo libraries in the hundreds of MB and SQLite-as-a-blob-store stops being the right shape there. CKAsset-only with no local copy — defeats backups, breaks offline use.
- **Schema implication**: a single `attachments` table created in Phase 2 with `id`, `parent_object_id`, `sha256`, `filename`, `mime_type`, `size_bytes`, `created_at`. The on-disk file is the source of truth for content; the row is metadata only. Cascade deletes when the parent object is deleted.

### 2026-05-10 — CloudKit spike PASS; encryption decision locked

The spike `Spike/CloudKit/CloudKitSpike.app` ran successfully against the production Apple Developer setup:

- Container `iCloud.com.bronty13.PurpleLife` provisioned.
- App ID `com.bronty13.PurpleLife.CloudKitSpike` created with iCloud capability + container attached.
- Mac registered as a development device on team `SRKV8T38CD`.
- `build-spike.sh` updated with `-allowProvisioningUpdates` and `DEVELOPMENT_TEAM=SRKV8T38CD` baked into `Spike/CloudKit/project.yml` so future runs are turnkey.

**Result**: PASS — bytes-out matched bytes-in (sha256 `822b5b86…`), plaintext columns round-tripped, 4.2 s end-to-end on a brand-new container's first write. Full log + decision in `Spike/CloudKit/SPIKE.md` § Run log / Decision.

**Effect on plan**: the encryption row in `PLAN.md` § Locked decisions stands as written. `CKRecord.encryptedValues` is confirmed as the layer Phase 4 will mirror through. No follow-up spike needed before Phase 4 starts.

**Gotcha for future reference**: a fresh App ID's iCloud row on developer.apple.com requires a separate "Configure → check container → Save" step *after* registration to actually attach the container — the Capability Requests during initial registration only enable the capability, not the container assignment. Skip this and CloudKit returns `CKError.code = 5 (badContainer)` even though everything else looks correct.

### 2026-05-10 — Phase 0 (Tap Forms trial) skipped; decision: build

The plan reserves Phase 0 as a one-week Tap Forms trial against ≥3 real use cases, with a "build or stop" gate at the end. That gate is now closed without running the trial.

- **Decision**: build PurpleLife. Skip Phase 0.
- **Rationale**:
  - The user has already evaluated the off-the-shelf options surveyed in `PLAN-original.md` (Tap Forms, Ninox, Trilium, Anytype) and concluded the gap on the planner side and on configurable cross-type relations would not be closed by any of them.
  - The PhantomLives family (`Timeliner`, `PurpleTracker`, `WeightTracker`, `PurpleIRC`, `PurpleDedup`) provides nearly every system service PurpleLife needs as copy-then-adapt source material; the build cost is meaningfully lower than the plan's original estimate assumes.
  - End-to-end encryption with keys the user controls is a hard requirement that no off-the-shelf candidate satisfies in the way `CKRecord.encryptedValues` does. Even a successful Tap Forms trial would not have changed this.
- **Effect on plan**:
  - `PLAN.md` § Build phases shows P0 as skipped, dashed-line, with the rationale pointer to this file.
  - `PLAN.md` § Phase acceptance tests row for Phase 0 reads "Skipped" with the same pointer.
  - The CloudKit spike is moved ahead of Phase 1 (rather than running parallel with Phase 2 as the original plan suggested), to surface any `encryptedValues` blockers before the Foundation phase commits to the storage shape.

### 2026-05-10 — Project name locked: PurpleLife

The project is named **PurpleLife**, matching the directory and the Purple* family naming convention (PurpleIRC, PurpleDedup, PurpleTracker). Any references to the prior working title ("Personal ERP") are removed from active documentation. `PLAN-original.md` retains the prior name in its content as a historical record only and is annotated accordingly at the top of the file.

---

## Design deviations from `~/Downloads/PurpleLife-handoff.zip`

_None yet._ Phase 2 has not begun. Add entries here as `### YYYY-MM-DD — <Screen> — <one-line reason>` as deviations are made.
