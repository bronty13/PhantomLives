# Personal ERP — Planning Doc

A planning document for building a structured, encrypted, multi-Mac personal life management application.

## Background

The goal: a single application that organizes wide-ranging life data — planner, hobbies (WoW, photography), extended contacts, health (weight), reading log — in a tightly integrated, structured way.

**Key requirements:**
- Data stays under personal control (no third-party cloud)
- Data encrypted at all times
- Runs across multiple Macs with iCloud sync
- Daily backups
- Highly configurable

## What's Already Out There

True personal ERPs don't really exist as polished products. The "Life OS" market is mostly Notion templates (cloud-based, ruled out), Obsidian configurations, or abandoned hobby projects on GitHub. The category — a structured, encrypted, multi-device, configurable life database — has surprising gaps.

### Closest existing tools

- **Tap Forms** — Native macOS personal database app. Strong encryption, iCloud sync, very configurable. Probably the closest off-the-shelf match.
- **Ninox** — Native Mac/iOS, custom database builder, scripting, real-time sync. Solid but has a cloud component for sync.
- **Trilium Notes** — Powerful, hierarchical, but Linux-leaning and requires self-hosted server for sync.
- **Anytype** — Object-based local-first system. Closest in philosophy but not quite as configurable as desired.

**Recommendation:** Trial Tap Forms before committing to build. It might cover 70-80% of requirements without the maintenance burden. The gap will be on the planner side.

## Should Obsidian Still Be In Play?

**No.** The reason Obsidian came up was the hybrid approach — but the hybrid felt too decoupled. If building one tightly integrated system, a separate Obsidian alongside reintroduces the exact problem the build is meant to solve. Better to bake rich note/journal capabilities into the custom app.

## The Build Plan

### Architecture Choice

**Native macOS app, built in Swift/SwiftUI, with SQLite storage.**

Why native over a web app:
- iCloud sync is genuinely hard to do well outside Apple's ecosystem; native apps get CloudKit "for free"
- Encryption integrates cleanly with macOS Keychain
- Better performance, real menu bar/Dock integration, real keyboard shortcuts
- Spotlight indexing, Shortcuts integration, Quick Look — all gifts of being native
- Runs forever without needing a web server process

Tradeoff: Swift learning curve, but it's well-suited to AI-assisted development, and Apple's tooling (Xcode, SwiftData) has gotten genuinely good.

### Data Model Approach

**Object-based, similar to Anytype's model.** Define types with custom fields:

- Person, Game (WoW character/session), Camera, Lens, Photo Shoot, Book, Weight Entry, Day (planner), Project, etc.
- Every object can link to any other object (true relations)
- Every object type is configurable — add fields anytime
- Custom views per type (table, kanban, calendar, gallery)

This is the "very configurable" requirement done right. Not hard-coding "WoW tracker" — defining what a Game Character looks like, and the app renders it.

### Sync, Backup, Encryption

| Concern | Approach |
|---------|----------|
| **Sync** | CloudKit (iCloud) — encrypted in transit and at rest by Apple, no third-party server |
| **Local encryption** | SQLCipher (encrypted SQLite) with key in macOS Keychain, requires login |
| **Daily backups** | Automatic timestamped exports to a designated folder (also iCloud-backed). Keep 30 daily, 12 monthly. Export format: JSON + media files, fully restorable |
| **Multi-Mac** | CloudKit handles this natively, near-real-time sync |

### Build Phases

1. **Foundation (weeks 1–2)** — Native shell, SwiftData/SQLite + SQLCipher, Keychain, basic object/field/relation primitives
2. **Core UX (weeks 3–4)** — Type editor, generic table/kanban/calendar views, search, basic linking
3. **Planner module (week 5)** — Daily/weekly planner that pulls in data from any object type
4. **CloudKit sync + backup (week 6)** — Multi-Mac sync, automated daily exports
5. **First real use cases (weeks 7+)** — Define actual types: Person, WoW Character, Camera, Book, Weight, etc.

### Risks To Flag

- **Week 2-3 wall** — A feature that seemed simple turns out to be a week's work. Normal but kills most personal projects.
- **CloudKit learning curve** — First sync setup will probably eat 2-3 days.
- **Backup correctness is critical** — Test restore from backup before trusting any data to it.

## Recommended Next Step

Before committing to the build:

1. Download **Tap Forms** and give it a real test drive for a week
2. Try to model 2-3 of the real use cases (WoW characters, contacts, weight log)
3. Note where it falls short — these become the requirements for the custom build

If Tap Forms doesn't cut it, the build plan above is solid and the hardware/skills (M4 Max, Apple Silicon, technical comfort) are more than up to it.

## Open Questions / Next Sessions

- [ ] Sketch out the object/type schema for specific use cases (WoW, photography, contacts, etc.)
- [ ] Deeper evaluation of Tap Forms against requirements
- [ ] Week-by-week breakdown of the build
- [ ] Decision: Tap Forms first, or commit to build now?
