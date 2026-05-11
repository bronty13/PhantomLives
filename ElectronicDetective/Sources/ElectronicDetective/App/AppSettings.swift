import Foundation
import SwiftUI

/// User-facing toggles — persisted in `UserDefaults` via `@AppStorage` keys so
/// the Settings scene can bind directly.
enum TranscriptionMode: String, CaseIterable, Identifiable {
    case auto    // notepad auto-records console answers (default)
    case strict  // user must type answers from the LED into the pad

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto:   return "Auto-record"
        case .strict: return "Strict (manual transcription)"
        }
    }
}

enum LEDStyle: String, CaseIterable, Identifiable {
    case warm
    case cool

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .warm: return "Warm (1979)"
        case .cool: return "Cool"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    // Console / UI
    @AppStorage("ED.transcriptionMode") var transcriptionModeRaw: String = TranscriptionMode.auto.rawValue
    @AppStorage("ED.audioEnabled")      var audioEnabled: Bool = true
    @AppStorage("ED.keyClickEnabled")   var keyClickEnabled: Bool = true
    @AppStorage("ED.showHints")         var showHints: Bool = true
    @AppStorage("ED.ledStyleRaw")       var ledStyleRaw: String = LEDStyle.warm.rawValue
    @AppStorage("ED.revealOnLoss")      var revealOnLoss: Bool = true

    // Backup
    @AppStorage("ED.autoBackupEnabled")   var autoBackupEnabled: Bool = true
    @AppStorage("ED.backupRetentionDays") var backupRetentionDays: Int = 14
    @AppStorage("ED.lastBackupAt")        var lastBackupAt: String = ""

    var transcriptionMode: TranscriptionMode {
        get { TranscriptionMode(rawValue: transcriptionModeRaw) ?? .auto }
        set { transcriptionModeRaw = newValue.rawValue }
    }

    var ledStyle: LEDStyle {
        get { LEDStyle(rawValue: ledStyleRaw) ?? .warm }
        set { ledStyleRaw = newValue.rawValue }
    }
}
