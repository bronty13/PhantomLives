import Foundation

/// Thread-safe accumulator for byte chunks that may not align with
/// newline boundaries. Locked because `Pipe.readabilityHandler`'s
/// closure is `Sendable` but cannot directly capture mutable `Data`.
///
/// Ported verbatim from messages-exporter-gui's ExportRunner.swift —
/// both apps spawn a child process and stream its stdout into the UI,
/// so the same buffering semantics (split on `\n`, `\r\n`, or bare `\r`;
/// surface CR-overwrite for tqdm-style progress bars) apply here too.
final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private var lastWasCarriageReturn = false
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    /// Returns (line, replacesLast) tuples. `replacesLast` is true when
    /// the previous terminator was a bare `\r`, matching how a terminal
    /// renders a carriage-return overwrite.
    func extractLines() -> [(String, replacesLast: Bool)] {
        lock.lock(); defer { lock.unlock() }
        var result: [(String, Bool)] = []
        while true {
            guard let idx = data.indices.first(where: { data[$0] == 0x0A || data[$0] == 0x0D })
            else { break }

            let lineData = data.prefix(upTo: idx)
            let isCR = data[idx] == 0x0D
            var removeEnd = data.index(after: idx)
            let isBareCR = isCR && (removeEnd >= data.endIndex || data[removeEnd] != 0x0A)
            if isCR && !isBareCR { removeEnd = data.index(after: removeEnd) }
            data.removeSubrange(data.startIndex..<removeEnd)

            let text = String(data: lineData, encoding: .utf8) ?? ""
            let replaces = lastWasCarriageReturn
            lastWasCarriageReturn = isBareCR
            result.append((text, replaces))
        }
        return result
    }

    /// Pull whatever's left as a single line. Used at process exit so we
    /// don't drop the final un-terminated line.
    func drainTrailing() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return [] }
        let tail = String(data: data, encoding: .utf8) ?? ""
        data.removeAll()
        lastWasCarriageReturn = false
        return tail.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
