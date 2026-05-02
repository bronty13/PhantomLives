import SwiftUI

@main
struct WeightTrackerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppMenuCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Weight Entry") {
                NotificationCenter.default.post(name: .addEntryRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Export") {
            Button("Export CSV…") {
                NotificationCenter.default.post(name: .exportRequested, object: "csv")
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            Button("Export Markdown…") {
                NotificationCenter.default.post(name: .exportRequested, object: "md")
            }
            Button("Export XLSX…") {
                NotificationCenter.default.post(name: .exportRequested, object: "xlsx")
            }
            Button("Export DOCX…") {
                NotificationCenter.default.post(name: .exportRequested, object: "docx")
            }
            Divider()
            Button("PDF Report…") {
                NotificationCenter.default.post(name: .exportRequested, object: "pdf")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Open Reports") {
                NotificationCenter.default.post(name: .navigateToReports, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let addEntryRequested   = Notification.Name("addEntryRequested")
    static let navigateToReports   = Notification.Name("navigateToReports")
    static let exportRequested     = Notification.Name("exportRequested")
    static let exportCSVRequested  = Notification.Name("exportCSVRequested")
    static let exportMDRequested   = Notification.Name("exportMDRequested")
    static let exportXLSXRequested = Notification.Name("exportXLSXRequested")
    static let exportDOCXRequested = Notification.Name("exportDOCXRequested")
    static let exportPDFRequested  = Notification.Name("exportPDFRequested")
    static let printRequested      = Notification.Name("printRequested")
}
