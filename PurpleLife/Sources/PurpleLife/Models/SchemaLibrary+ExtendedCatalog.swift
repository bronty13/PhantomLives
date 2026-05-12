import Foundation

/// Extended schema-library catalog. Lives in its own file so the core
/// catalog in `SchemaLibrary.swift` stays focused on the framework
/// (Entry, Category, search) and the original first-batch templates.
/// `SchemaLibrary.entries` is a computed property that concatenates
/// `coreEntries` (the original list) and `extendedEntries` (this list),
/// so the gallery + every consumer sees a single flat catalog.
///
/// New entries can land here freely. Tests in `SchemaLibraryTests`
/// validate that every entry satisfies the catalog invariants
/// (primary-field exists, kanban key references a select field, etc.).
extension SchemaLibrary {

    static let extendedEntries: [Entry] = [

        // MARK: - Productivity & Planning (extended)

        Entry(
            id: "lib.task",
            category: .productivity,
            blurb: "Lightweight to-do — title, due date, priority, done flag.",
            keywords: ["task", "todo", "checklist", "action"],
            template: makeType(
                id: "Task", name: "Task", plural: "Tasks",
                image: "checkmark.square", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Due", kind: .date),
                    selectField("Priority", [
                        ("Low", "#888888"), ("Medium", "#3FA9F5"),
                        ("High", "#E8A93B"), ("Urgent", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Inbox", "#888888"), ("Next", "#3FA9F5"),
                        ("In progress", "#9D4DCC"), ("Waiting", "#E8A93B"),
                        ("Done", "#3FB950"), ("Cancelled", "#666666"),
                    ]),
                    FieldDef.make(name: "Tags", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "status", calendar: "due"
            )
        ),

        Entry(
            id: "lib.okr",
            category: .productivity,
            blurb: "Objectives & Key Results — quarterly OKR tracker.",
            keywords: ["okr", "objective", "key result", "kpi", "quarterly"],
            template: makeType(
                id: "OKR", name: "OKR", plural: "OKRs",
                image: "scope", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Objective", kind: .text, required: true),
                    FieldDef.make(name: "Key results", kind: .longText),
                    selectField("Quarter", [
                        ("Q1", "#3FB950"), ("Q2", "#3FA9F5"),
                        ("Q3", "#9D4DCC"), ("Q4", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Owner", kind: .link),
                    selectField("Status", [
                        ("Not started", "#888888"), ("On track", "#3FB950"),
                        ("At risk", "#E8A93B"), ("Off track", "#D14B5C"),
                        ("Done", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Confidence %", kind: .number),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "objective", kanban: "status"
            )
        ),

        Entry(
            id: "lib.sprint",
            category: .productivity,
            blurb: "Agile sprint — number, dates, goal, retro takeaways.",
            keywords: ["sprint", "scrum", "agile", "iteration"],
            template: makeType(
                id: "Sprint", name: "Sprint", plural: "Sprints",
                image: "arrow.triangle.2.circlepath.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Number", kind: .number, required: true),
                    FieldDef.make(name: "Goal", kind: .text),
                    FieldDef.make(name: "Start", kind: .date),
                    FieldDef.make(name: "End", kind: .date),
                    selectField("Status", [
                        ("Planning", "#888888"), ("Active", "#3FA9F5"),
                        ("In review", "#9D4DCC"), ("Closed", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Velocity (points)", kind: .number),
                    FieldDef.make(name: "What went well", kind: .longText),
                    FieldDef.make(name: "What didn't", kind: .longText),
                    FieldDef.make(name: "Action items", kind: .longText),
                ],
                primary: "goal", kanban: "status", calendar: "start"
            )
        ),

        Entry(
            id: "lib.standup",
            category: .productivity,
            blurb: "Daily standup notes — yesterday, today, blockers.",
            keywords: ["standup", "daily", "scrum", "sync"],
            template: makeType(
                id: "Standup", name: "Standup", plural: "Standups",
                image: "person.3", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Yesterday", kind: .longText),
                    FieldDef.make(name: "Today", kind: .longText),
                    FieldDef.make(name: "Blockers", kind: .longText),
                    selectField("Mood", [
                        ("🚀 Great", "#3FB950"), ("👍 Good", "#3FA9F5"),
                        ("😐 Okay", "#E8A93B"), ("😩 Rough", "#D14B5C"),
                    ]),
                ],
                primary: "date", kanban: "mood", calendar: "date"
            )
        ),

        Entry(
            id: "lib.time_entry",
            category: .productivity,
            blurb: "Time tracking — start/stop, project, billable, summary.",
            keywords: ["time", "tracking", "toggl", "billable", "hours"],
            template: makeType(
                id: "TimeEntry", name: "Time Entry", plural: "Time Tracking",
                image: "clock", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Start", kind: .dateTime, required: true),
                    FieldDef.make(name: "End", kind: .dateTime),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "Project", kind: .link),
                    FieldDef.make(name: "Billable?", kind: .boolean),
                    selectField("Activity", [
                        ("Deep work", "#9D4DCC"), ("Meeting", "#3FA9F5"),
                        ("Email", "#E8A93B"), ("Admin", "#666666"),
                        ("Learning", "#3FB950"), ("Break", "#F08C2E"),
                    ]),
                ],
                primary: "description", kanban: "activity", calendar: "start"
            )
        ),

        Entry(
            id: "lib.pomodoro",
            category: .productivity,
            blurb: "Pomodoro sessions — what you focused on for 25 minutes.",
            keywords: ["pomodoro", "focus", "deep work", "session"],
            template: makeType(
                id: "Pomodoro", name: "Session", plural: "Pomodoro Sessions",
                image: "timer", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Focus", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    selectField("Quality", [
                        ("Distracted", "#D14B5C"), ("Okay", "#E8A93B"),
                        ("Focused", "#3FA9F5"), ("Flow", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Interruptions", kind: .number),
                    FieldDef.make(name: "What I did", kind: .longText),
                ],
                primary: "focus", kanban: "quality", calendar: "date"
            )
        ),

        Entry(
            id: "lib.decision",
            category: .productivity,
            blurb: "Decisions made — context, options weighed, what you chose, why.",
            keywords: ["decision", "log", "ADR", "rationale"],
            template: makeType(
                id: "Decision", name: "Decision", plural: "Decision Log",
                image: "arrow.triangle.branch", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Reversibility", [
                        ("One-way door", "#D14B5C"), ("Two-way door", "#3FB950"),
                    ]),
                    selectField("Status", [
                        ("Pending", "#E8A93B"), ("Decided", "#3FB950"),
                        ("Revisited", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Context", kind: .richText),
                    FieldDef.make(name: "Options considered", kind: .longText),
                    FieldDef.make(name: "Decision", kind: .longText),
                    FieldDef.make(name: "Rationale", kind: .richText),
                    FieldDef.make(name: "Revisit by", kind: .date),
                ],
                primary: "title", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.idea",
            category: .productivity,
            blurb: "Idea capture — quick jot now, expand later.",
            keywords: ["idea", "brainstorm", "spark", "concept"],
            template: makeType(
                id: "Idea", name: "Idea", plural: "Ideas",
                image: "lightbulb", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Captured", kind: .dateTime),
                    selectField("Category", [
                        ("Product", "#3FA9F5"), ("Business", "#9D4DCC"),
                        ("Writing", "#E8A93B"), ("App", "#F08C2E"),
                        ("Life", "#3FB950"), ("Other", "#666666"),
                    ]),
                    selectField("Energy level", [
                        ("Spark", "#888888"), ("Worth exploring", "#3FA9F5"),
                        ("Pursuing", "#9D4DCC"), ("Acting on", "#3FB950"),
                        ("Killed", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "One-liner", kind: .text),
                    FieldDef.make(name: "Expansion", kind: .richText),
                ],
                primary: "title", kanban: "energy_level", calendar: "captured"
            )
        ),

        Entry(
            id: "lib.weekly_review",
            category: .productivity,
            blurb: "Weekly review — what worked, what didn't, next-week focus.",
            keywords: ["review", "weekly", "reflection", "retro"],
            template: makeType(
                id: "WeeklyReview", name: "Weekly Review", plural: "Weekly Reviews",
                image: "calendar.day.timeline.left", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Week of", kind: .date, required: true),
                    FieldDef.make(name: "Wins", kind: .richText),
                    FieldDef.make(name: "Misses", kind: .richText),
                    FieldDef.make(name: "Lessons", kind: .richText),
                    FieldDef.make(name: "Energy (1–5)", kind: .rating),
                    FieldDef.make(name: "Focus next week", kind: .longText),
                    FieldDef.make(name: "Gratitude", kind: .longText),
                ],
                primary: "week_of", calendar: "week_of"
            )
        ),

        Entry(
            id: "lib.brain_dump",
            category: .productivity,
            blurb: "Stream-of-consciousness brain dump — date and a free-form blob.",
            keywords: ["brain dump", "freewrite", "journal", "ideas"],
            template: makeType(
                id: "BrainDump", name: "Brain Dump", plural: "Brain Dumps",
                image: "brain.head.profile", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Tag", kind: .text),
                    FieldDef.make(name: "Content", kind: .richText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.process",
            category: .productivity,
            blurb: "Standard operating procedures — repeatable how-tos.",
            keywords: ["sop", "process", "procedure", "runbook", "checklist"],
            template: makeType(
                id: "Process", name: "Process", plural: "Processes",
                image: "list.bullet.indent", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "When to use", kind: .text),
                    FieldDef.make(name: "Frequency", kind: .text),
                    FieldDef.make(name: "Steps", kind: .richText),
                    FieldDef.make(name: "Last run", kind: .date),
                    FieldDef.make(name: "Owner", kind: .link),
                ],
                primary: "name"
            )
        ),

        Entry(
            id: "lib.waiting_on",
            category: .productivity,
            blurb: "Things you're waiting on someone else for — who, what, since.",
            keywords: ["waiting", "blocked", "followup", "owed"],
            template: makeType(
                id: "WaitingOn", name: "Waiting", plural: "Waiting On",
                image: "hourglass", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Person", kind: .link),
                    FieldDef.make(name: "Asked on", kind: .date),
                    FieldDef.make(name: "Follow up by", kind: .date),
                    selectField("Status", [
                        ("Waiting", "#E8A93B"), ("Reminded", "#3FA9F5"),
                        ("Received", "#3FB950"), ("Stale", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "status", calendar: "follow_up_by"
            )
        ),

        Entry(
            id: "lib.someday_maybe",
            category: .productivity,
            blurb: "Someday/maybe list — things you'd love to do, no commitment yet.",
            keywords: ["someday", "maybe", "wishlist", "future"],
            template: makeType(
                id: "SomedayMaybe", name: "Someday", plural: "Someday / Maybe",
                image: "calendar.badge.exclamationmark", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Idea", kind: .text, required: true),
                    selectField("Bucket", [
                        ("Trip", "#3FA9F5"), ("Project", "#9D4DCC"),
                        ("Skill", "#3FB950"), ("Experience", "#E8A93B"),
                        ("Purchase", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Why", kind: .longText),
                    FieldDef.make(name: "Pulled in?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "idea", kanban: "bucket"
            )
        ),

        Entry(
            id: "lib.energy_log",
            category: .productivity,
            blurb: "Energy throughout the day — when am I sharp, when foggy?",
            keywords: ["energy", "chronotype", "focus", "circadian"],
            template: makeType(
                id: "EnergyLog", name: "Reading", plural: "Energy Log",
                image: "battery.75percent", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Energy (1–10)", kind: .number),
                    FieldDef.make(name: "Focus (1–10)", kind: .number),
                    FieldDef.make(name: "Mood (1–10)", kind: .number),
                    selectField("Activity context", [
                        ("Deep work", "#9D4DCC"), ("Meeting", "#3FA9F5"),
                        ("Exercise", "#3FB950"), ("Eating", "#E8A93B"),
                        ("Resting", "#F08C2E"), ("Commute", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "when", kanban: "activity_context", calendar: "when"
            )
        ),

        Entry(
            id: "lib.checklist_template",
            category: .productivity,
            blurb: "Reusable checklist (packing list, pre-publish, etc.).",
            keywords: ["checklist", "template", "preflight"],
            template: makeType(
                id: "ChecklistTemplate", name: "Checklist", plural: "Checklist Templates",
                image: "list.clipboard", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Category", [
                        ("Travel", "#3FA9F5"), ("Work", "#9D4DCC"),
                        ("Home", "#3FB950"), ("Hobby", "#E8A93B"),
                        ("Emergency", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Items", kind: .richText),
                    FieldDef.make(name: "Last used", kind: .date),
                ],
                primary: "name", kanban: "category"
            )
        ),

        Entry(
            id: "lib.resolution",
            category: .productivity,
            blurb: "New year (or any time) resolution — measurable progress.",
            keywords: ["resolution", "new year", "yearly", "commitment"],
            template: makeType(
                id: "Resolution", name: "Resolution", plural: "Resolutions",
                image: "flag.checkered", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Resolution", kind: .text, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Why", kind: .longText),
                    FieldDef.make(name: "How I'll measure", kind: .longText),
                    selectField("Status", [
                        ("Set", "#3FA9F5"), ("On track", "#3FB950"),
                        ("Slipping", "#E8A93B"), ("Achieved", "#9D4DCC"),
                        ("Abandoned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Progress %", kind: .number),
                    FieldDef.make(name: "Year-end note", kind: .richText),
                ],
                primary: "resolution", kanban: "status"
            )
        ),

        // MARK: - Home & Life Admin (extended)

        Entry(
            id: "lib.pet",
            category: .home,
            blurb: "Pets — name, species, vet, medications, milestones.",
            keywords: ["pet", "dog", "cat", "animal", "companion"],
            template: makeType(
                id: "Pet", name: "Pet", plural: "Pets",
                image: "pawprint", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Species", [
                        ("Dog", "#7B4F2F"), ("Cat", "#888888"),
                        ("Bird", "#3FA9F5"), ("Fish", "#3FB950"),
                        ("Reptile", "#9D4DCC"), ("Small mammal", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Breed", kind: .text),
                    FieldDef.make(name: "Birthday", kind: .date),
                    FieldDef.make(name: "Adoption date", kind: .date),
                    FieldDef.make(name: "Weight (lb)", kind: .number),
                    FieldDef.make(name: "Vet", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "name", kanban: "species", calendar: "birthday", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.vet_visit",
            category: .home,
            blurb: "Vet visits — date, reason, diagnosis, follow-up.",
            keywords: ["vet", "pet", "checkup", "vaccination"],
            template: makeType(
                id: "VetVisit", name: "Vet Visit", plural: "Vet Visits",
                image: "stethoscope.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Reason", [
                        ("Annual exam", "#3FA9F5"), ("Vaccination", "#3FB950"),
                        ("Sick visit", "#E8A93B"), ("Dental", "#9D4DCC"),
                        ("Emergency", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Vet", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Diagnosis", kind: .longText),
                    FieldDef.make(name: "Follow up", kind: .date),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "reason", kanban: "reason", calendar: "date"
            )
        ),

        Entry(
            id: "lib.contact_address",
            category: .home,
            blurb: "Friends' & family's addresses for cards, gifts, visits.",
            keywords: ["address", "contact", "mailing", "card"],
            template: makeType(
                id: "ContactAddress", name: "Address", plural: "Addresses",
                image: "envelope.open", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Street", kind: .text),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "State / region", kind: .text),
                    FieldDef.make(name: "Postal code", kind: .text),
                    FieldDef.make(name: "Country", kind: .text),
                    selectField("Type", [
                        ("Home", "#3FA9F5"), ("Work", "#9D4DCC"),
                        ("Vacation", "#3FB950"), ("Family", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "person", kanban: "type"
            )
        ),

        Entry(
            id: "lib.insurance_policy",
            category: .home,
            blurb: "Insurance policies — auto, home, life, health, with renewal dates.",
            keywords: ["insurance", "policy", "premium", "renewal", "claim"],
            template: makeType(
                id: "InsurancePolicy", name: "Policy", plural: "Insurance Policies",
                image: "shield.lefthalf.filled", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Policy name", kind: .text, required: true),
                    selectField("Type", [
                        ("Auto", "#3FA9F5"), ("Home", "#9D4DCC"),
                        ("Life", "#E8A93B"), ("Health", "#3FB950"),
                        ("Renters", "#F08C2E"), ("Travel", "#666666"),
                        ("Pet", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Carrier", kind: .text),
                    FieldDef.make(name: "Policy #", kind: .text),
                    FieldDef.make(name: "Premium / mo", kind: .number),
                    FieldDef.make(name: "Deductible", kind: .number),
                    FieldDef.make(name: "Effective", kind: .date),
                    FieldDef.make(name: "Renews", kind: .date),
                    FieldDef.make(name: "Agent contact", kind: .link),
                    FieldDef.make(name: "Policy document", kind: .attachment),
                ],
                primary: "policy_name", kanban: "type", calendar: "renews"
            )
        ),

        Entry(
            id: "lib.important_document",
            category: .home,
            blurb: "Track where your passport, birth certificate, deed live.",
            keywords: ["document", "passport", "vital", "records", "deed"],
            template: makeType(
                id: "ImportantDocument", name: "Document", plural: "Important Documents",
                image: "doc.badge.gearshape", color: "#666666",
                fields: [
                    FieldDef.make(name: "Document", kind: .text, required: true),
                    selectField("Type", [
                        ("ID / passport", "#3FA9F5"), ("Vital record", "#9D4DCC"),
                        ("Property", "#E8A93B"), ("Legal", "#D14B5C"),
                        ("Financial", "#3FB950"), ("Medical", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Issued by", kind: .text),
                    FieldDef.make(name: "Issue date", kind: .date),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Where it lives", kind: .text),
                    FieldDef.make(name: "Scan", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "document", kanban: "type", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.emergency_contact",
            category: .home,
            blurb: "Who to call in an emergency — relationship, phone, role.",
            keywords: ["emergency", "contact", "ICE", "next of kin"],
            template: makeType(
                id: "EmergencyContact", name: "Contact", plural: "Emergency Contacts",
                image: "phone.badge.plus", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Role", [
                        ("Spouse / partner", "#9D4DCC"), ("Parent", "#3FA9F5"),
                        ("Sibling", "#3FB950"), ("Child", "#E8A93B"),
                        ("Friend", "#F08C2E"), ("Doctor", "#D14B5C"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Phone", kind: .text),
                    FieldDef.make(name: "Email", kind: .email),
                    FieldDef.make(name: "Lives in", kind: .text),
                    FieldDef.make(name: "Notes (allergies, instructions)", kind: .longText),
                ],
                primary: "name", kanban: "role"
            )
        ),

        Entry(
            id: "lib.wardrobe",
            category: .home,
            blurb: "Wardrobe inventory — what you own, what fits, what's worn out.",
            keywords: ["clothing", "wardrobe", "outfit", "closet"],
            template: makeType(
                id: "WardrobeItem", name: "Garment", plural: "Wardrobe",
                image: "tshirt", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    selectField("Category", [
                        ("Top", "#3FA9F5"), ("Bottom", "#9D4DCC"),
                        ("Outerwear", "#E8A93B"), ("Shoes", "#F08C2E"),
                        ("Accessory", "#3FB950"), ("Underwear", "#666666"),
                    ]),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Color", kind: .text),
                    FieldDef.make(name: "Size", kind: .text),
                    FieldDef.make(name: "Bought", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                    selectField("Status", [
                        ("Wearing", "#3FB950"), ("Stored", "#3FA9F5"),
                        ("Donate", "#E8A93B"), ("Repair", "#F08C2E"),
                        ("Retired", "#666666"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "item", kanban: "category", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.storage_box",
            category: .home,
            blurb: "What's in that bin in the garage? Number, location, contents.",
            keywords: ["storage", "bin", "box", "inventory", "garage", "attic"],
            template: makeType(
                id: "StorageBox", name: "Box", plural: "Storage Boxes",
                image: "shippingbox", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Box label", kind: .text, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Contents", kind: .richText),
                    FieldDef.make(name: "Date stored", kind: .date),
                    selectField("Status", [
                        ("Stored", "#3FA9F5"), ("Needs sort", "#E8A93B"),
                        ("Ready to donate", "#9D4DCC"), ("Trash", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo of contents", kind: .attachment),
                ],
                primary: "box_label", kanban: "status", gallery: "photo_of_contents"
            )
        ),

        Entry(
            id: "lib.grocery_item",
            category: .home,
            blurb: "Smart grocery list — recurring vs one-off, store, last bought.",
            keywords: ["grocery", "shopping", "list", "pantry"],
            template: makeType(
                id: "GroceryItem", name: "Item", plural: "Grocery List",
                image: "cart", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    selectField("Aisle", [
                        ("Produce", "#3FB950"), ("Dairy", "#E8A93B"),
                        ("Meat", "#D14B5C"), ("Bakery", "#F08C2E"),
                        ("Pantry", "#9D4DCC"), ("Frozen", "#3FA9F5"),
                        ("Household", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Need", "#E8A93B"), ("In cart", "#3FA9F5"),
                        ("Bought", "#3FB950"), ("Skipped", "#888888"),
                    ]),
                    FieldDef.make(name: "Recurring?", kind: .boolean),
                    FieldDef.make(name: "Brand preference", kind: .text),
                    FieldDef.make(name: "Last bought", kind: .date),
                ],
                primary: "item", kanban: "status"
            )
        ),

        Entry(
            id: "lib.wishlist",
            category: .home,
            blurb: "Things you'd love to own someday — link, price, priority.",
            keywords: ["wishlist", "wantlist", "shopping", "future"],
            template: makeType(
                id: "WishlistItem", name: "Wish", plural: "Wishlist",
                image: "star.bubble", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    selectField("Category", [
                        ("Gear", "#3FA9F5"), ("Clothes", "#9D4DCC"),
                        ("Books", "#E8A93B"), ("Tech", "#F08C2E"),
                        ("Home", "#3FB950"), ("Experience", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Price", kind: .number),
                    FieldDef.make(name: "Link", kind: .url),
                    selectField("Priority", [
                        ("Idle want", "#888888"), ("Someday", "#3FA9F5"),
                        ("Saving up", "#E8A93B"), ("Pulling the trigger", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Why", kind: .longText),
                ],
                primary: "item", kanban: "priority"
            )
        ),

        Entry(
            id: "lib.online_account",
            category: .home,
            blurb: "Online accounts you have — service, URL, 2FA method, never passwords.",
            keywords: ["account", "online", "service", "login", "2fa"],
            template: makeType(
                id: "OnlineAccount", name: "Account", plural: "Online Accounts",
                image: "person.badge.key", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Service", kind: .text, required: true),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Username", kind: .text),
                    FieldDef.make(name: "Email used", kind: .email),
                    selectField("2FA method", [
                        ("None", "#D14B5C"), ("SMS", "#E8A93B"),
                        ("App (TOTP)", "#3FB950"), ("Security key", "#9D4DCC"),
                        ("Passkey", "#3FA9F5"),
                    ]),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Paused", "#E8A93B"),
                        ("Closing", "#F08C2E"), ("Closed", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes (recovery, etc.)", kind: .longText),
                ],
                primary: "service", kanban: "status"
            )
        ),

        Entry(
            id: "lib.home_project",
            category: .home,
            blurb: "Home improvement projects — paint a room, retile, build a deck.",
            keywords: ["renovation", "diy", "home improvement", "remodel"],
            template: makeType(
                id: "HomeProject", name: "Project", plural: "Home Projects",
                image: "house.lodge", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Project", kind: .text, required: true),
                    selectField("Room / area", [
                        ("Kitchen", "#E8A93B"), ("Bathroom", "#3FA9F5"),
                        ("Bedroom", "#9D4DCC"), ("Living room", "#3FB950"),
                        ("Garage", "#666666"), ("Outdoor", "#F08C2E"),
                        ("Whole house", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Researching", "#3FA9F5"),
                        ("Budgeted", "#9D4DCC"), ("In progress", "#E8A93B"),
                        ("Done", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Estimated cost", kind: .number),
                    FieldDef.make(name: "Actual cost", kind: .number),
                    FieldDef.make(name: "Contractor", kind: .link),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Finished", kind: .date),
                    FieldDef.make(name: "Before photo", kind: .attachment),
                    FieldDef.make(name: "After photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "project", kanban: "status", calendar: "finished", gallery: "after_photo"
            )
        ),

        Entry(
            id: "lib.cleaning_supply",
            category: .home,
            blurb: "Cleaning supply inventory — what's running low.",
            keywords: ["cleaning", "supply", "inventory", "paper goods"],
            template: makeType(
                id: "CleaningSupply", name: "Supply", plural: "Cleaning Supplies",
                image: "spray.bottle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    selectField("Category", [
                        ("Surface cleaner", "#3FA9F5"), ("Dish", "#9D4DCC"),
                        ("Laundry", "#E8A93B"), ("Paper", "#3FB950"),
                        ("Tool", "#666666"), ("Other", "#F08C2E"),
                    ]),
                    selectField("Stock", [
                        ("Full", "#3FB950"), ("Half", "#E8A93B"),
                        ("Low", "#F08C2E"), ("Out", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Preferred brand", kind: .text),
                    FieldDef.make(name: "Last bought", kind: .date),
                ],
                primary: "item", kanban: "stock"
            )
        ),

        Entry(
            id: "lib.utility_account",
            category: .home,
            blurb: "Electricity, water, gas, internet — account numbers, autopay.",
            keywords: ["utility", "electricity", "water", "gas", "internet"],
            template: makeType(
                id: "UtilityAccount", name: "Utility", plural: "Utilities",
                image: "bolt.square", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Provider", kind: .text, required: true),
                    selectField("Type", [
                        ("Electricity", "#E8A93B"), ("Water / sewer", "#3FA9F5"),
                        ("Gas", "#F08C2E"), ("Internet", "#9D4DCC"),
                        ("Trash", "#666666"), ("Phone", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Account #", kind: .text),
                    FieldDef.make(name: "Monthly avg", kind: .number),
                    FieldDef.make(name: "Autopay?", kind: .boolean),
                    FieldDef.make(name: "Due day of month", kind: .number),
                    FieldDef.make(name: "Login", kind: .url),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "provider", kanban: "type"
            )
        ),

        // MARK: - Money & Finance (extended)

        Entry(
            id: "lib.income",
            category: .finance,
            blurb: "Income entries — paychecks, side hustle, dividends.",
            keywords: ["income", "paycheck", "earnings", "salary", "revenue"],
            template: makeType(
                id: "Income", name: "Income", plural: "Income",
                image: "arrow.down.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    selectField("Source type", [
                        ("Salary", "#3FA9F5"), ("Bonus", "#9D4DCC"),
                        ("Side hustle", "#E8A93B"), ("Dividend", "#3FB950"),
                        ("Interest", "#F08C2E"), ("Refund", "#666666"),
                        ("Gift", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Account", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "source", kanban: "source_type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.bill",
            category: .finance,
            blurb: "Recurring bills — due day, amount, autopay status.",
            keywords: ["bill", "recurring", "monthly", "autopay"],
            template: makeType(
                id: "Bill", name: "Bill", plural: "Bills",
                image: "dollarsign.square", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Amount", kind: .number),
                    selectField("Frequency", [
                        ("Monthly", "#3FA9F5"), ("Quarterly", "#9D4DCC"),
                        ("Annual", "#E8A93B"), ("As-needed", "#666666"),
                    ]),
                    FieldDef.make(name: "Due day", kind: .number),
                    FieldDef.make(name: "Autopay?", kind: .boolean),
                    FieldDef.make(name: "Next due", kind: .date),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("On hold", "#E8A93B"),
                        ("Cancelled", "#666666"),
                    ]),
                ],
                primary: "name", kanban: "status", calendar: "next_due"
            )
        ),

        Entry(
            id: "lib.tax_doc",
            category: .finance,
            blurb: "Tax documents — W-2, 1099, receipts, year filed.",
            keywords: ["tax", "w-2", "1099", "filing", "deduction"],
            template: makeType(
                id: "TaxDocument", name: "Tax Document", plural: "Tax Documents",
                image: "doc.text.below.ecg", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Year", kind: .number, required: true),
                    selectField("Type", [
                        ("W-2", "#3FA9F5"), ("1099", "#9D4DCC"),
                        ("Receipt", "#E8A93B"), ("Donation receipt", "#3FB950"),
                        ("Return copy", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Description", kind: .text),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Issuer", kind: .text),
                    FieldDef.make(name: "Document", kind: .attachment),
                    FieldDef.make(name: "Filed?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "description", kanban: "type"
            )
        ),

        Entry(
            id: "lib.bank_account",
            category: .finance,
            blurb: "Bank & brokerage accounts you have — institution, type, balance snapshot.",
            keywords: ["bank", "account", "checking", "savings", "brokerage"],
            template: makeType(
                id: "BankAccount", name: "Account", plural: "Accounts",
                image: "building.columns", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Institution", kind: .text),
                    selectField("Type", [
                        ("Checking", "#3FA9F5"), ("Savings", "#3FB950"),
                        ("HYSA", "#9D4DCC"), ("CD", "#E8A93B"),
                        ("Brokerage", "#F08C2E"), ("Retirement", "#D14B5C"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Last 4 of account", kind: .text),
                    FieldDef.make(name: "Recent balance", kind: .number),
                    FieldDef.make(name: "Balance as of", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "nickname", kanban: "type"
            )
        ),

        Entry(
            id: "lib.credit_card",
            category: .finance,
            blurb: "Credit cards — limit, statement date, rewards rate.",
            keywords: ["credit", "card", "rewards", "limit", "apr"],
            template: makeType(
                id: "CreditCard", name: "Card", plural: "Credit Cards",
                image: "creditcard.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Card", kind: .text, required: true),
                    FieldDef.make(name: "Issuer", kind: .text),
                    FieldDef.make(name: "Last 4", kind: .text),
                    FieldDef.make(name: "Limit", kind: .number),
                    FieldDef.make(name: "APR %", kind: .number),
                    FieldDef.make(name: "Statement day", kind: .number),
                    FieldDef.make(name: "Due day", kind: .number),
                    selectField("Rewards", [
                        ("Cash back", "#3FB950"), ("Points", "#9D4DCC"),
                        ("Miles", "#3FA9F5"), ("None", "#666666"),
                    ]),
                    FieldDef.make(name: "Annual fee", kind: .number),
                ],
                primary: "card", kanban: "rewards"
            )
        ),

        Entry(
            id: "lib.loan",
            category: .finance,
            blurb: "Loans — mortgage, car, student — balance, rate, payoff date.",
            keywords: ["loan", "mortgage", "car loan", "student loan", "debt"],
            template: makeType(
                id: "Loan", name: "Loan", plural: "Loans",
                image: "banknote", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Loan name", kind: .text, required: true),
                    selectField("Type", [
                        ("Mortgage", "#3FA9F5"), ("Auto", "#9D4DCC"),
                        ("Student", "#E8A93B"), ("Personal", "#F08C2E"),
                        ("HELOC", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Lender", kind: .text),
                    FieldDef.make(name: "Original amount", kind: .number),
                    FieldDef.make(name: "Current balance", kind: .number),
                    FieldDef.make(name: "Rate %", kind: .number),
                    FieldDef.make(name: "Monthly payment", kind: .number),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Payoff target", kind: .date),
                ],
                primary: "loan_name", kanban: "type", calendar: "payoff_target"
            )
        ),

        Entry(
            id: "lib.net_worth_snapshot",
            category: .finance,
            blurb: "Monthly net worth snapshot — assets, liabilities, delta.",
            keywords: ["net worth", "balance sheet", "assets", "liabilities"],
            template: makeType(
                id: "NetWorthSnapshot", name: "Snapshot", plural: "Net Worth",
                image: "chart.bar.xaxis", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "As of", kind: .date, required: true),
                    FieldDef.make(name: "Assets total", kind: .number),
                    FieldDef.make(name: "Liabilities total", kind: .number),
                    FieldDef.make(name: "Net worth", kind: .number),
                    FieldDef.make(name: "Change vs last month", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "as_of", calendar: "as_of"
            )
        ),

        Entry(
            id: "lib.donation",
            category: .finance,
            blurb: "Charitable donations — recipient, amount, tax-deductible flag.",
            keywords: ["donation", "charity", "giving", "tithe", "nonprofit"],
            template: makeType(
                id: "Donation", name: "Donation", plural: "Donations",
                image: "heart.text.square", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Recipient", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount", kind: .number),
                    selectField("Cause", [
                        ("Animal welfare", "#3FB950"), ("Education", "#9D4DCC"),
                        ("Health", "#3FA9F5"), ("Hunger", "#E8A93B"),
                        ("Religion", "#F08C2E"), ("Arts", "#D14B5C"),
                        ("Environmental", "#666666"),
                    ]),
                    FieldDef.make(name: "Tax deductible?", kind: .boolean),
                    FieldDef.make(name: "Receipt", kind: .attachment),
                ],
                primary: "recipient", kanban: "cause", calendar: "date"
            )
        ),

        Entry(
            id: "lib.reimbursement",
            category: .finance,
            blurb: "Work / travel expenses awaiting reimbursement — amount, status.",
            keywords: ["reimbursement", "expense report", "work travel"],
            template: makeType(
                id: "Reimbursement", name: "Reimbursement", plural: "Reimbursements",
                image: "arrow.uturn.left.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    FieldDef.make(name: "Date spent", kind: .date),
                    FieldDef.make(name: "Submitted", kind: .date),
                    selectField("Status", [
                        ("Pending", "#E8A93B"), ("Submitted", "#3FA9F5"),
                        ("Approved", "#9D4DCC"), ("Paid", "#3FB950"),
                        ("Rejected", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Receipt", kind: .attachment),
                ],
                primary: "description", kanban: "status", calendar: "submitted"
            )
        ),

        Entry(
            id: "lib.crypto_holding",
            category: .finance,
            blurb: "Crypto holdings — coin, exchange/wallet, cost basis.",
            keywords: ["crypto", "bitcoin", "ethereum", "wallet", "exchange"],
            template: makeType(
                id: "CryptoHolding", name: "Holding", plural: "Crypto",
                image: "bitcoinsign.circle", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Symbol", kind: .text, required: true),
                    FieldDef.make(name: "Quantity", kind: .number),
                    FieldDef.make(name: "Cost basis (USD)", kind: .number),
                    FieldDef.make(name: "Current price", kind: .number),
                    FieldDef.make(name: "Wallet / exchange", kind: .text),
                    selectField("Storage", [
                        ("Hot wallet", "#E8A93B"), ("Cold wallet", "#3FA9F5"),
                        ("Exchange", "#9D4DCC"), ("Hardware", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "symbol", kanban: "storage"
            )
        ),

        Entry(
            id: "lib.real_estate_property",
            category: .finance,
            blurb: "Real estate holdings — address, purchase, mortgage, valuation.",
            keywords: ["real estate", "property", "house", "rental", "mortgage"],
            template: makeType(
                id: "RealEstate", name: "Property", plural: "Properties",
                image: "house.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Address", kind: .text),
                    selectField("Use", [
                        ("Primary", "#3FB950"), ("Vacation", "#9D4DCC"),
                        ("Rental", "#E8A93B"), ("Land", "#666666"),
                    ]),
                    FieldDef.make(name: "Bought", kind: .date),
                    FieldDef.make(name: "Purchase price", kind: .number),
                    FieldDef.make(name: "Current valuation", kind: .number),
                    FieldDef.make(name: "Mortgage balance", kind: .number),
                    FieldDef.make(name: "Property tax / year", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "nickname", kanban: "use", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.savings_goal",
            category: .finance,
            blurb: "Savings goal — target amount, deadline, progress, why.",
            keywords: ["savings", "goal", "target", "fund"],
            template: makeType(
                id: "SavingsGoal", name: "Goal", plural: "Savings Goals",
                image: "piggybank", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Goal", kind: .text, required: true),
                    FieldDef.make(name: "Target amount", kind: .number),
                    FieldDef.make(name: "Saved", kind: .number),
                    FieldDef.make(name: "Target date", kind: .date),
                    selectField("Status", [
                        ("Building", "#3FA9F5"), ("On track", "#3FB950"),
                        ("Behind", "#E8A93B"), ("Achieved", "#9D4DCC"),
                        ("Paused", "#666666"),
                    ]),
                    FieldDef.make(name: "Why", kind: .longText),
                ],
                primary: "goal", kanban: "status", calendar: "target_date"
            )
        ),

        Entry(
            id: "lib.budget_category",
            category: .finance,
            blurb: "Monthly budget by category — planned vs actual.",
            keywords: ["budget", "category", "envelope", "ynab"],
            template: makeType(
                id: "BudgetCategory", name: "Budget", plural: "Budget Categories",
                image: "chart.pie", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Category", kind: .text, required: true),
                    FieldDef.make(name: "Month", kind: .date),
                    FieldDef.make(name: "Planned", kind: .number),
                    FieldDef.make(name: "Actual", kind: .number),
                    FieldDef.make(name: "Rollover?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "category", calendar: "month"
            )
        ),

        Entry(
            id: "lib.retirement_contribution",
            category: .finance,
            blurb: "Retirement contributions — 401k, IRA, by year.",
            keywords: ["retirement", "401k", "ira", "roth", "contribution"],
            template: makeType(
                id: "RetirementContribution", name: "Contribution", plural: "Retirement Contributions",
                image: "calendar.badge.checkmark", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Account", kind: .text, required: true),
                    selectField("Plan", [
                        ("401(k)", "#3FA9F5"), ("Roth 401(k)", "#9D4DCC"),
                        ("Traditional IRA", "#E8A93B"), ("Roth IRA", "#3FB950"),
                        ("SEP", "#F08C2E"), ("HSA", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Tax year", kind: .number),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Employer match", kind: .number),
                ],
                primary: "account", kanban: "plan", calendar: "date"
            )
        ),

        Entry(
            id: "lib.financial_goal",
            category: .finance,
            blurb: "Big-picture financial milestones — emergency fund, house down payment, FI.",
            keywords: ["financial goal", "fire", "milestone", "savings"],
            template: makeType(
                id: "FinancialGoal", name: "Milestone", plural: "Financial Goals",
                image: "target", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Milestone", kind: .text, required: true),
                    FieldDef.make(name: "Target net worth or amount", kind: .number),
                    FieldDef.make(name: "Target date", kind: .date),
                    selectField("Status", [
                        ("Planning", "#888888"), ("Pursuing", "#3FA9F5"),
                        ("On track", "#3FB950"), ("Behind", "#E8A93B"),
                        ("Achieved", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Why", kind: .longText),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "milestone", kanban: "status", calendar: "target_date"
            )
        ),

        // MARK: - Health & Wellness (extended)

        Entry(
            id: "lib.sleep_log",
            category: .health,
            blurb: "Sleep log — bedtime, wake, duration, quality.",
            keywords: ["sleep", "rest", "insomnia", "rem", "tracker"],
            template: makeType(
                id: "SleepLog", name: "Night", plural: "Sleep Log",
                image: "bed.double", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Bedtime", kind: .dateTime),
                    FieldDef.make(name: "Wake time", kind: .dateTime),
                    FieldDef.make(name: "Duration (hr)", kind: .number),
                    selectField("Quality", [
                        ("Restless", "#D14B5C"), ("Okay", "#E8A93B"),
                        ("Good", "#3FA9F5"), ("Great", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Wakeups", kind: .number),
                    FieldDef.make(name: "Dream notes", kind: .longText),
                ],
                primary: "date", kanban: "quality", calendar: "date"
            )
        ),

        Entry(
            id: "lib.mood",
            category: .health,
            blurb: "Mood check-in — overall vibe + factors that contributed.",
            keywords: ["mood", "emotion", "feelings", "checkin"],
            template: makeType(
                id: "MoodEntry", name: "Mood", plural: "Mood Log",
                image: "face.smiling", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    selectField("Mood", [
                        ("😊 Great", "#3FB950"), ("🙂 Good", "#3FA9F5"),
                        ("😐 Meh", "#E8A93B"), ("😟 Low", "#F08C2E"),
                        ("😢 Bad", "#D14B5C"), ("😤 Frustrated", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Energy (1–10)", kind: .number),
                    FieldDef.make(name: "Anxiety (1–10)", kind: .number),
                    FieldDef.make(name: "What helped / hurt", kind: .richText),
                ],
                primary: "when", kanban: "mood", calendar: "when"
            )
        ),

        Entry(
            id: "lib.blood_pressure",
            category: .health,
            blurb: "Blood pressure readings — systolic, diastolic, pulse.",
            keywords: ["blood pressure", "bp", "systolic", "hypertension"],
            template: makeType(
                id: "BloodPressure", name: "Reading", plural: "Blood Pressure",
                image: "heart.circle", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Systolic", kind: .number, required: true),
                    FieldDef.make(name: "Diastolic", kind: .number, required: true),
                    FieldDef.make(name: "Pulse", kind: .number),
                    selectField("Time of day", [
                        ("Morning", "#E8A93B"), ("Midday", "#3FA9F5"),
                        ("Evening", "#9D4DCC"), ("Night", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "when", kanban: "time_of_day", calendar: "when"
            )
        ),

        Entry(
            id: "lib.hydration",
            category: .health,
            blurb: "Hydration log — water + other beverages by the day.",
            keywords: ["water", "hydration", "drink", "fluid"],
            template: makeType(
                id: "Hydration", name: "Day", plural: "Hydration",
                image: "drop", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Water (oz)", kind: .number),
                    FieldDef.make(name: "Coffee (oz)", kind: .number),
                    FieldDef.make(name: "Tea (oz)", kind: .number),
                    FieldDef.make(name: "Alcohol (drinks)", kind: .number),
                    FieldDef.make(name: "Other", kind: .text),
                    FieldDef.make(name: "Met goal?", kind: .boolean),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.meal_log",
            category: .health,
            blurb: "What you ate, when, calories, how it felt.",
            keywords: ["meal", "food log", "calorie", "nutrition", "eaten"],
            template: makeType(
                id: "MealLog", name: "Meal", plural: "Meal Log",
                image: "fork.knife.circle.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    selectField("Meal", [
                        ("Breakfast", "#E8A93B"), ("Lunch", "#3FA9F5"),
                        ("Dinner", "#9D4DCC"), ("Snack", "#3FB950"),
                    ]),
                    FieldDef.make(name: "What I ate", kind: .longText),
                    FieldDef.make(name: "Calories", kind: .number),
                    FieldDef.make(name: "Protein (g)", kind: .number),
                    selectField("How I felt", [
                        ("Energized", "#3FB950"), ("Satisfied", "#3FA9F5"),
                        ("Bloated", "#E8A93B"), ("Sluggish", "#F08C2E"),
                        ("Hungry still", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "what_i_ate", kanban: "meal", calendar: "when", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.allergy",
            category: .health,
            blurb: "Allergies — substance, severity, what to do.",
            keywords: ["allergy", "allergen", "reaction", "epipen"],
            template: makeType(
                id: "Allergy", name: "Allergy", plural: "Allergies",
                image: "exclamationmark.triangle", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Allergen", kind: .text, required: true),
                    selectField("Type", [
                        ("Food", "#E8A93B"), ("Medication", "#D14B5C"),
                        ("Environmental", "#3FB950"), ("Insect", "#F08C2E"),
                        ("Latex", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    selectField("Severity", [
                        ("Mild", "#3FA9F5"), ("Moderate", "#E8A93B"),
                        ("Severe", "#F08C2E"), ("Anaphylactic", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Reaction", kind: .longText),
                    FieldDef.make(name: "Treatment", kind: .longText),
                    FieldDef.make(name: "Identified on", kind: .date),
                ],
                primary: "allergen", kanban: "severity"
            )
        ),

        Entry(
            id: "lib.vaccination",
            category: .health,
            blurb: "Vaccination record — name, date, lot, next dose.",
            keywords: ["vaccine", "vaccination", "shot", "immunization"],
            template: makeType(
                id: "Vaccination", name: "Vaccination", plural: "Vaccinations",
                image: "syringe", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Vaccine", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Provider", kind: .text),
                    FieldDef.make(name: "Lot #", kind: .text),
                    FieldDef.make(name: "Next dose due", kind: .date),
                    FieldDef.make(name: "Card photo", kind: .attachment),
                    FieldDef.make(name: "Reaction notes", kind: .longText),
                ],
                primary: "vaccine", calendar: "next_dose_due", gallery: "card_photo"
            )
        ),

        Entry(
            id: "lib.lab_result",
            category: .health,
            blurb: "Lab results — test, value, units, ref range, flag.",
            keywords: ["lab", "blood test", "panel", "cholesterol"],
            template: makeType(
                id: "LabResult", name: "Result", plural: "Lab Results",
                image: "testtube.2", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Test", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Value", kind: .text),
                    FieldDef.make(name: "Units", kind: .text),
                    FieldDef.make(name: "Reference range", kind: .text),
                    selectField("Flag", [
                        ("Normal", "#3FB950"), ("Borderline", "#E8A93B"),
                        ("High", "#F08C2E"), ("Low", "#3FA9F5"),
                        ("Critical", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Ordering doctor", kind: .link),
                    FieldDef.make(name: "Report PDF", kind: .attachment),
                ],
                primary: "test", kanban: "flag", calendar: "date"
            )
        ),

        Entry(
            id: "lib.therapy_session",
            category: .health,
            blurb: "Therapy session log — themes, homework, follow-ups.",
            keywords: ["therapy", "counseling", "session", "psychotherapy"],
            template: makeType(
                id: "TherapySession", name: "Session", plural: "Therapy Sessions",
                image: "person.line.dotted.person", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Therapist", kind: .link),
                    FieldDef.make(name: "Themes", kind: .text),
                    FieldDef.make(name: "Notes", kind: .richText),
                    FieldDef.make(name: "Homework", kind: .longText),
                    FieldDef.make(name: "Next session", kind: .date),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.injury",
            category: .health,
            blurb: "Injuries and recovery — date, body part, treatment, status.",
            keywords: ["injury", "sprain", "strain", "broken", "recovery", "PT"],
            template: makeType(
                id: "Injury", name: "Injury", plural: "Injuries",
                image: "bandage", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Body part", [
                        ("Head/neck", "#9D4DCC"), ("Shoulder", "#3FA9F5"),
                        ("Back", "#E8A93B"), ("Hip", "#F08C2E"),
                        ("Knee", "#3FB950"), ("Ankle/foot", "#D14B5C"),
                        ("Hand/wrist", "#666666"), ("Other", "#888888"),
                    ]),
                    selectField("Severity", [
                        ("Minor", "#3FB950"), ("Moderate", "#E8A93B"),
                        ("Severe", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Acute", "#D14B5C"), ("Recovering", "#E8A93B"),
                        ("Maintenance", "#3FA9F5"), ("Healed", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Treatment", kind: .richText),
                    FieldDef.make(name: "Recovery notes", kind: .noteLog),
                ],
                primary: "description", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.menstrual_cycle",
            category: .health,
            blurb: "Cycle tracker — start, flow, symptoms, mood.",
            keywords: ["period", "menstrual", "cycle", "pms"],
            template: makeType(
                id: "Cycle", name: "Day", plural: "Cycle Log",
                image: "circle.dotted", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Flow", [
                        ("None", "#888888"), ("Spotting", "#E8A93B"),
                        ("Light", "#3FA9F5"), ("Medium", "#9D4DCC"),
                        ("Heavy", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Cramps (1–5)", kind: .rating),
                    FieldDef.make(name: "Symptoms", kind: .text, description: "headache, bloating, etc."),
                    FieldDef.make(name: "Mood", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", kanban: "flow", calendar: "date"
            )
        ),

        Entry(
            id: "lib.dental_visit",
            category: .health,
            blurb: "Dentist visits — cleaning, work done, next appointment.",
            keywords: ["dental", "dentist", "cleaning", "cavity", "filling"],
            template: makeType(
                id: "DentalVisit", name: "Visit", plural: "Dental Visits",
                image: "mouth", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Type", [
                        ("Cleaning", "#3FB950"), ("Exam", "#3FA9F5"),
                        ("Filling", "#E8A93B"), ("Crown", "#9D4DCC"),
                        ("Extraction", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Dentist", kind: .link),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Work done", kind: .longText),
                    FieldDef.make(name: "Next visit", kind: .date),
                ],
                primary: "type", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vision_prescription",
            category: .health,
            blurb: "Vision prescriptions — sphere/cyl/axis per eye, change over time.",
            keywords: ["vision", "glasses", "contact lens", "prescription", "eye"],
            template: makeType(
                id: "VisionRx", name: "Prescription", plural: "Vision Prescriptions",
                image: "eyeglasses", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "OD sphere", kind: .number),
                    FieldDef.make(name: "OD cylinder", kind: .number),
                    FieldDef.make(name: "OD axis", kind: .number),
                    FieldDef.make(name: "OS sphere", kind: .number),
                    FieldDef.make(name: "OS cylinder", kind: .number),
                    FieldDef.make(name: "OS axis", kind: .number),
                    FieldDef.make(name: "Pupillary distance", kind: .number),
                    FieldDef.make(name: "Doctor", kind: .link),
                    FieldDef.make(name: "Rx photo", kind: .attachment),
                ],
                primary: "date", calendar: "date"
            )
        ),

        // MARK: - Food & Drink (extended)

        Entry(
            id: "lib.beer",
            category: .food,
            blurb: "Craft beers tried — style, ABV, brewery, rating.",
            keywords: ["beer", "craft", "ipa", "stout", "brewery"],
            template: makeType(
                id: "Beer", name: "Beer", plural: "Beer Log",
                image: "mug", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Brewery", kind: .text),
                    selectField("Style", [
                        ("IPA", "#E8A93B"), ("Lager", "#F0E68C"),
                        ("Stout / Porter", "#3D2B1F"), ("Sour", "#D14B5C"),
                        ("Wheat", "#F08C2E"), ("Saison", "#9D4DCC"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "ABV %", kind: .number),
                    FieldDef.make(name: "IBU", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Date tried", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "name", kanban: "style", calendar: "date_tried", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.whiskey",
            category: .food,
            blurb: "Whiskey tasted — type, age, proof, mash, notes.",
            keywords: ["whiskey", "bourbon", "scotch", "rye", "spirits"],
            template: makeType(
                id: "Whiskey", name: "Whiskey", plural: "Whiskey",
                image: "drop.triangle", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Distillery", kind: .text),
                    selectField("Type", [
                        ("Bourbon", "#F08C2E"), ("Rye", "#9D4DCC"),
                        ("Scotch single malt", "#E8A93B"), ("Scotch blend", "#7B4F2F"),
                        ("Irish", "#3FB950"), ("Japanese", "#D14B5C"),
                        ("Canadian", "#3FA9F5"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Age", kind: .number),
                    FieldDef.make(name: "Proof", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Date tasted", kind: .date),
                    FieldDef.make(name: "Tasting notes", kind: .richText),
                    FieldDef.make(name: "Label photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", calendar: "date_tasted", gallery: "label_photo"
            )
        ),

        Entry(
            id: "lib.tea",
            category: .food,
            blurb: "Tea collection — type, origin, brew notes, source.",
            keywords: ["tea", "puer", "oolong", "matcha", "loose leaf"],
            template: makeType(
                id: "Tea", name: "Tea", plural: "Tea",
                image: "cup.and.heat.waves", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Type", [
                        ("Black", "#3D2B1F"), ("Green", "#3FB950"),
                        ("Oolong", "#E8A93B"), ("White", "#F0E68C"),
                        ("Pu-erh", "#7B4F2F"), ("Herbal", "#9D4DCC"),
                        ("Matcha", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Origin", kind: .text),
                    FieldDef.make(name: "Vendor", kind: .text),
                    FieldDef.make(name: "Brew temp (°F)", kind: .number),
                    FieldDef.make(name: "Steep time", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "name", kanban: "type"
            )
        ),

        Entry(
            id: "lib.cheese",
            category: .food,
            blurb: "Cheeses tried — milk, region, age, pairing notes.",
            keywords: ["cheese", "dairy", "fromage", "tasting"],
            template: makeType(
                id: "Cheese", name: "Cheese", plural: "Cheese",
                image: "drop.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Origin", kind: .text),
                    selectField("Milk", [
                        ("Cow", "#3FB950"), ("Goat", "#E8A93B"),
                        ("Sheep", "#9D4DCC"), ("Buffalo", "#3FA9F5"),
                        ("Blend", "#666666"),
                    ]),
                    selectField("Style", [
                        ("Fresh", "#3FB950"), ("Soft", "#E8A93B"),
                        ("Semi-soft", "#3FA9F5"), ("Hard", "#F08C2E"),
                        ("Blue", "#9D4DCC"), ("Washed rind", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Pairing notes", kind: .longText),
                ],
                primary: "name", kanban: "style"
            )
        ),

        Entry(
            id: "lib.brewery_visit",
            category: .food,
            blurb: "Breweries / distilleries / wineries you've visited.",
            keywords: ["brewery", "distillery", "winery", "tour", "tasting"],
            template: makeType(
                id: "BreweryVisit", name: "Visit", plural: "Brewery Visits",
                image: "building.2", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Type", [
                        ("Brewery", "#E8A93B"), ("Distillery", "#7B4F2F"),
                        ("Winery", "#9D4DCC"), ("Meadery", "#3FB950"),
                        ("Cidery", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Date visited", kind: .date),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Favorites", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", calendar: "date_visited", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.cafe_visit",
            category: .food,
            blurb: "Coffee shops & cafes — vibe, espresso quality, wifi.",
            keywords: ["cafe", "coffee shop", "espresso", "wifi", "remote work"],
            template: makeType(
                id: "CafeVisit", name: "Cafe", plural: "Cafes",
                image: "cup.and.saucer.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Neighborhood", kind: .text),
                    selectField("Verdict", [
                        ("Daily driver", "#3FB950"), ("Special trips", "#3FA9F5"),
                        ("Decent", "#E8A93B"), ("Skip", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Espresso rating", kind: .rating),
                    FieldDef.make(name: "Wifi / work-friendly?", kind: .boolean),
                    FieldDef.make(name: "Specialty drink", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "name", kanban: "verdict"
            )
        ),

        Entry(
            id: "lib.baking_project",
            category: .food,
            blurb: "Baking projects — bread, cake, croissant — with the variables you tweaked.",
            keywords: ["baking", "bread", "sourdough", "cake", "pastry"],
            template: makeType(
                id: "BakingProject", name: "Bake", plural: "Baking Projects",
                image: "birthday.cake", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Recipe", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Category", [
                        ("Bread", "#7B4F2F"), ("Cake", "#F08C2E"),
                        ("Pastry", "#E8A93B"), ("Cookie", "#9D4DCC"),
                        ("Pie", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Hydration %", kind: .number),
                    FieldDef.make(name: "Proof time", kind: .text),
                    FieldDef.make(name: "Oven temp (°F)", kind: .number),
                    FieldDef.make(name: "Bake time (min)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "What I'd change", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "recipe", kanban: "category", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.fermentation",
            category: .food,
            blurb: "Fermentation projects — sourdough starter, kimchi, kombucha.",
            keywords: ["fermentation", "kimchi", "kombucha", "sauerkraut", "starter"],
            template: makeType(
                id: "Fermentation", name: "Batch", plural: "Fermentation",
                image: "leaf.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Kind", [
                        ("Sourdough starter", "#7B4F2F"), ("Kombucha", "#E8A93B"),
                        ("Kimchi", "#D14B5C"), ("Sauerkraut", "#3FB950"),
                        ("Yogurt / kefir", "#3FA9F5"), ("Miso", "#9D4DCC"),
                        ("Hot sauce", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Ferment days", kind: .number),
                    FieldDef.make(name: "Temperature (°F)", kind: .number),
                    FieldDef.make(name: "Tasted on", kind: .date),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "kind", calendar: "started", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.garden_harvest",
            category: .food,
            blurb: "Garden harvest log — crop, amount, date, taste.",
            keywords: ["garden", "harvest", "vegetable", "crop", "homegrown"],
            template: makeType(
                id: "GardenHarvest", name: "Harvest", plural: "Garden Harvest",
                image: "leaf.arrow.triangle.circlepath", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Crop", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount", kind: .text, description: "weight or count"),
                    FieldDef.make(name: "Variety", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "crop", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.farmers_market",
            category: .food,
            blurb: "Farmers market visits — what's in season, who you bought from.",
            keywords: ["farmers market", "produce", "csa", "local food"],
            template: makeType(
                id: "FarmersMarket", name: "Visit", plural: "Farmers Market",
                image: "basket", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Market", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "What I bought", kind: .longText),
                    FieldDef.make(name: "Total spent", kind: .number),
                    FieldDef.make(name: "Highlights / vendors", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "market", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.hot_sauce",
            category: .food,
            blurb: "Hot sauce collection — heat, ingredients, where it shines.",
            keywords: ["hot sauce", "chili", "spicy", "scoville"],
            template: makeType(
                id: "HotSauce", name: "Sauce", plural: "Hot Sauces",
                image: "flame.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    selectField("Heat", [
                        ("Mild", "#3FB950"), ("Medium", "#E8A93B"),
                        ("Hot", "#F08C2E"), ("Very hot", "#D14B5C"),
                        ("Extreme", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Main pepper", kind: .text),
                    FieldDef.make(name: "Scoville (approx)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Best on", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "heat", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.takeout_order",
            category: .food,
            blurb: "Takeout / delivery — places you order from, favorite dishes.",
            keywords: ["takeout", "delivery", "doordash", "order"],
            template: makeType(
                id: "TakeoutOrder", name: "Order", plural: "Takeout Orders",
                image: "bag", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Restaurant", kind: .link),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Items ordered", kind: .longText),
                    FieldDef.make(name: "Total", kind: .number),
                    selectField("Verdict", [
                        ("Reorder", "#3FB950"), ("Decent", "#3FA9F5"),
                        ("One-off", "#E8A93B"), ("Avoid", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "restaurant", kanban: "verdict", calendar: "date"
            )
        ),

        // MARK: - Hobbies & Collecting (extended)

        Entry(
            id: "lib.coin",
            category: .hobbies,
            blurb: "Coin collection — country, year, denomination, mint, grade.",
            keywords: ["coin", "numismatic", "currency", "collecting"],
            template: makeType(
                id: "Coin", name: "Coin", plural: "Coin Collection",
                image: "centsign.circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Denomination", kind: .text),
                    FieldDef.make(name: "Mint mark", kind: .text),
                    selectField("Grade", [
                        ("Good", "#888888"), ("Fine", "#3FA9F5"),
                        ("Very fine", "#9D4DCC"), ("Extra fine", "#3FB950"),
                        ("Uncirculated", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Estimated value", kind: .number),
                    FieldDef.make(name: "Image", kind: .attachment),
                ],
                primary: "description", kanban: "grade", gallery: "image"
            )
        ),

        Entry(
            id: "lib.trading_card",
            category: .hobbies,
            blurb: "Trading cards — sport, year, set, number, condition.",
            keywords: ["trading card", "sports card", "tcg", "panini", "topps"],
            template: makeType(
                id: "TradingCard", name: "Card", plural: "Trading Cards",
                image: "rectangle.stack", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Player / subject", kind: .text, required: true),
                    selectField("Sport / category", [
                        ("Baseball", "#D14B5C"), ("Basketball", "#F08C2E"),
                        ("Football", "#3FB950"), ("Hockey", "#3FA9F5"),
                        ("Soccer", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Set", kind: .text),
                    FieldDef.make(name: "Card #", kind: .text),
                    selectField("Condition", [
                        ("Mint", "#3FB950"), ("Near mint", "#3FA9F5"),
                        ("Excellent", "#9D4DCC"), ("Very good", "#E8A93B"),
                        ("Good", "#F08C2E"), ("Played", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Graded?", kind: .boolean),
                    FieldDef.make(name: "Grade", kind: .text),
                    FieldDef.make(name: "Estimated value", kind: .number),
                    FieldDef.make(name: "Image", kind: .attachment),
                ],
                primary: "player_subject", kanban: "condition", gallery: "image"
            )
        ),

        Entry(
            id: "lib.comic_book",
            category: .hobbies,
            blurb: "Comic book collection — title, issue, publisher, key issue?",
            keywords: ["comic", "marvel", "dc", "issue", "graphic novel"],
            template: makeType(
                id: "ComicBook", name: "Comic", plural: "Comic Books",
                image: "book.pages", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Issue #", kind: .text),
                    FieldDef.make(name: "Publisher", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Writer", kind: .text),
                    FieldDef.make(name: "Artist", kind: .text),
                    selectField("Condition", [
                        ("Mint", "#3FB950"), ("NM", "#3FA9F5"),
                        ("VF", "#9D4DCC"), ("FN", "#E8A93B"),
                        ("VG", "#F08C2E"), ("Reading copy", "#666666"),
                    ]),
                    FieldDef.make(name: "Key issue?", kind: .boolean),
                    FieldDef.make(name: "Value", kind: .number),
                    FieldDef.make(name: "Cover image", kind: .attachment),
                ],
                primary: "title", kanban: "condition", gallery: "cover_image"
            )
        ),

        Entry(
            id: "lib.mtg_deck",
            category: .hobbies,
            blurb: "MTG decks — format, archetype, win rate, decklist link.",
            keywords: ["magic", "mtg", "deck", "commander", "edh", "modern"],
            template: makeType(
                id: "MTGDeck", name: "Deck", plural: "MTG Decks",
                image: "suit.spade", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Format", [
                        ("Standard", "#3FA9F5"), ("Modern", "#9D4DCC"),
                        ("Legacy", "#E8A93B"), ("Commander", "#3FB950"),
                        ("Pauper", "#666666"), ("Cube", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Commander / archetype", kind: .text),
                    FieldDef.make(name: "Colors", kind: .text),
                    FieldDef.make(name: "Decklist URL", kind: .url),
                    FieldDef.make(name: "Games played", kind: .number),
                    FieldDef.make(name: "Wins", kind: .number),
                    selectField("Status", [
                        ("Building", "#E8A93B"), ("Active", "#3FB950"),
                        ("Shelved", "#666666"), ("Dismantled", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "name", kanban: "status"
            )
        ),

        Entry(
            id: "lib.sneaker",
            category: .hobbies,
            blurb: "Sneaker collection — model, colorway, size, release date.",
            keywords: ["sneaker", "shoes", "jordan", "nike", "release"],
            template: makeType(
                id: "Sneaker", name: "Pair", plural: "Sneakers",
                image: "shoeprints.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Model", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Colorway", kind: .text),
                    FieldDef.make(name: "Size", kind: .text),
                    FieldDef.make(name: "Release date", kind: .date),
                    FieldDef.make(name: "Bought for", kind: .number),
                    FieldDef.make(name: "Current value", kind: .number),
                    selectField("Status", [
                        ("Deadstock", "#3FB950"), ("Worn", "#3FA9F5"),
                        ("Beat", "#E8A93B"), ("Sold", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "model", kanban: "status", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.watch",
            category: .hobbies,
            blurb: "Watch collection — brand, reference, movement, service log.",
            keywords: ["watch", "horology", "rolex", "seiko", "automatic"],
            template: makeType(
                id: "Watch", name: "Watch", plural: "Watches",
                image: "applewatch", color: "#666666",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Reference", kind: .text),
                    selectField("Movement", [
                        ("Automatic", "#3FA9F5"), ("Manual", "#9D4DCC"),
                        ("Quartz", "#E8A93B"), ("Hybrid / smart", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Purchased", kind: .date),
                    FieldDef.make(name: "Paid", kind: .number),
                    FieldDef.make(name: "Last service", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "nickname", kanban: "movement", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.pen",
            category: .hobbies,
            blurb: "Fountain pen collection — brand, nib, ink loaded, condition.",
            keywords: ["pen", "fountain", "nib", "ink", "stationery"],
            template: makeType(
                id: "FountainPen", name: "Pen", plural: "Pens",
                image: "pencil.tip", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Model", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Nib size", kind: .text),
                    selectField("Nib type", [
                        ("Steel", "#666666"), ("Gold 14k", "#E8A93B"),
                        ("Gold 18k", "#F08C2E"), ("Titanium", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Currently inked", kind: .text),
                    FieldDef.make(name: "Purchased", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "model", kanban: "nib_type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.astronomy_observation",
            category: .hobbies,
            blurb: "Astronomy log — what you spotted with the scope.",
            keywords: ["astronomy", "telescope", "stargazing", "messier", "planet"],
            template: makeType(
                id: "AstronomyLog", name: "Observation", plural: "Astronomy Log",
                image: "moon.stars.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Target", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Telescope / gear", kind: .text),
                    selectField("Category", [
                        ("Planet", "#F08C2E"), ("Moon", "#888888"),
                        ("Star", "#E8A93B"), ("Galaxy", "#9D4DCC"),
                        ("Nebula", "#3FA9F5"), ("Cluster", "#3FB950"),
                        ("ISS / satellite", "#666666"), ("Other", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Conditions", kind: .text, description: "seeing, transparency"),
                    FieldDef.make(name: "Sketch / photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "target", kanban: "category", calendar: "when", gallery: "sketch_photo"
            )
        ),

        Entry(
            id: "lib.bonsai",
            category: .hobbies,
            blurb: "Bonsai trees — species, age, training stage, last work.",
            keywords: ["bonsai", "tree", "horticulture", "training"],
            template: makeType(
                id: "BonsaiTree", name: "Tree", plural: "Bonsai",
                image: "tree", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Species", kind: .text),
                    selectField("Style", [
                        ("Informal upright", "#3FB950"), ("Formal upright", "#3FA9F5"),
                        ("Slanting", "#9D4DCC"), ("Cascade", "#E8A93B"),
                        ("Forest", "#F08C2E"), ("Root over rock", "#666666"),
                    ]),
                    FieldDef.make(name: "Age estimate", kind: .number),
                    FieldDef.make(name: "Last repot", kind: .date),
                    FieldDef.make(name: "Last wire", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Work log", kind: .noteLog),
                ],
                primary: "nickname", kanban: "style", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.aquarium_inhabitant",
            category: .hobbies,
            blurb: "Aquarium fish & plants — species, added, lost, behavior notes.",
            keywords: ["aquarium", "fish", "tank", "freshwater", "saltwater"],
            template: makeType(
                id: "AquariumLife", name: "Inhabitant", plural: "Aquarium",
                image: "fish.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Species / common name", kind: .text, required: true),
                    selectField("Type", [
                        ("Freshwater fish", "#3FA9F5"), ("Saltwater fish", "#9D4DCC"),
                        ("Invertebrate", "#E8A93B"), ("Plant", "#3FB950"),
                        ("Coral", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Count", kind: .number),
                    FieldDef.make(name: "Added", kind: .date),
                    selectField("Status", [
                        ("Thriving", "#3FB950"), ("Steady", "#3FA9F5"),
                        ("Struggling", "#E8A93B"), ("Lost", "#D14B5C"),
                        ("Rehomed", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species_common_name", kanban: "status", calendar: "added", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.rock_mineral",
            category: .hobbies,
            blurb: "Rocks & minerals — name, locality, hardness, photo.",
            keywords: ["rock", "mineral", "gem", "geology", "specimen"],
            template: makeType(
                id: "RockSpecimen", name: "Specimen", plural: "Rocks & Minerals",
                image: "diamond", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Type", [
                        ("Mineral", "#9D4DCC"), ("Rock", "#7B4F2F"),
                        ("Fossil", "#E8A93B"), ("Gem", "#3FA9F5"),
                        ("Meteorite", "#666666"),
                    ]),
                    FieldDef.make(name: "Locality", kind: .text),
                    FieldDef.make(name: "Hardness (Mohs)", kind: .number),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.knife",
            category: .hobbies,
            blurb: "Knife collection — maker, steel, blade shape, edge condition.",
            keywords: ["knife", "edc", "blade", "kitchen knife", "edc"],
            template: makeType(
                id: "Knife", name: "Knife", plural: "Knives",
                image: "scissors.badge.ellipsis", color: "#666666",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Maker", kind: .text),
                    selectField("Type", [
                        ("Kitchen", "#E8A93B"), ("EDC / folding", "#3FA9F5"),
                        ("Fixed", "#9D4DCC"), ("Tactical", "#666666"),
                        ("Collector", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Steel", kind: .text),
                    FieldDef.make(name: "Blade length (in)", kind: .number),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Last sharpened", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "nickname", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.funko_pop",
            category: .hobbies,
            blurb: "Funko Pop & figure collection — character, number, in/out of box.",
            keywords: ["funko", "pop", "figure", "vinyl", "collectible"],
            template: makeType(
                id: "FunkoPop", name: "Pop", plural: "Funko Pops",
                image: "person.bust", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Character", kind: .text, required: true),
                    FieldDef.make(name: "Series", kind: .text),
                    FieldDef.make(name: "Pop number", kind: .number),
                    FieldDef.make(name: "Exclusive?", kind: .boolean),
                    selectField("Status", [
                        ("Boxed", "#9D4DCC"), ("Displayed", "#3FA9F5"),
                        ("Stored", "#E8A93B"), ("Sold", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Value", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "character", kanban: "status", gallery: "photo"
            )
        ),

        // MARK: - Media & Entertainment (extended)

        Entry(
            id: "lib.album",
            category: .media,
            blurb: "Music albums — artist, year, format owned, rating.",
            keywords: ["album", "music", "lp", "cd", "streaming"],
            template: makeType(
                id: "Album", name: "Album", plural: "Albums",
                image: "music.note.list", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    selectField("Genre", [
                        ("Rock", "#D14B5C"), ("Pop", "#F08C2E"),
                        ("Hip-hop", "#9D4DCC"), ("Electronic", "#3FA9F5"),
                        ("Jazz", "#E8A93B"), ("Classical", "#3FB950"),
                        ("Country / folk", "#7B4F2F"), ("Metal", "#666666"),
                        ("Other", "#888888"),
                    ]),
                    selectField("Format", [
                        ("Streaming only", "#3FA9F5"), ("CD", "#9D4DCC"),
                        ("Vinyl", "#E8A93B"), ("Cassette", "#7B4F2F"),
                        ("Digital file", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Date discovered", kind: .date),
                    FieldDef.make(name: "Cover", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "title", kanban: "genre", calendar: "date_discovered", gallery: "cover"
            )
        ),

        Entry(
            id: "lib.song",
            category: .media,
            blurb: "Favorite songs — for playlists, mixtapes, memories.",
            keywords: ["song", "track", "favorite", "playlist"],
            template: makeType(
                id: "Song", name: "Song", plural: "Favorite Songs",
                image: "music.note", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Album", kind: .link),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Length", kind: .text),
                    selectField("Mood", [
                        ("Hype", "#D14B5C"), ("Chill", "#3FA9F5"),
                        ("Sad", "#9D4DCC"), ("Focus", "#3FB950"),
                        ("Driving", "#E8A93B"), ("Party", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Memory / context", kind: .longText),
                ],
                primary: "title", kanban: "mood"
            )
        ),

        Entry(
            id: "lib.concert",
            category: .media,
            blurb: "Concerts attended — artist, venue, date, setlist memory.",
            keywords: ["concert", "show", "live music", "gig"],
            template: makeType(
                id: "Concert", name: "Concert", plural: "Concerts",
                image: "music.mic", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Artist", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Venue", kind: .text),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Opener(s)", kind: .text),
                    FieldDef.make(name: "Ticket cost", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Best moment", kind: .longText),
                    FieldDef.make(name: "Setlist / photo", kind: .attachment),
                ],
                primary: "artist", calendar: "date", gallery: "setlist_photo"
            )
        ),

        Entry(
            id: "lib.live_event",
            category: .media,
            blurb: "Live shows — theater, comedy, opera, dance, anything ticketed.",
            keywords: ["theater", "comedy", "opera", "dance", "performance"],
            template: makeType(
                id: "LiveEvent", name: "Event", plural: "Live Events",
                image: "theatermasks", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Event", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Type", [
                        ("Play", "#9D4DCC"), ("Musical", "#E8A93B"),
                        ("Opera", "#F08C2E"), ("Ballet", "#3FA9F5"),
                        ("Stand-up", "#3FB950"), ("Improv", "#D14B5C"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Venue", kind: .text),
                    FieldDef.make(name: "Cast / performer", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes / review", kind: .richText),
                ],
                primary: "event", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.sports_event",
            category: .media,
            blurb: "Sports events attended — team, opponent, score, vibe.",
            keywords: ["sports", "game", "event", "stadium"],
            template: makeType(
                id: "SportsEvent", name: "Game", plural: "Sports Events",
                image: "sportscourt", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Matchup", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Sport", [
                        ("Baseball", "#D14B5C"), ("Basketball", "#F08C2E"),
                        ("Football", "#3FB950"), ("Hockey", "#3FA9F5"),
                        ("Soccer", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Venue", kind: .text),
                    FieldDef.make(name: "Final score", kind: .text),
                    FieldDef.make(name: "Did 'my' team win?", kind: .boolean),
                    FieldDef.make(name: "Memory", kind: .longText),
                    FieldDef.make(name: "Ticket stub", kind: .attachment),
                ],
                primary: "matchup", kanban: "sport", calendar: "date"
            )
        ),

        Entry(
            id: "lib.festival",
            category: .media,
            blurb: "Festivals attended — music, film, food. Lineup highlights.",
            keywords: ["festival", "lineup", "weekend", "music festival", "film festival"],
            template: makeType(
                id: "Festival", name: "Festival", plural: "Festivals",
                image: "tent", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Start", kind: .date),
                    FieldDef.make(name: "End", kind: .date),
                    selectField("Type", [
                        ("Music", "#9D4DCC"), ("Film", "#3FA9F5"),
                        ("Food", "#E8A93B"), ("Cultural", "#3FB950"),
                        ("Tech", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Highlights", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", calendar: "start", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.youtube_channel",
            category: .media,
            blurb: "YouTube channels worth following — topic, frequency, why.",
            keywords: ["youtube", "channel", "creator", "video"],
            template: makeType(
                id: "YouTubeChannel", name: "Channel", plural: "YouTube",
                image: "play.rectangle", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Channel", kind: .text, required: true),
                    FieldDef.make(name: "URL", kind: .url),
                    selectField("Topic", [
                        ("Tech", "#3FA9F5"), ("Comedy", "#E8A93B"),
                        ("Gaming", "#9D4DCC"), ("Education", "#3FB950"),
                        ("Cooking", "#F08C2E"), ("Music", "#D14B5C"),
                        ("Vlog", "#666666"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Subscribed?", kind: .boolean),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Why I like it", kind: .longText),
                ],
                primary: "channel", kanban: "topic"
            )
        ),

        Entry(
            id: "lib.anime",
            category: .media,
            blurb: "Anime watched — series, season, episodes, MAL link.",
            keywords: ["anime", "manga", "japanese", "myanimelist"],
            template: makeType(
                id: "Anime", name: "Anime", plural: "Anime",
                image: "tv.badge.wifi", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Studio", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Episodes total", kind: .number),
                    FieldDef.make(name: "Episodes watched", kind: .number),
                    selectField("Status", [
                        ("Plan to watch", "#888888"), ("Watching", "#3FA9F5"),
                        ("Completed", "#3FB950"), ("On hold", "#E8A93B"),
                        ("Dropped", "#D14B5C"),
                    ]),
                    selectField("Genre", [
                        ("Action", "#D14B5C"), ("Romance", "#F08C2E"),
                        ("SoL", "#3FB950"), ("Mecha", "#666666"),
                        ("Fantasy", "#9D4DCC"), ("Sci-fi", "#3FA9F5"),
                        ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "MAL / AniList URL", kind: .url),
                    FieldDef.make(name: "Cover", kind: .attachment),
                ],
                primary: "title", kanban: "status", gallery: "cover"
            )
        ),

        Entry(
            id: "lib.manga",
            category: .media,
            blurb: "Manga reading log — volume, status, ongoing or complete.",
            keywords: ["manga", "comic", "japanese", "manhwa"],
            template: makeType(
                id: "Manga", name: "Manga", plural: "Manga",
                image: "books.vertical.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Author", kind: .text),
                    FieldDef.make(name: "Chapters / volumes", kind: .text),
                    selectField("Status", [
                        ("Reading", "#3FA9F5"), ("Caught up", "#9D4DCC"),
                        ("Completed", "#3FB950"), ("Dropped", "#D14B5C"),
                        ("Plan to read", "#888888"),
                    ]),
                    FieldDef.make(name: "Current chapter", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Cover", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "status", gallery: "cover"
            )
        ),

        Entry(
            id: "lib.rpg_campaign",
            category: .media,
            blurb: "Tabletop RPG campaign — system, party, sessions, story arc.",
            keywords: ["rpg", "dnd", "dungeons", "campaign", "pathfinder", "ttrpg"],
            template: makeType(
                id: "RPGCampaign", name: "Campaign", plural: "RPG Campaigns",
                image: "dice", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "System", kind: .text),
                    FieldDef.make(name: "DM / GM", kind: .text),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Sessions played", kind: .number),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("On hiatus", "#E8A93B"),
                        ("Wrapping up", "#9D4DCC"), ("Completed", "#3FA9F5"),
                        ("Cancelled", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Setting", kind: .text),
                    FieldDef.make(name: "Story so far", kind: .richText),
                    FieldDef.make(name: "Session log", kind: .noteLog),
                ],
                primary: "name", kanban: "status", calendar: "started"
            )
        ),

        Entry(
            id: "lib.documentary",
            category: .media,
            blurb: "Documentaries watched — topic, director, rating, key takeaways.",
            keywords: ["documentary", "doc", "nonfiction", "film"],
            template: makeType(
                id: "Documentary", name: "Documentary", plural: "Documentaries",
                image: "film.stack", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Director", kind: .text),
                    FieldDef.make(name: "Year", kind: .number),
                    selectField("Topic", [
                        ("Nature", "#3FB950"), ("History", "#7B4F2F"),
                        ("Crime", "#D14B5C"), ("Politics", "#9D4DCC"),
                        ("Science", "#3FA9F5"), ("Sports", "#F08C2E"),
                        ("Music", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Date watched", kind: .date),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Takeaways", kind: .richText),
                ],
                primary: "title", kanban: "topic", calendar: "date_watched"
            )
        ),

        Entry(
            id: "lib.audiobook",
            category: .media,
            blurb: "Audiobooks listened to — narrator, hours, finished?",
            keywords: ["audiobook", "audible", "narrator", "listen"],
            template: makeType(
                id: "Audiobook", name: "Audiobook", plural: "Audiobooks",
                image: "headphones", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Author", kind: .text),
                    FieldDef.make(name: "Narrator", kind: .text),
                    FieldDef.make(name: "Length (hr)", kind: .number),
                    selectField("Status", [
                        ("Want to listen", "#888888"), ("Listening", "#3FA9F5"),
                        ("Finished", "#3FB950"), ("DNF", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Speed", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Finished on", kind: .date),
                    FieldDef.make(name: "Cover", kind: .attachment),
                ],
                primary: "title", kanban: "status", calendar: "finished_on", gallery: "cover"
            )
        ),

        Entry(
            id: "lib.magazine_subscription",
            category: .media,
            blurb: "Magazine / newsletter subscriptions — frequency, renewal.",
            keywords: ["magazine", "newsletter", "subscription", "print"],
            template: makeType(
                id: "MagazineSubscription", name: "Subscription", plural: "Magazines",
                image: "newspaper", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    selectField("Format", [
                        ("Print", "#9D4DCC"), ("Digital", "#3FA9F5"),
                        ("Both", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Frequency", kind: .text),
                    FieldDef.make(name: "Cost / year", kind: .number),
                    FieldDef.make(name: "Renews", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "format", calendar: "renews"
            )
        ),

        // MARK: - Travel & Places (extended)

        Entry(
            id: "lib.hotel_stay",
            category: .travel,
            blurb: "Hotels / Airbnbs stayed at — comfort, location, would return.",
            keywords: ["hotel", "airbnb", "accommodation", "stay", "lodging"],
            template: makeType(
                id: "HotelStay", name: "Stay", plural: "Hotels & Stays",
                image: "bed.double.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Place", kind: .text, required: true),
                    selectField("Type", [
                        ("Hotel", "#3FA9F5"), ("Airbnb", "#D14B5C"),
                        ("Hostel", "#E8A93B"), ("Resort", "#F08C2E"),
                        ("Friend's place", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Check-in", kind: .date),
                    FieldDef.make(name: "Check-out", kind: .date),
                    FieldDef.make(name: "Per-night", kind: .number),
                    FieldDef.make(name: "Confirmation", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Would return?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "place", kanban: "type", calendar: "check_in"
            )
        ),

        Entry(
            id: "lib.road_trip",
            category: .travel,
            blurb: "Road trips — route, miles, stops, cargo.",
            keywords: ["road trip", "drive", "route", "rv"],
            template: makeType(
                id: "RoadTrip", name: "Trip", plural: "Road Trips",
                image: "road.lanes", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Trip name", kind: .text, required: true),
                    FieldDef.make(name: "Start", kind: .date),
                    FieldDef.make(name: "End", kind: .date),
                    FieldDef.make(name: "Start city", kind: .text),
                    FieldDef.make(name: "End city", kind: .text),
                    FieldDef.make(name: "Miles driven", kind: .number),
                    FieldDef.make(name: "Vehicle", kind: .link),
                    FieldDef.make(name: "Companions", kind: .link),
                    FieldDef.make(name: "Highlights", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "trip_name", calendar: "start", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.cruise",
            category: .travel,
            blurb: "Cruise log — cruise line, ship, ports, cabin.",
            keywords: ["cruise", "ship", "ports", "cabin"],
            template: makeType(
                id: "Cruise", name: "Cruise", plural: "Cruises",
                image: "ferry", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Cruise name", kind: .text, required: true),
                    FieldDef.make(name: "Cruise line", kind: .text),
                    FieldDef.make(name: "Ship", kind: .text),
                    FieldDef.make(name: "Departure", kind: .date),
                    FieldDef.make(name: "Return", kind: .date),
                    FieldDef.make(name: "Cabin", kind: .text),
                    FieldDef.make(name: "Ports of call", kind: .longText),
                    FieldDef.make(name: "Cost per person", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "cruise_name", calendar: "departure", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.camping_trip",
            category: .travel,
            blurb: "Camping trips — site, gear list, weather, what worked.",
            keywords: ["camping", "campsite", "outdoor", "tent", "backpacking"],
            template: makeType(
                id: "CampingTrip", name: "Camp", plural: "Camping Trips",
                image: "tent.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Trip name", kind: .text, required: true),
                    FieldDef.make(name: "Park / area", kind: .text),
                    FieldDef.make(name: "Site #", kind: .text),
                    FieldDef.make(name: "Start", kind: .date),
                    FieldDef.make(name: "End", kind: .date),
                    selectField("Style", [
                        ("Car camping", "#3FA9F5"), ("Backpacking", "#9D4DCC"),
                        ("RV", "#E8A93B"), ("Glamping", "#F08C2E"),
                        ("Cabin", "#7B4F2F"),
                    ]),
                    FieldDef.make(name: "Weather", kind: .text),
                    FieldDef.make(name: "Companions", kind: .link),
                    FieldDef.make(name: "Highlights", kind: .richText),
                    FieldDef.make(name: "Lessons for next time", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "trip_name", kanban: "style", calendar: "start", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.national_park",
            category: .travel,
            blurb: "National park visits — park, season, trails hiked, stamp.",
            keywords: ["national park", "park", "nps", "passport", "stamp"],
            template: makeType(
                id: "NationalPark", name: "Park", plural: "National Parks",
                image: "mountain.2", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Park", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "State / region", kind: .text),
                    FieldDef.make(name: "First visit", kind: .date),
                    FieldDef.make(name: "Visits", kind: .number),
                    FieldDef.make(name: "Passport stamped?", kind: .boolean),
                    FieldDef.make(name: "Trails done", kind: .longText),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "park", calendar: "first_visit", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.museum",
            category: .travel,
            blurb: "Museums visited — collection, favorite piece, return-worthy.",
            keywords: ["museum", "gallery", "exhibit", "art", "history"],
            template: makeType(
                id: "Museum", name: "Museum", plural: "Museums",
                image: "building.columns.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Type", [
                        ("Art", "#9D4DCC"), ("History", "#7B4F2F"),
                        ("Science", "#3FA9F5"), ("Natural history", "#3FB950"),
                        ("Specialty", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Date visited", kind: .date),
                    FieldDef.make(name: "Special exhibit?", kind: .text),
                    FieldDef.make(name: "Favorite piece", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", calendar: "date_visited", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.beach_visited",
            category: .travel,
            blurb: "Beaches visited — sand quality, surf, vibe.",
            keywords: ["beach", "ocean", "surf", "swimming", "coast"],
            template: makeType(
                id: "Beach", name: "Beach", plural: "Beaches",
                image: "beach.umbrella", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "City / island", kind: .text),
                    FieldDef.make(name: "First visit", kind: .date),
                    selectField("Vibe", [
                        ("Tourist", "#F08C2E"), ("Local hangout", "#3FB950"),
                        ("Secluded", "#9D4DCC"), ("Family", "#3FA9F5"),
                        ("Surf", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "name", kanban: "vibe", calendar: "first_visit", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.summit",
            category: .travel,
            blurb: "Mountains summited — elevation, route, conditions, photo.",
            keywords: ["mountain", "summit", "peak", "climbing", "mountaineering"],
            template: makeType(
                id: "Summit", name: "Summit", plural: "Summits",
                image: "mountain.2.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Peak", kind: .text, required: true),
                    FieldDef.make(name: "Elevation (ft)", kind: .number),
                    FieldDef.make(name: "Range", kind: .text),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Route style", [
                        ("Hike", "#3FB950"), ("Scramble", "#E8A93B"),
                        ("Rock climb", "#9D4DCC"), ("Alpine", "#3FA9F5"),
                        ("Ski", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Companions", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "peak", kanban: "route_style", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.bucket_list",
            category: .travel,
            blurb: "Bucket list — places you want to visit, status, why.",
            keywords: ["bucket list", "wishlist", "dream", "travel goal"],
            template: makeType(
                id: "BucketListPlace", name: "Place", plural: "Bucket List",
                image: "list.star", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Destination", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    selectField("Status", [
                        ("Someday", "#888888"), ("Researching", "#3FA9F5"),
                        ("Planning", "#9D4DCC"), ("Booked", "#E8A93B"),
                        ("Visited", "#3FB950"),
                    ]),
                    selectField("Best season", [
                        ("Spring", "#3FB950"), ("Summer", "#E8A93B"),
                        ("Fall", "#F08C2E"), ("Winter", "#3FA9F5"),
                        ("Year-round", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Why", kind: .richText),
                    FieldDef.make(name: "Estimated cost", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "destination", kanban: "status", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.visa_application",
            category: .travel,
            blurb: "Visa applications — country, type, fee, status, validity.",
            keywords: ["visa", "passport", "embassy", "consulate", "travel doc"],
            template: makeType(
                id: "VisaApplication", name: "Visa", plural: "Visas",
                image: "person.text.rectangle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Country", kind: .text, required: true),
                    selectField("Visa type", [
                        ("Tourist", "#3FA9F5"), ("Business", "#9D4DCC"),
                        ("Student", "#E8A93B"), ("Work", "#F08C2E"),
                        ("Transit", "#666666"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Applied", kind: .date),
                    FieldDef.make(name: "Approved", kind: .date),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Fee", kind: .number),
                    selectField("Status", [
                        ("Draft", "#888888"), ("Submitted", "#3FA9F5"),
                        ("Approved", "#3FB950"), ("Denied", "#D14B5C"),
                        ("Expired", "#666666"),
                    ]),
                    FieldDef.make(name: "Visa document", kind: .attachment),
                ],
                primary: "country", kanban: "status", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.train_trip",
            category: .travel,
            blurb: "Train trips — operator, route, class, scenic notes.",
            keywords: ["train", "rail", "amtrak", "shinkansen", "eurail"],
            template: makeType(
                id: "TrainTrip", name: "Train Trip", plural: "Train Trips",
                image: "tram", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Train / route", kind: .text, required: true),
                    FieldDef.make(name: "Operator", kind: .text),
                    FieldDef.make(name: "From", kind: .text),
                    FieldDef.make(name: "To", kind: .text),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Class", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Scenic rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "train_route", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.cycling_route",
            category: .travel,
            blurb: "Cycling rides — route, distance, elevation, surface.",
            keywords: ["cycling", "bike", "ride", "strava", "gravel"],
            template: makeType(
                id: "CyclingRoute", name: "Ride", plural: "Cycling",
                image: "bicycle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Route name", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Distance (mi)", kind: .number),
                    FieldDef.make(name: "Elevation gain (ft)", kind: .number),
                    FieldDef.make(name: "Time (min)", kind: .number),
                    selectField("Surface", [
                        ("Road", "#666666"), ("Gravel", "#7B4F2F"),
                        ("MTB", "#3FB950"), ("Mixed", "#E8A93B"),
                    ]),
                    selectField("Effort", [
                        ("Easy", "#3FB950"), ("Steady", "#3FA9F5"),
                        ("Tempo", "#9D4DCC"), ("Hard", "#E8A93B"),
                        ("Race pace", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "route_name", kanban: "effort", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.diving_log",
            category: .travel,
            blurb: "Scuba dives — site, depth, time, viz, what you saw.",
            keywords: ["scuba", "dive", "diving", "snorkel", "underwater"],
            template: makeType(
                id: "DiveLog", name: "Dive", plural: "Dive Log",
                image: "drop.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Dive site", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Max depth (ft)", kind: .number),
                    FieldDef.make(name: "Bottom time (min)", kind: .number),
                    FieldDef.make(name: "Visibility (ft)", kind: .number),
                    FieldDef.make(name: "Water temp (°F)", kind: .number),
                    selectField("Type", [
                        ("Reef", "#3FB950"), ("Wreck", "#666666"),
                        ("Wall", "#9D4DCC"), ("Drift", "#3FA9F5"),
                        ("Cave / cavern", "#E8A93B"), ("Shore", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Buddy", kind: .link),
                    FieldDef.make(name: "Marine life seen", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "dive_site", kanban: "type", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.ski_day",
            category: .travel,
            blurb: "Ski/snowboard days — resort, conditions, vertical, runs.",
            keywords: ["ski", "snowboard", "powder", "resort", "mountain"],
            template: makeType(
                id: "SkiDay", name: "Ski Day", plural: "Ski Days",
                image: "figure.skiing.downhill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Resort", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Conditions", [
                        ("Powder", "#9D4DCC"), ("Packed powder", "#3FA9F5"),
                        ("Hardpack", "#666666"), ("Ice", "#D14B5C"),
                        ("Slush", "#E8A93B"), ("Spring", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Vertical (ft)", kind: .number),
                    FieldDef.make(name: "Runs", kind: .number),
                    FieldDef.make(name: "Lift tickets cost", kind: .number),
                    FieldDef.make(name: "Companions", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "resort", kanban: "conditions", calendar: "date", gallery: "photo"
            )
        ),

        // MARK: - Creative Work (extended)

        Entry(
            id: "lib.photo_portfolio",
            category: .creative,
            blurb: "Photography portfolio piece — gear, settings, where shown.",
            keywords: ["photography", "portfolio", "image", "shot"],
            template: makeType(
                id: "PortfolioPhoto", name: "Photo", plural: "Photo Portfolio",
                image: "photo.stack", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Taken", kind: .date),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Camera / lens", kind: .text),
                    FieldDef.make(name: "Settings", kind: .text, description: "f/ , ISO, shutter"),
                    selectField("Category", [
                        ("Landscape", "#3FB950"), ("Portrait", "#9D4DCC"),
                        ("Street", "#3FA9F5"), ("Wildlife", "#E8A93B"),
                        ("Macro", "#F08C2E"), ("Architecture", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Raw", "#888888"), ("Edited", "#3FA9F5"),
                        ("Published", "#3FB950"), ("Sold", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Image", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "title", kanban: "category", calendar: "taken", gallery: "image"
            )
        ),

        Entry(
            id: "lib.video_project",
            category: .creative,
            blurb: "Video / film projects — concept, status, shoot date, edits.",
            keywords: ["video", "film", "edit", "youtube", "short"],
            template: makeType(
                id: "VideoProject", name: "Project", plural: "Video Projects",
                image: "film", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Concept", kind: .longText),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Pre-prod", "#3FA9F5"),
                        ("Shot", "#9D4DCC"), ("Editing", "#E8A93B"),
                        ("Done", "#3FB950"), ("Published", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Shoot date", kind: .date),
                    FieldDef.make(name: "Runtime", kind: .text),
                    FieldDef.make(name: "Published URL", kind: .url),
                    FieldDef.make(name: "Views", kind: .number),
                    FieldDef.make(name: "Thumbnail", kind: .attachment),
                ],
                primary: "title", kanban: "status", calendar: "shoot_date", gallery: "thumbnail"
            )
        ),

        Entry(
            id: "lib.song_written",
            category: .creative,
            blurb: "Original songs you've written — key, BPM, status, demo.",
            keywords: ["songwriting", "music", "compose", "demo", "lyrics"],
            template: makeType(
                id: "SongWritten", name: "Song", plural: "Original Songs",
                image: "music.quarternote.3", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Key", kind: .text),
                    FieldDef.make(name: "BPM", kind: .number),
                    FieldDef.make(name: "Time signature", kind: .text),
                    selectField("Status", [
                        ("Idea", "#888888"), ("In progress", "#3FA9F5"),
                        ("Demo'd", "#9D4DCC"), ("Recorded", "#E8A93B"),
                        ("Released", "#3FB950"), ("Shelved", "#666666"),
                    ]),
                    FieldDef.make(name: "Lyrics", kind: .richText),
                    FieldDef.make(name: "Demo file", kind: .attachment),
                ],
                primary: "title", kanban: "status"
            )
        ),

        Entry(
            id: "lib.pottery_piece",
            category: .creative,
            blurb: "Pottery pieces thrown — clay, glaze, firing temp, fate.",
            keywords: ["pottery", "ceramics", "wheel", "kiln", "glaze"],
            template: makeType(
                id: "PotteryPiece", name: "Piece", plural: "Pottery",
                image: "circle.grid.cross", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Form", [
                        ("Bowl", "#3FB950"), ("Mug", "#3FA9F5"),
                        ("Plate", "#E8A93B"), ("Vase", "#9D4DCC"),
                        ("Sculpture", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Clay body", kind: .text),
                    FieldDef.make(name: "Glaze(s)", kind: .text),
                    FieldDef.make(name: "Firing cone", kind: .text),
                    FieldDef.make(name: "Thrown on", kind: .date),
                    FieldDef.make(name: "Fired on", kind: .date),
                    selectField("Fate", [
                        ("Keeper", "#3FB950"), ("Gifted", "#9D4DCC"),
                        ("Sold", "#E8A93B"), ("Practice", "#888888"),
                        ("Broken", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "fate", calendar: "fired_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.tattoo",
            category: .creative,
            blurb: "Tattoos owned (or planned) — artist, placement, design, healing.",
            keywords: ["tattoo", "ink", "body art", "design"],
            template: makeType(
                id: "Tattoo", name: "Tattoo", plural: "Tattoos",
                image: "drop.degreesign", color: "#666666",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Placement", kind: .text),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Shop", kind: .text),
                    FieldDef.make(name: "Date inked", kind: .date),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Booked", "#3FA9F5"),
                        ("Inked", "#3FB950"), ("Healed", "#9D4DCC"),
                        ("Touched up", "#E8A93B"), ("Removed", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Meaning", kind: .longText),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "description", kanban: "status", calendar: "date_inked", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.design_project",
            category: .creative,
            blurb: "Graphic / web design projects — client, scope, deliverables.",
            keywords: ["design", "graphic", "logo", "branding", "ui"],
            template: makeType(
                id: "DesignProject", name: "Project", plural: "Design Projects",
                image: "rectangle.3.group.bubble", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Project", kind: .text, required: true),
                    FieldDef.make(name: "Client", kind: .link),
                    selectField("Type", [
                        ("Logo", "#9D4DCC"), ("Branding", "#3FA9F5"),
                        ("Web", "#3FB950"), ("Print", "#E8A93B"),
                        ("Packaging", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Briefing", "#888888"), ("Drafting", "#3FA9F5"),
                        ("Revising", "#E8A93B"), ("Delivered", "#3FB950"),
                        ("Iterating", "#9D4DCC"), ("Closed", "#666666"),
                    ]),
                    FieldDef.make(name: "Deadline", kind: .date),
                    FieldDef.make(name: "Fee", kind: .number),
                    FieldDef.make(name: "Brief", kind: .richText),
                    FieldDef.make(name: "Final asset", kind: .attachment),
                ],
                primary: "project", kanban: "status", calendar: "deadline", gallery: "final_asset"
            )
        ),

        Entry(
            id: "lib.threed_print",
            category: .creative,
            blurb: "3D prints — model source, settings, filament, success rate.",
            keywords: ["3d print", "filament", "stl", "model", "printer"],
            template: makeType(
                id: "ThreeDPrint", name: "Print", plural: "3D Prints",
                image: "cube.box", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Model name", kind: .text, required: true),
                    FieldDef.make(name: "Source URL", kind: .url),
                    FieldDef.make(name: "Printer", kind: .text),
                    FieldDef.make(name: "Filament", kind: .text),
                    FieldDef.make(name: "Layer height (mm)", kind: .number),
                    FieldDef.make(name: "Infill %", kind: .number),
                    FieldDef.make(name: "Print time (hr)", kind: .number),
                    selectField("Outcome", [
                        ("Success", "#3FB950"), ("Minor flaws", "#E8A93B"),
                        ("Failed", "#D14B5C"), ("Reprint", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Date printed", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "model_name", kanban: "outcome", calendar: "date_printed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.cosplay",
            category: .creative,
            blurb: "Cosplay builds — character, source, work-in-progress photos.",
            keywords: ["cosplay", "costume", "convention", "build"],
            template: makeType(
                id: "Cosplay", name: "Cosplay", plural: "Cosplays",
                image: "person.crop.square.badge.camera", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Character", kind: .text, required: true),
                    FieldDef.make(name: "Source media", kind: .text),
                    selectField("Status", [
                        ("Concept", "#888888"), ("Building", "#3FA9F5"),
                        ("Finished", "#3FB950"), ("Worn", "#9D4DCC"),
                        ("Retired", "#666666"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Worn at", kind: .text),
                    FieldDef.make(name: "Budget", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Build log", kind: .noteLog),
                ],
                primary: "character", kanban: "status", calendar: "started", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sewing_project",
            category: .creative,
            blurb: "Sewing / quilting projects — pattern, fabric, status.",
            keywords: ["sewing", "quilt", "garment", "pattern", "fabric"],
            template: makeType(
                id: "SewingProject", name: "Project", plural: "Sewing",
                image: "scissors", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Project", kind: .text, required: true),
                    selectField("Type", [
                        ("Garment", "#9D4DCC"), ("Quilt", "#E8A93B"),
                        ("Home goods", "#3FB950"), ("Bag", "#7B4F2F"),
                        ("Costume", "#F08C2E"), ("Mending", "#666666"),
                    ]),
                    FieldDef.make(name: "Pattern", kind: .text),
                    FieldDef.make(name: "Fabric", kind: .text),
                    selectField("Status", [
                        ("Planning", "#888888"), ("Cutting", "#3FA9F5"),
                        ("Sewing", "#9D4DCC"), ("Fitting", "#E8A93B"),
                        ("Finished", "#3FB950"), ("UFO", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Finished", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "project", kanban: "status", calendar: "finished", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.blog_post",
            category: .creative,
            blurb: "Blog posts published — slug, platform, words, performance.",
            keywords: ["blog", "post", "essay", "substack", "medium"],
            template: makeType(
                id: "BlogPost", name: "Post", plural: "Blog Posts",
                image: "doc.richtext.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Slug / URL", kind: .url),
                    FieldDef.make(name: "Platform", kind: .text),
                    FieldDef.make(name: "Words", kind: .number),
                    FieldDef.make(name: "Published", kind: .date),
                    selectField("Status", [
                        ("Drafting", "#3FA9F5"), ("Editing", "#9D4DCC"),
                        ("Published", "#3FB950"), ("Unpublished", "#D14B5C"),
                        ("Update planned", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Views", kind: .number),
                    FieldDef.make(name: "Reactions", kind: .number),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "title", kanban: "status", calendar: "published"
            )
        ),

        Entry(
            id: "lib.newsletter_issue",
            category: .creative,
            blurb: "Newsletter issues — issue #, theme, subscribers, click rate.",
            keywords: ["newsletter", "substack", "mailchimp", "issue", "email"],
            template: makeType(
                id: "NewsletterIssue", name: "Issue", plural: "Newsletter Issues",
                image: "envelope.open.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Issue #", kind: .number, required: true),
                    FieldDef.make(name: "Subject line", kind: .text),
                    FieldDef.make(name: "Theme", kind: .text),
                    FieldDef.make(name: "Sent", kind: .date),
                    FieldDef.make(name: "Subscribers", kind: .number),
                    FieldDef.make(name: "Open rate %", kind: .number),
                    FieldDef.make(name: "Click rate %", kind: .number),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "subject_line", calendar: "sent"
            )
        ),

        Entry(
            id: "lib.scrapbook_page",
            category: .creative,
            blurb: "Scrapbook pages — event, layout, photos used.",
            keywords: ["scrapbook", "memory book", "layout", "album"],
            template: makeType(
                id: "ScrapbookPage", name: "Page", plural: "Scrapbook Pages",
                image: "doc.append", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Event date", kind: .date),
                    FieldDef.make(name: "Album", kind: .text),
                    FieldDef.make(name: "Layout style", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Story", kind: .richText),
                ],
                primary: "title", calendar: "event_date", gallery: "photo"
            )
        ),

        // MARK: - Work & Career (extended)

        Entry(
            id: "lib.resume_version",
            category: .professional,
            blurb: "Resume versions — date, tailored for, file, sent-to count.",
            keywords: ["resume", "cv", "version", "tailored"],
            template: makeType(
                id: "ResumeVersion", name: "Version", plural: "Resume Versions",
                image: "doc.text.image", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Date created", kind: .date),
                    FieldDef.make(name: "Tailored for", kind: .text),
                    selectField("Style", [
                        ("Standard", "#3FA9F5"), ("Visual", "#9D4DCC"),
                        ("Technical", "#3FB950"), ("Federal", "#E8A93B"),
                        ("Academic CV", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Times sent", kind: .number),
                    FieldDef.make(name: "File", kind: .attachment),
                ],
                primary: "name", kanban: "style", calendar: "date_created"
            )
        ),

        Entry(
            id: "lib.networking_contact",
            category: .professional,
            blurb: "People you've connected with professionally — context, follow-ups.",
            keywords: ["network", "contact", "professional", "linkedin"],
            template: makeType(
                id: "NetworkingContact", name: "Contact", plural: "Network",
                image: "person.crop.circle.badge.checkmark", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Met at", kind: .text),
                    FieldDef.make(name: "Met on", kind: .date),
                    selectField("Strength", [
                        ("Cold", "#888888"), ("Warm", "#3FA9F5"),
                        ("Strong", "#9D4DCC"), ("Champion", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Their company / role", kind: .text),
                    FieldDef.make(name: "How they can help", kind: .longText),
                    FieldDef.make(name: "How I can help", kind: .longText),
                    FieldDef.make(name: "Last touched", kind: .date),
                ],
                primary: "person", kanban: "strength", calendar: "last_touched"
            )
        ),

        Entry(
            id: "lib.performance_review",
            category: .professional,
            blurb: "Performance reviews received — period, rating, themes.",
            keywords: ["review", "performance", "annual", "feedback"],
            template: makeType(
                id: "PerformanceReview", name: "Review", plural: "Performance Reviews",
                image: "chart.bar.doc.horizontal", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Period", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Reviewer", kind: .link),
                    selectField("Rating", [
                        ("Below", "#D14B5C"), ("Meets", "#3FA9F5"),
                        ("Exceeds", "#9D4DCC"), ("Strong exceeds", "#3FB950"),
                        ("Outstanding", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Themes — strengths", kind: .richText),
                    FieldDef.make(name: "Themes — growth", kind: .richText),
                    FieldDef.make(name: "Comp outcome", kind: .text),
                    FieldDef.make(name: "Document", kind: .attachment),
                ],
                primary: "period", kanban: "rating", calendar: "date"
            )
        ),

        Entry(
            id: "lib.brag_doc_item",
            category: .professional,
            blurb: "Brag doc / wins — things to remember when self-reviews come around.",
            keywords: ["brag", "win", "accomplishment", "self review"],
            template: makeType(
                id: "BragDocItem", name: "Win", plural: "Brag Doc",
                image: "trophy", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Win", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Category", [
                        ("Shipped", "#3FB950"), ("Saved time / money", "#9D4DCC"),
                        ("Mentored", "#3FA9F5"), ("Improved process", "#E8A93B"),
                        ("Recognition", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Impact", kind: .richText),
                    FieldDef.make(name: "Evidence / link", kind: .url),
                    FieldDef.make(name: "Who recognized it", kind: .link),
                ],
                primary: "win", kanban: "category", calendar: "date"
            )
        ),

        Entry(
            id: "lib.conference",
            category: .professional,
            blurb: "Conferences attended — talks, contacts made, takeaways.",
            keywords: ["conference", "event", "summit", "expo"],
            template: makeType(
                id: "Conference", name: "Conference", plural: "Conferences",
                image: "person.3.sequence", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Start", kind: .date),
                    FieldDef.make(name: "End", kind: .date),
                    selectField("Mode", [
                        ("In person", "#3FB950"), ("Virtual", "#3FA9F5"),
                        ("Hybrid", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Sessions to revisit", kind: .longText),
                    FieldDef.make(name: "Contacts made", kind: .link),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "name", kanban: "mode", calendar: "start"
            )
        ),

        Entry(
            id: "lib.talk_given",
            category: .professional,
            blurb: "Talks / presentations you've given — venue, topic, slides.",
            keywords: ["talk", "presentation", "speaker", "slides"],
            template: makeType(
                id: "TalkGiven", name: "Talk", plural: "Talks Given",
                image: "mic.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Venue / event", kind: .text),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Audience size", kind: .number),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    selectField("Type", [
                        ("Lightning", "#3FA9F5"), ("Talk", "#9D4DCC"),
                        ("Keynote", "#E8A93B"), ("Workshop", "#3FB950"),
                        ("Panel", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Slides", kind: .attachment),
                    FieldDef.make(name: "Recording URL", kind: .url),
                    FieldDef.make(name: "Reflections", kind: .richText),
                ],
                primary: "title", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.mentee",
            category: .professional,
            blurb: "People you mentor — focus area, cadence, where they're going.",
            keywords: ["mentee", "mentorship", "coach", "junior"],
            template: makeType(
                id: "Mentee", name: "Mentee", plural: "Mentees",
                image: "person.fill.questionmark", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Focus area", kind: .text),
                    selectField("Cadence", [
                        ("Weekly", "#3FA9F5"), ("Biweekly", "#9D4DCC"),
                        ("Monthly", "#E8A93B"), ("As-needed", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Paused", "#E8A93B"),
                        ("Graduated", "#9D4DCC"), ("Ended", "#666666"),
                    ]),
                    FieldDef.make(name: "Session log", kind: .noteLog),
                ],
                primary: "person", kanban: "status", calendar: "started"
            )
        ),

        Entry(
            id: "lib.incident",
            category: .professional,
            blurb: "Incidents / postmortems — what broke, blast radius, what we changed.",
            keywords: ["incident", "postmortem", "outage", "sev", "rca"],
            template: makeType(
                id: "Incident", name: "Incident", plural: "Incidents",
                image: "exclamationmark.bubble", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Summary", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Severity", [
                        ("Sev 1", "#D14B5C"), ("Sev 2", "#E8A93B"),
                        ("Sev 3", "#3FA9F5"), ("Sev 4", "#666666"),
                    ]),
                    FieldDef.make(name: "Detected by", kind: .text),
                    FieldDef.make(name: "TTD (min)", kind: .number),
                    FieldDef.make(name: "TTR (min)", kind: .number),
                    FieldDef.make(name: "Customer impact", kind: .longText),
                    FieldDef.make(name: "Root cause", kind: .richText),
                    FieldDef.make(name: "Action items", kind: .longText),
                    selectField("Status", [
                        ("Active", "#D14B5C"), ("Mitigated", "#E8A93B"),
                        ("Resolved", "#3FA9F5"), ("Reviewed", "#3FB950"),
                    ]),
                ],
                primary: "summary", kanban: "severity", calendar: "date"
            )
        ),

        Entry(
            id: "lib.tech_debt",
            category: .professional,
            blurb: "Tech debt items — area, pain level, planned fix.",
            keywords: ["tech debt", "refactor", "cleanup", "engineering"],
            template: makeType(
                id: "TechDebt", name: "Item", plural: "Tech Debt",
                image: "minus.diamond", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Area / repo", kind: .text),
                    selectField("Pain", [
                        ("Annoying", "#3FA9F5"), ("Painful", "#E8A93B"),
                        ("Blocking", "#D14B5C"),
                    ]),
                    selectField("Effort", [
                        ("Small", "#3FB950"), ("Medium", "#9D4DCC"),
                        ("Large", "#E8A93B"), ("Project", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Logged", "#888888"), ("Triaged", "#3FA9F5"),
                        ("In progress", "#9D4DCC"), ("Done", "#3FB950"),
                        ("Wontfix", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "description", kanban: "status"
            )
        ),

        Entry(
            id: "lib.feature_request",
            category: .professional,
            blurb: "Feature requests from customers — request, requester, status.",
            keywords: ["feature", "request", "feedback", "product"],
            template: makeType(
                id: "FeatureRequest", name: "Request", plural: "Feature Requests",
                image: "lightbulb.max", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Request", kind: .text, required: true),
                    FieldDef.make(name: "Requester", kind: .link),
                    FieldDef.make(name: "Submitted", kind: .date),
                    FieldDef.make(name: "Demand count", kind: .number),
                    selectField("Status", [
                        ("New", "#888888"), ("Under review", "#3FA9F5"),
                        ("Planned", "#9D4DCC"), ("Building", "#E8A93B"),
                        ("Shipped", "#3FB950"), ("Declined", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Rationale", kind: .richText),
                ],
                primary: "request", kanban: "status", calendar: "submitted"
            )
        ),

        Entry(
            id: "lib.bug_report",
            category: .professional,
            blurb: "Bug reports — repro, severity, status, assignee.",
            keywords: ["bug", "issue", "defect", "tracker"],
            template: makeType(
                id: "BugReport", name: "Bug", plural: "Bugs",
                image: "ladybug", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Reported", kind: .date),
                    selectField("Severity", [
                        ("Critical", "#D14B5C"), ("High", "#E8A93B"),
                        ("Medium", "#3FA9F5"), ("Low", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Open", "#D14B5C"), ("Triaged", "#E8A93B"),
                        ("In progress", "#9D4DCC"), ("Fixed", "#3FB950"),
                        ("Closed", "#666666"), ("Wontfix", "#888888"),
                    ]),
                    FieldDef.make(name: "Steps to reproduce", kind: .longText),
                    FieldDef.make(name: "Expected vs actual", kind: .longText),
                    FieldDef.make(name: "Assignee", kind: .link),
                    FieldDef.make(name: "Reporter", kind: .link),
                ],
                primary: "title", kanban: "status", calendar: "reported"
            )
        ),

        Entry(
            id: "lib.recommendation_letter",
            category: .professional,
            blurb: "Recommendations / references — who, what for, status.",
            keywords: ["recommendation", "reference", "letter", "linkedin"],
            template: makeType(
                id: "Recommendation", name: "Recommendation", plural: "Recommendations",
                image: "hand.thumbsup", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    selectField("Direction", [
                        ("I gave them one", "#3FA9F5"), ("They gave me one", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Purpose", kind: .text, description: "job, school, etc."),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Status", [
                        ("Asked", "#E8A93B"), ("In progress", "#3FA9F5"),
                        ("Submitted", "#9D4DCC"), ("Posted", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Document", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "person", kanban: "status", calendar: "date"
            )
        ),

        // MARK: - Learning & Reference (extended)

        Entry(
            id: "lib.tutorial",
            category: .learning,
            blurb: "Tutorials followed — topic, source, completed, key learnings.",
            keywords: ["tutorial", "guide", "howto", "walkthrough"],
            template: makeType(
                id: "Tutorial", name: "Tutorial", plural: "Tutorials",
                image: "list.number", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "URL", kind: .url),
                    selectField("Topic", [
                        ("Coding", "#9D4DCC"), ("Design", "#3FA9F5"),
                        ("Craft", "#E8A93B"), ("Life skill", "#3FB950"),
                        ("Cooking", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Saved", "#888888"), ("Doing", "#3FA9F5"),
                        ("Done", "#3FB950"), ("Quit", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Key takeaways", kind: .richText),
                ],
                primary: "title", kanban: "status"
            )
        ),

        Entry(
            id: "lib.read_later",
            category: .learning,
            blurb: "Saved articles to read later — URL, source, why bookmarked.",
            keywords: ["read later", "instapaper", "pocket", "article", "bookmark"],
            template: makeType(
                id: "ReadLater", name: "Article", plural: "Read Later",
                image: "bookmark", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Author", kind: .text),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Saved", kind: .date),
                    selectField("Status", [
                        ("Unread", "#888888"), ("In progress", "#3FA9F5"),
                        ("Read", "#3FB950"), ("Skimmed", "#9D4DCC"),
                        ("Archived", "#666666"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Highlights / quotes", kind: .richText),
                ],
                primary: "title", kanban: "status", calendar: "saved"
            )
        ),

        Entry(
            id: "lib.coding_challenge",
            category: .learning,
            blurb: "LeetCode / coding problems — difficulty, time, approach.",
            keywords: ["leetcode", "coding", "algorithm", "interview", "challenge"],
            template: makeType(
                id: "CodingChallenge", name: "Problem", plural: "Coding Challenges",
                image: "curlybraces", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Problem", kind: .text, required: true),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Problem #", kind: .text),
                    selectField("Difficulty", [
                        ("Easy", "#3FB950"), ("Medium", "#E8A93B"),
                        ("Hard", "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Attempted", "#E8A93B"), ("Solved", "#3FB950"),
                        ("Skipped", "#666666"), ("Gave up", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Time taken (min)", kind: .number),
                    FieldDef.make(name: "Approach", kind: .longText),
                    FieldDef.make(name: "Solved on", kind: .date),
                ],
                primary: "problem", kanban: "status", calendar: "solved_on"
            )
        ),

        Entry(
            id: "lib.practice_session",
            category: .learning,
            blurb: "Practice sessions — instrument, sport, skill — duration, focus.",
            keywords: ["practice", "training", "session", "instrument", "skill"],
            template: makeType(
                id: "PracticeSession", name: "Session", plural: "Practice",
                image: "metronome", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Skill", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "What I worked on", kind: .longText),
                    selectField("Quality", [
                        ("Awful", "#D14B5C"), ("Going through motions", "#E8A93B"),
                        ("Solid", "#3FA9F5"), ("Breakthrough", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "skill", kanban: "quality", calendar: "date"
            )
        ),

        Entry(
            id: "lib.glossary_term",
            category: .learning,
            blurb: "Personal glossary — term, domain, definition, examples.",
            keywords: ["glossary", "term", "definition", "vocabulary", "jargon"],
            template: makeType(
                id: "GlossaryTerm", name: "Term", plural: "Glossary",
                image: "character.book.closed.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Term", kind: .text, required: true),
                    FieldDef.make(name: "Domain", kind: .text),
                    FieldDef.make(name: "Definition", kind: .richText),
                    FieldDef.make(name: "Example", kind: .longText),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Related terms", kind: .text),
                ],
                primary: "term"
            )
        ),

        Entry(
            id: "lib.quote",
            category: .learning,
            blurb: "Quotes worth keeping — author, source, why it lands.",
            keywords: ["quote", "wisdom", "saying", "epigraph"],
            template: makeType(
                id: "Quote", name: "Quote", plural: "Quotes",
                image: "quote.opening", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Quote", kind: .longText, required: true),
                    FieldDef.make(name: "Author", kind: .text),
                    FieldDef.make(name: "Source", kind: .text),
                    selectField("Theme", [
                        ("Stoicism", "#9D4DCC"), ("Wisdom", "#E8A93B"),
                        ("Humor", "#F08C2E"), ("Love", "#D14B5C"),
                        ("Work", "#3FA9F5"), ("Life", "#3FB950"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Date saved", kind: .date),
                    FieldDef.make(name: "Why it lands", kind: .longText),
                ],
                primary: "author", kanban: "theme", calendar: "date_saved"
            )
        ),

        Entry(
            id: "lib.lesson_learned",
            category: .learning,
            blurb: "Lessons learned — what happened, what I'd do differently next time.",
            keywords: ["lesson", "learning", "retrospective", "wisdom"],
            template: makeType(
                id: "LessonLearned", name: "Lesson", plural: "Lessons Learned",
                image: "graduationcap.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Lesson", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Area", [
                        ("Work", "#3FA9F5"), ("Relationships", "#9D4DCC"),
                        ("Money", "#E8A93B"), ("Health", "#3FB950"),
                        ("Personal", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "What happened", kind: .richText),
                    FieldDef.make(name: "What I'd do differently", kind: .richText),
                ],
                primary: "lesson", kanban: "area", calendar: "date"
            )
        ),

        Entry(
            id: "lib.mental_model",
            category: .learning,
            blurb: "Mental models / heuristics — name, summary, when to apply.",
            keywords: ["mental model", "heuristic", "framework", "thinking"],
            template: makeType(
                id: "MentalModel", name: "Model", plural: "Mental Models",
                image: "brain", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Originator", kind: .text),
                    selectField("Domain", [
                        ("Decision", "#9D4DCC"), ("Systems", "#3FA9F5"),
                        ("Psychology", "#E8A93B"), ("Economics", "#3FB950"),
                        ("Engineering", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Summary", kind: .richText),
                    FieldDef.make(name: "When to apply", kind: .longText),
                    FieldDef.make(name: "Example", kind: .longText),
                ],
                primary: "name", kanban: "domain"
            )
        ),

        Entry(
            id: "lib.flashcard_deck",
            category: .learning,
            blurb: "Flashcard / Anki decks — name, source, cards, review cadence.",
            keywords: ["flashcard", "anki", "spaced repetition", "memorize"],
            template: makeType(
                id: "FlashcardDeck", name: "Deck", plural: "Flashcard Decks",
                image: "rectangle.on.rectangle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Source / app", kind: .text),
                    FieldDef.make(name: "Cards in deck", kind: .number),
                    FieldDef.make(name: "Created", kind: .date),
                    FieldDef.make(name: "Last reviewed", kind: .date),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Paused", "#E8A93B"),
                        ("Mastered", "#9D4DCC"), ("Retired", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "name", kanban: "status", calendar: "last_reviewed"
            )
        ),

        Entry(
            id: "lib.skill_to_learn",
            category: .learning,
            blurb: "Skills you want to develop — current level, target, plan.",
            keywords: ["skill", "learn", "develop", "goal"],
            template: makeType(
                id: "SkillToLearn", name: "Skill", plural: "Skills",
                image: "chart.line.uptrend.xyaxis.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Skill", kind: .text, required: true),
                    selectField("Current level", [
                        ("Curious", "#888888"), ("Beginner", "#3FA9F5"),
                        ("Intermediate", "#9D4DCC"), ("Advanced", "#3FB950"),
                        ("Expert", "#E8A93B"),
                    ]),
                    selectField("Target level", [
                        ("Functional", "#3FA9F5"), ("Solid", "#9D4DCC"),
                        ("Strong", "#3FB950"), ("Expert", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Why", kind: .longText),
                    FieldDef.make(name: "Plan", kind: .richText),
                    FieldDef.make(name: "Progress log", kind: .noteLog),
                ],
                primary: "skill", kanban: "current_level"
            )
        ),

        // MARK: - Relationships (extended)

        Entry(
            id: "lib.important_date",
            category: .relationships,
            blurb: "Birthdays, anniversaries, important dates — who, what, recurring.",
            keywords: ["birthday", "anniversary", "date", "annual", "remember"],
            template: makeType(
                id: "ImportantDate", name: "Date", plural: "Important Dates",
                image: "calendar.badge.clock", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Person", kind: .link),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Type", [
                        ("Birthday", "#9D4DCC"), ("Anniversary", "#D14B5C"),
                        ("Wedding", "#3FA9F5"), ("Death day", "#666666"),
                        ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Recurring?", kind: .boolean),
                    FieldDef.make(name: "Year (if known)", kind: .number),
                    FieldDef.make(name: "Gift ideas", kind: .link),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "person", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.celebration_attended",
            category: .relationships,
            blurb: "Weddings, parties, big events you went to — when, where, gift given.",
            keywords: ["wedding", "party", "celebration", "event", "shower"],
            template: makeType(
                id: "Celebration", name: "Event", plural: "Celebrations",
                image: "balloon", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Event", kind: .text, required: true),
                    selectField("Type", [
                        ("Wedding", "#9D4DCC"), ("Birthday", "#F08C2E"),
                        ("Baby shower", "#3FA9F5"), ("Anniversary", "#D14B5C"),
                        ("Graduation", "#3FB950"), ("Retirement", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "For whom", kind: .link),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Gift given", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Memory", kind: .richText),
                ],
                primary: "event", kanban: "type", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.date_night",
            category: .relationships,
            blurb: "Date nights / outings with a partner — where, vibe, plan again?",
            keywords: ["date", "partner", "spouse", "outing", "couple"],
            template: makeType(
                id: "DateNight", name: "Date", plural: "Date Nights",
                image: "heart.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "What we did", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Repeat-worthy?", kind: .boolean),
                    FieldDef.make(name: "Memory", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "what_we_did", calendar: "when", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.family_tree",
            category: .relationships,
            blurb: "Family tree / ancestor records — relation, dates, where they lived.",
            keywords: ["family", "ancestor", "genealogy", "tree", "history"],
            template: makeType(
                id: "Ancestor", name: "Ancestor", plural: "Family Tree",
                image: "person.crop.square.filled.and.at.rectangle", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Relation to me", kind: .text),
                    FieldDef.make(name: "Birth date", kind: .date),
                    FieldDef.make(name: "Death date", kind: .date),
                    FieldDef.make(name: "Birthplace", kind: .text),
                    FieldDef.make(name: "Mother", kind: .link),
                    FieldDef.make(name: "Father", kind: .link),
                    FieldDef.make(name: "Spouse", kind: .link),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", calendar: "birth_date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.family_story",
            category: .relationships,
            blurb: "Family stories worth preserving — who, what, when (roughly), source.",
            keywords: ["family", "story", "history", "oral", "tradition"],
            template: makeType(
                id: "FamilyStory", name: "Story", plural: "Family Stories",
                image: "text.book.closed.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Era (approximate)", kind: .text),
                    FieldDef.make(name: "Who it's about", kind: .link),
                    FieldDef.make(name: "Source (who told you)", kind: .link),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Audio recording", kind: .attachment),
                ],
                primary: "title"
            )
        ),

        Entry(
            id: "lib.letter_to_write",
            category: .relationships,
            blurb: "Letters / cards you want to send — recipient, occasion, draft.",
            keywords: ["letter", "card", "postcard", "snail mail"],
            template: makeType(
                id: "LetterToWrite", name: "Letter", plural: "Letters",
                image: "envelope.badge.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Recipient", kind: .link, required: true),
                    selectField("Occasion", [
                        ("Birthday", "#9D4DCC"), ("Thank you", "#3FB950"),
                        ("Sympathy", "#666666"), ("Congrats", "#F08C2E"),
                        ("Just because", "#E8A93B"), ("Holiday", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Send by", kind: .date),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Drafted", "#3FA9F5"),
                        ("Written", "#9D4DCC"), ("Mailed", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Draft / notes", kind: .richText),
                ],
                primary: "recipient", kanban: "status", calendar: "send_by"
            )
        ),

        Entry(
            id: "lib.kindness",
            category: .relationships,
            blurb: "Kind acts you've done or received — small things worth remembering.",
            keywords: ["kindness", "gratitude", "compliment", "act"],
            template: makeType(
                id: "KindnessEntry", name: "Act", plural: "Kindness Log",
                image: "hands.sparkles", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "What happened", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Direction", [
                        ("I did", "#3FA9F5"), ("I received", "#9D4DCC"),
                        ("I witnessed", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Person involved", kind: .link),
                    FieldDef.make(name: "Detail", kind: .richText),
                ],
                primary: "what_happened", kanban: "direction", calendar: "date"
            )
        ),

        Entry(
            id: "lib.conflict_resolved",
            category: .relationships,
            blurb: "Conflict / disagreement notes — what, with whom, how it resolved.",
            keywords: ["conflict", "argument", "resolution", "disagreement"],
            template: makeType(
                id: "Conflict", name: "Conflict", plural: "Conflicts",
                image: "exclamationmark.bubble.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Topic", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "With whom", kind: .link),
                    selectField("Status", [
                        ("Active", "#D14B5C"), ("Cooling off", "#E8A93B"),
                        ("Resolved", "#3FB950"), ("Tabled", "#666666"),
                        ("Unresolved", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "What I felt", kind: .longText),
                    FieldDef.make(name: "What they felt", kind: .longText),
                    FieldDef.make(name: "Resolution", kind: .richText),
                ],
                primary: "topic", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.holiday_card",
            category: .relationships,
            blurb: "Holiday card list — sent, received, year-over-year.",
            keywords: ["holiday", "card", "christmas", "list"],
            template: makeType(
                id: "HolidayCard", name: "Recipient", plural: "Holiday Cards",
                image: "envelope.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Recipient", kind: .link, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Sent?", kind: .boolean),
                    FieldDef.make(name: "Date sent", kind: .date),
                    FieldDef.make(name: "Received from them?", kind: .boolean),
                    selectField("Cadence", [
                        ("Every year", "#3FB950"), ("Most years", "#3FA9F5"),
                        ("Sometimes", "#E8A93B"), ("First time", "#9D4DCC"),
                        ("Drop", "#D14B5C"),
                    ]),
                ],
                primary: "recipient", kanban: "cadence", calendar: "date_sent"
            )
        ),

        Entry(
            id: "lib.family_recipe",
            category: .relationships,
            blurb: "Family recipes passed down — who made it, story behind it.",
            keywords: ["family recipe", "heirloom", "grandmother", "tradition"],
            template: makeType(
                id: "FamilyRecipe", name: "Recipe", plural: "Family Recipes",
                image: "books.vertical", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "From (who)", kind: .link),
                    FieldDef.make(name: "Origin region", kind: .text),
                    FieldDef.make(name: "Generation", kind: .text),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Ingredients", kind: .longText),
                    FieldDef.make(name: "Method", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", gallery: "photo"
            )
        ),

        // MARK: - Unusual & Niche (extended)

        Entry(
            id: "lib.mushroom_foraging",
            category: .unusual,
            blurb: "Mushrooms found — species, location, edible status, photo.",
            keywords: ["mushroom", "foraging", "mycology", "fungi"],
            template: makeType(
                id: "MushroomFind", name: "Find", plural: "Mushroom Finds",
                image: "leaf.arrow.circlepath", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Substrate / host", kind: .text),
                    selectField("Edibility", [
                        ("Choice edible", "#3FB950"), ("Edible", "#3FA9F5"),
                        ("Inedible", "#666666"), ("Toxic", "#E8A93B"),
                        ("Deadly", "#D14B5C"), ("Unknown", "#888888"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes / ID confidence", kind: .longText),
                ],
                primary: "species", kanban: "edibility", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.wild_plant",
            category: .unusual,
            blurb: "Wild plants identified — species, location, season.",
            keywords: ["plant", "wild", "botany", "foraging", "id"],
            template: makeType(
                id: "WildPlant", name: "Plant", plural: "Wild Plants",
                image: "leaf.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Common name", kind: .text),
                    FieldDef.make(name: "Date observed", kind: .date),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Type", [
                        ("Tree", "#3FB950"), ("Shrub", "#9D4DCC"),
                        ("Herb / forb", "#E8A93B"), ("Grass", "#F08C2E"),
                        ("Vine", "#666666"), ("Fern", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Use (food/medicine/no)", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species", kanban: "type", calendar: "date_observed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.synchronicity",
            category: .unusual,
            blurb: "Synchronicities / coincidences worth noting.",
            keywords: ["synchronicity", "coincidence", "jung", "meaningful"],
            template: makeType(
                id: "Synchronicity", name: "Event", plural: "Synchronicities",
                image: "infinity", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "What happened", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Intensity", [
                        ("Mild", "#3FA9F5"), ("Notable", "#9D4DCC"),
                        ("Eerie", "#E8A93B"), ("Wow", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Context", kind: .richText),
                    FieldDef.make(name: "What I was thinking about", kind: .longText),
                ],
                primary: "what_happened", kanban: "intensity", calendar: "date"
            )
        ),

        Entry(
            id: "lib.lucid_dream",
            category: .unusual,
            blurb: "Lucid dreams — clarity, technique used, what you did.",
            keywords: ["lucid dream", "wbtb", "wild", "dream control"],
            template: makeType(
                id: "LucidDream", name: "Dream", plural: "Lucid Dreams",
                image: "moon.zzz", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Title", kind: .text),
                    selectField("Clarity", [
                        ("Dim awareness", "#888888"), ("Aware", "#3FA9F5"),
                        ("Fully lucid", "#9D4DCC"), ("Vivid superlucid", "#E8A93B"),
                    ]),
                    selectField("Induction", [
                        ("Spontaneous", "#888888"), ("WBTB", "#3FA9F5"),
                        ("WILD", "#9D4DCC"), ("MILD", "#E8A93B"),
                        ("Reality check", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "What I did in dream", kind: .longText),
                    FieldDef.make(name: "Recall", kind: .richText),
                ],
                primary: "title", kanban: "clarity", calendar: "date"
            )
        ),

        Entry(
            id: "lib.fortune_cookie",
            category: .unusual,
            blurb: "Fortune cookie messages collected over the years.",
            keywords: ["fortune", "cookie", "message", "chinese food"],
            template: makeType(
                id: "FortuneCookie", name: "Fortune", plural: "Fortune Cookies",
                image: "circle.bottomhalf.filled", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Fortune", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Lucky numbers", kind: .text),
                    FieldDef.make(name: "Came true?", kind: .boolean),
                    FieldDef.make(name: "Restaurant", kind: .text),
                ],
                primary: "fortune", calendar: "date"
            )
        ),

        Entry(
            id: "lib.synesthesia",
            category: .unusual,
            blurb: "Synesthesia notes — what crossed senses, your perception.",
            keywords: ["synesthesia", "perception", "cross modal"],
            template: makeType(
                id: "SynesthesiaEntry", name: "Entry", plural: "Synesthesia",
                image: "eye.trianglebadge.exclamationmark", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Trigger", kind: .text, required: true),
                    selectField("Type", [
                        ("Grapheme→color", "#9D4DCC"), ("Sound→color", "#3FA9F5"),
                        ("Taste→shape", "#E8A93B"), ("Smell→color", "#F08C2E"),
                        ("Number→spatial", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Perceived as", kind: .longText),
                    FieldDef.make(name: "Date noticed", kind: .date),
                ],
                primary: "trigger", kanban: "type", calendar: "date_noticed"
            )
        ),

        Entry(
            id: "lib.crystal",
            category: .unusual,
            blurb: "Crystal collection — type, intention, source, photo.",
            keywords: ["crystal", "gemstone", "metaphysical", "healing"],
            template: makeType(
                id: "Crystal", name: "Crystal", plural: "Crystals",
                image: "diamond.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Stone", kind: .text, required: true),
                    selectField("Type", [
                        ("Quartz", "#888888"), ("Amethyst", "#9D4DCC"),
                        ("Rose quartz", "#E8A0B5"), ("Citrine", "#E8A93B"),
                        ("Obsidian", "#666666"), ("Selenite", "#F0E68C"),
                        ("Other", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Intention / use", kind: .text),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "stone", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.snake_encounter",
            category: .unusual,
            blurb: "Snake / wildlife encounters — species, situation, outcome.",
            keywords: ["snake", "wildlife", "encounter", "outdoors"],
            template: makeType(
                id: "WildlifeEncounter", name: "Encounter", plural: "Wildlife Encounters",
                image: "ant", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    selectField("Outcome", [
                        ("Walked away", "#3FB950"), ("Photographed", "#3FA9F5"),
                        ("Relocated", "#9D4DCC"), ("Spooked", "#E8A93B"),
                        ("Bit/injured", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species", kanban: "outcome", calendar: "when", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.phenology",
            category: .unusual,
            blurb: "Phenology — first robin of spring, first frost, leaf-out dates.",
            keywords: ["phenology", "season", "first", "spring", "nature"],
            template: makeType(
                id: "PhenologyEvent", name: "Event", plural: "Phenology",
                image: "leaf.circle.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Event", kind: .text, required: true),
                    FieldDef.make(name: "Date observed", kind: .date, required: true),
                    selectField("Season marker", [
                        ("First spring", "#3FB950"), ("Peak spring", "#9D4DCC"),
                        ("First fall", "#E8A93B"), ("First frost", "#3FA9F5"),
                        ("First snow", "#FFFFFF"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Year", kind: .number),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "event", kanban: "season_marker", calendar: "date_observed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.mishap",
            category: .unusual,
            blurb: "The 'I'm an idiot' log — mishaps, dumb moments, things to laugh at later.",
            keywords: ["mishap", "blunder", "dumb", "idiot"],
            template: makeType(
                id: "Mishap", name: "Mishap", plural: "Mishap Log",
                image: "exclamationmark.triangle.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "What happened", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Severity", [
                        ("Funny", "#3FB950"), ("Annoying", "#E8A93B"),
                        ("Costly", "#F08C2E"), ("Yikes", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Lesson", kind: .longText),
                ],
                primary: "what_happened", kanban: "severity", calendar: "date"
            )
        ),

        Entry(
            id: "lib.joke",
            category: .unusual,
            blurb: "Jokes worth remembering — setup, punchline, who told it.",
            keywords: ["joke", "humor", "pun", "comedy"],
            template: makeType(
                id: "Joke", name: "Joke", plural: "Jokes",
                image: "face.smiling.inverse", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Setup", kind: .text, required: true),
                    FieldDef.make(name: "Punchline", kind: .longText),
                    selectField("Style", [
                        ("Pun", "#E8A93B"), ("One-liner", "#3FA9F5"),
                        ("Story", "#9D4DCC"), ("Observational", "#3FB950"),
                        ("Dad joke", "#F08C2E"), ("Dark", "#666666"),
                    ]),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                ],
                primary: "setup", kanban: "style"
            )
        ),

        Entry(
            id: "lib.lost_item",
            category: .unusual,
            blurb: "Lost items — what, last seen, found?",
            keywords: ["lost", "missing", "find", "item"],
            template: makeType(
                id: "LostItem", name: "Item", plural: "Lost & Found",
                image: "questionmark.app.dashed", color: "#888888",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Last seen", kind: .dateTime),
                    FieldDef.make(name: "Where I think it is", kind: .text),
                    selectField("Status", [
                        ("Missing", "#D14B5C"), ("Found", "#3FB950"),
                        ("Replaced", "#9D4DCC"), ("Gave up", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "status", calendar: "last_seen"
            )
        ),

        Entry(
            id: "lib.sleep_paralysis",
            category: .unusual,
            blurb: "Sleep paralysis episodes — duration, hallucinations, what helped.",
            keywords: ["sleep paralysis", "hypnagogia", "night terror"],
            template: makeType(
                id: "SleepParalysis", name: "Episode", plural: "Sleep Paralysis",
                image: "moon.dust", color: "#666666",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Time of night", kind: .text),
                    FieldDef.make(name: "Duration (sec)", kind: .number),
                    selectField("Hallucinations", [
                        ("None", "#888888"), ("Auditory", "#3FA9F5"),
                        ("Visual", "#9D4DCC"), ("Tactile (pressure)", "#E8A93B"),
                        ("Multiple", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Recall", kind: .richText),
                    FieldDef.make(name: "What helped break it", kind: .text),
                ],
                primary: "date", kanban: "hallucinations", calendar: "date"
            )
        ),

        Entry(
            id: "lib.aha_moment",
            category: .unusual,
            blurb: "Aha moments — sudden insights, breakthroughs in understanding.",
            keywords: ["aha", "insight", "epiphany", "realization"],
            template: makeType(
                id: "AhaMoment", name: "Moment", plural: "Aha Moments",
                image: "lightbulb.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Insight", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Triggered by", [
                        ("Book", "#9D4DCC"), ("Conversation", "#3FA9F5"),
                        ("Walk", "#3FB950"), ("Shower", "#E8A93B"),
                        ("Sleep", "#666666"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Context", kind: .richText),
                    FieldDef.make(name: "Implication", kind: .longText),
                ],
                primary: "insight", kanban: "triggered_by", calendar: "date"
            )
        ),

        // MARK: - Final batch — variety pack across categories

        Entry(
            id: "lib.work_log",
            category: .productivity,
            blurb: "End-of-day work log — what you actually got done.",
            keywords: ["work log", "done list", "diary", "shipped"],
            template: makeType(
                id: "WorkLog", name: "Day", plural: "Work Log",
                image: "list.bullet.clipboard", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Shipped today", kind: .longText),
                    FieldDef.make(name: "Hours focused", kind: .number),
                    FieldDef.make(name: "Hours in meetings", kind: .number),
                    selectField("Day type", [
                        ("Maker", "#3FB950"), ("Manager", "#3FA9F5"),
                        ("Mixed", "#9D4DCC"), ("Admin", "#E8A93B"),
                        ("Day off", "#666666"),
                    ]),
                    FieldDef.make(name: "Tomorrow priorities", kind: .longText),
                ],
                primary: "date", kanban: "day_type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.quarterly_goal",
            category: .productivity,
            blurb: "Quarterly goals — area, target, mid-quarter check-in.",
            keywords: ["quarterly", "goal", "12-week", "quarter"],
            template: makeType(
                id: "QuarterlyGoal", name: "Goal", plural: "Quarterly Goals",
                image: "calendar.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Goal", kind: .text, required: true),
                    FieldDef.make(name: "Year", kind: .number),
                    selectField("Quarter", [
                        ("Q1", "#3FB950"), ("Q2", "#3FA9F5"),
                        ("Q3", "#9D4DCC"), ("Q4", "#E8A93B"),
                    ]),
                    selectField("Area", [
                        ("Health", "#3FB950"), ("Career", "#3FA9F5"),
                        ("Finance", "#E8A93B"), ("Learning", "#9D4DCC"),
                        ("Relationships", "#D14B5C"), ("Creative", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Progress %", kind: .number),
                    FieldDef.make(name: "Mid-quarter check", kind: .richText),
                    FieldDef.make(name: "End-of-quarter reflection", kind: .richText),
                ],
                primary: "goal", kanban: "area"
            )
        ),

        Entry(
            id: "lib.appliance",
            category: .home,
            blurb: "Major appliances — make, model, age, expected lifespan.",
            keywords: ["appliance", "fridge", "washer", "dryer", "hvac"],
            template: makeType(
                id: "Appliance", name: "Appliance", plural: "Appliances",
                image: "refrigerator", color: "#666666",
                fields: [
                    FieldDef.make(name: "Appliance", kind: .text, required: true),
                    FieldDef.make(name: "Make", kind: .text),
                    FieldDef.make(name: "Model", kind: .text),
                    FieldDef.make(name: "Serial", kind: .text),
                    FieldDef.make(name: "Year installed", kind: .number),
                    FieldDef.make(name: "Expected life (yr)", kind: .number),
                    FieldDef.make(name: "Filter / consumable", kind: .text),
                    selectField("Status", [
                        ("Working", "#3FB950"), ("Quirky", "#E8A93B"),
                        ("Needs service", "#F08C2E"), ("Replace soon", "#D14B5C"),
                        ("Retired", "#666666"),
                    ]),
                    FieldDef.make(name: "Service log", kind: .noteLog),
                ],
                primary: "appliance", kanban: "status"
            )
        ),

        Entry(
            id: "lib.gym_membership",
            category: .health,
            blurb: "Gym & studio memberships — facility, dues, contract end.",
            keywords: ["gym", "membership", "studio", "fitness", "dues"],
            template: makeType(
                id: "GymMembership", name: "Membership", plural: "Gym Memberships",
                image: "figure.strengthtraining.traditional", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Facility", kind: .text, required: true),
                    selectField("Type", [
                        ("Big-box gym", "#3FA9F5"), ("Boutique", "#9D4DCC"),
                        ("Crossfit", "#E8A93B"), ("Yoga / pilates", "#3FB950"),
                        ("Climbing", "#F08C2E"), ("Pool", "#666666"),
                    ]),
                    FieldDef.make(name: "Monthly dues", kind: .number),
                    FieldDef.make(name: "Joined", kind: .date),
                    FieldDef.make(name: "Contract end", kind: .date),
                    FieldDef.make(name: "Last visit", kind: .date),
                    FieldDef.make(name: "Visits this month", kind: .number),
                ],
                primary: "facility", kanban: "type", calendar: "contract_end"
            )
        ),

        Entry(
            id: "lib.running_log",
            category: .health,
            blurb: "Runs — distance, pace, route, how it felt.",
            keywords: ["running", "run", "5k", "marathon", "pace"],
            template: makeType(
                id: "RunningLog", name: "Run", plural: "Running Log",
                image: "figure.run.circle", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Distance (mi)", kind: .number, required: true),
                    FieldDef.make(name: "Time (min)", kind: .number),
                    FieldDef.make(name: "Avg pace (min/mi)", kind: .number),
                    selectField("Type", [
                        ("Easy", "#3FB950"), ("Tempo", "#3FA9F5"),
                        ("Intervals", "#9D4DCC"), ("Long", "#E8A93B"),
                        ("Race", "#D14B5C"), ("Recovery", "#666666"),
                    ]),
                    FieldDef.make(name: "Route", kind: .text),
                    FieldDef.make(name: "Felt like", kind: .longText),
                ],
                primary: "date", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.race",
            category: .health,
            blurb: "Races run — 5K, 10K, half, full, plus your finish.",
            keywords: ["race", "marathon", "half marathon", "5k", "triathlon"],
            template: makeType(
                id: "Race", name: "Race", plural: "Races",
                image: "flag.2.crossed", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Race name", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Distance", [
                        ("5K", "#3FB950"), ("10K", "#3FA9F5"),
                        ("Half marathon", "#9D4DCC"), ("Marathon", "#E8A93B"),
                        ("Ultra", "#D14B5C"), ("Triathlon", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Finish time", kind: .text),
                    FieldDef.make(name: "Place / bib #", kind: .text),
                    FieldDef.make(name: "Pace (min/mi)", kind: .number),
                    FieldDef.make(name: "PR?", kind: .boolean),
                    FieldDef.make(name: "Photo / medal", kind: .attachment),
                    FieldDef.make(name: "Race notes", kind: .richText),
                ],
                primary: "race_name", kanban: "distance", calendar: "date", gallery: "photo_medal"
            )
        ),

        Entry(
            id: "lib.dad_joke_dynamic",
            category: .unusual,
            blurb: "Father / family roles to play — who you're being today.",
            keywords: ["family", "role", "parenting", "identity"],
            template: makeType(
                id: "FamilyRole", name: "Role", plural: "Family Roles",
                image: "person.fill.viewfinder", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Role / hat", kind: .text, required: true),
                    selectField("Context", [
                        ("Parent", "#3FA9F5"), ("Spouse", "#D14B5C"),
                        ("Sibling", "#9D4DCC"), ("Child", "#E8A93B"),
                        ("Friend", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "When activated", kind: .text),
                    FieldDef.make(name: "What it demands", kind: .longText),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "role_hat", kanban: "context"
            )
        ),

        Entry(
            id: "lib.baby_milestone",
            category: .relationships,
            blurb: "Baby / kid milestones — first steps, first words, growth.",
            keywords: ["baby", "child", "milestone", "first", "parenting"],
            template: makeType(
                id: "BabyMilestone", name: "Milestone", plural: "Baby Milestones",
                image: "figure.and.child.holdinghands", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Child", kind: .link, required: true),
                    FieldDef.make(name: "Milestone", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Age (months)", kind: .number),
                    selectField("Category", [
                        ("Physical", "#3FB950"), ("Verbal", "#9D4DCC"),
                        ("Social", "#3FA9F5"), ("Cognitive", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Photo / video", kind: .attachment),
                ],
                primary: "milestone", kanban: "category", calendar: "date", gallery: "photo_video"
            )
        ),

        Entry(
            id: "lib.kid_artwork",
            category: .relationships,
            blurb: "Kids' art / school work — date, medium, story, photo.",
            keywords: ["kid", "child", "art", "school", "drawing"],
            template: makeType(
                id: "KidArtwork", name: "Artwork", plural: "Kid Artwork",
                image: "scribble.variable", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Child", kind: .link),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Medium", kind: .text),
                    FieldDef.make(name: "Story behind it", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "title", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.beer_brewed",
            category: .hobbies,
            blurb: "Homebrewed beer — recipe, OG/FG, tasting notes, batch number.",
            keywords: ["homebrew", "beer", "brewing", "batch", "wort"],
            template: makeType(
                id: "HomebrewBatch", name: "Batch", plural: "Homebrew",
                image: "drop.halffull", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Batch #", kind: .number, required: true),
                    FieldDef.make(name: "Recipe name", kind: .text),
                    selectField("Style", [
                        ("IPA", "#E8A93B"), ("Lager", "#F0E68C"),
                        ("Stout", "#3D2B1F"), ("Sour", "#D14B5C"),
                        ("Wheat", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Brew date", kind: .date, required: true),
                    FieldDef.make(name: "OG", kind: .number),
                    FieldDef.make(name: "FG", kind: .number),
                    FieldDef.make(name: "ABV %", kind: .number),
                    FieldDef.make(name: "IBU", kind: .number),
                    FieldDef.make(name: "Bottling date", kind: .date),
                    FieldDef.make(name: "Tasting notes", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "recipe_name", kanban: "style", calendar: "brew_date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.gun_owned",
            category: .hobbies,
            blurb: "Firearms owned (legally) — caliber, model, serial, last fired.",
            keywords: ["firearm", "gun", "rifle", "handgun", "caliber"],
            template: makeType(
                id: "Firearm", name: "Firearm", plural: "Firearms",
                image: "scope", color: "#666666",
                fields: [
                    FieldDef.make(name: "Model", kind: .text, required: true),
                    FieldDef.make(name: "Manufacturer", kind: .text),
                    FieldDef.make(name: "Caliber", kind: .text),
                    selectField("Type", [
                        ("Handgun", "#9D4DCC"), ("Rifle", "#3FA9F5"),
                        ("Shotgun", "#E8A93B"), ("Antique", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Serial", kind: .text),
                    FieldDef.make(name: "Purchased", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Last fired", kind: .date),
                    FieldDef.make(name: "Storage location", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "model", kanban: "type", calendar: "last_fired"
            )
        ),

        Entry(
            id: "lib.kayak_paddle",
            category: .travel,
            blurb: "Kayak / canoe / SUP paddles — water, distance, conditions.",
            keywords: ["kayak", "canoe", "sup", "paddle", "water"],
            template: makeType(
                id: "PaddleTrip", name: "Paddle", plural: "Paddling",
                image: "water.waves", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Where", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Distance (mi)", kind: .number),
                    FieldDef.make(name: "Time (min)", kind: .number),
                    selectField("Craft", [
                        ("Kayak", "#3FA9F5"), ("Canoe", "#9D4DCC"),
                        ("SUP", "#E8A93B"), ("Raft", "#3FB950"),
                    ]),
                    selectField("Water", [
                        ("Lake", "#3FA9F5"), ("River", "#3FB950"),
                        ("Ocean", "#9D4DCC"), ("Whitewater", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Companions", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "where", kanban: "craft", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.snowstorm",
            category: .unusual,
            blurb: "Storm log — what kind, how much, impacts.",
            keywords: ["storm", "weather event", "snowstorm", "hurricane", "blizzard"],
            template: makeType(
                id: "StormEvent", name: "Storm", plural: "Storm Events",
                image: "cloud.snow", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Type", [
                        ("Snow", "#FFFFFF"), ("Ice", "#3FA9F5"),
                        ("Thunderstorm", "#9D4DCC"), ("Hurricane", "#D14B5C"),
                        ("Tornado", "#F08C2E"), ("Wildfire", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount / measure", kind: .text),
                    FieldDef.make(name: "Power out (hr)", kind: .number),
                    FieldDef.make(name: "Damage", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.thrift_find",
            category: .unusual,
            blurb: "Thrift store finds — what you scored, where, how much.",
            keywords: ["thrift", "vintage", "flea market", "find", "secondhand"],
            template: makeType(
                id: "ThriftFind", name: "Find", plural: "Thrift Finds",
                image: "tag.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Paid", kind: .number),
                    FieldDef.make(name: "Estimated value", kind: .number),
                    selectField("Category", [
                        ("Clothing", "#9D4DCC"), ("Furniture", "#7B4F2F"),
                        ("Book", "#E8A93B"), ("Vinyl", "#9D4DCC"),
                        ("Kitchenware", "#3FB950"), ("Decor", "#F08C2E"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Story", kind: .longText),
                ],
                primary: "item", kanban: "category", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.recycling_log",
            category: .home,
            blurb: "Recycling / donation log — what you got rid of, where it went.",
            keywords: ["recycling", "donation", "declutter", "minimalism"],
            template: makeType(
                id: "DonationOut", name: "Drop-off", plural: "Donations Out",
                image: "arrow.3.trianglepath", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Items", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Destination", [
                        ("Goodwill", "#3FB950"), ("Salvation Army", "#9D4DCC"),
                        ("Habitat ReStore", "#E8A93B"), ("Recycling center", "#3FA9F5"),
                        ("Curb", "#666666"), ("Friend / family", "#F08C2E"),
                        ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Number of items", kind: .number),
                    FieldDef.make(name: "Tax receipt?", kind: .boolean),
                ],
                primary: "items", kanban: "destination", calendar: "date"
            )
        ),

        Entry(
            id: "lib.candle",
            category: .home,
            blurb: "Candles owned — scent profile, brand, where it shines.",
            keywords: ["candle", "scent", "fragrance", "atmosphere"],
            template: makeType(
                id: "Candle", name: "Candle", plural: "Candles",
                image: "flame", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    selectField("Scent family", [
                        ("Citrus", "#E8A93B"), ("Floral", "#F08C2E"),
                        ("Woody", "#7B4F2F"), ("Spice", "#D14B5C"),
                        ("Fresh", "#3FA9F5"), ("Sweet", "#9D4DCC"),
                        ("Smoky", "#666666"),
                    ]),
                    FieldDef.make(name: "Burn time (hr)", kind: .number),
                    FieldDef.make(name: "Bought", kind: .date),
                    FieldDef.make(name: "Rating", kind: .rating),
                ],
                primary: "name", kanban: "scent_family"
            )
        ),

        Entry(
            id: "lib.fragrance",
            category: .hobbies,
            blurb: "Fragrance / cologne collection — notes, season, occasion.",
            keywords: ["fragrance", "cologne", "perfume", "scent", "fragrancehead"],
            template: makeType(
                id: "Fragrance", name: "Fragrance", plural: "Fragrances",
                image: "drop.triangle.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "House", kind: .text),
                    FieldDef.make(name: "Top notes", kind: .text),
                    FieldDef.make(name: "Heart notes", kind: .text),
                    FieldDef.make(name: "Base notes", kind: .text),
                    selectField("Season", [
                        ("Spring", "#3FB950"), ("Summer", "#E8A93B"),
                        ("Fall", "#F08C2E"), ("Winter", "#3FA9F5"),
                        ("Year-round", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "season", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.mileage_log",
            category: .home,
            blurb: "Vehicle mileage entries — odometer reads + fuel-ups.",
            keywords: ["mileage", "odometer", "fuel", "mpg", "gas"],
            template: makeType(
                id: "MileageEntry", name: "Entry", plural: "Mileage Log",
                image: "speedometer", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Vehicle", kind: .link),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Odometer", kind: .number, required: true),
                    FieldDef.make(name: "Gallons", kind: .number),
                    FieldDef.make(name: "Cost", kind: .number),
                    selectField("Reason", [
                        ("Fuel up", "#3FA9F5"), ("Service", "#9D4DCC"),
                        ("End of trip", "#3FB950"), ("Monthly check", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "MPG (computed)", kind: .number),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "date", kanban: "reason", calendar: "date"
            )
        ),

        Entry(
            id: "lib.charity_event",
            category: .relationships,
            blurb: "Charity events / volunteering done — when, what, hours.",
            keywords: ["volunteer", "charity", "service", "give back"],
            template: makeType(
                id: "VolunteerEvent", name: "Event", plural: "Volunteering",
                image: "heart.circle.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Organization", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Activity", kind: .text),
                    FieldDef.make(name: "Hours", kind: .number),
                    selectField("Cause", [
                        ("Hunger", "#E8A93B"), ("Housing", "#9D4DCC"),
                        ("Animals", "#3FB950"), ("Children", "#3FA9F5"),
                        ("Education", "#F08C2E"), ("Environment", "#3FB950"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Reflection", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "organization", kanban: "cause", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.research_question",
            category: .learning,
            blurb: "Open research questions you'd like to chase down someday.",
            keywords: ["research", "question", "open", "investigate"],
            template: makeType(
                id: "ResearchQuestion", name: "Question", plural: "Research Questions",
                image: "questionmark.bubble", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Question", kind: .text, required: true),
                    selectField("Domain", [
                        ("Science", "#3FA9F5"), ("History", "#7B4F2F"),
                        ("Philosophy", "#9D4DCC"), ("Tech", "#3FB950"),
                        ("Personal", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Open", "#888888"), ("Reading", "#3FA9F5"),
                        ("Forming answer", "#9D4DCC"), ("Answered", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Why it interests me", kind: .longText),
                    FieldDef.make(name: "Sources to check", kind: .longText),
                    FieldDef.make(name: "Findings", kind: .richText),
                ],
                primary: "question", kanban: "status"
            )
        ),

        Entry(
            id: "lib.museum_piece",
            category: .creative,
            blurb: "Specific museum pieces / artworks you saw and want to remember.",
            keywords: ["artwork", "museum piece", "painting", "sculpture"],
            template: makeType(
                id: "ArtworkSeen", name: "Piece", plural: "Artworks Seen",
                image: "photo.artframe", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Year", kind: .text),
                    FieldDef.make(name: "Medium", kind: .text),
                    FieldDef.make(name: "Where seen", kind: .text),
                    FieldDef.make(name: "Date seen", kind: .date),
                    FieldDef.make(name: "Why it moved me", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "title", calendar: "date_seen", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.tarot_card",
            category: .unusual,
            blurb: "Personal tarot card meanings — for your own deck/intuition.",
            keywords: ["tarot", "card", "interpretation", "deck"],
            template: makeType(
                id: "TarotCard", name: "Card", plural: "Tarot Cards",
                image: "rectangle.portrait", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Card name", kind: .text, required: true),
                    selectField("Arcana", [
                        ("Major", "#9D4DCC"), ("Cups", "#3FA9F5"),
                        ("Wands", "#F08C2E"), ("Swords", "#666666"),
                        ("Pentacles", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Card number", kind: .text),
                    FieldDef.make(name: "Upright meaning", kind: .longText),
                    FieldDef.make(name: "Reversed meaning", kind: .longText),
                    FieldDef.make(name: "Personal associations", kind: .richText),
                    FieldDef.make(name: "Card image", kind: .attachment),
                ],
                primary: "card_name", kanban: "arcana", gallery: "card_image"
            )
        ),

        Entry(
            id: "lib.pencil_pen_test",
            category: .unusual,
            blurb: "Trying out pens, pencils, papers — first impression, would buy again.",
            keywords: ["pen", "pencil", "paper", "stationery", "test"],
            template: makeType(
                id: "StationeryTest", name: "Test", plural: "Stationery Tests",
                image: "highlighter", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Product", kind: .text, required: true),
                    selectField("Type", [
                        ("Pen", "#3FA9F5"), ("Pencil", "#666666"),
                        ("Marker", "#F08C2E"), ("Paper / notebook", "#E8A93B"),
                        ("Ink", "#9D4DCC"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Price", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Pros", kind: .longText),
                    FieldDef.make(name: "Cons", kind: .longText),
                    FieldDef.make(name: "Would buy again?", kind: .boolean),
                ],
                primary: "product", kanban: "type"
            )
        ),

        Entry(
            id: "lib.daily_practice",
            category: .productivity,
            blurb: "Single-day completion log for daily practices.",
            keywords: ["daily", "practice", "streak", "ritual"],
            template: makeType(
                id: "DailyPractice", name: "Day", plural: "Daily Practice",
                image: "circle.grid.3x3.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Meditated?", kind: .boolean),
                    FieldDef.make(name: "Journaled?", kind: .boolean),
                    FieldDef.make(name: "Read?", kind: .boolean),
                    FieldDef.make(name: "Moved my body?", kind: .boolean),
                    FieldDef.make(name: "Hydrated?", kind: .boolean),
                    FieldDef.make(name: "Slept 7+ hours?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.api_endpoint",
            category: .professional,
            blurb: "External APIs you use / integrate with — auth, rate limits, docs.",
            keywords: ["api", "endpoint", "integration", "rest", "developer"],
            template: makeType(
                id: "APIEndpoint", name: "API", plural: "APIs",
                image: "network", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Service", kind: .text, required: true),
                    FieldDef.make(name: "Docs URL", kind: .url),
                    selectField("Auth", [
                        ("API key", "#3FA9F5"), ("OAuth", "#9D4DCC"),
                        ("JWT", "#E8A93B"), ("Basic", "#666666"),
                        ("None", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Rate limit", kind: .text),
                    FieldDef.make(name: "Cost / month", kind: .number),
                    FieldDef.make(name: "Base URL", kind: .url),
                    FieldDef.make(name: "Used by", kind: .text),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "service", kanban: "auth"
            )
        ),

        Entry(
            id: "lib.password_hint",
            category: .home,
            blurb: "Security questions / hints — clues only, never actual passwords.",
            keywords: ["security", "hint", "question", "recovery"],
            template: makeType(
                id: "SecurityHint", name: "Hint", plural: "Security Hints",
                image: "questionmark.key.filled", color: "#666666",
                fields: [
                    FieldDef.make(name: "Service", kind: .link, required: true),
                    FieldDef.make(name: "Question / prompt", kind: .text),
                    FieldDef.make(name: "Hint to my answer (NOT the answer)", kind: .longText),
                    selectField("Set", [
                        ("Standard truth", "#3FB950"), ("Custom answer", "#9D4DCC"),
                        ("Random string", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Last verified", kind: .date),
                ],
                primary: "service", kanban: "set", calendar: "last_verified"
            )
        ),

        Entry(
            id: "lib.bookmark_collection",
            category: .learning,
            blurb: "Reference bookmarks — sites you reach for, tagged by purpose.",
            keywords: ["bookmark", "favorite", "reference", "url"],
            template: makeType(
                id: "Bookmark", name: "Bookmark", plural: "Bookmarks",
                image: "bookmark.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "URL", kind: .url),
                    selectField("Purpose", [
                        ("Reference", "#3FA9F5"), ("Tool", "#9D4DCC"),
                        ("Inspiration", "#E8A93B"), ("Reading", "#3FB950"),
                        ("Shopping", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Tags", kind: .text),
                    FieldDef.make(name: "Added", kind: .date),
                    FieldDef.make(name: "Last opened", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title", kanban: "purpose", calendar: "last_opened"
            )
        ),

        Entry(
            id: "lib.compliment_received",
            category: .relationships,
            blurb: "Compliments you've received — file under 'evidence for self-doubt days'.",
            keywords: ["compliment", "kind word", "feedback", "self-esteem"],
            template: makeType(
                id: "ComplimentReceived", name: "Compliment", plural: "Compliments",
                image: "heart.text.square.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "What they said", kind: .text, required: true),
                    FieldDef.make(name: "From", kind: .link),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Context", [
                        ("Work", "#3FA9F5"), ("Family", "#D14B5C"),
                        ("Friend", "#9D4DCC"), ("Stranger", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Why it mattered", kind: .longText),
                ],
                primary: "what_they_said", kanban: "context", calendar: "date"
            )
        ),

        Entry(
            id: "lib.dispute",
            category: .home,
            blurb: "Refund / chargeback / dispute log — who, when, status.",
            keywords: ["dispute", "refund", "chargeback", "complaint"],
            template: makeType(
                id: "Dispute", name: "Dispute", plural: "Disputes",
                image: "exclamationmark.bubble.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "Company", kind: .text),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Opened on", kind: .date),
                    selectField("Status", [
                        ("Opened", "#3FA9F5"), ("In progress", "#9D4DCC"),
                        ("Resolved (refunded)", "#3FB950"), ("Denied", "#D14B5C"),
                        ("Escalated", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "subject", kanban: "status", calendar: "opened_on"
            )
        ),

        Entry(
            id: "lib.gift_received",
            category: .relationships,
            blurb: "Gifts you've received — from whom, occasion, sent thank you?",
            keywords: ["gift", "received", "thank you", "present"],
            template: makeType(
                id: "GiftReceived", name: "Gift", plural: "Gifts Received",
                image: "shippingbox.and.arrow.backward", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Gift", kind: .text, required: true),
                    FieldDef.make(name: "From", kind: .link),
                    FieldDef.make(name: "Occasion", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Thank you status", [
                        ("Owed", "#E8A93B"), ("Sent (text)", "#3FA9F5"),
                        ("Sent (card)", "#9D4DCC"), ("Sent (in person)", "#3FB950"),
                        ("Not applicable", "#666666"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "gift", kanban: "thank_you_status", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.daily_gratitude",
            category: .health,
            blurb: "Daily gratitude — three things you're grateful for today.",
            keywords: ["gratitude", "thankful", "appreciate", "daily"],
            template: makeType(
                id: "Gratitude", name: "Entry", plural: "Gratitude",
                image: "hands.clap", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Grateful for #1", kind: .text),
                    FieldDef.make(name: "Grateful for #2", kind: .text),
                    FieldDef.make(name: "Grateful for #3", kind: .text),
                    FieldDef.make(name: "Why", kind: .richText),
                ],
                primary: "date", calendar: "date"
            )
        ),

    ]
}
