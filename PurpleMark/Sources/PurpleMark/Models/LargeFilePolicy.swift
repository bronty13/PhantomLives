import Foundation

/// Pure size→feature-flags policy for large documents. Past `threshold` the
/// expensive conveniences degrade so a 100MB file stays smooth; past
/// `previewCap` the rendered Document view is truncated (with a "Render
/// anyway" escape hatch) to keep WebKit's content process alive.
struct LargeFilePolicy: Equatable, Sendable {
    /// 10 MB — where spellcheck, smart typography, and focus/typewriter modes
    /// start to visibly drag.
    static let thresholdBytes = 10_000_000
    /// 48 MB — beyond this the preview renders only the leading portion unless
    /// the user explicitly asks for everything.
    static let previewCapBytes = 48_000_000

    let isLarge: Bool
    let spellcheckAllowed: Bool
    let typographyAllowed: Bool      // markdown-it linkify + typographer
    let focusModesAllowed: Bool      // focus + typewriter
    let previewCapped: Bool
    let findDebounce: Duration
    let autoSaveDebounce: Duration

    static func features(forByteSize bytes: Int) -> LargeFilePolicy {
        let large = bytes > thresholdBytes
        return LargeFilePolicy(
            isLarge: large,
            spellcheckAllowed: !large,
            typographyAllowed: !large,
            focusModesAllowed: !large,
            previewCapped: bytes > previewCapBytes,
            findDebounce: .milliseconds(large ? 600 : 250),
            autoSaveDebounce: .milliseconds(large ? 5000 : 800))
    }
}
