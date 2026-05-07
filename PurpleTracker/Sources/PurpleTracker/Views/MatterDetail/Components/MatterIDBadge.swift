import SwiftUI
import AppKit

/// Big copyable Matter ID badge — rendered everywhere a Matter ID appears
/// in the UI per the spec ("always represented in clear large text and always
/// has a copy button next to it").
struct MatterIDBadge: View {
    let matterId: String
    var color: Color = .accentColor
    var size: Font = .system(size: 28, design: .monospaced).weight(.heavy)

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(matterId)
                .font(size)
                .foregroundStyle(color)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(matterId, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy Matter ID")
        }
    }
}
