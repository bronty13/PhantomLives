import Foundation
import GRDB

/// A user-named filter pinned to the sidebar. Criteria are JSON-encoded so
/// the schema can grow without DB migrations.
struct SavedSearch: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "saved_search"

    var id: String
    var name: String
    var queryJson: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case queryJson = "query_json"
        case sortOrder = "sort_order"
    }

    var criteria: SearchCriteria {
        get {
            (try? JSONDecoder().decode(SearchCriteria.self, from: Data(queryJson.utf8)))
                ?? SearchCriteria()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                queryJson = s
            }
        }
    }
}

/// Criteria for a saved search. All fields are optional; the filter ANDs
/// every populated condition together.
struct SearchCriteria: Codable, Hashable {
    var text: String? = nil
    var typeIds: [String] = []
    var statuses: [String] = []
    var priorities: [String] = []
    var initiativeIds: [String] = []
    var goalIds: [String] = []
    var requestorAssociateIds: [String] = []
    /// "due_within_days" — Matters whose due date is within N days from now
    /// (open Matters only).
    var dueWithinDays: Int? = nil
    var openOnly: Bool = true
}
