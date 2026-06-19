import Foundation
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`, exposing
/// "Check for Updates…" to the menu. Lifted from the PurpleIRC pattern.
///
/// Defensive start: a dev build made without `SPARKLE_PUBLIC_KEY` embeds a
/// placeholder `SUPublicEDKey`, and starting the updater with an undecodable key
/// is a fatal Sparkle error. So we only start the updater when a real key is
/// present; otherwise updates are simply disabled (the menu item greys out) and
/// the app launches normally.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController?
    let isEnabled: Bool

    private init() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? ""
        let hasRealKey = !key.isEmpty && !key.hasPrefix("PLACEHOLDER")
        if hasRealKey {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        isEnabled = hasRealKey
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }
}
