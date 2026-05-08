import SwiftUI

/// Frosted-glass sidebar from the Mission Control redesign. Shows the
/// run history (most recent N) and the saved-preset list, both
/// click-to-apply onto the form. Clicking a recent run repopulates the
/// inputs with what was used; clicking a preset applies the saved
/// configuration.
///
/// The bottom slot is the Full Disk Access status pill — green when the
/// process can read `chat.db`, amber when denied (with a Resolve action
/// that re-opens the FDA sheet).
struct Sidebar: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner
    @EnvironmentObject private var presets: PresetStore
    @Binding var showFDASheet: Bool
    /// Caller-provided callback that takes a recent-run row and pushes
    /// its values back into the form @State. Lives in RootView.
    var applyRecent: (RunHistoryEntry) -> Void
    /// Apply a saved preset onto the form.
    var applyPreset: (ExportPreset) -> Void

    private static let recentLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 28)

            SidebarItem(label: "Overview",      icon: "square.grid.2x2",   active: false, disabled: true)
            SidebarItem(label: "New export",    icon: "square.and.pencil", active: true)

            Spacer().frame(height: 16)
            SidebarKicker(label: "Recent runs")
            recentList
            Spacer().frame(height: 12)
            SidebarKicker(label: "Saved presets")
            presetList

            Spacer()

            FDAPill(showFDASheet: $showFDASheet)
                .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 220)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.ruleSoft).frame(width: 1)
        }
    }

    // MARK: - Recent runs

    @ViewBuilder
    private var recentList: some View {
        let entries = Array(runner.history.entries.prefix(Self.recentLimit))
        if entries.isEmpty {
            EmptyHint(text: "No runs yet. Press Run export to make the first.")
        } else {
            ForEach(entries) { entry in
                Button {
                    applyRecent(entry)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.exitOK ? t.green : t.amber)
                            .frame(width: 6, height: 6)
                            .shadow(color: (entry.exitOK ? t.green : t.amber).opacity(0.55), radius: 4)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.sidebarTitle)
                                .font(MissionFont.sans(12, weight: .medium))
                                .foregroundStyle(t.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(RelativeTime.short(entry.completedAt))
                                .font(MissionFont.sans(10))
                                .foregroundStyle(t.inkMute)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Apply this run's contact + range to the form.")
            }
        }
    }

    // MARK: - Saved presets

    @ViewBuilder
    private var presetList: some View {
        if presets.presets.isEmpty {
            EmptyHint(text: "Save your current setup with the ☆ chip in the header.")
        } else {
            ForEach(presets.presets) { p in
                Button {
                    applyPreset(p)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(t.accent)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name)
                                .font(MissionFont.sans(12, weight: .medium))
                                .foregroundStyle(t.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(presetDetail(p))
                                .font(MissionFont.sans(10))
                                .foregroundStyle(t.inkMute)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Apply this preset to the form.")
                .contextMenu {
                    Button("Delete preset", role: .destructive) {
                        presets.delete(id: p.id)
                    }
                }
            }
        }
    }

    private func presetDetail(_ p: ExportPreset) -> String {
        var parts: [String] = [p.contact.isEmpty ? "—" : p.contact]
        let span = RunStats.formatSpan(start: p.start, end: p.end)
        if span != "—" { parts.append(span) }
        if p.mode == .raw { parts.append("raw") }
        return parts.joined(separator: " · ")
    }
}

private struct SidebarItem: View {
    @Environment(\.missionTheme) private var t
    let label: String
    let icon: String
    var active: Bool = false
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? t.accent : (disabled ? t.inkMute : t.inkDim))
                .frame(width: 16, height: 16)
            Text(label)
                .font(MissionFont.sans(13, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? t.accent : (disabled ? t.inkMute : t.ink))
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? t.accentSoft : .clear)
        )
        .opacity(disabled ? 0.78 : 1)
    }
}

private struct SidebarKicker: View {
    @Environment(\.missionTheme) private var t
    let label: String

    var body: some View {
        Text(label)
            .font(MissionFont.kicker(10))
            .tracking(1.3)
            .foregroundStyle(t.inkMute)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

private struct EmptyHint: View {
    @Environment(\.missionTheme) private var t
    let text: String
    var body: some View {
        Text(text)
            .font(MissionFont.sans(11))
            .foregroundStyle(t.inkMute)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sidebar footer pill summarising FDA state.
///   .granted → "FDA · granted" with green dot
///   .denied  → "FDA · denied"  with amber dot, click to open the sheet
///   .missingDB → "Messages.app · unused" (rare)
///   .unknown → hidden (probe is in flight)
struct FDAPill: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner
    @Binding var showFDASheet: Bool

    var body: some View {
        switch runner.fdaStatus {
        case .unknown:
            EmptyView()
        case .granted:
            pill(dot: t.green,
                 title: "FDA",
                 detail: "granted",
                 action: nil)
        case .denied:
            pill(dot: t.amber,
                 title: "FDA",
                 detail: "denied — click to resolve",
                 action: { showFDASheet = true })
        case .missingDB:
            pill(dot: t.inkMute,
                 title: "Messages.app",
                 detail: "unused",
                 action: nil)
        }
    }

    @ViewBuilder
    private func pill(dot: Color,
                      title: String,
                      detail: String,
                      action: (() -> Void)?) -> some View {
        let body = HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .shadow(color: dot.opacity(0.45), radius: 4)
            (
                Text(title).foregroundStyle(t.ink).fontWeight(.semibold)
                + Text(" · \(detail)").foregroundStyle(t.inkDim)
            )
            .font(MissionFont.sans(11))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(t.ruleSoft, lineWidth: 1)
        )

        if let action {
            Button(action: action) { body }
                .buttonStyle(.plain)
                .help("Full Disk Access is denied — click to open the resolution sheet.")
        } else {
            body
        }
    }
}
