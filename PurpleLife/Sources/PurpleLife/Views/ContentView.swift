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
                // Clamp the sidebar column width so a user can never
                // drag the splitter to absurdity. AppKit's NSSplitView
                // (which SwiftUI's NavigationSplitView wraps on macOS)
                // persists subview frames in the app's UserDefaults
                // under the "NSSplitView Subview Frames …" key — if the
                // saved value exceeds the window width, the sidebar
                // takes the entire window and the detail pane is
                // invisible until the prefs are wiped. The
                // `navigationSplitViewColumnWidth` modifier caps the
                // max so even a hostile drag stays inside the window.
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
        } detail: {
            if appState.showTodayInDetail {
                TodayScreen()
            } else if let typeId = appState.selectedTypeId {
                // The Note type swaps the standard RecordsScreen for the
                // PurpleTracker-style two-pane Notes workspace. Same
                // ObjectEngine + sync underneath; just a different UX.
                if typeId == "Note" {
                    NotesWorkspaceView(typeId: typeId)
                } else {
                    RecordsScreen(typeId: typeId)
                }
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
