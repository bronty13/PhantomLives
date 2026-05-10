import SwiftUI
import UniformTypeIdentifiers
import PurpleDedupCore

/// Three-pane shell (Phase 4.5): sources sidebar · cluster list · comparison pane.
/// Built on `NavigationSplitView` for native column-resize gestures and the
/// macOS-standard sidebar appearance. Cluster selection in the middle column
/// drives the comparison pane on the right.
///
/// The top toolbar holds the controls that govern *all* scans (sources, scan
/// trigger, threshold steppers, cache stats). The cluster list is where you
/// scan for matches; the comparison pane is where you decide what to do about
/// any single one. Phase 5 adds the cleanup-action UI in the comparison pane.
struct ContentView: View {
    @ObservedObject var settingsStore: SettingsStore

    @State private var sources: [ScanSource] = []
    @State private var hydratedFromSettings = false
    @State private var exactClusters: [ExactClusterer.Cluster] = []
    @State private var similarClusters: [PerceptualClusterer.Cluster] = []
    @State private var similarVideoClusters: [VideoClusterer.Cluster] = []
    @State private var totalScanned: Int = 0
    @State private var statusMessage: String = "Drop folders into the sidebar, then click Scan."
    @State private var isScanning: Bool = false
    /// Handle to the currently-running scan task so the user can cancel
    /// from the toolbar. The engine respects `Task.checkCancellation()`
    /// in the walker; cancellation propagates through the async chain.
    @State private var scanTask: Task<Void, Never>? = nil
    /// Set when the user clicks Cancel — used by the toolbar to switch
    /// the button to a Force Quit option after a few seconds if the
    /// scan hasn't responded. Some non-cancellable phases (a slow
    /// SQLite read against a 100k+-row cache, a large-file hash that's
    /// already in flight) can take longer than the user is willing to
    /// wait, so we offer a brutal exit() escape hatch.
    @State private var cancelRequestedAt: Date? = nil
    @State private var progressLine: String = ""
    @State private var cacheLine: String = ""
    @State private var stageTiming: String = ""
    /// Photos-filter resolution diagnostic. Set right before the scan
    /// runs so the user can see how many basenames the filter produced
    /// and which fetch path won (smart album vs full-walk fallback).
    /// Persists in the status strip alongside the cache stats so the
    /// engine's cacheLine update doesn't clobber it.
    @State private var photosFilterLine: String = ""
    @State private var includeSimilar: Bool = true
    @State private var includeSimilarVideos: Bool = true
    @State private var threshold: Int = PerceptualClusterer.defaultThreshold
    @State private var videoThreshold: Int = VideoClusterer.defaultThreshold

    /// The user's current cluster selection in the left column. Drives the
    /// comparison pane on the right. Nil = no cluster selected (placeholder shown).
    @State private var selectedClusterID: String? = nil

    /// Engine recommendations per cluster (run on demand when a cluster is first
    /// selected) and per-cluster manual overrides. Both keyed by cluster ID.
    @State private var decisionsByCluster: [String: ClusterDecisions] = [:]
    @State private var manualOverrides: [String: [URL: Decision]] = [:]
    @State private var showPreflight: Bool = false
    @State private var lastTrashOperation: [TrashedFile] = []  // for undo
    @State private var isDropTargeted: Bool = false
    @State private var burstClusters: [BurstClusterer.Cluster] = []
    @State private var burstScanInProgress: Bool = false
    @State private var rotatedClusters: [RotatedClusterer.Cluster] = []
    @State private var rotatedScanInProgress: Bool = false
    /// When true, the cluster list filters to clusters whose members come
    /// from 2+ different scan sources. Useful for "is this photo BOTH in
    /// my Photos library AND on disk somewhere else?" questions.
    @State private var crossSourceFilterOn: Bool = false

    /// Filter sheet state. Single Identifiable state value drives
    /// `.sheet(item:)` — assignment is atomic so the sheet content
    /// always sees a non-nil URL when it renders. (An earlier paired
    /// `URL? + Bool` approach raced: the sheet body evaluated the URL
    /// optional before SwiftUI committed the assignment, producing an
    /// empty white sheet.)
    @State private var photoFilterSheetItem: PhotoFilterSheetItem? = nil

    /// Identifiable wrapper for the filter sheet's URL. Lives at the
    /// instance level (not nested) so SwiftUI's diffing has a stable
    /// type identity across body evaluations.
    struct PhotoFilterSheetItem: Identifiable, Hashable {
        let url: URL
        var id: String { url.path }
    }

    /// Reference index of content hashes from any lookup-mode Photos library
    /// sources. Populated by the scan; ComparisonView reads from this to
    /// render the "Also in Photos library" badge per file. Empty when no
    /// lookup source is configured.
    @State private var photosLookupHashes: Set<String> = []
    @State private var photosLookupCount: Int = 0

    /// Paths of cluster members whose content hash is in `photosLookupHashes`.
    /// Engine-populated. Lets the sidebar "In Photos" badge fire on non-exact
    /// clusters when at least one member is byte-identical to a Photos library
    /// asset. Empty when no lookup source is configured.
    @State private var clusterMembersInLookup: Set<String> = []

    /// Current PhotoKit auth status, refreshed on appear and after the user
    /// requests access. Drives the "Grant access" button vs "Open Privacy
    /// Settings" button in the Photos hint banner.
    @State private var photosAuthStatus: PhotoKitDeletionService.Authorization = .notDetermined

    /// When non-empty, the preflight sheet shows THIS subset instead of the full
    /// `filesToDelete` list. Set by the per-cluster and per-file trash actions
    /// before they raise the sheet; cleared on confirm/cancel/dismiss. The bulk
    /// "Trash N" toolbar button leaves it empty so the existing aggregate view
    /// keeps working unchanged.
    @State private var pendingTrashSubset: [DiscoveredFile] = []

    var body: some View {
        // Layered to keep each `body`-level expression under the SwiftUI type-
        // check budget on macOS Tahoe. Each layer adds a small group of
        // modifiers and is independently type-checked, dodging the
        // "compiler unable to type-check this expression" error that long
        // modifier chains produce.
        bodyTopLayer
    }

    @ViewBuilder
    private var bodyTopLayer: some View {
        bodyMiddleLayer
            .sheet(isPresented: $showPreflight) { preflightSheet }
            .background { keyboardShortcutHost }
    }

    @ViewBuilder
    private var bodyMiddleLayer: some View {
        bodyBottomLayer
            .onChange(of: decisionsByCluster) { _, _ in saveSessionState() }
            .onChange(of: manualOverrides) { _, _ in saveSessionState() }
    }

    @ViewBuilder
    private var bodyBottomLayer: some View {
        splitView
            .onAppear { hydrateFromSettingsIfNeeded() }
            .onChange(of: sources.map(\.url.path)) { _, paths in
                settingsStore.settings.lastSourcePaths = paths
            }
            .onChange(of: threshold) { _, v in settingsStore.settings.photoThreshold = v }
            .onChange(of: videoThreshold) { _, v in settingsStore.settings.videoThreshold = v }
            .onChange(of: includeSimilar) { _, v in settingsStore.settings.includeSimilarPhotos = v }
            .onChange(of: includeSimilarVideos) { _, v in settingsStore.settings.includeSimilarVideos = v }
    }

