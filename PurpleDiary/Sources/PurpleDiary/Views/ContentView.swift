import SwiftUI
import AppKit

/// Root container. Uses a plain `HStack` instead of `NavigationSplitView`
/// because `NavigationSplitView`'s runtime layout on macOS 14+ does not honor
/// `.navigationSplitViewColumnWidth(min:)` reliably — the sidebar can render
/// narrower than its declared minimum with no in-app recovery. The manual
/// HStack owns every pixel and AppKit's window-restoration machinery has no
/// split-view divider to mis-restore. This is the canonical PhantomLives
/// pattern (see CLAUDE.md → "Sidebar layout: avoid NavigationSplitView").
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true

    private let sidebarWidth: CGFloat = 240

    @State private var showingBackupError: String?
    @State private var showingBackupSuccess: URL?
    @State private var showingResetConfirm: Bool = false
    @State private var showingExport: Bool = false

    var body: some View {
        // Privacy gates take over the whole window, in priority order:
        // 1. unrecoverable DB (encrypted, key gone) → recovery screen
        // 2. a freshly-generated recovery key the user must save
        // 3. the app-lock screen
        // Otherwise the normal journal UI.
        Group {
            if let message = appState.dbUnrecoverable {
                RecoveryScreen(message: message)
            } else if let words = appState.pendingRecoveryKey {
                RecoveryKeySaveSheet(words: words) { appState.confirmRecoveryKeySaved() }
            } else if appState.appLocked {
                AppLockScreen()
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: sidebarWidth, alignment: .leading)
                    .clipped()
                    .background(.ultraThinMaterial)
                Divider()
            }
            DetailRouterView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar (⌃⌘S)")
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    newEntry()
                } label: {
                    Label("New Entry", systemImage: "square.and.pencil")
                }
                .help("Write a new entry (⌘N)")

                Button {
                    runBackupNow()
                } label: {
                    Label("Backup", systemImage: "externaldrive.fill.badge.timemachine")
                }
                .help("Back up the journal to the configured backup directory.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newEntryRequested)) { _ in
            newEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: .backupRequested)) { _ in
            runBackupNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowResetRequested)) { _ in
            showingResetConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lockRequested)) { _ in
            appState.lockApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
            showingExport = true
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet().environmentObject(appState)
        }
        .alert("Reset window state?", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Quit", role: .destructive) {
                WindowStateGuard.forceReset(appName: "PurpleDiary",
                                            resetVersion: AppDelegate.windowResetVersion)
                NSApp.terminate(nil)
            }
        } message: {
            Text("Wipes the persisted window frame and sidebar state, then quits. Relaunch from the Dock or Finder.")
        }
        .alert("Backup failed", isPresented: Binding(
            get: { showingBackupError != nil },
            set: { if !$0 { showingBackupError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingBackupError ?? "")
        }
        .alert("Backup written", isPresented: Binding(
            get: { showingBackupSuccess != nil },
            set: { if !$0 { showingBackupSuccess = nil } }
        )) {
            Button("Show in Finder") {
                if let url = showingBackupSuccess {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingBackupSuccess?.lastPathComponent ?? "")
        }
    }

    private func newEntry() {
        do {
            try appState.createEntry()
            appState.selectedSection = .timeline
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func runBackupNow() {
        do {
            showingBackupSuccess = try BackupService.doBackup(settingsStore: appState.settingsStore)
        } catch {
            showingBackupError = error.localizedDescription
        }
    }
}

/// Routes the selected sidebar section to its detail view.
struct DetailRouterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.selectedSection {
            case .timeline: TimelineView()
            case .calendar: CalendarView()
            case .onThisDay: OnThisDayView()
            case .insights: InsightsView()
            case .search:   SearchView()
            case .people:   PeopleView()
            case .tags:     TagsView()
            case .trackers: TrackersView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
