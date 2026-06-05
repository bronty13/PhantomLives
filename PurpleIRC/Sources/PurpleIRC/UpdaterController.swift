import Foundation
import Sparkle

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app can
/// trigger a manual update check or read the auto-check toggle without importing
/// Sparkle. The controller is `@MainActor` because Sparkle's user-driver UI must
/// run there.
///
/// Configuration lives in Info.plist (`SUFeedURL`, `SUPublicEDKey`,
/// `SUEnableAutomaticChecks`), which build-app.sh stamps in; the user-facing
/// toggle in Setup → Updates flips `automaticallyChecksForUpdates` at runtime.
///
/// Lifted from PurpleDedup's UpdaterController — keep the two in sync when one
/// changes, since they share the same Sparkle integration shape.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    /// Mirror of `updater.automaticallyChecksForUpdates` for SwiftUI binding.
    /// Reads from Sparkle on init; writes through to Sparkle on change.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private init() {
        // `startingUpdater: true` arms the periodic background check
        // immediately; the actual cadence is governed by `SUScheduledCheckInterval`
        // in Info.plist (default: 24h) and `automaticallyChecksForUpdates`.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    /// Show the standard "Checking…" → "Update available / no update / error"
    /// UI. Bound to the **Check for Updates…** menu item and the Updates tab's
    /// Check Now button.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Last time Sparkle successfully completed a check, or nil if never.
    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    /// Convenience for the SwiftUI button enabled-state.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
