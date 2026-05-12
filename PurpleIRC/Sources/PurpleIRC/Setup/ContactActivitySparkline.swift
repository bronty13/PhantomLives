import SwiftUI

/// Tiny bar-chart of message volume for a contact, binned by day over a
/// rolling window. Pulled from each live connection's `SeenStore`
/// history (`kind == "msg"` sightings only — joins/parts/quits are
/// activity but not conversation).
///
/// Lives inside the contact editor in Setup → Address Book and inside
/// the Setup → Address Book row when the user expands a contact. The
/// view itself doesn't know about networks; the caller folds across
/// every connection it cares about before passing the bin array in.
struct ContactActivitySparkline: View {
    /// Daily counts oldest→newest. Length 14 in the default editor
    /// placement; the view scales to whatever length the caller picks.
    let bins: [Int]

    var body: some View {
        let maxV = max(1, bins.max() ?? 1)
        let total = bins.reduce(0, +)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bins.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(bins[i] == 0 ? Color.secondary.opacity(0.2) : Color.purple)
                        .frame(width: 6,
                               height: bins[i] == 0
                                   ? 2
                                   : max(3, CGFloat(bins[i]) / CGFloat(maxV) * 28))
                        .help("\(bins[i]) \(bins[i] == 1 ? "message" : "messages")")
                }
            }
            .frame(height: 30, alignment: .bottom)
            HStack(spacing: 6) {
                Text("\(total) \(total == 1 ? "message" : "messages")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• last \(bins.count) days")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if total == 0 {
                    Text("• nothing recorded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
