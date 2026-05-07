import Foundation

/// Multi-tier matter status. Lifecycle (in default order):
/// `new → inProgress → complete → postMortem → closed`.
/// The status pick-list is stored in the DB (`status_value`) so the user can
/// rename / reorder / add values; the *role* of each slot in the lifecycle is
/// keyed by `sortOrder` in `MatterStatusService`, so renaming is safe but
/// reordering changes which value is the "first time entry" auto-bump target.
enum MatterStatus: String, Codable, CaseIterable, Hashable {
    case new        = "New"
    case inProgress = "In-Progress"
    case complete   = "Complete"
    case postMortem = "Post-Mortem"
    case closed     = "Closed"

    static var defaultLifecycle: [MatterStatus] {
        [.new, .inProgress, .complete, .postMortem, .closed]
    }
}
