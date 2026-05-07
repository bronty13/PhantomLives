import Foundation
import GRDB

struct Event: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID string
    var caseId: String              // FK → cases.id
    var title: String
    var dateStart: String           // ISO-8601 datetime; primary sort key
    var dateEnd: String?            // optional; for date ranges
    var descriptionMarkdown: String
    var sourceURL: String           // canonical citation URL or note
    var importance: String          // Importance.rawValue
    var createdAt: String

    static let databaseTableName = "events"

    enum CodingKeys: String, CodingKey {
        case id
        case caseId = "case_id"
        case title
        case dateStart = "date_start"
        case dateEnd = "date_end"
        case descriptionMarkdown = "description_markdown"
        case sourceURL = "source_url"
        case importance
        case createdAt = "created_at"
    }

    var importanceEnum: Importance {
        get { Importance(rawValue: importance) ?? .medium }
        set { importance = newValue.rawValue }
    }

    /// Parsed start date if the stored ISO string can be decoded.
    var parsedStart: Date? {
        EventDateParser.parse(dateStart)
    }

    var parsedEnd: Date? {
        guard let s = dateEnd else { return nil }
        return EventDateParser.parse(s)
    }
}

extension Event {
    static func newDraft(caseId: String, date: Date = Date()) -> Event {
        let now = ISO8601DateFormatter().string(from: Date())
        return Event(
            id: UUID().uuidString,
            caseId: caseId,
            title: "",
            dateStart: ISO8601DateFormatter().string(from: date),
            dateEnd: nil,
            descriptionMarkdown: "",
            sourceURL: "",
            importance: Importance.medium.rawValue,
            createdAt: now
        )
    }
}

/// Lenient ISO-8601 parser: accepts either an `internetDateTime`
/// (`2026-05-06T12:34:56Z`) or a date-only `yyyy-MM-dd` string.
enum EventDateParser {
    static func parse(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        if let d = isoNoTimeZone.date(from: s) { return d }
        return dateOnlyFormatter.date(from: s)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoNoTimeZone: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
