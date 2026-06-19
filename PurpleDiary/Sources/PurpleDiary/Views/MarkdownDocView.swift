import SwiftUI

/// Renders a bundled Markdown document (e.g. `Docs/SECURITY.md` or
/// `USER_MANUAL.md`, copied into Contents/Resources by project.yml) inside the
/// app, reachable from the **Help** menu. A lightweight hand-rolled block parser
/// keeps the view fast and avoids pulling in a markdown library for two
/// documents. Inline formatting (bold, italic, inline code, links) goes through
/// `AttributedString(markdown:)`; block structure (headings, list items,
/// dividers, code blocks, paragraphs) is laid out manually so headings actually
/// look like headings.
///
/// These are user-facing trust/help artifacts: someone deciding whether to trust
/// PurpleDiary with their most personal writing — or learning how a feature works
/// — deserves to read it without leaving for a browser. The bar isn't "perfect
/// CommonMark" — it's "the document is legible and selectable." One view serves
/// both docs; the caller passes the bundle resource name + a source label.
struct MarkdownDocView: View {

    /// Bundle resource base name (no extension), e.g. `"SECURITY"` / `"USER_MANUAL"`.
    let resource: String
    /// Footer attribution, e.g. "Source: Docs/SECURITY.md in the PurpleDiary repository."
    let sourceLabel: String

    @Environment(\.dismiss) private var dismiss

    @State private var blocks: [Block] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            Divider()
            HStack {
                Text(sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { load() }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .h1(let s):
            Text(s)
                .font(.title.weight(.semibold))
                .padding(.top, 8)
        case .h2(let s):
            Text(s)
                .font(.title2.weight(.semibold))
                .padding(.top, 4)
        case .h3(let s):
            Text(s)
                .font(.title3.weight(.semibold))
        case .paragraph(let attr):
            Text(attr)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let attr):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(attr)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)
        case .numberedItem(let n, let attr):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                Text(attr)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)
        case .codeBlock(let s):
            Text(s)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .divider:
            Divider().padding(.vertical, 4)
        }
    }

    // MARK: - Loading + parsing

    private func load() {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md") else {
            loadError = "\(resource).md not found in the app bundle. This is a build-config bug — it should be listed in project.yml under the app target's sources with type: file (destination: resources)."
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            blocks = Self.parse(text)
        } catch {
            loadError = "Couldn't read \(resource).md: \(error.localizedDescription)"
        }
    }

    enum Block: Identifiable {
        case h1(String)
        case h2(String)
        case h3(String)
        case paragraph(AttributedString)
        case listItem(AttributedString)
        case numberedItem(Int, AttributedString)
        case codeBlock(String)
        case divider

        var id: String {
            switch self {
            case .h1(let s):            return "h1:\(s)"
            case .h2(let s):            return "h2:\(s)"
            case .h3(let s):            return "h3:\(s)"
            case .paragraph(let a):     return "p:\(String(a.characters.prefix(40)))"
            case .listItem(let a):      return "li:\(String(a.characters.prefix(40)))"
            case .numberedItem(let n, let a): return "n\(n):\(String(a.characters.prefix(40)))"
            case .codeBlock(let s):     return "code:\(s.prefix(40))"
            case .divider:              return "hr:\(UUID().uuidString)"
            }
        }
    }

    /// Line-by-line block parser. Handles headings (h1-h3), unordered list items
    /// (`- ` or `* `), numbered items (`1. `), fenced code blocks, horizontal
    /// rules (`---`), and paragraphs (consecutive non-blank lines joined with a
    /// space). Inline formatting goes through `AttributedString(markdown:)` so
    /// bold / italic / code / links render correctly. This is deliberately not a
    /// full CommonMark parser — it's tuned to what SECURITY.md uses. (Tables in
    /// the whitepaper degrade gracefully to paragraph lines, which is acceptable
    /// for an in-app reader.)
    static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var paragraphBuffer: [String] = []
        var inCodeBlock = false
        var codeBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            let attr = (try? AttributedString(markdown: joined,
                                              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(joined)
            out.append(.paragraph(attr))
            paragraphBuffer.removeAll()
        }

        for rawLine in lines {
            // Fenced code blocks. Treat the body as plaintext; do NOT run inline
            // markdown over the contents (so tokens like `<hex>` aren't eaten as
            // inline HTML).
            if rawLine.hasPrefix("```") {
                if inCodeBlock {
                    out.append(.codeBlock(codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                codeBuffer.append(rawLine)
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                out.append(.divider)
                continue
            }
            if trimmed.hasPrefix("### ") {
                flushParagraph()
                out.append(.h3(String(trimmed.dropFirst(4))))
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                out.append(.h2(String(trimmed.dropFirst(3))))
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                out.append(.h1(String(trimmed.dropFirst(2))))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let body = String(trimmed.dropFirst(2))
                let attr = (try? AttributedString(markdown: body,
                                                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(body)
                out.append(.listItem(attr))
                continue
            }
            if let (n, rest) = parseNumberedPrefix(trimmed) {
                flushParagraph()
                let attr = (try? AttributedString(markdown: rest,
                                                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(rest)
                out.append(.numberedItem(n, attr))
                continue
            }
            paragraphBuffer.append(trimmed)
        }
        if inCodeBlock {
            out.append(.codeBlock(codeBuffer.joined(separator: "\n")))
        }
        flushParagraph()
        return out
    }

    /// "1. foo" → (1, "foo"). Returns nil if the prefix isn't a number followed
    /// by `. `. Keeps the parser one-pass.
    private static func parseNumberedPrefix(_ line: String) -> (Int, String)? {
        var digits = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty, idx < line.endIndex, line[idx] == "." else { return nil }
        let after = line.index(after: idx)
        guard after < line.endIndex, line[after] == " " else { return nil }
        guard let n = Int(digits) else { return nil }
        return (n, String(line[line.index(after: after)...]))
    }
}
