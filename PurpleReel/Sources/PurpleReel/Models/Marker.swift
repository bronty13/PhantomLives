import Foundation
import GRDB

struct Marker: Codable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var assetId: Int64
    var timecodeIn: Double
    var timecodeOut: Double?
    var note: String?
    var createdAt: Date

    static let databaseTableName = "marker"

    enum CodingKeys: String, CodingKey {
        case id, assetId, timecodeIn, timecodeOut, note, createdAt
    }
}

struct Subclip: Codable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var parentAssetId: Int64
    var name: String
    var timecodeIn: Double
    var timecodeOut: Double
    var createdAt: Date

    static let databaseTableName = "subclip"

    enum CodingKeys: String, CodingKey {
        case id, parentAssetId, name, timecodeIn, timecodeOut, createdAt
    }
}

struct Tag: Codable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String

    static let databaseTableName = "tag"

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct Rating: Codable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    var assetId: Int64
    var stars: Int
    var colorLabel: String?
    var description: String?

    static let databaseTableName = "rating"

    enum CodingKeys: String, CodingKey {
        case assetId, stars, colorLabel, description
    }
}
