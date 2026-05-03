import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailRouterView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct DetailRouterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.selectedSection {
            case .dashboard:    DashboardView()
            case .editingQueue: EditingQueueView()
            case .clips:        ClipListView()
            case .calendar:     CalendarRootView()
            case .postingBatch: PostingBatchView()
            case .reports:      ReportsRootView()
            case .importView:   ImportWizardView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
