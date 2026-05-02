import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarItem

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .background(appState.currentTheme.sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    var sidebarFooter: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.settings.username)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let stats = appState.stats {
                        Text("\(appState.entries.count) entries")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ExportService.fmtChange(stats.totalChange, unit: appState.settings.weightUnit))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(stats.totalChange < 0 ? .green : stats.totalChange > 0 ? .red : .secondary)
                    }
                }
                Spacer()
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(appState.effectiveAccentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
