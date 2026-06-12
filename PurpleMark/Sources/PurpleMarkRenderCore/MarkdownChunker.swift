import Foundation

/// One renderable slice of a markdown document. `text` is a `Substring`
/// sharing the original string's storage — chunking never copies the document.
public struct MarkdownChunk: Sendable, Equatable {
    /// Positional id (0-based). Stable for a given document state.
    public let id: Int
    /// FNV-1a over the chunk's UTF-8 bytes; the preview re-renders a chunk
    /// only when its hash changes.
    public let hash: UInt64
    public let text: Substring
}

public struct ChunkResult: Sendable {
    public let chunks: [MarkdownChunk]
    /// Reference-link definitions hoisted from the whole document, appended to
    /// every chunk at serve time so `[text][label]` references resolve across
    /// chunk boundaries. Empty when the document has none (or pathologically
    /// many — see `maxRefDefsBytes`).
    public let refDefsSuffix: String
    /// True when `maxTotalBytes` cut the document short (preview cap).
    public let truncated: Bool
    /// UTF-8 size of the full input.
    public let totalBytes: Int
}

/// Splits markdown into ~`targetBytes` chunks at blank-line block boundaries,
/// never inside ``` / ~~~ fenced code. Pure and unit-tested; runs off the main
/// thread for large documents.
public enum MarkdownChunker {
    /// Stop hoisting reference definitions past this much text — appending a
    /// huge suffix to every chunk would defeat the chunking.
    public static let maxRefDefsBytes = 16_384

    public static func fnv1a(_ s: Substring) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public static func split(_ text: String,
                             targetBytes: Int = 64_000,
                             maxTotalBytes: Int? = nil) -> ChunkResult {
        let utf8 = text.utf8
        let totalBytes = utf8.count

        var chunks: [MarkdownChunk] = []
        var refDefs = ""
        var refDefsBytes = 0

        var chunkStart = text.startIndex          // start of the chunk being built
        var chunkBytes = 0                        // bytes accumulated in it
        var lineStart = text.startIndex
        var inFence = false
        var fenceByte: UInt8 = 0                  // '`' (0x60) or '~' (0x7E)
        var truncated = false

        func appendChunk(endingAt end: String.Index) {
            guard chunkStart < end else { return }
            let slice = text[chunkStart..<end]
            chunks.append(MarkdownChunk(id: chunks.count, hash: fnv1a(slice), text: slice))
            chunkStart = end
            chunkBytes = 0
        }

        /// Classifies the line [lineStart, lineEnd) and updates fence state.
        /// Returns true when the line is blank (a safe cut point).
        func scanLine(_ lineEnd: String.Index) -> Bool {
            var i = lineStart
            // Skip indentation.
            while i < lineEnd {
                let b = utf8[i]
                if b != 0x20 && b != 0x09 { break }
                i = utf8.index(after: i)
            }
            guard i < lineEnd else { return true } // blank
            let first = utf8[i]

            // Fence delimiters.
            if first == 0x60 || first == 0x7E {
                var j = i
                var run = 0
                while j < lineEnd, utf8[j] == first, run < 3 {
                    run += 1
                    j = utf8.index(after: j)
                }
                if run == 3 {
                    if !inFence {
                        inFence = true
                        fenceByte = first
                    } else if first == fenceByte {
                        inFence = false
                    }
                    return false
                }
            }

            // Reference-link definition: optional ≤3-space indent, "[label]: target".
            if !inFence, first == 0x5B, refDefsBytes <= maxRefDefsBytes { // '['
                var j = utf8.index(after: i)
                var sawClose = false
                while j < lineEnd {
                    if utf8[j] == 0x5D { sawClose = true; break }          // ']'
                    j = utf8.index(after: j)
                }
                if sawClose {
                    let afterClose = utf8.index(after: j)
                    if afterClose < lineEnd, utf8[afterClose] == 0x3A {    // ':'
                        let def = String(text[lineStart..<lineEnd])
                        refDefs += def + "\n"
                        refDefsBytes += def.utf8.count + 1
                    }
                }
            }
            return false
        }

        var i = text.startIndex
        let endIndex = text.endIndex
        var bytesSeen = 0
        while i < endIndex {
            let b = utf8[i]
            bytesSeen += 1
            chunkBytes += 1
            if b == 0x0A {
                let next = utf8.index(after: i)
                let isBlank = scanLine(i)
                lineStart = next
                if isBlank, !inFence, chunkBytes >= targetBytes {
                    appendChunk(endingAt: next)
                }
                if let cap = maxTotalBytes, bytesSeen >= cap, !inFence {
                    // Preview cap: cut at the next line boundary outside a fence.
                    appendChunk(endingAt: next)
                    truncated = next < endIndex
                    i = next
                    break
                }
                i = next
            } else {
                i = utf8.index(after: i)
            }
        }
        if !truncated {
            _ = scanLine(endIndex)
            appendChunk(endingAt: endIndex)
        }

        if refDefsBytes > maxRefDefsBytes { refDefs = "" }
        return ChunkResult(chunks: chunks, refDefsSuffix: refDefs,
                           truncated: truncated, totalBytes: totalBytes)
    }
}
