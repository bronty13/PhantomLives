import AppKit

/// Tiny clipboard helper. Used by the message area's Copy / Copy All actions so
/// users can always lift text (e.g. an error line) out of the console, even
/// where SwiftUI drag-selection is unreliable.
enum Pasteboard {
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
