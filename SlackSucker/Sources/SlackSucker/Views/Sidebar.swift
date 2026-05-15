import SwiftUI

/// Left rail: current workspace, recent runs, saved presets. Click a
/// preset or run to repopulate the form via the closures passed in from
/// `RootView`.
struct Sidebar: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var workspaces: WorkspaceService
    @EnvironmentObject var presets: PresetStore
    @EnvironmentObject var runner: ArchiveRunner

    @Binding var showWorkspaceSheet: Bool
    var onApplyPreset: (ArchivePreset) -> Void
    var onApplyHistory: (RunHistoryEntry) -> Void

    var body: some View {
        AppThemeReader { theme in
            VStack(alignment: .leading, spacing: 16) {
                header
                workspaceSection(theme: theme)
                Divider()
                recentSection
                Divider()
                presetSection
                Spacer()
                footer(theme: theme)
            }
            .padding(14)
            .background(.thinMaterial)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 18, weight: .semibold))
            Text("SlackSucker")
                .font(AppFont.display(16, weight: .bold))
            Spacer()
        }
    }

    @ViewBuilder
    private func workspaceSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            HStack {
                Text(settings.selectedWorkspace ?? "Not selected")
                    .font(AppFont.sans(13, weight: .semibold))
                    .foregroundStyle(settings.selectedWorkspace == nil ? theme.amber : theme.ink)
                Spacer()
                Button("Manage…") { showWorkspaceSheet = true }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT RUNS")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            if runner.history.entries.isEmpty {
                Text("No runs yet")
                    .font(AppFont.sans(12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(runner.history.entries.prefix(5)) { entry in
                    Button(action: { onApplyHistory(entry) }) {
                        runRow(for: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func runRow(for entry: RunHistoryEntry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(entry.exitOK ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.sidebarTitle)
                    .font(AppFont.sans(12, weight: .medium))
                    .lineLimit(1)
                Text(RelativeTime.short(entry.completedAt))
                    .font(AppFont.sans(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESETS")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            if presets.presets.isEmpty {
                Text("Save a preset to reuse it here")
                    .font(AppFont.sans(12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(presets.presets) { preset in
                    HStack(spacing: 6) {
                        Button(action: { onApplyPreset(preset) }) {
                            Text(preset.name)
                                .font(AppFont.sans(12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            presets.delete(id: preset.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .opacity(0.5)
                    }
                }
            }
        }
    }

    private func footer(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("v\(AppVersion.combined)")
                .font(AppFont.mono(10))
                .foregroundStyle(.tertiary)
        }
    }
}
