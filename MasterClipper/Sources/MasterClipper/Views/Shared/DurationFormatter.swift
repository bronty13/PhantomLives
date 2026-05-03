import Foundation

enum DurationFormatter {
    /// Parse "mm:ss" or "hh:mm:ss" into total seconds. Returns nil on garbage input.
    static func parse(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let nums = parts.compactMap { Int($0) }
        guard nums.count == parts.count else { return nil }
        if nums.count == 2 {
            let (m, s) = (nums[0], nums[1])
            guard s >= 0 && s < 60 && m >= 0 else { return nil }
            return m * 60 + s
        } else {
            let (h, m, s) = (nums[0], nums[1], nums[2])
            guard h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60 else { return nil }
            return h * 3600 + m * 60 + s
        }
    }

    /// Format total seconds as "h:mm:ss" if ≥ 1 h, else "m:ss".
    static func format(_ totalSeconds: Int?) -> String {
        guard let total = totalSeconds, total >= 0 else { return "—" }
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
