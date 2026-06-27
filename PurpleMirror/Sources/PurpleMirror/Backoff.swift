import Foundation

/// Retry cadence for an unreachable remote host. A healthy host is refreshed every tick; one that's
/// failing is probed progressively less often so an asleep/offline runner doesn't burn an ssh
/// `ConnectTimeout` on every 10s tick. Pure + unit-tested.
enum Backoff {
    /// How many ticks to wait between probes given `consecutiveFailures`.
    /// 0 → every tick; then 2, 3, capped at 6 ticks (~60s at the 10s refresh tick).
    static func probeInterval(consecutiveFailures n: Int) -> Int {
        switch n {
        case ..<1: return 1
        case 1:    return 2
        case 2:    return 3
        default:   return 6
        }
    }

    /// Whether to probe a failing host on this `tick` (monotonic counter). Healthy hosts
    /// (`consecutiveFailures == 0`) always probe.
    static func shouldProbe(consecutiveFailures n: Int, tick: Int) -> Bool {
        let interval = probeInterval(consecutiveFailures: n)
        return interval <= 1 || tick % interval == 0
    }
}
