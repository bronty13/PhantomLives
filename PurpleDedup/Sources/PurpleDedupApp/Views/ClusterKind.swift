import SwiftUI

/// Type-safe identity for the five concrete cluster sections the GUI shows.
/// Replaces the string-prefix ladders ("exact:" / "photo:" / "video:" /
/// "burst:" / "rotated:") that grew across the cluster-list rendering, the
/// cluster-row badge logic, the cluster-kind chip filter, and the per-cluster
/// trash / decision plumbing.
///
/// On-the-wire IDs stay strings of the form `"<rawValue>:<unique>"` so the
/// `List(selection:)` binding (a `String?`) and any persisted state continue
/// to round-trip. Construct via `ClusterID(kind:raw:)`, parse via
/// `ClusterID(_ string:)`.
enum ClusterKind: String, CaseIterable, Hashable, Sendable {
    case exact
    case photo
    case video
    case burst
    case rotated

    /// User-facing chip label.
    var chipLabel: String {
        switch self {
        case .exact:   return "Exact"
        case .photo:   return "Photos"
        case .video:   return "Videos"
        case .burst:   return "Bursts"
        case .rotated: return "Rotated"
        }
    }

    /// User-facing list section title (with count interpolated by the caller).
    var sectionTitle: String {
        switch self {
        case .exact:   return "Exact duplicates"
        case .photo:   return "Similar photos"
        case .video:   return "Similar videos"
        case .burst:   return "Bursts"
        case .rotated: return "Rotated"
        }
    }

    /// SF Symbol used in the chip row.
    var iconName: String {
        switch self {
        case .exact:   return "equal.circle.fill"
        case .photo:   return "photo.on.rectangle"
        case .video:   return "play.rectangle"
        case .burst:   return "square.stack.3d.up"
        case .rotated: return "rotate.right"
        }
    }

    /// Section accent — drives the chip fill, the cluster-row dot, and the
    /// comparison-pane kind capsule.
    var accent: Color {
        switch self {
        case .exact:   return .green
        case .photo:   return .blue
        case .video:   return .purple
        case .burst:   return .orange
        case .rotated: return .pink
        }
    }

    /// Subset of kinds that the engine produces directly. `.burst` and
    /// `.rotated` are GUI-side detections kicked off by their own buttons,
    /// and may not exist on a typical scan.
    static var engineKinds: [ClusterKind] { [.exact, .photo, .video] }
}

/// Encoded cluster ID: kind prefix + a per-kind unique string (content hash for
/// exact, `stableID` for the others). Converts cleanly between the typed
/// representation and the string form `List(selection:)` already uses.
struct ClusterID: Hashable, Sendable {
    let kind: ClusterKind
    let raw: String

    var encoded: String { "\(kind.rawValue):\(raw)" }

    init(kind: ClusterKind, raw: String) {
        self.kind = kind
        self.raw = raw
    }

    /// Parse the on-the-wire form. Returns nil for malformed input —
    /// callers fall through to the existing "no match" handling.
    init?(_ string: String) {
        guard let colon = string.firstIndex(of: ":") else { return nil }
        let prefix = String(string[..<colon])
        let raw = String(string[string.index(after: colon)...])
        guard let k = ClusterKind(rawValue: prefix) else { return nil }
        self.kind = k
        self.raw = raw
    }
}
