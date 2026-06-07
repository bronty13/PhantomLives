import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater so SwiftUI menus can drive
/// "Check for Updates…" and the auto-check toggle. Mirrors the PurpleMark/
/// PurpleIRC pattern. The feed URL + public EdDSA key live in Info.plist
/// (`SUFeedURL` / `SUPublicEDKey`) — the latter is the shared Purple* key.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
}
