import Foundation
import SnREncoding

/// A streaming search backend.
public struct Searcher: Sendable {

    public typealias Stream = AsyncThrowingStream<FileMatches, Error>

    public enum Backend: Sendable {
        case ripgrep
        case nativeFallback   // pure-Swift, used only if rg is missing
    }

    public let backend: Backend
    public let ripgrepURL: URL?

    public static func ripgrep(at url: URL? = nil) -> Searcher {
        Searcher(backend: .ripgrep, ripgrepURL: url ?? RipgrepLocator.locate())
    }

    public static var nativeFallback: Searcher {
        Searcher(backend: .nativeFallback, ripgrepURL: nil)
    }

    public func stream(spec: SearchSpec) -> Stream {
        switch backend {
        case .ripgrep where ripgrepURL != nil:
            return ripgrepStream(spec: spec, rgURL: ripgrepURL!)
        default:
            return nativeStream(spec: spec)
        }
    }

    // MARK: - ripgrep backend

    private func ripgrepStream(spec: SearchSpec, rgURL: URL) -> Stream {
        AsyncThrowingStream { continuation in
            let task = Process()
            task.executableURL = rgURL
            task.arguments = buildRipgrepArgs(spec: spec)

            let stdout = Pipe()
            let stderr = Pipe()
            task.standardOutput = stdout
            task.standardError = stderr

            task.terminationHandler = { _ in
                continuation.finish()
            }

            let state = StreamState(continuation: continuation)

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    state.flush()
                    handle.readabilityHandler = nil
                    return
                }
                state.consume(chunk)
            }

            continuation.onTermination = { _ in
                if task.isRunning { task.terminate() }
            }

            do {
                try task.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Mutable buffer state shared between the `readabilityHandler` callback
    /// and the AsyncThrowingStream continuation. Wrapped in a class with a
    /// lock to satisfy Swift 6 concurrency checks.
    private final class StreamState: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var currentPath: String?
        private var currentHits: [Hit] = []
        private let continuation: Stream.Continuation

        init(continuation: Stream.Continuation) {
            self.continuation = continuation
        }

        func consume(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let event = RipgrepJSONDecoder.decode(line: line) else { continue }
                switch event {
                case .begin(let path):
                    currentPath = path
                    currentHits = []
                case .match(_, let lineNumber, let lines, let submatches):
                    for sm in submatches {
                        currentHits.append(Hit(
                            line: lineNumber,
                            columnStart: sm.start + 1,
                            columnEnd: sm.end + 1,
                            byteStart: sm.start,
                            byteEnd: sm.end,
                            preview: lines.trimmingCharacters(in: .newlines),
                            matchedText: sm.matchText
                        ))
                    }
                case .end(let path, _):
                    continuation.yield(FileMatches(
                        url: URL(fileURLWithPath: path),
                        hits: currentHits
                    ))
                    currentPath = nil
                    currentHits = []
                case .summary, .context:
                    break
                }
            }
        }

        func flush() {
            lock.lock(); defer { lock.unlock() }
            if let path = currentPath, !currentHits.isEmpty {
                continuation.yield(FileMatches(url: URL(fileURLWithPath: path), hits: currentHits))
            }
            currentPath = nil
            currentHits.removeAll()
        }
    }

    private func buildRipgrepArgs(spec: SearchSpec) -> [String] {
        var args: [String] = ["--json"]
        if spec.caseInsensitive { args.append("-i") }
        if spec.wholeWord       { args.append("-w") }
        if spec.multiline       { args.append("-U"); args.append("--multiline-dotall") }
        if !spec.honorGitignore { args.append("--no-ignore") }
        if spec.followSymlinks  { args.append("-L") }
        if let max = spec.maxFileBytes { args.append("--max-filesize"); args.append("\(max)") }
        for g in spec.includeGlobs { args.append("-g"); args.append(g) }
        for g in spec.excludeGlobs { args.append("-g"); args.append("!\(g)") }

        if spec.kind == .literal { args.append("-F") }

        args.append("--")
        args.append(spec.pattern)
        for r in spec.roots { args.append(r.path) }
        return args
    }

    // MARK: - Native fallback (used when ripgrep is unavailable; tests rely on this)

    private func nativeStream(spec: SearchSpec) -> Stream {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let regex = try NSRegularExpression(
                        pattern: spec.kind == .literal
                            ? NSRegularExpression.escapedPattern(for: spec.pattern)
                            : spec.pattern,
                        options: spec.caseInsensitive ? [.caseInsensitive] : []
                    )
                    for root in spec.roots {
                        Self.scan(root: root, regex: regex, spec: spec, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func scan(
        root: URL,
        regex: NSRegularExpression,
        spec: SearchSpec,
        continuation: Stream.Continuation
    ) {
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: spec.followSymlinks ? [] : [.skipsHiddenFiles]
        ) else { return }

        while let any = enumerator.nextObject() {
            guard let url = any as? URL else { continue }
            guard let vals = try? url.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            guard vals.isRegularFile == true else { continue }
            if let max = spec.maxFileBytes, let size = vals.fileSize, size > max { continue }
            if !matchesGlobs(url: url, includes: spec.includeGlobs, excludes: spec.excludeGlobs) { continue }

            let data = (try? Data(contentsOf: url)) ?? Data()
            if EncodingDetector.isProbablyBinary(data: data) { continue }
            let detection = EncodingDetector.detect(data: data)
            guard let text = String(data: data, encoding: detection.encoding) else { continue }

            var hits: [Hit] = []
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            regex.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let r = result else { return }
                let matched = nsText.substring(with: r.range)
                let lineNumber = lineNumberFor(location: r.range.location, in: text)
                hits.append(Hit(
                    line: lineNumber,
                    columnStart: r.range.location + 1,
                    columnEnd: r.range.location + r.range.length + 1,
                    byteStart: r.range.location,
                    byteEnd: r.range.location + r.range.length,
                    preview: lineContaining(location: r.range.location, in: text),
                    matchedText: matched
                ))
            }
            if !hits.isEmpty {
                continuation.yield(FileMatches(url: url, hits: hits))
            }
        }
    }

    private static func lineNumberFor(location: Int, in text: String) -> Int {
        var count = 1
        let ns = text as NSString
        let prefix = ns.substring(to: min(location, ns.length))
        for c in prefix where c == "\n" { count += 1 }
        return count
    }

    private static func lineContaining(location: Int, in text: String) -> String {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        return ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
    }

    private static func matchesGlobs(url: URL, includes: [String], excludes: [String]) -> Bool {
        let name = url.lastPathComponent
        if !includes.isEmpty {
            let any = includes.contains { fnmatch($0, name) }
            if !any { return false }
        }
        for ex in excludes where fnmatch(ex, name) { return false }
        return true
    }

    private static func fnmatch(_ pattern: String, _ name: String) -> Bool {
        var p = pattern[...]
        var n = name[...]
        while let pc = p.first {
            if pc == "*" {
                p.removeFirst()
                if p.isEmpty { return true }
                while !n.isEmpty {
                    if fnmatch(String(p), String(n)) { return true }
                    n.removeFirst()
                }
                return false
            } else if pc == "?" {
                if n.isEmpty { return false }
                p.removeFirst(); n.removeFirst()
            } else {
                if n.first != pc { return false }
                p.removeFirst(); n.removeFirst()
            }
        }
        return n.isEmpty
    }
}
