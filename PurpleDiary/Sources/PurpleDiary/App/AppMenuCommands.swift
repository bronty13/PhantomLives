import SwiftUI

/// Notification names posted by menu commands and observed by `ContentView`,
/// keeping the App-level menu decoupled from the view tree.
extension Notification.Name {
    static let newEntryRequested    = Notification.Name("PurpleDiary.newEntryRequested")
    static let backupRequested      = Notification.Name("PurpleDiary.backupRequested")
    static let windowResetRequested = Notification.Name("PurpleDiary.windowResetRequested")
}

/// Menu bar commands: File → New Entry, File → Back Up Now, Window → Reset
/// Window State. Each posts a notification picked up by `ContentView`.
struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                NotificationCenter.default.post(name: .newEntryRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(after: .saveItem) {
            Button("Back Up Now") {
                NotificationCenter.default.post(name: .backupRequested, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        CommandGroup(after: .windowArrangement) {
            Button("Reset Window State…") {
                NotificationCenter.default.post(name: .windowResetRequested, object: nil)
            }
        }
    }
}
