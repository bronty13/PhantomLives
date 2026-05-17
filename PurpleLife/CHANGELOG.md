# PurpleLife Changelog

Newest at the top. Follows the PhantomLives convention: every behavior-changing commit lands an entry here, USER_MANUAL.md updates if user-visible, and the version bumps automatically via `build-app.sh` + git commit count.

## Unreleased — Phase 5 starter (0.1.x)

### 2026-05-16 — Resilience Tier 5: plaintext snapshot export

The "I want to be able to read this in 30 years on hardware Apple doesn't sell yet" escape hatch from the 2026-05-15 resilience design. Settings → Backup gains an **Export plaintext snapshot…** button that walks every record + attachment, decrypts everything, and writes a self-describing file the user can stash anywhere — encrypted thumb drive, 1Password attachment, paper printout. The schema travels in the same file so every field meaning is interpretable without the running app.

**Two output formats, user picks per-export.** Both produce a self-describing `purplelife.snapshot.v1` envelope.

- **ZIP with sidecars** — `snapshot.json` + `attachments/<sha256>.<ext>` + a human-readable `README.txt`, bundled in a ZIP. Attachments stay binary-clean and open per-file after unzip; better for "I want to grep this with normal tools" use.
- **Single JSON (base64 attachments)** — one file with attachment bytes inlined as base64 under each metadata entry. Round-trip-verifiable (sha256 over the base64-decoded bytes matches the metadata sha256). Better for "drop into 1Password as a single attachment" use.

**Vault — require unlock first.** If the Vault is locked when the user opens the export sheet, Vault types are excluded by force (sheet says: cancel, unlock via ⇧⌘V, retry). If the Vault is unlocked, a checkbox controls inclusion and defaults to *off* — the user has to opt in to plaintext Vault data leaving the app. Matches the 2026-05-14 Vault contract: private data never leaves the app implicitly.

- **`Services/PlaintextSnapshotService.swift`** (new) — pure assembly + writers. `buildEnvelope(schema:settings:excludingTypeIds:inlineAttachmentBytes:)` is the unit-testable seam; `export(to:format:schema:settings:excludingTypeIds:)` is the entry point the UI calls. Envelope shape: `format`, `formatDescription`, `exportedAt`, `appVersion`, `appBuildNumber`, `counts`, `notes`, `schema {types, tags}`, `records[]` (each with decoded `fields` dictionary + per-attachment metadata). Attachments in single-JSON mode carry `bytesBase64` + an optional `readError` so a decryption failure produces preserved metadata with a typed explanation rather than fake bytes.
- **`AnyCodable`** — local helper at the bottom of the same file that round-trips the heterogeneous `fields_json` dictionary through `JSONEncoder` without per-key type-erasure. Detects `Bool`-wrapped-as-`NSNumber` via `CFBooleanGetTypeID` (the trap `JSONSerialization` would otherwise lay) and writes whole-number doubles as `Int64` so a `rating: 4` doesn't become `4.0` on disk.
- **`Views/Settings/BackupSettingsTab.swift`** — new "Plaintext snapshot" section above "Recent backups" with the button, a description, and async status messaging. A modal sheet collects format + Vault decision (with state-aware text for locked/unlocked Vault) then routes through `NSSavePanel`. Default filename `PurpleLife-plaintext-snapshot-<stamp>.<ext>` and default directory is `~/Downloads/PurpleLife/`.
- **`Tests/.../PlaintextSnapshotTests.swift`** (new) — 6 tests covering: envelope format tag + counts + schema embedding; record `fields` round-trip as a JSON object (not stringified); Vault exclusion drops both records and type definitions; ZIP shape (snapshot.json + attachments/ + README.txt, no bytes in manifest); single-JSON mode inlines bytes whose sha256 matches the metadata; filename convention.

**Defers (per HANDOFF 2026-05-15).** Tier 3 (iCloud Keychain mirror) and Tier 4 (CloudKit private-zone wrapped DEK) remain on the deferred list — Tier 2's recovery key already covers correctness; 3 and 4 are convenience layers. With Tier 5 shipped, the resilience plan now stands at: Tier 0 (trap-prevention guards) + Tier 1 (Keychain fast-path) + Tier 2 (24-word recovery key) + Tier 5 (plaintext escape hatch), all in production.

293/293 tests green (+6 PlaintextSnapshotTests).

### 2026-05-16 — Sidebar action buttons, Vault auto-lock, Lock Application

User asked for four things in one round:

1. **Sidebar action buttons (Views/Sidebar.swift).** A horizontal row of icon buttons lives above the sync footer:
   - Schema editor (opens the `schema-editor` window — same as ⇧⌘S)
   - Find (opens the `search` window — same as ⌘⇧F)
   - Quick switcher (opens the `quick-switcher` window — same as ⌘K)
   - Lock (visible only when the Vault is revealed; instantly calls `lockVault()`)

   Keyboard shortcuts are unchanged — these are purely a discoverability + ergonomics layer.

2. **Vault auto-lock by inactivity.**
   - **`Models/AppSettings.swift`** — new `vaultAutoLockAfterSeconds: Int = 120` (0 disables). Lenient decode so legacy settings.json files still load.
   - **`App/AppState.swift`** — `lastActivityAt: Date` stamped on every NSEvent monitored via a local `addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel])`. The existing 4 Hz vault-menu Timer now also checks whether (now - lastActivityAt) ≥ threshold while the vault is open, and calls `lockVault()` when it crosses. `revealVault()` resets `lastActivityAt` on success so a stale stamp can't snap the vault closed on the next tick.
   - **`Views/Settings/SecuritySettingsTab.swift`** — new Stepper in the Session section (step 15s, range 0–3600). Reads "Auto-lock Vault after 2 minutes" / "Auto-lock Vault: never" with a friendly time formatter.

3. **Lock Application — screen lock + crypto lock.** User picked "both" semantics.
   - **`App/AppState.swift`** — new `@Published var appLocked: Bool`. `lockApp()` flips it, locks the Vault for hygiene, and (when a passphrase is set) ALSO calls `keyStore.lock()` to wipe the in-memory DEK so a memory snapshot can't reveal it. `unlockApp()` clears the flag and resets `lastActivityAt`.
   - **`Views/AppLockScreen.swift`** (new) — full-window lock screen. Auto-invokes `VaultAuthService.authenticate` on appear; offers a manual retry button on cancel/failure; surfaces a footnote when a passphrase is set telling the user to enter it via Settings → Security after the screen dismisses.
   - **`Views/ContentView.swift`** — new gating branch: when `appLocked` is true, replace the entire content with `AppLockScreen`. Sits below the recovery / pending-key takeovers so an unrecoverable DB or first-launch key save still win.
   - **`App/PurpleLifeApp.swift`** — new `LockAppMenuItem` ("Lock PurpleLife", ⌃⌘L) sits in the View commands after the Vault menu item. Disabled while already locked. Users can rebind via System Settings → Keyboard → App Shortcuts.

USER_MANUAL gains "Vault auto-lock" + "Lock PurpleLife" sections; the Vault description picks up a sentence on the auto-lock setting.

### 2026-05-16 — Schema editor: vault toggle, type-scope tags, select-option editor, palette wrap, table-layout fix, detail spacing

Multi-part schema-editor pass triggered by reports against the Fantasy journal vault type:

1. **Vault toggle on every type.** `ObjectType.isVault` has existed since the Vault landed, but no UI ever exposed it — the documented "user can also flip it on any type via the schema editor" was aspirational. Fixed.
   - **`Services/SchemaRegistry.swift`** — new `setVault(_:isVault:)` mutator. Idempotent when the flag is already at the requested value, stamps `updatedAt`, persists, fans to CloudKit, and registers an undo action ("Move to Vault" / "Move out of Vault"). Same envelope as `upsertType`.
   - **`Views/SchemaEditor.swift`** — added a "Move to Vault" / "Move out of Vault" entry to the type rail context menu (covers built-ins and custom types alike). A small muted `lock.fill` badge now sits next to the field count for any type with `isVault = true`, so the user can see at a glance which types live behind the lock.
   - Comment in `Models/ObjectType.swift` updated to match reality — points at the new `setVault` mutator instead of the old aspirational claim.

2. **Type-scope tags.** Tags previously could only attach to records. The new contract: tags can scope to either an `ObjectType` (every record of that type inherits) or an individual record. The schema editor exposes type tags; Detail's `TagPillRow` continues to handle per-record tags.
   - **`Models/ObjectType.swift`** — new `tags: [String]` stored property, default `[]`. Lenient `decodeIfPresent` so legacy `schema.json` files without the key decode cleanly (same pattern as `isVault`).
   - **`Services/SchemaRegistry.swift`** — new `setTypeTags(_:onTypeId:)` mutator, dedupes input while preserving order. Routes through `upsertType` so undo + CloudKit sync stay coherent.
   - **`Services/TagService.swift`** — new `effectiveTagIds(for:in:)` and `effectiveTags(for:in:)` helpers. Return the union of `type.tags` (first) and `_tags` (second), dedupe with first-occurrence-wins, preserve declared order. Renderers can split on `Set(type.tags).contains` to distinguish inherited from per-record tags.
   - **`Views/SchemaEditor.swift`** — type-tags row sits between the type header and the field list. Tag chips render with the assigned `colorHex` and a remove `xmark.circle.fill`; an `Add tag` button opens the existing `TagChipPicker`.

3. **Record renderers — prominent tag colors + the vault marker.** Tags are no longer invisible until you open Detail.
   - **`Views/RecordTagStrip.swift`** (new) — read-only horizontal tag chip strip. Two styles: `.compact` (single line, "+N" overflow indicator) for narrow contexts, `.wrap` (FlowLayout) for the Detail hero. Type-scope chips get a slightly lighter fill and a dashed outline so the user can tell at a glance which tags are inherited vs per-record.
   - Wired into `RecordsTableBody.dataRow` (table), `RecordsKanbanBody.kanbanCard`, `RecordsGalleryBody.galleryCard`, `Today.TimelineRowView`, `Today.RailCard`, `QuickSwitcher.resultRow`, and `Detail.hero`.
   - Each of the same renderers picked up a small muted `lock.fill` glyph when `type.isVault` is true. Subtle but visible — `.foregroundStyle(.tertiary)` + `imageScale(.small)`. (User-assignable tag colors via `ColorPicker` already shipped in `TagManagementSheet` — this work makes those colors visible at every place a record surfaces, not just inside the Detail tag pills.)

4. **Field palette no longer cut off.** The `ADD A FIELD` row was a horizontal `ScrollView` with `showsIndicators: false`. Tiles past the visible edge were silently inaccessible — users had no scroll affordance to discover them.
   - **`Views/SchemaEditor.swift`** — replaced with a `LazyVGrid(.adaptive(minimum: 92, maximum: 110))` so tiles wrap onto a second row as needed. Every `FieldKind` is reachable at any window width.

5. **Select / multi-select option editor.** Field rows for `.select` and `.multiSelect` had no way to add / rename / recolor / reorder / delete option values. Option editing required hand-editing `schema.json`. Fixed.
   - **`Views/SelectOptionsEditor.swift`** (new) — modal editor with rows for each option: color picker, name field, up / down reorder buttons, delete. Footer adds new options. Caption flags the deliberate limitation that renaming an option doesn't rewrite already-tagged records (option storage on a record is the option *name*, not its id).
   - **`Views/SchemaEditor.swift`** — field row picks up an inline `N options · Edit` button beside the "required" / "primary" badges when the field is a select/multi-select kind, plus an "Edit options…" entry in the field row context menu. Both open the sheet, which commits via `SchemaRegistry.updateField` so undo + CloudKit-sync stay coherent.

6. **Detail view: chip / note-log overlap fixed.** A multi-select chip cluster followed by a noteLog field rendered with no visible separation — reported as "themes squished" + "can't get at notes."
   - **`Views/Detail.swift`** — per-field spacing in `mainPane` bumped from 14 → 22; each field block gets a hairline divider (40% opacity) so consecutive editors don't visually merge. Per-field label-to-editor spacing bumped from 4 → 8. `multiSelectEditor` chips redrawn with sharper contrast (off-state foreground = `.primary` instead of `.secondary`), thicker default opacity, and a thin outline; FlowLayout pinned to `maxWidth: .infinity` so wrap behavior is deterministic regardless of parent proposal.

7. **Records table no longer pushed to the bottom.** For short tables, the column header + rows rendered near the bottom of the visible area with a huge empty gap above them.
   - **`Views/RecordsScreen.swift`** — `RecordsTableBody` was using `ScrollView([.horizontal, .vertical])`, which on macOS 14/15 gave short tables a bottom-anchored layout no matter what `.frame(alignment: .topLeading)` the inner content asked for. Replaced with the nested-ScrollView pattern: outer `.vertical` ScrollView wrapping an inner `.horizontal` ScrollView wrapping the rows VStack. The inner ScrollView sizes to natural row height; the outer vertical ScrollView then top-aligns it the way every other scroll view in the app does. Both axes still scroll when content exceeds the viewport.

8. **View → Show Vault is now hidden until Shift+Option is held.** Discoverability dampener: someone glancing at a shared Mac's menu bar shouldn't learn that PurpleLife has a vault feature at all. The keyboard shortcut (⇧⌘V) still works without the modifier so a returning user doesn't have to fish for it; only the visible menu item is gated.
   - **`App/AppState.swift`** — new `@Published var vaultMenuVisible` driven by a 4 Hz Timer that polls `NSEvent.modifierFlags` (skipped under XCTest). ~250 ms latency between modifier hold and menu item appearance — well within the "hold this then click" tolerance.
   - **`App/PurpleLifeApp.swift`** — `VaultMenuItem` renders the "Show Vault…" button only when `vaultMenuVisible == true`; when not held, a zero-size hidden Button keeps the ⇧⌘V keyboard shortcut alive at the responder level. "Lock Vault" stays visible whenever the vault is already revealed — re-locking is the obvious counter-move and shouldn't be hidden.

**Tests.** `Tests/.../VaultToggleAndTypeTagsTests.swift` (new) — 8 tests covering `setVault` flag flip + visibility moves, `setVault` no-op-on-missing-id, `setVault` no-stamp-when-idempotent, `setTypeTags` replace + dedupe + clear, `setTypeTags` no-op-on-missing, `ObjectType.tags` legacy-JSON decode (without the key) and round-trip, and `effectiveTagIds` merge / dedupe / ordering invariants.

### 2026-05-16 — Fix: Notes workspace layout — replace inner HSplitView with HStack

The Notes workspace's inner `HSplitView` was causing the outer NavigationSplitView's sidebar to clip its row labels (`Planner` → `lanner`, `Notes` → `lotes`, etc.) — reported as backlog #15 (2026-05-15). Confirmed root cause: SwiftUI's `HSplitView` wraps `NSSplitView`, which keeps its own copy of subview frames in UserDefaults under a synthesized `"NSSplitView Subview Frames …, SidebarNavigationSplitView"` key. The autosaved frames (248 + 1097 = 1345pt total) outsized the current window (976pt); AppKit fell back to laying the panes out at the saved widths, which squeezed the outer Sidebar below its declared `navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)` minimum and clipped the leading character of every row label.

`AppDelegate.applicationWillFinishLaunching` already wipes the autosaved frames on every launch (added in commit `0654b0a`), but AppKit re-writes them at app quit using its in-memory copy of the broken layout — so the wipe doesn't actually break the cycle.

