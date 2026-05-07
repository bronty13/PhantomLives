import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingResetConfirm: Bool = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailRouterView()
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .windowResetRequested)) { _ in
            showingResetConfirm = true
        }
        .alert("Reset window state?", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Quit", role: .destructive) {
                MasterClipperApp.forceWindowResetNow()
                NSApp.terminate(nil)
            }
        } message: {
            Text("This wipes the persisted window frame, split-view widths, and sidebar collapse state, then quits the app. Relaunch from the Dock or Finder — the window will open at default size and position.")
        }
    }
}

private struct DetailRouterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.selectedSection {
            case .dashboard:    DashboardView()
            case .editingQueue: EditingQueueView()
            case .postingQueue: PostingQueueView()
            case .clips:        ClipListView()
            case .calendar:     CalendarRootView()
            case .postingBatch: PostingBatchView()
            case .reports:       ReportsRootView()
            case .c4sHistorical: C4SHistoricalView()
            case .importView:    ImportWizardView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
