# PurpleLife — HANDOFF

The durable log of decisions and design-handoff deviations for PurpleLife. Append-only; do not rewrite history. Newest entries at the top.

## How to use this file

- **Decisions**: every locked decision that overrides or amends `PLAN.md` is recorded here with a date and one-line rationale.
- **Design deviations**: any deliberate divergence from `~/Downloads/PurpleLife-handoff.zip` (the visual design source of truth) is recorded here with a one-line reason, per the process in `PLAN.md` § Design source of truth.
- **Format**: `### YYYY-MM-DD — Title` heading, then a short paragraph or bullet list. Reference the relevant section of `PLAN.md` when applicable.

---

## Decisions

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

1. ~~**Real-time CloudKit subscriptions**~~ — resolved 2026-05-10; see "Phase 4 sync: subscriptions landed" entry above. CKDatabaseSubscription is registered in `bootstrap()`; AppDelegate forwards pushes via NotificationCenter; poll is a 5 min recovery sweep now.
2. ~~**Test infrastructure regression**~~ — resolved 2026-05-10; see entry above. `./run-tests.sh` runs the full bundle (now 46 tests) green in ~17 s.
3. ~~**Export pipeline**~~ — resolved 2026-05-10; see "Per-type export pipeline shipped" entry above. Records → Export menu writes CSV / Markdown / HTML / PDF or copies CSV / Markdown to clipboard.
4. ~~**Schema versioning across synced peers**~~ — resolved 2026-05-10; see "Schema versioning: mirror schema through CloudKit + defensive merge" entry above. PurpleType records sync the schema; ObjectEngine.update preserves unknown JSON keys.
5. **Polish toward the prototype** — Today timeline + linked-from rail, two-pane object detail, drag-and-drop schema editor.
6. ~~**Daily-use ergonomics**~~ — partially resolved 2026-05-10 (menu-bar quick capture + ⌘N + ⌘1–⌘9 shortcuts); undo split out into its own follow-up item.
7. ~~**Undo across mutations**~~ — resolved 2026-05-10; see "Undo: NSUndoManager wired through ObjectEngine + SchemaRegistry" entry above. ⌘Z / ⇧⌘Z route through every mutation path; tests cover create/update/delete + schema operations.

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
