import Foundation
import BackgroundTasks
import MasterClipperCore

/// Registers a `BGAppRefreshTask` so iOS can periodically pull the latest
/// iCloud snapshot even while the app is backgrounded. When the user next
/// opens the app, the on-device cache is already up-to-date.
///
/// iOS picks the actual fire time based on the device's usage patterns; we
/// only set an *earliest* boundary. Expect a fire every ~hour on a regularly
/// used device, much less often on a phone that rarely sees the app.
enum BackgroundRefresh {
    static let taskIdentifier = "com.bronty13.MasterClipper.refreshSnapshot"

    /// Register the handler with the system. Must be called *before*
    /// `application(_:didFinishLaunchingWithOptions:)` returns — in a SwiftUI
    /// app that means inside the `App` value's `init()`.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Submit a new request, replacing any pending one. Called when the app
    /// moves to background.
    static func scheduleNext(after interval: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulators don't support BGTaskScheduler and certain provisioning
            // configurations also reject submits. We swallow — best-effort
            // background sync is fine to skip silently when unavailable.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Re-arm the chain *before* doing work. If we crash or get killed,
        // the next slot is still scheduled.
        scheduleNext()

        let work = Task { @MainActor in
            let reader = SnapshotReader()
            await reader.reload()
            return reader.manifest != nil
        }

        task.expirationHandler = {
            work.cancel()
        }

        Task {
            let success = await work.value
            task.setTaskCompleted(success: success)
        }
    }
}
