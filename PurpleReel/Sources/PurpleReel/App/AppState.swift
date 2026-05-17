import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var rootFolder: URL?
    @Published var workspaceRoots: [URL] = []
    @Published var assets: [Asset] = []
    @Published var folderTree: FolderNode?
    @Published var selectedFolderPath: String?   // nil = root (all)
    @AppStorage("drilldownEnabled") var drilldownEnabled: Bool = true
    @AppStorage("typeFilter") var typeFilter: String = "all"  // all/video/audio/image
    @AppStorage("sortKey") var sortKey: String = "name"        // name/date/size/duration/fps/rating

    // History stack for the back/forward navigation arrows.
    // Each entry is the `selectedFolderPath` value at that point.
    @Published private(set) var historyStack: [String?] = [nil]
    @Published private(set) var historyIndex: Int = 0
    private var suppressHistory = false
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < historyStack.count - 1 }
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var selectedAssetPath: String? {
        didSet { loadSelectionDetail() }
    }

    // Bridges `selectedFolderPath` writes through a history-aware
    // setter so the back/forward arrows see every navigation event.
    // Direct `selectedFolderPath = …` is still valid and supported;
    // when it changes from a non-suppressed path, we append.
    func navigate(to folder: String?) {
        let cur = historyStack.indices.contains(historyIndex) ? historyStack[historyIndex] : nil
        guard cur != folder else { return }
        // Drop any forward history past the current point — same as
        // browser history semantics.
        if historyIndex < historyStack.count - 1 {
            historyStack = Array(historyStack.prefix(historyIndex + 1))
        }
        historyStack.append(folder)
        historyIndex = historyStack.count - 1
        suppressHistory = true
        selectedFolderPath = folder
        suppressHistory = false
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        suppressHistory = true
        selectedFolderPath = historyStack[historyIndex]
        suppressHistory = false
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        suppressHistory = true
        selectedFolderPath = historyStack[historyIndex]
        suppressHistory = false
    }

    func clearHistory() {
        let current = historyStack.indices.contains(historyIndex) ? historyStack[historyIndex] : nil
        historyStack = [current]
        historyIndex = 0
    }

    /// Move the asset-table selection up or down by `delta` rows
    /// (within the currently-displayed list). Wired to ⌘← / ⌘→.
    func selectAdjacentAsset(delta: Int) {
        let list = displayedAssets
        guard !list.isEmpty else { return }
        if let current = selectedAssetPath,
           let idx = list.firstIndex(where: { $0.path == current }) {
            let newIdx = max(0, min(list.count - 1, idx + delta))
            selectedAssetPath = list[newIdx].path
        } else {
            selectedAssetPath = list.first?.path
        }
    }

    /// Filtered view of `assets` driven by `selectedFolderPath`,
    /// `drilldownEnabled`, `typeFilter`, and sorted by `sortKey`.
    /// Matches Kyno's browser-toolbar semantics.
    var displayedAssets: [Asset] {
        // Always scope to *some* root: either the explicitly-selected
        // folder, the current active root, or — if a workspace has
        // multiple roots — the union of all of them. Without this,
        // catalogue-wide history bleeds previous folders into the view.
        var base: [Asset]
        if let folder = selectedFolderPath, !folder.isEmpty {
            let normalized = (folder as NSString).standardizingPath
            if drilldownEnabled {
                base = assets.filter { ($0.path as NSString).standardizingPath
                                         .hasPrefix(normalized + "/") }
            } else {
                base = assets.filter { asset in
                    let parent = ((asset.path as NSString).standardizingPath as NSString)
                        .deletingLastPathComponent
                    return parent == normalized
                }
            }
        } else if !workspaceRoots.isEmpty {
            // Show every asset under any workspace root.
            let normalizedRoots = workspaceRoots.map { ($0.path as NSString).standardizingPath }
            base = assets.filter { asset in
                let p = (asset.path as NSString).standardizingPath
                return normalizedRoots.contains { p.hasPrefix($0 + "/") }
            }
        } else {
            base = assets
        }

        // Media-type filter
        switch typeFilter {
        case "video":
            base = base.filter { AssetKind.from(extension: ($0.filename as NSString).pathExtension) == .video }
        case "audio":
            base = base.filter { AssetKind.from(extension: ($0.filename as NSString).pathExtension) == .audio }
        case "image":
            base = base.filter { AssetKind.from(extension: ($0.filename as NSString).pathExtension) == .image }
        default: break
        }

        // Sort
        switch sortKey {
        case "date":
            base.sort { $0.modifiedAt > $1.modifiedAt }
        case "size":
            base.sort { $0.sizeBytes > $1.sizeBytes }
        case "duration":
            base.sort { ($0.durationSeconds ?? 0) > ($1.durationSeconds ?? 0) }
        case "fps":
            base.sort { ($0.frameRate ?? 0) > ($1.frameRate ?? 0) }
        default:
            base.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        }
        return base
    }

    // Detail state for the currently selected asset.
    @Published private(set) var selectedAsset: Asset?
    @Published private(set) var markers: [Marker] = []
    @Published private(set) var subclips: [Subclip] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var rating: Rating?

    private let scanner = MediaScanner()
    let db: DatabaseService
    let transcodeQueue = TranscodeQueue()
    @Published var transcodeSheetVisible = false
    @Published var backupSheetVisible = false
    @Published var sftpSheetVisible = false
    @Published var aiSheetState: AISheetState?
    @Published var batchRenameSheetVisible = false

    @Published private(set) var transcript: TranscriptDocument?
    @Published var aiStatus: String = ""

    init() {
        do {
            self.db = try DatabaseService()
        } catch {
            fatalError("PurpleReel could not open its database: \(error)")
        }
        BackupService.runOnLaunchIfNeeded()
        // Hydrate workspace from defaults: prefer the new
        // `workspaceRoots` array; fall back to the legacy single
        // `rootFolder` string for users upgrading from earlier builds.
        if let savedArray = UserDefaults.standard.array(forKey: "workspaceRoots") as? [String],
           !savedArray.isEmpty {
            self.workspaceRoots = savedArray.map { URL(fileURLWithPath: $0) }
            self.rootFolder = self.workspaceRoots.first
        } else if let saved = UserDefaults.standard.string(forKey: "rootFolder") {
            self.rootFolder = URL(fileURLWithPath: saved)
            self.workspaceRoots = [URL(fileURLWithPath: saved)]
        }
        if let root = rootFolder {
            self.selectedFolderPath = root.path
            self.historyStack = [root.path]
            self.historyIndex = 0
            self.assets = (try? db.allAssets()) ?? []
            self.rebuildFolderTree()
            Task { await rescan() }
        }
    }

    // MARK: - Root folder / scan

    /// "Open Folder…" semantics: replace the workspace with a single
    /// root and scan it. Behaves like a fresh-start.
    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            self.workspaceRoots = [url]
            self.rootFolder = url
            self.selectedFolderPath = url.path
            self.historyStack = [url.path]
            self.historyIndex = 0
            persistWorkspace()
            Task { await rescan() }
        }
    }

    /// Workspace addition: pick a folder and add it as a sibling
    /// root without dropping the existing roots. Matches Kyno's
    /// "Add Folder to Workspace…".
    func addFolderToWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !workspaceRoots.contains(url) {
                workspaceRoots.append(url)
            }
            self.rootFolder = url   // make the newly-added root active
            self.selectedFolderPath = url.path
            persistWorkspace()
            navigate(to: url.path)
            Task { await rescan() }
        }
    }

    func clearWorkspace() {
        workspaceRoots = []
        rootFolder = nil
        selectedFolderPath = nil
        assets = []
        folderTree = nil
        historyStack = [nil]
        historyIndex = 0
        persistWorkspace()
    }

    func removeWorkspaceRoot(_ url: URL) {
        workspaceRoots.removeAll { $0 == url }
        if rootFolder == url { rootFolder = workspaceRoots.first }
        persistWorkspace()
        Task { await rescan() }
    }

    private func persistWorkspace() {
        let paths = workspaceRoots.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "workspaceRoots")
        UserDefaults.standard.set(rootFolder?.path, forKey: "rootFolder")
    }

    /// Scan every workspace root and union the results into the
    /// catalogue. Always reloads `assets` from the DB at the end so
    /// the displayed view reflects EVERY catalogued file under any
    /// workspace root, with no stale entries from previously-opened
    /// folders.
    func rescan() async {
        let roots: [URL] = !workspaceRoots.isEmpty
            ? workspaceRoots
            : (rootFolder.map { [$0] } ?? [])
        guard !roots.isEmpty else { return }
        isScanning = true
        defer { isScanning = false; scanProgress = "" }

        do {
            for root in roots {
                scanProgress = "Scanning \(root.lastPathComponent)…"
                let found = try await scanner.scan(root: root) { [weak self] count in
                    Task { @MainActor in
                        self?.scanProgress = "Found \(count) media files in \(root.lastPathComponent)…"
                    }
                }
                try db.upsertAssets(found)
            }
            self.assets = try db.allAssets()
            self.rebuildFolderTree()
        } catch {
            NSLog("[PurpleReel] scan failed: \(error)")
        }
    }

    /// Rebuild the sidebar folder tree(s) from the current asset list.
    /// For a single-root workspace it's still rendered as one tree; for
    /// multi-root, the sidebar walks `workspaceRoots` and builds one
    /// tree per root (via the helper below).
    func rebuildFolderTree() {
        guard let root = rootFolder else {
            folderTree = nil
            return
        }
        folderTree = FolderTreeBuilder.build(rootPath: root.path, assets: assets)
    }

    func folderTree(forRoot root: URL) -> FolderNode? {
        FolderTreeBuilder.build(rootPath: root.path, assets: assets)
    }

    // MARK: - Selection detail

    private func loadSelectionDetail() {
        markers = []
        subclips = []
        tags = []
        rating = nil
        transcript = nil
        selectedAsset = nil
        guard let path = selectedAssetPath else { return }
        do {
            guard let asset = try db.asset(forPath: path),
                  let id = asset.rowId else { return }
            selectedAsset = asset
            markers = try db.markers(assetId: id)
            subclips = try db.subclips(parentAssetId: id)
            tags = try db.tags(assetId: id)
            rating = try db.rating(assetId: id)
            transcript = try db.transcript(assetId: id)
        } catch {
            NSLog("[PurpleReel] selection load failed: \(error)")
        }
    }

    private func refreshMarkers() {
        guard let id = selectedAsset?.rowId else { return }
        markers = (try? db.markers(assetId: id)) ?? []
    }

    private func refreshSubclips() {
        guard let id = selectedAsset?.rowId else { return }
        subclips = (try? db.subclips(parentAssetId: id)) ?? []
    }

    private func refreshTags() {
        guard let id = selectedAsset?.rowId else { return }
        tags = (try? db.tags(assetId: id)) ?? []
    }

    private func refreshRating() {
        guard let id = selectedAsset?.rowId else { return }
        rating = try? db.rating(assetId: id)
    }

    // MARK: - Markers

    func addMarker(timecodeIn: Double, note: String? = nil) {
        guard let id = selectedAsset?.rowId else { return }
        _ = try? db.addMarker(assetId: id, timecodeIn: timecodeIn, note: note)
        refreshMarkers()
    }

    func deleteMarker(_ marker: Marker) {
        guard let mid = marker.id else { return }
        try? db.deleteMarker(id: mid)
        refreshMarkers()
    }

    func updateMarkerNote(_ marker: Marker, note: String) {
        var copy = marker
        copy.note = note.isEmpty ? nil : note
        try? db.updateMarker(copy)
        refreshMarkers()
    }

    // MARK: - Subclips

    func addSubclip(name: String, timecodeIn: Double, timecodeOut: Double) {
        guard let id = selectedAsset?.rowId else { return }
        let lo = min(timecodeIn, timecodeOut)
        let hi = max(timecodeIn, timecodeOut)
        _ = try? db.addSubclip(parentAssetId: id, name: name,
                                timecodeIn: lo, timecodeOut: hi)
        refreshSubclips()
    }

    func deleteSubclip(_ subclip: Subclip) {
        guard let sid = subclip.id else { return }
        try? db.deleteSubclip(id: sid)
        refreshSubclips()
    }

    // MARK: - Tags

    func addTag(name: String) {
        guard let id = selectedAsset?.rowId else { return }
        _ = try? db.addTag(name: name, assetId: id)
        refreshTags()
    }

    func removeTag(name: String) {
        guard let id = selectedAsset?.rowId else { return }
        try? db.removeTag(name: name, assetId: id)
        refreshTags()
    }

    // MARK: - Rating + description

    func setRating(stars: Int) {
        guard let id = selectedAsset?.rowId else { return }
        let desc = rating?.description
        let color = rating?.colorLabel
        try? db.setRating(assetId: id, stars: stars,
                          colorLabel: color, description: desc)
        refreshRating()
    }

    // MARK: - AI: Whisper transcription

    func transcribeSelected(generateMarkers: Bool) {
        guard let asset = selectedAsset, let id = asset.rowId else { return }
        aiSheetState = .transcribing(filename: asset.filename)
        aiStatus = "Loading MLX Whisper…"
        // Honor user overrides from Settings → AI. Empty = defaults.
        let scriptPathOverride = UserDefaults.standard.string(forKey: "whisperScriptPath")
        let scriptPath = (scriptPathOverride?.isEmpty == false) ? scriptPathOverride : nil
        let model = UserDefaults.standard.string(forKey: "whisperModel") ?? "turbo"
        Task {
            do {
                let doc = try await WhisperService.transcribe(
                    file: URL(fileURLWithPath: asset.path),
                    model: model,
                    scriptPath: scriptPath
                )
                try await MainActor.run {
                    try db.saveTranscript(doc, assetId: id)
                    transcript = doc
                    if generateMarkers {
                        for seg in doc.segments {
                            _ = try? db.addMarker(
                                assetId: id, timecodeIn: seg.start,
                                timecodeOut: seg.end, note: seg.text
                            )
                        }
                        markers = try db.markers(assetId: id)
                    }
                    aiStatus = "Transcribed \(doc.segments.count) segments"
                    aiSheetState = .transcriptReady(doc: doc, assetName: asset.filename)
                }
            } catch {
                await MainActor.run {
                    aiStatus = "Transcription failed: \(error.localizedDescription)"
                    aiSheetState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - AI: Ollama auto-describe

    func autoDescribeSelected() {
        guard let asset = selectedAsset, let id = asset.rowId else { return }
        aiSheetState = .describing(filename: asset.filename)
        aiStatus = "Calling local LLM…"
        let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? OllamaService.defaultModel
        Task {
            do {
                let snippet = transcript?.fullText
                let description = try await OllamaService.describe(
                    filename: asset.filename,
                    transcriptSnippet: snippet,
                    model: model
                )
                await MainActor.run {
                    let starsNow = rating?.stars ?? 0
                    try? db.setRating(assetId: id, stars: starsNow,
                                       colorLabel: rating?.colorLabel,
                                       description: description)
                    self.rating = try? db.rating(assetId: id)
                    aiStatus = "Description generated."
                    aiSheetState = .describeReady(
                        text: description, assetName: asset.filename
                    )
                }
            } catch {
                await MainActor.run {
                    aiStatus = "LLM failed: \(error.localizedDescription)"
                    aiSheetState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - AI: Similar takes

    @Published var similarClusters: [SimilarTakeCluster] = []

    func findSimilarTakes() {
        aiSheetState = .findingSimilar(progress: 0, total: 0)
        Task {
            var ratingsById: [Int64: Rating] = [:]
            for a in assets {
                if let id = a.rowId, let r = try? db.rating(assetId: id) {
                    ratingsById[id] = r
                }
            }
            let clusters = await SimilarTakesService.findClusters(
                assets: assets,
                ratings: ratingsById,
                onProgress: { done, total in
                    Task { @MainActor in
                        self.aiSheetState = .findingSimilar(progress: done, total: total)
                    }
                }
            )
            await MainActor.run {
                self.similarClusters = clusters
                self.aiSheetState = .similarReady(count: clusters.count)
            }
        }
    }

    // MARK: - FCPXML export

    enum FCPXMLExportScope {
        case allCatalogued
        case selectedOnly
    }

    @Published var lastFCPXMLExportPath: URL?

    /// Build a Send-to-FCP package: gather every asset (or just the
    /// selection) plus its markers, subclips, tags, and rating, write
    /// the FCPXML to `~/Downloads/PurpleReel/exports/`, and (optionally)
    /// hand it to Final Cut Pro via `open -a`.
    @discardableResult
    func exportFCPXML(scope: FCPXMLExportScope, openInFCP: Bool) -> URL? {
        let targetAssets: [Asset]
        switch scope {
        case .allCatalogued: targetAssets = assets
        case .selectedOnly:
            if let a = selectedAsset { targetAssets = [a] } else { return nil }
        }
        guard !targetAssets.isEmpty else { return nil }

        var items: [FCPXMLExportInput] = []
        items.reserveCapacity(targetAssets.count)
        for a in targetAssets {
            guard let id = a.rowId else { continue }
            let m = (try? db.markers(assetId: id)) ?? []
            let s = (try? db.subclips(parentAssetId: id)) ?? []
            let t = (try? db.tags(assetId: id)) ?? []
            let r = (try? db.rating(assetId: id)) ?? nil
            items.append(FCPXMLExportInput(asset: a, markers: m, subclips: s, tags: t, rating: r))
        }
        guard !items.isEmpty else { return nil }

        do {
            let dir = try fcpxmlExportDirectory()
            let stamp = exportTimestamp()
            let eventName = scope == .allCatalogued
                ? "PurpleReel Library \(stamp)"
                : "PurpleReel — \(targetAssets[0].filename)"
            let url = dir.appendingPathComponent("PurpleReel_\(stamp).fcpxml")
            try FCPXMLWriter.write(
                eventName: eventName,
                items: items,
                toolVersion: AppVersion.marketing,
                to: url
            )
            lastFCPXMLExportPath = url
            if openInFCP {
                let fcpURL = URL(fileURLWithPath: "/Applications/Final Cut Pro.app")
                if FileManager.default.fileExists(atPath: fcpURL.path) {
                    NSWorkspace.shared.open([url], withApplicationAt: fcpURL,
                                              configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return url
        } catch {
            NSLog("[PurpleReel] FCPXML export failed: \(error)")
            return nil
        }
    }

    private func fcpxmlExportDirectory() throws -> URL {
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = downloads.appendingPathComponent("PurpleReel/exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func exportTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }

    // MARK: - Transcode

    func transcodeSelected(preset: TranscodePreset) {
        guard let asset = selectedAsset else { return }
        do {
            let dir = try TranscodeService.defaultOutputDirectory()
            let out = TranscodeService.outputURL(for: URL(fileURLWithPath: asset.path),
                                                  preset: preset, in: dir)
            let job = TranscodeJob(source: URL(fileURLWithPath: asset.path),
                                    preset: preset, outputURL: out)
            transcodeQueue.enqueue(job)
            transcodeSheetVisible = true
        } catch {
            NSLog("[PurpleReel] transcode enqueue failed: \(error)")
        }
    }

    func setDescription(_ text: String) {
        guard let id = selectedAsset?.rowId else { return }
        let stars = rating?.stars ?? 0
        let color = rating?.colorLabel
        try? db.setRating(assetId: id, stars: stars,
                          colorLabel: color,
                          description: text.isEmpty ? nil : text)
        refreshRating()
    }
}
