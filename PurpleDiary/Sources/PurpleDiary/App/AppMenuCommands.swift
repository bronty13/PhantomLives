import SwiftUI

/// Notification names posted by menu commands and observed by `ContentView`,
/// keeping the App-level menu decoupled from the view tree.
extension Notification.Name {
    static let newEntryRequested    = Notification.Name("PurpleDiary.newEntryRequested")
    static let backupRequested      = Notification.Name("PurpleDiary.backupRequested")
    static let exportRequested      = Notification.Name("PurpleDiary.exportRequested")
    static let importRequested      = Notification.Name("PurpleDiary.importRequested")
    static let windowResetRequested = Notification.Name("PurpleDiary.windowResetRequested")
    static let lockRequested        = Notification.Name("PurpleDiary.lockRequested")
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

            Button("Export Journal…") {
                NotificationCenter.default.post(name: .exportRequested, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Import Journal…") {
                NotificationCenter.default.post(name: .importRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Lock PurpleDiary") {
                NotificationCenter.default.post(name: .lockRequested, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command])
        }

        CommandGroup(after: .windowArrangement) {
            Button("Reset Window State…") {
                NotificationCenter.default.post(name: .windowResetRequested, object: nil)
            }
        }

        CommandGroup(replacing: .help) {
            HelpDocMenuItems()
        }
    }
}

/// The Help menu items: **PurpleDiary User Manual** (⌘?) and **Security &
/// Privacy whitepaper**. Each opens its in-app `MarkdownDocView` window (ids
/// `user-manual` / `security-doc`, declared in `PurpleDiaryApp`). Kept as their
/// own view so they can reach `\.openWindow` from inside the App-level Commands
/// block.
private struct HelpDocMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("PurpleDiary User Manual") {
            openWindow(id: "user-manual")
        }
        .keyboardShortcut("?", modifiers: [.command])

        Button("Security & Privacy whitepaper…") {
            openWindow(id: "security-doc")
        }
    }
}
