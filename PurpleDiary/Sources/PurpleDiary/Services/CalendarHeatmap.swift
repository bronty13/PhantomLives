import Foundation

/// Maps a day's total word count to a discrete intensity level (0…4) for the
/// calendar heatmap. Pure and local — drives the cell's background opacity.
enum CalendarHeatmap {

    /// 0 = no writing, 1 = a little, … 4 = a big day. Thresholds are tuned for
    /// personal journaling (a sentence vs. a full page).
    static func level(words: Int) -> Int {
        switch words {
        case ..<1:    return 0
        case 1...49:  return 1
        case 50...149: return 2
        case 150...399: return 3
        default:      return 4
        }
    }

    /// Background opacity for a level — feeds `accent.opacity(...)`.
    static func opacity(level: Int) -> Double {
        switch level {
        case 0:  return 0.06   // faint "has a cell" wash
        case 1:  return 0.20
        case 2:  return 0.38
        case 3:  return 0.58
        default: return 0.80
        }
    }
}
