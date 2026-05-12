import Foundation

/// Built-in type seeds installed on first launch. Mirrors the example
/// types referenced in `Design/MANIFEST.md` (Person, Camera, Book, Photo
/// Shoot, WoW Character, Photo) so the four list views in Phase 2 have
/// realistic content to render right away.
///
/// Built-in types can be hidden by the user but not deleted — keeping
/// the user's hidden-type set keyed by id means a future seed update
/// won't fight a user who turned a default off.
enum SchemaSeed {

    static let allTypes: [ObjectType] = [
        plannerItem, note, person, book, camera, photoShoot, wowCharacter, photo, weight
    ]

    // MARK: Note

    /// WYSIWYG notes — the home for free-form rich-text journaling.
    /// Backs the dedicated three-pane Notes workspace (left: date-grouped
    /// list, right: title + date + RichTextField editor). Routes through
    /// `NotesWorkspaceView` from `ContentView` instead of the standard
    /// `RecordsScreen` so the UX matches PurpleTracker's Notes feature.
    static let note: ObjectType = {
        let noteDate = FieldDef.make(name: "Date", kind: .date, required: true)
        let title    = FieldDef.make(name: "Title", kind: .text, required: true)
        let category = FieldDef.make(
            name: "Category",
            kind: .select,
            options: [
                .make("Personal",  colorHex: "#9D4DCC"),
                .make("Work",      colorHex: "#3FA9F5"),
                .make("Ideas",     colorHex: "#E8A93B"),
                .make("Journal",   colorHex: "#3FB950"),
                .make("Reference", colorHex: "#888888"),
            ]
        )
        let body = FieldDef.make(name: "Body", kind: .richText)
        return .builtIn(
            id: "Note",
            name: "Note",
            pluralName: "Notes",
            systemImage: "note.text",
            colorHex: "#9D4DCC",
            fields: [noteDate, title, category, body],
            primaryFieldKey: title.key,
            kanbanGroupKey: category.key,
            calendarDateKey: noteDate.key
        )
    }()

    // MARK: Planner Item

    static let plannerItem: ObjectType = {
        let title = FieldDef.make(name: "Title", kind: .text, required: true)
        let date  = FieldDef.make(name: "Date",  kind: .date)
        let status = FieldDef.make(
            name: "Status",
            kind: .select,
            options: [
                .make("Pending",   colorHex: "#3FA9F5"),
                .make("Doing",     colorHex: "#9D4DCC"),
                .make("Done",      colorHex: "#3FB950"),
                .make("Cancelled", colorHex: "#888888"),
            ]
        )
        let project = FieldDef.make(name: "Project", kind: .text)
        let notes   = FieldDef.make(name: "Notes",   kind: .longText)
        return .builtIn(
            id: "PlannerItem",
            name: "Planner Item",
            pluralName: "Planner",
            systemImage: "checkmark.circle",
            colorHex: "#3FA9F5",
            fields: [title, date, status, project, notes],
            primaryFieldKey: title.key,
            kanbanGroupKey: status.key,
            calendarDateKey: date.key
        )
    }()

    // MARK: Weight

    static let weight: ObjectType = {
        let date    = FieldDef.make(name: "Date",   kind: .date, required: true)
        let pounds  = FieldDef.make(name: "Pounds", kind: .number)
        let bodyFat = FieldDef.make(name: "Body fat %", kind: .number)
        let source = FieldDef.make(
            name: "Source",
            kind: .select,
            options: [
                .make("Manual",     colorHex: "#888888"),
                .make("Smart scale", colorHex: "#3FA9F5"),
                .make("Imported",    colorHex: "#9D4DCC"),
            ]
        )
        let notes = FieldDef.make(name: "Notes", kind: .longText)
        return .builtIn(
            id: "Weight",
            name: "Weight",
            pluralName: "Weight",
            systemImage: "scalemass",
            colorHex: "#E8A93B",
            fields: [date, pounds, bodyFat, source, notes],
            primaryFieldKey: pounds.key,
            calendarDateKey: date.key
        )
    }()

    // MARK: Person

