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
            // Send → DaVinci Resolve (Kyno-parity, Image #100). The
            // Resolve / Resolve Studio bundle IDs are tried in turn;
            // disable the button when neither is installed so the
            // menu doesn't lie about what'll happen.
            if let resolve = resolveAppURL {
                // Kyno's binding (⌘⇧D) collides with PurpleReel's
                // Sprint-1 Kyno-compat alias for drilldown toggle.
                // Ship without a shortcut — menu-only — and let the
                // user discover it through the menu. Pinning the
                // shortcut would silently break one of the two.
                Button("DaVinci Resolve…") {
                    sendSelectionToResolve(via: resolve)
                }
            }
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
        // (Batch Image Transform was a dead-end menu item — image
        // batch resize/crop isn't on any roadmap, so removing it
        // beats an "On the roadmap" alert that never gets crossed
        // off. Use Convert presets on images for format changes.)
        if kind == .video || kind == .audio {
            Button("Export Markers as Stills…") {
                appState.selectedAssetPath = asset.path
                appState.exportFramesAtMarkers()
            }
        }
        Menu("Export Metadata") {
            Button("Selected → FCPXML") {
                appState.selectedAssetPath = asset.path
                appState.exportFCPXML(scope: .selectedOnly, openInFCP: false)
            }
            Button("Entire Library → FCPXML") {
                appState.exportFCPXML(scope: .allCatalogued, openInFCP: false)
            }
        }
        Menu("Import Metadata") {
            Button("From FCPXML…") { appState.importFCPXML() }
            Button("From Kyno (.LP_Store)…") { appState.importFromKynoLPStore() }
        }
        Divider()
    }

    @ViewBuilder private var metadataSection: some View {
        Menu("Rating") {
            // 5..1 stars, then Unrated (0), then Rejected (-1) per
            // Kyno's right-click rating submenu (Image #98). Rejected
            // is a sentinel value (`stars = -1`) rather than a new
            // column — the rating table's stars Int already accepts
            // any value, so no schema migration needed.
            ForEach((1...5).reversed(), id: \.self) { stars in
                Button(String(repeating: "★", count: stars)) {
                    appState.selectedAssetPath = asset.path
                    appState.setRating(stars: stars)
                }
            }
            Button("Unrated") {
                appState.selectedAssetPath = asset.path
                appState.setRating(stars: 0)
            }
            Button("Rejected") {
                appState.selectedAssetPath = asset.path
                appState.setRating(stars: -1)
            }
        }
        Button("Tags…") {
            // C14 — Kyno routes single-clip Tags to a dedicated
            // dialog and multi-clip Tags to a batch sheet. Set the
            // primary selection first so the resolver sees the
            // right-clicked clip when nothing else is multi-selected.
            if !appState.selectedAssetPaths.contains(asset.path) {
                appState.selectedAssetPaths = [asset.path]
            }
            appState.selectedAssetPath = asset.path
            appState.openTagEditor()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        Button("Edit Multiple…") {
            appState.selectedAssetPath = asset.path
            appState.batchMetadataSheetVisible = true
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        // Per-clip LUT assignment (Kyno's Camera/Creative LUT
        // distinction) isn't a separate path — PurpleReel applies
        // LUTs preview-only via the player's LUT bar, and bakes
        // them on export per the `applyLUTToExportedFrames` toggle.
        // So no menu items here; the LUT bar in the player is the
        // single source of truth.
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
        Divider()
        // Pre-analyze (Kyno-parity, Image #97). Re-runs the AVAsset
        // probe (duration / codec / dims / fps / audio codec) on the
        // selected clip(s) and writes the refreshed values to the DB.
        // Useful when a clip was scanned with stale metadata (e.g.
        // before the user fixed the camera's clock) or when the user
        // wants to force a re-derive after editing the source file
        // out-of-band.
        Button("Pre-analyze…") {
            // C13 — open the Analysis Scope dialog (Kyno-parity).
            // The dialog's Start button calls preAnalyzeSelected(scope:)
            // with the user's pick of Technical metadata / Thumbnails /
            // Key frames. The ellipsis follows Apple HIG for menu
            // items that present a dialog.
            appState.openAnalysisScopeDialog()
        }
        .help("Opens the Analysis Scope dialog so you can pick which work to redo: AVAsset probe (duration / codec / dims / fps), thumbnail regeneration, and (reserved) keyframe extraction.")
    }

    // MARK: - DaVinci Resolve send-to helpers

    /// Resolved URL of either DaVinci Resolve or DaVinci Resolve
    /// Studio, whichever is installed first. nil = neither found,
    /// so we hide the menu item instead of letting the user click a
    /// no-op.
    private var resolveAppURL: URL? {
        // The free-tier and Studio bundles ship under different
        // bundle IDs; check both. Order matters only for the disabled-
        // menu fallback — we never need both at once.
        let bundles = [
            "com.blackmagic-design.DaVinciResolve",
            "com.blackmagic-design.DaVinciResolveStudio",
        ]
        for id in bundles {
            if let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        return nil
    }

    /// Hand the selection off to DaVinci. Multi-selection lands as
    /// one `open` call so Resolve imports them into the same Media
    /// Pool batch.
    private func sendSelectionToResolve(via app: URL) {
        let urls: [URL]
        if appState.selectedAssetPaths.contains(asset.path),
           appState.selectedAssetPaths.count > 1 {
            urls = appState.selectedAssetPaths.map {
                URL(fileURLWithPath: $0)
            }
        } else {
            urls = [URL(fileURLWithPath: asset.path)]
        }
        NSWorkspace.shared.open(urls, withApplicationAt: app,
                                  configuration: NSWorkspace.OpenConfiguration())
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
            // Kyno-parity (Image #99): show every registered handler,
            // not just the first 8. The 8-cap was leaving common apps
            // (Compressor, Pixelmator Pro, VLC) off the list when a
            // user had a dozen+ video apps installed. NSWorkspace
            // returns them already sorted by relevance.
            ForEach(handlers.prefix(20), id: \.self) { app in
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

}
