import Foundation

/// Specification for a search operation. Roughly mirrors Funduc's main dialog.
public struct SearchSpec: Sendable, Codable, Hashable {

    public enum PatternKind: String, Sendable, Codable, Hashable {
        case literal
        case regex
    }

    public var pattern: String
    public var kind: PatternKind
    public var caseInsensitive: Bool
    public var wholeWord: Bool
    public var multiline: Bool
    public var roots: [URL]
    public var includeGlobs: [String]   // ripgrep --glob patterns
    public var excludeGlobs: [String]   // negated ripgrep --glob patterns
    public var honorGitignore: Bool
    public var followSymlinks: Bool
    public var maxFileBytes: Int?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?

    public init(
        pattern: String,
        kind: PatternKind = .literal,
        caseInsensitive: Bool = false,
        wholeWord: Bool = false,
        multiline: Bool = false,
        roots: [URL],
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        honorGitignore: Bool = true,
        followSymlinks: Bool = false,
        maxFileBytes: Int? = nil,
        modifiedAfter: Date? = nil,
        modifiedBefore: Date? = nil
    ) {
        self.pattern = pattern
        self.kind = kind
        self.caseInsensitive = caseInsensitive
        self.wholeWord = wholeWord
        self.multiline = multiline
        self.roots = roots
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.honorGitignore = honorGitignore
        self.followSymlinks = followSymlinks
        self.maxFileBytes = maxFileBytes
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
    }
}
