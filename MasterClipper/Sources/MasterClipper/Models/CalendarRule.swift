import Foundation
import GRDB

struct CalendarRule: Codable, FetchableRecord, PersistableRecord, Hashable {
    var personaCode: String
    var weekday: Int                            // 1=Sun … 7=Sat (Calendar.weekday)
    var enabled: Bool

    static let databaseTableName = "calendar_rules"

    enum CodingKeys: String, CodingKey {
        case personaCode = "persona_code"
        case weekday
        case enabled
    }

    static let weekdayLabels: [String] = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func label(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "?" }
        return weekdayLabels[weekday]
    }
}
