import SwiftUI
import AppKit

@main
struct PurpleReelApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("PurpleReel") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // ---- File ---------------------------------------------------
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { appState.chooseRootFolder() }
                    .keyboardShortcut("o")
                Button("Add Folder to Workspace…") {
                    appState.addFolderToWorkspace()
                }
                .keyboardShortcut("i", modifiers: [.command])
                Divider()
                Button("Reveal in Finder") {
                    if let path = appState.selectedAsset?.path {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: path)]
                        )
                    } else if let root = appState.rootFolder {
                        NSWorkspace.shared.activateFileViewerSelecting([root])
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.selectedAsset == nil && appState.rootFolder == nil)
                Divider()
                Button("Rename…") {
                    appState.batchRenameSheetVisible = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.assets.isEmpty)
                Divider()
                Button("Export Markers as Stills…") {
                    // TODO: wire batch-export of frames at every marker
                    // for the selected clip. Engine exists in
                    // ThumbnailService; needs a save-panel + per-marker
                    // frame extraction at the exact TC.
                    notImplementedAlert(title: "Export Markers as Stills")
                }
                .disabled(appState.selectedAsset == nil)
                Menu("Export Subclips") {
                    Button("Save .fcpxml Only") {
                        appState.exportFCPXML(scope: .selectedOnly, openInFCP: false)
                    }
                    Button("Send to Final Cut Pro") {
                        appState.exportFCPXML(scope: .selectedOnly, openInFCP: true)
                    }
                }
                .disabled(appState.selectedAsset == nil)
                Menu("Export Metadata") {
                    Button("Selected Clip → FCPXML") {
                        appState.exportFCPXML(scope: .selectedOnly, openInFCP: false)
                    }
                    Button("Entire Library → FCPXML") {
                        appState.exportFCPXML(scope: .allCatalogued, openInFCP: false)
                    }
                }
            }

            // ---- Edit (extends standard) -------------------------------
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy and Verify…") {
                    appState.backupSheetVisible = true
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            // ---- Playback (new top-level) ------------------------------
            CommandMenu("Playback") {
                Button("Play From In to Out Point") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.playInToOut)
                }
                .keyboardShortcut(.space, modifiers: [.option])
                Divider()
                Button("Loop") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.toggleLoop)
                }
                .keyboardShortcut("l", modifiers: [.command])
                Button("Toggle Fullscreen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                Divider()
                Button("Jump Back 5 Seconds") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.jumpBack5s)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.shift])
                Button("Jump Forward 5 Seconds") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.jumpForward5s)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.shift])
                Button("Previous Marker") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.jumpPrevMarker)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                Button("Next Marker") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.jumpNextMarker)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                Divider()
                Button("Set In Point") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.setIn)
                }
                .keyboardShortcut("i", modifiers: [])
                Button("Set Out Point") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.setOut)
                }
                .keyboardShortcut("o", modifiers: [])
                Button("Clear In/Out") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.clearInOut)
                }
                .keyboardShortcut("x", modifiers: [.option])
                Divider()
                Button("Create or Edit Marker") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.addMarker)
                }
                .keyboardShortcut("m", modifiers: [])
                Button("Remove Marker at Playhead") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.removeMarker)
                }
                .keyboardShortcut("m", modifiers: [.option])
                Button("Create or Edit Subclip") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.saveSubclip)
                }
                .keyboardShortcut("s", modifiers: [])
                Divider()
                Button("Export Current Frame…") {
                    NotificationCenter.default.post(name: .playerCommand,
                                                    object: PlayerCommand.exportFrame)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.selectedAsset == nil)
            }

            // ---- Metadata (new top-level) ------------------------------
            CommandMenu("Metadata") {
                Menu("Rating") {
                    ForEach(0...5, id: \.self) { stars in
                        Button(stars == 0 ? "Unrated" : String(repeating: "★", count: stars)) {
                            appState.setRating(stars: stars)
                        }
                        .disabled(appState.selectedAsset == nil)
                        .keyboardShortcut(KeyEquivalent(Character("\(stars)")),
                                          modifiers: [.command])
                    }
                }
                Button("Tags…") {
                    // The right pane's Log tab houses the tag editor;
                    // this menu item nudges the user there. A standalone
                    // tags sheet is a small Phase-2 addition.
                    notImplementedAlert(title: "Tags sheet — for now use the Log tab on the right.")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Edit Multiple…") {
                    notImplementedAlert(title: "Batch metadata editor — see Kyno-parity roadmap.")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Transcribe (Whisper)") {
                    appState.transcribeSelected(generateMarkers: false)
                }
                .disabled(appState.selectedAsset == nil)
                Button("Transcribe + Create Markers") {
                    appState.transcribeSelected(generateMarkers: true)
                }
                .disabled(appState.selectedAsset == nil)
                Button("Auto-Describe (Ollama)") {
                    appState.autoDescribeSelected()
                }
                .disabled(appState.selectedAsset == nil)
                Divider()
                Button("Find Similar Takes") {
                    appState.findSimilarTakes()
                }
                .disabled(appState.assets.isEmpty)
            }

            // ---- Convert (new top-level) -------------------------------
            CommandMenu("Convert") {
                Section("Native (AVFoundation)") {
                    Button("H.264 1080p") {
                        appState.transcodeSelected(preset: TranscodePreset.all[0])
                    }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(appState.selectedAsset == nil)
                    Button("H.264 720p") {
                        appState.transcodeSelected(preset: TranscodePreset.all[1])
                    }.disabled(appState.selectedAsset == nil)
                    Button("HEVC 1080p") {
                        appState.transcodeSelected(preset: TranscodePreset.all[2])
                    }.disabled(appState.selectedAsset == nil)
                    Button("ProRes Proxy") {
                        appState.transcodeSelected(preset: TranscodePreset.all[3])
                    }.disabled(appState.selectedAsset == nil)
                    Button("ProRes 422") {
                        appState.transcodeSelected(preset: TranscodePreset.all[4])
                    }.disabled(appState.selectedAsset == nil)
                    Button("Pass-through (rewrap)") {
                        appState.transcodeSelected(preset: TranscodePreset.all[5])
                    }.disabled(appState.selectedAsset == nil)
                }
                Section("ffmpeg") {
                    Button("DNxHR SQ") {
                        appState.transcodeSelected(preset: TranscodePreset.all[6])
                    }.disabled(appState.selectedAsset == nil)
                    Button("DNxHR HQ") {
                        appState.transcodeSelected(preset: TranscodePreset.all[7])
                    }.disabled(appState.selectedAsset == nil)
                    Button("Cineform") {
                        appState.transcodeSelected(preset: TranscodePreset.all[8])
                    }.disabled(appState.selectedAsset == nil)
                    Button("ProRes in MXF") {
                        appState.transcodeSelected(preset: TranscodePreset.all[9])
                    }.disabled(appState.selectedAsset == nil)
                }
                Divider()
                Button("Show Queue…") {
                    appState.transcodeSheetVisible = true
                }
            }

            // ---- View (extends standard) -------------------------------
            CommandGroup(after: .sidebar) {
                Divider()
                Button("as Grid")   { appState.viewMode = "grid" }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("as List")   { appState.viewMode = "list" }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("as Detail") { appState.viewMode = "detail" }
                    .keyboardShortcut("3", modifiers: [.command])
                Divider()
                Button("Open Detail Sheet (Quick Look)") {
                    if appState.selectedAssetPath != nil {
                        appState.detailSheetVisible = true
                    }
                }
                .disabled(appState.selectedAssetPath == nil)
                Button("Previous Clip") {
                    appState.selectAdjacentAsset(delta: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(appState.selectedAssetPath == nil)
                Button("Next Clip") {
                    appState.selectAdjacentAsset(delta: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(appState.selectedAssetPath == nil)
                Divider()
                Button("Drilldown") {
                    appState.drilldownEnabled.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command])
            }

            // ---- History (new top-level) -------------------------------
            CommandMenu("History") {
                Button("Back") { appState.goBack() }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!appState.canGoBack)
                Button("Forward") { appState.goForward() }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(!appState.canGoForward)
                Divider()
                Button("Clear History") {
                    appState.clearHistory()
                }
                .disabled(appState.historyStack.count <= 1)
            }

            // ---- Window (extends standard) -----------------------------
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("Reset Window State…") {
                    let alert = NSAlert()
                    alert.messageText = "Reset Window State?"
                    alert.informativeText = "Sidebar, window size, and split positions will return to defaults. Restart PurpleReel after confirming for the change to take full effect."
                    alert.addButton(withTitle: "Reset")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        WindowStateGuard.forceReset(
                            appName: "PurpleReel",
                            resetVersion: AppDelegate.windowResetVersion
                        )
                    }
                }
            }

            // ---- Help (extends standard) -------------------------------
            // The Keyboard Shortcuts cheat sheet is the only fully
            // in-app help item — it reads from `Shortcuts.swift`, the
            // same canonical list `SHORTCUTS.md` is generated from.
            // User Manual + Install & Setup open bundled markdown via
            // `HelpDocs.open(...)` which prefers `Contents/Resources/
            // Help/<name>.md` first, then falls back to the repo path
            // for dev builds.
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts…") {
                    appState.shortcutsCheatSheetVisible = true
                }
                .keyboardShortcut("?", modifiers: [.command])
                Divider()
                Button("PurpleReel User Manual") {
                    HelpDocs.open(.userManual)
                }
                Button("Install & Setup") {
                    HelpDocs.open(.install)
                }
                Button("SHORTCUTS.md (Reference File)") {
                    HelpDocs.open(.shortcutsMarkdown)
                }
                Divider()
                Button("Visit Kyno parity roadmap") {
                    HelpDocs.open(.kynoRoadmap)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}

/// Player-command notifications routed from menu items to the active
/// `PlayerController` (subscribed in `PlayerView.onAppear`). Lets the
/// menu bar drive the same actions the keyboard shortcuts already do
/// without circumventing the existing key-handler.
enum PlayerCommand {
    case playInToOut
    case toggleLoop
    case setIn, setOut, clearInOut
    case addMarker, removeMarker, saveSubclip
    case exportFrame
    case jumpPrevMarker, jumpNextMarker
    case jumpBack5s, jumpForward5s
}

extension Notification.Name {
    static let playerCommand = Notification.Name("PurpleReel.PlayerCommand")
}

/// Small fallback alert for menu items whose implementation is on the
/// roadmap but not yet wired. Lives at module scope so the View body
/// doesn't escape its function-builder constraint.
@MainActor
private func notImplementedAlert(title: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "On the Kyno-parity roadmap. See KYNO_PARITY_ROADMAP.md."
    alert.runModal()
}
