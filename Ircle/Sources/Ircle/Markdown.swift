import Foundation

/// A block of Markdown for the in-app reader. Inline spans (`**bold**`,
/// `*italic*`, `` `code` ``, `[links](url)`) are left in the text and rendered
/// later via `AttributedString(markdown:)`.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(String)
    case quote(String)
    case code(String)        // a fenced block's contents (joined by newlines)
    case rule
}

/// A deliberately small Markdown block parser — enough for the manual: ATX
/// headings, paragraphs, `-`/`*` bullets, `1.` numbered items, `>` quotes,
/// fenced ``` code blocks, and `---` rules. Indented continuation lines fold
/// into the preceding list item / quote; consecutive flush lines fold into one
/// paragraph. Pure and dependency-free.
enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        func flushPara() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] }
        }

        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indented = raw.first == " " || raw.first == "\t"

            // Fenced code block.
            if line.hasPrefix("```") {
                flushPara()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1   // skip the closing fence
                continue
            }

            if line.isEmpty { flushPara(); i += 1; continue }

            if line == "---" || line == "***" || line == "___" {
                flushPara(); blocks.append(.rule); i += 1; continue
            }

            if line.hasPrefix("#") {
                flushPara()
                let hashes = line.prefix { $0 == "#" }.count
                let text = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(hashes, 6), text: text)); i += 1; continue
            }

            if line.hasPrefix("> ") || line == ">" {
                flushPara()
                blocks.append(.quote(line == ">" ? "" : String(line.dropFirst(2)))); i += 1; continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushPara(); blocks.append(.bullet(String(line.dropFirst(2)))); i += 1; continue
            }

            if let r = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                flushPara(); blocks.append(.numbered(String(line[r.upperBound...]))); i += 1; continue
            }

            // Continuation of the preceding list item / quote (indented), or a
            // paragraph line.
            if indented, para.isEmpty, let last = blocks.last {
                switch last {
                case .bullet(let t):   blocks[blocks.count - 1] = .bullet(t + " " + line); i += 1; continue
                case .numbered(let t): blocks[blocks.count - 1] = .numbered(t + " " + line); i += 1; continue
                case .quote(let t):    blocks[blocks.count - 1] = .quote((t.isEmpty ? "" : t + " ") + line); i += 1; continue
                default: break
                }
            }
            para.append(line)
            i += 1
        }
        flushPara()
        return blocks
    }
}
