import Foundation
import SwiftUI

/// Wraps `AppSettings` persistence in UserDefaults (JSON-encoded under a single key). Any
/// mutation of `settings` auto-saves. Also computes the on-demand default output paths that
/// follow the PhantomLives "~/Downloads/<AppName>/" convention.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let key = "PurplePeekSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Computed paths

    private static var downloadsBase: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Backup destination — user override or `~/Downloads/PurplePeek backup/`.
    var resolvedBackupPath: URL {
        let path = settings.backupPath.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { return URL(fileURLWithPath: path) }
        return Self.downloadsBase.appendingPathComponent("PurplePeek backup", isDirectory: true)
    }

    /// Kept-audio export destination — user override or `~/Downloads/PurplePeek/Kept Audio/`.
    var resolvedKeptAudioPath: URL {
        let path = settings.keptAudioExportPath.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { return URL(fileURLWithPath: path) }
        return Self.downloadsBase
            .appendingPathComponent("PurplePeek", isDirectory: true)
            .appendingPathComponent("Kept Audio", isDirectory: true)
    }
}
