import SwiftUI
import PurpleDedupCore

/// Type-erased cluster passed from the cluster list to the comparison pane. The
/// five concrete cluster kinds (exact / similar_photo / similar_video / burst /
/// rotated) have different underlying data shapes; this struct flattens them to
/// the subset the comparison view actually needs.
struct ClusterSelection: Identifiable, Hashable {
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let files: [DiscoveredFile]

    enum Kind: Hashable {
        case exact
        case similarPhoto
        case similarVideo
    }

    var kindLabel: String {
        switch kind {
        case .exact:        return "EXACT"
        case .similarPhoto: return "SIMILAR PHOTOS"
        case .similarVideo: return "SIMILAR VIDEOS"
        }
    }

    var kindColor: Color {
        switch kind {
        case .exact:        return .green
        case .similarPhoto: return .blue
        case .similarVideo: return .purple
        }
    }
}
