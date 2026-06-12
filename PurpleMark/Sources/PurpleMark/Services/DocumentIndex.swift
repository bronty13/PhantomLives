import Foundation

/// Everything we know about a document that requires a full text scan, computed
/// in ONE background pass so the per-keystroke cost on the main thread is zero:
/// the outline (TOC), the status-bar stats, the UTF-16 offset of every line
/// start (line-number ruler, fence→character mapping), and which lines sit
/// inside fenced code blocks (outline filtering + syntax highlighting).
///
/// Pure and `Sendable` — built off the main actor from an immutable snapshot.
struct DocumentIndex: Sendable {
    let outline: [OutlineItem]
    let stats: DocStats
    /// UTF-16 offset of the first character of each line. Always has at least
    /// one entry (0). `lineStartOffsets.count` == number of lines.
    let lineStartOffsets: [Int]
    /// Half-open ranges of 0-based line indices covered by ``` / ~~~ fenced
    /// code blocks, fence lines included. An unclosed fence runs to the end.
    let fenceLineRanges: [Range<Int>]

    static let empty = DocumentIndex(outline: [], stats: DocStats(),
                                     lineStartOffsets: [0], fenceLineRanges: [])

    /// 0-based line index containing the given UTF-16 offset (binary search).
    func lineIndex(forUTF16Offset offset: Int) -> Int {
        var lo = 0, hi = lineStartOffsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStartOffsets[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Whether the given 0-based line is inside (or on the delimiter of) a
    /// fenced code block.
    func isLineInFence(_ line: Int) -> Bool {
        // Ranges are sorted and disjoint; binary search the candidates.
        var lo = 0, hi = fenceLineRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = fenceLineRanges[mid]
            if line < r.lowerBound { hi = mid - 1 }
            else if line >= r.upperBound { lo = mid + 1 }
            else { return true }
        }
        return false
    }

    /// Fenced-code blocks as UTF-16 character ranges (delimiters included),
    /// for the syntax highlighter. `totalLength` is the document's UTF-16 length.
    func fenceCharacterRanges(totalLength: Int) -> [NSRange] {
        fenceLineRanges.map { characterRange(forLines: $0, totalLength: totalLength) }
    }

    /// Only the fences that intersect `target` — a viewport-sized answer even
    /// when the document holds tens of thousands of code blocks.
    func fenceCharacterRanges(intersecting target: NSRange, totalLength: Int) -> [NSRange] {
        guard !fenceLineRanges.isEmpty else { return [] }
        let firstLine = lineIndex(forUTF16Offset: target.location)
        let lastLine = lineIndex(forUTF16Offset: max(target.location, NSMaxRange(target) - 1))
        return fenceLineRanges
            .filter { $0.lowerBound <= lastLine && $0.upperBound > firstLine }
            .map { characterRange(forLines: $0, totalLength: totalLength) }
    }

    private func characterRange(forLines r: Range<Int>, totalLength: Int) -> NSRange {
        let start = r.lowerBound < lineStartOffsets.count ? lineStartOffsets[r.lowerBound] : totalLength
        let end = r.upperBound < lineStartOffsets.count ? lineStartOffsets[r.upperBound] : totalLength
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Single linear pass over the text. ~O(n) with no intermediate line array.
    static func build(from text: String) -> DocumentIndex {
        let ns = text as NSString
        let length = ns.length

        var outline: [OutlineItem] = []
        var lineStarts: [Int] = [0]
        var fences: [Range<Int>] = []

        var words = 0
        var inWord = false
        var inFence = false
        var fenceMarker: unichar = 0      // '`' or '~'
        var fenceStartLine = 0
        var lineIndex = 0
        var lineStart = 0

        // Per-line scratch examined when the line ends.
        func processLine(start: Int, end: Int, index: Int) {
            // Find the first non-space/tab character.
            var i = start
            while i < end {
                let c = ns.character(at: i)
                if c != 0x20 && c != 0x09 { break }
                i += 1
            }
            guard i < end else { return }
            let first = ns.character(at: i)

            // Fence open/close: ``` or ~~~ after optional indentation.
            if (first == 0x60 || first == 0x7E),                  // ` or ~
               i + 2 < end,
               ns.character(at: i + 1) == first, ns.character(at: i + 2) == first {
                if !inFence {
                    inFence = true
                    fenceMarker = first
                    fenceStartLine = index
                } else if first == fenceMarker {
                    inFence = false
                    fences.append(fenceStartLine..<(index + 1))
                }
                return
            }
            guard !inFence, first == 0x23 else { return }         // '#'

            // ATX heading: 1–6 #'s followed by a space (or nothing).
            var level = 0
            var j = i
            while j < end, ns.character(at: j) == 0x23 { level += 1; j += 1 }
            guard level <= 6 else { return }
            if j < end {
                guard ns.character(at: j) == 0x20 else { return }
            }
            let title = ns.substring(with: NSRange(location: j, length: end - j))
                .trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            outline.append(OutlineItem(level: level, title: title, line: index))
        }

        var i = 0
        while i < length {
            let c = ns.character(at: i)
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                if inWord { words += 1; inWord = false }
            } else if !inWord {
                inWord = true
            }
            if c == 0x0A {
                processLine(start: lineStart, end: i, index: lineIndex)
                lineIndex += 1
                lineStart = i + 1
                lineStarts.append(lineStart)
            }
            i += 1
        }
        if inWord { words += 1 }
        processLine(start: lineStart, end: length, index: lineIndex)
        if inFence { fences.append(fenceStartLine..<(lineIndex + 1)) }

        var stats = DocStats()
        stats.characters = text.count
        stats.lines = length == 0 ? 0 : lineStarts.count
        stats.words = words
        stats.readMinutes = words == 0 ? 0 : max(1, Int((Double(words) / 200.0).rounded(.up)))

        return DocumentIndex(outline: outline, stats: stats,
                             lineStartOffsets: lineStarts, fenceLineRanges: fences)
    }
}