- **`Views/Notes/NotesWorkspaceView.swift`** — replaced the inner `HSplitView` with a plain `HStack(spacing: 0)`. The Notes list pane is now a fixed `width: 300`; the editor pane takes the rest. With no `NSSplitView` in the tree, the broken autosave path is impossible. Trade-off: the inner splitter is no longer user-draggable; the previous one was broken anyway. The outer NavigationSplitView splitter (for the app's main sidebar) still works.

### 2026-05-16 — Tags Increment 3: advanced Search window with tag / date / Vault filters

Resumed from the pre-resilience pause. The Quick Switcher (⌘K) stays its current minimal self; the new advanced Search window (⌘⇧F) carries the structured filters that wouldn't fit in a single-input UI.

- **`Services/SearchService.swift`** — new `Filter` value type wrapping query / typeIds / excludingTypeIds / requiredTagIds / tagMatchMode (.any/.all) / untaggedOnly / dateRange / limit. New `search(_ filter:)` overload compiles a single SQL query: FTS5 MATCH when the query is non-empty (ranked), plain SELECT ordered by `updated_at` DESC when it's empty; type IN/NOT-IN clauses; `record_tags` subquery for `.any` (IN) or `.all` (GROUP BY HAVING COUNT(DISTINCT)); `objects.updated_at` subquery for the date range. The existing `search(_, limit:, excludingTypeIds:)` overload stays untouched so QuickSwitcher's tight call path is unchanged.
- **`Views/SearchScreen.swift`** (new) — dedicated window with a query header, collapsing filter bar (Types / Tags / Updated / Vault), and a results list. Filter changes collapse to a single `filterSignature` string so SwiftUI's `.onChange` chain doesn't blow the type checker on the nine inputs the search reacts to. Auto-runs the search on any change.
- **`Views/Sidebar.swift`** — new "Search" entry above Today (button, not a selection target — opens the search window in its own scene).
- **`App/PurpleLifeApp.swift`** — new `Window(id: "search")` scene; new `SearchMenuItem` (⌘⇧F).
- **`Views/QuickSwitcher.swift`** — footer "Open in Search…" appears whenever the user has typed a query. Stashes the query in `AppState.searchHandoffQuery`, opens the Search window, dismisses Quick Switcher. SearchScreen picks up the handoff once on appear and clears it.
- **`App/AppState.swift`** — new `searchHandoffQuery` for the Quick Switcher → Search hand-off.
- **`Tests/.../SearchFilterTests.swift`** (new) — 11 tests covering each filter dimension in isolation plus composition: empty filter returns everything newest-first, free-text path matches the existing overload, type-scope restriction, `excludingTypeIds` wins over `typeIds` (the load-bearing Vault contract), tag `.any` / `.all` / untagged, `requiredTagIds` takes precedence when `untaggedOnly` is also set, date-range bounds, and the multi-filter compose case.

**Vault gating (Phase 3c, built into SearchScreen).** Matches the 2026-05-14 design point-for-point: when the Vault is locked the "Include Vault" checkbox is hidden entirely, Vault types are absent from the type chip picker, and the SQL exclusion (`excludingTypeIds = schema.vaultTypeIds`) is passed unconditionally. When the Vault is unlocked the checkbox appears unchecked; ticking it clears the exclusion and reveals Vault chips. Re-locking the Vault while the search window is open auto-clears the user's "Include Vault" choice and any Vault-type chip selections — the SQL exclusion takes effect immediately.

277/277 tests green (was 266 before).

### 2026-05-15 — Resilience Phase A + B: 24-word recovery key + the trap-prevention guards

Multi-tier data-loss prevention, landed together as Phase A (stop creating new losses) and Phase B (give the user a path back when something else goes wrong). Triggered by data-loss incident #4 — the test suite wiping the user's production DEK via a shared `KeychainStore` service name. Full design rationale lives in HANDOFF.md (2026-05-15).

**Phase A — stop creating new losses.**

- **`Services/KeychainStore.swift`** — `service` is now `"com.purplelife.tests-<pid>"` under XCTest, stable `"com.purplelife"` in production. The 2026-05-14 fix to `deleteAll()` correctly deletes every entry under the service; without this split, every test run nuked the user's real DEK. New `KeyStoreTests.test_keychainServiceIsTestIsolatedUnderXCTest` locks the contract.
- **`Services/BootState.swift`** (new) — per-install `boot_state.json` marker, written on every successful unlock. Records first-launch and last-launch ISO timestamps. Forms the basis of the bootstrap-refusal guard below.
- **`Services/KeyStore.swift`** — `setupKeychainManaged()` now consults `BootState.everBooted(...)` before generating a fresh DEK. When the marker exists AND the Keychain slot is genuinely absent — the data-loss-trap shape — it throws the new `KeyStoreError.everBootedButKeychainGone` instead of silently minting a fresh DEK that would foreclose every remaining recovery path. `resetAndWipe()` also clears the marker so deliberate resets aren't bounced back into recovery.
- **`App/AppState.swift`** — catches `everBootedButKeychainGone` and routes to the recovery screen with a Time-Machine-specific message. Marks `BootState` on every successful unlock so future Keychain losses on this install get the protection automatically.
- **`Services/DatabaseService.swift`** — the Reset quarantine sweep moves `boot_state.json` and (Phase B) `recovery_envelope.json` alongside the DB / settings / attachments. Reset keeps clean fresh-install semantics.
- **`Tests/.../BootStateTests.swift`** (new) — 11 tests, including the **`test_RELEASE_BLOCKER_dataLossTrapScenarioDoesNotCreateFreshDEK`** invariant: simulates incident #4's conditions and asserts the bootstrap refuses to create a fresh DEK. If this test ever fails, the change being shipped has reintroduced the trap — do not merge.

**Phase B — user-held recovery key (BIP39 24-word).**

Picked over short hex / free-form passphrases because BIP39 has the best handwriting / dictation / mental-model story (every crypto wallet and Apple's iCloud Recovery Key already use this shape), and the checksum word gives free single-typo detection.

- **`Services/BIP39Wordlist.swift`** (new) — vendored 2048-word canonical BIP39 English wordlist (public domain, sourced from `github.com/bitcoin/bips/blob/master/bip-0039/english.txt`). Embedded as a Swift `[String]` literal so the project ships without resource-loading code.
- **`Services/RecoveryKey.swift`** (new) — generate / encode / decode / validate. `generate()` produces 256 bits of entropy + an 8-bit checksum = 24 words. `entropy(from:)` decodes back and verifies the checksum; single-word typos throw `.checksumMismatch`. Lowercase + whitespace tolerant for paste-from-anywhere unlock. `deriveKEK(phrase:salt:iterations:)` runs PBKDF2-SHA256 with the same 300k iterations `KeyStore` uses for passphrase mode.
- **`Services/KeyStore.swift`** — new `RecoveryEnvelope` struct + `recovery_envelope.json` written alongside `keystore.json`. `setupKeychainManaged()` and `setupWithPassphrase(_:)` now both return the generated 24-word phrase (`@discardableResult` keeps the existing call sites compiling). `ensureRecoveryEnvelope()` is the migration path for installs that pre-date this work — runs on every launch, no-op when the envelope already exists, mints one using the live DEK when it doesn't. `unlockWithRecoveryKey(phrase:)` derives the KEK and unwraps the DEK, then caches it back in Keychain so subsequent launches are silent again.
- **`App/AppState.swift`** — new `@Published pendingRecoveryKey: [String]?` non-nil whenever a phrase has been generated and the user hasn't yet confirmed they've saved it. `tryRecoveryKeyUnlock(phrase:)` is the recovery-screen entry point: validates the phrase, unlocks the keystore, reopens the SQLCipher pool, flips `dbHealth` back to `.ok` on success.
- **`Views/RecoveryKeySaveSheet.swift`** (new) — full-window mandatory save-recovery-key UX. Displays the 24 words in a numbered monospaced grid, offers copy-to-clipboard / save-to-file. Requires the user to retype three randomly-picked words before the "I've saved my recovery key" button enables. Non-dismissable by any other path — gates the entire app behind the save flow.
- **`Views/RecoveryScreen.swift`** — when a recovery envelope exists on disk, the recovery screen surfaces a third primary button "Enter recovery key…". Opens a sheet for the user to paste their 24 words; specific per-error-case messages (wrong word count, unknown word, checksum mismatch, wrong key entirely) instead of a generic failure.
- **`Views/ContentView.swift`** — gates the main split view on both `dbHealth` (existing) and `pendingRecoveryKey` (new). Hands the keystore's `hasRecoveryEnvelope` + the `tryRecoveryKeyUnlock` closure into `RecoveryScreen`.
- **`Tests/.../RecoveryKeyTests.swift`** (new) — 16 tests covering: BIP39 encode/decode round-trip including the canonical all-`0xFF` reference vector, checksum rejection on single-word edits, whitespace + case tolerance on decode, keystore round-trip via the recovery key, wrong-key rejection, `ensureRecoveryEnvelope` no-op + migration paths, and the **end-to-end Mac-A-backup → Mac-B-recovery release-blocker** test that takes a backup ZIP on one keystore and confirms the recovery key unlocks it on a completely separate keystore.

**Docs.** USER_MANUAL.md gains a "Your 24-word recovery key" section explaining what the key is, how to save it, how to use it, and what it doesn't protect against. INSTALL.md flags the first-launch save-flow so new users know to expect it. HANDOFF.md (2026-05-15) carries the full architectural rationale, the data-loss-incident log, and the deferred Tier 3-5 follow-ups (iCloud Keychain mirror, CloudKit wrapped DEK, plaintext JSON export).

**Pause status.** Tags Increments 1 + 2 (cross-cutting `_tags` field, `TagDef` vocabulary, `record_tags` index, `TagPillRow`, `TagManagementSheet`) shipped before this work and remain green. Tags Increment 3 (advanced Search window with Vault gating) was paused for resilience and is the next feature to resume.

**Tests.** 218 → 266 (+48). All green.

### 2026-05-14 — Fix: `KeychainStore.deleteAll()` silently no-oping on macOS 15

`SecItemDelete` with a query that omits `kSecAttrAccount` is unreliable across macOS versions — historically it deleted every match, but on macOS 15 it returns `errSecSuccess` while leaving the items in place. `KeyStore.resetAndWipe()` calls `deleteAll()` to wipe the DEK cache; the silent no-op meant a freshly-constructed `KeyStore` against the same support directory would discover the cached DEK and report `.unlocked` instead of `.notSetup`. Symptom in the test suite: `KeyStoreTests.test_resetAndWipeClearsEverything` failed deterministically even in isolation.

- **`Services/KeychainStore.swift`** — rewrote `deleteAll()` to enumerate matching items via `SecItemCopyMatching` (with `kSecMatchLimitAll` + `kSecReturnAttributes: true`) and then delete each one by its specific account using the account-scoped `delete(account:)` form. Account-scoped `SecItemDelete` IS reliable; the multi-match shape is the one that broke.
- **`Tests/.../KeyStoreTests.swift`** — new `test_keychainDeleteAllRemovesEveryEntryUnderService` regression: seeds two entries under the service, calls `deleteAll`, asserts both are gone via `entryStatus`. Locks the contract at the layer where the bug actually lived (rather than only at the `KeyStore` layer, where `test_resetAndWipeClearsEverything` already covers it).

218/218 tests green (was 217/217 with 1 pre-existing failure).

### 2026-05-14 — Vault: gated section for private types + 20 new library entries

A new sidebar section called **Vault** that's hidden on every launch and unlocks via **View → Show Vault…** (⇧⌘V). The reveal goes through `LAContext.deviceOwnerAuthentication` — Touch ID where available, falling back automatically to the Mac login password — and stays open until the user picks **Lock Vault** or quits. The flag is deliberately *not* persisted, so a forgotten unlock can't outlive the session.

When the Vault is locked, Vault types disappear from the sidebar list, from `SearchService` results, from the ⌘K Quick Switcher, from the Today timeline + saved-query panels + right-rail saved-query lookups, and from the Schema Library gallery's category sidebar / counts / result list. Schema Editor still shows Vault types so the user can manage them without first unlocking — this is the one place the privacy-everywhere story has an explicit exception, and it's documented at the call site. The library gallery also hides the **Vault** category itself when locked, so the existence of intimate templates isn't telegraphed to a casual browser.

- **`Models/ObjectType.swift`** — new `isVault: Bool = false` property with a custom `init(from:)` that uses `decodeIfPresent` for backward compat (Swift's synthesized decoder doesn't honor property defaults — every existing on-disk `schema.json` would otherwise fail to load). The explicit memberwise init is restored so existing call sites (tests, the `builtIn(...)` factory, `makeType`) still type-check unchanged.
- **`Models/SchemaLibrary.swift`** — new `Category.vault = "Vault"` case with `lock.fill` systemImage. `Entry.materialize()` now stamps `isVault = (category == .vault)` on the resulting `ObjectType` so importing a Vault library entry routes it to the Vault sidebar section automatically.
- **`Models/SchemaLibrary+Vault.swift`** (new) — 20 curated entries split across four buckets:
  - **Sexual health (6)**: Cycle entry · Intimate health visit · STI test · Contraception entry · Libido entry · Intimate symptom
  - **Encounter / relational (4)**: Encounter · Partner profile · Date night · Aftercare note
  - **Kink (6)**: Kink · Scene · Toy / gear · Hard limit · Safeword · Scene plan
  - **Body & intimate (4)**: Body entry · Fantasy · Intimacy goal · Negotiation
  Each entry uses the same field-kind discipline as the rest of the library (`.text`, `.date`, `.dateTime`, `.select`, `.multiSelect`, `.boolean`, `.rating`, `.longText`, `.richText`, `.noteLog`, `.link`, `.attachment`); the invariant tests (kanban → select, calendar → date, gallery → attachment, every entry has a primary + at least one required field) cover the new entries the same way they cover the 575 existing ones.
- **`Services/VaultAuthService.swift`** (new) — `LocalAuthentication` wrapper around `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`. `.deviceOwnerAuthentication` (not `.deviceOwnerAuthenticationWithBiometrics`) is the right policy here: it falls back to the Mac login password when biometrics fail / aren't enrolled, so users on a Touch ID-less Mac aren't locked out. Returns a typed `AuthResult` so AppState can distinguish user-cancel from auth-failed from unavailable-on-this-Mac (the last case logs but doesn't surface UI; the menu is the user's retry affordance).
- **`Services/SchemaRegistry.swift`** — `visibleTypes` now excludes `isVault` types (in addition to the existing `hiddenBuiltInIds` filter). Two new properties: `visibleVaultTypes` (the inverse, for the Vault sidebar section) and `vaultTypeIds` (for `SearchService.search`'s `excludingTypeIds` parameter). Callers that previously walked `visibleTypes` to render the sidebar / power ⌘1-9 / count the Today header automatically get the right behavior with no other changes.
- **`App/AppState.swift`** — runtime-only `vaultRevealed: Bool` (`@Published`, default `false`). `revealVault()` calls `VaultAuthService.authenticate(reason:)` and flips the flag on success. `lockVault()` flips it off and, if the user is currently looking at a Vault type's records, snaps the sidebar selection back to Today so they don't stare at a now-invisible type's header.
- **`Services/SearchService.swift`** — `search(_:, limit:, excludingTypeIds:)` adds the optional exclusion parameter. SQL builds `AND type_id NOT IN (?, ?, …)` only when the set is non-empty, so the unmodified call shape stays cheap. Done at the SQL layer (not post-fetch) so `limit` is honored against the visible set.
- **`Views/QuickSwitcher.swift`** — passes `appState.schema.vaultTypeIds` to `SearchService.search` when `!appState.vaultRevealed`. A Vault record's title never appears in Quick Switcher results when the Vault is locked.
- **`Views/Today.swift`** — `todayTimelineRows()` skips records whose `type.isVault` is `true` (when locked). `QueryPanel` filters Vault results out of saved-query result sets. `railCard(forSavedQueryNamed:)` skips Vault rows when picking its first-result-to-show. A user's "Currently reading" rail won't surface a Vault Fantasy entry by accident.
- **`Views/SchemaLibrarySheet.swift`** — `visibleCategories` and `browsableEntries` filter `.vault` out of the gallery's category sidebar and search results when locked. The "All" counter shows the locked-state total. Schema editor's `Browse library` button works as before; users unlock the Vault, reopen the gallery, and the new category appears.
- **`Views/Sidebar.swift`** — conditional `Section { … } header: { Vault + lock-icon button }` renders only when `appState.vaultRevealed`. Falls back to a soft "Open the schema library to import Vault types" hint when the section is empty. `reloadCounts()` includes Vault types so their row counters appear.
- **`App/PurpleLifeApp.swift`** — new `VaultMenuItem` inserted after the View → Sidebar group. Single command that switches its label and action based on `vaultRevealed`: **Show Vault…** triggers the async auth flow; **Lock Vault** flips the flag instantly. Both bind `⇧⌘V`.

### 2026-05-12 — Schema library expansion: 11 full categories from the proposals doc → 575 templates

Third round of catalog growth. Implemented the entire Productivity, Home & Life Admin, Money & Finance, Food & Drink, Travel & Places (with a special 50-state License Plate Sighting tracker), Creative Work, Relationships, Pets & Animals, Nature Observation, Unusual & Truly Weird, and Long-tail Personal Reference sections from the community proposals doc. Long-tail items distribute to their natural categories (Food, Relationships, Unusual).

- **`Models/SchemaLibrary+ExtendedCatalog2.swift`** — 324 new entries in a third extension file. `SchemaLibrary.entries` now computes `coreEntries + extendedEntries + extendedEntries2`, so all three files contribute to a single flat catalog the gallery shows.

- **License Plate Sighting** — special schema with all 50 US states + DC as select-field options, suitable for kanban grouping (one column per state, perfect for road-trip "have we found them all?" play). Constructed inline with the full `ObjectType` initializer (rather than `makeType`) because the state list is too long for the helper's tuple shorthand. The new entry exemplifies how a deliberately complex single-purpose schema is no different to the gallery / IO than any other.

- **Pets & Animals** — Pet weight log, medication, grooming, training sessions, behavior issues, food, toys, dog walks, boarding, adoption applications, fosters, microchips, allergies, and pet death. Treated as a Home category subset (`.home`) since pets are a household concern; the gallery search makes them easy to find under both "pet" and "home admin" keywords.

- **Nature Observation** — Animal tracks, scat (yes, scat), skulls, antler sheds, feathers, pressed plants, preserved leaves, saved seeds, beach combing, sea glass, driftwood, shells, sand samples, crystals grown, lichen, moss. All filed under `.unusual` since they're naturalist hobbies rather than household tasks.

- **Unusual / Truly Weird** — Sleep talking, sleepwalking, OBE, NDE, doppelgänger sightings, mistaken identity, wedding crashed, hitchhikers picked up, stranger conversations, wrong-number calls, mystery packages, letters to/from future and past selves, time capsules, pocket treasures, Mandela effects, misheard lyrics, spoonerisms, embarrassing memories, cringe messages, saved voicemails, rediscovered photos, unsent emails, unmailed letters, confessions, regrets, compliments given, apologies made, stranger kindness received, stranger quotes that stuck, pennies found, bumper stickers, strange signs, found typos, funny error messages, imaginary friends, stuffed animals, childhood obsessions, recurring dream themes, phobias, quirks, verbal tics, pet peeves, comfort things, lullabies, smell memories, songs that haunt, cool clouds, sticks collected, trash treasures, bizarre statues, murals, graffiti tags, ranked sunsets and sunrises, party stories, memorable phrases.

- **Test invariants caught zero bugs across the third round** — the catalog-validation suite (33 tests across `SchemaLibraryTests`, `SchemaIOTests`, `SchemaRegistryImportTests`) ran green after each per-category batch. The pattern from rounds 1 and 2 (where invariant tests caught 5 real bugs) made it cheap to add 324 entries without reading every entry's view-default keys twice.

### 2026-05-12 — Schema library + JSON import/export + reset-to-defaults

Three related capabilities added to the Schema Editor, in service of a single goal: make PurpleLife's flexibility tangible and let users move schema definitions between Macs / share them with anyone else.

- **`Models/SchemaLibrary.swift` + `Models/SchemaLibrary+ExtendedCatalog.swift`** — curated catalog of **251 ready-made schema templates** across 13 categories (Productivity, Home & Life Admin, Money, Health, Food, Hobbies, Media, Travel, Creative, Career, Learning, Relationships, and a deliberate "Unusual & Niche" bucket that includes a dream journal, cocktails, tarot readings, weather logs, fishing log, lefse-batch tracker, mushroom foraging, sleep paralysis episodes, lucid dreams, fortune cookies, synesthesia, mishaps, etc. — the "anything can be a schema" pitch). Each entry carries a category, blurb, search keywords, and a complete `ObjectType` template with primary / kanban / calendar / gallery defaults wired up. The catalog is split across two files (`coreEntries` + `extendedEntries`) and combined by a computed property so adding more entries doesn't risk one giant Swift file pushing past compiler limits.
- **`Views/SchemaLibrarySheet.swift`** — three-pane gallery (categories → results → preview) reached from the Schema Editor toolbar's **Library** button (or the new "Browse library…" button under the types rail). Free-text search across names, fields, blurb, and keywords; preview shows the field list with view-defaults badges; **Import** clones the template via `Entry.materialize()` (fresh UUIDs on the type and every field) so repeated imports of the same template never collide.
- **`Services/SchemaIO.swift`** — pure-function JSON encode/decode for `[ObjectType]` inside a `purplelife.schema.v1` envelope. Mirrors the `ThemeIO` shape (file extension `.purplelifeschema.json`, fresh ids on import, lenient decode that also accepts a bare `[ObjectType]` array). Decode throws `ImportError.unrecognizedFormat` / `.empty` for typed failure handling. Forces `builtIn = false` on every imported type — built-in status is reserved for ids the app ships with and can never be claimed by an imported file.
- **`Views/MultiSchemaExportSheet.swift`** — multi-select sheet for "Export multiple…": select-all / none, per-type checklist, counts, then a final NSSavePanel.
- **`Views/SchemaEditor.swift`** — toolbar gains a **Library** button and a **More** menu (Import from file…, Export <selected>…, Export multiple…, Export all…, Reset built-ins to defaults…). Per-type rail rows also pick up a context-menu "Export" entry. The reset action is alert-gated and undoable.
- **`Services/SchemaRegistry.swift`** — two new methods:
    - `importTypes(_:)` runs each incoming type through fresh-id stamping and renames colliding plurals with an "(imported)" suffix; routes through `upsertType` so each insertion participates in undo + CloudKit fan-out.
    - `resetBuiltInsToDefaults()` rebuilds every built-in from `SchemaSeed.allTypes`, fans the rewritten types out to CloudKit via `pushType`, and registers an undo snapshot. User-defined types and per-device `hiddenBuiltInIds` are untouched. Record data survives because records key field values by `FieldDef.key` (derived from the field name and stable across resets), not by field id.
- **`Tests/.../SchemaLibraryTests.swift`** — 14 new tests covering catalog invariants (every entry has a primary field, kanban keys point at select fields, calendar keys at date fields, gallery keys at attachment fields), search behavior (by name / category / keyword, case-insensitivity), and the materialize → registry handoff (fresh ids per import, two imports don't collide).
- **`Tests/.../SchemaIOTests.swift`** — 13 new tests on the envelope round-trip, fresh-id discipline, `builtIn=false` enforcement, multi-type bundles, disk read/write, and the three failure modes (corrupt JSON, wrong format tag, empty envelope). Plus 3 tests on `SchemaRegistry.importTypes` (user-defined coercion, plural-name collision suffix) and `resetBuiltInsToDefaults` (built-ins restored, user types preserved).

Doc updates: USER_MANUAL.md gains a Schema Library subsection and an Import/Export subsection under "Schema editor". HANDOFF.md gets a design decision entry.

208/208 tests pass.

### 2026-05-12 — Fix: Keychain DEK preservation — refuse to overwrite an existing-but-unreadable slot

Data-loss bug discovered while exercising the recovery UX. `KeychainStore.getData` returned `nil` for any non-success status from `SecItemCopyMatching` — `errSecItemNotFound`, `errSecAuthFailed`, transient unlock issues, all collapsed. `KeyStore.refreshState` then treated every nil as "no DEK exists yet", AppState called `setupKeychainManaged()`, and the new DEK silently **overwrote** the existing slot. The on-disk encrypted database became permanently unreadable, RecoveryScreen fired, the user lost data — for what may have been a momentary Keychain hiccup.

Two new guards:

- **`Services/KeychainStore.swift`** — new `entryStatus(for:) -> EntryStatus` metadata-only probe. Returns `.present` / `.absent` / `.unknown(OSStatus)` so callers can tell "definitively not there" apart from "couldn't tell."
- **`Services/KeyStore.swift`** — `setupKeychainManaged` calls `entryStatus` before generating a DEK and throws the new `KeyStoreError.keychainEntryAlreadyExists` when the slot is anything other than `.absent`. The DEK never gets overwritten on a transient miss.
- **`Services/DatabaseService.swift`** — new `databaseFileLooksEncrypted()` helper (probes file size + SQLite magic header). Belt-and-suspenders: if some external tool deletes the Keychain entry but the encrypted DB is still on disk, we surface `dbHealth = .unrecoverable` *after* the (now-successful) bootstrap so the user sees the recovery sheet instead of a silently broken app.
- **`App/AppState.swift`** — bootstrap path catches `.keychainEntryAlreadyExists` and surfaces the recovery sheet with a transient-failure message; also surfaces it post-bootstrap when the DB file looks encrypted.
- **`Tests/.../KeyStoreTests.swift`** — new regression test (175/175 → 175/175 green): `setupKeychainManaged` must throw `.keychainEntryAlreadyExists` rather than overwrite an existing slot. Includes a `KeyStore.test_forceState(_:)` escape hatch used only by tests to simulate the "looks like first launch even though the slot exists" scenario.

### 2026-05-12 — First-launch sync bootstrap: per-record progress in `pullingInitial` / `pushingLocalChanges`

The sub-states added on 2026-05-10 already named *which* bootstrap step was in flight (checking account / ensuring zone / pulling / pushing) so the user wasn't staring at a generic 5-minute "Setting up sync…". This change adds finer-grained progress *within* the two long steps so the footer shows visible motion:

- `SetupStep.pullingInitial(received: Int)` — running counter, no total (CloudKit doesn't tell us how many records to expect ahead of time). Label is `"Pulling existing data… (47 received)"`. Updated from `recordWasChangedBlock`, throttled to every 10 records so a thousand-record initial pull doesn't fire a thousand main-actor updates.
- `SetupStep.pushingLocalChanges(processed: Int, total: Int)` — both known upfront because the push iterates a pre-fetched local set. Label is `"Pushing local changes… (12 / 85)"`. Updated per record; the push is a sequential round-trip-per-record loop, so per-record granularity is cheap and gives the user something to watch.
- Only fires during the bootstrap's `.settingUp(.pullingInitial / .pushingLocalChanges)` state — background polls and post-push pulls briefly flip status to `.syncing`, which surfaces a plain "Syncing…" label without the counter. Background sync is supposed to be invisible; the counter is signal only when the user is staring at the launch screen.

### 2026-05-12 — Spell-check on record-level `.text` fields

SwiftUI's macOS `TextField` doesn't expose the continuous-spell-check / grammar flags that `NSTextField`'s field editor accepts, so single-line text inputs across the app had been silent (no red squiggles) while the longer rich-text editors got the flags via direct `NSTextView` config. New `SpellCheckedTextField` `NSViewRepresentable` wraps an `NSTextField`, configures the shared field editor on focus, and exposes a `TextField`-shaped initializer for drop-in swaps.

- **`Views/SpellCheckedTextField.swift`** (new, ~90 LOC) — placeholder, binding, and optional `onSubmit` callback. Field editor configured with `isContinuousSpellCheckingEnabled = true`, `isGrammarCheckingEnabled = true`, `isAutomaticSpellingCorrectionEnabled = false` (autocorrect off — silent substitution on notes containing code / acronyms / brand names is more harmful than helpful).
- **`Views/Detail.swift`** — `FieldKind.text` now renders through the wrapper. `.url` and `.email` keep the plain `TextField`; domain syntax lights the dictionary up uselessly in those cases. Other call sites (Schema Editor field names, NoteEditor title, Quick Capture, etc.) stay on `TextField` for now — extending the wrapper to support SwiftUI `.font` + `.focused()` is a follow-up if the asymmetry bites.

### 2026-05-12 — Recovery UX for "encrypted DB + Keychain DEK gone" trap

When the on-disk SQLCipher database is encrypted with a key the app can't reach (most common cause: Keychain entry cleared while the file stayed encrypted), the launch path used to leave the user with a normal-looking sidebar but every query failing in the console — silent breakage with no recovery path. Now PurpleLife detects the mismatch and takes the window over with a clear orange-lock recovery screen.

- **`Views/RecoveryScreen.swift`** (new) — full-window takeover. Explains what happened, offers two paths: **Quit PurpleLife** (let the user restore from a `~/Downloads/PurpleLife backup/` ZIP) and **Reset and start fresh** (destructive, behind a confirmation dialog).
- **`Services/DatabaseService.swift`** — new `isUsingPlaceholderPool: Bool` flag set when init's catch substitutes the temp placeholder; cleared on successful `reopenDatabase()`. New `resetUnrecoverableDataAndReopen()` quarantines the DB + settings + attachments into a timestamped `.unrecoverable-<ISO8601>/` sibling folder (nothing deleted) and creates a fresh keyed DB at the original path.
- **`App/AppState.swift`** — new `dbHealth: DBHealth` published property (`.ok` / `.unrecoverable(String)`). Set after the launch-time `reopenDatabase()` attempt; the placeholder-flag check is what flips it. New `resetUnrecoverableData()` wraps the database call, reloads settings + UI on success.
- **`Views/ContentView.swift`** — swaps to `RecoveryScreen` when `dbHealth` is `.unrecoverable`.

### 2026-05-12 — Rich-text editor: direct-manipulation image resize

Clicking an inline image in any rich-text or noteLog editor now selects it and draws a tinted border with four white corner handles. Drag a handle to live-resize with aspect ratio locked; release commits and fires the autosave debounce. Coexists with the right-click "Image size" submenu — direct manipulation is the fast path, the slider popover is the precision path, the presets are quick-jumps. Aspect lock is unconditional (no shift-to-unlock); inline images always look wrong when stretched.

- **`Views/RichText/RichTextEditor.swift`** — new `ResizableImageTextView: NSTextView` subclass (~280 LOC). Overrides `mouseDown`/`mouseDragged`/`mouseUp` for handle hit-testing and live-resize math; overrides `draw(_:)` to render the selection border + handles on top of the text. Aspect locked at the natural pixel-rep ratio. Clamped at min 40 pt (matches slider popover floor) and max natural pixel width (no upscale blur). Reloads the source bytes from the file wrapper on every drag so successive resizes don't progressively degrade the bitmap (same trick `resizeImage(at:toWidth:)` already used for the slider). `setSelectedRange` overridden so arrow-key navigation off the image clears the handle display.
- `makeNSView` now wires the `NSScrollView` + `NSTextView` manually (the `NSTextView.scrollableTextView()` convenience returns a base `NSTextView` and can't substitute a subclass). Same geometry the convenience built — vertical scroller, width-tracking container.

### 2026-05-12 — Fix: NavigationSplitView "blue stripe" trap

A user dragging the main-window sidebar splitter past the window edge could persist a sidebar width (e.g. 3087 px in a 1147 px window) into AppKit's `NSSplitView Subview Frames …` key in `~/Library/Preferences/com.bronty13.PurpleLife.plist`, causing the sidebar to fill the entire window on every subsequent launch — detail pane pushed off-screen, no UI affordance to recover. Two-part defense:

- **`Views/ContentView.swift`** — `.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)` on the sidebar so future drags can't exceed the cap.
- **`Views/Notes/NotesWorkspaceView.swift`** + **`Views/ThemeBuilderView.swift`** — added `maxWidth` to their `HSplitView` panes for the same reason.
- **`App/AppDelegate.swift`** — `applicationWillFinishLaunching` strips every `NSSplitView Subview Frames …` key from UserDefaults *before* the window restores. Belt-and-suspenders for users already trapped; future widths re-derive from the SwiftUI modifiers.

### 2026-05-12 — Fix: SQLCipher PRAGMA key form (split-key bug under `SQLITE_DQS=0`)

Our SQLCipher is compiled with `SQLITE_DQS=0`, which makes double-quoted strings parse as identifiers rather than string literals. The original `PRAGMA key = "x'HEX'"` / `ATTACH … KEY "x'HEX'"` form silently resolved differently between the two call sites — encryption ran with one effective key, decryption read another, and every second launch failed with `SQLite error 26: file is not a database`. Migration produced files that couldn't be opened with the same DEK that wrote them.

- **`Services/DatabaseService.swift`** — both PRAGMA key and ATTACH KEY now use the SQL single-quoted form with doubled inner quotes (`'x''HEX'''`), which produces the *string value* `x'HEX'` that SQLCipher recognizes as a raw 256-bit blob (no KDF) regardless of DQS. Comment in `makeConfiguration()` explains the gotcha so future-me doesn't "clean up" the awkward quoting.
- Init's previously-`try!` open is now wrapped in do/catch — if the file is encrypted and the key isn't wired yet (the normal property-init ordering), substitute a temp-file placeholder pool so the property stays non-nil; `AppState.init` calls `reopenDatabase()` after wiring the resolver, which replaces it with the real keyed pool. Stops the migration from bricking the app between key-not-ready init and key-ready reopen.
- Migration's throwaway pool moved from `:memory:` to a real temp file because GRDB's `DatabasePool` requires WAL mode, which isn't available on in-memory databases (`could not activate WAL Mode at path: :memory:`).
- New `purgeMigrationThrowaways()` sweep removes lingering `purplelife-throwaway-*` files in `NSTemporaryDirectory()` after the keyed pool is in place.

### 2026-05-11 — Encryption foundation · slice A2 (FINAL): SQLCipher 4.6.1 vendored

Closes the last at-rest encryption gap. The entire `purplelife.sqlite` is now SQLCipher-encrypted at the page level — objects table, FTS5 index, attachments metadata, schema, indexes, everything inside the file.

- **`Vendor/SQLCipher/`** (new) — SQLCipher 4.6.1 amalgamation as a local SwiftPM package. `sqlite3.c` + `sqlite3.h` generated by `make sqlite3.c` against `https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.6.1.tar.gz` (SHA-256 `d8f9afcbc2f4b55e316ca4ada4425daf3d0b4aab25f45e11a802ae422b9f53a3`; build recipe + SHA-pinning in `Vendor/SQLCipher/PROVENANCE.md`). Compiled with `SQLITE_HAS_CODEC` + `SQLCIPHER_CRYPTO_CC` (CommonCrypto backend — no OpenSSL dep) + `SQLITE_ENABLE_SNAPSHOT` + `SQLITE_ENABLE_COLUMN_METADATA` + `SQLITE_ENABLE_FTS5` + `NDEBUG`.
- **`Vendor/GRDB/`** (new) — `groue/GRDB.swift` 6.29.3 vendored with two surgical patches: `Sources/CSQLite/` converted from `.systemLibrary` to a real `.target` whose `shim.h` does `@import SQLCipher;`, and `Package.swift` declares CSQLite's dependency on `.package(path: "../SQLCipher")`. This is what re-tags GRDB's compiled `sqlite3_*` symbol bindings against our SQLCipher binary instead of `libsqlite3.dylib` at link time.
- **`project.yml`** — both packages declared as local paths; PurpleLife (and tests) depend on GRDB which transitively pulls SQLCipher.
- **`Services/DatabaseService.swift`** — `Configuration.prepareDatabase` runs `PRAGMA key = "x'<hex>'"` plus the four SQLCipher-4 default PRAGMAs (cipher_page_size=4096, kdf_iter=256000, HMAC_SHA512, PBKDF2_HMAC_SHA512) explicitly pinned. New `migratePlaintextToSQLCipher(at:key:)` uses `sqlcipher_export()` to copy a plaintext file to a freshly-keyed sibling, then atomic-renames into place. `isPlaintextSQLite(at:)` magic-header probe gates the migration. `reopenDatabase()` orchestrates the flow on first launch after the keystore is wired.
- **`App/AppState.swift`** — wires the resolver, calls `database.reopenDatabase()` to trigger the SQLCipher migration on existing installs.
- **Slice A2′ status**: column-level wrap of `objects.fields_json` is now redundant. Removed from the active CRUD write path; `unsealFromStorage` stays on the read path to handle data written during the A2'-only window.

**Final at-rest posture**:
- ✅ `settings.json` — AES-256-GCM (slice A3)
- ✅ Attachment files — AES-256-GCM (slice A3)
- ✅ `purplelife.sqlite` (entire file) — SQLCipher (this slice)

CloudKit transit + at-rest in iCloud unchanged: still `CKRecord.encryptedValues` E2E.

- **4 new SQLCipher tests + 2 retired A2′ tests**. **169/169 tests green** (was 165 with A2′ + 4 SQLCipher tests - 2 retired A2′ tests + 1 routing-probe helper test = 168, plus the migration test = 169).

### 2026-05-11 — Encryption foundation · slice A2′: field-level encryption on objects.fields_json

The originally-planned A2 was a SwiftPM swap to a SQLCipher-bundled GRDB fork plus a `sqlcipher_export()` migration. Tried `duckduckgo/GRDB.swift` 2.10.0; it has SQLCipher *code paths* but no SwiftPM SQLCipher target. Vendoring SQLCipher amalgamation source or picking a third-party wrapper package both want eyes on the package choice that aren't appropriate for a batch decision. Reverted `project.yml` and shipped a stand-in that gets us most of the protection without a dependency swap.

- **`Services/DatabaseService.swift`** — new `nonisolated static var keyResolver` wired by AppState. Two pure helpers: `sealForStorage(_:key:)` wraps a record's `fieldsJSON` with `EncryptedJSON` (AES-256-GCM + magic header `PLIF\x01`), base64-encoded to fit the TEXT column. `unsealFromStorage(_:key:)` does the inverse and is tolerant of legacy plaintext rows (detected via magic-header mismatch). Every CRUD method seals on write, unseals on read. **In-memory `ObjectRecord.fieldsJSON` is always plaintext**; callers (`ObjectEngine`, `CloudKitSyncService`, `SearchService`, all views) are unchanged.
- **Launch-time migration**: `DatabaseService.encryptExistingObjectsIfNeeded()` walks every row, wraps any plaintext `fields_json`. Idempotent; re-runs on every launch are essentially free.
- **CloudKit wire format unchanged**: the sync layer goes through `DatabaseService.fetchObject` (which decrypts) and produces plaintext for `encryptedValues["fieldsJSON"]`. Pull is symmetric. Macs on pre-A2′ and post-A2′ builds interop seamlessly.
- **Defensive blanking on decrypt failure**: missing key or wrong key returns `fieldsJSON = "{}"` rather than crashing. The user sees "no data visible" until the keystore unlocks; nothing on disk is destroyed.
- **6 new `AtRestEncryptionTests`** — seal/unseal round-trip; missing-key + wrong-key both blank the fields; plaintext-row pass-through (legacy compatibility); end-to-end DB round-trip verifies stored bytes are ciphertext; migration sweep wraps legacy rows idempotently. **165/165 tests green** (was 159, +6).

**Honest at-rest posture after this slice**:
- ✅ `settings.json`, attachment files, `objects.fields_json` — all AES-256-GCM at rest.
- ❌ `objects_fts.title` + `objects_fts.body` — FTS5 search index, plaintext on disk. Contains every record's title and body text in searchable form. Closing this requires either a custom decrypt-on-tokenize SQLite extension or the full SQLCipher swap.
- ❌ Sync-metadata columns (`type_id`, `parent_id`, `created_at`, `updated_at`) — needed for CloudKit LWW; can't be encrypted without breaking sync.
- ❌ Attachment metadata (`attachments.filename`, `mime_type`, `size_bytes`) — local-only, but exposed to a bare-file SQLite-inspection attack.

The user content — every field value in every record — is now encrypted at rest. The remaining gap is schema-shape metadata + the FTS index. Full SQLCipher swap remains the right long-term answer; gated on the SwiftPM package decision.

### 2026-05-11 — Documentation · slices C1+C2: customer-facing security whitepaper + docs sweep

Phase C of the encryption-and-notes plan. Documents the current at-rest / in-transit / in-iCloud posture honestly, including the still-open SQLCipher gap.

- **`Docs/SECURITY.md`** (new) — 12-section customer-facing security whitepaper. Covers: what we protect (and what we don't), threat model (device theft, bare-file exfiltration, CloudKit compromise, MitM, lost device), at-rest layer-by-layer (with the SQLCipher gap called out explicitly), in-transit, in-iCloud E2E (why inline-in-RTFD instead of CKAsset for note images), multi-device sync (per-Mac DEKs, no key ferrying), cryptographic primitives table, where each role lives in the source, three verification recipes anyone can run (`file` against settings.json + attachments, CloudKit dashboard inspection, keystore.json structural audit), known limitations (the honest section — Keychain ACL boundary, CloudKit metadata leakage, no forward secrecy, no biometric gating, memory safety), vulnerability reporting channel.
- **`README.md`** — new "Security & encryption" section near the top. Three-layer summary, link to whitepaper, source-level audit pointers to the load-bearing files. Also corrects the headline blurb to mention notes ("planner, notes, hobbies…").
- **`USER_MANUAL.md`** — new "Your data is encrypted" chapter explaining the encryption story in user-facing language: what's encrypted, what the Security settings tab does, what happens if you forget your passphrase (data loss; no recovery; that's the point), how multi-Mac sync stays private. New "Notes" chapter documents the workspace UX, keyboard shortcuts (⌘B/I/U, ⇧⌘X, ⌘⌥1/2/3, ⌘⌥0, ⇧⌘7/8, ⌘K), autosave behavior, image-size policy (1920 px / JPEG @ 0.7), size-budget banner.

No code changes in this slice — purely documentation. Tests still **159/159 green**.

### 2026-05-11 — Notes feature · slices B1+B2+B3: WYSIWYG notes shipped

Three plan-document slices landed as one batch (tightly coupled: storage shape + editor + seeded type can't ship independently without leaving a half-feature visible to the user).

- **`Models/FieldDef.swift`** — new `FieldKind.richText` case. Display name "Rich text", SF Symbol `text.book.closed`. Not groupable for kanban; not a date for calendar.
- **`Models/RichTextValue.swift`** (new) — pins the JSON storage shape: `{ rtf: <base64>, plain: <text mirror> }`. RTFD encoding when the body has attachments (pasted images), plain RTF otherwise. `from(jsonDictionary:)` tolerates missing keys / bad base64. `RichTextLimits` carries the size budget: hard cap at 900 KB (keeps the encrypted record under CloudKit's ~1 MB ceiling with headroom for other fields).
- **`Services/SearchService.swift`** — `searchableText` reads the `plain` mirror from richText fields. FTS5 indexing keeps working unchanged; encoded RTF bytes never reach the index.
- **`Views/RichText/RichTextEditor.swift`** (new) — port of PurpleTracker's 406-LOC `NSTextView`-backed editor. SwiftUI toolbar (bold/italic/underline/strikethrough, 3 heading levels, bullet/numbered lists, link, color, clear formatting), keyboard shortcuts (⌘B/I/U, ⇧⌘X, ⌘⌥1/2/3/0, ⇧⌘7/8, ⌘K). Carries the `ensureAttachmentFileWrappers` load-bearing fix that makes pasted screenshots survive RTFD round-trip.
- **`RichTextImagePolicy`** (NEW in this port; not in PurpleTracker) — caps incoming image width at 1920 px and encodes non-alpha images as JPEG @ 0.7. Keeps notes under the CloudKit budget without changing the E2E guarantee (compression isn't confidentiality).
- **`Views/Fields/RichTextField.swift`** (new) — SwiftUI adapter that hosts `RichTextEditor` inside `Detail.swift`'s field form. Implements the "live text storage at save" trick so paste-inserted attachments aren't lost between binding propagation and write. Enforces `RichTextLimits.fits` before writing back; over-budget edits leave the buffer at last-known-good and surface the error inline.
- **`Models/SchemaSeed.swift`** — new seeded `note` ObjectType. Fields: `noteDate` (date, required), `title` (text, required), `category` (select: Personal / Work / Ideas / Journal / Reference), `body` (richText). `primaryFieldKey: title`, `calendarDateKey: noteDate`, `kanbanGroupKey: category`. Color `#9D4DCC` (brand purple), SF Symbol `note.text`.
- **`Views/Notes/NotesWorkspaceView.swift`** (new) — two-pane HSplitView: list left, editor right. Toolbar +button bound to ⌘N. Re-reads on remote-change notifications.
- **`Views/Notes/NotesListView.swift`** (new) — search bar, date-grouped sections with friendly headers ("Today" / "Yesterday" / "Mon, Mar 5, 2026"), 2-line plain preview per row, context-menu delete.
- **`Views/Notes/NoteEditorView.swift`** (new) — date picker + title + `RichTextEditor` + Save button (⌘S) + Saved/Unsaved indicator. **1.2 s debounced autosave** + flush on view dismiss + flush on note-id change. Same shape as PurpleTracker's `NoteEditorView.swift:64–96`.
- **`Views/ContentView.swift`** — branches at the type router: `selectedTypeId == "Note"` routes to `NotesWorkspaceView`, everything else still routes to `RecordsScreen`. One-line change, zero impact on other types.
- **`Views/Detail.swift`** + **`Views/RecordsScreen.swift`** + **`Views/FieldDisplay.swift`** + **`Services/ExportService.swift`** — exhaustive `switch field.kind` sites extended with `.richText` (no `default` fallthrough in any of them; the compiler enforced the audit).
- **7 new `RichTextValueTests`** — JSON round-trip, missing-keys tolerance, NSAttributedString → RTF conversion produces magic, size-budget boundaries, FTS body includes `plain` mirror, FTS skips records with no `plain` key. **159/159 tests green** (was 152, +7).

**Current at-rest posture across PurpleLife**:
- Settings + attachment files: ✅ encrypted (slice A3).
- CloudKit transit + at-rest in iCloud: ✅ encrypted end-to-end (`encryptedValues`).
- SQLite database file (`purplelife.sqlite`): ❌ still plaintext locally — closes when slice A2 (SQLCipher swap) ships.

### 2026-05-11 — Encryption foundation · slice A3: settings.json + attachment files encrypted at rest

Shipped out of plan-document order (A1 → A3 → A2-pending). Slice A2 (SQLCipher DB) was deferred because it requires switching the GRDB SwiftPM dependency to a SQLCipher-capable fork — a structural change that wants a clean review-able commit rather than landing inside a multi-slice batch. The two side-channel paths that don't depend on SQLCipher (settings.json + attachment files) ship now.

- **`Services/AttachmentService.swift`** — new `keyResolver` static so the enum-of-statics pulls the live DEK without taking a `KeyStore` dependency at the call site. `add(from:parentObjectId:fieldKey:)` writes via `EncryptedJSON.safeWrite(_, to:, key:)` — file content on disk is AES-GCM ciphertext when a key is in scope; sha256 (used for content-addressed dedup) is still computed over the plaintext, so two adds of identical bytes still de-duplicate to one encrypted file. New `read(sha256:) throws -> Data?` and `image(forSha256:) -> NSImage?` are the read-path replacements for `NSImage(contentsOf:)`. New `encryptExistingFilesIfNeeded()` is the one-shot launch-time sweep that wraps any plaintext file lingering from a pre-A3 install — idempotent thanks to magic-header detection.
- **`Models/AppSettings.swift`** — `SettingsStore.init(keyResolver:)` accepts an optional key resolver; `load()` routes raw bytes through `EncryptedJSON.unwrap` (magic-detected); `save()` routes through `safeWrite` which **refuses to silently downgrade encrypted-on-disk to plaintext** (load-bearing for the seed save during early init, when the resolver is still nil).
- **`App/AppState.swift`** — after the keystore bootstraps, wires resolvers into both `SettingsStore` and `AttachmentService`, then calls `settingsStore.load()` + `save()` to encrypt any plaintext file lingering from a pre-A3 launch, then calls `AttachmentService.encryptExistingFilesIfNeeded()` to do the same for the attachments dir. Idempotent: every subsequent launch is essentially free.
- **`Views/AttachmentFieldEditor.swift`** + **`Views/RecordsScreen.swift`** — converted the two existing `NSImage(contentsOf:)` call sites to `AttachmentService.image(forSha256:)`. The legacy `fileURL(forSha256:)` API stays (some callers want a stable path identifier, even when the bytes at that path are ciphertext) — comments now explicit about that.
- **6 new `AtRestEncryptionTests`** — encrypted attachment write produces magic-headered bytes on disk and round-trips via `read(sha256:)`; wrong-key read throws (AES-GCM auth tag check); the launch-time sweep wraps plaintext idempotently; dedup survives encryption (two adds of identical content → one encrypted file, both reads work); settings.json encrypted round-trip; settings.json safeWrite refuses to downgrade. **152/152 tests green** (was 146, +6). The new tests carry explicit `AttachmentService.keyResolver` setup so they exercise the actual encrypted path — existing `AttachmentServiceTests` continue to test the plaintext path under XCTest's bootstrap-skipping mode, so both paths stay covered.

**Honest at-rest posture after this slice**: settings.json + every attachment file are AES-GCM ciphertext on disk. The SQLite database itself (`purplelife.sqlite` — objects, attachments-metadata, FTS5 index) stays plaintext-local until A2 ships. CloudKit `encryptedValues` path is unchanged (everything that crosses the network is still E2E).

### 2026-05-11 — Encryption foundation · slice A1: KeyStore + crypto primitives

First slice of the encryption-at-rest work that's a prerequisite for the Notes feature. Lands the cryptographic infrastructure without yet wiring it into any persistence path — slices A2 (SQLCipher database) and A3 (encrypted settings + attachment files) build on top of this.

- **`Services/Crypto.swift`** (port from `PurpleIRC`) — AES-256-GCM seal/open via `CryptoKit`, PBKDF2-HMAC-SHA256 (300 000 iterations default) via `CommonCrypto`, `randomBytes(_:)` over `SecRandomCopyBytes`, and a `SymmetricKey.rawData` convenience for serialising wrapped keys.
- **`Services/KeychainStore.swift`** (port + adapt) — thin SecItemAdd/Copy/Delete wrapper scoped to `kSecAttrService = "com.purplelife"`. PurpleIRC's per-profile credential helpers (`CredentialRef`) didn't carry over — PurpleLife doesn't have a multi-profile concept. `kSecAttrAccessibleWhenUnlocked` so the DEK is reachable while the Mac is unlocked but not while it's at the login screen.
- **`Services/EncryptedJSON.swift`** (port + adapt) — 5-byte magic-header envelope wrapping AES-GCM ciphertext. **Magic changed to `"PLIF\x01"`** (from PurpleIRC's `"PIRC\x01"`) so a file can never be misidentified across apps. `safeWrite(_:to:key:)` refuses to silently downgrade an already-encrypted file to plaintext — the load-bearing invariant when the keystore is locked during an early app-launch save.
- **`Services/KeyStore.swift`** (adapted from PurpleIRC) — two operating modes:
  - **Keychain-managed (default for new installs).** `setupKeychainManaged()` generates a random 256-bit DEK and stores it only in the Keychain. No `keystore.json` on disk. Defends against bare-file exfiltration (Time Machine backup on a shared NAS, Dropbox-synced Application Support, etc.); the Mac itself is the trust boundary. App opens silently.
  - **Passphrase-protected (opt-in).** `addPassphrase(_:)` wraps the existing DEK under a PBKDF2-derived KEK and writes `keystore.json`. `lock()` becomes meaningful (clears in-memory + Keychain). `changePassphrase` re-wraps the DEK in milliseconds — no re-encryption of user data. `removePassphrase` reverts to Keychain-managed mode after verifying the current passphrase. No recovery if a passphrase is forgotten and the Keychain cache is cleared — that's the point.
  - `refreshState()` reads both surfaces (file + Keychain) to compute `(state, hasPassphrase)`. Both are `@Published` so the Security settings UI updates live.
- **`Views/Settings/SecuritySettingsTab.swift`** (new) — status row + Add/Change/Remove passphrase / Lock now / Reset actions, driven off the keystore's `state` + `hasPassphrase`. Sheet-based passphrase entry with confirm-match validation; in-form red-text error surfacing on mismatch / wrong-current-passphrase.
- **`App/AppState.swift`** — adds `@Published var keyStore`. On first launch (`state == .notSetup`), automatically runs `setupKeychainManaged()` so every install — fresh or upgraded — has a DEK ready before any slice A2/A3 persistence path needs one. Skipped under XCTest so unit tests can construct their own per-test keystores against tempDirs.
- **22 new `KeyStoreTests`** covering: AES-GCM roundtrip / wrong-key / tamper detection, PBKDF2 determinism + sensitivity, EncryptedJSON magic round-trip + passthrough + safeWrite downgrade guard, full passphrase lifecycle (setup → lock → unlock from disk → change → unlock), Keychain-managed lifecycle (setup → reopen silently → add passphrase → remove passphrase → wrong-current rejection → reset). **146/146 tests green** (was 124, +22).

**What this slice does NOT do** (to be explicit): no on-disk file is encrypted yet. The SQLite DB, attachment files, and settings.json all remain plaintext for now — slice A2 (GRDB → SQLCipher) and slice A3 (settings + attachments wrap) will land those. The DEK exists in the Keychain for every install from this slice forward, ready to be consumed.

### 2026-05-11 — Bug fix: Weight records (and any numeric-primary type) showed "Untitled" everywhere

Real bug, not import-specific — surfaced by the user noticing that imported Weight entries all rendered as "Untitled" in the records list. Manual entries had the same issue; imports just made it visually noisy.

**Root cause**: `FieldDisplay.title(of:in:)` cast `record.fields()[primaryFieldKey] as? String`. The Weight type's `primaryFieldKey` is `pounds` (a `.number` field stored as `Double`), so the cast failed and the function fell through to its "Untitled" fallback. All 12 call sites that render a record's title (detail header, quick switcher, link picker, list footers, today panels) inherited the bug.

**Fix**: branch on the field's `kind` before falling back. `.number` runs through `numberValueOrNil` (same formatter the list cells use), `.date` / `.dateTime` run through `dateValueOrNil`, everything else takes the existing String path. Single-point fix in `Views/FieldDisplay.swift`.

- **5 new `FieldDisplayTitleTests`** — numeric primary renders the value (Double + Int), missing numeric primary still degrades to "Untitled", text primary unchanged, empty text primary still "Untitled". **124/124 tests green** (was 119, +5).

### 2026-05-11 — Appearance theming · slice 3: JSON import/export

Closes the stretch goal from slice 1. Themes can now be shared between Macs (or users) as `.purplelifetheme.json` files via standard macOS Save / Open panels — no settings.json hand-editing required.

- **`Services/ThemeIO.swift`** (new) — pure-function encode / decode. `sanitizedFilename(for:)` strips path separators, control characters, and leading dots before composing the default filename (`<sanitized-name>.purplelifetheme.json`); empty / all-illegal names fall back to `theme`. `encode(_:)` writes pretty-printed JSON with sorted keys so iterative exports diff cleanly. `decode(from:)` assigns a **fresh UUID** so re-importing the same file (or a file shared from another Mac) doesn't collide with an existing theme's id — `basedOn` and `createdAt` are preserved as provenance metadata.
- **`Views/Settings/AppearanceSettingsTab.swift`** — adds an **Import…** button next to "+ New theme" (NSOpenPanel restricted to JSON, defaults to the user's resolved export directory). Inline red-text error surfaces when a chosen file can't decode. Every theme card now carries a **right-click context menu** with **Export theme…** (Edit appears too on user-theme cards) — built-in cards synthesize a UserTheme via `duplicate(of:)` on demand so any palette in the app can be shipped to disk.
- **`Views/ThemeBuilderView.swift`** — Export button in the footer (between Delete and Cancel). Exports the current draft without committing it into `userThemes` — users can experiment, export a snapshot, and then keep iterating before deciding to Save.
- Both export paths use NSSavePanel rooted in `appState.settingsStore.resolvedExportDirectory` (the user's existing export-directory preference) and reveal the written file in Finder on success — same pattern as the per-type ExportService.
- **10 new `ThemeIOTests`** — filename sanitization (path separators / leading dots / empty), default-filename construction with extension, encode produces pretty-sorted JSON, decode assigns fresh UUID, full write→read roundtrip through `/tmp`, corrupt JSON / missing-key / missing-file failure modes. **119/119 tests green** (was 109, +10).
- **`USER_MANUAL.md`** — documents the Import button, right-click Export action on theme cards, and the Export button in the builder.

**Deliberate omissions** (recorded in HANDOFF): no custom UTType registration for `.purplelifetheme.json` (would mean a CFBundleDocumentTypes entry + icon work — not worth it for a single-file export format); no batch export of all user themes (one-at-a-time covers the realistic sharing case); no JSON validation beyond Codable decode (the format IS UserTheme, and `materialised`'s defensive parser handles corrupt hex strings without crashing).

### 2026-05-11 — Appearance theming · slice 2: WYSIWYG theme builder

Closes the queued slice from this morning's slice 1 entry. Users can now create, edit, and delete custom themes through a dedicated sheet — no more hand-editing `settings.json` to experiment.

- **`Views/ThemeBuilderView.swift`** (new, ~290 LOC) — sheet with `HSplitView` editor on the left and a live preview pane on the right. Editor uses a `Form` grouped by purpose (Surfaces / Text / Lines / Accent), with each row exposing **two** `ColorPicker`s side-by-side (Light then Dark) so a slot is tuned for both modes in one place. The preview pane renders a mini chrome — sidebar with mock type rows, main area with header + two list rows + a card — and carries its own Light/Dark segmented toggle so either half of the pair can be audited without leaving the sheet (independent of the user's actual appearance setting). Cancel discards; Save upserts and switches the active themeID to the draft; Save As clones with a fresh UUID + new name; Delete (only visible when editing an existing theme) removes the theme and, if it was active, falls back to its `basedOn` built-in (or Royal Purple).
- **`Views/Settings/AppearanceSettingsTab.swift`** — "Custom themes" placeholder replaced with a real **+ New theme** button that duplicates the currently-selected theme as the editor's starting point. User-theme cards in the picker grid get an **edit** affordance (pencil button) that opens the builder on the existing theme. Sheet state managed via a single `BuilderTarget` enum so opening for New vs. Edit goes through the same `.sheet(item:)` modifier.
- **`Models/PurpleTheme.swift`** — extracted two persistence helpers from the builder so they're testable without instantiating SwiftUI: `UserTheme.upsert(_:in:)` (insert or replace by id, preserving position so an edit doesn't shuffle the picker grid) and `PurpleTheme.resolveAfterDelete(currentID:removedID:basedOn:)` (compute the active themeID after deletion — falls back to `basedOn` when known, else Royal Purple, and leaves the current selection untouched if the deleted theme wasn't active).
- **6 new `ThemeTests`** cover the persistence helpers: upsert appends a new theme, upsert replaces in place preserving order, delete-fallback uses `basedOn` when valid + active, delete-fallback uses Royal Purple when `basedOn` is unknown, delete-fallback uses Royal Purple when `basedOn` is nil, delete preserves current selection when deleting an inactive theme. **109/109 tests green** (was 103, +6).
- **`USER_MANUAL.md`** — documents the New theme / Edit / Save / Save As / Delete flow and the preview-pane appearance toggle.

The builder UI itself isn't unit-tested (same constraint as every SwiftUI view in the suite) — every commit path routes through the testable model-layer helpers above, and the SwiftUI surface is small enough that manual verification covers it.

### 2026-05-11 — Appearance theming · slice 1: built-in themes + Light/Dark/Auto

User-facing customization of the app's look, framed as an accessibility need: users must be able to dial up contrast, swap surface tones, and force a specific appearance regardless of macOS setting. Reverses the prior "themes deferred — would muddy the design language" decision recorded in HANDOFF on 2026-05-10. The compromise that resolves the original concern: defaults stay the design-handoff oklch palette ("Royal Purple"), all built-ins are purple-rooted, the design coherence isn't diluted — customization is additive on top.

- **`Models/PurpleTheme.swift`** (new) — `PurpleTheme` struct with paired light/dark `Slot`s per chrome token (bg, sidebar, card, text/textDim/textFaint, cardBorder/hairline/rowHover, accent/accentSoft). 5 built-ins, all purple-rooted: Royal Purple (default = the existing oklch palette), Lavender (soft pastel), Plum (deep saturated), Heather (warm mauve), High Contrast (accessibility — pure white/black surfaces with bold purple accent). Plus `AppearanceMode` enum (`system`/`light`/`dark`) — orthogonal to theme so Auto follows the OS regardless of which theme is picked.
- **`Models/PurpleTheme.swift` — `UserTheme`** — Codable hex-pair mirror of `PurpleTheme` so user-built themes round-trip through settings.json. `duplicate(of:name:)` snapshots a built-in; `materialised` produces a runtime PurpleTheme. **Persistence ships in this slice; the WYSIWYG builder UI ships in slice 2** — settings.json already accepts hand-edited `userThemes` entries today.
- **`Views/Theme.swift`** — converted from a frozen `enum` of design tokens to a thin static facade reading from `Theme.current: PurpleTheme`. Keeps every existing call site (`Theme.bg`, `Theme.accent`, etc.) unchanged across the 32 references in 7 view files; runtime palette swap re-renders everywhere via the Combine bridge below.
- **`Models/AppSettings.swift`** — adds `themeID: String = "royalPurple"`, `appearance: AppearanceMode = .system`, `userThemes: [UserTheme] = []`. Plus a custom `init(from:)` using `decodeIfPresent` for **every** key so older settings.json files (missing any post-launch additions) decode successfully — preserving user settings on upgrade rather than silently resetting to defaults. Closes a latent regression that's been quietly waiting in the prior phases' `try?`-swallowed decode.
- **`Models/AppSettings.swift` — `SettingsStore.currentTheme`** — computed property resolving `themeID` against built-ins, then user themes, falling back to `.royalPurple`. Used by AppState to push the active palette into `Theme.current`.
- **`App/AppState.swift`** — Combine subscription bridges `SettingsStore.objectWillChange` into AppState's own `objectWillChange`, and reapplies `Theme.current = settingsStore.currentTheme` on every settings change. Without this bridge, a theme switch updates only the storage; views observing AppState don't re-render until something else changes.
- **`App/PurpleLifeApp.swift`** — `.preferredColorScheme(appState.settings.appearance.colorScheme)` applied at all five scene roots (main window, schema editor window, quick switcher window, Settings, menu-bar extra). `.system` resolves to `nil` — the OS appearance wins.
- **`Views/Settings/AppearanceSettingsTab.swift`** (new) + tab in `SettingsView` — appearance segmented picker (Auto / Light / Dark) plus a theme grid with mini chrome-preview cards. Each card renders the theme's own surfaces (sidebar strip, bg, card, accent dot) so users see the swap before committing. Selected theme gets an accent-colored ring + checkmark badge. Custom themes (slice 2) render alongside built-ins with a "Custom" badge.
- **`Views/Sidebar.swift`** — removed local `Color(hex:)` extension; the more permissive parser in `PurpleTheme.swift` (handles `#RGB`, `#RRGGBB`, `#AARRGGBB`) is now the single source of truth.
- **15 new `ThemeTests`** — built-in resolution + collision policy (built-ins win over user-themes on id collision), UserTheme duplicate-then-materialise roundtrip, Codable roundtrip preserving all slots, empty-name fallback, corrupt-hex tolerance on materialise, hex parser surface (all three length forms), AppearanceMode → ColorScheme mapping, AppSettings defaults are theming-neutral, **backward-compatible decode of a pre-theme settings.json**, full Codable roundtrip with theme fields populated. **103/103 tests green** (was 88, +15).

### 2026-05-10 — WeightTracker subsumption · slice 4: Smart Import wizard

Final slice of the WeightTracker → PurpleLife port. Brings over the free-form text parser so users can paste arbitrary text (CSV / spreadsheet copy-paste / plain English like "On 3/5/2024 I weighed 182 pounds") and have it become Weight records.

- **`Services/SmartWeightImporter.swift`** (new) — port of WeightTracker's `ImportService` regex parser. Five date formats: ISO-8601, MM/DD/YYYY (or M/D/YYYY), MM-DD-YYYY, abbreviated month name (`Jan 15 2024`), full month name (`January 15, 2024`). Weight extraction with lookarounds (so year digits like `2024` aren't matched as a 3-digit weight) and plausibility bounds (50-700 lb). Output is `[ParsedWeightEntry]` with `Date` (start of day in current TZ) rather than `"yyyy-MM-dd"` strings, plus `isDuplicate` / `isSelected` flags and the matched source line. Same-day duplicates within input collapse to first occurrence; pre-existing days flagged + pre-deselected.
- **`Views/Settings/SmartImportWizard.swift`** (new) — three-state sheet: paste → preview → done. Preview table shows checkbox + date + pounds + source-line excerpt + "dup" badge for matching existing days. Imports go through `ObjectEngine.create` with `source: "Imported"` (matches existing CSV importer for filter consistency).
- **`Views/Settings/ImportSettingsTab.swift`** — adds a "Smart Import" section above the existing CSV section. Examples in the explanatory copy ("CSV, spreadsheet copy-paste, plain English"); button opens the wizard sheet.
- **13 new `SmartWeightImporterTests`** — each date-format pattern (ISO / slash / dash / abbreviated / full / plain English), plausibility bounds (12 lb rejected; year digits not matched), same-day dedup within input, existing-day flagging + pre-deselect, empty input, garbage lines. **88/88 tests green** (was 75, +13).

### 2026-05-10 — WeightTracker subsumption · slice 3b: StatisticsService + Statistics panel + chart overlays

Ported WeightTracker's StatisticsService (~193 LOC of pure math) and surfaced the results both as a dedicated panel and as overlay layers on the existing Charts view kind.

- **`Services/StatisticsService.swift`** (new) — pure-math port. Input rewritten from `[WeightEntry]` to type-agnostic `[(date: Date, value: Double)]`; uses `Date` arithmetic instead of `"yyyy-MM-dd"` ↔ `Date` round-trips (cleaner, less locale-fragile). Components are independently `static` and testable: `linearRegression`, `movingAverage`, `forecastData`, `computeAverageWeeklyChange`, `computeBestWorstWeek`, `computeDaysToGoal`. `compute(...)` returns the full `WeightStats` bundle. Adapter `computeForWeightRecords(_:settings:)` extracts `(date, pounds)` from `[ObjectRecord]` for the Weight type.
- **`Views/WeightStatisticsPanel.swift`** (new) — sheet triggered from the Records → Weight toolbar. Four sections: Overview (start / current / goal / total change / progress bar), Trend (weekly rate / regression slope / R² / best+worst week), BMI (current / starting / goal with category labels — only when `heightInches` is set), Forecast (days-to-goal + projections at 7/14/30/60/90 days). Loss = green, gain = orange, same scheme as the rail card.
- **Chart overlays** added to `RecordsChartBody`. Three checkbox toggles in the toolbar, surface only when viewing the Weight type. **Trend** = regression line drawn from first to last visible date. **7d avg** = 7-day moving average dashed line. **Goal** = horizontal `RuleMark` with a small "Goal · N" annotation; disabled when `goalWeightPounds` is unset (with a tooltip explaining where to set it). Y-axis domain expands to include the goal line so it's always visible.
- **11 new `StatisticsServiceTests`** covering linear regression on known-slope data (recovers slope exactly + R² = 1), moving-average smoothing, BMI calculation, forecast extrapolation, days-to-goal at known slope, edge cases (positive slope → nil, already past goal → 0, fewer than 2 points → nil compute). **75/75 tests green** (was 64, +11).

### 2026-05-10 — WeightTracker subsumption · slice 3a: Weight settings (goal / starting / height / forecast)

Tiny prep slice — adds the four user profile values that slice 3b's chart overlays and Statistics panel need, with a Settings UI surfacing them. Lands on its own (rather than bundled with 3b) so each diff stays focused; AppSettings additions are 5 lines and the UI is one new tab.

- **`AppSettings`** gains four fields: `goalWeightPounds: Double?`, `startingWeightPounds: Double?`, `heightInches: Double?`, `forecastDays: Int = 30`. Optional Doubles so an unset value doesn't render a misleading 0 on the chart. Codable's missing-key tolerance handles existing `settings.json` files transparently — no migration.
- **`Views/Settings/WeightSettingsTab.swift`** (new) — fourth Settings tab. `LabeledContent` rows for goal / starting / height (text fields with `lb` / `in` units) plus a stepper for forecast horizon (1-365 days, default 30). Each field optional; placeholder copy explains what unset means ("(none)" / "(first record)" / "(no BMI)").
- All four values persist via the existing `SettingsStore.save()` path on each set.

64/64 tests still green (no test changes — pure data + UI plumbing).

### 2026-05-10 — WeightTracker subsumption · slice 2: Charts view kind in RecordsScreen

Second slice of the WeightTracker port. Adds a `Charts` view kind alongside Table / Kanban / Calendar / Gallery. Surfaces for any type whose primary field is numeric AND whose schema has at least one date-bearing field — Weight satisfies both; types like Person don't and the Charts tab won't appear in the picker.

- **`Views/RecordsChartBody.swift`** — new file. SwiftUI Charts framework (built-in, no new dep), `LineMark` + `AreaMark` with Catmull-Rom interpolation, accent color tinted to the type's `colorHex`. Time-range picker (7D / 30D / 90D / 1Y / All) at the top. Y-axis auto-scales with 12% padding (and a floor that prevents flat data from rendering as a degenerate domain). Empty state ("No data in this range") when the picker selection has no points.
- **Same-day dedup**: PurpleLife has no unique-per-day constraint (unlike WeightTracker's date-keyed schema). When the user has multiple records on the same calendar day, the chart keeps the most-recently-updated record per day. Last-write-wins, matches WeightTracker's effective semantics.
- **Pure extraction**: `RecordsChartBody.extractPoints(rows:dateKey:valueKey:)` is `nonisolated static` so tests can drive it without a MainActor host. Defensive against missing fields, empty keys, malformed dates.
- **5 new `RecordsChartBodyTests`**: empty input, sort order, same-day dedup, missing-field skipping, empty-keys guard. **64/64 tests green** (was 59, +5).
- **No overlays yet** — Trend / 7-day-avg / Goal-line overlays land in slice 3b once `StatisticsService` is in.

### 2026-05-10 — WeightTracker subsumption · slice 1: Today right-rail Weight sparkline

First slice of the WeightTracker → PurpleLife port (HANDOFF.md plan committed earlier today). Replaces the generic "Latest weight" rail card with a Weight-specific card matching `Design/purplelife/project/screens-light.jsx ScreenToday`'s right-rail weight section.

- **Big bold pounds number** (the latest record's value, monospaced digits, 26 pt) with a small `lb` unit caption.
- **14-day delta badge** in the upper right — green for loss, orange for gain, secondary for zero. No semantic claim about direction; users tracking weight gain can read the sign.
- **Hand-rolled 14-day sparkline** — `Path` over normalized points, `Theme.accent` stroke. SwiftUI Charts deliberately not imported here to keep the rail card lightweight; full Charts comes in slice 2 for the dedicated Charts view.
- **Pattern-match on `type.id == "Weight"`** in `Today.swift`'s `railCard(forSavedQueryNamed:)` — scoped exception, not a pattern for other types. Reading / Photos / etc. continue to render via the generic `RailCard`.
- Card collapses silently when there are no Weight records (matches existing rail behavior).

59/59 tests still green (no test changes — the new code is SwiftUI rendering of data the engine already serves).

### 2026-05-10 — App Nap suppression while CloudKit sync is enabled

Theory-driven prophylactic for the deeper "client went away" follow-up. macOS App Nap suspends background apps that don't have active UI; for an app that needs to stay live to receive silent-push CloudKit notifications, that's the wrong tradeoff. `cloudd` interpreting a napped process as "client went away" matches the symptom we saw — the receiver's CKContainer binding goes stale until the user brings the app back to the foreground (or restarts it).

- `CloudKitSyncService.start` now opens a `ProcessInfo.beginActivity(options:reason:)` assertion with `.userInitiatedAllowingIdleSystemSleep + .suddenTerminationDisabled`. Released in `deinit`. The sync service is owned by `AppState`, which lives for the app's lifetime, so the assertion effectively spans process lifetime.
- `latencyCritical` is **not** included — we don't need to be high-priority CPU-wise, just live.
- `idleSystemSleepDisabled` is **not** included — the Mac going to sleep at night should still work; we want App Nap suppressed but full sleep allowed.

This is a treats-the-symptom-but-correctly-this-time fix paired with the soft-recovery patch from earlier today. If "client went away" stops appearing across the next stretch of normal use, App Nap was the cause. If it still appears, the next investigation rung is longer-lived `CKDatabase` references, dedicated operation queues, or less Task hopping in the subscription handler.

59/59 tests still green.

### 2026-05-10 — Bootstrap sub-states surfaced in the sync status footer

Closes follow-up #1. The 2026-05-10 verification trial saw a fresh Mac sit on a generic "Setting up sync…" badge for ~5 minutes silently before resolving — users couldn't tell whether to wait or kill the app. Now each step of the CloudKit bootstrap stamps a distinct sub-state.

- `Status.settingUp` carries a new `SetupStep` payload — one of `.checkingAccount`, `.ensuringZone`, `.ensuringSubscription`, `.pullingInitial`, `.pushingLocalChanges`. The footer label updates accordingly: "Checking iCloud account…" → "Setting up CloudKit zone…" → "Registering for push notifications…" → "Pulling existing data…" → "Pushing local changes…" → "Synced".
- A user looking at a hung "Pulling existing data…" knows it's the initial fetch (probably big the first time on a fresh Mac, just wait); a hung "Registering for push notifications…" suggests an APS issue.

No behavior change beyond the label. 59/59 tests still green.

### 2026-05-10 — Soft recovery from "client went away" CloudKit error

Found during the Phase 4 verification trial: every cross-device record change put the *receiver* into `Sync error: client went away` state immediately after the change was applied. The receive itself worked (record landed in local DB and UI), but the sync footer read "error" until the receiving app was quit and relaunched. "Sync now" did not clear it (a fresh `pull()` hit the same error).

Hypothesis: `cloudd` (the local CloudKit daemon) loses track of our process's `CKContainer` binding after a successful subscription delivery + fetch round-trip. App restart fixes it because the new process gets a fresh container.

Fix: in `CloudKitSyncService.pull()`'s catch block, detect the specific `client went away` error message, re-create the `CKContainer` reference (replicating what app-restart does without needing one), and retry the fetch operation once. Sticky-error path is preserved for any other error so we don't mask real CloudKit problems.

Note this is treating the symptom rather than the root cause — the deeper question of *why* cloudd is dropping our binding remains. Possible avenues if it returns: longer-lived CKDatabase reference, different operation queue, less Task hopping in the subscription handler. Logged in `HANDOFF.md`.

### 2026-05-10 — Phase 4 acceptance gate verified PASS (Mac→Mac sync near-instant)

The long-standing Phase 4 latency gate is closed. Two-Mac trial run (same Apple ID, same iCloud, both running v0.1.187+ from commit `e8e4439`):

- Changes made on either Mac appeared near-immediately on the other, both directions. Comfortably under the <5 s gate.
- The silent-push subscription path is doing what it's supposed to: APS wakes the receiver, `pull()` runs, the new UI-refresh hook (also shipped today) bumps the visible records list.

Two observations recorded for follow-up:

- **First-launch bootstrap on the new Mac hung at "Setting up sync…" for ~5 min** before self-resolving. Quit + relaunch didn't shortcut. Possible causes include first-time CloudKit container handshake for a new device, APS registration latency, or a silent initial-pull stage. Logged as new follow-up item #1 ("first-launch sync bootstrap UX") — the fix is per-step timeout-and-retry with surfaced sub-state in the status badge.
- **`Sync error: client went away`** flickered briefly on the dev Mac during the second Mac's bootstrap. Self-cleared after a "Sync now" click. Known transient CloudKit pattern (CKOperation deallocated mid-flight); no action.

`README.md` Phase 4 row upgraded from "acceptance infrastructure met, latency unverified" to "fully met."

### 2026-05-10 — UI refresh on remote object changes (prep for Phase 4 Mac→Mac verification)

Found-and-fixed before walking through the Phase 4 latency verification: when CloudKit pulls in remote changes, `applyRemote` writes directly to `DatabaseService` without going through `ObjectEngine`'s mutation hooks. As a result, the visible `RecordsScreen.rows` `@State` and `appState.objectCount` weren't refreshing — Mac B would receive a record into the local DB but it wouldn't appear in the UI until you switched types or restarted the app.

- New `AppState.objectsChangedRemotelyNotification`. Posted from `CloudKitSyncService.runFetchOperation` once per fetch batch (skipped on no-op pulls so we don't spin views for nothing).
- `AppState.init` observes → calls `reloadAll()` (bumps `objectCount`, propagates through `@Published` to Today's panels).
- `RecordsScreen` observes → calls `reload()` to re-fetch rows from the database.

Without this fix, the Phase 4 acceptance verification would have been deceptive (records sync, UI doesn't reflect it). 59/59 tests still green; build clean.

### 2026-05-10 — Schema editor polish: drag-from-palette + reorder fields

Final slice of the prototype-polish follow-up. The schema editor now matches `Design/purplelife/project/screens-dark.jsx ScreenSchema`'s drag-and-drop affordance, plus a missing reorder primitive.

- **Drag-from-palette → drop on field list**. Field-type tiles in the bottom palette are now `.draggable`; the field list is a `.dropDestination`. Dragging a tile onto the list calls the same `addField(kind:)` path that click-to-add does. Click-to-add still works for users who prefer it.
- **Tinted drag preview**. While dragging, the tile renders with the accent color and a 1 pt accent stroke so it reads as "active" — matches the prototype's drag-handle treatment.
- **Drop-zone hint** under short field lists (< 3 fields). Dashed-border placeholder with "Drag a field type here" disappears once the list is large enough to be an obvious drop target on its own.
- **Move up / Move down** menu items on each field row, backed by a new `SchemaRegistry.moveField(fieldId:onTypeId:by:)` helper. Goes through `upsertType` so it gets the same undo + sync treatment as any other schema mutation. Items are disabled at the array bounds. Full row-drag-to-reorder lands later — the menu items cover the immediate need without inventing per-row drop math.
- **`FieldKindTransfer`** — small `Transferable` payload carrying the `FieldKind.rawValue` as the drag content. In-process only; never serialized across process boundaries.

59/59 tests still green (no test changes — drag/drop is `View` modifier behavior, not testable without a UI test host; the new `moveField` helper is exercised indirectly through the existing schema undo tests since it goes through `upsertType`). Build clean.

### 2026-05-10 — Detail polish: two-pane object detail with "Linked from" inspector rail

Second slice of the prototype-polish follow-up. Object detail sheet now has a two-pane layout matching `Design/purplelife/project/screens-dark.jsx ScreenDetail`:

- **Hero block** at the top of the main pane — large rounded square with the type's icon tinted to its accent color, type name above the record's title (bold, larger). Replaces the old icon + type-name header.
- **Two-pane layout**: main pane (flex) + 320 px right inspector rail, separated by a divider. Both panes scroll independently inside the existing fixed-size sheet. Sheet minimum size bumped to 880 × 560.
- **"Linked from" rail** — the killer feature. Shows every record across every type whose `.link` fields point at the record being viewed. Grouped by source type, with a colored bullet keyed to the type's accent. Clicking a row dismisses the sheet and routes through `appState.openRecordRequest` so the main window's `RecordsScreen` opens the picked record. Empty-state copy when nothing links.
- **Created / updated stamps** at the bottom of the rail — the prototype shows a richer per-mutation history; PurpleLife doesn't keep that log yet, so we surface the stamps we have without inventing new persistence.
- **`ObjectEngine.recordsLinkingTo(recordId:schema:)`** — new helper. Cross-type scan: walks every record, checks every `.link` field, returns matches with their resolved type. O(N · F) over records and link fields. Personal-scale; an index can come later if it ever becomes slow.

**2 new `InboundLinksTests`** — finds-the-linker and empty-for-unreferenced. **59/59 tests green** (was 57, +2). Build clean.

### 2026-05-10 — Today polish: timeline + linked-from-today rail (matches prototype)

First slice of follow-up #2 (polish toward the prototype). The Today screen layout now matches `Design/purplelife/project/screens-light.jsx ScreenToday` more closely:

- **Two-column layout** — flexible main column + 320 px right rail, separated by a divider. Rail uses `Theme.sidebarOpaque.opacity(0.4)` as a background so it reads as a distinct surface against the main column.
- **Today timeline** at the top of the main column. Walks every record across every type, picks the type's `calendarDateKey` (or first date-bearing field), keeps anything whose value falls on today's calendar day, sorts chronologically. Renders each as time-on-left + colored dot + card with the type's icon + record title — same time/dot/connector visual as the prototype. Date-only records show "all day"; dateTime records show `h:mm a`. The whole section is omitted when nothing's scheduled.
- **Linked-from-today rail** — small cards driven by the existing seeded `SavedQuery` rows, looked up by name. Currently shows two cards: the first result of the "Currently reading" query and of the "Latest weight" query. Cards collapse silently if the query doesn't exist or returns nothing — no placeholder noise.
- **Header bumped** to `.title.bold` (was `.title2.semibold`) to match the prototype's heavier visual weight.

Phase 3 acceptance gate ("no hard-coded modules") still holds — the timeline is one cross-type scan over the data the engine already serves, and the rail looks up named saved queries. Adding a third rail card later is a one-line `railCard(forSavedQueryNamed:subtitle:)` call.

57/57 tests still green (no test changes — the new code is SwiftUI layout). Build clean.

### 2026-05-10 — Undo across mutations (NSUndoManager wired through ObjectEngine + SchemaRegistry)

Closes the undo half of the daily-use ergonomics work. ⌘Z and ⇧⌘Z now round-trip through every record and schema mutation.

- **`ObjectEngine.undoManager`** — static `UndoManager?` fed from SwiftUI's `@Environment(\.undoManager)`. `create` / `update` / `delete` each register an inverse handler. Undo of a `delete` goes through the new `restore(_:)` helper, which re-inserts at the original id (so any inbound `link` field references from other records survive).
- **`SchemaRegistry.undoManager`** — instance-level. Snapshot-based: each mutation captures the full `types` array + `hiddenBuiltInIds` set before applying the change; undo restores the snapshot. Coarse but bulletproof — the schema is small (a handful of types each ~KB), and snapshot/restore avoids per-mutation invariants we'd otherwise have to think about (renames vs adds vs option edits).
- **Action names** are set on every undo registration: "Create record" / "Edit record" / "Delete record" / "Edit schema" / "Delete type" / "Hide type" / "Show type" / "Restore schema". macOS surfaces these in the Edit menu as "Undo X".
- **Hidden-flag undo doesn't fan out to CloudKit.** `hiddenBuiltInIds` is per-device by design, so undoing a hide/show only flips the local set.
- **Schema undo bumps `updatedAt`** when fanning out — the user's undo wins LWW on this device's next push, which is the right semantics for "the user just took an explicit action."
- **Env undoManager wired in three places**: `ContentView.onAppear` (covers Today), `RecordsScreen.onAppear` (the type list windows), `SchemaEditorScreen.onAppear` (its own window). All three set both `ObjectEngine.undoManager` and `appState.schema.undoManager` so ⌘Z works regardless of which surface is focused.

**6 new `UndoTests`** covering the deterministic part:
- Create + undo removes the record; redo restores it at the original id with original fields.
- Update + undo restores prior fields.
- Delete + undo recreates at the original id with original fields.
- Schema upsert + undo restores the prior types array.
- Schema setHidden + undo restores visibility.

The cross-device behavior (an undo on Mac A propagating via the same sync paths to Mac B) is not unit-testable here — covered by the same Mac→Mac trial that's still queued for the Phase 4 acceptance gate. **57/57 tests green** (was 51, +6).

### 2026-05-10 — Daily-use ergonomics: menu-bar quick capture + ⌘N / ⌘1–⌘9 shortcuts

Closes the menu-bar + shortcuts halves of follow-up #2 (formerly "daily-use ergonomics — quick-capture menu bar item, keyboard shortcuts, undo"). Real `NSUndoManager` integration is still queued as a focused follow-up — it touches every mutation path in `ObjectEngine` and `SchemaRegistry` and merits its own commit.

- **`MenuBarExtra` quick capture** — small SF Symbol (`wand.and.sparkles`) in the system menu bar opens a compact popover (`QuickCaptureMenu.swift`): type picker, title field, ⌘↩ to save, Esc to close. Saves into the type's `primaryFieldKey` (or the first text-bearing field for types without a primary). Defaults the type picker to the last one used (`UserDefaults: PurpleLife.quickCapture.lastTypeId`); falls back to the first visible type. After save, shows a brief green "Saved to <type>" status under the field and clears the title for the next entry — supports rapid repeat capture.
- **⌘N — File → New record** — replaces SwiftUI's default "New Window" command (we use a single `WindowGroup`; a second window isn't useful). Posts `AppState.newRecordRequestedNotification`; `RecordsScreen` observes and creates a new record of its currently-displayed type, opening the detail sheet so the user can fill in fields immediately. No-op when the Today panel is selected (no type to create against).
- **⌘1 … ⌘9 — Window → Jump to type N** — bound to a fixed set of 9 menu commands. Each posts `AppState.jumpToTypeIndexNotification` with a 1-based index; `AppState` resolves the index against `schema.visibleTypes` and flips `selectedTypeId`. Out-of-range indices (fewer than N visible types) are no-ops. Labels in the Window menu are intentionally generic ("Jump to type 1" etc.) — making them reactive to the actual type names would have required threading AppState into the App-scope Commands block, which is more refactor than the affordance is worth. The shortcut itself is the value.

51/51 tests still green — no test changes (the new code is App-scene wiring + a SwiftUI popover view, neither testable without a UI test host). Build clean.

### 2026-05-10 — Schema versioning across synced peers

Closes follow-up #3. Two prongs of fix so multi-Mac sync doesn't lose data when peers run different schema versions:

**Schema mirroring through CloudKit.** New `PurpleType` record type in the same custom zone. Same shape as `PurpleObject` records: plaintext `updated_at` for server-side LWW, full serialized `ObjectType` (including fields, view defaults, the lot) in `encryptedValues.typeJSON`. `SchemaRegistry.upsertType` / `deleteType` now push to CloudKit; `CloudKitSyncService.runFetchOperation` partitions buffered changes by record type and applies **schemas before objects**, so an arriving record always finds its type already there. `CKDatabaseSubscription` was already a database-level subscription, so silent push wakes both halves with no new APNS plumbing.

- **`ObjectType.updatedAt`** — new optional ISO-8601 stamp. `SchemaRegistry.load` backfills the epoch (`1970-01-01T00:00:00Z`) for pre-schema-sync types so they sort "older than anything" and the first remote update wins LWW. Built-ins also carry the epoch on construction; `SchemaRegistry.upsertType` stamps `now` on every mutation.
- **`SchemaRegistry.applyRemote(_:)`** — LWW per-type. Only overrides the local copy if the remote stamp beats it. `applyRemoteDelete(typeId:)` mirrors `pushDeleteType`; refuses to remove built-ins defensively.
- **`pushPendingLocalSchemas()`** — bootstrap analog of `pushPendingLocalChanges()`. Pushes any local types whose `updatedAt` is ahead of the server. Runs first in the bootstrap sequence so peers' types arrive before their records.
- **Hidden-flag stays per-device.** `SchemaRegistry.hiddenBuiltInIds` is not synced — different Macs may want different types visible in the sidebar.

**Defensive merge in `ObjectEngine.update`.** Even with schema sync, there's a window between a record arriving on a peer and that peer learning about the new field. If the user edits the same record locally during that window, the form only knows about the local schema's keys — the unknown remote field would have been silently dropped. The fix: `update` now reads the existing JSON, then overlays the incoming fields. Keys absent from the incoming dict are preserved. Same intent as `SchemaRegistry.removeField` leaving orphan data in records ("the field's data is left in place — old keys are just unreferenced").

**5 new `SchemaVersioningTests`**:
- `testUpdatePreservesUnknownFieldsFromExistingRecord` — defensive merge keeps the "field a peer added later" intact across a local update.
- `testUpdateAllowsExplicitlyClearingKnownFields` — empty-string values in the incoming dict still replace prior values; merge doesn't accidentally resurrect cleared fields.
- `testBuiltInTypesCarryEpochUpdatedAt` — backfill default.
- `testUpsertStampsUpdatedAt` — every mutation bumps past the epoch.
- `testApplyRemoteWinsOnlyWhenStampIsNewer` — older remote ignored, newer remote replaces local.

**51/51 tests green** (was 46, +5). Build clean.

### 2026-05-10 — Bug: Settings → Backup → Test gives no visible feedback

The Test button on each backup row called `BackupService.verifyArchive` synchronously and wrote the result into a `Section("Last test result")` rendered _below_ the "Recent backups" list. Two failure modes:

- The verify call blocked the main thread for the duration of the zip extract + sqlite open, so the spinner never got a chance to animate and the UI froze briefly with no indication anything was happening.
- When the Recent backups list was long enough to push the result section below the visible area, the section appeared but the user couldn't see it without scrolling — looked exactly like the button did nothing.

Fix:

- Per-row inline feedback. While verify is running, a `ProgressView` appears next to the row's Test button (and Test/Restore are disabled to prevent double-clicks). When verify completes, a green `Verified — N objects · M files · Z bytes · K migrations` line appears under the row; on failure, a red `Test failed: …` line in the same place.
- Verify call moved off the main thread via `Task.detached(priority: .userInitiated)`. Result lands back on the main actor.
- Removed the bottom "Last test result" / "Test failed" sections — the per-row inline feedback supersedes them; no need for two sources of truth.

### 2026-05-10 — Per-type export pipeline (CSV / Markdown / HTML / PDF + clipboard)

Closes follow-up #2. The Records screen now has an Export menu next to "New X"; clicking it writes a stamped file to the resolved export directory or copies the formatted text to the clipboard.

- **`ExportService.swift`** — pure formatters for CSV, Markdown, and HTML (no `@MainActor`, deterministic, take resolver closures for link titles + attachment labels). PDF uses the same WKWebView-based `HTML → pdf()` pipeline as `Timeliner.ExportService.exportCaseAsPDF`. CSV is RFC-4180 (commas / quotes / newlines escaped); Markdown escapes pipes and newlines; HTML escapes the standard entity set.
- **Cell rendering** handles every `FieldKind`: text/longText/url/email pass through; number trims trailing `.0` for whole values and avoids scientific notation; date/dateTime emit the stored ISO-8601; boolean → `true`/`false`; select/multi-select resolve option ids to display names (multi-select joined by `|`); link resolves the target id to the linked record's title (falls back to the raw id); rating to integer string; attachment to the resolver-provided filename (falls back to sha256). Missing fields render as empty cells.
- **`RecordsScreen` toolbar** — new `Menu` with "Save to file" submenu (CSV / Markdown / HTML / PDF) and "Copy to clipboard" submenu (CSV / Markdown). Disabled when the type has no records or an export is already in flight. After a file save, `NSWorkspace.activateFileViewerSelecting` opens the destination folder with the new file selected.
- **Settings → Export tab** (new) — text field + Choose… picker for the default export directory, "Reveal" button (creates the dir on demand), resolved-path readout. Default: `~/Downloads/PurpleLife/` per the PhantomLives convention. Override persists in `settings.json` via the existing `defaultExportDirectory` key (which was already declared in `AppSettings` but had no UI).
- **10 new `ExportServiceTests`** — header shape, RFC-4180 escaping (commas / quotes / newlines), link-title resolution, multi-select pipe-join, attachment-label fallback, rating + boolean cell rendering, missing-field handling, Markdown table shape + pipe-escape, HTML entity escape + table presence, helper-level `csvEscape` cases. **46/46 tests green** (was 36, +10).
- **Deferred**: per-record export (today only per-type lists), and `Today` panel exports.

### 2026-05-10 — Real-time CloudKit sync via silent-push subscriptions

Closes the Phase 4 follow-up "real-time CloudKit subscriptions": Mac→Mac sync no longer waits for the foreground poll, it wakes immediately when another device writes. Demotes the poll to a 5 min recovery sweep.

- **`AppDelegate.swift`** — new minimal `NSApplicationDelegate` attached via `@NSApplicationDelegateAdaptor` in `PurpleLifeApp`. Calls `NSApplication.shared.registerForRemoteNotifications()` on launch, parses incoming `application(_:didReceiveRemoteNotification:)` payloads through `CKNotification(fromRemoteNotificationDictionary:)`, and posts a `NotificationCenter` event so the sync service can react without a direct reference (init-ordering safe).
- **`CloudKitSyncService.ensureSubscription()`** — registers a single `CKDatabaseSubscription` (id `PurpleLife.databaseSubscription`) in `bootstrap()` after `ensureZone()`. `notificationInfo.shouldSendContentAvailable = true` keeps it silent (no UI, no user permission needed). A UserDefaults flag prevents the save round-trip on subsequent launches; `serverRejectedRequest` (already exists) is treated as success and remembered. Failures fall back to the recovery poll without blocking bootstrap.
- **`CloudKitSyncService.handleSubscriptionNotification(userInfo:)`** — observes the AppDelegate's NotificationCenter event, validates the payload is a CK push for our subscription id (defensive guard against unrelated APNS noise lighting up the container), and triggers an immediate `pull()`.
- **Recovery poll bumped from 30 s to 5 min** — subscriptions are the primary trigger now; the poll only catches up if a silent push was dropped (offline, sleep, APNS hiccup). 5 min keeps the worst-case lag bounded without burning cycles when push is doing its job.
- **Entitlements** — `PurpleLife.entitlements` adds `com.apple.developer.aps-environment` = `development`. Note: macOS uses the long key form; the iOS short form `aps-environment` is silently stripped by Xcode's `ProcessProductPackaging` step on macOS targets. The `PurpleLife-NoCloud.entitlements` test override stays empty (tests don't need push).
- **Apple-side setup** required once per developer account: enable Push Notifications capability on App ID `com.bronty13.PurpleLife` at developer.apple.com → Identifiers. Signing fails with a misleading "device isn't registered" error until this is done. Documented in `HANDOFF.md` § "Phase 4 sync: subscriptions landed".
- **2 new `CloudKitSubscriptionTests`** covering the deterministic part of the parser (empty / non-CK payloads are rejected). The positive path — a real APNS push triggers `pull()` — needs a real Mac→Mac round-trip to verify and is part of the Phase 4 acceptance gate. **36/36 tests green**.

### 2026-05-10 — Test infrastructure regression resolved

- `./run-tests.sh` runs end-to-end again. Full bundle (now **34 tests**) green in ~19 s; Timeliner's bundle (26 tests) likewise. No code or script change — the host appears to have recovered between sessions (reboot or Xcode/macOS update).
- The iCloud-entitlement-induces-test-hang workaround in `run-tests.sh` (`CODE_SIGN_ENTITLEMENTS=Sources/PurpleLife/App/PurpleLife-NoCloud.entitlements`) stays in place; whether it's still load-bearing wasn't tested. See `HANDOFF.md` § "Test infrastructure regression: no longer reproduces" for the full note.
- README and HANDOFF updated to drop the "blocked by an environmental hang" caveat next to the test command and close item #2 on the follow-up list.

### 2026-05-10 — Theme + visual pass against the design handoff

- **`Theme.swift`** — palette pulled out of `Design/purplelife/project/chrome.jsx` (`PE_LIGHT` / `PE_DARK`). Surfaces (`bg`, `card`, `sidebarOpaque`), text tiers (`text` / `textDim` / `textFaint`), lines (`cardBorder` 6 % black/white, `hairline` 7 %, `rowHover` 4–5 %), accent (`oklch(0.56 0.14 295)` → sRGB ~#8B65C1 light, brighter in dark). All values are sRGB approximations of the prototype's oklch — SwiftUI's `Color` doesn't take oklch directly.
- **Today panels** now sit on `Theme.card` with a `0.5px Theme.cardBorder` stroke — matches the design's white-card-on-cream / dark-card-on-warm-near-black surfaces. Inner result cards switch from `Color.primary.opacity(0.04)` to `Theme.bg.opacity(0.6)` so they read clearly against the panel.
- **Kanban cards** use the same card chrome.
- **Table view** column headers swap `secondary` for `Theme.textFaint` (no opacity tricks), alternating rows use `Theme.rowHover`, dividers are explicit 0.5 px `Theme.hairline` rectangles instead of system dividers.
- **Schema editor** field-type palette tiles switch to `Theme.card` with `Theme.cardBorder`; field-row separators use `Theme.hairline`; bottom palette tray uses `Theme.bg.opacity(0.6)` so it reads as a distinct surface.

### 2026-05-10 — Real attachments + WeightTracker CSV import

- **`AttachmentService`** — content-addressed local file storage. Adds files from any source URL into `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`. Same content referenced by multiple object/field pairs de-duplicates on disk; deleting a row only prunes the file when the last ref is gone. Cascading FK deletes on the `objects` table drop attachment rows automatically.
- **`AttachmentFieldEditor`** — `Detail.swift` `.attachment` editor is no longer a placeholder. Pick file → file copied into the store, the field's value becomes the sha256, real thumbnail renders inline with dimensions / size / Reveal button.
- **Gallery view** loads real images — `imageOrPlaceholder(for:)` reads the type's `galleryAttachmentKey` field, resolves the sha256 to a file URL via `AttachmentService`, displays the actual image. Falls back to the type-tinted gradient stand-in for records without an attachment (or whose attachment hasn't been downloaded yet — placeholder for the future CKAsset sync).
- **`WeightCSVImporter`** — Settings → Import tab. Parses WeightTracker's CSV export (header autodetects lb vs kg, converts kg → pounds), creates Weight records with `source = Imported`. Quoted fields with embedded commas and doubled-quote escapes parse correctly. Per-row errors are listed in the import report without aborting the run.
- **5 new `AttachmentServiceTests`** + **5 new `WeightCSVImporterTests`** covering hash determinism, dedup on add, ref-counted delete, cascade-on-parent-delete, lb/kg conversion, embedded-comma row parsing, error tolerance.
- Phase 5 acceptance gate ("real workflow migrated for ≥2 weeks") is yours to run — the migration infrastructure (CSV import + working attachments + the full Phase 2/3 UI) is in place. The remaining work is daily use.

## Unreleased — Phase 4 starter (0.1.x)

### 2026-05-10 — CloudKit E2E sync (Mac→Mac via private database)

- **`CloudKitSyncService`** — pushes every `ObjectEngine.create / update / delete` to the user's private CloudKit database in a custom zone (`PurpleLifeZone`). Uses `CKRecord.encryptedValues["fieldsJSON"]` for the JSON blob (the same shape the spike PASSed on 2026-05-10) and plaintext slots for `type_id` / `parent_id` / `created_at` / `updated_at` so server-side comparisons can read them. Conflict resolution is **last-write-wins by `updated_at`** — same-field offline edits on two Macs reconcile deterministically when they reconnect.
- **Initial pull + 30s poll** — on launch, the service checks the iCloud account, ensures the custom zone exists, runs `CKFetchRecordZoneChangesOperation` from the saved server change token (resumes incrementally across launches), pushes any local-only rows whose `updated_at` is ahead of the server. Then a 30 s poll keeps things fresh while the app is in the foreground. Real-time silent-push subscriptions (`CKDatabaseSubscription` + `aps-environment`) are queued for follow-up.
- **Graceful degradation** — if the iCloud account is missing, the entitlement is absent, or the container can't be opened, the service transitions to `.disabled` / `.notSignedIn` and the app stays fully usable as a local-only Life OS. No CloudKit failure can stop launch.
- **Sync status footer** in the sidebar — icon + label live-bound to `CloudKitSyncService.status` (idle / syncing / setting up / error / sign in / off), plus a "Sync now" refresh button. Color cues: green for idle, accent for syncing, red for error.
- **Entitlements** — `Sources/PurpleLife/App/PurpleLife.entitlements` now declares `com.apple.developer.icloud-container-identifiers` + `com.apple.developer.icloud-services` for `iCloud.com.bronty13.PurpleLife` (the same container the spike validated). `project.yml` carries `DEVELOPMENT_TEAM=SRKV8T38CD` so signing is non-interactive.
- **Build script switched to Debug + Apple Development signing** — Phase 4 needs the iCloud entitlement embedded in a development provisioning profile. The previous Developer-ID-Application post-sign step has been removed; xcodebuild now signs the `.app` with the dev profile that carries the iCloud capability + container assignment, fetched via `-allowProvisioningUpdates`. Personal-use multi-Mac install is unchanged; only distribution-style signing is affected (we don't distribute outside the team).
- **Lazy `CKContainer` construction** — the framework traps when constructed without the iCloud entitlement, which made `AppState` crash under any signing config that lacked it (e.g. test runs with the no-iCloud override). Container is now allocated inside `bootstrap()` so the local-only path stays viable.
- **Test entitlements override** — `run-tests.sh` passes `CODE_SIGN_ENTITLEMENTS=Sources/PurpleLife/App/PurpleLife-NoCloud.entitlements` so the host under test doesn't carry the iCloud entitlement. Reason: a host with iCloud entitlement plus the XCTest test runner combination causes the runner IPC to never establish (5-minute timeout, then "test runner hung before establishing connection"). The override is test-only; production builds keep the full entitlement. Note: a separate environmental issue is currently making `xcodebuild test` fail on this Mac for both PurpleLife and Timeliner; investigation queued. The Phase 4 functional code (lazy CKContainer, push/pull, LWW, sync footer) builds and runs correctly via `./build-app.sh`.

## Unreleased — Phase 3 starter (0.1.x)

### 2026-05-10 — Saved-query customization UI + Planner Item / Weight types

- **`Planner Item`** + **`Weight`** added to `SchemaSeed.allTypes` so the Phase 3 acceptance gate (planner items + weight + currently-reading book) has real types to query against. Planner Item: title / date / status (Pending/Doing/Done/Cancelled) / project / notes. Weight: date / pounds / body-fat % / source / notes.
- **`SavedQuerySeed.allDefaults`** updated: "Today's planner" (PlannerItem where Status=Pending, sort by date asc) and "Latest weight" (Weight, sort by date desc, limit 1) added at the top of the Today panel list.
- **`SavedQueriesEditor`** sheet — accessed from the Today toolbar's "Edit panels" button. Lists every panel with reorder (drag handles), inline edit / delete buttons, an Add panel CTA, and a "Restore defaults" button that re-adds any built-in defaults the user has previously deleted (without duplicating ones still present).
- **`SavedQueryEditor`** sheet — schema-aware form: type picker (All / each visible type), filter picker (No filter / Field equals / Updated within N days / Field is set), field pickers scoped to the selected type's fields, sort field + descending toggle, limit stepper (1–100), icon picker from a curated SF Symbols set. Edits are live-validated (field-equals filter without a type warns inline; Save disabled when name is empty).
- **`QueryRunnerTests`** — 5 tests covering type filter + limit, field-equals filter, withinDays cutoff against `updated_at`, sort asc / desc by field, cross-type cross-everything. **24/24 tests green**.

### 2026-05-10 — Today screen + saved-queries pattern

- **`SavedQuery`** model — serializable filter spec (typeId / field-equals / withinDays / nonEmpty / sort / limit). Persisted in `AppSettings.todayQueries`. `todayQueriesSeeded` is a one-shot flag so a deleted default never gets re-added.
- **`QueryRunner`** — single-pass executor. Fetches the candidate set (per-type or across all), filters in Swift, sorts by the requested field key (defaults to `updated_at` desc), trims to the limit. Pairs each row with its resolved `ObjectType` so the renderer doesn't have to look it up.
- **`SavedQuerySeed.allDefaults`** — installed on first launch: "Currently reading" (Book where status=Reading), "Recent people", "Recent across everything" (cross-type), "Updated in the last 7 days" (cross-type, 7-day rolling window).
- **`TodayScreen`** — one generic `QueryPanel` repeated over the saved-query list. Phase 3 acceptance gate satisfied: no hard-coded modules in the view, all panels are data-driven. Each panel header shows the count + a "See all" shortcut to the type's detail pane when scoped. Cards render the type icon/badge, primary title, and up to 2 supporting fields via shared `FieldDisplay` renderers. Double-click opens the detail sheet.
- **Sidebar** — new "Today" section above Types; selecting it routes the detail pane to `TodayScreen`. Default selection on first launch is Today (was the first type).
- Customization UI for saved queries (add / edit / delete / reorder) is the next chunk; the underlying model and persistence are in.

## Unreleased — Phase 2 starter (0.1.x)

### 2026-05-10 — Cross-type link picker + linked-title resolution

- **`LinkFieldEditor`** — popover record picker for `.link` fields. Replaces the plain TextField that the starter shipped. Lists every record across every type, grouped by type with sticky type headers, search-as-you-type filter on title or type name, click to select, "Clear link" footer when a value is set. Keeps the field's stored value as the linked record's id (UUID string), so cross-references survive renames.
- **`ObjectEngine.resolveLinkedTitle(recordId:)`** + **`allWithTypes(schema:)`** helpers used by the picker and the read-only renderers.
- **`FieldDisplay.cell`** for `.link` now resolves the id to the linked record's title with a chain icon. Unresolvable values (legacy free-text or deleted records) render in italic with a fallback `link.badge.questionmark` glyph instead of silently looking like real titles.
- Phase 2 acceptance gate now fully met for cross-type links: a Photo Shoot can pick a Camera; a Photo can pick its Shoot. Both render the linked record's title in the table / kanban / detail views.

### 2026-05-10 — Four list views + FTS5 search + Quick Switcher

- **View-kind picker** in the records-screen toolbar — switches between Table / Kanban / Calendar / Gallery for the selected type. Hidden views auto-omit per-type when the type's schema can't support them (no select field → no Kanban tab; no date field → no Calendar tab; no attachment field → no Gallery tab).
- **Kanban** — columns derived from a select field (defaults to `type.kanbanGroupKey` and falls back to the first select field). Each column is colored by the option's `colorHex`. Cards show the primary field + up to 3 supporting fields. Records whose value isn't one of the defined options collect into an "—" column.
- **Calendar** — month grid with prev/next/today controls; records placed by `type.calendarDateKey` (falls back to the first date / dateTime field). Cells show up to 3 record titles + an overflow count, double-click opens detail.
- **Gallery** — adaptive `LazyVGrid` of cards with a placeholder gradient keyed to the type's accent color (the real attachment loader is queued for the AttachmentService work; the layout is fully exercised). Rating badge overlays when the type has a rating field.
- **`FieldDisplay`** — read-only field renderers extracted out of the table body so kanban / calendar / gallery share them, keeps cell rendering uniform across views.
- **FTS5 search** — `objects_fts` virtual table (porter tokenizer) added in `v3_fts5` migration. `SearchService.reindexAll(schema:)` rebuilds from `objects` on every launch. `ObjectEngine.create / update / delete` keep the index incrementally up to date. Title is the primary field's value; body concatenates all text-bearing field values.
- **⌘K Quick Switcher** — floating window with live FTS5 results across every type. Arrow-key navigation, Enter opens the picked record (sets `selectedTypeId` and routes through the main window's detail sheet via `appState.openRecordRequest`), Esc dismisses.
- 4 new `SearchServiceTests` (cross-type query, reindex from disk, empty query → empty, delete-removes-from-index). Total: **19/19 green**.

### 2026-05-10 — Object detail + schema editor + table polish

- **Object detail sheet** — double-click any row opens a `Form`-style editor with one input per `FieldKind`. `text` / `url` / `email` / `link` use `TextField`; `longText` uses `TextEditor`; `number` is a numeric `TextField`; `date` and `dateTime` are native `DatePicker`s; `boolean` is a `Toggle`; `select` is a `Picker`; `multiSelect` is a wrapping chip cluster (custom `Layout`); `rating` is 5 toggleable stars; `attachment` is a placeholder until `AttachmentService` lands. Saves on Done. Right-click a row gives Open / Delete.
- **Schema editor** (⇧⌘S, also in the Window menu) — split view with a types rail (built-in/custom badge, hidden indicator, hide-from-sidebar / delete-custom-type context menu), the selected type's field list (rename / mark required / delete per field), and a field-type palette at the bottom — click any of the 12 kinds to add a field of that kind to the current type. Auto-renames duplicates (`New text 2`, `New text 3`, …).
- **Table view polish** — table body anchored at the top of its ScrollView (was bottom-pinned because of the missing maxHeight on the inner VStack); empty primary fields render "*Untitled*" in italic tertiary text, all other empty cells render "—" in tertiary text; column headers are uppercased + tracked; alternating row backgrounds at 4% secondary; row dividers bumped from 0.4 → 0.6 opacity; row creation now opens the detail sheet for the new record so the user fills in fields immediately rather than landing on a blank row.

### 2026-05-10 — Phase 2 data layer + sidebar + table

- Design handoff (`~/Downloads/PurpleLife-handoff.zip`) unpacked into `Design/`; `Design/MANIFEST.md` maps the 10 prototype screens to the SwiftUI files that will implement them. The JSX/HTML source is gitignored (large), the manifest is committed.
- Attachments storage decided in `HANDOFF.md`: content-addressed files at `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`, `attachments` table for metadata, CloudKit sync via `CKAsset` deferred to Phase 4.
- Models: `FieldDef` (12 field kinds incl. text, select, link, attachment, rating), `ObjectType` (with primary/kanban/calendar/gallery key hints), `Attachment` row.
- `SchemaSeed`: built-in types Person, Book, Camera, Photo Shoot, WoW Character, Photo. Each carries the example fields shown in the design's table/kanban/calendar/gallery screens.
- `SchemaRegistry` service: persists to `schema.json`, loads on launch, merges in newly-added built-ins on upgrade, supports user-add / user-edit / user-delete + hide-built-in.
- DB migration `v2_attachments`: id / parent_object_id / field_key / sha256 / filename / mime_type / size_bytes / created_at, indexed on parent + sha256.
- Views: replaced the Phase 1 placeholder `ContentView` with a `NavigationSplitView`. New `Sidebar` lists visible types with per-type record counts; new `TableViewScreen` renders any type's records as a horizontally-scrollable column grid (`Table` couldn't take dynamic columns at runtime).
- Tests: 6 new `SchemaRegistryTests` (seed, hide-not-delete-built-ins, refuse-delete-built-ins, upsert, field mutations, reload-from-disk). Total: **15/15 green**.

## Unreleased — Phase 1 scaffold (0.1.x)

### 2026-05-10 — CloudKit spike PASS

- Spike ran successfully against `iCloud.com.bronty13.PurpleLife` after attaching the container to the App ID via Configure (the registration-time iCloud capability tick is not enough — a separate save is needed).
- `Spike/CloudKit/build-spike.sh` now passes `-allowProvisioningUpdates`; `Spike/CloudKit/project.yml` carries `DEVELOPMENT_TEAM=SRKV8T38CD` so subsequent builds are non-interactive.
- `Spike/CloudKit/SPIKE.md` § Run log + Decision filled in; `HANDOFF.md` flipped from "scaffolded, run pending" to PASS; `PLAN.md` § Locked decisions encryption row annotated with the confirmation pointer.

### Added

- Refined `PLAN.md` synced from the planning branch, with Phase 0 marked **skipped** and the CloudKit spike moved ahead of Phase 1.
- `HANDOFF.md` decision log; Phase 0 skip + project-name lock recorded as the first two entries.
- Application icon (`PL•` purple gradient squircle) generated by `Scripts/generate-icon.swift`. Matches the Purple\* family treatment.
- CloudKit spike app (`Spike/CloudKit/`) with `encryptedValues` round-trip — compiles clean against Xcode 26.4.1; running it requires the user's iCloud + container provisioning. See `Spike/CloudKit/SPIKE.md`.
- XcodeGen `project.yml` (single app target + test bundle), `build-app.sh`, `run-tests.sh` cloned from Timeliner.
- Source skeleton: `App/`, `Models/`, `Services/`, `Views/`, `Resources/`.
- `DatabaseService` — GRDB pool + `v1_objects` migration (id, type_id, parent_id, fields_json, created_at, updated_at + indexes on type/parent/updated_at).
- `ObjectRecord` model + `ObjectEngine` thin facade for CRUD over `objects`.
- `BackupService` cloned from Timeliner — auto-backup-on-launch with debounce, retention trim, list ordering, archive verify, and destructive restore. Archive prefix: `PurpleLife-`.
- Phase 1 acceptance test (`BackupRoundtripTests.testRoundtrip100Objects`): seeds 100 objects → archives → wipes the support dir → restores → confirms every id survives.
- Four required backup tests (`debounce`, `retention trim` on `PurpleLife-` prefix, `target-directory auto-create`, `list ordering` newest-first) pass.

- **Settings → Backup pane** wired to the existing service primitives:
  toggle for `autoBackupEnabled`, dir picker with resolved path in
  monospaced caption, retention stepper, "Run backup now" button,
  "Recent backups" list with Test / Restore (with mandatory pre-restore
  safety backup) / Reveal in Finder, last-backup timestamp readout, and
  a "Last test result" section showing object count + migrations from
  the verified archive.
- `AppState.reloadAll()` and a `settings` pass-through binding so views
  can write `appState.settings.foo = …` and persist atomically.

### Known gaps for the rest of Phase 1

- ContentView is a placeholder. The real screens land in Phase 2 from `~/Downloads/PurpleLife-handoff.zip`.
