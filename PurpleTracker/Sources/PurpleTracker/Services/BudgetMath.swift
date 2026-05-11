import SwiftUI

/// Shared budget math for the Third Party Budget & Actuals matrix:
///   - **Variance** = Budget − Effective Actual (positive = under budget).
///   - **Y/Y %** = (current − prior) / |prior| × 100. Returns "—" when prior
///     is nil (first year) or zero (no meaningful base).
enum BudgetMath {

    /// `nil` → "—"; otherwise returns "+12.3%" / "-4.0%" / "0.0%".
    static func yoyPercent(current: Int64, prior: Int64?) -> Double? {
        guard let prior, prior != 0 else { return nil }
        return Double(current - prior) / Double(abs(prior)) * 100.0
    }

    static func yoyDisplay(current: Int64, prior: Int64?) -> String {
        guard let pct = yoyPercent(current: current, prior: prior) else { return "—" }
        let sign = pct > 0 ? "+" : ""
        return String(format: "\(sign)%.1f%%", pct)
    }

    /// Green for positive/zero %, red for negative %, secondary for "—".
    /// Note: callers may invert (e.g. budget growth might be neutral, not
    /// positive). For now we color budget and actual growth uniformly so the
    /// user can read the trend at a glance.
    static func yoyColor(current: Int64, prior: Int64?) -> Color {
        guard let pct = yoyPercent(current: current, prior: prior) else { return .secondary }
        if pct > 0 { return .green }
        if pct < 0 { return .red }
        return .secondary
    }

    /// Format a variance (Int64 cents, signed). Negative variance gets a
    /// leading "−" sign using `Money.format` on the absolute value.
    static func varianceDisplay(cents: Int64) -> String {
        if cents < 0 { return "−" + Money.format(cents: -cents) }
        return Money.format(cents: cents)
    }
}
