import Foundation
import GRDB

/// A person sourced from the ADP UserFeed CSV. The Associate ID is the
/// stable primary key — names and titles change, the ADP ID does not.
struct Person: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "person"

    var id: String                 // Associate ID (e.g. "SLTWK00000606")
    var firstName: String
    var lastName: String
    var preferredName: String      // empty if none
    var jobTitle: String           // Job Title Description
    var workEmail: String
    var department: String         // Home Department Description
    var location: String           // Location Description
    var positionStatus: String     // "Active", "Terminated", "Leave", …
    var managerAssociateId: String // empty if none
    var updatedAt: Date            // last time the row was upserted from a CSV

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case preferredName = "preferred_name"
        case jobTitle = "job_title"
        case workEmail = "work_email"
        case department
        case location
        case positionStatus = "position_status"
        case managerAssociateId = "manager_associate_id"
        case updatedAt = "updated_at"
    }

    /// Display name = preferred name when present, else first name. Plus
    /// last name. Title-Cased because the ADP feed comes in SHOUTY ALL CAPS.
    var displayName: String {
        let first = !preferredName.isEmpty ? preferredName : firstName
        return "\(Self.titleCase(first)) \(Self.titleCase(lastName))"
            .trimmingCharacters(in: .whitespaces)
    }

    /// "Name (Title)" — empty title collapses to just the name.
    var displayNameWithTitle: String {
        if jobTitle.isEmpty { return displayName }
        return "\(displayName) (\(Self.titleCase(jobTitle)))"
    }

    var isActive: Bool { positionStatus.lowercased() == "active" }

    static func titleCase(_ s: String) -> String {
        s.lowercased()
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
