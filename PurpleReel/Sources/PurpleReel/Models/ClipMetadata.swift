import Foundation
import GRDB

/// Kyno-parity log fields. One row per asset (assetId is PK), so
/// reads/writes are upserts via `setClipMetadata(_:assetId:)`.
/// Every field is optional so callers can store a partial sheet —
/// "just a title", "scene + take only", etc.
struct ClipMetadata: Codable, Equatable, FetchableRecord, PersistableRecord {
    var assetId: Int64
    var title: String?
    var description: String?
    var reel: String?
    var scene: String?
    var shot: String?
    var take: String?
    var angle: String?
    var camera: String?
    /// User-provided per-channel labels for the asset's audio
    /// tracks ("boom", "lav-Alice", "lav-Bob"). Comma-separated in
    /// SQLite; indexed by track order. Kyno doesn't preserve these
    /// — a doc/interview-shop win. Nil when the user hasn't named
    /// channels yet. Default = nil keeps the old memberwise
    /// initializer's call-site compatible at every existing site.
    var audioChannelNames: String? = nil

    static let databaseTableName = "clip_metadata"

    enum CodingKeys: String, CodingKey {
        case assetId, title, description, reel, scene, shot, take, angle, camera
        case audioChannelNames
    }

    static let empty = ClipMetadata(
        assetId: 0,
        title: nil, description: nil,
        reel: nil, scene: nil, shot: nil, take: nil, angle: nil, camera: nil,
        audioChannelNames: nil
    )
}
