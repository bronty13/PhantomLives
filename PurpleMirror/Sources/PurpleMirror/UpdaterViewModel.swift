import Foundation
import Combine
import Sparkle

/// Thin SwiftUI-friendly wrapper around Sparkle's standard updater. Owns the
/// `SPUStandardUpdaterController` (which starts the updater + schedules the
/// automatic background checks configured in Info.plist) and exposes whether a
/// manual check is currently possible.
@MainActor
final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Marketing version of the running app, for display.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
