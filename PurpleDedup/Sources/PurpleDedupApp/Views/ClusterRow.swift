import SwiftUI

/// Single row in the cluster sidebar list. Layout: small accent dot + title
/// & subtitle stack + cross-source / "in Photos" indicators + review-state
/// checkmark on the trailing edge. Tag-based selection drives the parent
/// list's `selectedClusterID` binding directly — this view only renders.
///
/// All "is this cluster X?" decisions are computed by the caller and passed
/// in as bools so this view doesn't need a back-channel into ContentView's
/// state. Keeps it pure and trivially preview-able.
struct ClusterRow: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    let isCrossSource: Bool
    let isArchivedInPhotos: Bool
    /// True when the engine (or user) has produced a per-file decision for
    /// every file in this cluster — drives the trailing checkmark.
    let isReviewed: Bool
    /// True when at least one decision in the cluster came from a manual
    /// override — flips the trailing checkmark from green (engine) to
    /// orange (touched).
    let hasManualOverride: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(accentColor.opacity(0.7)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.body)
                    if isCrossSource {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                            .help("Files in this cluster span multiple scan sources")
                    }
                    if isArchivedInPhotos {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("At least one file in this cluster is also archived in your Photos library — safe to delete the folder copy.")
                    }
                }
                Text(subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if isReviewed {
                Image(systemName: hasManualOverride ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(hasManualOverride ? .orange : .green)
                    .font(.caption)
                    .help(hasManualOverride ? "Reviewed (with manual override)" : "Reviewed (engine recommendation)")
            }
        }
        .padding(.vertical, 2)
    }
}