    /// The NavigationSplitView + toolbar bundle. Pulled out of `body` so the
    /// compiler can specialise each expression independently.
    @ViewBuilder
    private var splitView: some View {
        NavigationSplitView {
            clusterListColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
        } detail: {
            comparisonColumn
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if isScanning {
                    if let requestedAt = cancelRequestedAt,
                       Date().timeIntervalSince(requestedAt) > 4 {
                        // Soft cancel didn't take effect within 4 s.
                        // Offer a hard exit — the cache flushes on every
                        // batch, so killing mid-scan is safe.
                        Button {
                            exit(0)
                        } label: {
                            Label("Force quit", systemImage: "xmark.octagon.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .help("The scan didn't respond to Cancel — terminate the process. The on-disk SQLite cache is flushed per batch, so the next launch picks up cleanly.")
                    } else {
                        Button {
                            scanTask?.cancel()
                            scanTask = nil
                            cancelRequestedAt = Date()
                            statusMessage = "Cancelling…"
                        } label: {
                            Label("Cancel", systemImage: "stop.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop the running scan (⌘.). The cache keeps whatever's already been hashed, so re-running picks up where this left off.")
                    }
                } else {
                    Button {
                        scanTask = Task { await runScan() }
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(sources.isEmpty)
                    .keyboardShortcut("s", modifiers: .command)
                    .help(sources.isEmpty
                          ? "Add at least one source folder before scanning"
                          : "Scan all sources for duplicates (⌘S)")
                }
            }
            ToolbarItemGroup(placement: .principal) {
                // Each kind has a labeled Menu (named presets) AND a Stepper
                // (fine adjustment). The bare-stepper version had two unlabeled
                // arrow buttons that the user had no way to interpret; this
                // shows the threshold's *meaning* up front.
                Toggle("Photos", isOn: $includeSimilar)
                    .toggleStyle(.checkbox).disabled(isScanning)
                thresholdMenu(value: $threshold, enabled: !isScanning && includeSimilar,
                              tooltip: "Photo similarity threshold (Hamming distance on the 64-bit pHash)")
                Toggle("Videos", isOn: $includeSimilarVideos)
                    .toggleStyle(.checkbox).disabled(isScanning)
                thresholdMenu(value: $videoThreshold, enabled: !isScanning && includeSimilarVideos,
                              tooltip: "Video similarity threshold (mean Hamming distance over aligned frames)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if isScanning { ProgressView().controlSize(.small) }
                if (pendingDeleteCount ?? 0) > 0 || !exactClusters.isEmpty || !similarClusters.isEmpty || !similarVideoClusters.isEmpty || !burstClusters.isEmpty || !rotatedClusters.isEmpty {
                    Button { savePlanJSON() } label: {
                        Label("Save plan…", systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("FR-5.9 dry run — write every cluster + decision to a JSON file. Nothing is moved.")
                }
                if let count = pendingDeleteCount, count > 0 {
                    let stage = settingsStore.settings.stageFolderPath ?? ""
                    let label = stage.isEmpty ? "Trash \(count)" : "Stage \(count)"
                    Button { showPreflight = true } label: {
                        Label(label, systemImage: stage.isEmpty ? "trash" : "tray.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .help(stage.isEmpty
                          ? "Move all files marked DELETE to the Trash"
                          : "Move all files marked DELETE to the configured stage folder (Settings → Engine)")
                }
                if !lastTrashOperation.isEmpty {
                    Button { Task { await undoLastTrash() } } label: {
                        Label("Undo \(lastTrashOperation.count)", systemImage: "arrow.uturn.backward")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Restore the last batch from Trash to their original locations")
                    .keyboardShortcut("z", modifiers: .command)
                }
            }
        }
        .navigationTitle("PurpleDedup")
        .navigationSubtitle(currentSummary)
    }

    // MARK: - threshold control

    /// Compact threshold control: Menu chip shows ONLY the number. The named
    /// definitions ("Strict", "Very similar", etc.) appear in the dropdown
    /// items so the user can pick by intent rather than guess at numbers, but
    /// the toolbar itself stays narrow enough to keep Scan on-screen on
    /// laptop-sized windows. The tooltip names the current band so hover
    /// already explains the value without opening the menu.
    @ViewBuilder
    private func thresholdMenu(value: Binding<Int>, enabled: Bool, tooltip: String) -> some View {
        HStack(spacing: 2) {
            Menu {
                Button("Strict (3) — only nearly-identical")     { value.wrappedValue = 3 }
                Button("Very similar (6) — default")             { value.wrappedValue = 6 }
                Button("Loose (10) — small edits / crops")       { value.wrappedValue = 10 }
                Button("Very loose (14) — same scene")           { value.wrappedValue = 14 }
            } label: {
                Text("\(value.wrappedValue)")
                    .font(.callout.monospaced())
                    .frame(minWidth: 14)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("\(tooltip) — currently \(thresholdLabel(value.wrappedValue)) (\(value.wrappedValue)). Click for presets.")
            Stepper("threshold", value: value, in: 0...32)
                .labelsHidden()
        }
        .disabled(!enabled)
    }

    /// Map a numeric Hamming-distance threshold to a human label. Bands chosen
    /// to match the requirements-doc semantics — anything <3 is treated as
    /// "Identical-ish" (most files will need >=3 because re-saves perturb a
    /// few bits even from the same source bytes).
    private func thresholdLabel(_ n: Int) -> String {
        switch n {
        case ...2:  return "Identical"
        case 3...5: return "Strict"
        case 6...9: return "Very similar"
        case 10...13: return "Loose"
        default:    return "Very loose"
        }
    }

    // MARK: - sources strip (top of cluster column)

    /// Always-visible sources control. Sits at the top of the cluster column so
    /// the user can never wonder where to add a folder. Compact when there are
    /// sources (one chip per source); promotes the empty state with a clear CTA
    /// when there aren't any.
    ///
    /// `.onDrop` lives on the dashed-rectangle empty state and on the populated
    /// list view so drag-drop hits the same surface the user is looking at.
    /// Putting it on the parent NavigationSplitView wasn't reliable — SwiftUI's
    /// split-view columns each have their own drop region and intercept events
    /// before the parent sees them.
    private var sourcesStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sources").font(.subheadline.bold())
                if isDropTargeted {
                    Text("· drop to add")
                        .font(.caption).foregroundStyle(.blue)
                }
                Spacer()
                Menu {
                    Button {
                        pickFolder()
                    } label: {
                        Label("Add folder…", systemImage: "folder")
                    }
                    Button {
                        pickPhotosLibrary()
                    } label: {
                        Label("Add Photos library…", systemImage: "photo.on.rectangle.angled")
                    }
                } label: {
                    Label("Add…", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a regular folder or your Apple Photos library (.photoslibrary)")
            }
            if sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isDropTargeted ? "Release to add" : "Drag folders or a Photos library here")
                        .font(.callout)
                        .foregroundStyle(isDropTargeted ? .blue : .secondary)
                    Text("…or click Add… above. Photos libraries (.photoslibrary) live in ~/Pictures by default.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isDropTargeted ? Color.blue : Color.secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [4]))
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sources, id: \.url) { src in
                        HStack(spacing: 6) {
                            Image(systemName: src.isPhotosLibrary
                                  ? "photo.on.rectangle.angled"
                                  : (src.isLocked ? "lock.fill" : "folder"))
                                .foregroundStyle(src.isPhotosLibrary
                                                 ? .purple
                                                 : (src.isLocked ? .orange : .primary))
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(src.url.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1).truncationMode(.middle)
                                        .foregroundStyle(.secondary)
                                    if src.isLookupOnly {
                                        Text("(lookup only)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.purple)
                                    }
                                }
                                if src.isPhotosLibrary,
                                   let f = settingsStore.settings.photoLibraryFilters[src.url.path],
                                   f.isActive {
                                    Text(f.summary)
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                        .lineLimit(1).truncationMode(.tail)
                                }
                            }
                            Spacer()
                            // Lookup-only mode toggle for Photos libraries.
                            // When ON: library acts as a reference index;
                            // folder duplicates that also live in Photos
                            // get an "In Photos" badge. Files in the
                            // library never appear in clusters / DELETE.
                            if src.isPhotosLibrary {
                                Button {
                                    toggleLookupOnly(for: src.url)
                                } label: {
                                    Image(systemName: src.isLookupOnly
                                          ? "magnifyingglass.circle.fill"
                                          : "magnifyingglass.circle")
                                        .foregroundStyle(src.isLookupOnly ? .purple : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .help(src.isLookupOnly
                                      ? "Lookup-only mode: this library tags folder duplicates that already live in Photos. Click to make it a regular scan source."
                                      : "Treat this library as a lookup reference: scan folders for duplicates and tag any that already live in Photos.")
                            }
                            // Filter funnel for Photos libraries — opens
                            // the sheet to pick albums / subtypes /
                            // favorites / hidden.
                            if src.isPhotosLibrary {
                                let active = settingsStore.settings.photoLibraryFilters[src.url.path]?.isActive == true
                                Button {
                                    if photoFilterSheetItem?.url == src.url {
                                        photoFilterSheetItem = nil
                                    } else {
                                        photoFilterSheetItem = PhotoFilterSheetItem(url: src.url)
                                    }
                                } label: {
                                    Image(systemName: active
                                          ? "line.3.horizontal.decrease.circle.fill"
                                          : "line.3.horizontal.decrease.circle")
                                        .foregroundStyle(active ? .purple : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Filter this Photos library by album, subtype, favorites, or hidden state")
                            }
                            Button {
                                sources.removeAll { $0.url == src.url }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove this source")
                        }
                    }
                }
                if sources.contains(where: \.isPhotosLibrary) {
                    photosLibraryHint
                }
                // Filter editor lives at the cluster column level now —
                // when open it replaces the sources strip + cluster list
                // entirely so its sticky footer is always reachable. See
                // `clusterListColumn` for the conditional swap.
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            // Wrapping the populated-state too: when there are already sources,
            // the user can still drop more folders on the strip and they'll be
            // appended to the list.
            handleDrop(providers: providers)
        }
    }

    /// Shown when at least one Apple Photos library is in the scan sources.
    /// Adapts to whichever mode the source was added in: locked (PhotoKit
    /// auth was denied / not requested → read-only display) vs unlocked
    /// (auth granted → marked-DELETE files queue in Photos.app's album).
    /// When auth is missing, surfaces an inline button that either prompts
    /// (notDetermined) or jumps to System Settings (denied/restricted) so
    /// the user doesn't have to leave the app to navigate menus.
    private var photosLibraryHint: some View {
        let anyUnlocked = sources.contains { $0.isPhotosLibrary && !$0.isLocked }
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                if anyUnlocked {
                    Text("Photos library: action queued in Photos.app.")
                        .font(.caption.bold())
                    Text("Files you mark DELETE will land in the \"Marked for Deletion in PurpleDedup\" album. Open Photos.app and delete from that album to finalise.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("PurpleDedup needs Photos access.")
                        .font(.caption.bold())
                    Text(authHintMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            Task { await requestPhotosAccess() }
                        } label: {
                            Label("Grant Photos access", systemImage: "checkmark.shield")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.purple)
                        if photosAuthStatus == .denied || photosAuthStatus == .restricted {
                            Button {
                                Task { await resetPhotosPermission() }
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Run tccutil reset Photos to clear any stale denial — needed when the app doesn't appear in Privacy Settings.")
                            Button {
                                openPhotosPrivacySettings()
                            } label: {
                                Label("Settings", systemImage: "gear")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(8)
        // Vibrancy material + a subtle purple-tinted stroke. Plain
        // Color.purple.opacity(0.08) was nearly invisible in dark mode and
        // pure-flat in light mode; .thinMaterial picks up the desktop and
        // the accent overlay tints it without going saturated.
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.top, 4)
        .onAppear { photosAuthStatus = PhotoKitDeletionService.shared.currentStatus() }
    }

    /// Toggle a source's `isLookupOnly` mode. Replaces the source in the
    /// list (since `ScanSource` is immutable) preserving its other fields.
    /// The user's settings.lastSourcePaths persistence is by URL path so
    /// the mode change is captured on next save.
    private func toggleLookupOnly(for url: URL) {
        guard let idx = sources.firstIndex(where: { $0.url == url }) else { return }
        let old = sources[idx]
        sources[idx] = ScanSource(
            url: old.url,
            isLocked: old.isLocked,
            allowedBasenames: old.allowedBasenames,
            isLookupOnly: !old.isLookupOnly
        )
        // Lookup-mode source switches off "show lookup match" badges from
        // the previous scan since the index would be stale; clearing here
        // means the user sees a clean state until they re-scan.
        if !old.isLookupOnly {
            photosLookupHashes = []
            photosLookupCount = 0
            clusterMembersInLookup = []
        }
    }

    /// Body copy for the auth-denied banner. Computed instead of inline
    /// switch-in-Group to keep the SwiftUI body size small — the bigger
    /// `photosLibraryHint` body was making layout misbehave on Tahoe.
    private var authHintMessage: String {
        switch photosAuthStatus {
        case .notDetermined:
            return "Click Grant Photos access — macOS will show its prompt. Without it, your Photos library is treated as read-only."
        case .denied, .restricted:
            return "Photos access was denied — and PurpleDedup may not even appear in System Settings → Privacy → Photos yet (the OS records a deny before the entry is created). Click Reset below to clear the stale record, then Grant to get the system prompt."
        case .authorized, .limited:
            return "Granted — re-scan to populate clusters with Photos library data."
        }
    }

    /// Jump directly to the Photos pane in System Settings → Privacy &
    /// Security. The URL scheme is documented internally on macOS — the
    /// only invariant is that opening any settings pane requires the
    /// `x-apple.systempreferences:` scheme.
    private func openPhotosPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Run `tccutil reset Photos com.bronty13.PurpleDedup` to clear any
    /// stale TCC entry. This is the recovery path for when:
    ///   1. The app was launched in an earlier build that lacked the
    ///      `com.apple.security.personal-information.photos-library`
    ///      entitlement → macOS recorded a silent deny without ever
    ///      prompting → the app doesn't appear in Privacy Settings.
    ///   2. The user clicked "Don't Allow" on the system prompt and now
    ///      wants to be asked again without hunting through Settings.
    /// After the reset, immediately re-issue `requestAuthorization`. From
    /// the user's POV: one click resets and re-prompts.
    private func requestPhotosAccess() async {
        let status = await PhotoKitDeletionService.shared.requestAuthorization()
        photosAuthStatus = status
        if status == .authorized || status == .limited {
            for (idx, src) in sources.enumerated() where src.isPhotosLibrary {
                sources[idx] = ScanSource(
                    url: src.url,
                    isLocked: false,
                    allowedBasenames: src.allowedBasenames,
                    isLookupOnly: src.isLookupOnly
                )
            }
        }
    }

    private func resetPhotosPermission() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Photos", PurpleDedup.bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("tccutil reset failed: \(error.localizedDescription, privacy: .public)")
        }
        // Status is now .notDetermined; immediately re-request so the
        // user gets the system prompt without an extra click.
        let status = await PhotoKitDeletionService.shared.requestAuthorization()
        photosAuthStatus = status
        if status == .authorized || status == .limited {
            for (idx, src) in sources.enumerated() where src.isPhotosLibrary {
                sources[idx] = ScanSource(
                    url: src.url,
                    isLocked: false,
                    allowedBasenames: src.allowedBasenames,
                    isLookupOnly: src.isLookupOnly
                )
            }
        }
    }

    // MARK: - middle column: cluster list

    private var clusterListColumn: some View {
        GeometryReader { geo in
            // When the filter editor is open, it takes over the entire
            // sidebar so the footer (Reset / Cancel / Apply) is always
            // reachable regardless of window height. The ScrollView
            // inside the editor handles long album lists; the footer
            // stays sticky at the bottom of the column. Closing the
            // editor (Apply / Cancel / clicking the funnel again)
            // restores the regular sources + clusters layout.
            if let item = photoFilterSheetItem,
               sources.contains(where: { $0.url == item.url }) {
                PhotoLibraryFilterSheet(
                    libraryURL: item.url,
                    filter: Binding(
                        get: { settingsStore.settings.photoLibraryFilters[item.url.path] ?? PhotoLibraryFilter() },
                        set: { newValue in
                            if newValue.isActive {
                                settingsStore.settings.photoLibraryFilters[item.url.path] = newValue
                            } else {
                                settingsStore.settings.photoLibraryFilters.removeValue(forKey: item.url.path)
                            }
                        }
                    ),
                    onClose: { photoFilterSheetItem = nil }
                )
                .padding(8)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            } else {
                clusterListColumnContent(geo: geo)
            }
        }
    }

    @ViewBuilder
    private func clusterListColumnContent(geo: GeometryProxy) -> some View {
        // GeometryReader on Tahoe (macOS 26.x) forces the sidebar's
        // content height to match the visible window — without it,
        // NSSplitViewItem reports content as ~2× the window and pushes
        // the sources strip off the top. The outer reader is shared
        // with the filter-editor branch so we don't double-wrap.
        VStack(alignment: .leading, spacing: 0) {
            sourcesStrip
            Divider()
            statusStrip
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            if !exactClusters.isEmpty || !similarClusters.isEmpty || !similarVideoClusters.isEmpty {
                bulkActionsStrip
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            if exactClusters.isEmpty && similarClusters.isEmpty && similarVideoClusters.isEmpty {
                emptyClusterState
            } else {
                List(selection: $selectedClusterID) {
                    let visibleExact = exactClusters.filter { shouldShow(clusterID: "exact:\($0.contentHashHex)") }
                    let visibleSimilar = similarClusters.filter { shouldShow(clusterID: "photo:\($0.stableID)") }
                    let visibleVideos = similarVideoClusters.filter { shouldShow(clusterID: "video:\($0.stableID)") }
                    let visibleBursts = burstClusters.filter { shouldShow(clusterID: "burst:\($0.stableID)") }
                    let visibleRotated = rotatedClusters.filter { shouldShow(clusterID: "rotated:\($0.stableID)") }
                    if !visibleExact.isEmpty {
                        Section("Exact duplicates (\(visibleExact.count))") {
                            ForEach(visibleExact, id: \.contentHashHex) { cluster in
                                clusterRow(
                                    id: "exact:\(cluster.contentHashHex)",
                                    title: "\(cluster.files.count) copies · \(formatBytes(cluster.sizeBytes))",
                                    subtitle: "hash \(cluster.contentHashHex.prefix(12))…",
                                    accentColor: .green
                                )
                                .tag("exact:\(cluster.contentHashHex)")
                            }
                        }
                    }
                    if !visibleSimilar.isEmpty {
                        Section("Similar photos (\(visibleSimilar.count))") {
                            ForEach(visibleSimilar, id: \.stableID) { cluster in
                                clusterRow(
                                    id: "photo:\(cluster.stableID)",
                                    title: "\(cluster.files.count) variants · ~\(formatBytes(cluster.totalReclaimableBytes))",
                                    subtitle: "diameter \(cluster.maxPairwiseDistance)/64",
                                    accentColor: .blue
                                )
                                .tag("photo:\(cluster.stableID)")
                            }
                        }
                    }
                    if !visibleVideos.isEmpty {
                        Section("Similar videos (\(visibleVideos.count))") {
                            ForEach(visibleVideos, id: \.stableID) { cluster in
                                clusterRow(
                                    id: "video:\(cluster.stableID)",
                                    title: "\(cluster.files.count) variants · ~\(formatBytes(cluster.totalReclaimableBytes))",
                                    subtitle: "mean dist \(cluster.maxPairwiseMeanDistance)/64",
                                    accentColor: .purple
                                )
                                .tag("video:\(cluster.stableID)")
                            }
                        }
                    }
                    if !visibleBursts.isEmpty {
                        Section("Burst series (\(visibleBursts.count))") {
                            ForEach(visibleBursts, id: \.stableID) { cluster in
                                clusterRow(
                                    id: "burst:\(cluster.stableID)",
                                    title: "\(cluster.files.count) shots · ~\(formatBytes(cluster.totalReclaimableBytes))",
                                    subtitle: "\(String(format: "%.1f", cluster.durationSeconds))s window · diameter \(cluster.maxPairwiseDistance)/64",
                                    accentColor: .orange
                                )
                                .tag("burst:\(cluster.stableID)")
                            }
                        }
                    }
                    if !visibleRotated.isEmpty {
                        Section("Rotated duplicates (\(visibleRotated.count))") {
                            ForEach(visibleRotated, id: \.stableID) { cluster in
                                clusterRow(
                                    id: "rotated:\(cluster.stableID)",
                                    title: "\(cluster.files.count) copies · ~\(formatBytes(cluster.totalReclaimableBytes))",
                                    subtitle: "rotated " + cluster.rotationsRelativeToFirst.dropFirst().map { "\($0)°" }.joined(separator: " / "),
                                    accentColor: .pink
                                )
                                .tag("rotated:\(cluster.stableID)")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
    }

    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duplicates").font(.headline)
            Text(statusMessage).font(.callout).foregroundStyle(.secondary)
            if !progressLine.isEmpty {
                Text(progressLine).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !stageTiming.isEmpty {
                Text(stageTiming).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !cacheLine.isEmpty {
                Text(cacheLine).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !photosFilterLine.isEmpty {
                Text(photosFilterLine).font(.caption.monospaced()).foregroundStyle(.purple)
            }
        }
    }

    /// Bulk-action buttons that operate over EVERY cluster in the current
    /// scan. "Apply" runs the rule chain on every cluster (lazy — already-
    /// decided clusters short-circuit). "Clear overrides" wipes manual
    /// decisions everywhere. "Find bursts" extracts capture dates and
    /// runs the burst-series clusterer on photos not already in another
    /// cluster.
    private var bulkActionsStrip: some View {
        HStack(spacing: 6) {
            Button {
                Task { await applyRecommendationToAllClusters() }
            } label: {
                Label("Apply to all", systemImage: "wand.and.stars")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Run the rule chain on every cluster (\(allClusterIDs.count) groups). Manual overrides are preserved.")

            Button {
                manualOverrides.removeAll()
            } label: {
                Label("Clear overrides", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(manualOverrides.isEmpty)
            .help("Reset every manual KEEP/DELETE override back to the engine's recommendation")

            Button {
                Task { await runBurstDetection() }
            } label: {
                if burstScanInProgress {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Finding…")
                    }
                    .font(.caption)
                } else {
                    Label("Find bursts", systemImage: "rectangle.stack")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(burstScanInProgress || photosInScan.isEmpty)
            .help("Find rapid-fire photo series the perceptual matcher misses. Reads EXIF capture dates lazily — only runs when you click.")

            Button {
                Task { await runRotatedDetection() }
            } label: {
                if rotatedScanInProgress {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Finding…")
                    }
                    .font(.caption)
                } else {
                    Label("Find rotated", systemImage: "rotate.right")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(rotatedScanInProgress || photosInScan.isEmpty)
            .help("Find photos that are exact-content duplicates of each other under 90/180/270° rotation. Re-hashes photos with all four rotations.")

            // Cross-source filter — only matters when there are 2+ scan
            // sources. Off by default; flips the cluster list to show only
            // clusters whose files live in multiple sources (Photos library
            // + folder, or two folders).
            if sources.count >= 2 {
                Toggle(isOn: $crossSourceFilterOn) {
                    Label("Cross-source only", systemImage: "link")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show only clusters whose files come from 2+ different scan sources — files duplicated between e.g. your Photos library and a folder.")
            }
            Spacer()
        }
    }

    private func applyRecommendationToAllClusters() async {
        let ids = allClusterIDs
        // Run sequentially to avoid clobbering @State writes from many tasks.
        // Each call is fast (already-decided clusters short-circuit), and the
        // total stays well under a second on the test folder.
        for id in ids where decisionsByCluster[id] == nil {
            await ensureDecisions(for: id)
        }
    }

    private var emptyClusterState: some View {
        // No `maxHeight: .infinity` here — on Tahoe (macOS 26.x),
        // NSSplitViewItem treats that as an unbounded intrinsic content
        // size and sizes the whole sidebar at ~2× the window height,
        // which pushes the sources strip off the top of the visible
        // window. Natural sizing with vertical padding gets the same
        // visual placement (centered-feeling empty state) without
        // breaking the column layout.
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36)).foregroundStyle(.secondary.opacity(0.4))
            Text(sources.isEmpty
                 ? "Add a source folder above to begin."
                 : isScanning ? "Scanning…" : "Click Scan in the toolbar to find duplicates.")
                .foregroundStyle(.secondary).font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Single row in the middle column. Tag-based selection drives `selectedClusterID`
    /// directly via `List(selection:)` — we don't manage expansion state any more
    /// because the comparison pane on the right shows the full file list.
    private func clusterRow(id: String, title: String, subtitle: String, accentColor: Color) -> some View {
        let crossSource = isClusterCrossSource(id: id)
        let archivedInPhotos = isClusterArchivedInPhotos(id: id)
        return HStack(spacing: 8) {
            Circle().fill(accentColor.opacity(0.7)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.body)
                    if crossSource {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                            .help("Files in this cluster span multiple scan sources")
                    }
                    if archivedInPhotos {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("At least one file in this cluster is also archived in your Photos library — safe to delete the folder copy.")
                    }
                }
                Text(subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if decisionsByCluster[id] != nil {
                // The cluster has a recommendation; checkmark colour mirrors
                // whether the user has manually overridden anything in it
                // (orange = touched, green = engine-default).
                let touched = manualOverrides[id]?.isEmpty == false
                Image(systemName: touched ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(touched ? .orange : .green)
                    .font(.caption)
                    .help(touched ? "Reviewed (with manual override)" : "Reviewed (engine recommendation)")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - selection bridging

    /// Resolve the selected cluster ID into a typed `ClusterSelection` for
    /// `ComparisonView`. The IDs encode the cluster kind as a prefix so we don't
    /// need to maintain a parallel index.
    private var currentSelection: ClusterSelection? {
        guard let id = selectedClusterID else { return nil }
        if id.hasPrefix("exact:") {
            let hash = String(id.dropFirst("exact:".count))
            guard let c = exactClusters.first(where: { $0.contentHashHex == hash }) else { return nil }
            return ClusterSelection(
                id: id, kind: .exact,
                title: "\(c.files.count) byte-identical copies",
                subtitle: "\(formatBytes(c.sizeBytes)) each · sha:\(c.contentHashHex.prefix(12))…",
                files: c.files
            )
        }
        if id.hasPrefix("photo:") {
            let key = String(id.dropFirst("photo:".count))
            guard let c = similarClusters.first(where: { $0.stableID == key }) else { return nil }
            return ClusterSelection(
                id: id, kind: .similarPhoto,
                title: "\(c.files.count) visually similar photos",
                subtitle: "pHash diameter \(c.maxPairwiseDistance)/64 · ~\(formatBytes(c.totalReclaimableBytes)) reclaimable",
                files: c.files
            )
        }
        if id.hasPrefix("video:") {
            let key = String(id.dropFirst("video:".count))
            guard let c = similarVideoClusters.first(where: { $0.stableID == key }) else { return nil }
            return ClusterSelection(
                id: id, kind: .similarVideo,
                title: "\(c.files.count) visually similar videos",
                subtitle: "mean frame distance \(c.maxPairwiseMeanDistance)/64 · ~\(formatBytes(c.totalReclaimableBytes)) reclaimable",
                files: c.files
            )
        }
        if id.hasPrefix("burst:") {
            let key = String(id.dropFirst("burst:".count))
            guard let c = burstClusters.first(where: { $0.stableID == key }) else { return nil }
            let dur = String(format: "%.1f", c.durationSeconds)
            return ClusterSelection(
                id: id, kind: .similarPhoto,   // reuse photo styling/behaviour
                title: "Burst series: \(c.files.count) shots in \(dur)s",
                subtitle: "pHash diameter \(c.maxPairwiseDistance)/64 · ~\(formatBytes(c.totalReclaimableBytes)) reclaimable",
                files: c.files
            )
        }
        if id.hasPrefix("rotated:") {
            let key = String(id.dropFirst("rotated:".count))
            guard let c = rotatedClusters.first(where: { $0.stableID == key }) else { return nil }
            let rotations = c.rotationsRelativeToFirst
                .enumerated()
                .map { "\($0.element)°" }
                .joined(separator: " / ")
            return ClusterSelection(
                id: id, kind: .similarPhoto,
                title: "Rotated copies: \(c.files.count) files",
                subtitle: "rotations \(rotations) · diameter \(c.maxPairwiseDistance)/64 · ~\(formatBytes(c.totalReclaimableBytes)) reclaimable",
                files: c.files
            )
        }
        return nil
    }

    // MARK: - actions

    /// Generic "pick a scannable source" panel. Accepts both regular folders
    /// AND `.photoslibrary` packages — the latter requires special handling
    /// because macOS treats bundles as files (greyed-out and unselectable
    /// in the default folder-picker config). We turn on `canChooseFiles`
    /// (so the bundle isn't greyed) but keep `treatsFilePackagesAsDirectories
    /// = false` (so the panel doesn't navigate INTO the bundle) and then
    /// filter post-selection: accept .photoslibrary OR any directory,
    /// reject everything else.
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose a folder or an Apple Photos library to scan."
        if panel.runModal() == .OK {
            for url in panel.urls {
                addPickedURL(url)
            }
        }
    }

    /// Open the picker pre-aimed at the standard Photos library location so
    /// `.photoslibrary` bundles are easy to find. Falls back to the user's
    /// Pictures folder if the canonical path doesn't resolve.
    private func pickPhotosLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose your Apple Photos library (.photoslibrary)."
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        if let pictures { panel.directoryURL = pictures }
        if panel.runModal() == .OK {
            for url in panel.urls where url.pathExtension.lowercased() == "photoslibrary" {
                addPickedURL(url)
            }
        }
    }

    /// Validate a URL coming out of either picker before sending it through
    /// the auth-aware `addURL`. Folders and `.photoslibrary` bundles are
    /// accepted; anything else is silently dropped to avoid populating the
    /// sources list with junk like a JPEG the user clicked by accident.
    private func addPickedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "photoslibrary" {
            addURL(url)
            return
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            addURL(url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Two paths to extract a URL from the drop. SwiftUI's
        // `loadObject(ofClass: URL.self)` is the canonical one but on
        // macOS Sequoia/Tahoe it fails for folder drops from Finder
        // (Apple bug). The fallback uses `loadDataRepresentation` for the
        // raw "public.file-url" type and decodes the bookmark/path bytes —
        // this works for both files and folders dropped from Finder.
        guard !providers.isEmpty else { return false }
        for p in providers {
            if p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url { addURL(url) }
                }
            } else {
                p.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data = data,
                          let s = String(data: data, encoding: .utf8),
                          let url = URL(string: s) else { return }
                    addURL(url)
                }
            }
        }
        return true
    }

    /// Restore last-session sources, threshold prefs, AND review state on
    /// first window appearance. Idempotent — only runs once per launch
    /// (guarded by `hydratedFromSettings`). When restored sources still
    /// resolve, an automatic scan kicks off so the user can resume review
    /// where they left off without an extra click. The cache makes the
    /// scan ~0.2s on warm runs.
    private func hydrateFromSettingsIfNeeded() {
        guard !hydratedFromSettings else { return }
        hydratedFromSettings = true
        let s = settingsStore.settings
        threshold = s.photoThreshold
        videoThreshold = s.videoThreshold
        includeSimilar = s.includeSimilarPhotos
        includeSimilarVideos = s.includeSimilarVideos

        // Sources first: prune any whose path no longer resolves so a moved/
        // deleted folder doesn't become a ghost row that perpetually fails.
        let fm = FileManager.default
        sources = s.lastSourcePaths.compactMap { path in
            fm.fileExists(atPath: path) ? ScanSource(url: URL(fileURLWithPath: path)) : nil
        }

        // Then load the review snapshot. Cluster IDs in this file refer to
        // clusters from the previous scan; they auto-attach to a fresh scan
        // because IDs are derived from URL/hash content, not from cluster
        // identity. Orphaned entries (cluster no longer exists) are harmless.
        let snap = SessionState.load()
        decisionsByCluster = snap.decisionsByCluster
        manualOverrides = SessionState.decodeOverrides(snap.manualOverridesByCluster)

        if !sources.isEmpty {
            // Auto-scan on launch so the cluster list re-populates immediately
            // and the persisted decisions visibly re-attach. The cache makes
            // this near-instant when nothing's changed; if files have been
            // added/removed, the user sees the delta on screen.
            scanTask = Task { await runScan() }
        }
    }

    private func saveSessionState() {
        var snap = SessionState()
        snap.decisionsByCluster = decisionsByCluster
        snap.manualOverridesByCluster = SessionState.encodeOverrides(manualOverrides)
        snap.save()
    }

    /// Append a URL to `sources` from any thread. Wrapping the @State write
    /// in a main-actor Task is required because `loadObject` / `loadData…`
    /// completion handlers run off-main.
    ///
    /// `.photoslibrary` URLs go through an extra step: request PhotoKit
    /// authorization first. If the user grants it, the source is added
    /// *un-locked* — the GUI lets them mark DELETE on Photos library files
    /// and trashing them routes through `PhotoKitDeletionService`'s album
    /// round-trip. If access is denied (or the user dismisses), the source
    /// stays locked (read-only viewing only) and a hint banner explains
    /// they have to use Photos.app's own Duplicates feature.
    private func addURL(_ url: URL) {
        if ScanSource.isPhotosLibrary(url: url) {
            Task {
                let status = await PhotoKitDeletionService.shared.requestAuthorization()
                let unlocked = (status == .authorized)
                await MainActor.run {
                    if !sources.contains(where: { $0.url == url }) {
                        sources.append(ScanSource(url: url, isLocked: !unlocked))
                        if unlocked {
                            statusMessage = "Photos library added with full access. Files marked DELETE will be queued in Photos.app's \"Marked for Deletion in PurpleDedup\" album."
                        } else {
                            statusMessage = "Photos library added in read-only mode. Use Photos.app → Library → Duplicates to delete."
                        }
                    }
                }
            }
            return
        }
        Task { @MainActor in
            if !sources.contains(where: { $0.url == url }) {
                sources.append(ScanSource(url: url))
            }
        }
    }

    private func runScan() async {
        isScanning = true
        defer { isScanning = false }

        exactClusters = []
        similarClusters = []
        similarVideoClusters = []
        clusterMembersInLookup = []
        selectedClusterID = nil
        totalScanned = 0
        progressLine = ""
        cacheLine = ""
        stageTiming = ""
        statusMessage = "Scanning…"

        let throttleInterval: TimeInterval = 0.2
        let lastUpdate = ProgressThrottle()

        do {
            // Materialise per-Photos-library filters before scanning. For each
            // .photoslibrary source with an active filter, ask PhotoKit which
            // basenames pass — the walker then uses that set as a whitelist.
            // Sources without filters pass through unchanged.
            let filters = settingsStore.settings.photoLibraryFilters
            var resolved: [ScanSource] = []
            for src in sources {
                if src.isPhotosLibrary,
                   let f = filters[src.url.path],
                   f.isActive {
                    statusMessage = "Resolving Photos filter for \(src.url.lastPathComponent)…"
                    let resolution = await PhotoKitDeletionService.shared.matchingBasenamesDetailed(filter: f, libraryURL: src.url)
                    self.photosFilterLine = "Photos filter: \(resolution.summary)"
                    resolved.append(ScanSource(
                        url: src.url,
                        isLocked: src.isLocked,
                        allowedBasenames: resolution.basenames,
                        isLookupOnly: src.isLookupOnly
                    ))
                } else {
                    resolved.append(src)
                }
            }
            let captured = resolved
            statusMessage = "Scanning…"
            let perceptual = ScanEngine.PerceptualOptions(enabled: includeSimilar, threshold: threshold)
            let videoOpts = ScanEngine.VideoOptions(enabled: includeSimilarVideos, threshold: videoThreshold)

            if settingsStore.settings.useCachedEngine {
                let database = try Database.openDefault()
                // FFmpeg sidecar: only probe when the user has opted in.
                // Probe is a process spawn; not free, so skip when disabled.
                let ffmpegProbe: FFmpegProbe.Probe? = settingsStore.settings.ffmpegFallbackEnabled ? FFmpegProbe.find() : nil
                let engine = CachedScanEngine(
                    database: database,
                    videoFingerprinter: VideoFingerprinter(ffmpegFallback: ffmpegProbe)
                )
                let pair = try await engine.scan(
                    sources: captured,
                    options: ScanOptions(kinds: [.photo, .video]),
                    perceptual: perceptual,
                    video: videoOpts
                ) { p in
                    if !lastUpdate.shouldFire(interval: throttleInterval) { return }
                    Task { @MainActor in
                        self.progressLine = Self.formatProgress(p)
                    }
                }
                self.exactClusters = pair.result.exactClusters
                self.similarClusters = pair.result.similarClusters
                self.similarVideoClusters = pair.result.similarVideoClusters
                self.totalScanned = pair.result.filesScanned
                self.photosLookupHashes = pair.result.photosLookupHashes
                self.photosLookupCount = pair.result.photosLookupCount
                self.clusterMembersInLookup = pair.result.clusterMembersInLookup
                let s = pair.cache
                self.cacheLine = "cache: content \(s.contentHashHits)/\(s.contentHashHits + s.contentHashMisses) · perceptual \(s.perceptualHits)/\(s.perceptualHits + s.perceptualMisses) · video \(s.videoHits)/\(s.videoHits + s.videoMisses)"
                self.stageTiming = pair.result.timing.summary()
                self.statusMessage = "Scanned \(pair.result.filesScanned) file(s) · \(pair.result.exactClusters.count) exact + \(pair.result.similarClusters.count) similar photos + \(pair.result.similarVideoClusters.count) similar videos."
            } else {
                // Plain (non-cached) engine doesn't know about lookup mode.
                // Filter the lookup sources out so they don't accidentally
                // appear in clusters; the lookup index stays empty in this
                // path. Use the cached engine to get full lookup support.
                let engine = ScanEngine()
                let scanOnly = captured.filter { !$0.isLookupOnly }
                let result = try await engine.scan(
                    sources: scanOnly,
                    options: ScanOptions(kinds: [.photo, .video]),
                    perceptual: perceptual,
                    video: videoOpts
                ) { p in
                    if !lastUpdate.shouldFire(interval: throttleInterval) { return }
                    Task { @MainActor in
                        self.progressLine = Self.formatProgress(p)
                    }
                }
                self.exactClusters = result.exactClusters
                self.similarClusters = result.similarClusters
                self.similarVideoClusters = result.similarVideoClusters
                self.totalScanned = result.filesScanned
                self.photosLookupHashes = result.photosLookupHashes
                self.photosLookupCount = result.photosLookupCount
                self.statusMessage = "Scanned \(result.filesScanned) file(s) · \(result.exactClusters.count) exact + \(result.similarClusters.count) similar photos + \(result.similarVideoClusters.count) similar videos."
            }
        } catch is CancellationError {
            statusMessage = "Scan cancelled"
            progressLine = ""
        } catch {
            statusMessage = "Scan failed: \(error.localizedDescription)"
            Log.app.error("Scan failed: \(error.localizedDescription, privacy: .public)")
        }
        scanTask = nil
        cancelRequestedAt = nil
    }

    // MARK: - status helpers

    private var currentSummary: String {
        let totalClusters = exactClusters.count + similarClusters.count + similarVideoClusters.count
        if totalClusters == 0 { return "" }
        let pending = pendingDeleteCount ?? 0
        if pending > 0 {
            return "\(totalClusters) groups · \(formatBytes(reclaimable)) reclaimable · \(pending) marked"
        }
        return "\(totalClusters) groups · \(formatBytes(reclaimable)) reclaimable"
    }

    /// Total files marked DELETE across all clusters (engine recommendation OR manual
    /// override). Used to populate the toolbar's "Move N to Trash" button.
    private var pendingDeleteCount: Int? {
        let count = filesToDelete.count
        return count == 0 ? nil : count
    }

    /// All files marked DELETE across reviewed clusters. Manual overrides win;
    /// engine output fills in the rest. Locked sources can never end up here
    /// because `SelectionEngine` already excludes them.
    private var filesToDelete: [DiscoveredFile] {
        var out: [DiscoveredFile] = []
        let allClusters = currentClusterFileMap()
        for (clusterID, files) in allClusters {
            let manual = manualOverrides[clusterID] ?? [:]
            let engine = decisionsByCluster[clusterID]?.perFile ?? [:]
            for f in files {
                let decision = manual[f.url] ?? engine[f.url]
                if case .delete = decision {
                    out.append(f)
                }
            }
        }
        return out
    }

    /// Confirmation sheet pre-filled with whichever subset of files the user
    /// has requested to trash (one file, one cluster's pending deletes, or
    /// the full cross-cluster batch). Extracted from `body` to keep that
    /// expression under the SwiftUI type-check budget.
    @ViewBuilder
    private var preflightSheet: some View {
        PreflightView(
            toDelete: pendingTrashSubset.isEmpty ? filesToDelete : pendingTrashSubset,
            onCancel: {
                showPreflight = false
                pendingTrashSubset = []
            },
            onConfirm: {
                let subset = pendingTrashSubset
                showPreflight = false
                pendingTrashSubset = []
                Task { await runTrash(subset: subset.isEmpty ? nil : subset) }
            }
        )
    }

    /// Right-hand detail column. Extracted from the main `body` to keep that
    /// expression under SwiftUI's type-check budget on macOS Tahoe — the
    /// inline `NavigationSplitView { ... } detail: { ComparisonView(...).task(...) }`
    /// form pushed the compiler over its limit.
    @ViewBuilder
    private var comparisonColumn: some View {
        ComparisonView(
            selection: currentSelection,
            decisionsByCluster: $decisionsByCluster,
            manualOverrides: $manualOverrides,
            onApproveAndNext: { Task { await approveAndAdvance() } },
            onRequestTrash: { subset in
                pendingTrashSubset = subset
                showPreflight = true
            },
            photosLookupHashes: photosLookupHashes
        )
        .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        .task(id: selectedClusterID) {
            if let id = selectedClusterID, decisionsByCluster[id] == nil {
                await ensureDecisions(for: id)
            }
        }
    }

    /// Hidden buttons whose only purpose is to register global keyboard
    /// shortcuts. Each button's action runs from anywhere in the window
    /// because `.keyboardShortcut` registers a command at scene level.
    /// Extracted from the main `body` to keep that expression under the
    /// SwiftUI compiler's type-check budget on macOS Tahoe.
    @ViewBuilder
    private var keyboardShortcutHost: some View {
        Group {
            Button("Next cluster") { advanceCluster(direction: 1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("Previous cluster") { advanceCluster(direction: -1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Approve & next") { Task { await approveAndAdvance() } }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Next undecided") { advanceToNextUndecided() }
                .keyboardShortcut("n", modifiers: .command)
        }
        .opacity(0).allowsHitTesting(false).frame(width: 0, height: 0)
    }

    /// All cluster IDs in the current scan, in display order. Used by the
    /// "Apply to all" / "Expand all" bulk actions and by keyboard navigation.
    /// Honors the cross-source filter when on so navigation only steps through
    /// the visible subset.
    private var allClusterIDs: [String] {
        let allMap = currentClusterFileMap()
        guard crossSourceFilterOn else { return allMap.map(\.0) }
        return allMap.compactMap { id, _ in
            isClusterCrossSource(id: id) ? id : nil
        }
    }

    /// True when a cluster's files come from at least 2 distinct scan source
    /// roots (different folders, or a folder + a Photos library, etc.). The
    /// match is path-prefix-based against the current `sources` set.
    private func isClusterCrossSource(id: String) -> Bool {
        guard sources.count >= 2 else { return false }
        guard let entry = currentClusterFileMap().first(where: { $0.0 == id }) else { return false }
        var rootsHit: Set<URL> = []
        for f in entry.1 {
            for src in sources {
                let base = src.url.path
                if f.url.path == base || f.url.path.hasPrefix(base + "/") {
                    rootsHit.insert(src.url)
                    break
                }
            }
            if rootsHit.count >= 2 { return true }
        }
        return rootsHit.count >= 2
    }

    /// True when the cluster has at least one file whose content hash is
    /// in the lookup-mode Photos library's reference index. Used by the
    /// cluster-row badge so the user can see at a glance "this folder
    /// duplicate is also archived in my Photos library — safe to trash
    /// the folder copy."
    ///
    /// Exact clusters share one content hash so the check is cheap. For
    /// perceptual / video / burst / rotated clusters we use the engine's
    /// per-cluster-member crossref set (`clusterMembersInLookup`), which
    /// is populated only for files the exact stage hashed (i.e., files
    /// with at least one same-size sibling). Files lacking a cached
    /// content hash silently miss the badge — acceptable: the badge is
    /// purely advisory.
    private func isClusterArchivedInPhotos(id: String) -> Bool {
        guard !photosLookupHashes.isEmpty else { return false }
        if id.hasPrefix("exact:") {
            let hex = String(id.dropFirst("exact:".count))
            return photosLookupHashes.contains(hex)
        }
        guard !clusterMembersInLookup.isEmpty else { return false }

        let files: [DiscoveredFile]?
        if id.hasPrefix("photo:") {
            let key = String(id.dropFirst("photo:".count))
            files = similarClusters.first(where: { $0.stableID == key })?.files
        } else if id.hasPrefix("video:") {
            let key = String(id.dropFirst("video:".count))
            files = similarVideoClusters.first(where: { $0.stableID == key })?.files
        } else if id.hasPrefix("burst:") {
            let key = String(id.dropFirst("burst:".count))
            files = burstClusters.first(where: { $0.stableID == key })?.files
        } else if id.hasPrefix("rotated:") {
            let key = String(id.dropFirst("rotated:".count))
            files = rotatedClusters.first(where: { $0.stableID == key })?.files
        } else {
            files = nil
        }
        guard let members = files else { return false }
        return members.contains { clusterMembersInLookup.contains($0.url.path) }
    }

    /// Predicate used by every cluster section: with the cross-source filter
    /// on, hide non-cross-source clusters entirely.
    private func shouldShow(clusterID: String) -> Bool {
        if !crossSourceFilterOn { return true }
        return isClusterCrossSource(id: clusterID)
    }

    /// Move the selection forward (1) or backward (-1) through the cluster list,
    /// wrapping at the ends. No-op when there are no clusters. Used by the
    /// ⌘↑ / ⌘↓ keyboard shortcuts.
    private func advanceCluster(direction: Int) {
        let ids = allClusterIDs
        guard !ids.isEmpty else { return }
        guard let current = selectedClusterID,
              let idx = ids.firstIndex(of: current) else {
            selectedClusterID = ids.first
            return
        }
        let next = (idx + direction + ids.count) % ids.count
        selectedClusterID = ids[next]
    }

    /// Find the next cluster after the current selection that has no
    /// recommendation yet (i.e. the user hasn't reviewed it). Bound to ⌘N
    /// for fast skipping through long lists. Falls back to the first
    /// undecided if no current selection.
    private func advanceToNextUndecided() {
        let ids = allClusterIDs
        guard !ids.isEmpty else { return }
        let startIndex: Int
        if let current = selectedClusterID, let idx = ids.firstIndex(of: current) {
            startIndex = idx + 1
        } else {
            startIndex = 0
        }
        // Search forward from start, then wrap once. If nothing's undecided,
        // the user has reviewed everything; leave selection alone.
        for offset in 0..<ids.count {
            let i = (startIndex + offset) % ids.count
            if decisionsByCluster[ids[i]] == nil {
                selectedClusterID = ids[i]
                return
            }
        }
    }

    /// Approve the current cluster's engine recommendation (just ensures it's
    /// computed — manual overrides are kept) and jump to the next undecided
    /// cluster. The keyboard-driven "review wizard" workflow: hit ⌘⏎ to flip
    /// through every cluster in seconds.
    private func approveAndAdvance() async {
        if let id = selectedClusterID, decisionsByCluster[id] == nil {
            await ensureDecisions(for: id)
        }
        advanceToNextUndecided()
    }

    /// Map of cluster ID → DiscoveredFile list, regardless of cluster type.
    private func currentClusterFileMap() -> [(String, [DiscoveredFile])] {
        var out: [(String, [DiscoveredFile])] = []
        for c in exactClusters { out.append(("exact:\(c.contentHashHex)", c.files)) }
        for c in similarClusters { out.append(("photo:\(c.stableID)", c.files)) }
        for c in similarVideoClusters { out.append(("video:\(c.stableID)", c.files)) }
        for c in burstClusters { out.append(("burst:\(c.stableID)", c.files)) }
        for c in rotatedClusters { out.append(("rotated:\(c.stableID)", c.files)) }
        return out
    }

    /// Photos in the current scan, derived from the existing cluster sets.
    /// Used to gate the "Find bursts" button and as input to the burst
    /// clusterer. We don't keep a separate flat photo list because the
    /// scan engine doesn't surface one — but every photo that ended up
    /// anywhere (including in clusters) is fair game for burst detection,
    /// since burst detection considers photos as photos regardless of
    /// whether they're already in another cluster.
    private var photosInScan: [DiscoveredFile] {
        var seen: Set<URL> = []
        var out: [DiscoveredFile] = []
        for (_, files) in currentClusterFileMap() {
            for f in files {
                let ext = f.url.pathExtension.lowercased()
                guard FileKind.photoExtensions.contains(ext) else { continue }
                if seen.insert(f.url).inserted {
                    out.append(f)
                }
            }
        }
        return out
    }

    /// Run burst detection on demand. Extracts capture dates and pHashes for
    /// every photo across the scan in parallel, then hands the inputs to
    /// `BurstClusterer`. Files already in an exact cluster are excluded
    /// (they're the same bytes; burst grouping is about visual
    /// rapid-fire variation, not byte equality). Files already in a
    /// similar_photo cluster ARE eligible — the same photo can be both a
    /// burst neighbour and a perceptual match.
    private func runBurstDetection() async {
        guard !burstScanInProgress else { return }
        burstScanInProgress = true
        defer { burstScanInProgress = false }

        let photos = photosInScan
        guard !photos.isEmpty else { return }

        let exactURLs = Set(exactClusters.flatMap { $0.files.map(\.url) })
        let candidates = photos.filter { !exactURLs.contains($0.url) }

        // Extract capture dates + pHashes in parallel. Both are cheap on the
        // embedded-thumbnail path; total runtime is dominated by the HEVC
        // decoder serialisation we capped at 6 in PerceptualHasher's stage.
        let extractor = MetadataExtractor()
        let hasher = PerceptualHasher()

        var entries: [BurstClusterer.Entry] = []
        await withTaskGroup(of: BurstClusterer.Entry?.self) { group in
            for f in candidates {
                group.addTask {
                    let m = await extractor.extract(url: f.url)
                    guard let date = m.captureDate else { return nil }
                    guard let h = try? hasher.hash(imageAt: f.url) else { return nil }
                    return BurstClusterer.Entry(
                        file: f, captureDate: date, phash: h.phash
                    )
                }
            }
            for await e in group { if let e = e { entries.append(e) } }
        }

        let result = BurstClusterer().clusterBursts(entries: entries)
        burstClusters = result
        statusMessage = "Found \(result.count) burst series across \(entries.count) dated photos."
    }

    /// Run rotated-copy detection on demand. Re-hashes every photo with all
    /// four rotations and clusters by cross-rotation pHash similarity. Files
    /// already in an exact cluster are excluded — byte-identical files
    /// rotated identically are already caught there. Files already in a
    /// similar_photo cluster ARE eligible because a perceptual match doesn't
    /// preclude a rotated variant existing somewhere else in the scan.
    private func runRotatedDetection() async {
        guard !rotatedScanInProgress else { return }
        rotatedScanInProgress = true
        defer { rotatedScanInProgress = false }

        let photos = photosInScan
        guard !photos.isEmpty else { return }
        let exactURLs = Set(exactClusters.flatMap { $0.files.map(\.url) })
        let candidates = photos.filter { !exactURLs.contains($0.url) }

        let hasher = PerceptualHasher()
        var entries: [RotatedClusterer.Entry] = []
        await withTaskGroup(of: RotatedClusterer.Entry?.self) { group in
            // Bound concurrency for the same VideoToolbox-HEVC reason as the
            // perceptual stage — HEIC decode goes through a serialised
            // hardware decoder that punishes high concurrency.
            let limit = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            var iterator = candidates.makeIterator()
            var inFlight = 0
            func submit() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    guard let h = try? hasher.hashWithRotations(imageAt: next.url) else { return nil }
                    return RotatedClusterer.Entry(file: next, rotationHashes: h)
                }
            }
            for _ in 0..<limit { submit() }
            while inFlight > 0 {
                if let r = try? await group.next() {
                    inFlight -= 1
                    if let e = r { entries.append(e) }
                    submit()
                } else {
                    break
                }
            }
        }

        let result = RotatedClusterer().clusterRotated(entries: entries)
        rotatedClusters = result
        statusMessage = "Found \(result.count) rotated-copy group(s) across \(entries.count) photos."
    }

    /// Run the rule chain on a cluster the first time the user selects it.
    /// Metadata is pulled lazily inside `ComparisonView` already; the engine
    /// uses the same lookup so locked / size / mtime fields are populated even
    /// before the user has scrolled through the metadata table.
    private func ensureDecisions(for clusterID: String) async {
        let map = currentClusterFileMap()
        guard let entry = map.first(where: { $0.0 == clusterID }) else { return }
        let files = entry.1

        // Extract metadata for selection inputs in parallel. Cheap (no decode);
        // only happens for clusters the user actually opens.
        let extractor = MetadataExtractor()
        var metaByURL: [URL: FileMetadata] = [:]
        await withTaskGroup(of: (URL, FileMetadata).self) { group in
            for f in files {
                group.addTask { (f.url, await extractor.extract(url: f.url)) }
            }
            for await (u, m) in group { metaByURL[u] = m }
        }

        let inputs = files.map {
            FileForSelection(
                url: $0.url,
                sizeBytes: $0.sizeBytes,
                modificationTime: $0.modificationTime,
                metadata: metaByURL[$0.url] ?? FileMetadata(),
                isLocked: $0.isLocked
            )
        }
        // Build the chain + context from current Settings every time. The user
        // can edit Rules in Settings while the app is running and the next
        // cluster they review uses the new ordering — no rescan needed.
        let rules = settingsStore.settings.selectionRuleNames.compactMap { Rule(rawValue: $0) }
        let chain = rules.isEmpty ? .default : RuleChain(rules: rules)
        let context = SelectionContext(folderPriority: settingsStore.settings.folderPriority)
        let decisions = SelectionEngine().decide(files: inputs, chain: chain, context: context)
        decisionsByCluster[clusterID] = decisions
    }

    /// Move files to Trash. With `subset == nil`, processes the full
    /// `filesToDelete` set (every cluster's pending DELETE). With a non-nil
    /// `subset`, processes only those — used by the per-cluster and per-file
    /// trash actions so the user can act on one group or even one file at a
    /// time without committing the rest of their review.
    private func runTrash(subset: [DiscoveredFile]? = nil) async {
        let toDelete = subset ?? filesToDelete
        guard !toDelete.isEmpty else { return }

        // Split into regular files (Trash via FileManager) and Photos library
        // files (queue in PhotoKit album). Photos files inside `.photoslibrary/`
        // can't go to Trash directly without leaving Photos.app's database in
        // a broken state — they round-trip through the "Marked for Deletion
        // in PurpleDedup" album where the user finalises inside Photos.app.
        let regularFiles = toDelete.filter { !$0.url.path.contains(".photoslibrary/") }
        let photosFiles = toDelete.filter { $0.url.path.contains(".photoslibrary/") }

        let database = (try? Database.openDefault())
        let manager = TrashManager(database: database)
        var trashed: [TrashedFile] = []
        var failures: [String] = []
        // FR-5.5: route to a user-chosen stage folder when configured,
        // otherwise the Finder Trash. The TrashManager records both
        // destinations in the operation log so Cmd+Z can restore from
        // either kind.
        let stageFolderPath = settingsStore.settings.stageFolderPath ?? ""
        let destination: TrashManager.Destination =
            stageFolderPath.isEmpty
            ? .trash
            : .folder(URL(fileURLWithPath: stageFolderPath))
        for f in regularFiles {
            do {
                if let resultURL = try manager.move(f, to: destination) {
                    trashed.append(TrashedFile(originalPath: f.url.path, trashURL: resultURL, sizeBytes: f.sizeBytes))
                }
            } catch {
                failures.append("\(f.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Photos library round-trip. The service builds (or reuses) the
        // album, looks up each path's PHAsset by basename, and bulk-adds
        // them via PHAssetCollectionChangeRequest. The user opens Photos.app
        // afterwards to actually delete the queued assets.
        var photoKitSummary: String = ""
        if !photosFiles.isEmpty {
            let result = await PhotoKitDeletionService.shared.markForDeletion(
                paths: photosFiles.map(\.url)
            )
            photoKitSummary = result.summary
            // Photos files queued for album-level deletion don't go into
            // `lastTrashOperation` because Cmd+Z can't undo a PhotoKit
            // album add (the user has to remove from the album inside
            // Photos.app). Surface this difference in the status message
            // so users don't expect undo to work for the Photos batch.
        }
        // Files that successfully moved are gone from disk — drop them from the
        // in-memory cluster lists so the UI doesn't show stale ghost rows.
        let trashedSet = Set(trashed.map { $0.originalPath })
        exactClusters = removeMembers(in: exactClusters, where: { trashedSet.contains($0.url.path) })
        similarClusters = removeMembers(in: similarClusters, where: { trashedSet.contains($0.url.path) })
        similarVideoClusters = removeMembers(in: similarVideoClusters, where: { trashedSet.contains($0.url.path) })

        // Clear decisions for files that no longer exist; preserve overrides for
        // remaining cluster members (which might still be visible).
        for clusterID in decisionsByCluster.keys {
            if var perFile = decisionsByCluster[clusterID]?.perFile {
                for url in perFile.keys where trashedSet.contains(url.path) {
                    perFile.removeValue(forKey: url)
                }
                if perFile.isEmpty {
                    decisionsByCluster.removeValue(forKey: clusterID)
                } else {
                    let keeper = decisionsByCluster[clusterID]!.keeper
                    decisionsByCluster[clusterID] = ClusterDecisions(keeper: keeper, perFile: perFile)
                }
            }
        }
        manualOverrides = [:]

        lastTrashOperation = trashed
        var msg: [String] = []
        if !trashed.isEmpty {
            let dest = stageFolderPath.isEmpty
                ? "Trash"
                : "stage folder (\(URL(fileURLWithPath: stageFolderPath).lastPathComponent))"
            msg.append("Moved \(trashed.count) file(s) to \(dest)")
        }
        if !photoKitSummary.isEmpty {
            msg.append(photoKitSummary)
        }
        if !failures.isEmpty {
            msg.append("\(failures.count) failed")
        }
        if trashed.isEmpty && !photosFiles.isEmpty {
            statusMessage = msg.joined(separator: " · ") + ". Open Photos.app to finalise."
        } else {
            statusMessage = msg.joined(separator: " · ") + (lastTrashOperation.isEmpty ? "." : ". Cmd+Z to undo the Trash batch.")
        }
    }

    /// FR-5.9 dry-run: serialise every cluster + per-file decision to JSON
    /// and let the user pick where to save it. Nothing on disk changes.
    /// The output is shaped like a `ScanReport` augmented with the user's
    /// decisions so it's diffable (week-over-week deduping reviews) and
    /// audit-friendly.
    private func savePlanJSON() {
        struct PlanFile: Codable {
            let path: String
            let decision: String   // "keep" | "delete" | "(no decision)"
            let reason: String?
            let isManualOverride: Bool
            let sizeBytes: Int64
        }
        struct PlanCluster: Codable {
            let id: String
            let kind: String
            let fileCount: Int
            let reclaimableBytes: Int64
            let files: [PlanFile]
        }
        struct Plan: Codable {
            let appName: String
            let appVersion: String
            let generatedAtISO: String
            let totalFiles: Int
            let totalMarkedDelete: Int
            let totalReclaimableBytes: Int64
            let stageFolder: String?
            let clusters: [PlanCluster]
        }

        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]

        var planClusters: [PlanCluster] = []
        let allMap = currentClusterFileMap()
        var totalMarked = 0
        for (id, files) in allMap {
            let decisions = decisionsByCluster[id]?.perFile ?? [:]
            let manual = manualOverrides[id] ?? [:]
            let kind: String
            if id.hasPrefix("exact:")        { kind = "exact" }
            else if id.hasPrefix("photo:")   { kind = "similar_photo" }
            else if id.hasPrefix("video:")   { kind = "similar_video" }
            else if id.hasPrefix("burst:")   { kind = "similar_burst" }
            else if id.hasPrefix("rotated:") { kind = "similar_rotated" }
            else { kind = "unknown" }

            let planFiles: [PlanFile] = files.map { f in
                let effective = manual[f.url] ?? decisions[f.url]
                let isManual = manual[f.url] != nil
                let (decisionStr, reason): (String, String?)
                switch effective {
                case .keep(let r):   decisionStr = "keep";   reason = r
                case .delete(let r): decisionStr = "delete"; reason = r; totalMarked += 1
                case nil:            decisionStr = "(no decision)"; reason = nil
                }
                return PlanFile(
                    path: f.url.path, decision: decisionStr, reason: reason,
                    isManualOverride: isManual, sizeBytes: f.sizeBytes
                )
            }

            let reclaim = filesToDelete
                .filter { f in files.contains(where: { $0.url == f.url }) }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }

            planClusters.append(PlanCluster(
                id: id, kind: kind, fileCount: files.count,
                reclaimableBytes: reclaim, files: planFiles
            ))
        }

        let plan = Plan(
            appName: PurpleDedup.appName,
            appVersion: PurpleDedup.coreVersion,
            generatedAtISO: iso.string(from: Date()),
            totalFiles: allMap.reduce(0) { $0 + $1.1.count },
            totalMarkedDelete: totalMarked,
            totalReclaimableBytes: reclaimable,
            stageFolder: settingsStore.settings.stageFolderPath,
            clusters: planClusters
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "purplededup-plan-\(Self.timestampForFilename()).json"
        panel.title = "Save dry-run plan"
        panel.message = "Writes a JSON record of every cluster + decision. Nothing is moved or trashed."
        panel.directoryURL = PurpleDedup.defaultOutputDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(plan)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                statusMessage = "Plan written to \(url.lastPathComponent) (\(plan.clusters.count) clusters, \(plan.totalMarkedDelete) marked DELETE)."
            } catch {
                statusMessage = "Couldn't write plan: \(error.localizedDescription)"
            }
        }
    }

    /// Compact filename-safe timestamp. Used to disambiguate plan exports
    /// when the user runs several in one session.
    private static func timestampForFilename() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /// Render `ScanProgress` to a one-line status string for the sidebar.
    /// Phrasing varies by phase so the user can tell what's actually
    /// happening — `indexing` (Photos lookup hash on cold cache) used to
    /// look like a hang because progress was emitted only after it
    /// finished.
    static func formatProgress(_ p: ScanProgress) -> String {
        switch p.phase {
        case .walking:
            return "Walking… \(p.filesSeen) file(s) discovered"
        case .indexing:
            if p.totalCandidates > 0 && p.filesHashed > 0 {
                return "Indexing Photos library… \(p.filesHashed)/\(p.totalCandidates) hashed"
            } else if p.filesSeen > 0 {
                return "Indexing Photos library… \(p.filesSeen) file(s) found"
            } else {
                return "Indexing Photos library…"
            }
        case .hashing:
            if p.totalCandidates > 0 {
                return "Hashing… \(p.filesHashed)/\(p.totalCandidates) · clusters \(p.clustersSoFar)"
            } else {
                return "Hashing… \(p.filesHashed) file(s)"
            }
        case .done:
            return "Done · clusters \(p.clustersSoFar)"
        }
    }

    private func undoLastTrash() async {
        let fm = FileManager.default
        var restored = 0
        for entry in lastTrashOperation {
            do {
                let dst = URL(fileURLWithPath: entry.originalPath)
                try fm.moveItem(at: entry.trashURL, to: dst)
                restored += 1
            } catch {
                Log.app.notice("Restore failed for \(entry.originalPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        lastTrashOperation = []
        statusMessage = "Restored \(restored) file(s) from Trash. Re-scan to see them in clusters again."
    }

    /// Generic helper for filtering cluster files. Returns clusters with members
    /// that still satisfy the predicate; clusters that drop below 2 members get
    /// removed entirely (a 1-file "cluster" isn't a cluster any more).
    private func removeMembers<T>(in clusters: [T], where shouldRemove: (DiscoveredFile) -> Bool) -> [T] {
        clusters.compactMap { cluster -> T? in
            // Reflection-light: handle each known cluster type.
            if let c = cluster as? ExactClusterer.Cluster {
                let kept = c.files.filter { !shouldRemove($0) }
                guard kept.count >= 2 else { return nil }
                return ExactClusterer.Cluster(
                    contentHashHex: c.contentHashHex,
                    sizeBytes: c.sizeBytes,
                    files: kept
                ) as? T
            }
            if let c = cluster as? PerceptualClusterer.Cluster {
                let zipped = Array(zip(c.files, c.hashes))
                let kept = zipped.filter { !shouldRemove($0.0) }
                guard kept.count >= 2 else { return nil }
                return PerceptualClusterer.Cluster(
                    files: kept.map(\.0),
                    hashes: kept.map(\.1),
                    maxPairwiseDistance: c.maxPairwiseDistance
                ) as? T
            }
            if let c = cluster as? VideoClusterer.Cluster {
                let zipped = Array(zip(c.files, c.fingerprints))
                let kept = zipped.filter { !shouldRemove($0.0) }
                guard kept.count >= 2 else { return nil }
                return VideoClusterer.Cluster(
                    files: kept.map(\.0),
                    fingerprints: kept.map(\.1),
                    maxPairwiseMeanDistance: c.maxPairwiseMeanDistance
                ) as? T
            }
            return cluster
        }
    }

    private var reclaimable: Int64 {
        exactClusters.reduce(Int64(0)) { $0 + $1.totalReclaimableBytes }
        + similarClusters.reduce(Int64(0)) { $0 + $1.totalReclaimableBytes }
        + similarVideoClusters.reduce(Int64(0)) { $0 + $1.totalReclaimableBytes }
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter(); bcf.allowedUnits = [.useAll]; bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }
}

#Preview {
    ContentView(settingsStore: SettingsStore())
}

// MARK: - Trash undo bookkeeping

/// One entry per file successfully moved to the Trash by the most recent batch.
/// `trashURL` is the resulting URL inside Trash (returned by `FileManager.trashItem`)
/// — that's what we move back from when the user presses Cmd+Z.
struct TrashedFile {
    let originalPath: String
    let trashURL: URL
    let sizeBytes: Int64
}

// MARK: - Throttle for high-frequency progress callbacks

/// Lock-free time-based gate. The progress closure passed into `engine.scan`
/// runs from worker tasks; this lets us drop all events that arrive within
/// `interval` of the last we let through. Reference type so a single instance
/// can be captured by the closure across iterations.
final class ProgressThrottle: @unchecked Sendable {
    private var lastFireSeconds: Double = 0
    private let lock = NSLock()
    func shouldFire(interval: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastFireSeconds < interval { return false }
        lastFireSeconds = now
        return true
    }
}

// MARK: - Stable cluster IDs for SwiftUI

/// SwiftUI's `ForEach(_, id:)` needs a Hashable, deterministic identity per row.
/// The cluster types ship without one because they're domain values; we synthesise
/// it here from the member URLs (sorted, joined). Two clusters with the same
/// member set have the same ID — perfect for re-rendering the same `expanded`
/// state across rescans, and impossible to collide across sections because the
/// section view ID is composed as e.g. `"photo:<stableID>"`.
extension PerceptualClusterer.Cluster {
    var stableID: String {
        files.map { $0.url.path }.sorted().joined(separator: "\u{1}")
    }
}

extension VideoClusterer.Cluster {
    var stableID: String {
        files.map { $0.url.path }.sorted().joined(separator: "\u{1}")
    }
}

extension BurstClusterer.Cluster {
    var stableID: String {
        files.map { $0.url.path }.sorted().joined(separator: "\u{1}")
    }
}

extension RotatedClusterer.Cluster {
    var stableID: String {
        files.map { $0.url.path }.sorted().joined(separator: "\u{1}")
    }
}
