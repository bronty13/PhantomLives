import Foundation
import GRDB

/// A single diary entry. Multiple entries per day are allowed — `date` is the
/// moment the entry is *about* (user-editable), `createdAt` / `updatedAt` track
/// the record's lifecycle. Body is Markdown. Mood is a 0–5 star rating where
/// 0 means "unset". Location and weather columns are nullable and populated by
/// the Phase-2 auto-context services; they're created now so no follow-up
/// migration is needed when that UI lands.
struct Entry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID string, stable across exports
    var date: String                // ISO-8601 — the day/time the entry is about
    var title: String
    var bodyMarkdown: String
    var moodRating: Int             // 0 = unset, 1...5 stars
    var wordCount: Int              // denormalized for stats / writing-goal UI
    var journalId: String           // owning journal; defaults to Journal.defaultId

    // Phase-2 auto-context (nullable until the import services populate them).
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var weatherSummary: String?
    var temperatureC: Double?

    var createdAt: String           // ISO-8601
    var updatedAt: String

    static let databaseTableName = "entries"

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case title
        case bodyMarkdown = "body_markdown"
        case moodRating = "mood_rating"
        case wordCount = "word_count"
        case journalId = "journal_id"
        case latitude
        case longitude
        case placeName = "place_name"
        case weatherSummary = "weather_summary"
        case temperatureC = "temperature_c"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var mood: Mood {
        get { Mood(rawValue: moodRating) ?? .unset }
        set { moodRating = newValue.rawValue }
    }

    /// Recompute `wordCount` from the current body. Call before persisting.
    mutating func refreshWordCount() {
        wordCount = Self.countWords(in: bodyMarkdown)
    }

    static func countWords(in text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }
            .filter { !$0.isEmpty }
            .count
    }
}

extension Entry {
    static func newDraft(date: Date = Date(), title: String = "",
                         journalId: String = Journal.defaultId) -> Entry {
        let now = ISO8601DateFormatter().string(from: Date())
        return Entry(
            id: UUID().uuidString,
            date: ISO8601DateFormatter().string(from: date),
            title: title,
            bodyMarkdown: "",
            moodRating: Mood.unset.rawValue,
            wordCount: 0,
            journalId: journalId,
            latitude: nil,
            longitude: nil,
            placeName: nil,
            weatherSummary: nil,
            temperatureC: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Parsed `Date` from the ISO-8601 `date` string, falling back to now.
    var dateValue: Date {
        ISO8601DateFormatter().date(from: date) ?? Date()
    }
}
