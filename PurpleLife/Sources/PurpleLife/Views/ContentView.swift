import SwiftUI

/// Main split-view surface — sidebar of types on the left, the selected
/// type's records on the right. Phase 2 starting point. Today / Planner
/// (Phase 3) takes over the detail-pane default once it lands.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .frame(minWidth: 220)
        } detail: {
            if appState.showTodayInDetail {
                TodayScreen()
            } else if let typeId = appState.selectedTypeId {
                RecordsScreen(typeId: typeId)
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Wire SwiftUI's main-window undo manager into the engines
            // so ⌘Z routes to the same instance the mutation methods
            // register against. RecordsScreen and SchemaEditorScreen
            // re-do the same wiring on their own appear hooks (their
            // window may have a different env value), but doing it
            // here covers the Today screen and any other root-level
            // surface that mutates indirectly.
            ObjectEngine.undoManager = undoManager
            appState.schema.undoManager = undoManager
        }
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
