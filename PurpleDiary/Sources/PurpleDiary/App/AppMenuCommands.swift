import SwiftUI

/// Notification names posted by menu commands and observed by `ContentView`,
/// keeping the App-level menu decoupled from the view tree.
extension Notification.Name {
    static let newEntryRequested    = Notification.Name("PurpleDiary.newEntryRequested")
    static let backupRequested      = Notification.Name("PurpleDiary.backupRequested")
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
            SecurityDocMenuItem()
        }
    }
}

/// Help → Security & Privacy whitepaper. Opens the in-app `SecurityDocView`
/// window (id `security-doc`, declared in `PurpleDiaryApp`). Kept as its own
/// view so it can reach `\.openWindow` from inside the App-level Commands block.
private struct SecurityDocMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Security & Privacy whitepaper…") {
            openWindow(id: "security-doc")
        }
    }
}
