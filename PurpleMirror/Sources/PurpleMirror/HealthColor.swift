import SwiftUI

/// One place for the health → SwiftUI color mapping used by the menu, the settings sidebar,
/// and anywhere else a job's status glyph is tinted. (Kept out of `SyncStatusParser` so that
/// the parser stays UI-free and unit-testable.)
extension SyncStatusParser.Health {
    var color: Color {
        switch self {
        case .healthy: return .green
        case .running: return .accentColor
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