    static let person: ObjectType = {
        let displayName  = FieldDef.make(name: "Display name",  kind: .text,    required: true)
        let firstName    = FieldDef.make(name: "First name",    kind: .text)
        let lastName     = FieldDef.make(name: "Last name",     kind: .text)
        let email        = FieldDef.make(name: "Email",         kind: .email)
        let phone        = FieldDef.make(name: "Phone",         kind: .text)
        let relationship = FieldDef.make(
            name: "Relationship",
            kind: .select,
            options: [
                .make("Family",     colorHex: "#9D4DCC"),
                .make("Friend",     colorHex: "#3FA9F5"),
                .make("Colleague",  colorHex: "#3FB950"),
                .make("Acquaintance", colorHex: "#888888"),
            ]
        )
        let notes = FieldDef.make(name: "Notes", kind: .longText)
        return .builtIn(
            id: "Person",
            name: "Person",
            pluralName: "People",
            systemImage: "person.crop.circle",
            colorHex: "#3FA9F5",
            fields: [displayName, firstName, lastName, email, phone, relationship, notes],
            primaryFieldKey: displayName.key,
            kanbanGroupKey: relationship.key
        )
    }()

    // MARK: Book

    static let book: ObjectType = {
        let title    = FieldDef.make(name: "Title",  kind: .text, required: true)
        let author   = FieldDef.make(name: "Author", kind: .text)
        let status = FieldDef.make(
            name: "Status",
            kind: .select,
            options: [
                .make("Want to read", colorHex: "#888888"),
                .make("Reading",      colorHex: "#3FA9F5"),
                .make("Finished",     colorHex: "#3FB950"),
                .make("Abandoned",    colorHex: "#D14B5C"),
            ]
        )
        let started  = FieldDef.make(name: "Started",  kind: .date)
        let finished = FieldDef.make(name: "Finished", kind: .date)
        let rating   = FieldDef.make(name: "Rating",   kind: .rating)
        let cover    = FieldDef.make(name: "Cover",    kind: .attachment)
        let notes    = FieldDef.make(name: "Notes",    kind: .longText)
        return .builtIn(
            id: "Book",
            name: "Book",
            pluralName: "Books",
            systemImage: "book.closed",
            colorHex: "#E8A93B",
            fields: [title, author, status, started, finished, rating, cover, notes],
            primaryFieldKey: title.key,
            kanbanGroupKey: status.key,
            calendarDateKey: started.key,
            galleryAttachmentKey: cover.key
        )
    }()

    // MARK: Camera

    static let camera: ObjectType = {
        let model   = FieldDef.make(name: "Model",   kind: .text, required: true)
        let brand = FieldDef.make(
            name: "Brand",
            kind: .select,
            options: [
                .make("Sony",     colorHex: "#3FA9F5"),
                .make("Canon",    colorHex: "#D14B5C"),
                .make("Nikon",    colorHex: "#E8A93B"),
                .make("Fujifilm", colorHex: "#3FB950"),
                .make("Leica",    colorHex: "#9D4DCC"),
                .make("Other",    colorHex: "#888888"),
            ]
        )
        let kind = FieldDef.make(
            name: "Kind",
            kind: .select,
            options: [
                .make("Mirrorless", colorHex: "#3FA9F5"),
                .make("DSLR",       colorHex: "#9D4DCC"),
                .make("Compact",    colorHex: "#3FB950"),
                .make("Film",       colorHex: "#E8A93B"),
            ]
        )
        let purchased = FieldDef.make(name: "Purchased", kind: .date)
        let serial    = FieldDef.make(name: "Serial",    kind: .text)
        let photo     = FieldDef.make(name: "Photo",     kind: .attachment)
        let notes     = FieldDef.make(name: "Notes",     kind: .longText)
        return .builtIn(
            id: "Camera",
            name: "Camera",
            pluralName: "Cameras",
            systemImage: "camera",
            colorHex: "#3FB950",
            fields: [model, brand, kind, purchased, serial, photo, notes],
            primaryFieldKey: model.key,
            kanbanGroupKey: brand.key,
            calendarDateKey: purchased.key,
            galleryAttachmentKey: photo.key
        )
    }()

    // MARK: Photo Shoot

