import SwiftUI

struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Case") {
                NotificationCenter.default.post(name: .newCaseRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Event") {
                NotificationCenter.default.post(name: .newEventRequested, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .findRequested, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Export") {
            Button("Export Case as HTML…") {
                NotificationCenter.default.post(name: .exportRequested, object: "html")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Export Case as PDF…") {
                NotificationCenter.default.post(name: .exportRequested, object: "pdf")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Backup") {
            Button("Run Backup Now") {
                NotificationCenter.default.post(name: .backupRequested, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Reset Window State…") {
                NotificationCenter.default.post(name: .windowResetRequested, object: nil)
            }
            .help("Wipe persisted window frame and sidebar state. Takes effect after relaunch.")
        }
    }
}

extension Notification.Name {
    static let newCaseRequested     = Notification.Name("Timeliner.newCaseRequested")
    static let newEventRequested    = Notification.Name("Timeliner.newEventRequested")
    static let findRequested        = Notification.Name("Timeliner.findRequested")
    static let exportRequested      = Notification.Name("Timeliner.exportRequested")
    static let backupRequested      = Notification.Name("Timeliner.backupRequested")
    static let windowResetRequested = Notification.Name("Timeliner.windowResetRequested")
}
