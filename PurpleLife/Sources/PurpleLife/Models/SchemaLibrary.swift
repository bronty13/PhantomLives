import Foundation

/// Curated showcase library of schemas the user can import from the
/// Schema Editor → "Browse library" sheet. The point of this catalog is
/// to make the app's flexibility tangible: PurpleLife is a generic
/// object engine, and a dense catalog of plausible-looking schemas across
/// hobbies, life admin, creative work, and unusual collections is the
/// fastest way to communicate that.
///
/// Each entry is a self-contained `ObjectType` template plus
/// presentation metadata (category, blurb, search keywords). Importing
/// goes through `SchemaLibrary.materialize(_:)` which assigns fresh UUIDs
/// to the type id and every field id — so re-importing the same entry
/// produces a clean copy rather than colliding with the previous one.
///
/// Entries are static; the catalog grows by appending to `entries`. None
/// of these are built-ins — they all import as user-defined types the
/// user can rename, delete, or edit freely.
enum SchemaLibrary {

    // MARK: - Categories

    /// Top-level grouping for the gallery sidebar. Names are display strings.
    enum Category: String, CaseIterable, Codable {
        case productivity = "Productivity & Planning"
        case home = "Home & Life Admin"
        case finance = "Money & Finance"
        case health = "Health & Wellness"
        case food = "Food & Drink"
        case hobbies = "Hobbies & Collecting"
        case media = "Media & Entertainment"
        case travel = "Travel & Places"
        case creative = "Creative Work"
        case professional = "Work & Career"
        case learning = "Learning & Reference"
        case relationships = "Relationships"
        case unusual = "Unusual & Niche"

        var systemImage: String {
            switch self {
            case .productivity:  return "checklist"
            case .home:          return "house"
            case .finance:       return "dollarsign.circle"
            case .health:        return "heart"
            case .food:          return "fork.knife"
            case .hobbies:       return "paintpalette"
            case .media:         return "play.tv"
            case .travel:        return "airplane"
            case .creative:      return "wand.and.stars"
            case .professional:  return "briefcase"
            case .learning:      return "graduationcap"
            case .relationships: return "person.2"
            case .unusual:       return "sparkles"
            }
        }
    }

    // MARK: - Entry

    /// A single library entry. `template` carries the canonical
    /// `ObjectType` shape; `materialize()` clones it with fresh ids so
    /// the user can import the same entry twice without collisions.
    struct Entry: Identifiable, Hashable {
        let id: String              // stable library-entry id; survives across launches
        let category: Category
        let blurb: String           // 1–2 sentence pitch shown on the entry card
        let keywords: [String]      // free-text search tokens (lower-cased on match)
        let template: ObjectType

        /// Returns a fresh copy of the template, ready to insert into a
        /// `SchemaRegistry`. New `ObjectType.id` is a UUID (so future
        /// re-imports don't collide), every `FieldDef.id` is regenerated,
        /// and the view-key references (primary / kanban / calendar /
        /// gallery) are rewritten to point at the new field ids' keys,
        /// which stay stable because they're derived from field names.
        func materialize() -> ObjectType {
            var fresh = template
            fresh.id = UUID().uuidString
            fresh.builtIn = false
            fresh.updatedAt = nil
            fresh.fields = fresh.fields.map { field in
                var f = field
                f.id = UUID().uuidString
                return f
            }
            return fresh
        }
    }

    // MARK: - Lookup

    /// Look up an entry by its library-entry id.
    static func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Filter entries by category + free-text query. Empty query returns
    /// everything in the category (or everywhere if `category == nil`).
    static func search(query: String, category: Category? = nil) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries
            .filter { category == nil || $0.category == category! }
            .filter { entry in
                guard !q.isEmpty else { return true }
                if entry.template.name.lowercased().contains(q) { return true }
                if entry.template.pluralName.lowercased().contains(q) { return true }
                if entry.blurb.lowercased().contains(q) { return true }
                if entry.keywords.contains(where: { $0.lowercased().contains(q) }) { return true }
                if entry.category.rawValue.lowercased().contains(q) { return true }
                if entry.template.fields.contains(where: { $0.name.lowercased().contains(q) }) { return true }
                return false
            }
    }
}

// MARK: - Catalog

extension SchemaLibrary {

    /// Helper used inside the entries below to make a select-field
    /// definition with named options. Keeps the entry literals readable.
    /// Internal (not fileprivate) so it's reachable from the extended
    /// catalog in `SchemaLibrary+ExtendedCatalog.swift`.
    static func selectField(
        _ name: String,
        _ options: [(String, String)]
    ) -> FieldDef {
        FieldDef.make(
            name: name,
            kind: .select,
            options: options.map { FieldOption.make($0.0, colorHex: $0.1) }
        )
    }

    /// The full catalog the gallery shows. Computed so additional
    /// entries declared in extension files (e.g.
    /// `SchemaLibrary+ExtendedCatalog.swift`) are picked up
    /// automatically without touching this file.
    static var entries: [Entry] {
        coreEntries + extendedEntries
    }