    static let photoShoot: ObjectType = {
        let title    = FieldDef.make(name: "Title",    kind: .text, required: true)
        let date     = FieldDef.make(name: "Date",     kind: .dateTime, required: true)
        let location = FieldDef.make(name: "Location", kind: .text)
        let cameraRef = FieldDef.make(name: "Camera",  kind: .link)
        let status = FieldDef.make(
            name: "Status",
            kind: .select,
            options: [
                .make("Planned",   colorHex: "#888888"),
                .make("Shot",      colorHex: "#3FA9F5"),
                .make("Edited",    colorHex: "#9D4DCC"),
                .make("Published", colorHex: "#3FB950"),
            ]
        )
        let coverPhoto = FieldDef.make(name: "Cover photo", kind: .attachment)
        let notes      = FieldDef.make(name: "Notes",       kind: .longText)
        return .builtIn(
            id: "PhotoShoot",
            name: "Photo Shoot",
            pluralName: "Photo Shoots",
            systemImage: "camera.aperture",
            colorHex: "#F08C2E",
            fields: [title, date, location, cameraRef, status, coverPhoto, notes],
            primaryFieldKey: title.key,
            kanbanGroupKey: status.key,
            calendarDateKey: date.key,
            galleryAttachmentKey: coverPhoto.key
        )
    }()

    // MARK: WoW Character

    static let wowCharacter: ObjectType = {
        let name = FieldDef.make(name: "Name", kind: .text, required: true)
        let className = FieldDef.make(
            name: "Class",
            kind: .select,
            options: [
                .make("Death Knight",  colorHex: "#C41F3B"),
                .make("Demon Hunter",  colorHex: "#A330C9"),
                .make("Druid",         colorHex: "#FF7C0A"),
                .make("Evoker",        colorHex: "#33937F"),
                .make("Hunter",        colorHex: "#AAD372"),
                .make("Mage",          colorHex: "#3FC7EB"),
                .make("Monk",          colorHex: "#00FF98"),
                .make("Paladin",       colorHex: "#F48CBA"),
                .make("Priest",        colorHex: "#FFFFFF"),
                .make("Rogue",         colorHex: "#FFF468"),
                .make("Shaman",        colorHex: "#0070DD"),
                .make("Warlock",       colorHex: "#8788EE"),
                .make("Warrior",       colorHex: "#C69B6D"),
            ]
        )
        let level   = FieldDef.make(name: "Level",  kind: .number)
        let realm   = FieldDef.make(name: "Realm",  kind: .text)
        let faction = FieldDef.make(
            name: "Faction",
            kind: .select,
            options: [
                .make("Alliance", colorHex: "#0070DD"),
                .make("Horde",    colorHex: "#C41F3B"),
            ]
        )
        let status = FieldDef.make(
            name: "Status",
            kind: .select,
            options: [
                .make("Main",     colorHex: "#3FB950"),
                .make("Alt",      colorHex: "#3FA9F5"),
                .make("Banked",   colorHex: "#888888"),
                .make("Deleted",  colorHex: "#D14B5C"),
            ]
        )
        let notes = FieldDef.make(name: "Notes", kind: .longText)
        return .builtIn(
            id: "WoWCharacter",
            name: "WoW Character",
            pluralName: "WoW Characters",
            systemImage: "shield.lefthalf.filled",
            colorHex: "#9D4DCC",
            fields: [name, className, level, realm, faction, status, notes],
            primaryFieldKey: name.key,
            kanbanGroupKey: status.key
        )
    }()

    // MARK: Photo

    static let photo: ObjectType = {
        let title  = FieldDef.make(name: "Title",  kind: .text)
        let taken  = FieldDef.make(name: "Taken",  kind: .dateTime)
        let cameraRef = FieldDef.make(name: "Camera", kind: .link)
        let shootRef  = FieldDef.make(name: "Shoot",  kind: .link)
        let rating = FieldDef.make(name: "Rating", kind: .rating)
        let kind = FieldDef.make(
            name: "Kind",
            kind: .select,
            options: [
                .make("Keeper",    colorHex: "#3FB950"),
                .make("Maybe",     colorHex: "#E8A93B"),
                .make("Reject",    colorHex: "#D14B5C"),
                .make("Unsorted",  colorHex: "#888888"),
            ]
        )
        let image = FieldDef.make(name: "Image", kind: .attachment)
        let notes = FieldDef.make(name: "Notes", kind: .longText)
        return .builtIn(
            id: "Photo",
            name: "Photo",
            pluralName: "Photos",
            systemImage: "photo",
            colorHex: "#3FA9F5",
            fields: [title, taken, cameraRef, shootRef, rating, kind, image, notes],
            primaryFieldKey: title.key,
            kanbanGroupKey: kind.key,
            calendarDateKey: taken.key,
            galleryAttachmentKey: image.key
        )
    }()
}
