import Foundation

/// Canonical keyboard-shortcut catalogue. Read by:
///   • the in-app `ShortcutsCheatSheet` sheet (Help → Keyboard
///     Shortcuts…)
///   • `Scripts/generate-shortcuts-md.swift` which renders
///     `SHORTCUTS.md` at build time
///
/// Everything that takes a key combo in the app should be listed
/// here so the cheat sheet, the Markdown reference, and the menu
/// bar bindings can't drift.
///
/// **Adding a new shortcut**
/// 1. Add an entry to `Shortcuts.all` below.
/// 2. Bind the same combo where it lives (CommandMenu in
///    `PurpleReelApp.swift`, or directly in a View's
///    `.keyboardShortcut` modifier).
/// 3. Run `swift Scripts/generate-shortcuts-md.swift` (or just
///    rebuild — `build-app.sh` runs it) to refresh `SHORTCUTS.md`.
enum ShortcutGroup: String, CaseIterable, Identifiable {
    case browser   = "Browser"
    case player    = "Player"
    case logging   = "Logging & Metadata"
    case convert   = "Convert / Send"
    case view      = "View"
    case window    = "Window"

    var id: String { rawValue }
}

struct Shortcut: Identifiable {
    /// Stable id for ForEach. Built from group + key so it stays
    /// unique without explicit numbering.
    var id: String { "\(group.rawValue)|\(combo)|\(action)" }

    let group: ShortcutGroup
    /// Human-readable combo, e.g. "⌘E" or "Shift-click".
    let combo: String
    /// Action description shown in the cheat sheet.
    let action: String
    /// Where the binding is implemented — helps the next
    /// maintainer find the call site quickly. Optional.
    let source: String?

    init(_ group: ShortcutGroup, _ combo: String, _ action: String,
         source: String? = nil) {
        self.group = group
        self.combo = combo
        self.action = action
        self.source = source
    }
}

enum Shortcuts {
    static let all: [Shortcut] = [

        // ---- Browser ----
        .init(.browser, "⌘1", "Switch to Grid view",
              source: "BrowserView.viewModeToggle"),
        .init(.browser, "⌘2", "Switch to List view",
              source: "BrowserView.viewModeToggle"),
        .init(.browser, "⌘3", "Switch to Detail view",
              source: "BrowserView.viewModeToggle"),
        .init(.browser, "⌘[",  "History — Back",
              source: "AppState.goBack"),
        .init(.browser, "⌘]",  "History — Forward",
              source: "AppState.goForward"),
        .init(.browser, "⌘I",  "Add Folder to Workspace…",
              source: "ContentView.workspaceHeader"),
        .init(.browser, "⌃⌘S", "Toggle Sidebar",
              source: "ContentView.toolbar"),
        .init(.browser, "⌘O",  "Open Folder… (workspace root)",
              source: "AppState.chooseRootFolder"),
        .init(.browser, "Cmd-click",   "Toggle item in multi-selection",
              source: "AppState.handleAssetClick"),
        .init(.browser, "Shift-click", "Range-extend multi-selection",
              source: "AppState.handleAssetClick"),
        .init(.browser, "Double-click", "Open clip in Detail view (inline)",
              source: "BrowserView.openInlineDetail"),

        // ---- Player ----
        .init(.player, "Space",   "Play / pause",
              source: "PlayerView.transportBar"),
        .init(.player, "←",      "Step back 1 frame"),
        .init(.player, "→",      "Step forward 1 frame"),
        .init(.player, "Shift+←", "Jump back 5 seconds"),
        .init(.player, "Shift+→", "Jump forward 5 seconds"),
        .init(.player, "↑",      "Jump to previous marker (or in/out)"),
        .init(.player, "↓",      "Jump to next marker (or in/out)"),
        .init(.player, "J",       "Shuttle reverse (multi-rate)"),
        .init(.player, "K",       "Stop shuttle"),
        .init(.player, "L",       "Shuttle forward (multi-rate)"),
        .init(.player, "I",       "Set in point"),
        .init(.player, "O",       "Set out point"),
        .init(.player, "⌥X",     "Clear in / out"),
        .init(.player, "⌥Space", "Play from in to out",
              source: "PlayerCommand.playInToOut"),
        .init(.player, "⌘L",     "Toggle loop mode",
              source: "PlayerController.toggleLoop"),
        .init(.player, "⌘F",     "Toggle fullscreen",
              source: "NSWindow.toggleFullScreen"),
        .init(.player, "⌘⇧E",   "Export current frame as PNG",
              source: "PlayerController.exportCurrentFrame"),

        // ---- Logging & Metadata ----
        .init(.logging, "M",      "Add marker at playhead"),
        .init(.logging, "⌥M",    "Remove marker at playhead"),
        .init(.logging, "S",      "Save subclip from I/O range"),
        .init(.logging, "⌘0…⌘5", "Set rating (0 = unrated)"),
        .init(.logging, "⌘⇧T",  "Tags sheet (roadmap)"),
        .init(.logging, "⌘⇧M",  "Edit Multiple metadata across selection",
              source: "AppState.applyBatchMetadata(_:)"),

        // ---- Convert / Send ----
        .init(.convert, "⌘E",  "Convert with most-recently-used preset",
              source: "AssetContextMenu.convertSubmenuContents"),

        // ---- View ----
        .init(.view, "⌘R",  "Rotate clockwise (roadmap)"),
        .init(.view, "⌘⌥R", "Rotate counter-clockwise (roadmap)"),
        .init(.view, "⌃⌥E", "Zebra filter (roadmap)"),
        .init(.view, "⌃⌥W", "Widescreen mattes (roadmap)"),

        // ---- Window ----
        .init(.window, "⌘,",  "Open Settings",
              source: "macOS standard"),
        .init(.window, "⌘?",  "Keyboard Shortcuts cheat sheet",
              source: "Help menu"),
    ]

    static func byGroup() -> [(ShortcutGroup, [Shortcut])] {
        ShortcutGroup.allCases.map { g in
            (g, all.filter { $0.group == g })
        }.filter { !$0.1.isEmpty }
    }
}
