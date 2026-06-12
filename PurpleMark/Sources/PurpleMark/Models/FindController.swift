import AppKit

/// A command sent from the find bar to the source editor's coordinator (which
/// owns the `NSTextView`). Boxed in a class so it can ride a `Notification`.
enum FindCommand {
    case select(NSRange)
    case replace(NSRange, String)
    case replaceAll([NSRange], String)
}

final class FindCommandBox {
    let command: FindCommand
    init(_ command: FindCommand) { self.command = command }
}

extension Notification.Name {
    static let pmFind = Notification.Name("pm.find")
}

/// Drives Find & Replace over the source text: computes matches (literal or
/// regex, case-sensitive or not), tracks the current match, and asks the editor
/// to select/replace. Replacement is literal in both modes (the regex toggle
/// affects matching only). The matching is pure and unit-tested.
@MainActor
final class FindController: ObservableObject {
    // Single window for now; multi-window will scope this per-window.
    static let shared = FindController()

    @Published var query = "" { didSet { if query != oldValue { dirty = true } } }
    @Published var replacement = ""
    @Published var useRegex = false { didSet { dirty = true } }
    @Published var caseSensitive = false { didSet { dirty = true } }
    @Published var showReplace = false

    @Published private(set) var matches: [NSRange] = []
    @Published var currentIndex = 0
    /// True when more matches exist than `maxMatches` — the label shows "N+".
    @Published private(set) var matchesCapped = false

    /// Set when search inputs change; `recompute(in:)` clears it.
    private var dirty = true

    /// The document version the current `matches` were computed against;
    /// callers compare with `Document.textVersion` to detect staleness.
    private(set) var matchesVersion = -1
    private var recomputeTask: Task<Void, Never>?

    /// Bounds the match array (and replace-all work) on giant documents.
    static let maxMatches = 50_000

    var matchCount: Int { matches.count }
    var hasMatches: Bool { !matches.isEmpty }

    /// Recompute matches against the current document text, synchronously.
    func recompute(in text: String, version: Int = -1) {
        recomputeTask?.cancel()
        applyMatches(FindController.findMatches(query: query, in: text,
                                                regex: useRegex, caseSensitive: caseSensitive),
                     version: version)
    }

    /// Debounced background recompute — text is materialized lazily by the
    /// caller-supplied closure only when the debounce actually fires, so a
    /// keystroke never copies a huge document.
    func scheduleRecompute(debounce: Duration, version: Int,
                           text: @escaping @MainActor () -> String) {
        recomputeTask?.cancel()
        let (query, regex, caseSensitive) = (query, useRegex, self.caseSensitive)
        recomputeTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let snapshot = text()
            let found = await Task.detached(priority: .userInitiated) {
                FindController.findMatches(query: query, in: snapshot,
                                           regex: regex, caseSensitive: caseSensitive)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.applyMatches(found, version: version)
        }
    }

    private func applyMatches(_ found: [NSRange], version: Int) {
        matchesCapped = found.count > FindController.maxMatches
        matches = matchesCapped ? Array(found.prefix(FindController.maxMatches)) : found
        matchesVersion = version
        dirty = false
        if matches.isEmpty {
            currentIndex = 0
        } else if currentIndex >= matches.count {
            currentIndex = matches.count - 1
        }
    }

    func selectCurrent() {
        guard hasMatches else { return }
        post(.select(matches[currentIndex]))
    }

    func next() {
        guard hasMatches else { return }
        currentIndex = (currentIndex + 1) % matches.count
        selectCurrent()
    }

    func previous() {
        guard hasMatches else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        selectCurrent()
    }

    func replaceCurrent() {
        guard hasMatches else { return }
        post(.replace(matches[currentIndex], replacement))
    }

    func replaceAll() {
        guard hasMatches else { return }
        post(.replaceAll(matches, replacement))
    }

    private func post(_ command: FindCommand) {
        NotificationCenter.default.post(name: .pmFind, object: FindCommandBox(command))
    }

    // MARK: - Pure matching (unit-tested)

    nonisolated static func findMatches(query: String, in text: String,
                                        regex: Bool, caseSensitive: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        if regex {
            var options: NSRegularExpression.Options = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            guard let re = try? NSRegularExpression(pattern: query, options: options) else { return [] }
            return re.matches(in: text, range: full)
                .map(\.range)
                .filter { $0.length > 0 }
        }

        var ranges: [NSRange] = []
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var start = 0
        while start < ns.length {
            let searchRange = NSRange(location: start, length: ns.length - start)
            let r = ns.range(of: query, options: options, range: searchRange)
            if r.location == NSNotFound { break }
            ranges.append(r)
            start = r.location + max(1, r.length)
        }
        return ranges
    }
}
