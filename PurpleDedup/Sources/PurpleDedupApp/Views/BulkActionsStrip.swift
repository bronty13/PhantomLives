import SwiftUI
import PurpleDedupCore

/// Bulk-action button row beneath the status strip. Operates over EVERY
/// cluster: applies the rule chain, clears manual overrides, kicks off
/// burst / rotated detection, toggles the cross-source-only filter.
///
/// All work happens through closures so the strip doesn't have to know
/// about scan engines, settings, or the on-disk cache.
struct BulkActionsStrip: View {
    let allClusterCount: Int
    @Binding var manualOverrides: [String: [URL: Decision]]

    let burstScanInProgress: Bool
    let rotatedScanInProgress: Bool
    let canRunBurstDetection: Bool
    let canRunRotatedDetection: Bool

    /// Number of scan sources — the cross-source toggle only renders when
    /// there are at least 2 sources (otherwise the filter is always empty).
    let sourcesCount: Int
    @Binding var crossSourceFilterOn: Bool

    let onApplyToAll: () async -> Void
    let onRunBurstDetection: () async -> Void
    let onRunRotatedDetection: () async -> Void

    var body: some View {
        HStack(spacing: 6) {
            applyToAllButton
            clearOverridesButton
            findBurstsButton
            findRotatedButton
            if sourcesCount >= 2 {
                crossSourceToggle
            }
            Spacer()
        }
    }

    private var applyToAllButton: some View {
        Button {
            Task { await onApplyToAll() }
        } label: {
            Label("Apply to all", systemImage: "wand.and.stars")
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .help("Run the rule chain on every cluster (\(allClusterCount) groups). Manual overrides are preserved.")
    }

    private var clearOverridesButton: some View {
        Button {
            manualOverrides.removeAll()
        } label: {
            Label("Clear overrides", systemImage: "arrow.uturn.backward")
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(manualOverrides.isEmpty)
        .help("Reset every manual KEEP/DELETE override back to the engine's recommendation")
    }

    private var findBurstsButton: some View {
        Button {
            Task { await onRunBurstDetection() }
        } label: {
            if burstScanInProgress {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Finding…")
                }
                .font(.caption)
            } else {
                Label("Find bursts", systemImage: "rectangle.stack")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(burstScanInProgress || !canRunBurstDetection)
        .help("Find rapid-fire photo series the perceptual matcher misses. Reads EXIF capture dates lazily — only runs when you click.")
    }

    private var findRotatedButton: some View {
        Button {
            Task { await onRunRotatedDetection() }
        } label: {
            if rotatedScanInProgress {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Finding…")
                }
                .font(.caption)
            } else {
                Label("Find rotated", systemImage: "rotate.right")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(rotatedScanInProgress || !canRunRotatedDetection)
        .help("Find photos that are exact-content duplicates of each other under 90/180/270° rotation. Re-hashes photos with all four rotations.")
    }

    private var crossSourceToggle: some View {
        Toggle(isOn: $crossSourceFilterOn) {
            Label("Cross-source only", systemImage: "link")
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help("Show only clusters whose files come from 2+ different scan sources — files duplicated between e.g. your Photos library and a folder.")
    }
}
