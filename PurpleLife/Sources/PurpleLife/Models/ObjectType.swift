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

    /// Creates a built-in type. Built-ins have a stable id so user customizations
    /// keyed by id (e.g. hidden flags) survive across upgrades.
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
            galleryAttachmentKey: galleryAttachmentKey
        )
    }

    /// Returns the field for a given key, if any.
    func field(forKey key: String) -> FieldDef? {
        fields.first { $0.key == key }
    }
}
