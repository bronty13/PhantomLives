import SwiftUI
import AppKit

/// Click-to-copy clip ID label. Renders the ID in a monospaced font and
/// copies it to the clipboard on click; flashes a brief "Copied" toast
/// over the label so the user knows it worked. Drop-in replacement for
/// `Text(clip.id).font(.caption.monospaced())` everywhere clip IDs are
/// shown — list rows, sticky headers, audit banners, posting windows.
///
/// `style` lets the call site pick the font / colour to match the
/// surrounding context.
struct ClipIDLabel: View {
    enum Style {
        case caption
        case captionTertiary
        case captionSecondary
        case body
    }

    let id: String
    var style: Style = .caption

    @State private var justCopied: Bool = false

    var body: some View {
        Text(id)
            .font(font)
            .foregroundStyle(foreground)
            .textSelection(.enabled)
            .lineLimit(1)
            .help(justCopied ? "Copied!" : "Click to copy clip ID")
            .overlay(alignment: .trailing) {
                if justCopied {
                    Text("Copied")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.thickMaterial, in: Capsule())
                        .foregroundStyle(.green)
                        .offset(x: 60)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                copy()
            }
    }

    private var font: Font {
        switch style {
        case .caption, .captionTertiary, .captionSecondary:
            return .caption.monospaced()
        case .body:
            return .body.monospaced()
        }
    }

    private var foreground: HierarchicalShapeStyle {
        switch style {
        case .caption, .body:    return .primary
        case .captionSecondary:  return .secondary
        case .captionTertiary:   return .tertiary
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
        }
    }
}
