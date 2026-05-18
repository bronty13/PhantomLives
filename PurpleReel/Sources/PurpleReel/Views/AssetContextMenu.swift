import SwiftUI
import AppKit

/// Kyno-style right-click menu for a single asset. Media-type aware:
/// video/audio show Play All + Convert + Export Subclips; images show
/// Batch Image Transform instead. Returns @ViewBuilder content so the
/// caller can drop it inside `.contextMenu { … }`.
struct AssetContextMenu: View {
    @EnvironmentObject var appState: AppState
    let asset: Asset

    private var kind: MediaKind { MediaKind.of(asset: asset) }

    @ViewBuilder
    var body: some View {
        // Split into chunks because ViewBuilder closures cap at 10
        // children. The full Kyno-style menu is ~25 items; if we put
        // them in one Group they silently collapse and no menu items
        // appear. Each helper var stays well under the limit.
        openSection
        editSection
        deliverySection
        metadataSection
        aiSection
    }

    @ViewBuilder private var openSection: some View {
        Button("Open") { openInDefaultApp() }
        if kind == .video || kind == .audio {
            Button("Play All") {
                appState.selectedAssetPath = asset.path
                appState.detailSheetVisible = true
            }
            .keyboardShortcut("p", modifiers: [.command])
        }
        Menu("Open With") { openWithMenu }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: asset.path)]
            )
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        Button("Show in Enclosing Folder") {
            let parent = (asset.path as NSString).deletingLastPathComponent
            NSWorkspace.shared.open(URL(fileURLWithPath: parent))
        }
        Divider()
        Button("Move to Trash") { moveToTrash() }
        Divider()
    }

    @ViewBuilder private var editSection: some View {
        Button("Rename…") {
            appState.selectedAssetPath = asset.path
            appState.batchRenameSheetVisible = true
        }
        Button("Copy") { copyFileToPasteboard() }
            .keyboardShortcut("c", modifiers: [.command])
        Button("Refresh") { Task { await appState.rescan() } }
        Divider()
    }

    @ViewBuilder private var deliverySection: some View {
        Menu("Send To") {
            Button("SFTP Delivery…") { appState.sftpSheetVisible = true }
            Button("Verified Backup…") { appState.backupSheetVisible = true }
        }
        if kind == .video || kind == .audio {
            Menu("Convert") {
                convertSubmenuContents
            }
            Menu("Export Subclips") {
                Button("Save .fcpxml") {
                    appState.selectedAssetPath = asset.path
                    appState.exportFCPXML(scope: .selectedOnly, openInFCP: false)
                }
                Button("Send to Final Cut Pro") {
                    appState.selectedAssetPath = asset.path
                    appState.exportFCPXML(scope: .selectedOnly, openInFCP: true)
                }
            }
        }
        if kind == .image {
            Button("Batch Image Transform…") { notImplementedAlert("Batch Image Transform") }
        }
        Button("Export Markers as Stills…") { notImplementedAlert("Export Markers as Stills") }
        Menu("Export Metadata") {
            Button("Selected → FCPXML") {
                appState.selectedAssetPath = asset.path
                appState.exportFCPXML(scope: .selectedOnly, openInFCP: false)
            }
            Button("Entire Library → FCPXML") {
                appState.exportFCPXML(scope: .allCatalogued, openInFCP: false)
            }
        }
        Button("Import Metadata…") { notImplementedAlert("Import Metadata") }
        Divider()
    }

    @ViewBuilder private var metadataSection: some View {
        Menu("Rating") {
            ForEach(0...5, id: \.self) { stars in
                Button(stars == 0 ? "Unrated"
                                   : String(repeating: "★", count: stars)) {
                    appState.selectedAssetPath = asset.path
                    appState.setRating(stars: stars)
                }
            }
        }
        Button("Tags…") { notImplementedAlert("Tags sheet") }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        Button("Edit Multiple…") { notImplementedAlert("Edit Multiple") }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        if kind == .video {
            Menu("Camera LUT") {
                Button("Load .cube…") {
                    notImplementedAlert("Camera LUT picker — use the LUT bar in the player for now.")
                }
            }
            Menu("Creative LUT") {
                Button("Load .cube…") {
                    notImplementedAlert("Creative LUT picker — use the LUT bar in the player for now.")
                }
            }
        }
        Divider()
    }

    @ViewBuilder private var aiSection: some View {
        Button("Transcribe (Whisper)") {
            appState.selectedAssetPath = asset.path
            appState.transcribeSelected(generateMarkers: false)
        }
        .disabled(kind == .image)
        Button("Auto-Describe (Ollama)") {
            appState.selectedAssetPath = asset.path
            appState.autoDescribeSelected()
        }
    }

    /// Categorized Convert submenu (Kyno-parity). Recently-used presets
    /// surface at the top, then each category gets its own submenu so
    /// the user doesn't have to scan a long flat list.
    @ViewBuilder
    private var convertSubmenuContents: some View {
        let recent = RecentPresets.list()
        if !recent.isEmpty {
            Section("Recently Used") {
                ForEach(Array(recent.enumerated()), id: \.element.id) { idx, preset in
                    if idx == 0 {
                        Button(preset.name) { fireConvert(preset) }
                            .keyboardShortcut("e", modifiers: [.command])
                    } else {
                        Button(preset.name) { fireConvert(preset) }
                    }
                }
            }
            Divider()
        }
        ForEach(TranscodeCategory.allCases) { cat in
            let presets = TranscodePreset.byCategory(cat)
            if !presets.isEmpty {
                Menu(cat.displayName) {
                    ForEach(presets) { preset in
                        Button(preset.name) { fireConvert(preset) }
                    }
                }
            }
        }
    }

    private func fireConvert(_ preset: TranscodePreset) {
        // If the user right-clicked a row not yet in the multi-selection,
        // include it so batch operates on what they clicked.
        if !appState.selectedAssetPaths.contains(asset.path) {
            appState.selectedAssetPaths = [asset.path]
            appState.selectedAssetPath = asset.path
        }
        appState.openConvertDialog(preset: preset)
    }

    @ViewBuilder
    private var openWithMenu: some View {
        let url = URL(fileURLWithPath: asset.path)
        let handlers = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if handlers.isEmpty {
            Text("No registered handlers").foregroundStyle(.secondary)
        } else {
            ForEach(handlers.prefix(8), id: \.self) { app in
                Button(app.deletingPathExtension().lastPathComponent) {
                    NSWorkspace.shared.open([url], withApplicationAt: app,
                                              configuration: NSWorkspace.OpenConfiguration())
                }
            }
            Divider()
            Button("Other…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                if panel.runModal() == .OK, let appURL = panel.url {
                    NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                              configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    // MARK: - Actions

    private func openInDefaultApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: asset.path))
    }

    private func moveToTrash() {
        let url = URL(fileURLWithPath: asset.path)
        do {
            var dst: NSURL? = nil
            try FileManager.default.trashItem(at: url, resultingItemURL: &dst)
            Task { await appState.rescan() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not move to Trash"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func copyFileToPasteboard() {
        let url = URL(fileURLWithPath: asset.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    private func notImplementedAlert(_ title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "On the Kyno-parity roadmap. See KYNO_PARITY_ROADMAP.md."
        alert.runModal()
    }
}
