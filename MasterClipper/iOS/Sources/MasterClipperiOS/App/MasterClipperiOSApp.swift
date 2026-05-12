import SwiftUI
import MasterClipperCore

@main
struct MasterClipperiOSApp: App {
    @StateObject private var appState = iOSAppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { await appState.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: iOSAppState

    var body: some View {
        NavigationStack {
            ClipListView()
        }
    }
}
