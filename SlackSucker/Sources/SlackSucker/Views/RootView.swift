import SwiftUI
import AppKit

/// Top-level layout: Sidebar | main pane. The main pane is a vertical
/// stack of: scope picker → time range → archive options → run strip →
/// stat tiles → live output. Modeled after messages-exporter-gui's
/// RootView, but the form is much smaller (no transcribe, no FDA, no
/// emoji handling — slackdump owns all that).
struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var runner: ArchiveRunner
    @EnvironmentObject var workspaces: WorkspaceService
    @EnvironmentObject var channels: ChannelService
    @EnvironmentObject var presets: PresetStore

    @State private var scope: ArchiveScope = .entireWorkspace
    @State private var allTime: Bool = true
    @State private var fromDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var includeFiles: Bool = true
    @State private var includeAvatars: Bool = false
    @State private var memberOnly: Bool = false
    @State private var organizeFiles: Bool = true
    @State private var fileOrdering: FileOrdering = .messageTimestamp
    @State private var generateHashes: Bool = false
    @State private var transcribeMedia: Bool = false
    @State private var stripPhotoMetadata: Bool = false
    @State private var bakeOrientation: Bool = false
    /// Per-session override of the output root. Resets on relaunch
    /// back to settings.resolvedOutputDir — Settings is the source of
    /// the persistent default, the main-screen row is a temporary
    /// "just for this run / session" override.
    @State private var sessionOutputOverride: URL? = nil
    @State private var showWorkspaceSheet = false
    @State private var showSavePresetSheet = false

    var body: some View {
        AppThemeReader { theme in
            HStack(spacing: 0) {
                Sidebar(showWorkspaceSheet: $showWorkspaceSheet,
                        onApplyPreset: applyPreset,
                        onApplyHistory: applyHistoryEntry)
                    .frame(width: 260)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        formCard
                        runStrip
                        StatTiles(stats: runner.runStats)
                        outputDirCard
                        LiveOutputCard(lines: runner.logLines,
                                       runFolder: runner.runFolder,
                                       canResume: runner.resumeAvailable,
                                       onResume: { Task { await runner.resume(folder: runner.runFolder!) } })
                    }
                    .padding(20)
                }
                .background(
                    LinearGradient(colors: [theme.bg1, theme.bg2],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            }
            .sheet(isPresented: $showWorkspaceSheet) {
                WorkspaceSheet()
                    .environmentObject(workspaces)
                    .environmentObject(settings)
                    .frame(minWidth: 520, minHeight: 420)
            }
            .sheet(isPresented: $showSavePresetSheet) {
                SavePresetSheet(buildRequest: buildRequest)
                    .environmentObject(presets)
                    .frame(minWidth: 360, minHeight: 200)
            }
            .onAppear {
                channels.loadCache(for: settings.selectedWorkspace)
                let opts = settings.defaultArchiveOptions
                includeFiles = opts.includeFiles
                includeAvatars = opts.includeAvatars
                memberOnly = opts.memberOnly
                organizeFiles = opts.organizeFiles
                fileOrdering = opts.fileOrdering
                generateHashes = opts.generateHashes
                transcribeMedia = opts.transcribeMedia
                stripPhotoMetadata = opts.stripPhotoMetadata
                bakeOrientation = opts.bakeOrientation
                Task {
                    await workspaces.refresh()
                    // Auto-populate the channel/DM picker on launch when
                    // a workspace is already selected but its cache is
                    // empty (e.g. fresh install, or the user just signed
                    // in for the first time).
                    if settings.selectedWorkspace != nil, channels.entities.isEmpty {
                        await channels.refresh(for: settings.selectedWorkspace)
                    }
                }
            }
            .onChange(of: settings.selectedWorkspace) { _, newWorkspace in
                // Picking a different workspace from the sheet should
                // immediately repopulate the entity list — the user
                // shouldn't have to hunt for the Refresh button.
                channels.loadCache(for: newWorkspace)
                if let newWorkspace, !newWorkspace.isEmpty {
                    Task { await channels.refresh(for: newWorkspace) }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var formCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                ScopePicker(scope: $scope)
                    .environmentObject(channels)
                    .environmentObject(settings)
                TimeRangeForm(allTime: $allTime, from: $fromDate, to: $toDate)
                archiveOptions
            }
            .padding(18)
        }
    }

    @ViewBuilder private var archiveOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPTIONS")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            // Slackdump-side toggles (passed to the CLI).
            HStack(spacing: 14) {
                Toggle("Download files", isOn: $includeFiles)
                Toggle("Avatars", isOn: $includeAvatars)
                if case .entireWorkspace = scope {
                    Toggle("Member-only channels", isOn: $memberOnly)
                }
                Spacer()
                Button("Save preset…") { showSavePresetSheet = true }
                    .buttonStyle(.borderless)
            }
            // Post-processing toggles (run after slackdump exits 0).
            // Each one is independent; failures don't block the others.
            HStack(spacing: 14) {
                Toggle("Sort folders", isOn: $organizeFiles)
                    .disabled(!includeFiles)
                    .help(includeFiles
                          ? "After the archive completes, move attachments from __uploads/ into Videos/Photos/Audio/Other subfolders."
                          : "Turn on \u{201C}Download files\u{201D} first — there's nothing to sort otherwise.")
                Picker("Order", selection: $fileOrdering) {
                    ForEach(FileOrdering.allCases) { o in
                        Text(o.shortLabel).tag(o)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .disabled(!includeFiles || !organizeFiles)
                .help("Per-category 0001_, 0002_, … prefix order. Slack TS uses parent-message timestamps from slackdump.sqlite. Created uses the on-disk file creation date (ms). None disables the prefix.")
                Toggle("Bake orientation", isOn: $bakeOrientation)
                    .disabled(!includeFiles)
                    .help("Read each photo's EXIF Orientation tag and bake the rotation into pixel data; for videos, flatten the rotation matrix via ffmpeg. Runs before metadata strip so the orientation isn't lost.")
                Toggle("Strip metadata", isOn: $stripPhotoMetadata)
                    .disabled(!includeFiles)
                    .help("Remove EXIF, IPTC, and XMP metadata from photos and videos via exiftool. Destructive — the slackdump SQLite still has provenance.")
                Toggle("Transcribe A/V", isOn: $transcribeMedia)
                    .disabled(!includeFiles)
                    .help("Run the transcribe.py subproject against every audio/video file; emit a .txt transcript next to each source.")
                Toggle("Hashes", isOn: $generateHashes)
                    .disabled(!includeFiles)
                    .help("Generate hashes.txt at the run-folder root with the configured checksum algorithms (Settings → Hashes).")
                Spacer()
            }
        }
    }

    @ViewBuilder private var outputDirCard: some View {
        GlassCard {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPORT FOLDER")
                        .font(AppFont.kicker())
                        .foregroundStyle(.secondary)
                    Text(currentOutputRoot.path)
                        .font(AppFont.mono(11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if sessionOutputOverride != nil {
                        Text("Session override — Settings default is \(settings.resolvedOutputDir.path)")
                            .font(AppFont.sans(10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button("Choose…") { chooseSessionOutputDir() }
                if sessionOutputOverride != nil {
                    Button("Reset") { sessionOutputOverride = nil }
                        .buttonStyle(.borderless)
                }
                Button {
                    revealCurrentOutputRoot()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            .padding(14)
        }
    }

    /// Resolved output root for the next run — session override wins
    /// over the persistent Settings default.
    var currentOutputRoot: URL {
        sessionOutputOverride ?? settings.resolvedOutputDir
    }

    private func chooseSessionOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for this session"
        panel.directoryURL = currentOutputRoot
        if panel.runModal() == .OK, let url = panel.url {
            sessionOutputOverride = url
        }
    }

    private func revealCurrentOutputRoot() {
        let dir = currentOutputRoot
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    @ViewBuilder private var runStrip: some View {
        RunStrip(isRunning: runner.isRunning,
                 isCancelling: runner.isCancelling,
                 phase: runner.runStats.phase,
                 onRun: { Task { await runner.run(buildRequest()) } },
                 onCancel: { runner.cancel() })
    }

    // MARK: - Compose ArchiveRequest

    func buildRequest() -> ArchiveRequest {
        let timeRange: ArchiveTimeRange = allTime
            ? .all
            : .range(from: fromDate, to: toDate)
        let outputDir = ArchiveRequest.computeRunFolder(
            root: currentOutputRoot, scope: scope)
        return ArchiveRequest(
            workspace: settings.selectedWorkspace,
            scope: scope,
            timeRange: timeRange,
            includeFiles: includeFiles,
            includeAvatars: includeAvatars,
            memberOnly: memberOnly,
            organizeFiles: organizeFiles && includeFiles,
            fileOrdering: (organizeFiles && includeFiles) ? fileOrdering : .none,
            generateHashes: generateHashes && includeFiles,
            hashAlgorithms: settings.defaultArchiveOptions.hashAlgorithms,
            transcribeMedia: transcribeMedia && includeFiles,
            transcribeModel: settings.defaultArchiveOptions.transcribeModel,
            stripPhotoMetadata: stripPhotoMetadata && includeFiles,
            bakeOrientation: bakeOrientation && includeFiles,
            outputDir: outputDir,
            debug: UserDefaults.standard.bool(forKey: "debugLogging")
        )
    }

    // MARK: - Preset / history apply

    private func applyPreset(_ preset: ArchivePreset) {
        let r = preset.request
        scope = r.scope
        switch r.timeRange {
        case .all:
            allTime = true
        case .range(let from, let to):
            allTime = false
            fromDate = from
            toDate = to
        }
        includeFiles = r.includeFiles
        includeAvatars = r.includeAvatars
        memberOnly = r.memberOnly
        organizeFiles = r.organizeFiles
        fileOrdering = r.fileOrdering
        generateHashes = r.generateHashes
        transcribeMedia = r.transcribeMedia
        stripPhotoMetadata = r.stripPhotoMetadata
        bakeOrientation = r.bakeOrientation
    }

    private func applyHistoryEntry(_ entry: RunHistoryEntry) {
        applyPreset(ArchivePreset(name: "(history)", request: entry.request))
    }
}
