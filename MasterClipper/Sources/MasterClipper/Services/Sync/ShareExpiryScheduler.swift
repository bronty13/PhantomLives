import Foundation
import MasterClipperCore

/// Auto-revoke expired CloudKit shares. CKShare has no native expiration —
/// we enforce it ourselves by:
///   1. Sweeping on app launch + on every share-list refresh.
///   2. Arming a one-shot Timer at the next-expiring share's `expiresAt`,
///      re-arming whenever the active-shares list changes.
///   3. iOS-side: SharedZoneReader (Phase 6d) refuses to display SharedClip
///      records past their `expiresAt` regardless of whether Mac got around
///      to revoking, so a sleeping Mac doesn't leak access.
@MainActor
final class ShareExpiryScheduler {
    static let shared = ShareExpiryScheduler()

    private var timer: Timer?
    private var observation: Task<Void, Never>?

    private init() {}

    /// Start watching. Idempotent.
    func start() {
        // Initial sweep.
        Task { await ShareManager.shared.revokeExpiredShares() }
        // Watch for changes to the active-shares list.
        observation?.cancel()
        observation = Task { [weak self] in
            for await _ in ShareManager.shared.$activeShares.values {
                self?.armNextTimer()
            }
        }
        armNextTimer()
    }

    private func armNextTimer() {
        timer?.invalidate()
        timer = nil

        let upcoming = ShareManager.shared.activeShares
            .filter { !$0.revoked && !$0.isExpired }
            .min(by: { $0.expiresAt < $1.expiresAt })

        guard let next = upcoming else { return }
        let delay = max(1, next.expiresAt.timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                _ = await ShareManager.shared.revokeExpiredShares()
                // Re-arm in case there's a next-next.
                ShareExpiryScheduler.shared.armNextTimer()
            }
        }
    }
}
