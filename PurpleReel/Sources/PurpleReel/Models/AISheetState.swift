import Foundation

/// Identifiable sheet selector for AI-augmented actions. SwiftUI's
/// `.sheet(item:)` modifier wants an `Identifiable` enum so the
/// presented sheet swaps when the case changes.
enum AISheetState: Identifiable, Equatable {
    case transcribing(filename: String)
    case transcriptReady(doc: TranscriptDocument, assetName: String)
    case describing(filename: String)
    case describeReady(text: String, assetName: String)
    case findingSimilar(progress: Int, total: Int)
    case similarReady(count: Int)
    case error(message: String)

    var id: String {
        switch self {
        case .transcribing: return "transcribing"
        case .transcriptReady: return "transcriptReady"
        case .describing: return "describing"
        case .describeReady: return "describeReady"
        case .findingSimilar: return "findingSimilar"
        case .similarReady: return "similarReady"
        case .error: return "error"
        }
    }
}
