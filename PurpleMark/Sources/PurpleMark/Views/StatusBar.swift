import SwiftUI

/// Bottom status bar: live word / character / line counts and reading time,
/// matching the OpenMark screenshots (`342 words · 2191 characters · 43 lines ·
/// 2 min read`). Shows selection counts while text is selected, and a
/// "Large file" capsule when the large-file policy is degrading features.
struct StatusBar: View {
    @ObservedObject var doc: Document

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if LargeFilePolicy.features(forByteSize: doc.byteSize).isLarge {
                Text("Large file")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
                    .help("Spellcheck, smart typography, and focus modes are off for files over 10 MB to keep editing fast.")
            }
            if doc.isDirty {
                Text("Edited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
    }

    private var label: String {
        if let sel = doc.selectionStats {
            return "\(sel.words) \(sel.words == 1 ? "word" : "words") selected · \(sel.characters) characters"
        }
        return parts(doc.stats)
    }

    private func parts(_ s: DocStats) -> String {
        var pieces = [
            "\(s.words) " + (s.words == 1 ? "word" : "words"),
            "\(s.characters) characters",
            "\(s.lines) " + (s.lines == 1 ? "line" : "lines"),
        ]
        if s.readMinutes > 0 { pieces.append("\(s.readMinutes) min read") }
        return pieces.joined(separator: " · ")
    }
}
