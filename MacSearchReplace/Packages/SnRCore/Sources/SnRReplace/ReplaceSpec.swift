import Foundation
import SnREncoding

/// Specification for a replacement applied alongside a search.
public struct ReplaceSpec: Sendable, Codable, Hashable {

    public enum Mode: String, Sendable, Codable, Hashable {
        case literal
        case regex
        case binary
    }

    public var pattern: String
    public var replacement: String
    public var mode: Mode
    public var caseInsensitive: Bool
    public var multiline: Bool

    /// Counter operator: when present, occurrences of the literal token
    /// `#{start,step,format}` inside `replacement` are expanded per-match.
    /// Format follows printf (e.g. `%04d`).
    public var counterEnabled: Bool

    /// File/path interpolation tokens enabled (%FILE%, %PATH%, %BASENAME%).
    public var interpolatePathTokens: Bool

    /// Backup destination root. nil → default
    /// (~/Library/Application Support/MacSearchReplace/Backups/<timestamp>).
    public var backupRoot: URL?

    /// Whether to preserve the original mtime on rewritten files.
    public var preserveMtime: Bool

    /// Length-changing binary edits (extremely dangerous). Default false.
    public var allowLengthChangingBinary: Bool

    public init(
        pattern: String,
        replacement: String,
        mode: Mode = .literal,
        caseInsensitive: Bool = false,
        multiline: Bool = false,
        counterEnabled: Bool = false,
        interpolatePathTokens: Bool = false,
        backupRoot: URL? = nil,
        preserveMtime: Bool = true,
        allowLengthChangingBinary: Bool = false
    ) {
        self.pattern = pattern
        self.replacement = replacement
        self.mode = mode
        self.caseInsensitive = caseInsensitive
        self.multiline = multiline
        self.counterEnabled = counterEnabled
        self.interpolatePathTokens = interpolatePathTokens
        self.backupRoot = backupRoot
        self.preserveMtime = preserveMtime
        self.allowLengthChangingBinary = allowLengthChangingBinary
    }
}
