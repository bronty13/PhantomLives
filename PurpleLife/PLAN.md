# Personal ERP — Refined Plan

## Context

Refinement of `~/Downloads/personal-erp-plan.md` — a native macOS "Life OS" for tracking planner, hobbies (WoW, photography), contacts, health, and reading. This document keeps the original's good bones (native + CloudKit + object model + Tap Forms trial) and addresses the gaps that would bite in week 2–3.

Two locked decisions going into this refinement:
- **E2E encryption with a key the user controls is required** (not Apple-managed-only)
- A design exercise in claude.ai/design runs in parallel with build planning

## What carries over unchanged

- Tap Forms-first trial before committing code
- Native macOS, Swift / SwiftUI, SQLite, CloudKit for sync
- Object-based data model: configurable types, custom fields, relations, multiple views (table, kanban, calendar, gallery)
- Daily timestamped backups in restorable format
- No Obsidian (with one caveat — see "tools to revisit")

## Refinements

### 1. E2E encryption — the original plan undercounts the work

The original implies "SQLCipher locally + CloudKit sync" gives end-to-end encryption. It doesn't. Standard `CKRecord` fields are encrypted by Apple in transit and at rest, but **Apple holds the keys**. For E2E with keys you control, three options:

| Approach | Trust model | Cost |
|---|---|---|
| CloudKit `encryptedValues` (per-field) | True E2E. Apple cannot decrypt. Key custody anchored in iCloud Keychain trust circle, not Apple's servers. | Low. Native API since macOS 12. |
| Client-side AES-GCM with your own key | You physically hold the key in Keychain. Maximum control. Apple has zero access even theoretically. | High. You re-implement key custody, rotation, escrow, multi-device recovery. CloudKit indexes unusable on encrypted fields → all queries become local. +2–3 weeks. |
| Hybrid (queryable fields plaintext, sensitive fields client-encrypted) | Mixed | Most complexity; classify every field |

**Recommendation given "user controls the key" requirement:**

Start with **`encryptedValues`**. Its trust model genuinely matches "Apple can't read my data" — the keys exist only inside the user's iCloud Keychain trust circle, not on Apple's servers. The literal interpretation of "key I physically hold" (option 2) buys very little additional security against any realistic threat model and costs weeks. If after a real evaluation you still want option 2, the JSON-blob storage shape (next section) makes the migration mechanical.

**Action before week 1:** Decide `encryptedValues` vs. custom AES. They produce different schemas and sync code.

### 2. Dynamic schema is the hardest part — and it was hidden in "weeks 3–4"

"Add fields anytime to any type" = runtime schema. SwiftData and Core Data are compile-time-modeled and don't fit this cleanly.

