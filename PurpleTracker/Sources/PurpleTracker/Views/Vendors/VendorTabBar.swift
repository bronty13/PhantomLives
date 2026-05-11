import SwiftUI

/// Wrapping tab bar — fills horizontally then wraps to a new row.
/// Used by `VendorDetailView` because its 12 tab labels don't fit in a single
/// row on narrow window widths.
struct VendorTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let label: (Tab) -> String

    var body: some View {
        TabFlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(tabs) { t in
                Button {
                    selection = t
                } label: {
                    Text(label(t))
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selection == t
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// Simple flow layout: places children left-to-right, wrapping to a new row
/// when the next child doesn't fit. Available on macOS 13+.
struct TabFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        let totalHeight = y + rowHeight
        return CGSize(width: min(maxLineWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            v.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
