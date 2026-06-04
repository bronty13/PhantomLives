# Sidebar layout: avoid `NavigationSplitView`

**For new macOS apps: do NOT use `NavigationSplitView` for the top-level
sidebar. Use a manual `HStack` with a fixed-width sidebar.** This is the
empirically-verified pattern after this codebase has burned through
three+ fix attempts.

## The bug

`NavigationSplitView` on macOS 14+ (Sonoma / Sequoia / Tahoe) does not
reliably honor `.navigationSplitViewColumnWidth(min:ideal:max:)` at
runtime — even when the persisted state is **within** the declared
range, the sidebar can render narrower than its `min`. Apple
FB10749141 was partially fixed on iPadOS 18 but not on macOS. The
problem compounds because AppKit persists split-view divider positions
in **two** places — `UserDefaults` (`"NSSplitView Subview Frames *"`)
and `~/Library/Saved Application State/<bundleId>.savedState/` — and
restores from either. Wiping `UserDefaults` alone is not enough, and
even with both stores in a valid state the runtime layout still
mis-renders.

## The canonical fix: MusicJournal pattern

A plain `HStack` with explicit sidebar `.frame(width:)`. With manual
layout we own every pixel; AppKit's window-restoration machinery has
no split-view divider to mis-restore.

```swift
struct ContentView: View {
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: 240)
                    .background(.ultraThinMaterial)
                Divider()
            }
            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }
    }
}
```

Resizability is a nice-to-have and re-opens the persistence-corruption
door — defer until explicitly requested.

## Defense in depth: `WindowStateGuard`

For nested `HSplitView` / `VSplitView` inside the detail tree (e.g.
PurpleReel splits the asset table above the player), still ship
`Services/WindowStateGuard.swift` and wire it from
`AppDelegate.applicationWillFinishLaunching`:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let windowResetVersion = 1
    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(appName: "<AppName>",
                                        resetVersion: Self.windowResetVersion)
    }
}
```

The guard does two things on each launch:

1. **Preflight purge**: strips `"NSSplitView Subview Frames *"` keys
   from `UserDefaults` AND wipes the bundle's `.savedState/` directory
   whenever a stale frame key was found. Idempotent, runs every launch.
2. **Versioned one-shot reset**: when source-declared
   `windowResetVersion` exceeds the user's stored version, wipes the
   entire window-state surface (NSWindow frames, sidebar separation,
   `.savedState`). Bump in source to invalidate every install.

Also expose a `Window → Reset Window State…` menu item calling
`WindowStateGuard.forceReset(...)` for user-visible recovery.

## Reference implementation

- `PurpleReel/Sources/PurpleReel/Views/ContentView.swift` — HStack
  layout (copy verbatim into new apps).
- `PurpleReel/Sources/PurpleReel/Services/WindowStateGuard.swift` —
  guard helper (copy verbatim).
- `PurpleReel/Sources/PurpleReel/App/AppDelegate.swift` — minimal
  delegate wired via `@NSApplicationDelegateAdaptor`.
- `MusicJournal/Sources/MusicJournal/Views/ContentView.swift` —
  original incident report and HStack template.

## Apps still on `NavigationSplitView` (retrofit on next touch)

PurpleLife, PurpleTracker, PurpleIRC, PurpleDedup, Timeliner,
MasterClipper. All have been bitten by this bug in some form. None
are crash-broken today (their `WindowStateGuard`-style hacks cover
the worst cases) but the only durable fix is to drop
`NavigationSplitView` for the manual HStack pattern.
