import Foundation
import GRDB

public struct CalendarRule: Codable, FetchableRecord, PersistableRecord, Hashable {
    public var personaCode: String
    public var weekday: Int
    public var enabled: Bool

    public static let databaseTableName = "calendar_rules"

    enum CodingKeys: String, CodingKey {
        case personaCode = "persona_code"
        case weekday
        case enabled
    }

    public init(personaCode: String, weekday: Int, enabled: Bool) {
        self.personaCode = personaCode
        self.weekday = weekday
        self.enabled = enabled
    }

    public static let weekdayLabels: [String] = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func label(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "?" }
        return weekdayLabels[weekday]
    }
}
