import Foundation

/// A user-defined (or built-in) object type. Defines the shape of records
/// of this type — which fields they carry, how they're displayed in the
/// four list views, and how the type itself is presented in the sidebar.
struct ObjectType: Codable, Identifiable, Hashable {
    var id: String              // stable identifier; matches `ObjectRecord.typeId`
    var name: String            // display name, e.g. "Person"
    var pluralName: String      // sidebar label, e.g. "People"
    var systemImage: String     // SF Symbol name
    var colorHex: String        // accent color (hex with #)
    var fields: [FieldDef]
    var builtIn: Bool           // true for the seeded types; user can hide but not delete

    // View defaults — point at field keys.
    var primaryFieldKey: String?     // the field that acts as the record's "title"
    var kanbanGroupKey: String?      // a select-field key
    var calendarDateKey: String?     // a date / dateTime field key
    var galleryAttachmentKey: String?// an attachment field key (used by gallery for thumbnails)

    /// ISO-8601 timestamp of the last mutation. CloudKit schema sync
    /// reconciles peers by LWW on this — the more recent of two
    /// versions wins. Optional so old `schema.json` files (pre
    /// schema-sync) decode cleanly; `SchemaRegistry.load()` backfills
    /// a stable epoch value for any type missing it, which sorts
    /// "older than anything" so the first remote update overwrites.
    var updatedAt: String?

    /// Creates a built-in type. Built-ins have a stable id so user customizations
    /// keyed by id (e.g. hidden flags) survive across upgrades. The
    /// timestamp is the stable epoch — every real mutation overrides
    /// it via `updatedAt` stamping in `SchemaRegistry`.
    static func builtIn(
        id: String,
        name: String,
        pluralName: String,
        systemImage: String,
        colorHex: String,
        fields: [FieldDef],
        primaryFieldKey: String? = nil,
        kanbanGroupKey: String? = nil,
        calendarDateKey: String? = nil,
        galleryAttachmentKey: String? = nil
    ) -> ObjectType {
        ObjectType(
            id: id,
            name: name,
            pluralName: pluralName,
            systemImage: systemImage,
            colorHex: colorHex,
            fields: fields,
            builtIn: true,
            primaryFieldKey: primaryFieldKey,
            kanbanGroupKey: kanbanGroupKey,
            calendarDateKey: calendarDateKey,
            galleryAttachmentKey: galleryAttachmentKey,
            updatedAt: epochTimestamp
        )
    }

    /// Stable "older than anything" timestamp used as the default for
    /// types that haven't been touched since schema sync was added.
    /// Picked as 1970-01-01 so any real edit naturally beats it under
    /// LWW comparison.
    static let epochTimestamp = "1970-01-01T00:00:00Z"

    /// Returns the field for a given key, if any.
    func field(forKey key: String) -> FieldDef? {
        fields.first { $0.key == key }
    }
}
