import SwiftUI
import PurpleAtticCore

/// Root container — manual `HStack` sidebar (the PhantomLives pattern; never
/// `NavigationSplitView`, which mis-restores column widths on macOS 14+).
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    private let sidebarWidth: CGFloat = 210

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth, alignment: .leading)
                .background(.ultraThinMaterial)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
                Text("PurpleAttic").font(.headline)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            ForEach(Pane.allCases) { pane in
                sidebarRow(pane)
            }
            Spacer()
            readinessFooter
        }
    }

    private func sidebarRow(_ pane: Pane) -> some View {
        Button {
            appState.selectedPane = pane
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pane.icon).frame(width: 18)
                Text(pane.rawValue)
                Spacer()
                if pane == .purge {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(appState.selectedPane == pane ? Color.accentColor.opacity(0.22) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var readinessFooter: some View {
        let r = appState.readiness
        return VStack(alignment: .leading, spacing: 3) {
            Divider()
            toolRow("osxphotos", ok: r.osxphotos != nil)
            toolRow("exiftool", ok: r.exiftool != nil)
            toolRow("rsync", ok: r.rsync != nil)
        }
        .font(.caption2)
        .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 4)
    }

    private func toolRow(_ name: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(name).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedPane {
        case .dashboard: DashboardView()
        case .run: RunView()
        case .schedule: ScheduleView()
        case .profile: ProfileSettingsView(store: appState.store)
        case .offsite: OffsiteSettingsView(store: appState.store)
        case .adhoc: AdhocBackupView(store: appState.store)
        case .backup: BackupSettingsView(store: appState.store)
        case .purge: PurgeSettingsView()
        }
    }
}
