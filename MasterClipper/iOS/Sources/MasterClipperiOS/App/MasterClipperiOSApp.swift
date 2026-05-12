import SwiftUI
import CloudKit
import MasterClipperCore

@main
struct MasterClipperiOSApp: App {
    @StateObject private var appState = iOSAppState()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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
                // AppDelegate forwards CKShare acceptance via NotificationCenter
                // (UIApplicationDelegateAdaptor is the cleanest hook in a
                // pure-SwiftUI app for `userDidAcceptCloudKitShareWith`).
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.acceptedShareNotification)) { note in
                    if let metadata = note.userInfo?[AppDelegate.acceptedShareMetadataKey] as? CKShare.Metadata {
                        Task { await appState.sharedReader.accept(metadata) }
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
        // The Shared tab only surfaces once the user has accepted at least
        // one share — keeps the chrome minimal for solo use.
        if appState.sharedReader.sessions.isEmpty {
            myClipsView
        } else {
            TabView {
                myClipsView
                    .tabItem { Label("My Clips", systemImage: "film.stack") }

                SharedTabView()
                    .tabItem {
                        Label("Shared", systemImage: "person.2.fill")
                    }
                    .badge(appState.sharedReader.sessions.reduce(0) { $0 + $1.clips.count })
            }
        }
    }

    @ViewBuilder
    private var myClipsView: some View {
        if horizontalSizeClass == .regular {
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
            NavigationStack {
                ClipListView(selection: $selectedClipId)
            }
        }
    }
}
