import AppKit
import UniformTypeIdentifiers

/// Registers PurpleMark as the default application for markdown files. Uses the
/// modern `NSWorkspace.setDefaultApplication(at:toOpen:)` API (macOS 12+).
enum DefaultHandlerService {
    /// Content types we want to own as the default editor.
    static var markdownTypes: [UTType] {
        var types: [UTType] = []
        if let md = UTType("net.daringfireball.markdown") { types.append(md) }
        return types
    }

    /// True when PurpleMark is already the default app for markdown.
    static func isDefault() -> Bool {
        guard let md = UTType("net.daringfireball.markdown") else { return false }
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: md) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Makes PurpleMark the default for all markdown content types. Completion
    /// runs on the main actor with the first error encountered, if any.
    static func setAsDefault(completion: @escaping (Error?) -> Void) {
        let appURL = Bundle.main.bundleURL
        let types = markdownTypes
        guard !types.isEmpty else { completion(nil); return }

        let group = DispatchGroup()
        var firstError: Error?
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                if firstError == nil { firstError = error }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(firstError) }
    }
}
