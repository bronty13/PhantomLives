import SwiftUI

/// Main split-view surface — sidebar of types on the left, the selected
/// type's records on the right. Phase 2 starting point. Today / Planner
/// (Phase 3) takes over the detail-pane default once it lands.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .frame(minWidth: 220)
        } detail: {
            if let typeId = appState.selectedTypeId {
                TableViewScreen(typeId: typeId)
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Pick a type from the sidebar")
                .font(.headline).foregroundStyle(.secondary)
            Text("\(AppVersion.display)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
