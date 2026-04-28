import Foundation
import SnRSearch
import SnRReplace

/// On-disk representation of a saved search/replace pipeline.
/// Format version 1 supports a single search and an array of replace steps
/// applied to the same file set.
public struct SnRScript: Sendable, Codable, Equatable {
    public var version: Int
    public var name: String
    public var roots: [String]
    public var include: [String]
    public var exclude: [String]
    public var honorGitignore: Bool
    public var followSymlinks: Bool
    public var maxFileBytes: Int?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    public var steps: [Step]

    public struct Step: Sendable, Codable, Equatable {
        public var type: String           // "literal" | "regex" | "binary"
        public var search: String
        public var replace: String?
        public var caseInsensitive: Bool
        public var multiline: Bool
        public var counter: Bool
        public var interpolatePathTokens: Bool
        // v2 — per-step overrides. nil → inherit from script-level fields.
        public var roots: [String]?
        public var include: [String]?
        public var exclude: [String]?
        public var honorGitignore: Bool?
        public var maxFileBytes: Int?

        public init(
            type: String,
            search: String,
            replace: String? = nil,
            caseInsensitive: Bool = false,
            multiline: Bool = false,
            counter: Bool = false,
            interpolatePathTokens: Bool = false,
            roots: [String]? = nil,
            include: [String]? = nil,
            exclude: [String]? = nil,
            honorGitignore: Bool? = nil,
            maxFileBytes: Int? = nil
        ) {
            self.type = type
            self.search = search
            self.replace = replace
            self.caseInsensitive = caseInsensitive
            self.multiline = multiline
            self.counter = counter
            self.interpolatePathTokens = interpolatePathTokens
            self.roots = roots
            self.include = include
            self.exclude = exclude
            self.honorGitignore = honorGitignore
            self.maxFileBytes = maxFileBytes
        }
    }

    public init(
        version: Int = 1,
        name: String,
        roots: [String],
        include: [String] = [],
        exclude: [String] = [],
        honorGitignore: Bool = true,
        followSymlinks: Bool = false,
        maxFileBytes: Int? = nil,
        modifiedAfter: Date? = nil,
        modifiedBefore: Date? = nil,
        steps: [Step]
    ) {
        self.version = version
        self.name = name
        self.roots = roots
        self.include = include
        self.exclude = exclude
        self.honorGitignore = honorGitignore
        self.followSymlinks = followSymlinks
        self.maxFileBytes = maxFileBytes
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
        self.steps = steps
    }

    public static func load(from url: URL) throws -> SnRScript {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(SnRScript.self, from: data)
    }

    public func write(to url: URL) throws {
        try JSONEncoder.pretty.encode(self).write(to: url)
    }

    // MARK: - Convert to runtime specs

    public func searchSpec(forStep step: Step) -> SearchSpec {
        SearchSpec(
            pattern: step.search,
            kind: step.type == "regex" ? .regex : .literal,
            caseInsensitive: step.caseInsensitive,
            wholeWord: false,
            multiline: step.multiline,
            roots: (step.roots ?? roots).map { URL(fileURLWithPath: $0) },
            includeGlobs: step.include ?? include,
            excludeGlobs: step.exclude ?? exclude,
            honorGitignore: step.honorGitignore ?? honorGitignore,
            followSymlinks: followSymlinks,
            maxFileBytes: step.maxFileBytes ?? maxFileBytes,
            modifiedAfter: modifiedAfter,
            modifiedBefore: modifiedBefore
        )
    }

    public func replaceSpec(forStep step: Step) -> ReplaceSpec? {
        guard let replace = step.replace else { return nil }
        let mode: ReplaceSpec.Mode
        switch step.type {
        case "regex":  mode = .regex
        case "binary": mode = .binary
        default:       mode = .literal
        }
        return ReplaceSpec(
            pattern: step.search,
            replacement: replace,
            mode: mode,
            caseInsensitive: step.caseInsensitive,
            multiline: step.multiline,
            counterEnabled: step.counter,
            interpolatePathTokens: step.interpolatePathTokens
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