    /// Original first-batch entries kept inline. New entries belong in
    /// the extension file (`SchemaLibrary+ExtendedCatalog.swift`) to
    /// keep this file from growing unboundedly.
    static let coreEntries: [Entry] = [

        // MARK: Productivity & Planning

        Entry(
            id: "lib.project",
            category: .productivity,
            blurb: "Track multi-step projects with status, owner, budget, and milestones.",
            keywords: ["project", "kanban", "deliverable", "milestone", "work"],
            template: makeType(
                id: "Project", name: "Project", plural: "Projects",
                image: "folder.badge.gearshape", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Planning", "#3FA9F5"),
                        ("In progress", "#9D4DCC"), ("Blocked", "#D14B5C"),
                        ("Shipped", "#3FB950"), ("Archived", "#666666"),
                    ]),
                    selectField("Priority", [
                        ("Low", "#888888"), ("Medium", "#3FA9F5"),
                        ("High", "#E8A93B"), ("Critical", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Owner", kind: .link, description: "Link to a Person"),
                    FieldDef.make(name: "Start date", kind: .date),
                    FieldDef.make(name: "Target date", kind: .date),
                    FieldDef.make(name: "Budget", kind: .number),
                    FieldDef.make(name: "Description", kind: .richText),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "name", kanban: "status", calendar: "target_date"
            )
        ),

        Entry(
            id: "lib.goal",
            category: .productivity,
            blurb: "SMART goals with target date, progress, and weekly check-ins.",
            keywords: ["goal", "okr", "objective", "smart", "target"],
            template: makeType(
                id: "Goal", name: "Goal", plural: "Goals",
                image: "target", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Goal", kind: .text, required: true),
                    selectField("Area", [
                        ("Career", "#3FA9F5"), ("Health", "#3FB950"),
                        ("Finance", "#E8A93B"), ("Learning", "#9D4DCC"),
                        ("Personal", "#F08C2E"), ("Relationships", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Not started", "#888888"), ("On track", "#3FB950"),
                        ("At risk", "#E8A93B"), ("Off track", "#D14B5C"),
                        ("Achieved", "#9D4DCC"), ("Abandoned", "#666666"),
                    ]),
                    FieldDef.make(name: "Target date", kind: .date),
                    FieldDef.make(name: "Progress %", kind: .number),
                    FieldDef.make(name: "Why", kind: .longText, description: "What's the motivation?"),
                    FieldDef.make(name: "Check-ins", kind: .noteLog),
                ],
                primary: "goal", kanban: "status", calendar: "target_date"
            )
        ),

        Entry(
            id: "lib.habit",
            category: .productivity,
            blurb: "Daily habit log with streak-friendly fields and a yes/no checkmark.",
            keywords: ["habit", "streak", "daily", "routine", "tracker"],
            template: makeType(
                id: "Habit", name: "Habit Entry", plural: "Habit Log",
                image: "flame", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Habit", [
                        ("Exercise", "#3FB950"), ("Read", "#3FA9F5"),
                        ("Meditate", "#9D4DCC"), ("Hydrate", "#3FA9F5"),
                        ("Journal", "#E8A93B"), ("Sleep by 11", "#666666"),
                    ]),
                    FieldDef.make(name: "Done", kind: .boolean, required: true),
                    FieldDef.make(name: "Effort (1–5)", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "habit", kanban: "habit", calendar: "date"
            )
        ),

        Entry(
            id: "lib.meeting",
            category: .productivity,
            blurb: "Meeting log with attendees, agenda, decisions, and follow-ups.",
            keywords: ["meeting", "1:1", "minutes", "agenda", "standup"],
            template: makeType(
                id: "Meeting", name: "Meeting", plural: "Meetings",
                image: "person.2.wave.2", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Type", [
                        ("1:1", "#9D4DCC"), ("Team", "#3FA9F5"),
                        ("Client", "#E8A93B"), ("Interview", "#3FB950"),
                        ("All hands", "#666666"),
                    ]),
                    FieldDef.make(name: "Attendees", kind: .link, description: "Link to People"),
                    FieldDef.make(name: "Agenda", kind: .longText),
                    FieldDef.make(name: "Notes & decisions", kind: .noteLog),
                    FieldDef.make(name: "Follow-ups", kind: .longText),
                ],
                primary: "title", kanban: "type", calendar: "when"
            )
        ),

        // MARK: Home & Life Admin

        Entry(
            id: "lib.household_chore",
            category: .home,
            blurb: "Rotating household chores with frequency, last done, and who's responsible.",
            keywords: ["chore", "household", "cleaning", "routine"],
            template: makeType(
                id: "Chore", name: "Chore", plural: "Chores",
                image: "sparkles.rectangle.stack", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Task", kind: .text, required: true),
                    selectField("Frequency", [
                        ("Daily", "#3FA9F5"), ("Weekly", "#9D4DCC"),
                        ("Monthly", "#E8A93B"), ("Quarterly", "#F08C2E"),
                        ("Seasonal", "#3FB950"), ("Yearly", "#666666"),
                    ]),
                    selectField("Room", [
                        ("Kitchen", "#E8A93B"), ("Bathroom", "#3FA9F5"),
                        ("Bedroom", "#9D4DCC"), ("Living room", "#3FB950"),
                        ("Garage", "#666666"), ("Outdoor", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Last done", kind: .date),
                    FieldDef.make(name: "Next due", kind: .date),
                    FieldDef.make(name: "Assigned to", kind: .link),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "task", kanban: "frequency", calendar: "next_due"
            )
        ),

        Entry(
            id: "lib.home_maintenance",
            category: .home,
            blurb: "Home maintenance log — filters changed, HVAC serviced, gutters cleared.",
            keywords: ["home", "maintenance", "hvac", "filter", "repair", "house"],
            template: makeType(
                id: "HomeMaintenance", name: "Maintenance Log", plural: "Home Maintenance",
                image: "wrench.adjustable", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Task", kind: .text, required: true),
                    FieldDef.make(name: "Date performed", kind: .date, required: true),
                    selectField("Category", [
                        ("HVAC", "#3FA9F5"), ("Plumbing", "#9D4DCC"),
                        ("Electrical", "#E8A93B"), ("Roof", "#666666"),
                        ("Exterior", "#3FB950"), ("Appliance", "#F08C2E"),
                        ("Pest", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Performed by", kind: .text, description: "Contractor or self"),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Warranty until", kind: .date),
                    FieldDef.make(name: "Receipt", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "task", kanban: "category", calendar: "date_performed"
            )
        ),

        Entry(
            id: "lib.warranty",
            category: .home,
            blurb: "Appliance & electronics warranties — model, serial, purchase date, expiry.",
            keywords: ["warranty", "appliance", "electronics", "registration", "receipt"],
            template: makeType(
                id: "Warranty", name: "Warranty", plural: "Warranties",
                image: "shield.checkered", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Product", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Model number", kind: .text),
                    FieldDef.make(name: "Serial number", kind: .text),
                    FieldDef.make(name: "Purchased", kind: .date),
                    FieldDef.make(name: "Warranty expires", kind: .date),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Expiring soon", "#E8A93B"),
                        ("Expired", "#888888"), ("Claimed", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Receipt", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "product", kanban: "status", calendar: "warranty_expires"
            )
        ),

        Entry(
            id: "lib.vehicle",
            category: .home,
            blurb: "Vehicles you own — VIN, plate, insurance, registration, service history.",
            keywords: ["vehicle", "car", "truck", "motorcycle", "vin", "insurance"],
            template: makeType(
                id: "Vehicle", name: "Vehicle", plural: "Vehicles",
                image: "car", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Make", kind: .text),
                    FieldDef.make(name: "Model", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "VIN", kind: .text),
                    FieldDef.make(name: "License plate", kind: .text),
                    FieldDef.make(name: "Color", kind: .text),
                    FieldDef.make(name: "Mileage", kind: .number),
                    FieldDef.make(name: "Insurance expires", kind: .date),
                    FieldDef.make(name: "Registration expires", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Service log", kind: .noteLog),
                ],
                primary: "nickname", calendar: "registration_expires",
                gallery: "photo"
            )
        ),

        Entry(
            id: "lib.plant",
            category: .home,
            blurb: "Indoor & outdoor plants — species, watering schedule, last watered.",
            keywords: ["plant", "houseplant", "garden", "water", "fertilize"],
            template: makeType(
                id: "Plant", name: "Plant", plural: "Plants",
                image: "leaf", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Species", kind: .text),
                    selectField("Light", [
                        ("Bright direct", "#E8A93B"), ("Bright indirect", "#F08C2E"),
                        ("Medium", "#3FB950"), ("Low", "#666666"),
                    ]),
                    selectField("Water frequency", [
                        ("Weekly", "#3FA9F5"), ("Every 2 weeks", "#9D4DCC"),
                        ("Every 3 weeks", "#E8A93B"), ("Monthly", "#666666"),
                        ("When dry", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Last watered", kind: .date),
                    FieldDef.make(name: "Last fertilized", kind: .date),
                    FieldDef.make(name: "Location at home", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Care log", kind: .noteLog),
                ],
                primary: "nickname", kanban: "water_frequency",
                calendar: "last_watered", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.medication",
            category: .health,
            blurb: "Daily medication & supplement tracker — dose, frequency, refill dates.",
            keywords: ["medication", "pill", "drug", "supplement", "prescription", "rx"],
            template: makeType(
                id: "Medication", name: "Medication", plural: "Medications",
                image: "pills", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Dosage", kind: .text, description: "e.g. 10 mg"),
                    selectField("Frequency", [
                        ("Once daily", "#3FA9F5"), ("Twice daily", "#9D4DCC"),
                        ("3× daily", "#E8A93B"), ("As needed", "#666666"),
                        ("Weekly", "#3FB950"),
                    ]),
                    selectField("Type", [
                        ("Prescription", "#D14B5C"), ("OTC", "#3FA9F5"),
                        ("Supplement", "#3FB950"), ("Vitamin", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Prescribing doctor", kind: .link),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Next refill", kind: .date),
                    FieldDef.make(name: "Pharmacy", kind: .text),
                    FieldDef.make(name: "Side effects observed", kind: .longText),
                ],
                primary: "name", kanban: "frequency", calendar: "next_refill"
            )
        ),

        Entry(
            id: "lib.doctor_visit",
            category: .health,
            blurb: "Medical appointments — provider, reason, notes, follow-up actions.",
            keywords: ["doctor", "appointment", "medical", "visit", "clinic", "health"],
            template: makeType(
                id: "DoctorVisit", name: "Doctor Visit", plural: "Doctor Visits",
                image: "stethoscope", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Reason", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Specialty", [
                        ("Primary care", "#3FA9F5"), ("Dental", "#3FB950"),
                        ("Vision", "#9D4DCC"), ("Mental health", "#E8A93B"),
                        ("Specialist", "#F08C2E"), ("Urgent care", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Provider", kind: .link),
                    FieldDef.make(name: "Visit notes", kind: .richText),
                    FieldDef.make(name: "Follow-up needed", kind: .boolean),
                    FieldDef.make(name: "Follow-up date", kind: .date),
                    FieldDef.make(name: "Attachments", kind: .attachment),
                ],
                primary: "reason", kanban: "specialty", calendar: "date"
            )
        ),

        Entry(
            id: "lib.symptom",
            category: .health,
            blurb: "Symptom journal — what hurt, when, severity, suspected triggers.",
            keywords: ["symptom", "pain", "journal", "trigger", "headache"],
            template: makeType(
                id: "Symptom", name: "Symptom Entry", plural: "Symptom Journal",
                image: "waveform.path.ecg", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Symptom", kind: .text, required: true),
                    FieldDef.make(name: "Severity (1–5)", kind: .rating),
                    selectField("Location", [
                        ("Head", "#9D4DCC"), ("Chest", "#D14B5C"),
                        ("Stomach", "#E8A93B"), ("Back", "#3FA9F5"),
                        ("Joints", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Suspected trigger", kind: .text),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "symptom", kanban: "location", calendar: "date"
            )
        ),

        Entry(
            id: "lib.workout",
            category: .health,
            blurb: "Workout log — date, type, duration, exercises performed.",
            keywords: ["workout", "exercise", "gym", "fitness", "training", "lift"],
            template: makeType(
                id: "Workout", name: "Workout", plural: "Workouts",
                image: "figure.run", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Type", [
                        ("Strength", "#9D4DCC"), ("Cardio", "#D14B5C"),
                        ("HIIT", "#F08C2E"), ("Yoga", "#3FB950"),
                        ("Sport", "#3FA9F5"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "Calories burned", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Exercises", kind: .longText, description: "One per line, e.g. Bench × 3×8"),
                    FieldDef.make(name: "Felt like", kind: .longText),
                ],
                primary: "type", kanban: "type", calendar: "date"
            )
        ),

        // MARK: Food & Drink

        Entry(
            id: "lib.recipe",
            category: .food,
            blurb: "Recipes you cook — ingredients, steps, cook time, rating, source.",
            keywords: ["recipe", "cook", "kitchen", "meal", "food"],
            template: makeType(
                id: "Recipe", name: "Recipe", plural: "Recipes",
                image: "fork.knife.circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Source", kind: .url),
                    selectField("Cuisine", [
                        ("Italian", "#3FB950"), ("Asian", "#D14B5C"),
                        ("Mexican", "#F08C2E"), ("American", "#3FA9F5"),
                        ("Mediterranean", "#9D4DCC"), ("Indian", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    selectField("Meal", [
                        ("Breakfast", "#E8A93B"), ("Lunch", "#3FA9F5"),
                        ("Dinner", "#9D4DCC"), ("Snack", "#3FB950"),
                        ("Dessert", "#D14B5C"), ("Drink", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Prep time (min)", kind: .number),
                    FieldDef.make(name: "Cook time (min)", kind: .number),
                    FieldDef.make(name: "Servings", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Ingredients", kind: .longText),
                    FieldDef.make(name: "Steps", kind: .richText),
                    FieldDef.make(name: "Cook log", kind: .noteLog),
                ],
                primary: "title", kanban: "cuisine", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.meal_plan",
            category: .food,
            blurb: "Weekly meal plan — date, meal slot, dish, recipe link, prep status.",
            keywords: ["meal", "plan", "menu", "weekly", "prep"],
            template: makeType(
                id: "MealPlan", name: "Meal Plan Entry", plural: "Meal Plan",
                image: "calendar.badge.plus", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Meal", [
                        ("Breakfast", "#E8A93B"), ("Lunch", "#3FA9F5"),
                        ("Dinner", "#9D4DCC"), ("Snack", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Dish", kind: .text, required: true),
                    FieldDef.make(name: "Recipe", kind: .link),
                    selectField("Status", [
                        ("Planned", "#888888"), ("Shopping done", "#3FA9F5"),
                        ("Prepped", "#9D4DCC"), ("Eaten", "#3FB950"),
                        ("Skipped", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "dish", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.wine",
            category: .food,
            blurb: "Wines you've tried — varietal, region, vintage, score, tasting notes.",
            keywords: ["wine", "cellar", "tasting", "vintage", "varietal"],
            template: makeType(
                id: "Wine", name: "Wine", plural: "Wines",
                image: "wineglass", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Producer", kind: .text),
                    FieldDef.make(name: "Vintage", kind: .number),
                    FieldDef.make(name: "Varietal", kind: .text),
                    FieldDef.make(name: "Region", kind: .text),
                    selectField("Type", [
                        ("Red", "#7B1E2D"), ("White", "#E8DBB0"),
                        ("Rosé", "#E8A0B5"), ("Sparkling", "#F0E68C"),
                        ("Fortified", "#9D4DCC"), ("Dessert", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Score (1–100)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Price", kind: .number),
                    FieldDef.make(name: "Date tasted", kind: .date),
                    FieldDef.make(name: "Label photo", kind: .attachment),
                    FieldDef.make(name: "Tasting notes", kind: .richText),
                ],
                primary: "name", kanban: "type", calendar: "date_tasted", gallery: "label_photo"
            )
        ),

        Entry(
            id: "lib.coffee",
            category: .food,
            blurb: "Coffee log — roaster, origin, process, brew method, dial-in.",
            keywords: ["coffee", "espresso", "roaster", "v60", "pourover", "brew"],
            template: makeType(
                id: "Coffee", name: "Coffee Bean", plural: "Coffee",
                image: "cup.and.saucer", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Bean", kind: .text, required: true),
                    FieldDef.make(name: "Roaster", kind: .text),
                    FieldDef.make(name: "Origin", kind: .text),
                    selectField("Process", [
                        ("Washed", "#3FA9F5"), ("Natural", "#E8A93B"),
                        ("Honey", "#F08C2E"), ("Anaerobic", "#9D4DCC"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Roast date", kind: .date),
                    FieldDef.make(name: "Tasting notes", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Brew log", kind: .noteLog),
                ],
                primary: "bean", kanban: "process", calendar: "roast_date"
            )
        ),

        Entry(
            id: "lib.restaurant",
            category: .food,
            blurb: "Restaurants you've eaten at — cuisine, neighborhood, rating, return-worthy.",
            keywords: ["restaurant", "dining", "review", "food"],
            template: makeType(
                id: "Restaurant", name: "Restaurant", plural: "Restaurants",
                image: "fork.knife", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Neighborhood", kind: .text),
                    FieldDef.make(name: "Cuisine", kind: .text),
                    selectField("Price", [
                        ("$", "#3FB950"), ("$$", "#3FA9F5"),
                        ("$$$", "#9D4DCC"), ("$$$$", "#D14B5C"),
                    ]),
                    selectField("Verdict", [
                        ("Go back!", "#3FB950"), ("Solid", "#3FA9F5"),
                        ("One-and-done", "#E8A93B"), ("Avoid", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Website", kind: .url),
                    FieldDef.make(name: "Visits", kind: .noteLog),
                ],
                primary: "name", kanban: "verdict"
            )
        ),

        // MARK: Money & Finance

        Entry(
            id: "lib.expense",
            category: .finance,
            blurb: "Expense entries with category, amount, vendor, receipt attachment.",
            keywords: ["expense", "spend", "money", "receipt", "budget"],
            template: makeType(
                id: "Expense", name: "Expense", plural: "Expenses",
                image: "creditcard", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    selectField("Category", [
                        ("Groceries", "#3FB950"), ("Dining", "#E8A93B"),
                        ("Transport", "#3FA9F5"), ("Utilities", "#9D4DCC"),
                        ("Entertainment", "#F08C2E"), ("Health", "#D14B5C"),
                        ("Subscriptions", "#666666"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Vendor", kind: .text),
                    FieldDef.make(name: "Account", kind: .text),
                    FieldDef.make(name: "Receipt", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "vendor", kanban: "category", calendar: "date"
            )
        ),

        Entry(
            id: "lib.subscription",
            category: .finance,
            blurb: "Recurring subscriptions — Netflix, gym, SaaS — with billing date and cost.",
            keywords: ["subscription", "recurring", "saas", "netflix", "streaming", "membership"],
            template: makeType(
                id: "Subscription", name: "Subscription", plural: "Subscriptions",
                image: "arrow.triangle.2.circlepath", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Service", kind: .text, required: true),
                    FieldDef.make(name: "Cost", kind: .number),
                    selectField("Billing cycle", [
                        ("Monthly", "#3FA9F5"), ("Quarterly", "#9D4DCC"),
                        ("Annual", "#E8A93B"), ("Lifetime", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Next charge", kind: .date),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Trial", "#E8A93B"),
                        ("Paused", "#666666"), ("Cancelled", "#D14B5C"),
                    ]),
                    selectField("Category", [
                        ("Streaming", "#3FA9F5"), ("Software", "#9D4DCC"),
                        ("News", "#E8A93B"), ("Fitness", "#3FB950"),
                        ("Cloud", "#F08C2E"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Login", kind: .url),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "service", kanban: "status", calendar: "next_charge"
            )
        ),

        Entry(
            id: "lib.investment",
            category: .finance,
            blurb: "Holdings tracker — ticker, shares, cost basis, current value.",
            keywords: ["investment", "stock", "portfolio", "ticker", "etf", "crypto"],
            template: makeType(
                id: "Investment", name: "Holding", plural: "Investments",
                image: "chart.line.uptrend.xyaxis", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Ticker", kind: .text, required: true),
                    FieldDef.make(name: "Name", kind: .text),
                    selectField("Type", [
                        ("Stock", "#3FA9F5"), ("ETF", "#9D4DCC"),
                        ("Mutual fund", "#E8A93B"), ("Bond", "#666666"),
                        ("Crypto", "#F08C2E"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Shares", kind: .number),
                    FieldDef.make(name: "Cost basis", kind: .number),
                    FieldDef.make(name: "Current price", kind: .number),
                    FieldDef.make(name: "Account", kind: .text),
                    FieldDef.make(name: "Thesis", kind: .longText),
                ],
                primary: "ticker", kanban: "type"
            )
        ),

        // MARK: Hobbies & Collecting

        Entry(
            id: "lib.boardgame",
            category: .hobbies,
            blurb: "Board games owned — player count, length, mechanics, last played.",
            keywords: ["board", "game", "tabletop", "bgg"],
            template: makeType(
                id: "BoardGame", name: "Board Game", plural: "Board Games",
                image: "die.face.5", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Designer", kind: .text),
                    FieldDef.make(name: "Publisher", kind: .text),
                    FieldDef.make(name: "Players (min)", kind: .number),
                    FieldDef.make(name: "Players (max)", kind: .number),
                    FieldDef.make(name: "Playtime (min)", kind: .number),
                    selectField("Weight", [
                        ("Light", "#3FB950"), ("Medium-light", "#3FA9F5"),
                        ("Medium", "#9D4DCC"), ("Medium-heavy", "#E8A93B"),
                        ("Heavy", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "BGG rank", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Last played", kind: .date),
                    FieldDef.make(name: "Box photo", kind: .attachment),
                    FieldDef.make(name: "Play log", kind: .noteLog),
                ],
                primary: "title", kanban: "weight", gallery: "box_photo"
            )
        ),

        Entry(
            id: "lib.vinyl",
            category: .hobbies,
            blurb: "Vinyl record collection — artist, label, pressing, condition.",
            keywords: ["vinyl", "record", "lp", "album", "music", "collection"],
            template: makeType(
                id: "VinylRecord", name: "Vinyl Record", plural: "Vinyl Collection",
                image: "opticaldisc", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Album", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Label", kind: .text),
                    FieldDef.make(name: "Catalog #", kind: .text),
                    FieldDef.make(name: "Pressing", kind: .text, description: "e.g. 1973 1st US"),
                    selectField("Speed", [
                        ("33⅓", "#3FA9F5"), ("45", "#9D4DCC"), ("78", "#666666"),
                    ]),
                    selectField("Condition", [
                        ("Mint", "#3FB950"), ("Near mint", "#3FA9F5"),
                        ("Very good+", "#9D4DCC"), ("Very good", "#E8A93B"),
                        ("Good", "#F08C2E"), ("Fair", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Purchased", kind: .date),
                    FieldDef.make(name: "Paid", kind: .number),
                    FieldDef.make(name: "Cover", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "album", kanban: "condition", gallery: "cover"
            )
        ),

        Entry(
            id: "lib.lego",
            category: .hobbies,
            blurb: "LEGO set log — number, theme, piece count, build status, value.",
            keywords: ["lego", "set", "minifig", "brick", "afol"],
            template: makeType(
                id: "LegoSet", name: "LEGO Set", plural: "LEGO Sets",
                image: "cube", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Set number", kind: .text, required: true),
                    FieldDef.make(name: "Name", kind: .text),
                    FieldDef.make(name: "Theme", kind: .text),
                    FieldDef.make(name: "Year released", kind: .number),
                    FieldDef.make(name: "Pieces", kind: .number),
                    FieldDef.make(name: "Minifigs", kind: .number),
                    selectField("Status", [
                        ("Wishlist", "#888888"), ("Owned (sealed)", "#9D4DCC"),
                        ("Built", "#3FB950"), ("Displayed", "#3FA9F5"),
                        ("Disassembled", "#E8A93B"), ("Sold", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Purchased", kind: .date),
                    FieldDef.make(name: "Paid", kind: .number),
                    FieldDef.make(name: "Current value", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "status", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.guitar",
            category: .hobbies,
            blurb: "Guitars & instruments owned — make, model, year, last setup.",
            keywords: ["guitar", "bass", "instrument", "music", "amp"],
            template: makeType(
                id: "Instrument", name: "Instrument", plural: "Instruments",
                image: "guitars", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Make", kind: .text),
                    FieldDef.make(name: "Model", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Serial", kind: .text),
                    selectField("Type", [
                        ("Electric guitar", "#9D4DCC"), ("Acoustic guitar", "#E8A93B"),
                        ("Bass", "#3FA9F5"), ("Keyboard", "#3FB950"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Strings gauge", kind: .text),
                    FieldDef.make(name: "Last setup", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Maintenance log", kind: .noteLog),
                ],
                primary: "nickname", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.stamp",
            category: .hobbies,
            blurb: "Stamp collection — country, year, condition, catalog reference.",
            keywords: ["stamp", "philately", "postage", "collection"],
            template: makeType(
                id: "Stamp", name: "Stamp", plural: "Stamps",
                image: "envelope.badge", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "Year issued", kind: .number),
                    FieldDef.make(name: "Denomination", kind: .text),
                    FieldDef.make(name: "Scott #", kind: .text),
                    selectField("Condition", [
                        ("Mint NH", "#3FB950"), ("Mint hinged", "#3FA9F5"),
                        ("Used", "#9D4DCC"), ("Damaged", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Estimated value", kind: .number),
                    FieldDef.make(name: "Image", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "condition", gallery: "image"
            )
        ),

        Entry(
            id: "lib.bird_sighting",
            category: .hobbies,
            blurb: "Bird sightings — species, location, date, behavior, photo.",
            keywords: ["bird", "birding", "sighting", "ebird", "wildlife"],
            template: makeType(
                id: "BirdSighting", name: "Bird Sighting", plural: "Bird Sightings",
                image: "bird", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Count", kind: .number),
                    selectField("Habitat", [
                        ("Backyard", "#3FB950"), ("Forest", "#9D4DCC"),
                        ("Wetland", "#3FA9F5"), ("Shore", "#E8A93B"),
                        ("Urban", "#666666"), ("Mountain", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "First time?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "species", kanban: "habitat", calendar: "date", gallery: "photo"
            )
        ),

        // MARK: Media & Entertainment

        Entry(
            id: "lib.movie",
            category: .media,
            blurb: "Movies watched — title, year, director, where you watched, rating.",
            keywords: ["movie", "film", "cinema", "watch", "letterboxd"],
            template: makeType(
                id: "Movie", name: "Movie", plural: "Movies",
                image: "film", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Director", kind: .text),
                    FieldDef.make(name: "Runtime (min)", kind: .number),
                    selectField("Status", [
                        ("Want to watch", "#888888"), ("Watching", "#3FA9F5"),
                        ("Watched", "#3FB950"), ("Abandoned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Date watched", kind: .date),
                    selectField("Where", [
                        ("Theater", "#9D4DCC"), ("Streaming", "#3FA9F5"),
                        ("Blu-ray", "#3FB950"), ("Rental", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Poster", kind: .attachment),
                    FieldDef.make(name: "Review", kind: .richText),
                ],
                primary: "title", kanban: "status", calendar: "date_watched", gallery: "poster"
            )
        ),

        Entry(
            id: "lib.tv_show",
            category: .media,
            blurb: "TV shows — current season/episode, status, network, rating.",
            keywords: ["tv", "show", "series", "netflix", "episode"],
            template: makeType(
                id: "TVShow", name: "TV Show", plural: "TV Shows",
                image: "tv", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Network", kind: .text),
                    FieldDef.make(name: "Year started", kind: .number),
                    selectField("Status", [
                        ("Want to watch", "#888888"), ("Watching", "#3FA9F5"),
                        ("Caught up", "#9D4DCC"), ("Completed", "#3FB950"),
                        ("Abandoned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Current season", kind: .number),
                    FieldDef.make(name: "Current episode", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Poster", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "status", gallery: "poster"
            )
        ),

        Entry(
            id: "lib.video_game",
            category: .media,
            blurb: "Video game backlog — platform, hours, status, rating.",
            keywords: ["game", "video", "playstation", "xbox", "steam", "nintendo"],
            template: makeType(
                id: "VideoGame", name: "Video Game", plural: "Video Games",
                image: "gamecontroller", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    selectField("Platform", [
                        ("PC", "#3FA9F5"), ("PlayStation", "#0070DD"),
                        ("Xbox", "#3FB950"), ("Switch", "#D14B5C"),
                        ("Mobile", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Wishlist", "#888888"), ("Playing", "#3FA9F5"),
                        ("Completed", "#3FB950"), ("100%", "#9D4DCC"),
                        ("Dropped", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Hours played", kind: .number),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Finished", kind: .date),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Cover", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "status", calendar: "finished", gallery: "cover"
            )
        ),

        Entry(
            id: "lib.podcast",
            category: .media,
            blurb: "Podcast episodes — show, host, length, key takeaways.",
            keywords: ["podcast", "episode", "audio", "listen"],
            template: makeType(
                id: "PodcastEpisode", name: "Podcast Episode", plural: "Podcast Episodes",
                image: "mic", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Episode title", kind: .text, required: true),
                    FieldDef.make(name: "Show", kind: .text),
                    FieldDef.make(name: "Guest", kind: .text),
                    FieldDef.make(name: "Date listened", kind: .date),
                    FieldDef.make(name: "Length (min)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Link", kind: .url),
                    FieldDef.make(name: "Key takeaways", kind: .richText),
                ],
                primary: "episode_title", calendar: "date_listened"
            )
        ),

        // MARK: Travel & Places

        Entry(
            id: "lib.trip",
            category: .travel,
            blurb: "Trips — destination, dates, travelers, accommodation, highlights.",
            keywords: ["trip", "travel", "vacation", "itinerary"],
            template: makeType(
                id: "Trip", name: "Trip", plural: "Trips",
                image: "airplane", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Destination", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "Start", kind: .date, required: true),
                    FieldDef.make(name: "End", kind: .date),
                    selectField("Type", [
                        ("Vacation", "#3FB950"), ("Work", "#3FA9F5"),
                        ("Family", "#9D4DCC"), ("Adventure", "#E8A93B"),
                        ("Wellness", "#F08C2E"),
                    ]),
                    selectField("Status", [
                        ("Researching", "#888888"), ("Booked", "#3FA9F5"),
                        ("Underway", "#9D4DCC"), ("Completed", "#3FB950"),
                        ("Cancelled", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Travelers", kind: .link),
                    FieldDef.make(name: "Budget", kind: .number),
                    FieldDef.make(name: "Cover photo", kind: .attachment),
                    FieldDef.make(name: "Highlights", kind: .richText),
                    FieldDef.make(name: "Trip log", kind: .noteLog),
                ],
                primary: "destination", kanban: "status", calendar: "start", gallery: "cover_photo"
            )
        ),

        Entry(
            id: "lib.flight",
            category: .travel,
            blurb: "Flights — airline, route, dates, confirmation, seat.",
            keywords: ["flight", "airline", "travel", "boarding", "ticket"],
            template: makeType(
                id: "Flight", name: "Flight", plural: "Flights",
                image: "airplane.departure", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Flight number", kind: .text, required: true),
                    FieldDef.make(name: "Airline", kind: .text),
                    FieldDef.make(name: "From", kind: .text),
                    FieldDef.make(name: "To", kind: .text),
                    FieldDef.make(name: "Departs", kind: .dateTime, required: true),
                    FieldDef.make(name: "Arrives", kind: .dateTime),
                    FieldDef.make(name: "Seat", kind: .text),
                    FieldDef.make(name: "Confirmation", kind: .text),
                    selectField("Status", [
                        ("Booked", "#3FA9F5"), ("Checked in", "#9D4DCC"),
                        ("Flown", "#3FB950"), ("Cancelled", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Boarding pass", kind: .attachment),
                    FieldDef.make(name: "Trip", kind: .link),
                ],
                primary: "flight_number", kanban: "status", calendar: "departs"
            )
        ),

        Entry(
            id: "lib.place_visited",
            category: .travel,
            blurb: "Places visited — city, country, dates, what you did there.",
            keywords: ["place", "city", "country", "visited", "geography"],
            template: makeType(
                id: "PlaceVisited", name: "Place Visited", plural: "Places Visited",
                image: "mappin.and.ellipse", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Place", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "First visit", kind: .date),
                    FieldDef.make(name: "Latest visit", kind: .date),
                    FieldDef.make(name: "Number of visits", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "place", calendar: "latest_visit", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.hike",
            category: .travel,
            blurb: "Hikes & trails — distance, elevation, conditions, companions.",
            keywords: ["hike", "trail", "outdoor", "walking", "backpacking"],
            template: makeType(
                id: "Hike", name: "Hike", plural: "Hikes",
                image: "figure.hiking", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Trail", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Park / area", kind: .text),
                    FieldDef.make(name: "Distance (mi)", kind: .number),
                    FieldDef.make(name: "Elevation gain (ft)", kind: .number),
                    FieldDef.make(name: "Time (min)", kind: .number),
                    selectField("Difficulty", [
                        ("Easy", "#3FB950"), ("Moderate", "#3FA9F5"),
                        ("Hard", "#E8A93B"), ("Strenuous", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Companions", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "trail", kanban: "difficulty", calendar: "date", gallery: "photo"
            )
        ),

        // MARK: Creative Work

        Entry(
            id: "lib.writing",
            category: .creative,
            blurb: "Writing projects — drafts, word count, status, deadlines.",
            keywords: ["writing", "draft", "blog", "essay", "manuscript"],
            template: makeType(
                id: "WritingPiece", name: "Piece", plural: "Writing",
                image: "pencil.and.outline", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    selectField("Type", [
                        ("Blog post", "#3FA9F5"), ("Essay", "#9D4DCC"),
                        ("Short story", "#E8A93B"), ("Novel chapter", "#F08C2E"),
                        ("Poetry", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Outlining", "#3FA9F5"),
                        ("Drafting", "#9D4DCC"), ("Revising", "#E8A93B"),
                        ("Submitted", "#F08C2E"), ("Published", "#3FB950"),
                        ("Shelved", "#666666"),
                    ]),
                    FieldDef.make(name: "Word count", kind: .number),
                    FieldDef.make(name: "Target word count", kind: .number),
                    FieldDef.make(name: "Deadline", kind: .date),
                    FieldDef.make(name: "Published link", kind: .url),
                    FieldDef.make(name: "Draft", kind: .richText),
                    FieldDef.make(name: "Revision log", kind: .noteLog),
                ],
                primary: "title", kanban: "status", calendar: "deadline"
            )
        ),

        Entry(
            id: "lib.art_piece",
            category: .creative,
            blurb: "Drawings, paintings, digital art — medium, dimensions, status, photo.",
            keywords: ["art", "drawing", "painting", "sketch", "digital", "illustration"],
            template: makeType(
                id: "ArtPiece", name: "Art Piece", plural: "Art",
                image: "paintbrush", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    selectField("Medium", [
                        ("Pencil", "#666666"), ("Ink", "#3FA9F5"),
                        ("Watercolor", "#9D4DCC"), ("Oil", "#E8A93B"),
                        ("Acrylic", "#3FB950"), ("Digital", "#F08C2E"),
                        ("Mixed", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("In progress", "#9D4DCC"), ("Completed", "#3FB950"),
                        ("Displayed", "#3FA9F5"), ("Sold", "#E8A93B"),
                        ("Gifted", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Completed", kind: .date),
                    FieldDef.make(name: "Dimensions", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Reference photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "status", calendar: "completed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.craft",
            category: .creative,
            blurb: "Knitting, sewing, woodworking projects — pattern, yarn, status, photo.",
            keywords: ["craft", "knit", "sew", "wood", "diy", "maker"],
            template: makeType(
                id: "CraftProject", name: "Craft Project", plural: "Craft Projects",
                image: "scissors", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Craft", [
                        ("Knit", "#9D4DCC"), ("Crochet", "#3FA9F5"),
                        ("Sew", "#E8A93B"), ("Embroidery", "#F08C2E"),
                        ("Woodwork", "#7B4F2F"), ("Pottery", "#3FB950"),
                        ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Planning", "#888888"), ("Materials gathered", "#3FA9F5"),
                        ("In progress", "#9D4DCC"), ("Finished", "#3FB950"),
                        ("Frogged", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Pattern / plan", kind: .url),
                    FieldDef.make(name: "Materials", kind: .longText),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Finished", kind: .date),
                    FieldDef.make(name: "Progress photos", kind: .attachment),
                    FieldDef.make(name: "Project log", kind: .noteLog),
                ],
                primary: "name", kanban: "status", calendar: "finished", gallery: "progress_photos"
            )
        ),

        // MARK: Work & Career

        Entry(
            id: "lib.job_application",
            category: .professional,
            blurb: "Job applications — company, role, status, contacts, next step.",
            keywords: ["job", "application", "interview", "career", "hiring"],
            template: makeType(
                id: "JobApplication", name: "Application", plural: "Job Search",
                image: "briefcase", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Company", kind: .text, required: true),
                    FieldDef.make(name: "Role", kind: .text, required: true),
                    selectField("Status", [
                        ("Researching", "#888888"), ("Applied", "#3FA9F5"),
                        ("Screened", "#9D4DCC"), ("Interviewing", "#E8A93B"),
                        ("Offer", "#3FB950"), ("Rejected", "#D14B5C"),
                        ("Withdrawn", "#666666"),
                    ]),
                    FieldDef.make(name: "Applied on", kind: .date),
                    FieldDef.make(name: "Salary range", kind: .text),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Recruiter", kind: .link),
                    FieldDef.make(name: "JD link", kind: .url),
                    FieldDef.make(name: "Next step", kind: .text),
                    FieldDef.make(name: "Next step date", kind: .date),
                    FieldDef.make(name: "Resume sent", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "company", kanban: "status", calendar: "next_step_date"
            )
        ),

        Entry(
            id: "lib.client",
            category: .professional,
            blurb: "Clients & accounts — primary contact, status, retainer, last touch.",
            keywords: ["client", "crm", "account", "contract", "consulting"],
            template: makeType(
                id: "Client", name: "Client", plural: "Clients",
                image: "person.crop.rectangle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Industry", kind: .text),
                    FieldDef.make(name: "Primary contact", kind: .link),
                    selectField("Status", [
                        ("Lead", "#888888"), ("Proposal sent", "#3FA9F5"),
                        ("Active", "#3FB950"), ("On hold", "#E8A93B"),
                        ("Churned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Monthly retainer", kind: .number),
                    FieldDef.make(name: "Contract end", kind: .date),
                    FieldDef.make(name: "Last touch", kind: .date),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "name", kanban: "status", calendar: "contract_end"
            )
        ),

        Entry(
            id: "lib.invoice",
            category: .professional,
            blurb: "Invoices issued — client, amount, due date, paid status.",
            keywords: ["invoice", "billing", "payment", "freelance", "ar"],
            template: makeType(
                id: "Invoice", name: "Invoice", plural: "Invoices",
                image: "doc.text", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Invoice #", kind: .text, required: true),
                    FieldDef.make(name: "Client", kind: .link),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    FieldDef.make(name: "Issued", kind: .date),
                    FieldDef.make(name: "Due", kind: .date),
                    selectField("Status", [
                        ("Draft", "#888888"), ("Sent", "#3FA9F5"),
                        ("Paid", "#3FB950"), ("Overdue", "#D14B5C"),
                        ("Void", "#666666"),
                    ]),
                    FieldDef.make(name: "Paid on", kind: .date),
                    FieldDef.make(name: "PDF", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "invoice", kanban: "status", calendar: "due"
            )
        ),

        // MARK: Learning & Reference

        Entry(
            id: "lib.course",
            category: .learning,
            blurb: "Online courses — platform, instructor, progress, certificate.",
            keywords: ["course", "udemy", "coursera", "education", "learning"],
            template: makeType(
                id: "Course", name: "Course", plural: "Courses",
                image: "graduationcap", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Platform", kind: .text),
                    FieldDef.make(name: "Instructor", kind: .text),
                    FieldDef.make(name: "URL", kind: .url),
                    selectField("Status", [
                        ("Wishlist", "#888888"), ("In progress", "#3FA9F5"),
                        ("Completed", "#3FB950"), ("Certified", "#9D4DCC"),
                        ("Abandoned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Completed", kind: .date),
                    FieldDef.make(name: "Progress %", kind: .number),
                    FieldDef.make(name: "Hours invested", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Certificate", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "title", kanban: "status", calendar: "completed"
            )
        ),

        Entry(
            id: "lib.research_paper",
            category: .learning,
            blurb: "Academic papers read — citation, summary, key findings.",
            keywords: ["paper", "research", "academic", "citation", "doi", "arxiv"],
            template: makeType(
                id: "ResearchPaper", name: "Paper", plural: "Research Papers",
                image: "doc.richtext", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Authors", kind: .text),
                    FieldDef.make(name: "Journal / venue", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "DOI / arXiv", kind: .text),
                    FieldDef.make(name: "URL", kind: .url),
                    selectField("Status", [
                        ("Queued", "#888888"), ("Skimmed", "#3FA9F5"),
                        ("Read", "#9D4DCC"), ("Annotated", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "PDF", kind: .attachment),
                    FieldDef.make(name: "Summary", kind: .richText),
                    FieldDef.make(name: "Key findings", kind: .longText),
                    FieldDef.make(name: "BibTeX", kind: .longText),
                ],
                primary: "title", kanban: "status"
            )
        ),

        Entry(
            id: "lib.vocab",
            category: .learning,
            blurb: "Foreign-language vocabulary — word, translation, example, mastery.",
            keywords: ["vocab", "language", "spanish", "french", "flashcard"],
            template: makeType(
                id: "VocabWord", name: "Vocab Word", plural: "Vocabulary",
                image: "character.book.closed", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Word", kind: .text, required: true),
                    FieldDef.make(name: "Language", kind: .text),
                    FieldDef.make(name: "Translation", kind: .text),
                    FieldDef.make(name: "Pronunciation", kind: .text),
                    selectField("Part of speech", [
                        ("Noun", "#3FA9F5"), ("Verb", "#9D4DCC"),
                        ("Adjective", "#E8A93B"), ("Adverb", "#F08C2E"),
                        ("Other", "#666666"),
                    ]),
                    selectField("Mastery", [
                        ("New", "#888888"), ("Learning", "#3FA9F5"),
                        ("Familiar", "#9D4DCC"), ("Mastered", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Example sentence", kind: .longText),
                    FieldDef.make(name: "Last reviewed", kind: .date),
                ],
                primary: "word", kanban: "mastery"
            )
        ),

        // MARK: Relationships

        Entry(
            id: "lib.gift_idea",
            category: .relationships,
            blurb: "Gift ideas for people in your life — recipient, occasion, where to buy.",
            keywords: ["gift", "present", "birthday", "holiday"],
            template: makeType(
                id: "GiftIdea", name: "Gift Idea", plural: "Gift Ideas",
                image: "gift", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Idea", kind: .text, required: true),
                    FieldDef.make(name: "For", kind: .link),
                    selectField("Occasion", [
                        ("Birthday", "#9D4DCC"), ("Holiday", "#3FB950"),
                        ("Anniversary", "#D14B5C"), ("Just because", "#E8A93B"),
                        ("Wedding", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Estimated cost", kind: .number),
                    FieldDef.make(name: "Where to get", kind: .url),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Bought", "#3FA9F5"),
                        ("Wrapped", "#9D4DCC"), ("Given", "#3FB950"),
                        ("Skipped", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Occasion date", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "idea", kanban: "status", calendar: "occasion_date"
            )
        ),

        Entry(
            id: "lib.touch_log",
            category: .relationships,
            blurb: "Keep-in-touch log — last contacted, cadence, what you talked about.",
            keywords: ["touch", "contact", "friend", "relationship", "checkin"],
            template: makeType(
                id: "TouchLog", name: "Touch Log Entry", plural: "Keep in Touch",
                image: "phone.bubble", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Channel", [
                        ("In person", "#3FB950"), ("Phone", "#3FA9F5"),
                        ("Text", "#9D4DCC"), ("Email", "#E8A93B"),
                        ("Video", "#F08C2E"), ("Social", "#666666"),
                    ]),
                    selectField("Cadence target", [
                        ("Weekly", "#3FA9F5"), ("Monthly", "#9D4DCC"),
                        ("Quarterly", "#E8A93B"), ("Yearly", "#666666"),
                    ]),
                    FieldDef.make(name: "What we talked about", kind: .richText),
                    FieldDef.make(name: "Follow up", kind: .text),
                ],
                primary: "person", kanban: "channel", calendar: "date"
            )
        ),

        // MARK: Unusual / Niche

        Entry(
            id: "lib.dream",
            category: .unusual,
            blurb: "Dream journal — date, vivid recall, recurring symbols, mood.",
            keywords: ["dream", "journal", "lucid", "sleep"],
            template: makeType(
                id: "Dream", name: "Dream", plural: "Dream Journal",
                image: "moon.stars", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Title", kind: .text),
                    selectField("Vividness", [
                        ("Foggy", "#888888"), ("Clear", "#3FA9F5"),
                        ("Vivid", "#9D4DCC"), ("Lucid", "#E8A93B"),
                    ]),
                    selectField("Mood", [
                        ("Peaceful", "#3FB950"), ("Anxious", "#E8A93B"),
                        ("Scary", "#D14B5C"), ("Strange", "#9D4DCC"),
                        ("Hopeful", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Symbols / themes", kind: .text),
                    FieldDef.make(name: "Recall", kind: .richText),
                ],
                primary: "title", kanban: "vividness", calendar: "date"
            )
        ),

        Entry(
            id: "lib.cocktail",
            category: .unusual,
            blurb: "Cocktails you've made — recipe, glassware, garnish, photo, rating.",
            keywords: ["cocktail", "bar", "drink", "mixology", "spirits"],
            template: makeType(
                id: "Cocktail", name: "Cocktail", plural: "Cocktails",
                image: "wineglass.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Base spirit", [
                        ("Gin", "#3FB950"), ("Vodka", "#3FA9F5"),
                        ("Rum", "#7B4F2F"), ("Tequila", "#E8A93B"),
                        ("Whiskey", "#F08C2E"), ("Brandy", "#9D4DCC"),
                        ("None", "#666666"),
                    ]),
                    FieldDef.make(name: "Glassware", kind: .text),
                    FieldDef.make(name: "Garnish", kind: .text),
                    FieldDef.make(name: "Ingredients", kind: .longText),
                    FieldDef.make(name: "Method", kind: .richText),
                    FieldDef.make(name: "Source", kind: .url),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "base_spirit", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.tarot_reading",
            category: .unusual,
            blurb: "Tarot readings — spread, cards drawn, interpretation, follow-up.",
            keywords: ["tarot", "card", "reading", "divination", "spread"],
            template: makeType(
                id: "TarotReading", name: "Reading", plural: "Tarot Readings",
                image: "rectangle.portrait.on.rectangle.portrait", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Spread", [
                        ("One card", "#3FA9F5"), ("Past–Present–Future", "#9D4DCC"),
                        ("Celtic Cross", "#E8A93B"), ("Year ahead", "#F08C2E"),
                        ("Custom", "#666666"),
                    ]),
                    FieldDef.make(name: "Question", kind: .text),
                    FieldDef.make(name: "Cards drawn", kind: .longText),
                    FieldDef.make(name: "Interpretation", kind: .richText),
                    FieldDef.make(name: "Outcome / follow-up", kind: .longText),
                    FieldDef.make(name: "Photo of spread", kind: .attachment),
                ],
                primary: "question", kanban: "spread", calendar: "date", gallery: "photo_of_spread"
            )
        ),

        Entry(
            id: "lib.weather_log",
            category: .unusual,
            blurb: "Daily weather observations — temp, conditions, mood correlation.",
            keywords: ["weather", "climate", "temperature", "observation"],
            template: makeType(
                id: "WeatherLog", name: "Observation", plural: "Weather Log",
                image: "cloud.sun", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "High (°F)", kind: .number),
                    FieldDef.make(name: "Low (°F)", kind: .number),
                    selectField("Conditions", [
                        ("Sunny", "#E8A93B"), ("Partly cloudy", "#3FA9F5"),
                        ("Cloudy", "#888888"), ("Rain", "#9D4DCC"),
                        ("Storm", "#D14B5C"), ("Snow", "#FFFFFF"),
                        ("Fog", "#666666"),
                    ]),
                    FieldDef.make(name: "Precipitation (in)", kind: .number),
                    FieldDef.make(name: "Wind", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", kanban: "conditions", calendar: "date"
            )
        ),

        Entry(
            id: "lib.fish_caught",
            category: .unusual,
            blurb: "Fishing log — species, length, weight, lure, location, released?",
            keywords: ["fishing", "fish", "tackle", "lure", "angling"],
            template: makeType(
                id: "FishCaught", name: "Catch", plural: "Fishing Log",
                image: "fish", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Length (in)", kind: .number),
                    FieldDef.make(name: "Weight (lb)", kind: .number),
                    FieldDef.make(name: "Lure / bait", kind: .text),
                    selectField("Conditions", [
                        ("Sunny", "#E8A93B"), ("Overcast", "#888888"),
                        ("Raining", "#3FA9F5"), ("Windy", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Released?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "species", kanban: "conditions", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.lefse",
            category: .unusual,
            blurb: "A truly unique example — log every batch of lefse (or any folk recipe) with starter, technique tweaks, and verdict.",
            keywords: ["lefse", "tradition", "batch", "experiment", "norwegian"],
            template: makeType(
                id: "LefseBatch", name: "Batch", plural: "Lefse Batches",
                image: "circle.dashed", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Batch #", kind: .number, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Potato variety", kind: .text),
                    FieldDef.make(name: "Riced grams", kind: .number),
                    FieldDef.make(name: "Flour grams", kind: .number),
                    FieldDef.make(name: "Butter grams", kind: .number),
                    FieldDef.make(name: "Cream grams", kind: .number),
                    FieldDef.make(name: "Grill temp (°F)", kind: .number),
                    FieldDef.make(name: "Yield (rounds)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "What I'd change", kind: .longText),
                ],
                primary: "batch", calendar: "date", gallery: "photo"
            )
        ),
    ]

    // MARK: - Type builder

    /// Concise helper for the entry literals above. Resolves the
    /// `primary`/`kanban`/`calendar`/`gallery` string parameters into the
    /// field keys those fields produce; `FieldDef.make` derives the key
    /// from the name (lowercased + snake_case) so we just match against
    /// the slugged name.
    /// Builder used by both the core catalog and the extended catalog
    /// extension. Internal (not fileprivate) so the extension file can
    /// reach it.
    static func makeType(
        id: String,
        name: String,
        plural: String,
        image: String,
        color: String,
        fields: [FieldDef],
        primary: String? = nil,
        kanban: String? = nil,
        calendar: String? = nil,
        gallery: String? = nil
    ) -> ObjectType {
        // Library entries import as user-defined types (builtIn: false).
        // The id is stamped at materialization time; the in-template id
        // is just a stable handle for debugging the catalog itself.
        ObjectType(
            id: id,
            name: name,
            pluralName: plural,
            systemImage: image,
            colorHex: color,
            fields: fields,
            builtIn: false,
            primaryFieldKey: primary,
            kanbanGroupKey: kanban,
            calendarDateKey: calendar,
            galleryAttachmentKey: gallery,
            updatedAt: nil
        )
    }
}
