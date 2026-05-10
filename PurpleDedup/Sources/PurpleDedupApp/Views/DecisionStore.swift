import SwiftUI
import PurpleDedupCore

/// Read/write façade over the two decision dictionaries the host owns:
/// `decisionsByCluster` (engine recommendations) and `manualOverrides`
/// (per-file user overrides that win). Pulled out of `ComparisonView` so
/// `FileCard` can take it as a value and mutate through the bindings without
/// each card knowing the storage shape.
///
/// Construction is cheap (just two binding wrappers); pass `DecisionStore`
/// down by value, mutate via methods.
struct DecisionStore {
    @Binding var decisionsByCluster: [String: ClusterDecisions]
    @Binding var manualOverrides: [String: [URL: Decision]]

    /// Effective decision for `url` in `s`: manual override beats the engine
    /// recommendation; nil when neither has spoken.
    func decision(for url: URL, in s: ClusterSelection) -> Decision? {
        if let manual = manualOverrides[s.id]?[url] { return manual }
        return decisionsByCluster[s.id]?.perFile[url]
    }

    /// Free-text reason from the active decision, suitable for the small caption
    /// below each thumbnail. Returns nil when the decision was the engine's
    /// default and carries no reason string.
    func decisionReason(for url: URL, in s: ClusterSelection) -> String? {
        switch decision(for: url, in: s) {
        case .keep(let r):   return r.isEmpty ? nil : "keeper · \(r)"
        case .delete(let r): return r.isEmpty ? nil : "delete · \(r)"
        case nil:            return nil
        }
    }

    /// True when the user's manual override is the source of the current
    /// decision (engine recommendation may also exist; the override wins).
    /// Drives the "↻ reset" chip and the small hand-icon overlay.
    func isManualOverride(url: URL, in s: ClusterSelection) -> Bool {
        manualOverrides[s.id]?[url] != nil
    }

    func setManual(_ d: Decision, for url: URL, in s: ClusterSelection) {
        var m = manualOverrides[s.id] ?? [:]
        m[url] = d
        manualOverrides[s.id] = m
    }

    func clearManual(for url: URL, in s: ClusterSelection) {
        var m = manualOverrides[s.id] ?? [:]
        m[url] = nil
        if m.isEmpty {
            manualOverrides[s.id] = nil
        } else {
            manualOverrides[s.id] = m
        }
    }
}
