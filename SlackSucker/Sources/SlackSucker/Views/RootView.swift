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
        VStack(alignment: .leading, spacing: 6) {
            Text("OPTIONS")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Toggle("Download files", isOn: $includeFiles)
                Toggle("Avatars", isOn: $includeAvatars)
                if case .entireWorkspace = scope {
                    Toggle("Member-only channels", isOn: $memberOnly)
                }
                Toggle("Sort into Videos/Photos/Audio/Other", isOn: $organizeFiles)
                    .disabled(!includeFiles)
                    .help(includeFiles
                          ? "After the archive completes, move attachments from __uploads/ into category subfolders at the run-folder root."
                          : "Turn on \u{201C}Download files\u{201D} first — there's nothing to sort otherwise.")
                Spacer()
                Button("Save preset…") { showSavePresetSheet = true }
                    .buttonStyle(.borderless)
            }
        }
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
            root: settings.resolvedOutputDir, scope: scope)
        return ArchiveRequest(
            workspace: settings.selectedWorkspace,
            scope: scope,
            timeRange: timeRange,
            includeFiles: includeFiles,
            includeAvatars: includeAvatars,
            memberOnly: memberOnly,
            organizeFiles: organizeFiles && includeFiles,
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
    }

    private func applyHistoryEntry(_ entry: RunHistoryEntry) {
        applyPreset(ArchivePreset(name: "(history)", request: entry.request))
    }
}
