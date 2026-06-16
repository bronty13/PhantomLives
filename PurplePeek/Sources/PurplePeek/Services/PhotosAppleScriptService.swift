import Foundation
import AppKit

/// Sets title / caption / keywords on an already-imported Photos asset by driving Photos
/// via AppleScript. This is how metadata reaches **videos** (which PhotoKit can't write and
/// which exiftool-embedding doesn't carry into Photos), and a fallback for photos whose
/// embedding didn't take. Requires the one-time "PurplePeek controls Photos" Automation
/// grant (the app ships `NSAppleEventsUsageDescription`).
///
/// `name` and `description` are well-supported settable properties of a Photos `media item`.
/// `keywords` settability varies by macOS version, so it's applied as a separate, best-effort
/// script — if it isn't supported, title/caption still succeed.
enum PhotosAppleScriptService {

    struct Result { var titleCaptionOK: Bool; var keywordsOK: Bool; var error: String? }

    /// Apply metadata to the asset with the given PHAsset `localIdentifier` ("UUID/L0/001").
    /// Runs `NSAppleScript` on the main thread (caller is @MainActor).
    @discardableResult
    @MainActor
    static func applyMetadata(localIdentifier: String, title: String?, caption: String?, keywords: [String]) -> Result {
        let uuid = localIdentifier.components(separatedBy: "/").first ?? localIdentifier
        var result = Result(titleCaptionOK: true, keywordsOK: true, error: nil)

        // 1) name + description (the reliable properties).
        var sets: [String] = []
        if let t = title, !t.isEmpty { sets.append("set name of theItem to \"\(escape(t))\"") }
        if let c = caption, !c.isEmpty { sets.append("set description of theItem to \"\(escape(c))\"") }
        if !sets.isEmpty {
            let src = """
            tell application "Photos"
                set theItem to media item id "\(escape(uuid))"
                \(sets.joined(separator: "\n    "))
            end tell
            """
            if let err = run(src) {
                result.titleCaptionOK = false
                result.error = err
            }
        }

        // 2) keywords — separate, best-effort (dictionary support varies).
        if !keywords.isEmpty {
            let list = keywords.map { "\"\(escape($0))\"" }.joined(separator: ", ")
            let src = """
            tell application "Photos"
                set theItem to media item id "\(escape(uuid))"
                set keywords of theItem to {\(list)}
            end tell
            """
            if run(src) != nil { result.keywordsOK = false }
        }
        return result
    }

    /// Run a script; return an error string on failure, nil on success.
    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return "couldn't compile" }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error { return (error[NSAppleScript.errorMessage] as? String) ?? "\(error)" }
        return nil
    }

    /// Escape for an AppleScript double-quoted string literal; flatten newlines (AppleScript
    /// literals can't contain raw line breaks).
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\r", with: " ")
    }
}
