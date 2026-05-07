import SwiftUI
import AppKit

/// Root window content. Hosts the `NavigationSplitView` (sidebar +
/// `DetailRouterView`) and the global toolbar / alert chrome. Listens for
/// menu-driven `NotificationCenter` events (new case, new event, export,
/// backup, window reset) so the App-level menu commands stay decoupled from
/// the view tree. Export and backup results surface as success / error
/// alerts here.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingResetConfirm: Bool = false
    @State private var showingNewCase: Bool = false
    @State private var showingExportError: String?
    @State private var showingExportSuccess: URL?
    @State private var showingBackupError: String?
    @State private var showingBackupSuccess: URL?

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailRouterView()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingNewCase = true
                } label: {
                    Label("New Case", systemImage: "folder.fill.badge.plus")
                }
                .help("Create a new case (⌘N)")

                Button {
                    runBackupNow()
                } label: {
                    Label("Backup", systemImage: "externaldrive.fill.badge.timemachine")
                }
                .help("Back up the database to the configured backup directory.")
            }
        }
        .sheet(isPresented: $showingNewCase) {
            NewCaseSheet()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowResetRequested)) { _ in
            showingResetConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCaseRequested)) { _ in
            showingNewCase = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .backupRequested)) { _ in
            runBackupNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { note in
            // The notification's `object` is the format string ("html" / "pdf").
            // Default to HTML when posted from a context that doesn't specify.
            let format = (note.object as? String) ?? "html"
            exportSelectedCase(format: format)
        }
        // Fallback handler for ⌘E (New Event) — runs only when CaseDetailView
        // isn't on screen, so the user gets useful feedback instead of a
        // silent no-op. If at least one case exists, auto-select it and
        // navigate to All Cases (the case-detail handler will then catch
        // a re-posted notification and show the editor).
        .onReceive(NotificationCenter.default.publisher(for: .newEventRequested)) { _ in
            if appState.selectedCase == nil {
                if let target = appState.cases.first {
                    appState.selectedSection = .allCases
                    appState.selectedCaseId = target.id
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .newEventRequested, object: nil)
                    }
                } else {
                    // No cases exist yet — prompt for one. The user can hit
                    // ⌘E again after creating it.
                    showingNewCase = true
                }
            }
        }
        .alert("Reset window state?", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Quit", role: .destructive) {
                TimelinerApp.forceWindowResetNow()
                NSApp.terminate(nil)
            }
        } message: {
            Text("Wipes the persisted window frame, split-view widths, and sidebar collapse state, then quits. Relaunch from the Dock or Finder.")
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
        .alert("Export failed", isPresented: Binding(
            get: { showingExportError != nil },
            set: { if !$0 { showingExportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingExportError ?? "")
        }
        .alert("Exported", isPresented: Binding(
            get: { showingExportSuccess != nil },
            set: { if !$0 { showingExportSuccess = nil } }
        )) {
            Button("Show in Finder") {
                if let url = showingExportSuccess {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingExportSuccess?.lastPathComponent ?? "")
        }
    }

    private func runBackupNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: appState.settingsStore)
            showingBackupSuccess = url
        } catch {
            showingBackupError = error.localizedDescription
        }
    }

    private func exportSelectedCase(format: String) {
        guard let aCase = appState.selectedCase else {
            showingExportError = "Select a case in the sidebar before exporting."
            return
        }
        let events = appState.events.filter { $0.caseId == aCase.id }
        let people = appState.people.filter { $0.caseId == aCase.id }
        let tagsByEvent = appState.tagsByEvent
        let peopleByEvent = appState.peopleByEvent
        let exportDir = appState.settingsStore.resolvedExportDirectory

        switch format {
        case "pdf":
            // PDF goes through WKWebView and is async — wrap in a Task so the
            // notification handler returns immediately.
            Task { @MainActor in
                do {
                    let url = try await ExportService.exportCaseAsPDF(
                        aCase,
                        events: events,
                        people: people,
                        tagsByEvent: tagsByEvent,
                        peopleByEvent: peopleByEvent,
                        exportDir: exportDir
                    )
                    showingExportSuccess = url
                } catch {
                    showingExportError = error.localizedDescription
                }
            }
        default:
            do {
                let url = try ExportService.exportCaseAsHTML(
                    aCase,
                    events: events,
                    people: people,
                    tagsByEvent: tagsByEvent,
                    peopleByEvent: peopleByEvent,
                    exportDir: exportDir
                )
                showingExportSuccess = url
            } catch {
                showingExportError = error.localizedDescription
            }
        }
    }
}

struct DetailRouterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.selectedSection {
            case .dashboard: DashboardView()
            case .allCases:  CaseListView()
            case .crossCase: CrossCaseTimelineView()
            case .people:    GlobalPeopleView()
            case .tags:      TagsView()
            case .search:    SearchView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
