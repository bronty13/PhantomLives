import SwiftUI

/// Left sidebar. Phase 1 shows the scanned-roots list (empty on a fresh install) and an
/// app header. The recursive folder tree and per-folder filtering arrive in Phase 2.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.3)

            if appState.scanRoots.isEmpty {
                emptyRoots
            } else {
                rootList
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(theme.accentColor)
                .font(.title3)
            Text("PurplePeek")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyRoots: some View {
        Text("No folders scanned yet.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private var rootList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(appState.scanRoots) { root in
                    Button {
                        appState.selectedRootPath = root.path
                        appState.reloadMediaFiles()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(theme.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(root.displayName).lineLimit(1)
                                Text("\(root.totalFiles) items")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            appState.selectedRootPath == root.path
                                ? theme.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }
}
