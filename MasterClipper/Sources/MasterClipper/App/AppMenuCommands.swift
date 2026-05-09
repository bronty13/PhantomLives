import SwiftUI

struct AppMenuCommands: Commands {
    var body: some Commands {
        // Replace SwiftUI's default File → New (which would open a brand-new
        // window via WindowGroup) so ⌘N triggers the New Clip flow inside
        // the existing window instead.
        CommandGroup(replacing: .newItem) {
            Button("New Clip") {
                NotificationCenter.default.post(name: .newClipRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import…") {
                NotificationCenter.default.post(name: .importRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
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

            Button("Full Data Export (HTML)…") {
                NotificationCenter.default.post(name: .exportRequested, object: "html")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("PDF Report…") {
                NotificationCenter.default.post(name: .exportRequested, object: "pdf")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Backup") {
            Button("Run Backup Now") {
                NotificationCenter.default.post(name: .backupRequested, object: nil)
            }
        }

        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Reset Window State…") {
                NotificationCenter.default.post(name: .windowResetRequested, object: nil)
            }
            .help("Wipe persisted window frame, split-view widths, and sidebar collapse state. Takes effect after relaunch.")
        }
    }
}

extension Notification.Name {
    static let newClipRequested  = Notification.Name("newClipRequested")
    static let importRequested   = Notification.Name("importRequested")
    static let exportRequested   = Notification.Name("exportRequested")
    static let backupRequested   = Notification.Name("backupRequested")
    static let refineRequested   = Notification.Name("refineRequested")
    static let windowResetRequested = Notification.Name("windowResetRequested")
}
