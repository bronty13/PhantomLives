import SwiftUI
import MasterClipperCore

@main
struct MasterClipperiOSApp: App {
    @StateObject private var appState = iOSAppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must be called before app finishes launching — iOS rejects late
        // registrations. The registered handler triggers a fresh snapshot
        // reload off-foreground.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { await appState.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        BackgroundRefresh.scheduleNext()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: iOSAppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedClipId: String?

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad / iPhone landscape: two-column split view.
            NavigationSplitView(columnVisibility: $splitColumnVisibility) {
                ClipListView(selection: $selectedClipId)
            } detail: {
                NavigationStack {
                    if let id = selectedClipId {
                        ClipDetailView(clipId: id)
                    } else {
                        ContentUnavailableView("No clip selected",
                                               systemImage: "film",
                                               description: Text("Pick a clip from the list."))
                    }
                }
            }
        } else {
            // iPhone portrait: navigation stack with push.
            NavigationStack {
                ClipListView(selection: $selectedClipId)
            }
        }
    }
}
