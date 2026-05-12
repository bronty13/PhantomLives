import Foundation

/// Metadata describing a published snapshot, written alongside the SQLite file
/// and thumbnails inside the iCloud ubiquity container. Both the macOS
/// publisher and the iOS reader use this to coordinate version compatibility
/// and detect new publishes.
public struct SnapshotManifest: Codable, Hashable {
    public var schemaVersion: Int
    public var generatedAt: String          // ISO-8601
    public var clipCount: Int
    public var thumbnailCount: Int
    public var publisherDeviceId: String
    public var minIosSchemaVersion: Int

    public init(
        schemaVersion: Int,
        generatedAt: String,
        clipCount: Int,
        thumbnailCount: Int,
        publisherDeviceId: String,
        minIosSchemaVersion: Int
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.clipCount = clipCount
        self.thumbnailCount = thumbnailCount
        self.publisherDeviceId = publisherDeviceId
        self.minIosSchemaVersion = minIosSchemaVersion
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion        = "schema_version"
        case generatedAt          = "generated_at"
        case clipCount            = "clip_count"
        case thumbnailCount       = "thumbnail_count"
        case publisherDeviceId    = "publisher_device_id"
        case minIosSchemaVersion  = "min_ios_schema_version"
    }
}

/// Filesystem layout constants. Centralised here so the iOS reader and the
/// macOS publisher can never drift on filename or directory casing.
public enum SnapshotLayout {
    public static let currentSchemaVersion = 1
    public static let minIosSchemaVersion = 1

    public static let snapshotDir = "snapshot"
    public static let snapshotTmpDir = "snapshot.tmp"
    public static let thumbnailsDir = "thumbnails"
    public static let snapshotDbFile = "snapshot.sqlite"
    public static let manifestFile = "manifest.json"
    public static let intentsDir = "intents"

    public static let iCloudContainerID = "iCloud.com.bronty13.MasterClipper"
}
