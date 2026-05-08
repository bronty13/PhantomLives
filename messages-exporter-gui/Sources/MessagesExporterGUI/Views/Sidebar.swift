import SwiftUI

/// Frosted-glass sidebar from the Mission Control redesign. The redesign
/// reserves slots for "Recent runs" and "Saved presets" which are not yet
/// backed by persistence — they render disabled with a `Soon` chip until
/// the underlying stores ship. The "New export" item is the only active
/// destination today, so the sidebar is currently single-state.
///
/// The bottom slot is the Full Disk Access status pill — green when the
/// process can read `chat.db`, orange when denied (with a Resolve action
/// that re-opens the FDA sheet).
struct Sidebar: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner
    @Binding var showFDASheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Match the main pane's top inset so the first sidebar nav
            // row aligns with the kicker on the right; the hidden title
            // bar leaves the entire content area to us.
            Spacer().frame(height: 28)

            SidebarItem(label: "Overview",       icon: "square.grid.2x2",         active: false, disabled: true)
            SidebarItem(label: "New export",     icon: "square.and.pencil",       active: true)
            SidebarItem(label: "Recent runs",    icon: "clock",                   active: false, disabled: true, trailing: "Soon")
            SidebarItem(label: "Saved presets",  icon: "star",                    active: false, disabled: true, trailing: "Soon")

            Spacer().frame(height: 16)
            SidebarKicker(label: "Recent")
            // No history store yet — show a flat empty hint rather than
            // fake rows. The placeholder gives the sidebar visual mass and
            // signals where the upcoming feature will live.
            Text("Run history will appear here once the\u{00a0}history store ships.")
                .font(MissionFont.sans(11))
                .foregroundStyle(t.inkMute)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

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
}

private struct SidebarItem: View {
    @Environment(\.missionTheme) private var t
    let label: String
    let icon: String
    var active: Bool = false
    var disabled: Bool = false
    var trailing: String? = nil

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
            if let trailing {
                Text(trailing)
                    .font(MissionFont.sans(10, weight: .semibold))
                    .foregroundStyle(t.inkMute)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }
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