**Recommended storage shape:** single `Object` table with a JSON `fields` column.
- Plays well with `encryptedValues` (one encrypted blob per object)
- Indexed metadata columns: `type_id`, `created_at`, `updated_at`, `parent_id`
- Use **GRDB** rather than SwiftData (SwiftData's compile-time model assumption is the wrong shape for this app)
- Lift specific fields out of JSON to typed columns only when a query becomes slow

EAV (entity-attribute-value) is more "pure" but punishes sync and queries; skip it.

### 3. iOS from day one, even if you don't ship it for a year

CloudKit container ID, schema, and module boundaries are painful to retrofit. Mitigation:
- All non-UI code lives in a Swift Package called `Core` (storage, sync, crypto, object engine, backup)
- Mac app and (eventual) iOS app both import `Core`
- No `AppKit` / `UIKit` imports inside `Core`

Cost: ~2 days in week 1. Savings: weeks later.

### 4. Backup-restore moves to phase 1

The original plan acknowledges "test restore before trusting data" but lands restore in week 6. Flip it: implement export + automated restore round-trip *as the phase 1 acceptance test*. No data goes in until restore is proven.

### 5. Tools to revisit before writing code

Original list: Tap Forms, Ninox, Trilium, Anytype. Add:
- **Capacities** — Notion-like with first-class object types; the closest philosophical match
- **Obsidian Bases** (shipped late 2025) — gives Obsidian a database layer; mildly reopens the "no Obsidian" call
- **NotePlan** — same daily-planner-as-front-door hypothesis

30 minutes each. Cheap insurance.

## Revised build phases

| Phase | Original | Revised | Notes |
|---|---|---|---|
| 1. Foundation | weeks 1–2 | **weeks 1–3** | + `Core` package, CloudKit container, encryption decision, backup-restore loop |
| 2. Object engine + 4 views | weeks 3–4 | **weeks 4–7** | Dynamic schema + 4 view types is its own subproject |
| 3. Planner | week 5 | **weeks 8–9** | |
| 4. CloudKit E2E sync + conflict resolution | week 6 | **weeks 10–11** | |
| 5. First real use cases | week 7+ | **week 12+** | |

Realistic budget to "real use": ~3 months of personal-project time, not ~7 weeks.

## Sketch of repo structure

```
PersonalERP/
  Core/                            # Swift package, platform-agnostic
    Sources/Core/
      Storage/                     # GRDB, schema, migrations
      Object/                      # types, fields, relations
      Sync/                        # CloudKit mirror
      Crypto/                      # encryptedValues wrapper
      Backup/                      # export + restore
  Mac/                             # macOS app target
    Views/
      Today.swift, Sidebar.swift, TableView.swift,
      KanbanView.swift, CalendarView.swift, GalleryView.swift,
      Detail.swift, SchemaEditor.swift, QuickSwitcher.swift, Settings.swift
  Tests/CoreTests/
    BackupRestoreRoundtripTests.swift   # phase 1 gate
    SyncRoundtripTests.swift            # phase 4 gate
```

## Phase acceptance tests

- **Phase 1:** create 100 random objects → force-quit → restart, all present. Backup → wipe → restore, identical. Sync to second Mac, identical.
- **Phase 2:** define Person, Book, Camera; instances render in table, kanban, calendar, gallery; cross-type links work; search returns across all three.
- **Phase 3:** Today view pulls planner items, current weight entry, currently-reading book from the object engine (no hard-coded modules).
- **Phase 4:** typical edit syncs Mac→Mac in <5s. Conflict test: edit same field offline on both Macs, reconnect, deterministic resolution.
- **Phase 5:** migrate at least one real life-tracking workflow off its current home.

## Design exercise (parallel track)

**Approach:** mood board first, then generation.

1. Pull screenshots from Things 3, Bear, Reeder, Anytype, Tap Forms, Capacities. For each, write one line: "I want to steal X from this." (Sidebar from Things, density from Reeder, type editor from Anytype, etc.)
2. Then run the prompt below in claude.ai/design. Iterate on the Today / Planner screen first — it sets the tone for everything else.

### claude.ai/design prompt

```
Design a native macOS app called "Personal ERP" — a single-user "Life OS"
for tracking everything personal: contacts, hobbies (WoW characters,
photography gear), reading log, weight, and a daily planner that pulls
from all of it.

The defining feature: object-based, fully configurable. The user defines
types (Person, Camera, Book, Game Character, Photo Shoot) with custom
fields. The app renders table, kanban, calendar, and gallery views over
any type. Think Anytype + Tap Forms + Things 3, native to macOS.

Visual language:
- macOS Sequoia/Tahoe-native: translucent sidebar, SF Symbols, native
  toolbar with traffic lights, real macOS controls
- Calm, structured, generous whitespace — not a busy enterprise tool
- Light and dark themes
- References: Things 3 (sidebar + clarity), Bear (typography),
  Reeder (density), Anytype (type system), Capacities (object UI)

Design these screens, in this order:
1. Today / Planner — central home. Timeline, today's linked objects
   (current book, today's weight, today's photo shoot), quick capture.
2. Sidebar — object types grouped, saved views, search at top.
3. Type table view — generic spreadsheet for any object type
   (Contacts shown as the example).
4. Type kanban view — WoW characters by status as the example.
5. Type calendar view — Photo Shoots as the example.
6. Type gallery view — Photos as the example.
7. Object detail — fields, linked objects, attachments, notes, history.
8. Schema builder — how a user adds a field or defines a new type.
   This is the most distinctive screen; spend extra design effort here.
9. Quick switcher (Cmd+K) — global search across all object types.
10. Settings — sync status, encryption, backup, type management.

Constraints:
- Single-window, sidebar + main content layout
- Keyboard-first; show key shortcuts inline where natural
- Native macOS chrome and behavior (no custom title bars, no web-app feel)
- Designed for one user with potentially thousands of objects

Show light mode for screens 1–5 and dark mode for 6–10 so I can see both.
```

## Still-open questions

- [ ] Trial Tap Forms for a week before any code?
- [ ] `encryptedValues` vs. custom AES — final call before week 1
- [ ] Search: SQLite FTS5 over locally-decrypted fields, or skip incremental search for v1?
- [ ] Attachments: CloudKit `CKAsset` vs. external file refs (matters for big photo libraries)
- [ ] Schema versioning — user-driven type changes need a migration story

## What this plan deliberately does NOT include

- A decision on whether to build at all. Tap Forms might cover 80% — that's still the right gate.
- An iOS UI plan. The `Core` split makes it possible later, but the iOS app is genuinely a separate project.
- Any code. This is planning + design preparation only.
