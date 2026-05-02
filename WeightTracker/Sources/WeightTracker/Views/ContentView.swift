import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case entries = "Entries"
    case charts = "Charts"
    case statistics = "Statistics"
    case reports = "Reports"
    case importData = "Import"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:  return "house.fill"
        case .entries:    return "list.bullet.rectangle.fill"
        case .charts:     return "chart.line.uptrend.xyaxis"
        case .statistics: return "function"
        case .reports:    return "square.and.arrow.up.fill"
        case .importData: return "square.and.arrow.down.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SidebarItem = .dashboard
    @State private var showAddEntry = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 220)
        } detail: {
            detailView
                .background(themeBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToReports)) { _ in
            selection = .reports
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { note in
            if let fmt = note.object as? String {
                performExport(fmt)
            }
        }
        .sheet(isPresented: $showAddEntry) {
            AddEntryView(isPresented: $showAddEntry)
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addEntryRequested)) { _ in
            showAddEntry = true
        }
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView()
        case .entries:
            EntryListView()
        case .charts:
            ChartsView()
        case .statistics:
            StatisticsView()
        case .reports:
            ReportsView()
        case .importData:
            ImportWizardView()
        }
    }

    // MARK: - Export (handles menu-bar Export commands regardless of active view)

    private var defaultOutputDir: URL {
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = dl.appendingPathComponent("WeightTracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func performExport(_ format: String) {
        guard !appState.entries.isEmpty else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = defaultOutputDir
        let entries  = appState.entries
        let unit     = appState.settings.weightUnit
        let stats    = appState.stats
        let username = appState.settings.username

        switch format {
        case "csv":
            panel.nameFieldStringValue = "WeightTracker.csv"
            panel.allowedContentTypes  = [.commaSeparatedText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? ExportService.exportCSV(entries: entries, unit: unit)
                .write(to: url, atomically: true, encoding: .utf8)
        case "md":
            panel.nameFieldStringValue = "WeightTracker.md"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? ExportService.exportMarkdown(entries: entries, unit: unit,
                                              stats: stats, username: username)
                .write(to: url, atomically: true, encoding: .utf8)
        case "xlsx":
            panel.nameFieldStringValue = "WeightTracker.xlsx"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            ExportService.exportXLSX(entries: entries, unit: unit).map { try? $0.write(to: url) }
        case "docx":
            panel.nameFieldStringValue = "WeightTracker.docx"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            ExportService.exportDOCX(entries: entries, unit: unit,
                                     stats: stats, username: username).map { try? $0.write(to: url) }
        case "pdf":
            panel.nameFieldStringValue = "WeightTracker Report.pdf"
            panel.allowedContentTypes  = [.pdf]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let data = ExportService.exportPDFReport(entries: entries, stats: stats,
                                                         unit: unit, username: username, chartImage: nil)
                try? data.write(to: url)
            }
        default: break
        }
    }

    var themeBackground: some View {
        LinearGradient(
            colors: appState.currentTheme.gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
