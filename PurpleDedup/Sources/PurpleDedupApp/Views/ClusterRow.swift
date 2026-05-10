import SwiftUI
import PurpleDedupCore

/// Single row in the cluster sidebar list. Adopted from the design
/// handoff's `GroupRow` layout: 36 × 36 thumbnail of the cluster's first
/// file with an overlapping count badge, then a two-line title/meta stack,
/// then trailing status indicators (cross-source, "in Photos", reviewed
/// checkmark).
///
/// All "is this cluster X?" decisions are computed by the caller and
/// passed in as bools so this view doesn't need a back-channel into
/// ContentView's state. Stays a pure renderer.
struct ClusterRow: View {
    let kind: ClusterKind
    /// First file in the cluster — used as the thumbnail seed. Nil falls
    /// back to a kind-tinted SF Symbol so video / burst / rotated rows
    /// still get a visual handle even before image decode kicks in.
    let firstFile: DiscoveredFile?
    let count: Int
    /// Primary display name — typically the basename of the first file.
    let primaryName: String
    /// Technical meta line ("diameter 4/64", "4.2 MB each · sha:abc…").
    /// Caller decides what's worth showing per-kind.
    let metaLine: String
    /// Reclaimable-bytes label, rendered in the kind's accent colour.
    /// Empty string suppresses the segment.
    let reclaimableLabel: String

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
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                titleLine
                metaRow
            }
            Spacer(minLength: 4)
            trailingStatus
        }
        .padding(.vertical, 3)
    }

    // MARK: - thumbnail

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let f = firstFile {
                    ThumbnailView(url: f.url, size: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: kind.iconName)
                        .font(.title3)
                        .foregroundStyle(kind.accent)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(kind.accent.opacity(0.15))
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(kind.accent.opacity(0.3), lineWidth: 0.5)
            )
            // Count badge in upper-right corner, slightly oversized so it
            // visually anchors the row and gives the user the cluster
            // size at a glance without parsing the meta line.
            if count > 1 {
                Text("\(count)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(kind.accent))
                    .offset(x: 5, y: -5)
            }
        }
        .frame(width: 36, height: 36)
    }

    // MARK: - text rows

    private var titleLine: some View {
        HStack(spacing: 4) {
            Text(primaryName)
                .font(.body.weight(.medium))
                .lineLimit(1).truncationMode(.middle)
            if count > 1 {
                Text("+\(count - 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(kind.chipLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(kind.accent)
            if !metaLine.isEmpty {
                Text("·")
                    .font(.caption2).foregroundStyle(.secondary.opacity(0.6))
                Text(metaLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            if !reclaimableLabel.isEmpty {
                Text("·")
                    .font(.caption2).foregroundStyle(.secondary.opacity(0.6))
                Text(reclaimableLabel)
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(kind.accent)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if isReviewed {
            Image(systemName: hasManualOverride ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(hasManualOverride ? .orange : .green)
                .font(.caption)
                .help(hasManualOverride ? "Reviewed (with manual override)" : "Reviewed (engine recommendation)")
        }
    }
}
