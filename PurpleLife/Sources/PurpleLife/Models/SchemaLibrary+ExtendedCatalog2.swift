import Foundation

/// Round-3 extension to the schema library catalog. Concentrates the
/// "implement entire categories" picks from the community proposals
/// doc (`Docs/SchemaLibraryProposals.md`). Combined with `coreEntries +
/// extendedEntries` via `SchemaLibrary.entries`, this brings the
/// library catalog total to ~590 templates.
///
/// Categories represented: Productivity, Home & Life Admin, Finance,
/// Food, Travel (incl. the 50-state License Plate sighting tracker),
/// Creative, Relationships, Pets, Nature Observation, and the bulk of
/// the Unusual / Truly Weird bucket. Long-tail items from the proposals
/// doc are distributed to their natural category here.
///
/// New entries can land here freely. Tests in `SchemaLibraryTests`
/// validate every entry against the catalog invariants (primary field
/// resolves, kanban → select, calendar → date, gallery → attachment,
/// at least one required field).
extension SchemaLibrary {

    static let extendedEntries2: [Entry] = [

        // MARK: - Productivity & Planning

        Entry(
            id: "lib.tickler_file",
            category: .productivity,
            blurb: "Defer-until-date items — surface on a specific day so it's out of mind until needed.",
            keywords: ["tickler", "defer", "gtd", "future", "wait"],
            template: makeType(
                id: "TicklerItem", name: "Tickler", plural: "Tickler File",
                image: "calendar.badge.minus", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Surface on", kind: .date, required: true),
                    FieldDef.make(name: "Context", kind: .text),
                    FieldDef.make(name: "Action when surfaced", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", calendar: "surface_on"
            )
        ),

        Entry(
            id: "lib.atomic_action",
            category: .productivity,
            blurb: "GTD next-action — the single physical thing you'd do next on a project.",
            keywords: ["next action", "gtd", "atomic", "action"],
            template: makeType(
                id: "NextAction", name: "Action", plural: "Next Actions",
                image: "bolt.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Action", kind: .text, required: true),
                    FieldDef.make(name: "Project", kind: .link),
                    selectField("Context", [
                        ("@home", "#3FB950"), ("@work", "#3FA9F5"),
                        ("@phone", "#9D4DCC"), ("@computer", "#E8A93B"),
                        ("@errands", "#F08C2E"), ("@waiting", "#666666"),
                    ]),
                    FieldDef.make(name: "Energy needed", kind: .rating),
                    FieldDef.make(name: "Time estimate (min)", kind: .number),
                    selectField("Status", [
                        ("Active", "#3FA9F5"), ("Done", "#3FB950"),
                        ("Cancelled", "#666666"),
                    ]),
                ],
                primary: "action", kanban: "context"
            )
        ),

        Entry(
            id: "lib.stop_doing",
            category: .productivity,
            blurb: "Things you're consciously NOT going to do — anti-tasks that reclaim attention.",
            keywords: ["stop", "anti-todo", "subtraction", "minimalism"],
            template: makeType(
                id: "StopDoing", name: "Stop Doing", plural: "Stop-Doing List",
                image: "minus.circle", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "What I'm stopping", kind: .text, required: true),
                    FieldDef.make(name: "Why it goes", kind: .longText),
                    FieldDef.make(name: "Started avoiding", kind: .date),
                    selectField("Domain", [
                        ("Work", "#3FA9F5"), ("Home", "#3FB950"),
                        ("Tech", "#9D4DCC"), ("Health", "#E8A93B"),
                        ("Money", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Slipped", "#E8A93B"),
                        ("Back on", "#D14B5C"), ("Retired", "#666666"),
                    ]),
                ],
                primary: "what_i_m_stopping", kanban: "status", calendar: "started_avoiding"
            )
        ),

        Entry(
            id: "lib.personal_manifesto",
            category: .productivity,
            blurb: "Operating principles, values, working agreements you live by. Revisit annually.",
            keywords: ["manifesto", "values", "principles", "commitments"],
            template: makeType(
                id: "PersonalManifesto", name: "Manifesto", plural: "Personal Manifesto",
                image: "doc.text.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Version date", kind: .date),
                    FieldDef.make(name: "Principles", kind: .richText),
                    FieldDef.make(name: "Anti-patterns", kind: .longText),
                    FieldDef.make(name: "Last reviewed", kind: .date),
                ],
                primary: "title", calendar: "version_date"
            )
        ),

        Entry(
            id: "lib.daily_highlight",
            category: .productivity,
            blurb: "A single must-do for the day (Make Time methodology) — write at start of day, reflect at end.",
            keywords: ["highlight", "make time", "daily focus"],
            template: makeType(
                id: "DailyHighlight", name: "Highlight", plural: "Daily Highlights",
                image: "star.circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Highlight", kind: .text, required: true),
                    selectField("Type", [
                        ("Urgent", "#D14B5C"), ("Satisfying", "#9D4DCC"),
                        ("Joyful", "#3FB950"), ("Other", "#666666"),
                    ]),
                    selectField("Outcome", [
                        ("Hit it", "#3FB950"), ("Partial", "#E8A93B"),
                        ("Missed", "#D14B5C"), ("Skipped", "#666666"),
                    ]),
                    FieldDef.make(name: "Reflection", kind: .longText),
                ],
                primary: "highlight", kanban: "outcome", calendar: "date"
            )
        ),

        Entry(
            id: "lib.top_three",
            category: .productivity,
            blurb: "Three priorities for the day. Lighter than a full planner.",
            keywords: ["top three", "daily", "priority", "three"],
            template: makeType(
                id: "TopThree", name: "Day", plural: "Top 3 Daily",
                image: "list.number", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Priority 1", kind: .text),
                    FieldDef.make(name: "Priority 2", kind: .text),
                    FieldDef.make(name: "Priority 3", kind: .text),
                    FieldDef.make(name: "Done count", kind: .number),
                    FieldDef.make(name: "End-of-day note", kind: .longText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.after_action",
            category: .productivity,
            blurb: "Military-style retro on a discrete event: plan vs reality vs lessons.",
            keywords: ["aar", "after action", "retro", "debrief"],
            template: makeType(
                id: "AfterAction", name: "AAR", plural: "After-Action Reviews",
                image: "checkmark.shield", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Event", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "What was planned", kind: .richText),
                    FieldDef.make(name: "What actually happened", kind: .richText),
                    FieldDef.make(name: "Why it differed", kind: .longText),
                    FieldDef.make(name: "Sustain", kind: .longText),
                    FieldDef.make(name: "Improve", kind: .longText),
                ],
                primary: "event", calendar: "date"
            )
        ),

        Entry(
            id: "lib.pre_mortem",
            category: .productivity,
            blurb: "Imagine the project failed. What would the post-mortem say? Run before kickoff.",
            keywords: ["pre-mortem", "premortem", "risk", "kickoff"],
            template: makeType(
                id: "PreMortem", name: "Pre-Mortem", plural: "Pre-Mortems",
                image: "exclamationmark.triangle.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Project", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Imagined failure mode", kind: .richText),
                    FieldDef.make(name: "Most likely causes", kind: .longText),
                    FieldDef.make(name: "Prevention plan", kind: .richText),
                    FieldDef.make(name: "Early warning signs", kind: .longText),
                ],
                primary: "project", calendar: "date"
            )
        ),

        Entry(
            id: "lib.one_three_five",
            category: .productivity,
            blurb: "One big thing, three medium, five small. Daily completion log.",
            keywords: ["1-3-5", "daily", "list", "priority"],
            template: makeType(
                id: "OneThreeFive", name: "Day", plural: "1-3-5 List",
                image: "square.grid.3x1.below.line.grid.1x2", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Big (1)", kind: .text),
                    FieldDef.make(name: "Medium (3)", kind: .longText),
                    FieldDef.make(name: "Small (5)", kind: .longText),
                    FieldDef.make(name: "Items done", kind: .number),
                    FieldDef.make(name: "End-of-day note", kind: .longText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.eisenhower_item",
            category: .productivity,
            blurb: "Tag a task with urgent/important quadrant — clarifies do/schedule/delegate/drop.",
            keywords: ["eisenhower", "matrix", "quadrant", "urgent", "important"],
            template: makeType(
                id: "EisenhowerItem", name: "Item", plural: "Eisenhower Matrix",
                image: "square.grid.2x2", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Task", kind: .text, required: true),
                    selectField("Quadrant", [
                        ("Q1: urgent+important (do)", "#D14B5C"),
                        ("Q2: important not urgent (schedule)", "#3FB950"),
                        ("Q3: urgent not important (delegate)", "#E8A93B"),
                        ("Q4: neither (drop)", "#666666"),
                    ]),
                    FieldDef.make(name: "Deadline", kind: .date),
                    FieldDef.make(name: "Owner / delegate", kind: .link),
                    FieldDef.make(name: "Why this quadrant", kind: .longText),
                ],
                primary: "task", kanban: "quadrant", calendar: "deadline"
            )
        ),

        Entry(
            id: "lib.tomorrow_setup",
            category: .productivity,
            blurb: "Pre-bed prep: what's on tap, what's laid out, what's blocked.",
            keywords: ["tomorrow", "evening review", "prep"],
            template: makeType(
                id: "TomorrowSetup", name: "Setup", plural: "Tomorrow Setup",
                image: "moon.haze", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "For date", kind: .date, required: true),
                    FieldDef.make(name: "First task tomorrow", kind: .text),
                    FieldDef.make(name: "What I prepped tonight", kind: .longText),
                    FieldDef.make(name: "Outfit / gear laid out", kind: .text),
                    FieldDef.make(name: "Calendar checked?", kind: .boolean),
                    FieldDef.make(name: "Blockers anticipated", kind: .longText),
                ],
                primary: "for_date", calendar: "for_date"
            )
        ),

        Entry(
            id: "lib.operating_principle",
            category: .productivity,
            blurb: "Personal or team — short rules you've committed to. One per row.",
            keywords: ["principle", "operating", "rule", "tenet"],
            template: makeType(
                id: "OperatingPrinciple", name: "Principle", plural: "Operating Principles",
                image: "scroll", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Principle", kind: .text, required: true),
                    selectField("Domain", [
                        ("Personal", "#9D4DCC"), ("Team", "#3FA9F5"),
                        ("Family", "#E8A93B"), ("Money", "#3FB950"),
                        ("Health", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Rationale", kind: .richText),
                    FieldDef.make(name: "Counter-example", kind: .longText),
                    FieldDef.make(name: "Set on", kind: .date),
                ],
                primary: "principle", kanban: "domain", calendar: "set_on"
            )
        ),

        Entry(
            id: "lib.personal_user_manual",
            category: .productivity,
            blurb: "\"How to work with me\" — share with colleagues, partners, kids.",
            keywords: ["user manual", "how to work with me", "guide"],
            template: makeType(
                id: "PersonalUserManual", name: "Section", plural: "Personal User Manual",
                image: "person.text.rectangle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Section heading", kind: .text, required: true),
                    selectField("Section type", [
                        ("How I communicate", "#3FA9F5"),
                        ("When I'm at my best", "#3FB950"),
                        ("Watch outs", "#E8A93B"),
                        ("Feedback preferences", "#9D4DCC"),
                        ("How to win with me", "#F08C2E"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Content", kind: .richText),
                    FieldDef.make(name: "Last updated", kind: .date),
                ],
                primary: "section_heading", kanban: "section_type", calendar: "last_updated"
            )
        ),

        Entry(
            id: "lib.capability",
            category: .productivity,
            blurb: "Things you can confidently do well, with evidence — for reviews, pitches, self-esteem.",
            keywords: ["capability", "skill", "competence", "proof"],
            template: makeType(
                id: "Capability", name: "Capability", plural: "Capabilities",
                image: "checkmark.seal", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Capability", kind: .text, required: true),
                    selectField("Confidence", [
                        ("Emerging", "#E8A93B"), ("Solid", "#3FA9F5"),
                        ("Strong", "#9D4DCC"), ("World-class", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Evidence / examples", kind: .richText),
                    FieldDef.make(name: "Last demonstrated", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "capability", kanban: "confidence", calendar: "last_demonstrated"
            )
        ),

        Entry(
            id: "lib.time_saver",
            category: .productivity,
            blurb: "Tricks and shortcuts you've discovered — tag by domain so you remember.",
            keywords: ["time saver", "hack", "trick", "shortcut"],
            template: makeType(
                id: "TimeSaver", name: "Trick", plural: "Time Savers",
                image: "wand.and.stars.inverse", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Trick", kind: .text, required: true),
                    selectField("Domain", [
                        ("Computer", "#3FA9F5"), ("Phone", "#9D4DCC"),
                        ("Home", "#3FB950"), ("Cooking", "#E8A93B"),
                        ("Travel", "#F08C2E"), ("Money", "#D14B5C"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Saves about (min)", kind: .number),
                    FieldDef.make(name: "Description", kind: .richText),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Date discovered", kind: .date),
                ],
                primary: "trick", kanban: "domain", calendar: "date_discovered"
            )
        ),

        Entry(
            id: "lib.meeting_prep",
            category: .productivity,
            blurb: "Notes ahead of a meeting — questions, goals, what success looks like.",
            keywords: ["meeting prep", "agenda", "pre-meeting"],
            template: makeType(
                id: "MeetingPrep", name: "Prep", plural: "Meeting Prep",
                image: "doc.badge.clock", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Meeting", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "My goal", kind: .text),
                    FieldDef.make(name: "Questions to ask", kind: .longText),
                    FieldDef.make(name: "What success looks like", kind: .text),
                    FieldDef.make(name: "Pre-reads to send", kind: .longText),
                    FieldDef.make(name: "Attendees", kind: .link),
                ],
                primary: "meeting", calendar: "when"
            )
        ),

        Entry(
            id: "lib.outsourced_item",
            category: .productivity,
            blurb: "Delegated tasks: who, what, status, deadline.",
            keywords: ["delegate", "outsource", "assistant", "subcontract"],
            template: makeType(
                id: "OutsourcedItem", name: "Outsource", plural: "Outsourced Tasks",
                image: "arrow.up.right.circle", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Task", kind: .text, required: true),
                    FieldDef.make(name: "Delegated to", kind: .link),
                    FieldDef.make(name: "Sent on", kind: .date),
                    FieldDef.make(name: "Due", kind: .date),
                    selectField("Status", [
                        ("Sent", "#3FA9F5"), ("Confirmed", "#9D4DCC"),
                        ("In progress", "#E8A93B"), ("Done", "#3FB950"),
                        ("Stalled", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "task", kanban: "status", calendar: "due"
            )
        ),

        Entry(
            id: "lib.annual_plan",
            category: .productivity,
            blurb: "Yearly themes, big rocks, hopes — written at year start, reviewed at year end.",
            keywords: ["annual", "year", "plan", "yearly"],
            template: makeType(
                id: "AnnualPlan", name: "Year", plural: "Annual Plans",
                image: "calendar", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Year", kind: .number, required: true),
                    FieldDef.make(name: "Theme", kind: .text),
                    FieldDef.make(name: "Top 3 hopes", kind: .longText),
                    FieldDef.make(name: "Top 3 fears", kind: .longText),
                    FieldDef.make(name: "Big rocks", kind: .richText),
                    FieldDef.make(name: "Mid-year check", kind: .richText),
                    FieldDef.make(name: "Year-end review", kind: .richText),
                ],
                primary: "year"
            )
        ),

        Entry(
            id: "lib.five_year_vision",
            category: .productivity,
            blurb: "Long-horizon picture; revisit annually. Where do you want to be in 5 years?",
            keywords: ["vision", "long term", "five year", "lifetime"],
            template: makeType(
                id: "FiveYearVision", name: "Vision", plural: "Five-Year Vision",
                image: "scope", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Drafted", kind: .date, required: true),
                    FieldDef.make(name: "Target year", kind: .number),
                    FieldDef.make(name: "Career picture", kind: .richText),
                    FieldDef.make(name: "Home / life picture", kind: .richText),
                    FieldDef.make(name: "Relationships picture", kind: .richText),
                    FieldDef.make(name: "Health picture", kind: .richText),
                    FieldDef.make(name: "Money picture", kind: .richText),
                    FieldDef.make(name: "Annual review log", kind: .noteLog),
                ],
                primary: "drafted", calendar: "drafted"
            )
        ),

        Entry(
            id: "lib.implementation_intention",
            category: .productivity,
            blurb: "\"If X happens, I will do Y.\" Habit science — turns vague goals into reflexes.",
            keywords: ["implementation intention", "if-then", "habit", "trigger"],
            template: makeType(
                id: "ImplementationIntention", name: "Intention", plural: "Implementation Intentions",
                image: "arrow.triangle.swap", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "If (cue)", kind: .text, required: true),
                    FieldDef.make(name: "Then (action)", kind: .text, required: true),
                    selectField("Domain", [
                        ("Health", "#3FB950"), ("Work", "#3FA9F5"),
                        ("Money", "#E8A93B"), ("Relationships", "#D14B5C"),
                        ("Learning", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    selectField("Status", [
                        ("Trying", "#E8A93B"), ("Working", "#3FB950"),
                        ("Failed", "#D14B5C"), ("Auto-pilot", "#9D4DCC"),
                    ]),
                ],
                primary: "if_cue", kanban: "status", calendar: "started"
            )
        ),

        Entry(
            id: "lib.habit_stack",
            category: .productivity,
            blurb: "Linked chains of habits — after coffee → meditate → journal. Cue triggers next link.",
            keywords: ["habit stack", "atomic habits", "chain", "routine"],
            template: makeType(
                id: "HabitStack", name: "Stack", plural: "Habit Stacks",
                image: "square.stack.3d.up", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Stack name", kind: .text, required: true),
                    FieldDef.make(name: "Anchor habit", kind: .text),
                    FieldDef.make(name: "Stack sequence", kind: .longText),
                    selectField("Time of day", [
                        ("Morning", "#E8A93B"), ("Midday", "#3FA9F5"),
                        ("Evening", "#9D4DCC"), ("Bedtime", "#666666"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    selectField("Status", [
                        ("Building", "#E8A93B"), ("Solid", "#3FB950"),
                        ("Drifting", "#F08C2E"), ("Retired", "#666666"),
                    ]),
                ],
                primary: "stack_name", kanban: "status", calendar: "started"
            )
        ),

        Entry(
            id: "lib.energy_block",
            category: .productivity,
            blurb: "Calendar-style \"deep work between 9–11\" scheduled blocks for cognitive work.",
            keywords: ["energy block", "deep work", "time block", "schedule"],
            template: makeType(
                id: "EnergyBlock", name: "Block", plural: "Energy Blocks",
                image: "rectangle.split.3x1", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    selectField("Type", [
                        ("Deep work", "#9D4DCC"), ("Shallow", "#3FA9F5"),
                        ("Meeting", "#E8A93B"), ("Recovery", "#3FB950"),
                        ("Admin", "#666666"),
                    ]),
                    FieldDef.make(name: "Held?", kind: .boolean),
                    FieldDef.make(name: "What got done", kind: .longText),
                ],
                primary: "title", kanban: "type", calendar: "when"
            )
        ),

        Entry(
            id: "lib.time_audit",
            category: .productivity,
            blurb: "Where did the hour actually go? For week-long audits — track in 15- or 30-min slices.",
            keywords: ["time audit", "tracking", "where did time go"],
            template: makeType(
                id: "TimeAudit", name: "Slice", plural: "Time Audit",
                image: "stopwatch", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "What I did", kind: .text),
                    selectField("Category", [
                        ("Deep work", "#9D4DCC"), ("Meeting", "#3FA9F5"),
                        ("Admin", "#666666"), ("Comms", "#E8A93B"),
                        ("Break", "#3FB950"), ("Personal", "#F08C2E"),
                        ("Wasted", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Energy after (1–10)", kind: .number),
                ],
                primary: "what_i_did", kanban: "category", calendar: "when"
            )
        ),

        Entry(
            id: "lib.daily_intention",
            category: .productivity,
            blurb: "\"Today I will…\" written each morning — sets the frame for the day.",
            keywords: ["intention", "daily", "morning", "set the day"],
            template: makeType(
                id: "DailyIntention", name: "Intention", plural: "Daily Intentions",
                image: "sun.max.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "I will", kind: .text, required: true),
                    FieldDef.make(name: "I won't", kind: .text),
                    selectField("Theme", [
                        ("Focus", "#9D4DCC"), ("Patience", "#3FA9F5"),
                        ("Service", "#3FB950"), ("Boldness", "#D14B5C"),
                        ("Rest", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "End-of-day reflection", kind: .longText),
                ],
                primary: "i_will", kanban: "theme", calendar: "date"
            )
        ),

        Entry(
            id: "lib.lesson_applied",
            category: .productivity,
            blurb: "When you actually used a past lesson — closes the loop on learning → behavior.",
            keywords: ["lesson", "applied", "learning loop", "growth"],
            template: makeType(
                id: "LessonApplied", name: "Application", plural: "Lessons Applied",
                image: "arrow.triangle.2.circlepath.circle.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Lesson", kind: .link, required: true),
                    FieldDef.make(name: "Situation", kind: .text),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "How I applied it", kind: .richText),
                    FieldDef.make(name: "Outcome", kind: .longText),
                    selectField("Result", [
                        ("Worked great", "#3FB950"), ("Better than baseline", "#3FA9F5"),
                        ("Wash", "#E8A93B"), ("Backfired", "#D14B5C"),
                    ]),
                ],
                primary: "situation", kanban: "result", calendar: "date"
            )
        ),

        // MARK: - Home & Life Admin

        Entry(
            id: "lib.mail_received",
            category: .home,
            blurb: "Physical mail log — from, type (bill / personal / junk), action needed.",
            keywords: ["mail", "snail mail", "post", "delivery"],
            template: makeType(
                id: "MailReceived", name: "Piece", plural: "Mail In",
                image: "tray.and.arrow.down", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "From", kind: .text),
                    selectField("Type", [
                        ("Bill", "#D14B5C"), ("Personal", "#9D4DCC"),
                        ("Bank / financial", "#3FA9F5"), ("Junk", "#666666"),
                        ("Subscription", "#E8A93B"), ("Government", "#F08C2E"),
                        ("Package", "#3FB950"),
                    ]),
                    selectField("Action", [
                        ("File", "#3FA9F5"), ("Pay", "#D14B5C"),
                        ("Reply", "#9D4DCC"), ("Toss", "#666666"),
                        ("Done", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "from", kanban: "action", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.mail_sent",
            category: .home,
            blurb: "Outgoing physical mail — recipient, tracking, what you sent.",
            keywords: ["mail", "sent", "outgoing", "package", "shipped"],
            template: makeType(
                id: "MailSent", name: "Shipment", plural: "Mail Out",
                image: "paperplane", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Recipient", kind: .link, required: true),
                    FieldDef.make(name: "Sent on", kind: .date, required: true),
                    FieldDef.make(name: "Contents", kind: .text),
                    selectField("Carrier", [
                        ("USPS", "#3FA9F5"), ("UPS", "#7B4F2F"),
                        ("FedEx", "#9D4DCC"), ("DHL", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Tracking #", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    selectField("Status", [
                        ("In transit", "#3FA9F5"), ("Delivered", "#3FB950"),
                        ("Lost", "#D14B5C"),
                    ]),
                ],
                primary: "recipient", kanban: "status", calendar: "sent_on"
            )
        ),

        Entry(
            id: "lib.tool_inventory",
            category: .home,
            blurb: "Garage / workshop tools — name, location, last used.",
            keywords: ["tool", "garage", "workshop", "inventory"],
            template: makeType(
                id: "Tool", name: "Tool", plural: "Tool Inventory",
                image: "hammer", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Tool", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    selectField("Category", [
                        ("Hand tool", "#7B4F2F"), ("Power tool", "#D14B5C"),
                        ("Measuring", "#3FA9F5"), ("Cutting", "#9D4DCC"),
                        ("Fastener / hardware", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Storage location", kind: .text),
                    FieldDef.make(name: "Bought", kind: .date),
                    FieldDef.make(name: "Last used", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "tool", kanban: "category", calendar: "last_used", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sentimental_item",
            category: .home,
            blurb: "Family heirlooms and objects with stories — provenance, who gets it.",
            keywords: ["sentimental", "heirloom", "memory", "legacy"],
            template: makeType(
                id: "SentimentalItem", name: "Item", plural: "Sentimental Items",
                image: "heart.text.square", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "From whom", kind: .link),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Current location", kind: .text),
                    FieldDef.make(name: "Designated for", kind: .link, description: "Who inherits"),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "item", calendar: "acquired", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.heirloom",
            category: .home,
            blurb: "Passed-down items with generation chain — specifically multi-generational.",
            keywords: ["heirloom", "antique", "passed down", "family"],
            template: makeType(
                id: "Heirloom", name: "Heirloom", plural: "Heirlooms",
                image: "crown", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Origin / first owner", kind: .text),
                    FieldDef.make(name: "Year originated", kind: .number),
                    FieldDef.make(name: "Generation chain", kind: .longText, description: "Great-grandmother → grandmother → mother → me"),
                    FieldDef.make(name: "Appraised value", kind: .number),
                    FieldDef.make(name: "Insured?", kind: .boolean),
                    FieldDef.make(name: "Stored at", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Story", kind: .richText),
                ],
                primary: "item", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.furniture",
            category: .home,
            blurb: "Major furniture pieces — where bought, condition, plan.",
            keywords: ["furniture", "couch", "chair", "table"],
            template: makeType(
                id: "FurniturePiece", name: "Piece", plural: "Furniture",
                image: "sofa", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Piece", kind: .text, required: true),
                    selectField("Room", [
                        ("Living room", "#3FB950"), ("Bedroom", "#9D4DCC"),
                        ("Dining", "#E8A93B"), ("Office", "#3FA9F5"),
                        ("Outdoor", "#F08C2E"), ("Storage", "#666666"),
                    ]),
                    FieldDef.make(name: "Bought from", kind: .text),
                    FieldDef.make(name: "Bought on", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Material", kind: .text),
                    selectField("Condition", [
                        ("Like new", "#3FB950"), ("Good", "#3FA9F5"),
                        ("Worn", "#E8A93B"), ("Needs repair", "#F08C2E"),
                        ("Replace soon", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "piece", kanban: "room", calendar: "bought_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.wall_art",
            category: .home,
            blurb: "Art hung at home: piece, room, dimensions, story.",
            keywords: ["wall art", "decor", "art", "hanging"],
            template: makeType(
                id: "WallArt", name: "Piece", plural: "Wall Art",
                image: "photo.tv", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    selectField("Type", [
                        ("Print", "#3FA9F5"), ("Original", "#9D4DCC"),
                        ("Photograph", "#E8A93B"), ("Poster", "#F08C2E"),
                        ("Tapestry", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Room", kind: .text),
                    FieldDef.make(name: "Dimensions", kind: .text),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Image", kind: .attachment),
                    FieldDef.make(name: "Story", kind: .longText),
                ],
                primary: "title", kanban: "type", calendar: "acquired", gallery: "image"
            )
        ),

        Entry(
            id: "lib.plant_cutting",
            category: .home,
            blurb: "Cuttings taken from existing plants — rooting status, mother plant.",
            keywords: ["cutting", "propagation", "plant", "clone"],
            template: makeType(
                id: "PlantCutting", name: "Cutting", plural: "Cuttings",
                image: "leaf.arrow.triangle.circlepath", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "From (mother plant)", kind: .link),
                    FieldDef.make(name: "Taken on", kind: .date, required: true),
                    selectField("Method", [
                        ("Water", "#3FA9F5"), ("Soil", "#7B4F2F"),
                        ("Perlite", "#666666"), ("Sphagnum", "#3FB950"),
                        ("Other", "#888888"),
                    ]),
                    selectField("Status", [
                        ("Just cut", "#E8A93B"), ("Rooting", "#3FA9F5"),
                        ("Rooted", "#9D4DCC"), ("Potted up", "#3FB950"),
                        ("Failed", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Roots visible on", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species", kanban: "status", calendar: "taken_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.compost_batch",
            category: .home,
            blurb: "Compost pile / bin batches — start, brown:green ratio, ready estimate, temperature.",
            keywords: ["compost", "garden", "soil", "bin"],
            template: makeType(
                id: "CompostBatch", name: "Batch", plural: "Compost Batches",
                image: "leaf.circle.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Batch name", kind: .text, required: true),
                    FieldDef.make(name: "Started", kind: .date, required: true),
                    FieldDef.make(name: "Browns added", kind: .text),
                    FieldDef.make(name: "Greens added", kind: .text),
                    FieldDef.make(name: "Last turned", kind: .date),
                    FieldDef.make(name: "Internal temp (°F)", kind: .number),
                    selectField("Stage", [
                        ("Building", "#E8A93B"), ("Hot phase", "#D14B5C"),
                        ("Curing", "#9D4DCC"), ("Ready", "#3FB950"),
                        ("Used", "#666666"),
                    ]),
                    FieldDef.make(name: "Ready estimate", kind: .date),
                ],
                primary: "batch_name", kanban: "stage", calendar: "ready_estimate"
            )
        ),

        Entry(
            id: "lib.spare_key",
            category: .home,
            blurb: "Spare keys — whose key do you have, and who has yours.",
            keywords: ["key", "spare", "lockout", "trust"],
            template: makeType(
                id: "SpareKey", name: "Key", plural: "Spare Keys",
                image: "key", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Key to", kind: .text, required: true),
                    selectField("Direction", [
                        ("I hold their key", "#3FA9F5"),
                        ("They hold my key", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Person", kind: .link),
                    FieldDef.make(name: "Given on", kind: .date),
                    FieldDef.make(name: "Rotated on", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "key_to", kanban: "direction", calendar: "rotated_on"
            )
        ),

        Entry(
            id: "lib.house_sitter_notes",
            category: .home,
            blurb: "Instructions for house sitters / pet sitters — feeding, plants, mail, quirks.",
            keywords: ["house sitter", "pet sitter", "instructions"],
            template: makeType(
                id: "SitterNotes", name: "Section", plural: "House-Sitter Notes",
                image: "doc.plaintext", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Heading", kind: .text, required: true),
                    selectField("Category", [
                        ("Pets", "#F08C2E"), ("Plants", "#3FB950"),
                        ("Mail", "#3FA9F5"), ("Trash / recycling", "#666666"),
                        ("Appliances", "#9D4DCC"), ("Emergencies", "#D14B5C"),
                        ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Instructions", kind: .richText),
                    FieldDef.make(name: "Last updated", kind: .date),
                ],
                primary: "heading", kanban: "category", calendar: "last_updated"
            )
        ),

        Entry(
            id: "lib.loyalty_program",
            category: .home,
            blurb: "Loyalty / rewards program memberships — number, status, expiry.",
            keywords: ["loyalty", "rewards", "member", "points"],
            template: makeType(
                id: "LoyaltyProgram", name: "Program", plural: "Loyalty Programs",
                image: "star.circle.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Brand", kind: .text, required: true),
                    selectField("Category", [
                        ("Coffee / food", "#7B4F2F"), ("Retail", "#3FA9F5"),
                        ("Grocery", "#3FB950"), ("Gas", "#F08C2E"),
                        ("Pharmacy", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Member #", kind: .text),
                    FieldDef.make(name: "Tier", kind: .text),
                    FieldDef.make(name: "Points balance", kind: .number),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "brand", kanban: "category", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.frequent_flyer",
            category: .home,
            blurb: "Airline status accounts — carrier, tier, miles, qualifying balance.",
            keywords: ["frequent flyer", "airline", "miles", "status"],
            template: makeType(
                id: "FrequentFlyer", name: "Account", plural: "Frequent Flyer",
                image: "airplane.circle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Airline", kind: .text, required: true),
                    FieldDef.make(name: "Member #", kind: .text),
                    selectField("Tier", [
                        ("Base", "#888888"), ("Silver", "#666666"),
                        ("Gold", "#E8A93B"), ("Platinum", "#9D4DCC"),
                        ("Diamond / 1K", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Miles balance", kind: .number),
                    FieldDef.make(name: "Qualifying segments / miles YTD", kind: .number),
                    FieldDef.make(name: "Status expires", kind: .date),
                    FieldDef.make(name: "Login URL", kind: .url),
                ],
                primary: "airline", kanban: "tier", calendar: "status_expires"
            )
        ),

        Entry(
            id: "lib.mowing_log",
            category: .home,
            blurb: "Lawn mowing dates — hours, fuel, blade sharpened.",
            keywords: ["mowing", "lawn", "yard work", "grass"],
            template: makeType(
                id: "MowingLog", name: "Mow", plural: "Mowing Log",
                image: "leaf", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Hours", kind: .number),
                    FieldDef.make(name: "Fuel used (gal)", kind: .number),
                    FieldDef.make(name: "Blade sharpened?", kind: .boolean),
                    selectField("Conditions", [
                        ("Dry", "#E8A93B"), ("Damp", "#3FA9F5"),
                        ("Long grass", "#9D4DCC"), ("Hot", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", kanban: "conditions", calendar: "date"
            )
        ),

        Entry(
            id: "lib.pool_maintenance",
            category: .home,
            blurb: "Pool chemistry log — chlorine, pH, last shock, vacuum.",
            keywords: ["pool", "chlorine", "ph", "shock", "chemistry"],
            template: makeType(
                id: "PoolMaintenance", name: "Test", plural: "Pool Maintenance",
                image: "drop.circle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Free chlorine (ppm)", kind: .number),
                    FieldDef.make(name: "pH", kind: .number),
                    FieldDef.make(name: "Alkalinity (ppm)", kind: .number),
                    FieldDef.make(name: "Cyanuric acid (ppm)", kind: .number),
                    selectField("Action taken", [
                        ("Tested only", "#888888"), ("Added chlorine", "#3FA9F5"),
                        ("Shocked", "#D14B5C"), ("pH adjust", "#9D4DCC"),
                        ("Vacuumed", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", kanban: "action_taken", calendar: "date"
            )
        ),

        Entry(
            id: "lib.hot_tub_maintenance",
            category: .home,
            blurb: "Hot tub upkeep — sanitizer, filter clean, drain schedule.",
            keywords: ["hot tub", "spa", "sanitizer", "filter"],
            template: makeType(
                id: "HotTubMaintenance", name: "Service", plural: "Hot Tub",
                image: "drop.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Service", [
                        ("Sanitizer add", "#3FA9F5"), ("Filter clean", "#9D4DCC"),
                        ("Filter replace", "#E8A93B"), ("Drain & refill", "#D14B5C"),
                        ("Cover clean", "#3FB950"), ("Shock", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Sanitizer level", kind: .number),
                    FieldDef.make(name: "pH", kind: .number),
                    FieldDef.make(name: "Next service due", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", kanban: "service", calendar: "next_service_due"
            )
        ),

        Entry(
            id: "lib.septic_well",
            category: .home,
            blurb: "Septic / well log — pumping, water test, levels, inspections.",
            keywords: ["septic", "well", "water", "rural"],
            template: makeType(
                id: "SepticWellLog", name: "Service", plural: "Septic & Well",
                image: "drop.degreesign", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Service type", [
                        ("Septic pumping", "#7B4F2F"), ("Septic inspection", "#9D4DCC"),
                        ("Well water test", "#3FA9F5"), ("Well pump service", "#E8A93B"),
                        ("Filter change", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Service provider", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Result / findings", kind: .longText),
                    FieldDef.make(name: "Next due", kind: .date),
                ],
                primary: "service_type", kanban: "service_type", calendar: "next_due"
            )
        ),

        Entry(
            id: "lib.smoke_detector_check",
            category: .home,
            blurb: "Smoke / CO detector — battery change date, last test, alert noise.",
            keywords: ["smoke detector", "co", "battery", "safety"],
            template: makeType(
                id: "SmokeDetector", name: "Detector", plural: "Smoke Detectors",
                image: "sensor.tag.radiowaves.forward", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Location", kind: .text, required: true),
                    selectField("Type", [
                        ("Smoke", "#666666"), ("CO", "#9D4DCC"),
                        ("Combo smoke/CO", "#3FA9F5"), ("Heat", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Model", kind: .text),
                    FieldDef.make(name: "Last battery change", kind: .date),
                    FieldDef.make(name: "Last tested", kind: .date),
                    FieldDef.make(name: "Replace by", kind: .date),
                ],
                primary: "location", kanban: "type", calendar: "replace_by"
            )
        ),

        Entry(
            id: "lib.furnace_filter",
            category: .home,
            blurb: "Furnace / HVAC filter — change date, MERV rating, brand.",
            keywords: ["furnace", "hvac", "filter", "merv"],
            template: makeType(
                id: "FurnaceFilter", name: "Change", plural: "Furnace Filter",
                image: "rectangle.grid.3x2", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date changed", kind: .date, required: true),
                    FieldDef.make(name: "Size", kind: .text),
                    FieldDef.make(name: "MERV rating", kind: .number),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Next change due", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date_changed", calendar: "next_change_due"
            )
        ),

        Entry(
            id: "lib.water_filter",
            category: .home,
            blurb: "Water filters — whole-house, fridge, shower. Change schedule.",
            keywords: ["water filter", "fridge", "shower", "filter"],
            template: makeType(
                id: "WaterFilter", name: "Change", plural: "Water Filter",
                image: "drop.triangle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date changed", kind: .date, required: true),
                    selectField("Location", [
                        ("Whole house", "#3FA9F5"), ("Kitchen sink", "#9D4DCC"),
                        ("Fridge", "#3FB950"), ("Shower", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Model / cartridge", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Next change due", kind: .date),
                ],
                primary: "date_changed", kanban: "location", calendar: "next_change_due"
            )
        ),

        Entry(
            id: "lib.recall_received",
            category: .home,
            blurb: "Product recalls affecting you — action taken, refund status.",
            keywords: ["recall", "product", "safety", "cpsc"],
            template: makeType(
                id: "ProductRecall", name: "Recall", plural: "Recalls",
                image: "exclamationmark.octagon", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Product", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Recall date", kind: .date, required: true),
                    selectField("Severity", [
                        ("Fire / explosion", "#D14B5C"), ("Injury", "#F08C2E"),
                        ("Allergy / contamination", "#E8A93B"), ("Cosmetic / minor", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Recall #", kind: .text),
                    selectField("Action taken", [
                        ("Returned", "#3FB950"), ("Repaired", "#9D4DCC"),
                        ("Refunded", "#E8A93B"), ("Disposed", "#666666"),
                        ("Pending", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "product", kanban: "action_taken", calendar: "recall_date"
            )
        ),

        Entry(
            id: "lib.lemon_law",
            category: .home,
            blurb: "Lemon law / consumer protection claims — vehicle issue through resolution.",
            keywords: ["lemon law", "consumer", "warranty claim"],
            template: makeType(
                id: "LemonClaim", name: "Claim", plural: "Lemon Claims",
                image: "doc.text.magnifyingglass", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "Manufacturer", kind: .text),
                    FieldDef.make(name: "Purchased on", kind: .date),
                    FieldDef.make(name: "Issue", kind: .longText),
                    FieldDef.make(name: "Repair attempts", kind: .number),
                    selectField("Status", [
                        ("Documenting", "#3FA9F5"), ("Notice sent", "#9D4DCC"),
                        ("In arbitration", "#E8A93B"), ("Won", "#3FB950"),
                        ("Lost", "#D14B5C"), ("Settled", "#666666"),
                    ]),
                    FieldDef.make(name: "Outcome / refund", kind: .longText),
                    FieldDef.make(name: "Documents", kind: .attachment),
                ],
                primary: "subject", kanban: "status", calendar: "purchased_on"
            )
        ),

        Entry(
            id: "lib.hoa_correspondence",
            category: .home,
            blurb: "HOA letters, fees, complaints, votes.",
            keywords: ["hoa", "homeowners", "association", "fees"],
            template: makeType(
                id: "HOACorrespondence", name: "Letter", plural: "HOA Correspondence",
                image: "envelope.badge.shield.half.filled", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Type", [
                        ("Notice", "#3FA9F5"), ("Fee / dues", "#E8A93B"),
                        ("Complaint", "#D14B5C"), ("Vote", "#9D4DCC"),
                        ("Newsletter", "#3FB950"), ("Other", "#666666"),
                    ]),
                    selectField("Status", [
                        ("New", "#3FA9F5"), ("Responded", "#9D4DCC"),
                        ("Paid", "#3FB950"), ("Disputing", "#D14B5C"),
                        ("Closed", "#666666"),
                    ]),
                    FieldDef.make(name: "Document", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "subject", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.permit_license",
            category: .home,
            blurb: "Permits & licenses — building, hunting, fishing, professional. Renewal dates.",
            keywords: ["permit", "license", "renewal", "hunting", "fishing"],
            template: makeType(
                id: "PermitLicense", name: "Permit", plural: "Permits & Licenses",
                image: "checkmark.seal.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Type", [
                        ("Building", "#7B4F2F"), ("Hunting / fishing", "#3FB950"),
                        ("Professional", "#3FA9F5"), ("Driver's", "#9D4DCC"),
                        ("Concealed carry", "#666666"), ("Business", "#E8A93B"),
                        ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Issuing body", kind: .text),
                    FieldDef.make(name: "Permit #", kind: .text),
                    FieldDef.make(name: "Issued", kind: .date),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Document", kind: .attachment),
                ],
                primary: "name", kanban: "type", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.flat_pack_build",
            category: .home,
            blurb: "IKEA / flat-pack assembly — time, problems, missing parts.",
            keywords: ["ikea", "flat pack", "assembly", "furniture", "build"],
            template: makeType(
                id: "FlatPackBuild", name: "Build", plural: "Flat-Pack Builds",
                image: "wrench.and.screwdriver", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Brand / model", kind: .text),
                    FieldDef.make(name: "Build date", kind: .date, required: true),
                    FieldDef.make(name: "Time taken (min)", kind: .number),
                    FieldDef.make(name: "Helpers", kind: .number),
                    selectField("Difficulty", [
                        ("Easy", "#3FB950"), ("Moderate", "#3FA9F5"),
                        ("Hard", "#E8A93B"), ("Brutal", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Missing / damaged parts", kind: .text),
                    FieldDef.make(name: "Notes / tips", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "item", kanban: "difficulty", calendar: "build_date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.smart_home_device",
            category: .home,
            blurb: "Smart home device — hub, firmware, integration notes.",
            keywords: ["smart home", "homekit", "alexa", "google home"],
            template: makeType(
                id: "SmartHomeDevice", name: "Device", plural: "Smart Home Devices",
                image: "homekit", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Brand / model", kind: .text),
                    selectField("Category", [
                        ("Light", "#E8A93B"), ("Lock", "#666666"),
                        ("Camera", "#3FA9F5"), ("Thermostat", "#D14B5C"),
                        ("Plug", "#9D4DCC"), ("Sensor", "#3FB950"),
                        ("Hub", "#F08C2E"), ("Other", "#888888"),
                    ]),
                    selectField("Platform", [
                        ("HomeKit", "#3FA9F5"), ("Google", "#3FB950"),
                        ("Alexa", "#F08C2E"), ("SmartThings", "#9D4DCC"),
                        ("Matter", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Room", kind: .text),
                    FieldDef.make(name: "Firmware version", kind: .text),
                    FieldDef.make(name: "Last firmware update", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "nickname", kanban: "category", calendar: "last_firmware_update", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.iot_device",
            category: .home,
            blurb: "All connected devices — SSID assignment, MAC, network segment.",
            keywords: ["iot", "network", "device", "mac", "wifi"],
            template: makeType(
                id: "IoTDevice", name: "Device", plural: "IoT Inventory",
                image: "network", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Device", kind: .text, required: true),
                    FieldDef.make(name: "MAC address", kind: .text),
                    FieldDef.make(name: "Assigned IP", kind: .text),
                    selectField("Network segment", [
                        ("Main", "#3FA9F5"), ("IoT VLAN", "#9D4DCC"),
                        ("Guest", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Open ports", kind: .text),
                    FieldDef.make(name: "Vendor", kind: .text),
                    selectField("Trust level", [
                        ("Trusted", "#3FB950"), ("Limited", "#E8A93B"),
                        ("Quarantined", "#D14B5C"),
                    ]),
                ],
                primary: "device", kanban: "trust_level"
            )
        ),

        Entry(
            id: "lib.phone_number_history",
            category: .home,
            blurb: "Old phone numbers — when active, why dropped, useful for accounts.",
            keywords: ["phone number", "history", "old", "carrier"],
            template: makeType(
                id: "PhoneNumberHistory", name: "Number", plural: "Phone Number History",
                image: "phone.arrow.up.right", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Phone number", kind: .text, required: true),
                    FieldDef.make(name: "Carrier", kind: .text),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Ended", kind: .date),
                    selectField("Status", [
                        ("Current", "#3FB950"), ("Retired", "#666666"),
                        ("Lost", "#D14B5C"), ("Recycled", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Why dropped", kind: .longText),
                ],
                primary: "phone_number", kanban: "status", calendar: "ended"
            )
        ),

        Entry(
            id: "lib.email_history",
            category: .home,
            blurb: "Email addresses you've used — throwaway / persistent, when, for what.",
            keywords: ["email", "history", "address", "throwaway"],
            template: makeType(
                id: "EmailHistory", name: "Address", plural: "Email Addresses",
                image: "envelope.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Email", kind: .email, required: true),
                    selectField("Purpose", [
                        ("Personal", "#9D4DCC"), ("Work", "#3FA9F5"),
                        ("Shopping", "#E8A93B"), ("Throwaway", "#666666"),
                        ("Newsletter", "#3FB950"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Provider", kind: .text),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Forwarding", "#3FA9F5"),
                        ("Retired", "#666666"), ("Compromised", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "email", kanban: "purpose", calendar: "started"
            )
        ),

        Entry(
            id: "lib.identity_change",
            category: .home,
            blurb: "Identity changes (name, gender marker, citizenship) — when, where filed.",
            keywords: ["identity", "name change", "gender marker", "citizenship"],
            template: makeType(
                id: "IdentityChange", name: "Change", plural: "Identity Changes",
                image: "person.crop.square.filled.and.at.rectangle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Type of change", kind: .text, required: true),
                    FieldDef.make(name: "From", kind: .text),
                    FieldDef.make(name: "To", kind: .text),
                    FieldDef.make(name: "Effective date", kind: .date, required: true),
                    FieldDef.make(name: "Filed with", kind: .text),
                    FieldDef.make(name: "Court / case #", kind: .text),
                    FieldDef.make(name: "Document", kind: .attachment),
                    FieldDef.make(name: "Notes (downstream updates needed)", kind: .longText),
                ],
                primary: "type_of_change", calendar: "effective_date"
            )
        ),

        // MARK: - Money & Finance

        Entry(
            id: "lib.pending_transaction",
            category: .finance,
            blurb: "Pending vs cleared transactions — amount, expected post date.",
            keywords: ["pending", "transaction", "cleared"],
            template: makeType(
                id: "PendingTransaction", name: "Transaction", plural: "Pending Transactions",
                image: "hourglass.circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    FieldDef.make(name: "Authorized on", kind: .date),
                    FieldDef.make(name: "Expected post", kind: .date),
                    FieldDef.make(name: "Account", kind: .link),
                    selectField("Status", [
                        ("Pending", "#E8A93B"), ("Posted", "#3FB950"),
                        ("Disputed", "#D14B5C"), ("Reversed", "#666666"),
                    ]),
                ],
                primary: "description", kanban: "status", calendar: "expected_post"
            )
        ),

        Entry(
            id: "lib.recurring_audit",
            category: .finance,
            blurb: "Annual \"what am I actually paying for?\" review per service.",
            keywords: ["recurring", "audit", "subscription review", "annual"],
            template: makeType(
                id: "RecurringAudit", name: "Review", plural: "Recurring Audits",
                image: "magnifyingglass.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Service", kind: .text, required: true),
                    FieldDef.make(name: "Reviewed on", kind: .date, required: true),
                    FieldDef.make(name: "Annual cost", kind: .number),
                    selectField("Decision", [
                        ("Keep", "#3FB950"), ("Downgrade", "#E8A93B"),
                        ("Cancel", "#D14B5C"), ("Renegotiate", "#9D4DCC"),
                        ("Pause", "#666666"),
                    ]),
                    FieldDef.make(name: "Rationale", kind: .longText),
                    FieldDef.make(name: "Next review", kind: .date),
                ],
                primary: "service", kanban: "decision", calendar: "next_review"
            )
        ),

        Entry(
            id: "lib.lending",
            category: .finance,
            blurb: "Money lent or borrowed to/from friends — terms, repayment.",
            keywords: ["lending", "borrowing", "loan friend", "informal"],
            template: makeType(
                id: "Lending", name: "Loan", plural: "Lendings & Borrowings",
                image: "arrow.left.arrow.right.circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    selectField("Direction", [
                        ("I lent", "#3FA9F5"), ("I borrowed", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Other party", kind: .link),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Expected return", kind: .date),
                    selectField("Status", [
                        ("Outstanding", "#E8A93B"), ("Partial", "#3FA9F5"),
                        ("Paid back", "#3FB950"), ("Forgiven", "#9D4DCC"),
                        ("Bad debt", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "description", kanban: "status", calendar: "expected_return"
            )
        ),

        Entry(
            id: "lib.shared_bill",
            category: .finance,
            blurb: "Group expenses — paid by, owed by, settled? Splitwise-style.",
            keywords: ["splitwise", "shared", "group expense", "split"],
            template: makeType(
                id: "SharedBill", name: "Bill", plural: "Shared Bills",
                image: "person.2.square.stack", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Description", kind: .text, required: true),
                    FieldDef.make(name: "Total amount", kind: .number, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Paid by", kind: .link),
                    FieldDef.make(name: "Split with", kind: .link),
                    FieldDef.make(name: "My share", kind: .number),
                    selectField("Settled", [
                        ("Not yet", "#E8A93B"), ("Partial", "#3FA9F5"),
                        ("Settled", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "description", kanban: "settled", calendar: "date"
            )
        ),

        Entry(
            id: "lib.atm_withdrawal",
            category: .finance,
            blurb: "ATM cash withdrawals — when, where, what for. Traces cash flow.",
            keywords: ["atm", "withdrawal", "cash", "fee"],
            template: makeType(
                id: "ATMWithdrawal", name: "Withdrawal", plural: "ATM Withdrawals",
                image: "banknote.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    FieldDef.make(name: "ATM location", kind: .text),
                    FieldDef.make(name: "ATM fee", kind: .number),
                    FieldDef.make(name: "Account", kind: .link),
                    FieldDef.make(name: "What for", kind: .text),
                ],
                primary: "atm_location", calendar: "date"
            )
        ),

        Entry(
            id: "lib.cash_spent",
            category: .finance,
            blurb: "Off-statement cash transactions — small spend, where cash went.",
            keywords: ["cash", "spent", "small spend", "off books"],
            template: makeType(
                id: "CashSpent", name: "Spend", plural: "Cash Spent",
                image: "dollarsign", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount", kind: .number, required: true),
                    FieldDef.make(name: "Vendor / on what", kind: .text),
                    selectField("Category", [
                        ("Food", "#E8A93B"), ("Tip", "#9D4DCC"),
                        ("Transit", "#3FA9F5"), ("Gift", "#D14B5C"),
                        ("Charity", "#3FB950"), ("Other", "#666666"),
                    ]),
                ],
                primary: "vendor_on_what", kanban: "category", calendar: "date"
            )
        ),

        Entry(
            id: "lib.money_owed",
            category: .finance,
            blurb: "Receivables aging tracker — who owes you, how long.",
            keywords: ["receivable", "owed", "aging", "ar"],
            template: makeType(
                id: "MoneyOwed", name: "Receivable", plural: "Money Owed",
                image: "calendar.badge.exclamationmark", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "From whom", kind: .link, required: true),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Originated", kind: .date),
                    FieldDef.make(name: "Due", kind: .date),
                    FieldDef.make(name: "Days outstanding", kind: .number),
                    selectField("Aging", [
                        ("Current", "#3FB950"), ("30+", "#E8A93B"),
                        ("60+", "#F08C2E"), ("90+", "#D14B5C"),
                        ("Bad debt", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "from_whom", kanban: "aging", calendar: "due"
            )
        ),

        Entry(
            id: "lib.identity_theft",
            category: .finance,
            blurb: "Identity theft incident — date discovered, accounts compromised, resolution steps.",
            keywords: ["identity theft", "fraud", "credit", "compromise"],
            template: makeType(
                id: "IdentityTheft", name: "Incident", plural: "ID Theft Incidents",
                image: "person.crop.circle.badge.exclamationmark", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Summary", kind: .text, required: true),
                    FieldDef.make(name: "Discovered on", kind: .date, required: true),
                    FieldDef.make(name: "Accounts compromised", kind: .longText),
                    FieldDef.make(name: "Estimated loss", kind: .number),
                    selectField("Status", [
                        ("Investigating", "#E8A93B"), ("Freeze placed", "#3FA9F5"),
                        ("FTC reported", "#9D4DCC"), ("Resolved", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Actions taken", kind: .noteLog),
                    FieldDef.make(name: "Police / FTC report #", kind: .text),
                ],
                primary: "summary", kanban: "status", calendar: "discovered_on"
            )
        ),

        Entry(
            id: "lib.bank_fee",
            category: .finance,
            blurb: "Bank fees — date, type, refunded? Pattern detection.",
            keywords: ["fee", "bank", "overdraft", "refund"],
            template: makeType(
                id: "BankFee", name: "Fee", plural: "Bank Fees",
                image: "exclamationmark.bubble", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Account", kind: .link),
                    selectField("Type", [
                        ("Overdraft", "#D14B5C"), ("ATM", "#E8A93B"),
                        ("Wire", "#9D4DCC"), ("Account maintenance", "#666666"),
                        ("Foreign transaction", "#F08C2E"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Refunded?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "date", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.fx_transaction",
            category: .finance,
            blurb: "Currency exchanges done — rate, fees, source/destination currencies.",
            keywords: ["currency", "exchange", "forex", "fx"],
            template: makeType(
                id: "FXTransaction", name: "Exchange", plural: "Currency Exchanges",
                image: "arrow.left.arrow.right", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "From currency", kind: .text),
                    FieldDef.make(name: "From amount", kind: .number),
                    FieldDef.make(name: "To currency", kind: .text),
                    FieldDef.make(name: "To amount", kind: .number),
                    FieldDef.make(name: "Rate", kind: .number),
                    FieldDef.make(name: "Fee", kind: .number),
                    FieldDef.make(name: "Provider", kind: .text),
                ],
                primary: "from_currency", calendar: "date"
            )
        ),

        Entry(
            id: "lib.estate_doc",
            category: .finance,
            blurb: "Estate planning documents — wills, trusts, POA, healthcare directive locations.",
            keywords: ["estate", "will", "trust", "poa", "directive"],
            template: makeType(
                id: "EstateDocument", name: "Document", plural: "Estate Documents",
                image: "doc.text.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Document", kind: .text, required: true),
                    selectField("Type", [
                        ("Will", "#9D4DCC"), ("Trust", "#3FA9F5"),
                        ("Power of attorney", "#E8A93B"), ("Healthcare directive", "#3FB950"),
                        ("Living will", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Signed on", kind: .date),
                    FieldDef.make(name: "Last reviewed", kind: .date),
                    FieldDef.make(name: "Attorney", kind: .link),
                    FieldDef.make(name: "Original location", kind: .text),
                    FieldDef.make(name: "Copy location", kind: .text),
                    FieldDef.make(name: "Scan", kind: .attachment),
                ],
                primary: "document", kanban: "type", calendar: "last_reviewed"
            )
        ),

        Entry(
            id: "lib.beneficiary",
            category: .finance,
            blurb: "Who's on what account — last reviewed.",
            keywords: ["beneficiary", "account", "designation"],
            template: makeType(
                id: "Beneficiary", name: "Designation", plural: "Beneficiaries",
                image: "person.3.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Account / policy", kind: .text, required: true),
                    FieldDef.make(name: "Primary beneficiary", kind: .link),
                    FieldDef.make(name: "Secondary beneficiary", kind: .link),
                    FieldDef.make(name: "Share %", kind: .text),
                    FieldDef.make(name: "Last verified", kind: .date),
                    selectField("Status", [
                        ("Current", "#3FB950"), ("Needs update", "#E8A93B"),
                        ("Stale", "#D14B5C"),
                    ]),
                ],
                primary: "account_policy", kanban: "status", calendar: "last_verified"
            )
        ),

        Entry(
            id: "lib.education_savings",
            category: .finance,
            blurb: "529 / college savings — beneficiary, balance, target.",
            keywords: ["529", "college savings", "education"],
            template: makeType(
                id: "EducationSavings", name: "Plan", plural: "Education Savings",
                image: "graduationcap.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Plan name", kind: .text, required: true),
                    FieldDef.make(name: "Beneficiary", kind: .link),
                    FieldDef.make(name: "Plan provider", kind: .text),
                    selectField("Type", [
                        ("529", "#3FA9F5"), ("Coverdell ESA", "#9D4DCC"),
                        ("UTMA/UGMA", "#E8A93B"), ("Roth", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Current balance", kind: .number),
                    FieldDef.make(name: "Target", kind: .number),
                    FieldDef.make(name: "Monthly contribution", kind: .number),
                    FieldDef.make(name: "Target year", kind: .number),
                ],
                primary: "plan_name", kanban: "type"
            )
        ),

        Entry(
            id: "lib.hsa_fsa",
            category: .finance,
            blurb: "HSA / FSA balance — plan year, balance, eligible expenses.",
            keywords: ["hsa", "fsa", "health savings", "medical"],
            template: makeType(
                id: "HSAFSAAccount", name: "Account", plural: "HSA / FSA",
                image: "cross.case.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Account", kind: .text, required: true),
                    selectField("Type", [
                        ("HSA", "#3FB950"), ("FSA", "#3FA9F5"),
                        ("Dependent care FSA", "#9D4DCC"), ("LPFSA", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Plan year", kind: .number),
                    FieldDef.make(name: "Annual contribution", kind: .number),
                    FieldDef.make(name: "Current balance", kind: .number),
                    FieldDef.make(name: "Use-by date", kind: .date),
                    FieldDef.make(name: "Investment options?", kind: .boolean),
                ],
                primary: "account", kanban: "type", calendar: "use_by_date"
            )
        ),

        Entry(
            id: "lib.annuity",
            category: .finance,
            blurb: "Annuity — issuer, payout schedule, beneficiaries.",
            keywords: ["annuity", "income", "retirement"],
            template: makeType(
                id: "Annuity", name: "Annuity", plural: "Annuities",
                image: "calendar.badge.checkmark", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Issuer", kind: .text, required: true),
                    FieldDef.make(name: "Contract #", kind: .text),
                    selectField("Type", [
                        ("Fixed", "#3FA9F5"), ("Variable", "#9D4DCC"),
                        ("Indexed", "#E8A93B"), ("Immediate", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Premium paid", kind: .number),
                    FieldDef.make(name: "Payout / month", kind: .number),
                    FieldDef.make(name: "Payout starts", kind: .date),
                    FieldDef.make(name: "Beneficiary", kind: .link),
                ],
                primary: "issuer", kanban: "type", calendar: "payout_starts"
            )
        ),

        Entry(
            id: "lib.pension_benefit",
            category: .finance,
            blurb: "Pension benefit — employer, monthly amount, COLA, survivor benefit.",
            keywords: ["pension", "retirement", "benefit"],
            template: makeType(
                id: "PensionBenefit", name: "Pension", plural: "Pensions",
                image: "building.columns.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Employer", kind: .text, required: true),
                    FieldDef.make(name: "Years credited", kind: .number),
                    FieldDef.make(name: "Monthly benefit", kind: .number),
                    FieldDef.make(name: "Start age", kind: .number),
                    FieldDef.make(name: "Cost-of-living adjustment?", kind: .boolean),
                    FieldDef.make(name: "Survivor benefit %", kind: .number),
                    FieldDef.make(name: "Vested?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "employer"
            )
        ),

        Entry(
            id: "lib.estimated_tax",
            category: .finance,
            blurb: "Quarterly tax estimate — Q1–Q4 paid, owed, calculations.",
            keywords: ["estimated tax", "quarterly", "self employed", "1099"],
            template: makeType(
                id: "EstimatedTax", name: "Estimate", plural: "Estimated Taxes",
                image: "doc.text.below.ecg", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Tax year", kind: .number, required: true),
                    selectField("Quarter", [
                        ("Q1 (Apr 15)", "#3FB950"), ("Q2 (Jun 15)", "#3FA9F5"),
                        ("Q3 (Sep 15)", "#9D4DCC"), ("Q4 (Jan 15)", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Due date", kind: .date, required: true),
                    FieldDef.make(name: "Federal owed", kind: .number),
                    FieldDef.make(name: "State owed", kind: .number),
                    FieldDef.make(name: "Federal paid", kind: .number),
                    FieldDef.make(name: "State paid", kind: .number),
                    FieldDef.make(name: "Paid on", kind: .date),
                    selectField("Status", [
                        ("Planned", "#888888"), ("Paid", "#3FB950"),
                        ("Late", "#D14B5C"),
                    ]),
                ],
                primary: "quarter", kanban: "status", calendar: "due_date"
            )
        ),

        Entry(
            id: "lib.crypto_transaction",
            category: .finance,
            blurb: "Crypto transactions — send/receive/swap, fees, tx hash.",
            keywords: ["crypto", "transaction", "txhash", "blockchain"],
            template: makeType(
                id: "CryptoTransaction", name: "Transaction", plural: "Crypto Transactions",
                image: "link.circle", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Type", [
                        ("Buy", "#3FB950"), ("Sell", "#D14B5C"),
                        ("Send", "#3FA9F5"), ("Receive", "#9D4DCC"),
                        ("Swap", "#E8A93B"), ("Stake / unstake", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Asset", kind: .text),
                    FieldDef.make(name: "Quantity", kind: .number),
                    FieldDef.make(name: "USD value at time", kind: .number),
                    FieldDef.make(name: "Fee", kind: .number),
                    FieldDef.make(name: "Counter-party / exchange", kind: .text),
                    FieldDef.make(name: "Tx hash", kind: .text),
                ],
                primary: "asset", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.defi_position",
            category: .finance,
            blurb: "DeFi positions — protocol, pool, APY, risks, last harvested.",
            keywords: ["defi", "yield", "staking", "liquidity"],
            template: makeType(
                id: "DeFiPosition", name: "Position", plural: "DeFi Positions",
                image: "circle.hexagonpath", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Protocol", kind: .text, required: true),
                    FieldDef.make(name: "Pool / pair", kind: .text),
                    FieldDef.make(name: "Chain", kind: .text),
                    FieldDef.make(name: "Principal (USD)", kind: .number),
                    FieldDef.make(name: "Current value", kind: .number),
                    FieldDef.make(name: "APY %", kind: .number),
                    FieldDef.make(name: "Last harvested", kind: .date),
                    selectField("Risk", [
                        ("Low", "#3FB950"), ("Medium", "#E8A93B"),
                        ("High", "#F08C2E"), ("Degen", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "protocol", kanban: "risk", calendar: "last_harvested"
            )
        ),

        Entry(
            id: "lib.nft_owned",
            category: .finance,
            blurb: "NFTs owned — collection, token id, acquired, current floor.",
            keywords: ["nft", "token", "opensea", "collectible"],
            template: makeType(
                id: "NFT", name: "NFT", plural: "NFTs",
                image: "square.grid.3x3", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Collection", kind: .text, required: true),
                    FieldDef.make(name: "Token #", kind: .text),
                    FieldDef.make(name: "Chain", kind: .text),
                    FieldDef.make(name: "Acquired on", kind: .date),
                    FieldDef.make(name: "Cost (USD)", kind: .number),
                    FieldDef.make(name: "Current floor", kind: .number),
                    selectField("Status", [
                        ("Held", "#3FB950"), ("Listed", "#3FA9F5"),
                        ("Sold", "#666666"), ("Burned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Image", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "collection", kanban: "status", calendar: "acquired_on", gallery: "image"
            )
        ),

        Entry(
            id: "lib.dividend",
            category: .finance,
            blurb: "Dividend received — ticker, date, amount, reinvested?",
            keywords: ["dividend", "drip", "income"],
            template: makeType(
                id: "Dividend", name: "Dividend", plural: "Dividends",
                image: "arrow.down.right.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Ticker", kind: .text, required: true),
                    FieldDef.make(name: "Pay date", kind: .date, required: true),
                    FieldDef.make(name: "Amount per share", kind: .number),
                    FieldDef.make(name: "Shares", kind: .number),
                    FieldDef.make(name: "Total received", kind: .number),
                    FieldDef.make(name: "Reinvested?", kind: .boolean),
                    FieldDef.make(name: "Account", kind: .link),
                ],
                primary: "ticker", calendar: "pay_date"
            )
        ),

        Entry(
            id: "lib.corporate_action",
            category: .finance,
            blurb: "Stock split / corporate actions — event, ratio, cost-basis adjustment.",
            keywords: ["split", "corporate action", "spin-off", "merger"],
            template: makeType(
                id: "CorporateAction", name: "Action", plural: "Corporate Actions",
                image: "arrow.triangle.swap", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Ticker", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Type", [
                        ("Stock split", "#3FB950"), ("Reverse split", "#E8A93B"),
                        ("Spin-off", "#9D4DCC"), ("Merger", "#3FA9F5"),
                        ("Buyback", "#F08C2E"), ("Special div", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Ratio / details", kind: .text),
                    FieldDef.make(name: "Cost basis adj", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "ticker", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.ipo_interest",
            category: .finance,
            blurb: "Companies you'd buy on day one or via tender — watchlist with rationale.",
            keywords: ["ipo", "going public", "day one"],
            template: makeType(
                id: "IPOInterest", name: "IPO", plural: "IPOs of Interest",
                image: "sparkles.tv", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Company", kind: .text, required: true),
                    FieldDef.make(name: "Ticker (expected)", kind: .text),
                    FieldDef.make(name: "Filing date", kind: .date),
                    FieldDef.make(name: "Expected pricing", kind: .date),
                    selectField("Plan", [
                        ("Day one", "#3FB950"), ("Wait for dust to settle", "#3FA9F5"),
                        ("Watching", "#E8A93B"), ("Skip", "#666666"),
                    ]),
                    FieldDef.make(name: "Thesis", kind: .richText),
                ],
                primary: "company", kanban: "plan", calendar: "expected_pricing"
            )
        ),

        Entry(
            id: "lib.class_action",
            category: .finance,
            blurb: "Class action lawsuits — settlement received, claim filed, payout.",
            keywords: ["class action", "lawsuit", "settlement"],
            template: makeType(
                id: "ClassAction", name: "Suit", plural: "Class Actions",
                image: "scalemass", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Case name", kind: .text, required: true),
                    FieldDef.make(name: "Defendant", kind: .text),
                    FieldDef.make(name: "Notified on", kind: .date),
                    FieldDef.make(name: "Claim deadline", kind: .date),
                    selectField("Status", [
                        ("Considering", "#888888"), ("Claim filed", "#3FA9F5"),
                        ("Approved", "#9D4DCC"), ("Paid", "#3FB950"),
                        ("Denied", "#D14B5C"), ("Opted out", "#666666"),
                    ]),
                    FieldDef.make(name: "Payout received", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "case_name", kanban: "status", calendar: "claim_deadline"
            )
        ),

        Entry(
            id: "lib.late_payment_chase",
            category: .finance,
            blurb: "Late payments you're chasing — whom, days overdue, next step.",
            keywords: ["chase", "overdue", "late", "collections"],
            template: makeType(
                id: "LatePaymentChase", name: "Chase", plural: "Late Payment Chases",
                image: "phone.arrow.up.right.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Debtor", kind: .link, required: true),
                    FieldDef.make(name: "Invoice / item", kind: .text),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Due", kind: .date),
                    FieldDef.make(name: "Days overdue", kind: .number),
                    FieldDef.make(name: "Last contact", kind: .date),
                    FieldDef.make(name: "Next step", kind: .text),
                    FieldDef.make(name: "Next step date", kind: .date),
                    selectField("Status", [
                        ("Friendly nudge", "#3FA9F5"), ("Firm reminder", "#E8A93B"),
                        ("Final notice", "#F08C2E"), ("Collections", "#D14B5C"),
                        ("Paid", "#3FB950"),
                    ]),
                ],
                primary: "debtor", kanban: "status", calendar: "next_step_date"
            )
        ),

        // MARK: - Food & Drink

        Entry(
            id: "lib.cookbook",
            category: .food,
            blurb: "Cookbooks owned — author, cuisine, recipes-tried count.",
            keywords: ["cookbook", "library", "kitchen", "recipes"],
            template: makeType(
                id: "Cookbook", name: "Cookbook", plural: "Cookbooks",
                image: "books.vertical", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Author", kind: .text),
                    FieldDef.make(name: "Cuisine", kind: .text),
                    FieldDef.make(name: "Year published", kind: .number),
                    FieldDef.make(name: "Recipes tried", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Acquired", kind: .date),
                    selectField("Status", [
                        ("On shelf", "#3FA9F5"), ("Actively cooking from", "#3FB950"),
                        ("Borrowed out", "#E8A93B"), ("Donated", "#666666"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "title", kanban: "status", calendar: "acquired", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.cooking_class",
            category: .food,
            blurb: "Cooking classes taken — instructor, dishes made, level.",
            keywords: ["cooking class", "lesson", "instructor", "culinary"],
            template: makeType(
                id: "CookingClass", name: "Class", plural: "Cooking Classes",
                image: "person.fill.checkmark", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Class title", kind: .text, required: true),
                    FieldDef.make(name: "Instructor", kind: .text),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Venue", kind: .text),
                    FieldDef.make(name: "Cuisine / focus", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Dishes made", kind: .longText),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes / techniques", kind: .richText),
                ],
                primary: "class_title", calendar: "date"
            )
        ),

        Entry(
            id: "lib.cooking_technique",
            category: .food,
            blurb: "Skill you learned (julienne, beurre monté, lamination).",
            keywords: ["technique", "skill", "culinary", "method"],
            template: makeType(
                id: "CookingTechnique", name: "Technique", plural: "Cooking Techniques",
                image: "graduationcap", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Technique", kind: .text, required: true),
                    FieldDef.make(name: "What it does", kind: .longText),
                    selectField("Difficulty", [
                        ("Basic", "#3FB950"), ("Intermediate", "#3FA9F5"),
                        ("Advanced", "#E8A93B"), ("Expert", "#D14B5C"),
                    ]),
                    selectField("Mastery", [
                        ("Learning", "#E8A93B"), ("Functional", "#3FA9F5"),
                        ("Confident", "#9D4DCC"), ("Reliable", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Practice notes", kind: .noteLog),
                ],
                primary: "technique", kanban: "mastery"
            )
        ),

        Entry(
            id: "lib.kitchen_gadget",
            category: .food,
            blurb: "Kitchen gadget reviews — tool, used count, would buy again?",
            keywords: ["gadget", "kitchen", "tool", "appliance"],
            template: makeType(
                id: "KitchenGadget", name: "Gadget", plural: "Kitchen Gadgets",
                image: "fork.knife.circle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Bought on", kind: .date),
                    FieldDef.make(name: "Paid", kind: .number),
                    FieldDef.make(name: "Times used", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    selectField("Verdict", [
                        ("Daily driver", "#3FB950"), ("Useful", "#3FA9F5"),
                        ("Occasional", "#E8A93B"), ("Drawer of shame", "#D14B5C"),
                        ("Sold / gifted", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "item", kanban: "verdict", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sourdough_feed",
            category: .food,
            blurb: "Sourdough starter feeds — time, temperature, behavior.",
            keywords: ["sourdough", "starter", "feed", "fermentation"],
            template: makeType(
                id: "SourdoughFeed", name: "Feed", plural: "Sourdough Feeds",
                image: "drop.degreesign.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "When", kind: .dateTime, required: true),
                    FieldDef.make(name: "Starter name", kind: .text),
                    FieldDef.make(name: "Flour type", kind: .text),
                    FieldDef.make(name: "Hydration %", kind: .number),
                    FieldDef.make(name: "Ambient temp (°F)", kind: .number),
                    FieldDef.make(name: "Hours to peak", kind: .number),
                    selectField("Health", [
                        ("Sluggish", "#E8A93B"), ("Healthy", "#3FA9F5"),
                        ("Vigorous", "#3FB950"), ("Overproofed", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "when", kanban: "health", calendar: "when"
            )
        ),

        Entry(
            id: "lib.bread_loaf",
            category: .food,
            blurb: "Specific bread bake — hydration, crumb photo, what you'd change.",
            keywords: ["bread", "loaf", "crumb", "bake"],
            template: makeType(
                id: "BreadLoaf", name: "Loaf", plural: "Bread Loaves",
                image: "circle.grid.cross", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Recipe / style", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Hydration %", kind: .number),
                    FieldDef.make(name: "Bulk ferment hours", kind: .number),
                    FieldDef.make(name: "Cold retard hours", kind: .number),
                    FieldDef.make(name: "Bake temp (°F)", kind: .number),
                    FieldDef.make(name: "Bake time (min)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    selectField("Crumb", [
                        ("Tight", "#7B4F2F"), ("Even", "#E8A93B"),
                        ("Open", "#3FA9F5"), ("Wild", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Crumb photo", kind: .attachment),
                    FieldDef.make(name: "What I'd change", kind: .longText),
                ],
                primary: "recipe_style", kanban: "crumb", calendar: "date", gallery: "crumb_photo"
            )
        ),

        Entry(
            id: "lib.pasta_fresh",
            category: .food,
            blurb: "Fresh pasta made — type, egg:flour ratio, drying method.",
            keywords: ["pasta", "fresh", "egg", "00"],
            template: makeType(
                id: "PastaFresh", name: "Pasta", plural: "Fresh Pasta",
                image: "wave.3.forward", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Shape", kind: .text),
                    FieldDef.make(name: "Flour type", kind: .text),
                    FieldDef.make(name: "Egg yolks per 100g flour", kind: .number),
                    FieldDef.make(name: "Whole eggs per 100g", kind: .number),
                    FieldDef.make(name: "Rest time (min)", kind: .number),
                    selectField("Drying", [
                        ("Fresh / immediate", "#3FB950"), ("Air-dried", "#E8A93B"),
                        ("Frozen", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "shape", kanban: "drying", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.stock_made",
            category: .food,
            blurb: "Stock made — chicken/veg/beef, hours simmered, yield.",
            keywords: ["stock", "broth", "bone broth", "simmer"],
            template: makeType(
                id: "StockMade", name: "Stock", plural: "Stocks",
                image: "drop.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Type", [
                        ("Chicken", "#E8A93B"), ("Beef / bone", "#7B4F2F"),
                        ("Vegetable", "#3FB950"), ("Fish", "#3FA9F5"),
                        ("Mushroom", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Hours simmered", kind: .number),
                    FieldDef.make(name: "Yield (cups)", kind: .number),
                    FieldDef.make(name: "Frozen in jars / cubes?", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "type", kanban: "type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.jam_batch",
            category: .food,
            blurb: "Jam batches — fruit, pectin, jars yielded.",
            keywords: ["jam", "jelly", "preserves", "fruit"],
            template: makeType(
                id: "JamBatch", name: "Batch", plural: "Jam Batches",
                image: "drop.halffull", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Fruit", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Sugar : fruit ratio", kind: .text),
                    selectField("Pectin", [
                        ("Natural only", "#3FB950"), ("Added powdered", "#3FA9F5"),
                        ("Liquid", "#9D4DCC"), ("Low-sugar", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Jars yielded", kind: .number),
                    FieldDef.make(name: "Set quality", kind: .rating),
                    FieldDef.make(name: "Notes / tweaks", kind: .longText),
                    FieldDef.make(name: "Label photo", kind: .attachment),
                ],
                primary: "fruit", kanban: "pectin", calendar: "date", gallery: "label_photo"
            )
        ),

        Entry(
            id: "lib.canning_batch",
            category: .food,
            blurb: "Canning batch — item, jar count, processing time, lids sealed.",
            keywords: ["canning", "preserving", "jar", "waterbath"],
            template: makeType(
                id: "CanningBatch", name: "Batch", plural: "Canning Batches",
                image: "cylinder.split.1x2", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Method", [
                        ("Water bath", "#3FA9F5"), ("Pressure", "#D14B5C"),
                        ("Steam", "#9D4DCC"), ("Refrigerator pickle", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Processing time (min)", kind: .number),
                    FieldDef.make(name: "Jar size", kind: .text),
                    FieldDef.make(name: "Jars yielded", kind: .number),
                    FieldDef.make(name: "Lids sealed", kind: .number),
                    FieldDef.make(name: "Recipe source", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "method", calendar: "date"
            )
        ),

        Entry(
            id: "lib.pickle_jar",
            category: .food,
            blurb: "Pickle jars — cuke / kraut / other; brine recipe; ready date.",
            keywords: ["pickle", "ferment", "brine", "kraut"],
            template: makeType(
                id: "PickleJar", name: "Jar", plural: "Pickle Jars",
                image: "cylinder.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Type", kind: .text, required: true),
                    FieldDef.make(name: "Started", kind: .date, required: true),
                    FieldDef.make(name: "Salt %", kind: .number),
                    FieldDef.make(name: "Brine recipe", kind: .longText),
                    FieldDef.make(name: "Ready estimate", kind: .date),
                    FieldDef.make(name: "First taste", kind: .date),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "type", calendar: "ready_estimate", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.smoked_meat",
            category: .food,
            blurb: "Smoked meat sessions — cut, wood, temp, time, internal probe.",
            keywords: ["smoke", "bbq", "brisket", "low and slow"],
            template: makeType(
                id: "SmokedMeat", name: "Smoke", plural: "Smoked Meats",
                image: "flame", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Cut", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Wood", [
                        ("Oak", "#7B4F2F"), ("Hickory", "#D14B5C"),
                        ("Cherry", "#F08C2E"), ("Apple", "#3FB950"),
                        ("Pecan", "#9D4DCC"), ("Mesquite", "#666666"),
                        ("Mixed", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Weight (lb)", kind: .number),
                    FieldDef.make(name: "Smoker temp (°F)", kind: .number),
                    FieldDef.make(name: "Hours", kind: .number),
                    FieldDef.make(name: "Probe internal (°F)", kind: .number),
                    FieldDef.make(name: "Rest hours", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Bark / pellicle notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "cut", kanban: "wood", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sous_vide",
            category: .food,
            blurb: "Sous vide cooks — item, temp, time, finish method.",
            keywords: ["sous vide", "anova", "immersion", "circulator"],
            template: makeType(
                id: "SousVideCook", name: "Cook", plural: "Sous Vide Cooks",
                image: "thermometer.high", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Temp (°F)", kind: .number),
                    FieldDef.make(name: "Time (hr)", kind: .number),
                    selectField("Finish method", [
                        ("Sear cast iron", "#D14B5C"), ("Torch", "#F08C2E"),
                        ("Grill", "#7B4F2F"), ("Broil", "#9D4DCC"),
                        ("None", "#666666"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "finish_method", calendar: "date"
            )
        ),

        Entry(
            id: "lib.grill_session",
            category: .food,
            blurb: "Grill session — what was on it, fire type, char level.",
            keywords: ["grill", "bbq", "charcoal", "gas"],
            template: makeType(
                id: "GrillSession", name: "Grill", plural: "Grill Sessions",
                image: "flame.circle.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Fuel", [
                        ("Charcoal lump", "#666666"), ("Charcoal briquette", "#888888"),
                        ("Gas / propane", "#3FA9F5"), ("Wood", "#7B4F2F"),
                    ]),
                    FieldDef.make(name: "What was on", kind: .longText),
                    FieldDef.make(name: "Grill temp (°F)", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Guests", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "what_was_on", kanban: "fuel", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.pizza_place",
            category: .food,
            blurb: "Pizza places — style (NY / Detroit / Neapolitan / Sicilian), rating.",
            keywords: ["pizza", "ny style", "neapolitan", "slice"],
            template: makeType(
                id: "PizzaPlace", name: "Pizzeria", plural: "Pizza Places",
                image: "triangle.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Style", [
                        ("NY", "#D14B5C"), ("Neapolitan", "#3FB950"),
                        ("Detroit", "#9D4DCC"), ("Sicilian", "#E8A93B"),
                        ("Roman tonda", "#F08C2E"), ("Chicago deep", "#3FA9F5"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Best slice", kind: .text),
                    FieldDef.make(name: "Crust rating", kind: .rating),
                    FieldDef.make(name: "Overall rating", kind: .rating),
                    FieldDef.make(name: "Date first tried", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "style", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sushi_place",
            category: .food,
            blurb: "Sushi restaurants — omakase or à la carte, fish freshness.",
            keywords: ["sushi", "omakase", "japanese", "raw"],
            template: makeType(
                id: "SushiPlace", name: "Sushiya", plural: "Sushi Places",
                image: "fish.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Format", [
                        ("Omakase", "#9D4DCC"), ("À la carte", "#3FA9F5"),
                        ("Conveyor", "#E8A93B"), ("Grocery counter", "#666666"),
                    ]),
                    FieldDef.make(name: "Best pieces", kind: .longText),
                    FieldDef.make(name: "Freshness rating", kind: .rating),
                    FieldDef.make(name: "Overall rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "format", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.bbq_joint",
            category: .food,
            blurb: "BBQ joints — style (Texas / Memphis / KC / Carolina), meats sampled.",
            keywords: ["bbq", "smoke", "brisket", "ribs", "texas"],
            template: makeType(
                id: "BBQJoint", name: "Joint", plural: "BBQ Joints",
                image: "flame.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Style", [
                        ("Texas", "#D14B5C"), ("Memphis", "#9D4DCC"),
                        ("Kansas City", "#3FA9F5"), ("Carolina (whole hog)", "#E8A93B"),
                        ("Alabama white", "#F0E68C"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Best meat", kind: .text),
                    FieldDef.make(name: "Sauce notes", kind: .longText),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "style", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.burger_place",
            category: .food,
            blurb: "Burger joints — smash / pub / specialty.",
            keywords: ["burger", "smash", "double", "shack"],
            template: makeType(
                id: "BurgerPlace", name: "Joint", plural: "Burger Places",
                image: "circle.circle", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Style", [
                        ("Smash", "#D14B5C"), ("Pub", "#7B4F2F"),
                        ("Specialty / chef", "#9D4DCC"), ("Fast food", "#E8A93B"),
                        ("Diner classic", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Their best burger", kind: .text),
                    FieldDef.make(name: "Patty rating", kind: .rating),
                    FieldDef.make(name: "Bun rating", kind: .rating),
                    FieldDef.make(name: "Overall rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "style", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.ice_cream_shop",
            category: .food,
            blurb: "Ice cream parlors — flavors tried, favorite.",
            keywords: ["ice cream", "gelato", "soft serve"],
            template: makeType(
                id: "IceCreamShop", name: "Parlor", plural: "Ice Cream Shops",
                image: "swirl.circle", color: "#E8A0B5",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Type", [
                        ("Ice cream", "#E8A0B5"), ("Gelato", "#9D4DCC"),
                        ("Sorbet", "#3FA9F5"), ("Soft serve", "#E8A93B"),
                        ("Frozen custard", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Best flavor", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.donut_shop",
            category: .food,
            blurb: "Donut places — best flavor, would return.",
            keywords: ["donut", "doughnut", "pastry"],
            template: makeType(
                id: "DonutShop", name: "Donut Shop", plural: "Donut Shops",
                image: "circle.dashed", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Style", [
                        ("Old-school / cake", "#7B4F2F"), ("Yeasted / glazed", "#E8A93B"),
                        ("Specialty / artisanal", "#9D4DCC"), ("Vegan", "#3FB950"),
                        ("Filled / Bismarck", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Best donut", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Open early?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "style", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.bakery_visit",
            category: .food,
            blurb: "Bakery visits — what you got, would recommend.",
            keywords: ["bakery", "bread", "pastry", "croissant"],
            template: makeType(
                id: "BakeryVisit", name: "Visit", plural: "Bakery Visits",
                image: "fork.knife.circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Bakery", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Date visited", kind: .date),
                    FieldDef.make(name: "What I got", kind: .longText),
                    FieldDef.make(name: "Bread rating", kind: .rating),
                    FieldDef.make(name: "Pastry rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "bakery", calendar: "date_visited", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.bagel_shop",
            category: .food,
            blurb: "Bagel shops — style, schmear, lox quality.",
            keywords: ["bagel", "schmear", "lox", "deli"],
            template: makeType(
                id: "BagelShop", name: "Shop", plural: "Bagel Shops",
                image: "circle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Shop", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    selectField("Style", [
                        ("NY style", "#D14B5C"), ("Montreal", "#9D4DCC"),
                        ("Chewy / hearth", "#7B4F2F"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Best variety", kind: .text),
                    FieldDef.make(name: "Schmear quality", kind: .rating),
                    FieldDef.make(name: "Lox quality", kind: .rating),
                    FieldDef.make(name: "Overall rating", kind: .rating),
                ],
                primary: "shop", kanban: "style"
            )
        ),

        Entry(
            id: "lib.diner",
            category: .food,
            blurb: "Diners / breakfast spots — pancakes, hash, atmosphere.",
            keywords: ["diner", "breakfast", "pancake", "hash"],
            template: makeType(
                id: "DinerSpot", name: "Diner", plural: "Diners",
                image: "fork.knife", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Pancake rating", kind: .rating),
                    FieldDef.make(name: "Hash browns rating", kind: .rating),
                    FieldDef.make(name: "Atmosphere", kind: .text),
                    FieldDef.make(name: "Best dish", kind: .text),
                    FieldDef.make(name: "Open 24h?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.food_truck",
            category: .food,
            blurb: "Food trucks — location, when seen, what they serve.",
            keywords: ["food truck", "street food", "vendor"],
            template: makeType(
                id: "FoodTruck", name: "Truck", plural: "Food Trucks",
                image: "truck.box", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Cuisine", kind: .text),
                    FieldDef.make(name: "Last seen", kind: .text),
                    FieldDef.make(name: "Social handle", kind: .text),
                    FieldDef.make(name: "Best item", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.popup_dinner",
            category: .food,
            blurb: "Pop-up dinners — chef, theme, venue, courses.",
            keywords: ["pop-up", "dinner", "supper club", "tasting"],
            template: makeType(
                id: "PopUpDinner", name: "Pop-Up", plural: "Pop-Up Dinners",
                image: "moon.stars.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Theme / name", kind: .text, required: true),
                    FieldDef.make(name: "Chef", kind: .text),
                    FieldDef.make(name: "Venue", kind: .text),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Course count", kind: .number),
                    FieldDef.make(name: "Highlights", kind: .longText),
                    FieldDef.make(name: "Cost / pp", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "theme_name", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.tasting_menu",
            category: .food,
            blurb: "Tasting menus — restaurant, course count, wine pairing.",
            keywords: ["tasting menu", "michelin", "courses", "pairing"],
            template: makeType(
                id: "TastingMenu", name: "Tasting", plural: "Tasting Menus",
                image: "list.bullet.below.rectangle", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Restaurant", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Course count", kind: .number),
                    FieldDef.make(name: "Wine pairing?", kind: .boolean),
                    FieldDef.make(name: "Cost / pp", kind: .number),
                    FieldDef.make(name: "Stand-out course", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Menu photo", kind: .attachment),
                    FieldDef.make(name: "Reflection", kind: .richText),
                ],
                primary: "restaurant", calendar: "date", gallery: "menu_photo"
            )
        ),

        Entry(
            id: "lib.sommelier",
            category: .food,
            blurb: "Sommeliers encountered — who, where, recommendations they gave.",
            keywords: ["sommelier", "som", "wine", "pairing"],
            template: makeType(
                id: "Sommelier", name: "Sommelier", plural: "Sommeliers",
                image: "wineglass.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Restaurant", kind: .text),
                    FieldDef.make(name: "Met on", kind: .date),
                    FieldDef.make(name: "Their recommendations", kind: .richText),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "name", calendar: "met_on"
            )
        ),

        Entry(
            id: "lib.chef_met",
            category: .food,
            blurb: "Chefs met — when, dish they made for you, photo.",
            keywords: ["chef", "kitchen", "cook"],
            template: makeType(
                id: "ChefMet", name: "Chef", plural: "Chefs Met",
                image: "person.fill.badge.plus", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Restaurant", kind: .text),
                    FieldDef.make(name: "Met on", kind: .date),
                    FieldDef.make(name: "Dish they made", kind: .text),
                    FieldDef.make(name: "Story", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", calendar: "met_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.wine_club",
            category: .food,
            blurb: "Wine club shipments — club, bottles, drink dates.",
            keywords: ["wine club", "shipment", "subscription"],
            template: makeType(
                id: "WineClub", name: "Shipment", plural: "Wine Club",
                image: "shippingbox.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Club", kind: .text, required: true),
                    FieldDef.make(name: "Shipment date", kind: .date, required: true),
                    FieldDef.make(name: "Bottles", kind: .longText),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Drink window", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "club", calendar: "shipment_date"
            )
        ),

        Entry(
            id: "lib.beer_of_month",
            category: .food,
            blurb: "Beer of the month subscription — source, beers shipped, ratings.",
            keywords: ["beer of month", "subscription", "club", "craft"],
            template: makeType(
                id: "BeerOfMonth", name: "Shipment", plural: "Beer of the Month",
                image: "mug.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Source", kind: .text, required: true),
                    FieldDef.make(name: "Shipped on", kind: .date, required: true),
                    FieldDef.make(name: "Beers included", kind: .longText),
                    FieldDef.make(name: "Best of the box", kind: .text),
                    FieldDef.make(name: "Worst of the box", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                ],
                primary: "source", calendar: "shipped_on"
            )
        ),

        Entry(
            id: "lib.mystery_box",
            category: .food,
            blurb: "Try-the-world style box subscriptions — origin country, items.",
            keywords: ["mystery box", "try the world", "snack", "international"],
            template: makeType(
                id: "MysteryBox", name: "Box", plural: "Mystery Boxes",
                image: "shippingbox", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Box theme / month", kind: .text, required: true),
                    FieldDef.make(name: "Country of origin", kind: .text),
                    FieldDef.make(name: "Received on", kind: .date),
                    FieldDef.make(name: "Items inside", kind: .longText),
                    FieldDef.make(name: "Favorite", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Rating", kind: .rating),
                ],
                primary: "box_theme_month", calendar: "received_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.spice",
            category: .food,
            blurb: "Spice pantry — spice, source, opened date, freshness.",
            keywords: ["spice", "pantry", "freshness", "seasoning"],
            template: makeType(
                id: "Spice", name: "Spice", plural: "Spice Pantry",
                image: "leaf.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Spice", kind: .text, required: true),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Bought", kind: .date),
                    FieldDef.make(name: "Opened", kind: .date),
                    selectField("Freshness", [
                        ("Fresh", "#3FB950"), ("Decent", "#E8A93B"),
                        ("Old", "#F08C2E"), ("Replace", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Form", kind: .text, description: "Whole / ground / leaf"),
                    FieldDef.make(name: "Storage location", kind: .text),
                ],
                primary: "spice", kanban: "freshness", calendar: "opened"
            )
        ),

        Entry(
            id: "lib.spice_blend",
            category: .food,
            blurb: "Spice blends you've made — mix, ratio, what it's for.",
            keywords: ["spice blend", "rub", "mix", "seasoning"],
            template: makeType(
                id: "SpiceBlend", name: "Blend", plural: "Spice Blends",
                image: "scribble.variable", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Blend name", kind: .text, required: true),
                    FieldDef.make(name: "Made on", kind: .date),
                    FieldDef.make(name: "Recipe / ratios", kind: .richText),
                    FieldDef.make(name: "Use for", kind: .text),
                    FieldDef.make(name: "Yield (g)", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "blend_name", calendar: "made_on"
            )
        ),

        Entry(
            id: "lib.food_seed",
            category: .food,
            blurb: "Seeds for the food garden — heirloom / hybrid, source, planting depth.",
            keywords: ["seed", "garden", "planting", "heirloom"],
            template: makeType(
                id: "FoodSeed", name: "Seed", plural: "Food Seeds",
                image: "leaf.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Variety", kind: .text, required: true),
                    FieldDef.make(name: "Species", kind: .text),
                    selectField("Type", [
                        ("Heirloom", "#9D4DCC"), ("Hybrid", "#3FA9F5"),
                        ("Open-pollinated", "#3FB950"), ("Organic", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Source", kind: .text),
                    FieldDef.make(name: "Planting depth (in)", kind: .number),
                    FieldDef.make(name: "Days to maturity", kind: .number),
                    FieldDef.make(name: "Year acquired", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "variety", kanban: "type"
            )
        ),

        Entry(
            id: "lib.microgreen",
            category: .food,
            blurb: "Microgreen trays — variety, sow date, harvest day.",
            keywords: ["microgreen", "tray", "indoor garden"],
            template: makeType(
                id: "Microgreen", name: "Tray", plural: "Microgreens",
                image: "sprinkler.and.droplets", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Variety", kind: .text, required: true),
                    FieldDef.make(name: "Sown on", kind: .date, required: true),
                    FieldDef.make(name: "Days to germination", kind: .number),
                    FieldDef.make(name: "Days to harvest", kind: .number),
                    FieldDef.make(name: "Harvest day", kind: .date),
                    FieldDef.make(name: "Yield (g)", kind: .number),
                    selectField("Outcome", [
                        ("Bumper", "#3FB950"), ("Good", "#3FA9F5"),
                        ("Meh", "#E8A93B"), ("Failed", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "variety", kanban: "outcome", calendar: "harvest_day", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sprout_batch",
            category: .food,
            blurb: "Sprout batches — seed, soak time, rinse schedule.",
            keywords: ["sprout", "alfalfa", "mung", "lentil"],
            template: makeType(
                id: "SproutBatch", name: "Batch", plural: "Sprout Batches",
                image: "leaf", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Seed", kind: .text, required: true),
                    FieldDef.make(name: "Started", kind: .date, required: true),
                    FieldDef.make(name: "Soak hours", kind: .number),
                    FieldDef.make(name: "Rinse per day", kind: .number),
                    FieldDef.make(name: "Days to ready", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "seed", calendar: "started", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.cheese_plate",
            category: .food,
            blurb: "Cheese plates you've composed — cheeses, pairings, occasion.",
            keywords: ["cheese plate", "board", "pairing"],
            template: makeType(
                id: "CheesePlate", name: "Plate", plural: "Cheese Plates",
                image: "circle.grid.2x1", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Occasion", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Cheeses (list)", kind: .longText),
                    FieldDef.make(name: "Accompaniments", kind: .longText),
                    FieldDef.make(name: "Pairing notes", kind: .longText),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "occasion", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.charcuterie_board",
            category: .food,
            blurb: "Charcuterie boards — meats, accompaniments, photo.",
            keywords: ["charcuterie", "board", "meat", "plate"],
            template: makeType(
                id: "CharcuterieBoard", name: "Board", plural: "Charcuterie Boards",
                image: "square.grid.2x2", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Occasion", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Meats", kind: .longText),
                    FieldDef.make(name: "Cheeses", kind: .longText),
                    FieldDef.make(name: "Accompaniments", kind: .longText),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "occasion", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.best_meal",
            category: .food,
            blurb: "Lifetime best meals — by year. Where, with whom, what.",
            keywords: ["best meal", "memorable", "top", "all-time"],
            template: makeType(
                id: "BestMeal", name: "Meal", plural: "Best Meals",
                image: "trophy", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title / dish", kind: .text, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "With whom", kind: .link),
                    FieldDef.make(name: "Why it stood out", kind: .richText),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "title_dish", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.restaurant_revisit",
            category: .food,
            blurb: "Restaurants I want to revisit — place, dish I want next time.",
            keywords: ["revisit", "restaurant", "next time", "queue"],
            template: makeType(
                id: "RestaurantRevisit", name: "Revisit", plural: "Restaurants to Revisit",
                image: "arrow.uturn.right.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Restaurant", kind: .link, required: true),
                    FieldDef.make(name: "What I missed", kind: .text),
                    FieldDef.make(name: "Dish I want next time", kind: .text),
                    selectField("Priority", [
                        ("Someday", "#666666"), ("Next visit there", "#3FA9F5"),
                        ("Plan a trip back", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "dish_i_want_next_time", kanban: "priority"
            )
        ),

        // MARK: - Travel & Places

        Entry(
            id: "lib.license_plate_sighting",
            category: .travel,
            blurb: "Spot license plates from all 50 states + DC — classic road-trip game with provenance, dates, photos.",
            keywords: ["license plate", "state", "plate game", "road trip", "spotting"],
            template: ObjectType(
                id: "LicensePlateSighting",
                name: "Sighting",
                pluralName: "License Plate Sightings",
                systemImage: "car.rear",
                colorHex: "#3FA9F5",
                fields: [
                    FieldDef.make(
                        name: "State",
                        kind: .select,
                        options: [
                            FieldOption.make("Alabama", colorHex: "#D14B5C"),
                            FieldOption.make("Alaska", colorHex: "#3FA9F5"),
                            FieldOption.make("Arizona", colorHex: "#E8A93B"),
                            FieldOption.make("Arkansas", colorHex: "#3FB950"),
                            FieldOption.make("California", colorHex: "#F08C2E"),
                            FieldOption.make("Colorado", colorHex: "#9D4DCC"),
                            FieldOption.make("Connecticut", colorHex: "#D14B5C"),
                            FieldOption.make("Delaware", colorHex: "#3FA9F5"),
                            FieldOption.make("Florida", colorHex: "#E8A93B"),
                            FieldOption.make("Georgia", colorHex: "#3FB950"),
                            FieldOption.make("Hawaii", colorHex: "#F08C2E"),
                            FieldOption.make("Idaho", colorHex: "#9D4DCC"),
                            FieldOption.make("Illinois", colorHex: "#D14B5C"),
                            FieldOption.make("Indiana", colorHex: "#3FA9F5"),
                            FieldOption.make("Iowa", colorHex: "#E8A93B"),
                            FieldOption.make("Kansas", colorHex: "#3FB950"),
                            FieldOption.make("Kentucky", colorHex: "#F08C2E"),
                            FieldOption.make("Louisiana", colorHex: "#9D4DCC"),
                            FieldOption.make("Maine", colorHex: "#D14B5C"),
                            FieldOption.make("Maryland", colorHex: "#3FA9F5"),
                            FieldOption.make("Massachusetts", colorHex: "#E8A93B"),
                            FieldOption.make("Michigan", colorHex: "#3FB950"),
                            FieldOption.make("Minnesota", colorHex: "#F08C2E"),
                            FieldOption.make("Mississippi", colorHex: "#9D4DCC"),
                            FieldOption.make("Missouri", colorHex: "#D14B5C"),
                            FieldOption.make("Montana", colorHex: "#3FA9F5"),
                            FieldOption.make("Nebraska", colorHex: "#E8A93B"),
                            FieldOption.make("Nevada", colorHex: "#3FB950"),
                            FieldOption.make("New Hampshire", colorHex: "#F08C2E"),
                            FieldOption.make("New Jersey", colorHex: "#9D4DCC"),
                            FieldOption.make("New Mexico", colorHex: "#D14B5C"),
                            FieldOption.make("New York", colorHex: "#3FA9F5"),
                            FieldOption.make("North Carolina", colorHex: "#E8A93B"),
                            FieldOption.make("North Dakota", colorHex: "#3FB950"),
                            FieldOption.make("Ohio", colorHex: "#F08C2E"),
                            FieldOption.make("Oklahoma", colorHex: "#9D4DCC"),
                            FieldOption.make("Oregon", colorHex: "#D14B5C"),
                            FieldOption.make("Pennsylvania", colorHex: "#3FA9F5"),
                            FieldOption.make("Rhode Island", colorHex: "#E8A93B"),
                            FieldOption.make("South Carolina", colorHex: "#3FB950"),
                            FieldOption.make("South Dakota", colorHex: "#F08C2E"),
                            FieldOption.make("Tennessee", colorHex: "#9D4DCC"),
                            FieldOption.make("Texas", colorHex: "#D14B5C"),
                            FieldOption.make("Utah", colorHex: "#3FA9F5"),
                            FieldOption.make("Vermont", colorHex: "#E8A93B"),
                            FieldOption.make("Virginia", colorHex: "#3FB950"),
                            FieldOption.make("Washington", colorHex: "#F08C2E"),
                            FieldOption.make("West Virginia", colorHex: "#9D4DCC"),
                            FieldOption.make("Wisconsin", colorHex: "#D14B5C"),
                            FieldOption.make("Wyoming", colorHex: "#3FA9F5"),
                            FieldOption.make("District of Columbia", colorHex: "#9D4DCC"),
                        ],
                        required: true
                    ),
                    FieldDef.make(name: "Date spotted", kind: .date, required: true),
                    FieldDef.make(name: "City spotted in", kind: .text),
                    FieldDef.make(name: "Plate text", kind: .text),
                    FieldDef.make(name: "Vanity plate?", kind: .boolean),
                    FieldDef.make(name: "Special edition / theme", kind: .text,
                                  description: "e.g. 'Wildlife', '50 years' commemorative"),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                builtIn: false,
                primaryFieldKey: "state",
                kanbanGroupKey: "state",
                calendarDateKey: "date_spotted",
                galleryAttachmentKey: "photo",
                updatedAt: nil
            )
        ),

        Entry(
            id: "lib.airport_visited",
            category: .travel,
            blurb: "Airport lifer list — code, first visit, layover count.",
            keywords: ["airport", "iata", "layover", "lifer"],
            template: makeType(
                id: "AirportVisited", name: "Airport", plural: "Airports Visited",
                image: "airplane.arrival", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Airport code", kind: .text, required: true),
                    FieldDef.make(name: "Airport name", kind: .text),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "First visit", kind: .date),
                    FieldDef.make(name: "Visit count", kind: .number),
                    selectField("Best reason", [
                        ("Origin / home", "#3FB950"), ("Destination", "#3FA9F5"),
                        ("Layover only", "#E8A93B"), ("Just transited", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "airport_code", kanban: "best_reason", calendar: "first_visit"
            )
        ),

        Entry(
            id: "lib.train_station_visited",
            category: .travel,
            blurb: "Train stations visited — name, country, photo.",
            keywords: ["train station", "rail", "station", "depot"],
            template: makeType(
                id: "TrainStationVisited", name: "Station", plural: "Train Stations",
                image: "tram.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Station", kind: .text, required: true),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "First visit", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "station", calendar: "first_visit", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.subway_system",
            category: .travel,
            blurb: "Subway / metro systems ridden — city, lines used.",
            keywords: ["subway", "metro", "tube", "underground"],
            template: makeType(
                id: "SubwaySystem", name: "System", plural: "Subway Systems",
                image: "arrow.triangle.branch", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "City", kind: .text, required: true),
                    FieldDef.make(name: "System name", kind: .text),
                    FieldDef.make(name: "First ridden", kind: .date),
                    FieldDef.make(name: "Lines used", kind: .longText),
                    FieldDef.make(name: "Stations visited", kind: .number),
                    FieldDef.make(name: "Map photo", kind: .attachment),
                ],
                primary: "city", calendar: "first_ridden", gallery: "map_photo"
            )
        ),

        Entry(
            id: "lib.transit_pass",
            category: .travel,
            blurb: "Public transit passes held — city, type, balance.",
            keywords: ["transit", "pass", "metro card", "oyster"],
            template: makeType(
                id: "TransitPass", name: "Pass", plural: "Transit Passes",
                image: "creditcard.viewfinder", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "City / system", kind: .text, required: true),
                    FieldDef.make(name: "Pass type", kind: .text),
                    FieldDef.make(name: "Balance", kind: .number),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Card photo", kind: .attachment),
                ],
                primary: "city_system", calendar: "expires", gallery: "card_photo"
            )
        ),

        Entry(
            id: "lib.rideshare",
            category: .travel,
            blurb: "Lyft / Uber rides — date, route, cost, driver rating exchange.",
            keywords: ["lyft", "uber", "rideshare", "taxi"],
            template: makeType(
                id: "Rideshare", name: "Ride", plural: "Rideshare Trips",
                image: "car.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "From", kind: .text),
                    FieldDef.make(name: "To", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Tip", kind: .number),
                    selectField("Service", [
                        ("Lyft", "#D14B5C"), ("Uber", "#666666"),
                        ("Local taxi", "#E8A93B"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Rating given", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "from", kanban: "service", calendar: "date"
            )
        ),

        Entry(
            id: "lib.foreign_currency_wallet",
            category: .travel,
            blurb: "Foreign currency in your wallet — currency, amount, where from.",
            keywords: ["foreign currency", "cash", "wallet", "travel"],
            template: makeType(
                id: "ForeignCurrency", name: "Cash", plural: "Foreign Currency",
                image: "dollarsign.arrow.circlepath", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Currency", kind: .text, required: true),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "From trip", kind: .link),
                    FieldDef.make(name: "Picked up on", kind: .date),
                    FieldDef.make(name: "USD value approx", kind: .number),
                    FieldDef.make(name: "Storage location", kind: .text),
                ],
                primary: "currency", calendar: "picked_up_on"
            )
        ),

        Entry(
            id: "lib.passport_stamp",
            category: .travel,
            blurb: "Passport stamps collected — country, entry/exit date.",
            keywords: ["passport", "stamp", "entry", "exit"],
            template: makeType(
                id: "PassportStamp", name: "Stamp", plural: "Passport Stamps",
                image: "checkmark.seal", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Country", kind: .text, required: true),
                    selectField("Direction", [
                        ("Entry", "#3FB950"), ("Exit", "#3FA9F5"),
                        ("Transit", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Port of entry", kind: .text),
                    FieldDef.make(name: "Passport page #", kind: .number),
                    FieldDef.make(name: "Stamp photo", kind: .attachment),
                ],
                primary: "country", kanban: "direction", calendar: "date", gallery: "stamp_photo"
            )
        ),

        Entry(
            id: "lib.customs_declaration",
            category: .travel,
            blurb: "Customs declarations — country, what you declared.",
            keywords: ["customs", "declare", "border"],
            template: makeType(
                id: "CustomsDeclaration", name: "Declaration", plural: "Customs Declarations",
                image: "doc.text.magnifyingglass", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Country", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Items declared", kind: .longText),
                    FieldDef.make(name: "Total value declared", kind: .number),
                    selectField("Outcome", [
                        ("Cleared", "#3FB950"), ("Duty paid", "#E8A93B"),
                        ("Held for inspection", "#F08C2E"), ("Refused entry", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "country", kanban: "outcome", calendar: "date"
            )
        ),

        Entry(
            id: "lib.cruise_excursion",
            category: .travel,
            blurb: "Cruise excursions — port, tour, rating.",
            keywords: ["cruise", "shore excursion", "port", "tour"],
            template: makeType(
                id: "CruiseExcursion", name: "Excursion", plural: "Cruise Excursions",
                image: "ferry.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Cruise", kind: .link),
                    FieldDef.make(name: "Port", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Tour / activity", kind: .text),
                    FieldDef.make(name: "Cost / pp", kind: .number),
                    FieldDef.make(name: "Booked through", kind: .text, description: "Cruise line / independent"),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "tour_activity", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.tour_booked",
            category: .travel,
            blurb: "Booked tours — operator, tour, date, included.",
            keywords: ["tour", "guide", "booked", "operator"],
            template: makeType(
                id: "TourBooked", name: "Tour", plural: "Tours Booked",
                image: "map.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Tour name", kind: .text, required: true),
                    FieldDef.make(name: "Operator", kind: .text),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Cost / pp", kind: .number),
                    FieldDef.make(name: "What's included", kind: .longText),
                    FieldDef.make(name: "Confirmation #", kind: .text),
                    selectField("Status", [
                        ("Booked", "#3FA9F5"), ("Paid", "#9D4DCC"),
                        ("Completed", "#3FB950"), ("Cancelled", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                ],
                primary: "tour_name", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.local_guide",
            category: .travel,
            blurb: "Local guides hired — name, country, contact for return trips.",
            keywords: ["guide", "local", "tour guide"],
            template: makeType(
                id: "LocalGuide", name: "Guide", plural: "Local Guides",
                image: "person.fill.checkmark", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "City / region", kind: .text),
                    FieldDef.make(name: "Contact", kind: .text),
                    FieldDef.make(name: "Languages", kind: .text),
                    FieldDef.make(name: "Specialty", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "name"
            )
        ),

        Entry(
            id: "lib.lounge_access",
            category: .travel,
            blurb: "Airport lounge visits — airport, lounge, how accessed.",
            keywords: ["lounge", "priority pass", "airline lounge"],
            template: makeType(
                id: "LoungeAccess", name: "Visit", plural: "Lounge Visits",
                image: "sofa.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Lounge", kind: .text, required: true),
                    FieldDef.make(name: "Airport", kind: .text),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Accessed via", [
                        ("Priority Pass", "#3FA9F5"), ("Airline status", "#9D4DCC"),
                        ("Credit card", "#E8A93B"), ("Paid day pass", "#F08C2E"),
                        ("Guest of member", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Highlights", kind: .longText),
                ],
                primary: "lounge", kanban: "accessed_via", calendar: "date"
            )
        ),

        Entry(
            id: "lib.hotel_chain_status",
            category: .travel,
            blurb: "Hotel chain loyalty status — chain, tier, nights this year.",
            keywords: ["hotel status", "loyalty", "marriott", "hilton"],
            template: makeType(
                id: "HotelStatus", name: "Status", plural: "Hotel Status",
                image: "building.2.crop.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Chain", kind: .text, required: true),
                    FieldDef.make(name: "Member #", kind: .text),
                    selectField("Tier", [
                        ("Base", "#888888"), ("Silver", "#666666"),
                        ("Gold", "#E8A93B"), ("Platinum", "#9D4DCC"),
                        ("Diamond / Ambassador", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Nights YTD", kind: .number),
                    FieldDef.make(name: "Points balance", kind: .number),
                    FieldDef.make(name: "Tier expires", kind: .date),
                ],
                primary: "chain", kanban: "tier", calendar: "tier_expires"
            )
        ),

        Entry(
            id: "lib.suite_upgrade",
            category: .travel,
            blurb: "Suite upgrades — when, how, gratitude.",
            keywords: ["upgrade", "suite", "complimentary"],
            template: makeType(
                id: "SuiteUpgrade", name: "Upgrade", plural: "Suite Upgrades",
                image: "sparkles", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Hotel", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Original room", kind: .text),
                    FieldDef.make(name: "Upgraded to", kind: .text),
                    selectField("Reason", [
                        ("Status", "#9D4DCC"), ("Anniversary", "#D14B5C"),
                        ("Available", "#3FB950"), ("Customer service recovery", "#E8A93B"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Estimated value", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "hotel", kanban: "reason", calendar: "date"
            )
        ),

        Entry(
            id: "lib.miles_balance",
            category: .travel,
            blurb: "Program balances — program, balance, expiry.",
            keywords: ["miles", "points", "balance", "expiring"],
            template: makeType(
                id: "MilesBalance", name: "Balance", plural: "Miles & Points",
                image: "ticket.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Program", kind: .text, required: true),
                    FieldDef.make(name: "Balance", kind: .number, required: true),
                    FieldDef.make(name: "As of", kind: .date, required: true),
                    FieldDef.make(name: "Expires", kind: .date),
                    selectField("Currency type", [
                        ("Airline miles", "#3FA9F5"), ("Hotel points", "#9D4DCC"),
                        ("Credit card points", "#E8A93B"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "program", kanban: "currency_type", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.award_flight",
            category: .travel,
            blurb: "Award flights booked — origin/dest, miles used.",
            keywords: ["award", "miles", "free flight", "redemption"],
            template: makeType(
                id: "AwardFlight", name: "Award", plural: "Award Flights",
                image: "airplane.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Route", kind: .text, required: true),
                    FieldDef.make(name: "Airline", kind: .text),
                    FieldDef.make(name: "Booked on", kind: .date),
                    FieldDef.make(name: "Flying on", kind: .date),
                    FieldDef.make(name: "Miles spent", kind: .number),
                    FieldDef.make(name: "Taxes / fees", kind: .number),
                    FieldDef.make(name: "Cash equivalent", kind: .number),
                    FieldDef.make(name: "Confirmation", kind: .text),
                    selectField("Status", [
                        ("Booked", "#3FA9F5"), ("Flown", "#3FB950"),
                        ("Cancelled", "#D14B5C"),
                    ]),
                ],
                primary: "route", kanban: "status", calendar: "flying_on"
            )
        ),

        Entry(
            id: "lib.bumped_flight",
            category: .travel,
            blurb: "Bumped from flight — date, compensation, new flight.",
            keywords: ["bumped", "volunteer", "compensation", "voucher"],
            template: makeType(
                id: "BumpedFlight", name: "Bump", plural: "Bumped Flights",
                image: "arrow.triangle.swap", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Original flight", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Reason", [
                        ("Voluntary", "#3FB950"), ("Involuntary", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Compensation type", kind: .text),
                    FieldDef.make(name: "Compensation value", kind: .number),
                    FieldDef.make(name: "Rebooked flight", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "original_flight", kanban: "reason", calendar: "date"
            )
        ),

        Entry(
            id: "lib.cancelled_flight",
            category: .travel,
            blurb: "Cancelled flights — original, replacement, comp.",
            keywords: ["cancelled", "irregular ops", "rebook"],
            template: makeType(
                id: "CancelledFlight", name: "Cancellation", plural: "Cancelled Flights",
                image: "x.circle.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Original flight", kind: .text, required: true),
                    FieldDef.make(name: "Original date", kind: .dateTime, required: true),
                    selectField("Reason given", [
                        ("Weather", "#3FA9F5"), ("Mechanical", "#E8A93B"),
                        ("Crew", "#9D4DCC"), ("ATC", "#666666"),
                        ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Replacement flight", kind: .text),
                    FieldDef.make(name: "Delay (hours)", kind: .number),
                    FieldDef.make(name: "Compensation received", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "original_flight", kanban: "reason_given", calendar: "original_date"
            )
        ),

        Entry(
            id: "lib.lost_luggage",
            category: .travel,
            blurb: "Lost luggage events — bag, where, return time.",
            keywords: ["lost luggage", "baggage", "delayed bag"],
            template: makeType(
                id: "LostLuggage", name: "Event", plural: "Lost Luggage Events",
                image: "bag.fill.badge.questionmark", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Airline", kind: .text, required: true),
                    FieldDef.make(name: "Flight", kind: .text),
                    FieldDef.make(name: "Date lost", kind: .date, required: true),
                    FieldDef.make(name: "Date returned", kind: .date),
                    FieldDef.make(name: "Bag description", kind: .text),
                    FieldDef.make(name: "PIR reference", kind: .text),
                    FieldDef.make(name: "Compensation", kind: .number),
                    selectField("Outcome", [
                        ("Returned", "#3FB950"), ("Damaged", "#E8A93B"),
                        ("Lost permanently", "#D14B5C"),
                    ]),
                ],
                primary: "bag_description", kanban: "outcome", calendar: "date_lost"
            )
        ),

        Entry(
            id: "lib.packing_list",
            category: .travel,
            blurb: "Carry-on packing lists — by trip type. Reusable.",
            keywords: ["packing list", "carry-on", "checklist"],
            template: makeType(
                id: "PackingList", name: "List", plural: "Packing Lists",
                image: "list.bullet.rectangle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Trip type", kind: .text, required: true),
                    selectField("Climate", [
                        ("Cold", "#3FA9F5"), ("Temperate", "#3FB950"),
                        ("Hot", "#E8A93B"), ("Tropical", "#F08C2E"),
                        ("Mixed", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Items", kind: .richText),
                    FieldDef.make(name: "Days covered", kind: .number),
                    FieldDef.make(name: "Last used", kind: .date),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "trip_type", kanban: "climate", calendar: "last_used"
            )
        ),

        Entry(
            id: "lib.foreign_sim",
            category: .travel,
            blurb: "Foreign SIM cards — carrier, country, data plan.",
            keywords: ["sim", "foreign", "carrier", "travel data"],
            template: makeType(
                id: "ForeignSIM", name: "SIM", plural: "Foreign SIMs",
                image: "simcard", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Carrier", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "Phone #", kind: .text),
                    FieldDef.make(name: "Data plan", kind: .text),
                    FieldDef.make(name: "Activated on", kind: .date),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                ],
                primary: "carrier", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.esim_plan",
            category: .travel,
            blurb: "eSIM purchases — provider, plan, dates.",
            keywords: ["esim", "airalo", "travel data"],
            template: makeType(
                id: "eSIM", name: "eSIM", plural: "eSIMs",
                image: "antenna.radiowaves.left.and.right", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Provider", kind: .text, required: true),
                    FieldDef.make(name: "Country / region", kind: .text),
                    FieldDef.make(name: "Data (GB)", kind: .number),
                    FieldDef.make(name: "Days valid", kind: .number),
                    FieldDef.make(name: "Activated on", kind: .date),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                ],
                primary: "provider", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.travel_insurance_claim",
            category: .travel,
            blurb: "Travel insurance claims — trip, claim, payout.",
            keywords: ["travel insurance", "claim", "payout"],
            template: makeType(
                id: "TravelInsuranceClaim", name: "Claim", plural: "Travel Insurance Claims",
                image: "shield.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Trip", kind: .link),
                    FieldDef.make(name: "Insurer", kind: .text),
                    FieldDef.make(name: "Claim date", kind: .date, required: true),
                    FieldDef.make(name: "Claim type", kind: .text),
                    FieldDef.make(name: "Amount claimed", kind: .number),
                    FieldDef.make(name: "Amount paid", kind: .number),
                    selectField("Status", [
                        ("Submitted", "#3FA9F5"), ("Reviewing", "#E8A93B"),
                        ("Approved", "#3FB950"), ("Denied", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Documents", kind: .attachment),
                ],
                primary: "claim_type", kanban: "status", calendar: "claim_date"
            )
        ),

        Entry(
            id: "lib.trip_vaccination",
            category: .travel,
            blurb: "Vaccinations required for a trip — country, vaccine, date.",
            keywords: ["travel vaccine", "yellow fever", "required"],
            template: makeType(
                id: "TripVaccination", name: "Vaccine", plural: "Trip Vaccinations",
                image: "syringe.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Vaccine", kind: .text, required: true),
                    FieldDef.make(name: "For country", kind: .text),
                    FieldDef.make(name: "Date received", kind: .date),
                    FieldDef.make(name: "Valid until", kind: .date),
                    FieldDef.make(name: "Issuing clinic", kind: .text),
                    FieldDef.make(name: "Yellow card photo", kind: .attachment),
                ],
                primary: "vaccine", calendar: "valid_until", gallery: "yellow_card_photo"
            )
        ),

        Entry(
            id: "lib.travel_pharmacy",
            category: .travel,
            blurb: "Travel pharmacy — med, indication, brought home?",
            keywords: ["travel pharmacy", "medication abroad"],
            template: makeType(
                id: "TravelPharmacy", name: "Item", plural: "Travel Pharmacy",
                image: "cross.case", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Medication", kind: .text, required: true),
                    FieldDef.make(name: "Indication", kind: .text),
                    FieldDef.make(name: "Bought in", kind: .text, description: "Country / pharmacy"),
                    FieldDef.make(name: "Date acquired", kind: .date),
                    FieldDef.make(name: "Expires", kind: .date),
                    FieldDef.make(name: "Stored in travel kit?", kind: .boolean),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "medication", calendar: "expires"
            )
        ),

        Entry(
            id: "lib.souvenir",
            category: .travel,
            blurb: "Souvenirs purchased — item, country, recipient.",
            keywords: ["souvenir", "gift", "memento"],
            template: makeType(
                id: "Souvenir", name: "Souvenir", plural: "Souvenirs",
                image: "gift", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "City", kind: .text),
                    FieldDef.make(name: "Bought on", kind: .date),
                    FieldDef.make(name: "Recipient", kind: .link),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "item", calendar: "bought_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.postcard_sent",
            category: .travel,
            blurb: "Postcards sent — from where, recipient, message gist.",
            keywords: ["postcard", "snail mail", "travel"],
            template: makeType(
                id: "PostcardSent", name: "Postcard", plural: "Postcards Sent",
                image: "envelope", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "From", kind: .text, required: true),
                    FieldDef.make(name: "Date sent", kind: .date, required: true),
                    FieldDef.make(name: "Recipient", kind: .link),
                    FieldDef.make(name: "Message", kind: .richText),
                    FieldDef.make(name: "Postcard photo", kind: .attachment),
                    FieldDef.make(name: "Stamp featured", kind: .text),
                    FieldDef.make(name: "Arrived?", kind: .boolean),
                ],
                primary: "from", calendar: "date_sent", gallery: "postcard_photo"
            )
        ),

        Entry(
            id: "lib.border_crossing",
            category: .travel,
            blurb: "Border crossings — country in/out, mode, time.",
            keywords: ["border", "crossing", "immigration"],
            template: makeType(
                id: "BorderCrossing", name: "Crossing", plural: "Border Crossings",
                image: "arrow.triangle.2.circlepath", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "From country", kind: .text, required: true),
                    FieldDef.make(name: "To country", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Mode", [
                        ("Air", "#3FA9F5"), ("Land", "#7B4F2F"),
                        ("Sea", "#9D4DCC"), ("Rail", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Crossing point", kind: .text),
                    FieldDef.make(name: "Time at border (min)", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "crossing_point", kanban: "mode", calendar: "date"
            )
        ),

        Entry(
            id: "lib.time_zone_crossing",
            category: .travel,
            blurb: "Time zones crossed and jet lag severity.",
            keywords: ["timezone", "jet lag", "tz"],
            template: makeType(
                id: "TimeZoneCrossing", name: "Crossing", plural: "Time-Zone Crossings",
                image: "globe.americas", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Trip", kind: .link),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "From TZ", kind: .text),
                    FieldDef.make(name: "To TZ", kind: .text),
                    FieldDef.make(name: "Hours shifted", kind: .number),
                    selectField("Jet lag severity", [
                        ("None", "#3FB950"), ("Mild", "#3FA9F5"),
                        ("Moderate", "#E8A93B"), ("Brutal", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Recovery days", kind: .number),
                ],
                primary: "date", kanban: "jet_lag_severity", calendar: "date"
            )
        ),

        // MARK: - Creative Work

        Entry(
            id: "lib.voice_memo",
            category: .creative,
            blurb: "Audio idea dumps — transcribed gist, status.",
            keywords: ["voice memo", "audio note", "idea capture"],
            template: makeType(
                id: "VoiceMemo", name: "Memo", plural: "Voice Memos",
                image: "waveform", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Recorded on", kind: .dateTime, required: true),
                    FieldDef.make(name: "Audio file", kind: .attachment),
                    FieldDef.make(name: "Transcribed gist", kind: .richText),
                    selectField("Status", [
                        ("Raw", "#888888"), ("Reviewed", "#3FA9F5"),
                        ("Acted on", "#3FB950"), ("Archived", "#666666"),
                    ]),
                ],
                primary: "title", kanban: "status", calendar: "recorded_on"
            )
        ),

        Entry(
            id: "lib.screenplay",
            category: .creative,
            blurb: "Screenplay drafts — title, page count, act structure.",
            keywords: ["screenplay", "script", "film", "draft"],
            template: makeType(
                id: "Screenplay", name: "Screenplay", plural: "Screenplays",
                image: "doc.richtext", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Logline", kind: .text),
                    FieldDef.make(name: "Genre", kind: .text),
                    FieldDef.make(name: "Page count", kind: .number),
                    FieldDef.make(name: "Act structure", kind: .text),
                    selectField("Stage", [
                        ("Outline", "#888888"), ("First draft", "#3FA9F5"),
                        ("Revising", "#E8A93B"), ("Polished", "#9D4DCC"),
                        ("Sold / produced", "#3FB950"), ("Shelved", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "title", kanban: "stage"
            )
        ),

        Entry(
            id: "lib.storyboard",
            category: .creative,
            blurb: "Storyboards — sequence, panel count, shot list link.",
            keywords: ["storyboard", "shot list", "previs"],
            template: makeType(
                id: "Storyboard", name: "Sequence", plural: "Storyboards",
                image: "rectangle.split.3x3", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Project", kind: .text, required: true),
                    FieldDef.make(name: "Sequence", kind: .text),
                    FieldDef.make(name: "Panel count", kind: .number),
                    FieldDef.make(name: "Date drafted", kind: .date),
                    FieldDef.make(name: "Shot list URL", kind: .url),
                    FieldDef.make(name: "Storyboard image", kind: .attachment),
                ],
                primary: "sequence", calendar: "date_drafted", gallery: "storyboard_image"
            )
        ),

        Entry(
            id: "lib.vfx_shot",
            category: .creative,
            blurb: "VFX shots — project, shot id, software, render time.",
            keywords: ["vfx", "render", "composite", "houdini"],
            template: makeType(
                id: "VFXShot", name: "Shot", plural: "VFX Shots",
                image: "wand.and.rays", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Shot ID", kind: .text, required: true),
                    FieldDef.make(name: "Project", kind: .text),
                    FieldDef.make(name: "Software", kind: .text),
                    FieldDef.make(name: "Render time (min)", kind: .number),
                    FieldDef.make(name: "Frame count", kind: .number),
                    selectField("Status", [
                        ("Comp WIP", "#3FA9F5"), ("Review", "#E8A93B"),
                        ("Approved", "#3FB950"), ("Final", "#9D4DCC"),
                        ("Re-do", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Preview frame", kind: .attachment),
                ],
                primary: "shot_id", kanban: "status", gallery: "preview_frame"
            )
        ),

        Entry(
            id: "lib.color_grade",
            category: .creative,
            blurb: "Color grade preset / LUT — project applied, looks-like.",
            keywords: ["color grade", "lut", "davinci", "look"],
            template: makeType(
                id: "ColorGrade", name: "Grade", plural: "Color Grades",
                image: "paintpalette.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "LUT / preset name", kind: .text, required: true),
                    FieldDef.make(name: "Project", kind: .text),
                    FieldDef.make(name: "Software", kind: .text),
                    FieldDef.make(name: "Look description", kind: .longText),
                    FieldDef.make(name: "Reference frame", kind: .attachment),
                ],
                primary: "lut_preset_name", gallery: "reference_frame"
            )
        ),

        Entry(
            id: "lib.audio_mix",
            category: .creative,
            blurb: "Audio mixes — project, channels, peak / loudness target.",
            keywords: ["mix", "audio", "mastering", "lufs"],
            template: makeType(
                id: "AudioMix", name: "Mix", plural: "Audio Mixes",
                image: "speaker.wave.3", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Project / song", kind: .text, required: true),
                    FieldDef.make(name: "Mix date", kind: .date),
                    FieldDef.make(name: "Channels", kind: .number),
                    FieldDef.make(name: "Target loudness (LUFS)", kind: .number),
                    FieldDef.make(name: "Peak (dBFS)", kind: .number),
                    selectField("Format", [
                        ("Stereo", "#3FA9F5"), ("5.1 surround", "#9D4DCC"),
                        ("7.1 / Atmos", "#E8A93B"), ("Mono", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "project_song", kanban: "format", calendar: "mix_date"
            )
        ),

        Entry(
            id: "lib.mastering_session",
            category: .creative,
            blurb: "Mastering sessions — track, target loudness, format.",
            keywords: ["mastering", "loudness", "ozone", "ozone"],
            template: makeType(
                id: "MasteringSession", name: "Session", plural: "Mastering Sessions",
                image: "music.note.tv", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Track / album", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Target LUFS", kind: .number),
                    selectField("Format", [
                        ("Streaming", "#3FA9F5"), ("CD", "#9D4DCC"),
                        ("Vinyl", "#E8A93B"), ("Cassette", "#7B4F2F"),
                    ]),
                    FieldDef.make(name: "Engineer", kind: .text),
                    FieldDef.make(name: "Reference tracks", kind: .longText),
                ],
                primary: "track_album", kanban: "format", calendar: "date"
            )
        ),

        Entry(
            id: "lib.sound_design",
            category: .creative,
            blurb: "Sound design clips — source, layers, what it represents.",
            keywords: ["sound design", "fx", "asset"],
            template: makeType(
                id: "SoundDesign", name: "Clip", plural: "Sound Design Clips",
                image: "speaker.badge.exclamationmark", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Clip name", kind: .text, required: true),
                    FieldDef.make(name: "Represents", kind: .text),
                    FieldDef.make(name: "Source recordings", kind: .longText),
                    FieldDef.make(name: "Layers", kind: .number),
                    FieldDef.make(name: "Length (sec)", kind: .number),
                    FieldDef.make(name: "Audio file", kind: .attachment),
                ],
                primary: "clip_name"
            )
        ),

        Entry(
            id: "lib.foley_session",
            category: .creative,
            blurb: "Foley sessions — scene, props, recordings made.",
            keywords: ["foley", "footsteps", "props", "field recording"],
            template: makeType(
                id: "FoleySession", name: "Session", plural: "Foley Sessions",
                image: "shoeprints.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Scene / cue", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Props used", kind: .longText),
                    FieldDef.make(name: "Mic / setup", kind: .text),
                    FieldDef.make(name: "Takes recorded", kind: .number),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "scene_cue", calendar: "date"
            )
        ),

        Entry(
            id: "lib.daw_project",
            category: .creative,
            blurb: "DAW projects — name, tempo, key, status.",
            keywords: ["daw", "logic", "ableton", "pro tools"],
            template: makeType(
                id: "DAWProject", name: "Project", plural: "DAW Projects",
                image: "waveform.path.ecg.rectangle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "DAW", kind: .text),
                    FieldDef.make(name: "Tempo", kind: .number),
                    FieldDef.make(name: "Key", kind: .text),
                    FieldDef.make(name: "Track count", kind: .number),
                    selectField("Status", [
                        ("Sketch", "#888888"), ("Tracking", "#3FA9F5"),
                        ("Mixing", "#E8A93B"), ("Mastering", "#9D4DCC"),
                        ("Released", "#3FB950"),
                    ]),
                    FieldDef.make(name: "File path", kind: .text),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "title", kanban: "status"
            )
        ),

        Entry(
            id: "lib.synth_patch",
            category: .creative,
            blurb: "Synth patches — synth, sound description, file path.",
            keywords: ["synth", "patch", "preset", "moog"],
            template: makeType(
                id: "SynthPatch", name: "Patch", plural: "Synth Patches",
                image: "pianokeys", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Patch name", kind: .text, required: true),
                    FieldDef.make(name: "Synth", kind: .text),
                    selectField("Type", [
                        ("Lead", "#D14B5C"), ("Pad", "#9D4DCC"),
                        ("Bass", "#3FB950"), ("Pluck", "#E8A93B"),
                        ("Texture", "#F08C2E"), ("Drum / perc", "#666666"),
                    ]),
                    FieldDef.make(name: "Sound description", kind: .longText),
                    FieldDef.make(name: "File path / location", kind: .text),
                    FieldDef.make(name: "Created", kind: .date),
                ],
                primary: "patch_name", kanban: "type", calendar: "created"
            )
        ),

        Entry(
            id: "lib.sample_pack",
            category: .creative,
            blurb: "Sample packs made — theme, sample count, license.",
            keywords: ["sample pack", "loops", "samples"],
            template: makeType(
                id: "SamplePack", name: "Pack", plural: "Sample Packs",
                image: "rectangle.stack.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Pack name", kind: .text, required: true),
                    FieldDef.make(name: "Theme / genre", kind: .text),
                    FieldDef.make(name: "Sample count", kind: .number),
                    FieldDef.make(name: "BPM range", kind: .text),
                    FieldDef.make(name: "Key signature", kind: .text),
                    selectField("License", [
                        ("Royalty-free", "#3FB950"), ("Personal", "#3FA9F5"),
                        ("Commercial", "#9D4DCC"), ("CC", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Release date", kind: .date),
                    FieldDef.make(name: "Cover art", kind: .attachment),
                ],
                primary: "pack_name", kanban: "license", calendar: "release_date", gallery: "cover_art"
            )
        ),

        Entry(
            id: "lib.beat_made",
            category: .creative,
            blurb: "Loops / beats made — genre, BPM, where used.",
            keywords: ["beat", "loop", "instrumental", "type beat"],
            template: makeType(
                id: "BeatMade", name: "Beat", plural: "Beats Made",
                image: "music.note.list", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "BPM", kind: .number),
                    FieldDef.make(name: "Key", kind: .text),
                    selectField("Genre", [
                        ("Hip-hop", "#9D4DCC"), ("Trap", "#E8A93B"),
                        ("R&B", "#D14B5C"), ("Lofi", "#3FA9F5"),
                        ("House", "#3FB950"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Used in / placed?", kind: .text),
                    FieldDef.make(name: "Audio preview", kind: .attachment),
                ],
                primary: "title", kanban: "genre", calendar: "date"
            )
        ),

        Entry(
            id: "lib.logo_concept",
            category: .creative,
            blurb: "Iteration log for a single brand's logo concepts.",
            keywords: ["logo", "concept", "iteration", "branding"],
            template: makeType(
                id: "LogoConcept", name: "Concept", plural: "Logo Concepts",
                image: "scribble", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Concept name / iteration", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Concept image", kind: .attachment),
                    FieldDef.make(name: "Rationale", kind: .longText),
                    selectField("Status", [
                        ("Sketch", "#888888"), ("Refined", "#3FA9F5"),
                        ("Presented", "#9D4DCC"), ("Selected", "#3FB950"),
                        ("Killed", "#D14B5C"),
                    ]),
                ],
                primary: "concept_name_iteration", kanban: "status", calendar: "date", gallery: "concept_image"
            )
        ),

        Entry(
            id: "lib.mascot_design",
            category: .creative,
            blurb: "Mascot designs — concept, character bible, file.",
            keywords: ["mascot", "character", "brand", "design"],
            template: makeType(
                id: "MascotDesign", name: "Mascot", plural: "Mascots",
                image: "person.crop.circle.badge.checkmark", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    FieldDef.make(name: "Personality", kind: .text),
                    FieldDef.make(name: "Character bible", kind: .richText),
                    FieldDef.make(name: "Reference image", kind: .attachment),
                ],
                primary: "name", gallery: "reference_image"
            )
        ),

        Entry(
            id: "lib.brand_palette",
            category: .creative,
            blurb: "Brand color palettes — brand, hex codes, usage rules.",
            keywords: ["color palette", "brand", "hex", "swatches"],
            template: makeType(
                id: "BrandPalette", name: "Palette", plural: "Brand Palettes",
                image: "paintpalette", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Brand", kind: .text, required: true),
                    FieldDef.make(name: "Primary hex", kind: .text),
                    FieldDef.make(name: "Secondary hex", kind: .text),
                    FieldDef.make(name: "Accent hex", kind: .text),
                    FieldDef.make(name: "Neutral hex", kind: .text),
                    FieldDef.make(name: "Usage rules", kind: .richText),
                    FieldDef.make(name: "Swatch image", kind: .attachment),
                ],
                primary: "brand", gallery: "swatch_image"
            )
        ),

        Entry(
            id: "lib.icon_set",
            category: .creative,
            blurb: "Icon sets — style, count, exported formats.",
            keywords: ["icon set", "ui icons", "glyphs"],
            template: makeType(
                id: "IconSet", name: "Set", plural: "Icon Sets",
                image: "square.grid.3x3.square", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Set name", kind: .text, required: true),
                    FieldDef.make(name: "Style", kind: .text),
                    FieldDef.make(name: "Icon count", kind: .number),
                    FieldDef.make(name: "Stroke width (px)", kind: .number),
                    FieldDef.make(name: "Formats exported", kind: .text),
                    FieldDef.make(name: "Date released", kind: .date),
                    FieldDef.make(name: "Cover image", kind: .attachment),
                ],
                primary: "set_name", calendar: "date_released", gallery: "cover_image"
            )
        ),

        Entry(
            id: "lib.app_icon_design",
            category: .creative,
            blurb: "App icon designs — app, drafts, final.",
            keywords: ["app icon", "ios", "macos", "design"],
            template: makeType(
                id: "AppIconDesign", name: "Icon", plural: "App Icons",
                image: "app.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "App name", kind: .text, required: true),
                    FieldDef.make(name: "Platform", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Status", [
                        ("Sketching", "#888888"), ("Refining", "#3FA9F5"),
                        ("Approved", "#3FB950"), ("Shipped", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Icon image", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "app_name", kanban: "status", calendar: "date", gallery: "icon_image"
            )
        ),

        Entry(
            id: "lib.website_mockup",
            category: .creative,
            blurb: "Website mockups — page, breakpoints, status.",
            keywords: ["mockup", "website", "design", "figma"],
            template: makeType(
                id: "WebsiteMockup", name: "Mockup", plural: "Website Mockups",
                image: "macwindow", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Page", kind: .text, required: true),
                    FieldDef.make(name: "Site / project", kind: .text),
                    FieldDef.make(name: "Breakpoints", kind: .text),
                    selectField("Fidelity", [
                        ("Wireframe", "#888888"), ("Lo-fi", "#3FA9F5"),
                        ("Hi-fi", "#9D4DCC"), ("Production-ready", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Mockup image", kind: .attachment),
                ],
                primary: "page", kanban: "fidelity", calendar: "date", gallery: "mockup_image"
            )
        ),

        Entry(
            id: "lib.ui_screen",
            category: .creative,
            blurb: "UI screens designed — product, screen, last revision.",
            keywords: ["ui screen", "design", "product", "figma"],
            template: makeType(
                id: "UIScreen", name: "Screen", plural: "UI Screens",
                image: "rectangle.on.rectangle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Screen name", kind: .text, required: true),
                    FieldDef.make(name: "Product", kind: .text),
                    FieldDef.make(name: "Last revised", kind: .date),
                    FieldDef.make(name: "Revision count", kind: .number),
                    selectField("Status", [
                        ("Wireframe", "#888888"), ("Visual draft", "#3FA9F5"),
                        ("Reviewed", "#9D4DCC"), ("Shipped", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Screen image", kind: .attachment),
                ],
                primary: "screen_name", kanban: "status", calendar: "last_revised", gallery: "screen_image"
            )
        ),

        Entry(
            id: "lib.design_token",
            category: .creative,
            blurb: "Design system tokens — token name, value, where used.",
            keywords: ["design token", "design system", "style token"],
            template: makeType(
                id: "DesignToken", name: "Token", plural: "Design Tokens",
                image: "circle.dotted", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Token name", kind: .text, required: true),
                    FieldDef.make(name: "Value", kind: .text),
                    selectField("Type", [
                        ("Color", "#9D4DCC"), ("Spacing", "#3FA9F5"),
                        ("Typography", "#E8A93B"), ("Radius", "#3FB950"),
                        ("Elevation", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Used by", kind: .text),
                    FieldDef.make(name: "Deprecated?", kind: .boolean),
                ],
                primary: "token_name", kanban: "type"
            )
        ),

        Entry(
            id: "lib.component_lib",
            category: .creative,
            blurb: "Design system components — variants, API.",
            keywords: ["component", "library", "design system"],
            template: makeType(
                id: "ComponentLibrary", name: "Component", plural: "Component Library",
                image: "square.stack.3d.up.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Component name", kind: .text, required: true),
                    FieldDef.make(name: "Variants count", kind: .number),
                    FieldDef.make(name: "Props / API", kind: .longText),
                    FieldDef.make(name: "Used in pages", kind: .number),
                    selectField("Status", [
                        ("Draft", "#888888"), ("In review", "#3FA9F5"),
                        ("Stable", "#3FB950"), ("Deprecated", "#666666"),
                    ]),
                    FieldDef.make(name: "Last updated", kind: .date),
                ],
                primary: "component_name", kanban: "status", calendar: "last_updated"
            )
        ),

        Entry(
            id: "lib.wireframe",
            category: .creative,
            blurb: "Wireframes — project, flow stage, fidelity.",
            keywords: ["wireframe", "flow", "low fidelity"],
            template: makeType(
                id: "Wireframe", name: "Wireframe", plural: "Wireframes",
                image: "rectangle.dashed", color: "#888888",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Project", kind: .text),
                    FieldDef.make(name: "Flow stage", kind: .text),
                    selectField("Fidelity", [
                        ("Paper", "#888888"), ("Low-fi", "#3FA9F5"),
                        ("Mid-fi", "#9D4DCC"), ("Hi-fi", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Date drafted", kind: .date),
                    FieldDef.make(name: "Wireframe image", kind: .attachment),
                ],
                primary: "title", kanban: "fidelity", calendar: "date_drafted", gallery: "wireframe_image"
            )
        ),

        Entry(
            id: "lib.user_persona",
            category: .creative,
            blurb: "User personas — demographics, jobs-to-be-done.",
            keywords: ["persona", "ux", "user research", "jtbd"],
            template: makeType(
                id: "UserPersona", name: "Persona", plural: "User Personas",
                image: "person.crop.rectangle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Persona name", kind: .text, required: true),
                    FieldDef.make(name: "Age range", kind: .text),
                    FieldDef.make(name: "Role / occupation", kind: .text),
                    FieldDef.make(name: "Goals", kind: .richText),
                    FieldDef.make(name: "Pains", kind: .richText),
                    FieldDef.make(name: "Jobs to be done", kind: .longText),
                    FieldDef.make(name: "Avatar", kind: .attachment),
                ],
                primary: "persona_name", gallery: "avatar"
            )
        ),

        Entry(
            id: "lib.ux_research",
            category: .creative,
            blurb: "UX research sessions — participant, method, key finding.",
            keywords: ["ux research", "interview", "discovery"],
            template: makeType(
                id: "UXResearch", name: "Session", plural: "UX Research Sessions",
                image: "magnifyingglass.circle.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Participant ID", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Method", [
                        ("Interview", "#9D4DCC"), ("Diary study", "#3FA9F5"),
                        ("Shadowing", "#3FB950"), ("Survey", "#E8A93B"),
                        ("Card sort", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Key finding", kind: .richText),
                    FieldDef.make(name: "Transcript", kind: .attachment),
                ],
                primary: "participant_id", kanban: "method", calendar: "date"
            )
        ),

        Entry(
            id: "lib.usability_test",
            category: .creative,
            blurb: "Usability tests — task, success rate, friction points.",
            keywords: ["usability", "test", "task", "friction"],
            template: makeType(
                id: "UsabilityTest", name: "Test", plural: "Usability Tests",
                image: "checkmark.circle.trianglebadge.exclamationmark", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Task", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Participants", kind: .number),
                    FieldDef.make(name: "Success rate %", kind: .number),
                    FieldDef.make(name: "Time on task (sec)", kind: .number),
                    FieldDef.make(name: "Friction observations", kind: .richText),
                    FieldDef.make(name: "Recommendations", kind: .longText),
                ],
                primary: "task", calendar: "date"
            )
        ),

        Entry(
            id: "lib.ab_test",
            category: .creative,
            blurb: "A/B tests — variant, lift, significance.",
            keywords: ["ab test", "experiment", "lift", "p-value"],
            template: makeType(
                id: "ABTest", name: "Test", plural: "A/B Tests",
                image: "chart.bar.xaxis", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Test name", kind: .text, required: true),
                    FieldDef.make(name: "Hypothesis", kind: .text),
                    FieldDef.make(name: "Start", kind: .date),
                    FieldDef.make(name: "End", kind: .date),
                    FieldDef.make(name: "Sample size", kind: .number),
                    FieldDef.make(name: "Lift %", kind: .number),
                    FieldDef.make(name: "P-value", kind: .number),
                    selectField("Outcome", [
                        ("Win", "#3FB950"), ("Loss", "#D14B5C"),
                        ("Inconclusive", "#E8A93B"), ("Shipped both", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "test_name", kanban: "outcome", calendar: "end"
            )
        ),

        Entry(
            id: "lib.survey",
            category: .creative,
            blurb: "Surveys written — title, audience, response count.",
            keywords: ["survey", "questionnaire", "nps"],
            template: makeType(
                id: "Survey", name: "Survey", plural: "Surveys",
                image: "list.bullet.clipboard.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Audience", kind: .text),
                    FieldDef.make(name: "Launched", kind: .date),
                    FieldDef.make(name: "Closed", kind: .date),
                    FieldDef.make(name: "Responses", kind: .number),
                    FieldDef.make(name: "Response rate %", kind: .number),
                    FieldDef.make(name: "Key insight", kind: .richText),
                ],
                primary: "title", calendar: "launched"
            )
        ),

        Entry(
            id: "lib.interview_transcript",
            category: .creative,
            blurb: "Interview transcripts — subject, length, themes.",
            keywords: ["transcript", "interview", "qualitative"],
            template: makeType(
                id: "InterviewTranscript", name: "Transcript", plural: "Interview Transcripts",
                image: "doc.text.below.ecg", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Length (min)", kind: .number),
                    FieldDef.make(name: "Themes", kind: .longText),
                    FieldDef.make(name: "Transcript file", kind: .attachment),
                    FieldDef.make(name: "Audio file", kind: .attachment),
                ],
                primary: "subject", calendar: "date"
            )
        ),

        Entry(
            id: "lib.customer_interview",
            category: .creative,
            blurb: "Customer interviews — person, recurring pain, quote.",
            keywords: ["customer interview", "discovery", "pain"],
            template: makeType(
                id: "CustomerInterview", name: "Interview", plural: "Customer Interviews",
                image: "person.crop.circle.fill.badge.exclamationmark", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Customer", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Stage in journey", kind: .text),
                    FieldDef.make(name: "Recurring pain", kind: .richText),
                    FieldDef.make(name: "Memorable quote", kind: .longText),
                    FieldDef.make(name: "Action items", kind: .longText),
                ],
                primary: "customer", calendar: "date"
            )
        ),

        Entry(
            id: "lib.job_description",
            category: .creative,
            blurb: "Job descriptions written — role, level, status.",
            keywords: ["job description", "jd", "hiring", "spec"],
            template: makeType(
                id: "JobDescription", name: "JD", plural: "Job Descriptions",
                image: "doc.text", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Role title", kind: .text, required: true),
                    FieldDef.make(name: "Level", kind: .text),
                    FieldDef.make(name: "Team", kind: .text),
                    FieldDef.make(name: "Drafted on", kind: .date),
                    selectField("Status", [
                        ("Draft", "#888888"), ("In review", "#3FA9F5"),
                        ("Posted", "#3FB950"), ("Closed", "#666666"),
                    ]),
                    FieldDef.make(name: "JD content", kind: .richText),
                ],
                primary: "role_title", kanban: "status", calendar: "drafted_on"
            )
        ),

        Entry(
            id: "lib.onboarding_doc",
            category: .creative,
            blurb: "Onboarding docs — topic, owner, last updated.",
            keywords: ["onboarding", "new hire", "doc"],
            template: makeType(
                id: "OnboardingDoc", name: "Doc", plural: "Onboarding Docs",
                image: "person.fill.questionmark", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Topic", kind: .text, required: true),
                    FieldDef.make(name: "Owner", kind: .link),
                    FieldDef.make(name: "Last updated", kind: .date),
                    FieldDef.make(name: "Estimated read time (min)", kind: .number),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Outline", kind: .richText),
                ],
                primary: "topic", calendar: "last_updated"
            )
        ),

        Entry(
            id: "lib.wiki_page",
            category: .creative,
            blurb: "Wiki pages — page, hub, last edited.",
            keywords: ["wiki", "page", "internal doc"],
            template: makeType(
                id: "WikiPage", name: "Page", plural: "Wiki Pages",
                image: "doc.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Hub / space", kind: .text),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Last edited", kind: .date),
                    FieldDef.make(name: "Edited by", kind: .link),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Stale", "#E8A93B"),
                        ("Archived", "#666666"),
                    ]),
                ],
                primary: "title", kanban: "status", calendar: "last_edited"
            )
        ),

        Entry(
            id: "lib.documentation_page",
            category: .creative,
            blurb: "Documentation pages — section, audience, status.",
            keywords: ["documentation", "docs", "manual"],
            template: makeType(
                id: "DocumentationPage", name: "Page", plural: "Documentation Pages",
                image: "doc.append.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Section", kind: .text),
                    selectField("Audience", [
                        ("End user", "#3FA9F5"), ("Developer", "#9D4DCC"),
                        ("Internal", "#E8A93B"), ("Admin", "#F08C2E"),
                    ]),
                    selectField("Status", [
                        ("Outline", "#888888"), ("Drafting", "#3FA9F5"),
                        ("Review", "#E8A93B"), ("Published", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Last updated", kind: .date),
                    FieldDef.make(name: "URL", kind: .url),
                ],
                primary: "title", kanban: "status", calendar: "last_updated"
            )
        ),

        Entry(
            id: "lib.tutorial_video",
            category: .creative,
            blurb: "Tutorial videos produced — topic, runtime, audience.",
            keywords: ["tutorial", "video", "course", "screencast"],
            template: makeType(
                id: "TutorialVideo", name: "Video", plural: "Tutorial Videos",
                image: "rectangle.stack.badge.play", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Topic", kind: .text),
                    FieldDef.make(name: "Runtime (min)", kind: .number),
                    FieldDef.make(name: "Audience", kind: .text),
                    FieldDef.make(name: "Published on", kind: .date),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Views", kind: .number),
                    FieldDef.make(name: "Thumbnail", kind: .attachment),
                ],
                primary: "title", calendar: "published_on", gallery: "thumbnail"
            )
        ),

        Entry(
            id: "lib.lesson_plan",
            category: .creative,
            blurb: "Lesson plans — subject, age, materials, learning objective.",
            keywords: ["lesson plan", "teaching", "classroom"],
            template: makeType(
                id: "LessonPlan", name: "Lesson", plural: "Lesson Plans",
                image: "book.closed.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Subject", kind: .text),
                    FieldDef.make(name: "Age / grade", kind: .text),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "Learning objective", kind: .longText),
                    FieldDef.make(name: "Materials", kind: .longText),
                    FieldDef.make(name: "Date taught", kind: .date),
                    FieldDef.make(name: "Reflection", kind: .richText),
                ],
                primary: "title", calendar: "date_taught"
            )
        ),

        Entry(
            id: "lib.workshop_curriculum",
            category: .creative,
            blurb: "Workshop curriculum — hours, modules.",
            keywords: ["workshop", "curriculum", "modules"],
            template: makeType(
                id: "WorkshopCurriculum", name: "Workshop", plural: "Workshop Curricula",
                image: "books.vertical.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Workshop title", kind: .text, required: true),
                    FieldDef.make(name: "Total hours", kind: .number),
                    FieldDef.make(name: "Modules outline", kind: .richText),
                    FieldDef.make(name: "Target audience", kind: .text),
                    FieldDef.make(name: "Materials needed", kind: .longText),
                    FieldDef.make(name: "Last refreshed", kind: .date),
                ],
                primary: "workshop_title", calendar: "last_refreshed"
            )
        ),

        Entry(
            id: "lib.cfp",
            category: .creative,
            blurb: "Conference CFPs submitted — abstract, status, deadlines.",
            keywords: ["cfp", "conference", "talk", "abstract"],
            template: makeType(
                id: "CFPSubmission", name: "CFP", plural: "CFPs",
                image: "paperplane.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Conference", kind: .text, required: true),
                    FieldDef.make(name: "Talk title", kind: .text),
                    FieldDef.make(name: "Submission deadline", kind: .date),
                    FieldDef.make(name: "Submitted on", kind: .date),
                    FieldDef.make(name: "Abstract", kind: .richText),
                    selectField("Status", [
                        ("Drafting", "#888888"), ("Submitted", "#3FA9F5"),
                        ("Accepted", "#3FB950"), ("Rejected", "#D14B5C"),
                        ("Waitlist", "#E8A93B"),
                    ]),
                ],
                primary: "conference", kanban: "status", calendar: "submission_deadline"
            )
        ),

        Entry(
            id: "lib.paper_rejection",
            category: .creative,
            blurb: "Paper rejection — journal, reviewer comments, revise plan.",
            keywords: ["paper", "rejection", "peer review"],
            template: makeType(
                id: "PaperRejection", name: "Rejection", plural: "Paper Rejections",
                image: "doc.text.fill.viewfinder", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Paper", kind: .text, required: true),
                    FieldDef.make(name: "Journal / venue", kind: .text),
                    FieldDef.make(name: "Date received", kind: .date, required: true),
                    FieldDef.make(name: "Reviewer comments", kind: .richText),
                    FieldDef.make(name: "Revise plan", kind: .longText),
                    selectField("Next step", [
                        ("Revise & resubmit", "#3FA9F5"), ("Submit elsewhere", "#9D4DCC"),
                        ("Withdraw", "#666666"), ("Major rewrite", "#E8A93B"),
                    ]),
                ],
                primary: "paper", kanban: "next_step", calendar: "date_received"
            )
        ),

        Entry(
            id: "lib.paper_acceptance",
            category: .creative,
            blurb: "Paper acceptance — journal, date, citation forming.",
            keywords: ["paper", "acceptance", "publication"],
            template: makeType(
                id: "PaperAcceptance", name: "Acceptance", plural: "Paper Acceptances",
                image: "checkmark.diamond.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Paper", kind: .text, required: true),
                    FieldDef.make(name: "Journal / venue", kind: .text),
                    FieldDef.make(name: "Date accepted", kind: .date, required: true),
                    FieldDef.make(name: "Estimated publication date", kind: .date),
                    FieldDef.make(name: "DOI", kind: .text),
                    FieldDef.make(name: "Citation", kind: .longText),
                ],
                primary: "paper", calendar: "date_accepted"
            )
        ),

        Entry(
            id: "lib.grant_application",
            category: .creative,
            blurb: "Grant applications — funder, ask, deadline.",
            keywords: ["grant", "funding", "application", "rfp"],
            template: makeType(
                id: "GrantApplication", name: "Application", plural: "Grant Applications",
                image: "doc.badge.gearshape.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Funder", kind: .text, required: true),
                    FieldDef.make(name: "Program / RFP", kind: .text),
                    FieldDef.make(name: "Ask amount", kind: .number),
                    FieldDef.make(name: "Submission deadline", kind: .date),
                    FieldDef.make(name: "Submitted on", kind: .date),
                    selectField("Status", [
                        ("Drafting", "#888888"), ("Submitted", "#3FA9F5"),
                        ("Awarded", "#3FB950"), ("Declined", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "funder", kanban: "status", calendar: "submission_deadline"
            )
        ),

        Entry(
            id: "lib.grant_received",
            category: .creative,
            blurb: "Grants received — funder, amount, period.",
            keywords: ["grant", "received", "funding"],
            template: makeType(
                id: "GrantReceived", name: "Grant", plural: "Grants Received",
                image: "rosette", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Funder", kind: .text, required: true),
                    FieldDef.make(name: "Project", kind: .text),
                    FieldDef.make(name: "Amount", kind: .number),
                    FieldDef.make(name: "Period start", kind: .date),
                    FieldDef.make(name: "Period end", kind: .date),
                    FieldDef.make(name: "Reporting cadence", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "funder", calendar: "period_end"
            )
        ),

        Entry(
            id: "lib.patent_filed",
            category: .creative,
            blurb: "Patents filed — title, number, status.",
            keywords: ["patent", "ip", "uspto"],
            template: makeType(
                id: "PatentFiled", name: "Patent", plural: "Patents",
                image: "lock.shield", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Inventors", kind: .text),
                    FieldDef.make(name: "Application #", kind: .text),
                    FieldDef.make(name: "Filing date", kind: .date),
                    selectField("Status", [
                        ("Provisional", "#888888"), ("Non-provisional", "#3FA9F5"),
                        ("Office action", "#E8A93B"), ("Granted", "#3FB950"),
                        ("Abandoned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Granted date", kind: .date),
                    FieldDef.make(name: "Patent #", kind: .text),
                ],
                primary: "title", kanban: "status", calendar: "filing_date"
            )
        ),

        Entry(
            id: "lib.trademark_filed",
            category: .creative,
            blurb: "Trademarks filed — mark, class, examiner.",
            keywords: ["trademark", "tm", "uspto", "brand"],
            template: makeType(
                id: "TrademarkFiled", name: "Trademark", plural: "Trademarks",
                image: "tm.square", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Mark", kind: .text, required: true),
                    FieldDef.make(name: "Class", kind: .text),
                    FieldDef.make(name: "Filing date", kind: .date),
                    FieldDef.make(name: "Serial #", kind: .text),
                    FieldDef.make(name: "Examiner", kind: .text),
                    selectField("Status", [
                        ("Filed", "#3FA9F5"), ("Office action", "#E8A93B"),
                        ("Published", "#9D4DCC"), ("Registered", "#3FB950"),
                        ("Abandoned", "#D14B5C"),
                    ]),
                ],
                primary: "mark", kanban: "status", calendar: "filing_date"
            )
        ),

        Entry(
            id: "lib.copyright_registration",
            category: .creative,
            blurb: "Copyright registrations — work, date, certificate.",
            keywords: ["copyright", "registration", "ip"],
            template: makeType(
                id: "CopyrightRegistration", name: "Registration", plural: "Copyrights",
                image: "c.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Work title", kind: .text, required: true),
                    FieldDef.make(name: "Type", kind: .text, description: "literary, music, visual…"),
                    FieldDef.make(name: "Author(s)", kind: .text),
                    FieldDef.make(name: "Registration date", kind: .date),
                    FieldDef.make(name: "Registration #", kind: .text),
                    FieldDef.make(name: "Certificate", kind: .attachment),
                ],
                primary: "work_title", calendar: "registration_date"
            )
        ),

        Entry(
            id: "lib.open_source_repo",
            category: .creative,
            blurb: "Open source projects you maintain — stars, last release.",
            keywords: ["open source", "oss", "github", "maintain"],
            template: makeType(
                id: "OpenSourceRepo", name: "Repo", plural: "Open Source Repos",
                image: "chevron.left.forwardslash.chevron.right", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Repo name", kind: .text, required: true),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Primary language", kind: .text),
                    FieldDef.make(name: "Stars", kind: .number),
                    FieldDef.make(name: "Forks", kind: .number),
                    FieldDef.make(name: "Last release version", kind: .text),
                    FieldDef.make(name: "Last release date", kind: .date),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Maintenance", "#E8A93B"),
                        ("Frozen", "#666666"), ("Archived", "#888888"),
                    ]),
                ],
                primary: "repo_name", kanban: "status", calendar: "last_release_date"
            )
        ),

        Entry(
            id: "lib.github_repo",
            category: .creative,
            blurb: "GitHub repos (mine) — project, primary language, status.",
            keywords: ["github", "repo", "project", "my repos"],
            template: makeType(
                id: "GitHubRepo", name: "Repo", plural: "GitHub Repos",
                image: "folder.fill.badge.gearshape", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Repo name", kind: .text, required: true),
                    FieldDef.make(name: "Description", kind: .text),
                    FieldDef.make(name: "Primary language", kind: .text),
                    selectField("Visibility", [
                        ("Public", "#3FB950"), ("Private", "#9D4DCC"),
                        ("Internal", "#E8A93B"),
                    ]),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("WIP", "#3FA9F5"),
                        ("Stale", "#E8A93B"), ("Archived", "#666666"),
                    ]),
                    FieldDef.make(name: "Created on", kind: .date),
                    FieldDef.make(name: "URL", kind: .url),
                ],
                primary: "repo_name", kanban: "status", calendar: "created_on"
            )
        ),

        Entry(
            id: "lib.pr_submitted",
            category: .creative,
            blurb: "Open-source PRs submitted (outbound) — repo, PR #, status.",
            keywords: ["pull request", "pr", "open source contribution"],
            template: makeType(
                id: "OutboundPR", name: "PR", plural: "Open Source PRs",
                image: "arrow.triangle.merge", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Repo", kind: .text),
                    FieldDef.make(name: "PR URL", kind: .url),
                    FieldDef.make(name: "Submitted on", kind: .date),
                    selectField("Status", [
                        ("Open", "#3FA9F5"), ("Review requested", "#E8A93B"),
                        ("Merged", "#3FB950"), ("Closed", "#666666"),
                        ("Rejected", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Lines changed", kind: .number),
                    FieldDef.make(name: "Description", kind: .richText),
                ],
                primary: "title", kanban: "status", calendar: "submitted_on"
            )
        ),

        Entry(
            id: "lib.issue_opened",
            category: .creative,
            blurb: "Issues opened — project, issue, resolution.",
            keywords: ["issue", "github", "bug report"],
            template: makeType(
                id: "IssueOpened", name: "Issue", plural: "Issues Opened",
                image: "exclamationmark.bubble", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Project / repo", kind: .text),
                    FieldDef.make(name: "URL", kind: .url),
                    FieldDef.make(name: "Opened on", kind: .date),
                    selectField("Status", [
                        ("Open", "#3FA9F5"), ("In progress", "#9D4DCC"),
                        ("Closed", "#3FB950"), ("Won't fix", "#666666"),
                    ]),
                    FieldDef.make(name: "Resolution", kind: .longText),
                ],
                primary: "title", kanban: "status", calendar: "opened_on"
            )
        ),

        Entry(
            id: "lib.release_shipped",
            category: .creative,
            blurb: "Releases shipped — project, version, highlights.",
            keywords: ["release", "version", "ship"],
            template: makeType(
                id: "ReleaseShipped", name: "Release", plural: "Releases",
                image: "shippingbox.and.arrow.backward.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Project", kind: .text, required: true),
                    FieldDef.make(name: "Version", kind: .text, required: true),
                    FieldDef.make(name: "Released on", kind: .date, required: true),
                    selectField("Channel", [
                        ("Beta", "#E8A93B"), ("Stable", "#3FB950"),
                        ("Canary / nightly", "#9D4DCC"), ("Hotfix", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Highlights", kind: .richText),
                    FieldDef.make(name: "Changelog URL", kind: .url),
                ],
                primary: "version", kanban: "channel", calendar: "released_on"
            )
        ),

        Entry(
            id: "lib.roadmap_item",
            category: .creative,
            blurb: "Roadmap items — project, theme, target quarter.",
            keywords: ["roadmap", "theme", "quarterly"],
            template: makeType(
                id: "RoadmapItem", name: "Item", plural: "Roadmap",
                image: "map.circle.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Project", kind: .text),
                    FieldDef.make(name: "Theme", kind: .text),
                    FieldDef.make(name: "Target quarter", kind: .text),
                    selectField("Status", [
                        ("Backlog", "#888888"), ("Committed", "#3FA9F5"),
                        ("Building", "#9D4DCC"), ("Done", "#3FB950"),
                        ("Cut", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "item", kanban: "status"
            )
        ),

        // MARK: - Pets & Animals (subset of Home)

        Entry(
            id: "lib.pet_weight_log",
            category: .home,
            blurb: "Per-pet weight log — track over time for vet visits.",
            keywords: ["pet weight", "dog weight", "cat weight"],
            template: makeType(
                id: "PetWeightLog", name: "Reading", plural: "Pet Weight Log",
                image: "scalemass.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Weight (lb)", kind: .number),
                    FieldDef.make(name: "Body condition (1-9)", kind: .number),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.pet_medication",
            category: .home,
            blurb: "Pet medications — drug, dose, frequency, refill date.",
            keywords: ["pet medication", "flea", "heartworm"],
            template: makeType(
                id: "PetMedication", name: "Med", plural: "Pet Medications",
                image: "pills.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Medication", kind: .text, required: true),
                    FieldDef.make(name: "Dosage", kind: .text),
                    selectField("Frequency", [
                        ("Daily", "#3FA9F5"), ("Twice daily", "#9D4DCC"),
                        ("Weekly", "#E8A93B"), ("Monthly", "#3FB950"),
                        ("As needed", "#666666"),
                    ]),
                    FieldDef.make(name: "Started", kind: .date),
                    FieldDef.make(name: "Next refill", kind: .date),
                    FieldDef.make(name: "Prescribing vet", kind: .link),
                    FieldDef.make(name: "Side effects observed", kind: .longText),
                ],
                primary: "medication", kanban: "frequency", calendar: "next_refill"
            )
        ),

        Entry(
            id: "lib.pet_grooming",
            category: .home,
            blurb: "Pet grooming sessions — date, type, groomer.",
            keywords: ["grooming", "bath", "haircut", "pet"],
            template: makeType(
                id: "PetGrooming", name: "Session", plural: "Pet Grooming",
                image: "scissors.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Service", [
                        ("Bath", "#3FA9F5"), ("Full groom", "#9D4DCC"),
                        ("Nail trim", "#E8A93B"), ("Teeth cleaning", "#3FB950"),
                        ("De-shedding", "#F08C2E"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Groomer", kind: .text),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Next visit", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "service", kanban: "service", calendar: "next_visit", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.pet_training",
            category: .home,
            blurb: "Pet training sessions — cue, success rate, treats.",
            keywords: ["pet training", "obedience", "trick", "clicker"],
            template: makeType(
                id: "PetTraining", name: "Session", plural: "Pet Training",
                image: "graduationcap.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Cue / trick", kind: .text),
                    FieldDef.make(name: "Reps", kind: .number),
                    FieldDef.make(name: "Success rate %", kind: .number),
                    selectField("Mastery", [
                        ("New", "#888888"), ("Learning", "#3FA9F5"),
                        ("Reliable", "#3FB950"), ("Mastered", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Treats used", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "cue_trick", kanban: "mastery", calendar: "date"
            )
        ),

        Entry(
            id: "lib.pet_behavior",
            category: .home,
            blurb: "Pet behavior issues — trigger, severity, intervention.",
            keywords: ["pet behavior", "issue", "anxiety", "aggression"],
            template: makeType(
                id: "PetBehavior", name: "Issue", plural: "Pet Behavior Issues",
                image: "exclamationmark.bubble.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Behavior", kind: .text, required: true),
                    FieldDef.make(name: "Trigger", kind: .text),
                    selectField("Severity", [
                        ("Mild", "#3FA9F5"), ("Moderate", "#E8A93B"),
                        ("Severe", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "First observed", kind: .date),
                    FieldDef.make(name: "Intervention", kind: .richText),
                    FieldDef.make(name: "Progress notes", kind: .noteLog),
                ],
                primary: "behavior", kanban: "severity", calendar: "first_observed"
            )
        ),

        Entry(
            id: "lib.pet_food",
            category: .home,
            blurb: "Pet food — brand, formula, allergies, bag bought.",
            keywords: ["pet food", "kibble", "raw", "brand"],
            template: makeType(
                id: "PetFood", name: "Food", plural: "Pet Food",
                image: "bag.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Brand", kind: .text, required: true),
                    FieldDef.make(name: "Formula", kind: .text),
                    selectField("Type", [
                        ("Dry kibble", "#E8A93B"), ("Wet / canned", "#3FA9F5"),
                        ("Raw", "#D14B5C"), ("Freeze-dried", "#9D4DCC"),
                        ("Prescription", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Bag size (lb)", kind: .number),
                    FieldDef.make(name: "Last bought", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Pet reaction (love / fine / refuses)", kind: .text),
                ],
                primary: "brand", kanban: "type", calendar: "last_bought"
            )
        ),

        Entry(
            id: "lib.pet_toy",
            category: .home,
            blurb: "Pet toys — durability, replaced?",
            keywords: ["pet toy", "chew", "rope"],
            template: makeType(
                id: "PetToy", name: "Toy", plural: "Pet Toys",
                image: "circle.hexagongrid", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link),
                    FieldDef.make(name: "Toy", kind: .text, required: true),
                    FieldDef.make(name: "Brand", kind: .text),
                    selectField("Type", [
                        ("Chew", "#7B4F2F"), ("Rope / tug", "#9D4DCC"),
                        ("Ball", "#E8A93B"), ("Puzzle", "#3FA9F5"),
                        ("Plush", "#F08C2E"), ("Catnip", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Cost", kind: .number),
                    selectField("Durability", [
                        ("Destroyed in 1 day", "#D14B5C"), ("Days", "#E8A93B"),
                        ("Weeks", "#3FA9F5"), ("Months", "#3FB950"),
                        ("Indestructible", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Replaced?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "toy", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.dog_walk",
            category: .home,
            blurb: "Dog walks — date, route, distance, time, poop count.",
            keywords: ["dog walk", "walk", "leash"],
            template: makeType(
                id: "DogWalk", name: "Walk", plural: "Dog Walks",
                image: "figure.walk.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Route", kind: .text),
                    FieldDef.make(name: "Distance (mi)", kind: .number),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "Poop count", kind: .number),
                    selectField("Pace", [
                        ("Sniff walk", "#E8A93B"), ("Strolling", "#3FA9F5"),
                        ("Brisk", "#9D4DCC"), ("Run", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .text),
                ],
                primary: "route", kanban: "pace", calendar: "date"
            )
        ),

        Entry(
            id: "lib.pet_boarding",
            category: .home,
            blurb: "Pet boarding — facility, dates, cost.",
            keywords: ["boarding", "kennel", "pet hotel"],
            template: makeType(
                id: "PetBoarding", name: "Stay", plural: "Pet Boarding",
                image: "house.lodge.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Facility", kind: .text),
                    FieldDef.make(name: "Drop off", kind: .date, required: true),
                    FieldDef.make(name: "Pick up", kind: .date),
                    FieldDef.make(name: "Nights", kind: .number),
                    FieldDef.make(name: "Cost", kind: .number),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "facility", calendar: "drop_off"
            )
        ),

        Entry(
            id: "lib.pet_adoption_app",
            category: .home,
            blurb: "Adoption applications — org, animal, status.",
            keywords: ["adoption", "rescue", "shelter"],
            template: makeType(
                id: "PetAdoptionApp", name: "Application", plural: "Adoption Applications",
                image: "house.and.flag", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Organization", kind: .text, required: true),
                    FieldDef.make(name: "Animal name", kind: .text),
                    FieldDef.make(name: "Species / breed", kind: .text),
                    FieldDef.make(name: "Applied on", kind: .date, required: true),
                    selectField("Status", [
                        ("Submitted", "#3FA9F5"), ("Home visit", "#9D4DCC"),
                        ("Approved", "#3FB950"), ("Adopted!", "#E8A93B"),
                        ("Denied", "#D14B5C"), ("Withdrew", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "animal_name", kanban: "status", calendar: "applied_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.pet_foster",
            category: .home,
            blurb: "Pets fostered — animal, dates, outcome.",
            keywords: ["foster", "rescue", "temporary"],
            template: makeType(
                id: "PetFoster", name: "Foster", plural: "Pet Fosters",
                image: "house.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Animal name", kind: .text, required: true),
                    FieldDef.make(name: "Species / breed", kind: .text),
                    FieldDef.make(name: "Organization", kind: .text),
                    FieldDef.make(name: "Start", kind: .date, required: true),
                    FieldDef.make(name: "End", kind: .date),
                    selectField("Outcome", [
                        ("Adopted out", "#3FB950"), ("Adopted by me!", "#9D4DCC"),
                        ("Returned to shelter", "#666666"), ("Still here", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "animal_name", kanban: "outcome", calendar: "start", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.pet_chip",
            category: .home,
            blurb: "Pet microchip — chip number, registry, last updated.",
            keywords: ["microchip", "chip", "registry"],
            template: makeType(
                id: "PetChip", name: "Chip", plural: "Pet Microchips",
                image: "cpu", color: "#666666",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Chip number", kind: .text, required: true),
                    FieldDef.make(name: "Registry", kind: .text),
                    FieldDef.make(name: "Implanted on", kind: .date),
                    FieldDef.make(name: "Last verified", kind: .date),
                    FieldDef.make(name: "Account login", kind: .url),
                ],
                primary: "chip_number", calendar: "last_verified"
            )
        ),

        Entry(
            id: "lib.pet_allergy",
            category: .home,
            blurb: "Pet allergies — allergen, reaction, treatment.",
            keywords: ["pet allergy", "reaction", "diet"],
            template: makeType(
                id: "PetAllergy", name: "Allergy", plural: "Pet Allergies",
                image: "exclamationmark.shield.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Allergen", kind: .text, required: true),
                    selectField("Type", [
                        ("Food", "#E8A93B"), ("Environmental", "#3FB950"),
                        ("Medication", "#D14B5C"), ("Other", "#666666"),
                    ]),
                    selectField("Severity", [
                        ("Mild", "#3FA9F5"), ("Moderate", "#E8A93B"),
                        ("Severe", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Reaction", kind: .longText),
                    FieldDef.make(name: "Identified on", kind: .date),
                ],
                primary: "allergen", kanban: "severity"
            )
        ),

        Entry(
            id: "lib.pet_death",
            category: .home,
            blurb: "Pet death — date, cause, burial / cremation, where remains rest.",
            keywords: ["pet death", "rainbow bridge", "memorial"],
            template: makeType(
                id: "PetDeath", name: "Memorial", plural: "Pet Memorials",
                image: "leaf.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Pet", kind: .link, required: true),
                    FieldDef.make(name: "Date passed", kind: .date, required: true),
                    FieldDef.make(name: "Age", kind: .text),
                    FieldDef.make(name: "Cause", kind: .text),
                    selectField("Disposition", [
                        ("Cremated", "#3FA9F5"), ("Buried", "#3FB950"),
                        ("Aquamation", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Where remains rest", kind: .text),
                    FieldDef.make(name: "Memorial photo", kind: .attachment),
                    FieldDef.make(name: "What I'll always remember", kind: .richText),
                ],
                primary: "pet", kanban: "disposition", calendar: "date_passed", gallery: "memorial_photo"
            )
        ),

        // MARK: - Nature Observation

        Entry(
            id: "lib.animal_track",
            category: .unusual,
            blurb: "Animal tracks ID'd — species, soil, photo, location.",
            keywords: ["track", "footprint", "tracking", "wildlife"],
            template: makeType(
                id: "AnimalTrack", name: "Track", plural: "Animal Tracks",
                image: "pawprint.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Species (or guess)", kind: .text, required: true),
                    FieldDef.make(name: "Date observed", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Substrate", [
                        ("Mud", "#7B4F2F"), ("Sand", "#E8A93B"),
                        ("Snow", "#FFFFFF"), ("Dust", "#888888"),
                        ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "Track size (in)", kind: .number),
                    FieldDef.make(name: "Confidence (1–5)", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species_or_guess", kanban: "substrate", calendar: "date_observed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.scat",
            category: .unusual,
            blurb: "Scat / droppings ID'd — species, age, photo (for naturalist tracking).",
            keywords: ["scat", "droppings", "wildlife", "tracking"],
            template: makeType(
                id: "Scat", name: "Sign", plural: "Scat Sightings",
                image: "circle.dashed.inset.filled", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Species (or guess)", kind: .text, required: true),
                    FieldDef.make(name: "Date observed", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Age", [
                        ("Fresh", "#3FB950"), ("Recent (days)", "#E8A93B"),
                        ("Old", "#666666"),
                    ]),
                    FieldDef.make(name: "Diet inferred", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species_or_guess", kanban: "age", calendar: "date_observed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.skull_found",
            category: .unusual,
            blurb: "Skulls found — species, location, condition.",
            keywords: ["skull", "bone", "naturalist"],
            template: makeType(
                id: "SkullFound", name: "Skull", plural: "Skulls Found",
                image: "circle.grid.cross.left.filled", color: "#666666",
                fields: [
                    FieldDef.make(name: "Species (or guess)", kind: .text, required: true),
                    FieldDef.make(name: "Found on", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Condition", [
                        ("Fresh (smelly)", "#D14B5C"), ("Bone clean", "#3FB950"),
                        ("Weathered", "#E8A93B"), ("Broken", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Kept?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "species_or_guess", kanban: "condition", calendar: "found_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.antler_shed",
            category: .unusual,
            blurb: "Antler sheds found — species, point count, location.",
            keywords: ["antler", "shed", "deer", "elk"],
            template: makeType(
                id: "AntlerShed", name: "Shed", plural: "Antler Sheds",
                image: "burst.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Date found", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Point count", kind: .number),
                    FieldDef.make(name: "Length (in)", kind: .number),
                    FieldDef.make(name: "Side (L/R)", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species", calendar: "date_found", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.feather_found",
            category: .unusual,
            blurb: "Feathers found — species, body part.",
            keywords: ["feather", "bird", "naturalist"],
            template: makeType(
                id: "FeatherFound", name: "Feather", plural: "Feathers Found",
                image: "feather", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Species (or guess)", kind: .text, required: true),
                    FieldDef.make(name: "Date found", kind: .date),
                    selectField("Body part", [
                        ("Flight / primary", "#9D4DCC"), ("Tail", "#E8A93B"),
                        ("Body / contour", "#3FA9F5"), ("Down", "#F0E68C"),
                        ("Unknown", "#666666"),
                    ]),
                    FieldDef.make(name: "Length (cm)", kind: .number),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species_or_guess", kanban: "body_part", calendar: "date_found", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.plant_pressed",
            category: .unusual,
            blurb: "Pressed plants — species, date, paper used.",
            keywords: ["pressed plant", "herbarium", "naturalist"],
            template: makeType(
                id: "PressedPlant", name: "Specimen", plural: "Pressed Plants",
                image: "leaf.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Collected on", kind: .date, required: true),
                    FieldDef.make(name: "Collected at", kind: .text),
                    FieldDef.make(name: "Pressing paper", kind: .text),
                    FieldDef.make(name: "Press date", kind: .date),
                    FieldDef.make(name: "Mounted?", kind: .boolean),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species", calendar: "collected_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.leaf_preserved",
            category: .unusual,
            blurb: "Leaves preserved — species, color, framing.",
            keywords: ["leaf", "fall", "preserved", "wax paper"],
            template: makeType(
                id: "LeafPreserved", name: "Leaf", plural: "Preserved Leaves",
                image: "leaf.circle.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Species", kind: .text, required: true),
                    FieldDef.make(name: "Color", kind: .text),
                    selectField("Season", [
                        ("Spring", "#3FB950"), ("Summer", "#3FA9F5"),
                        ("Fall", "#F08C2E"), ("Winter", "#666666"),
                    ]),
                    FieldDef.make(name: "Collected on", kind: .date),
                    selectField("Method", [
                        ("Wax paper", "#E8A93B"), ("Glycerin", "#9D4DCC"),
                        ("Pressed", "#3FB950"), ("Mod Podge", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Where displayed", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species", kanban: "season", calendar: "collected_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.seed_saved",
            category: .unusual,
            blurb: "Seeds saved — variety, harvest date, viability test.",
            keywords: ["seed", "save", "harvest", "viability"],
            template: makeType(
                id: "SeedSaved", name: "Seed", plural: "Saved Seeds",
                image: "leaf.arrow.triangle.circlepath", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Variety", kind: .text, required: true),
                    FieldDef.make(name: "Harvested on", kind: .date, required: true),
                    FieldDef.make(name: "Parent plant source", kind: .text),
                    FieldDef.make(name: "Viability test date", kind: .date),
                    FieldDef.make(name: "Viability %", kind: .number),
                    FieldDef.make(name: "Storage location", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "variety", calendar: "harvested_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.beachcombing",
            category: .unusual,
            blurb: "Beach combing finds — item, beach, date.",
            keywords: ["beachcombing", "beach", "find"],
            template: makeType(
                id: "BeachcombingFind", name: "Find", plural: "Beachcombing Finds",
                image: "beach.umbrella.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Beach", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Type", [
                        ("Shell", "#E8A93B"), ("Sea glass", "#3FA9F5"),
                        ("Driftwood", "#7B4F2F"), ("Rock", "#666666"),
                        ("Bottle / trash", "#9D4DCC"), ("Other", "#888888"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "type", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sea_glass",
            category: .unusual,
            blurb: "Sea glass found — color, beach, age estimate.",
            keywords: ["sea glass", "beach glass", "tumbled"],
            template: makeType(
                id: "SeaGlass", name: "Piece", plural: "Sea Glass",
                image: "drop.degreesign", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Color", kind: .text, required: true),
                    FieldDef.make(name: "Beach", kind: .text),
                    FieldDef.make(name: "Date found", kind: .date),
                    selectField("Frostiness", [
                        ("Pristine matte", "#3FB950"), ("Well-frosted", "#3FA9F5"),
                        ("Lightly frosted", "#E8A93B"), ("Sharp / fresh", "#D14B5C"),
                    ]),
                    selectField("Rarity", [
                        ("Common", "#888888"), ("Uncommon", "#3FA9F5"),
                        ("Rare", "#9D4DCC"), ("Ultra rare (red/orange)", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "color", kanban: "rarity", calendar: "date_found", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.driftwood",
            category: .unusual,
            blurb: "Driftwood collected — shape, beach.",
            keywords: ["driftwood", "beach", "wood"],
            template: makeType(
                id: "Driftwood", name: "Piece", plural: "Driftwood",
                image: "tree", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Nickname / shape", kind: .text, required: true),
                    FieldDef.make(name: "Beach", kind: .text),
                    FieldDef.make(name: "Found on", kind: .date),
                    FieldDef.make(name: "Length (in)", kind: .number),
                    FieldDef.make(name: "Intended use", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "nickname_shape", calendar: "found_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.shell_found",
            category: .unusual,
            blurb: "Shells found — species, beach.",
            keywords: ["shell", "conchology", "beach"],
            template: makeType(
                id: "ShellFound", name: "Shell", plural: "Shells",
                image: "shell.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Species (or family)", kind: .text, required: true),
                    FieldDef.make(name: "Common name", kind: .text),
                    FieldDef.make(name: "Beach", kind: .text),
                    FieldDef.make(name: "Found on", kind: .date),
                    FieldDef.make(name: "Size (in)", kind: .number),
                    selectField("Condition", [
                        ("Whole intact", "#3FB950"), ("Chipped", "#E8A93B"),
                        ("Worn", "#3FA9F5"), ("Fragment", "#666666"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "common_name", kanban: "condition", calendar: "found_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sand_sample",
            category: .unusual,
            blurb: "Sand samples — beach, mineral mix, jar id.",
            keywords: ["sand", "sample", "geology"],
            template: makeType(
                id: "SandSample", name: "Sample", plural: "Sand Samples",
                image: "circle.dotted", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Beach", kind: .text, required: true),
                    FieldDef.make(name: "Country", kind: .text),
                    FieldDef.make(name: "Collected on", kind: .date),
                    FieldDef.make(name: "Color description", kind: .text),
                    FieldDef.make(name: "Mineral / origin notes", kind: .longText),
                    FieldDef.make(name: "Jar / vial label", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "beach", calendar: "collected_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.crystal_grown",
            category: .unusual,
            blurb: "Crystals grown at home — solution, days, photo.",
            keywords: ["crystal", "grow", "borax", "salt"],
            template: makeType(
                id: "CrystalGrown", name: "Crystal", plural: "Crystals Grown",
                image: "diamond", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Solute used", kind: .text, required: true),
                    FieldDef.make(name: "Started on", kind: .date, required: true),
                    FieldDef.make(name: "Days to harvest", kind: .number),
                    FieldDef.make(name: "Size achieved (mm)", kind: .number),
                    selectField("Result", [
                        ("Failure", "#D14B5C"), ("Tiny", "#E8A93B"),
                        ("Good", "#3FA9F5"), ("Excellent", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "solute_used", kanban: "result", calendar: "started_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.lichen",
            category: .unusual,
            blurb: "Lichen ID'd — species, substrate.",
            keywords: ["lichen", "moss", "fungus", "symbiosis"],
            template: makeType(
                id: "LichenID", name: "Lichen", plural: "Lichen Sightings",
                image: "leaf", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species (or guess)", kind: .text, required: true),
                    FieldDef.make(name: "Date observed", kind: .date),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Growth form", [
                        ("Crustose", "#666666"), ("Foliose", "#3FB950"),
                        ("Fruticose", "#9D4DCC"), ("Squamulose", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Substrate", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species_or_guess", kanban: "growth_form", calendar: "date_observed", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.moss_id",
            category: .unusual,
            blurb: "Mosses identified — species, habitat.",
            keywords: ["moss", "bryophyte", "naturalist"],
            template: makeType(
                id: "MossID", name: "Moss", plural: "Moss Sightings",
                image: "leaf.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Species (or guess)", kind: .text, required: true),
                    FieldDef.make(name: "Date observed", kind: .date),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Habitat", [
                        ("Rock", "#666666"), ("Soil", "#7B4F2F"),
                        ("Bark", "#9D4DCC"), ("Wet / water", "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Confidence (1–5)", kind: .rating),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "species_or_guess", kanban: "habitat", calendar: "date_observed", gallery: "photo"
            )
        ),

        // MARK: - Relationships

        Entry(
            id: "lib.partner_checkin",
            category: .relationships,
            blurb: "Spouse / partner check-in — date, topics, agreements.",
            keywords: ["partner", "spouse", "check-in", "couples"],
            template: makeType(
                id: "PartnerCheckin", name: "Check-in", plural: "Partner Check-ins",
                image: "heart.text.square.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Topics discussed", kind: .longText),
                    FieldDef.make(name: "Agreements", kind: .richText),
                    FieldDef.make(name: "What I'm grateful for about them", kind: .longText),
                    FieldDef.make(name: "Next check-in", kind: .date),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.couples_therapy",
            category: .relationships,
            blurb: "Couples therapy session — therapist, topics, homework.",
            keywords: ["couples therapy", "counseling", "homework"],
            template: makeType(
                id: "CouplesTherapy", name: "Session", plural: "Couples Therapy",
                image: "person.2.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Therapist", kind: .link),
                    FieldDef.make(name: "Topics", kind: .richText),
                    FieldDef.make(name: "Homework", kind: .longText),
                    FieldDef.make(name: "Next session", kind: .date),
                    FieldDef.make(name: "Notes (private)", kind: .richText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.dating_profile",
            category: .relationships,
            blurb: "Dating profile setups — platform, prompts, photos.",
            keywords: ["dating", "profile", "hinge", "tinder", "bumble"],
            template: makeType(
                id: "DatingProfile", name: "Profile", plural: "Dating Profiles",
                image: "person.crop.rectangle.stack", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Platform", kind: .text, required: true),
                    FieldDef.make(name: "Setup date", kind: .date),
                    FieldDef.make(name: "Prompts / bio", kind: .richText),
                    FieldDef.make(name: "Photos used", kind: .longText),
                    selectField("Status", [
                        ("Active", "#3FB950"), ("Paused", "#E8A93B"),
                        ("Deleted", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes / experiments", kind: .longText),
                ],
                primary: "platform", kanban: "status", calendar: "setup_date"
            )
        ),

        Entry(
            id: "lib.date_asked",
            category: .relationships,
            blurb: "Times you asked someone out — person, where, outcome.",
            keywords: ["asked out", "date", "courage"],
            template: makeType(
                id: "DateAsked", name: "Ask", plural: "Dates Asked",
                image: "heart.circle", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "When asked", kind: .date, required: true),
                    FieldDef.make(name: "Asked for", kind: .text, description: "Coffee, dinner, walk…"),
                    selectField("Outcome", [
                        ("Yes", "#3FB950"), ("Rain check", "#E8A93B"),
                        ("No thanks", "#666666"), ("No reply", "#888888"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "person", kanban: "outcome", calendar: "when_asked"
            )
        ),

        Entry(
            id: "lib.breakup",
            category: .relationships,
            blurb: "Breakups — person, when, agreed-on terms.",
            keywords: ["breakup", "split", "ended"],
            template: makeType(
                id: "Breakup", name: "Breakup", plural: "Breakups",
                image: "heart.slash", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "With whom", kind: .link, required: true),
                    FieldDef.make(name: "Relationship length", kind: .text),
                    FieldDef.make(name: "Ended on", kind: .date, required: true),
                    selectField("Mutual?", [
                        ("Mutual", "#3FA9F5"), ("I initiated", "#9D4DCC"),
                        ("They initiated", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Reason / story", kind: .richText),
                    FieldDef.make(name: "Agreed-on terms", kind: .longText),
                    FieldDef.make(name: "Lessons", kind: .richText),
                ],
                primary: "with_whom", kanban: "mutual", calendar: "ended_on"
            )
        ),

        Entry(
            id: "lib.reconciliation",
            category: .relationships,
            blurb: "Reconciliations — person, when, what changed.",
            keywords: ["reconcile", "make up", "patched"],
            template: makeType(
                id: "Reconciliation", name: "Reconciliation", plural: "Reconciliations",
                image: "arrow.triangle.merge", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Reconciled on", kind: .date, required: true),
                    FieldDef.make(name: "What we fixed", kind: .richText),
                    FieldDef.make(name: "Changes I committed to", kind: .longText),
                    FieldDef.make(name: "Changes they committed to", kind: .longText),
                ],
                primary: "person", calendar: "reconciled_on"
            )
        ),

        Entry(
            id: "lib.friend_made",
            category: .relationships,
            blurb: "New friend made — where met, what clicked.",
            keywords: ["friend", "made", "new connection"],
            template: makeType(
                id: "FriendMade", name: "Friendship", plural: "Friends Made",
                image: "person.crop.circle.badge.plus", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Met on", kind: .date),
                    FieldDef.make(name: "Where / how", kind: .text),
                    FieldDef.make(name: "What clicked", kind: .longText),
                    selectField("Tier (Dunbar-ish)", [
                        ("Acquaintance", "#888888"), ("Friendly", "#3FA9F5"),
                        ("Close friend", "#9D4DCC"), ("Inner circle", "#3FB950"),
                    ]),
                ],
                primary: "person", kanban: "tier_dunbar_ish", calendar: "met_on"
            )
        ),

        Entry(
            id: "lib.friend_drifted",
            category: .relationships,
            blurb: "Friend drifted — person, last contact, reasons.",
            keywords: ["drifted", "friendship", "fade"],
            template: makeType(
                id: "FriendDrifted", name: "Drift", plural: "Friends Drifted",
                image: "person.crop.circle.badge.minus", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Last contact", kind: .date),
                    FieldDef.make(name: "Drift began (approx)", kind: .text),
                    FieldDef.make(name: "Suspected reason", kind: .longText),
                    selectField("Want to reconnect?", [
                        ("Yes, soon", "#3FB950"), ("Maybe, someday", "#3FA9F5"),
                        ("Not actively", "#E8A93B"), ("Let it go", "#666666"),
                    ]),
                ],
                primary: "person", kanban: "want_to_reconnect", calendar: "last_contact"
            )
        ),

        Entry(
            id: "lib.estrangement",
            category: .relationships,
            blurb: "Estrangements — person, date, status, contact rules.",
            keywords: ["estrangement", "cut off", "no contact"],
            template: makeType(
                id: "Estrangement", name: "Estrangement", plural: "Estrangements",
                image: "person.crop.circle.fill.badge.xmark", color: "#666666",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Began on", kind: .date, required: true),
                    selectField("Status", [
                        ("Active", "#D14B5C"), ("Cautious contact", "#E8A93B"),
                        ("In thaw", "#3FA9F5"), ("Reconciled", "#3FB950"),
                    ]),
                    FieldDef.make(name: "Contact rules", kind: .richText),
                    FieldDef.make(name: "Reason / story", kind: .richText),
                ],
                primary: "person", kanban: "status", calendar: "began_on"
            )
        ),

        Entry(
            id: "lib.family_reunion",
            category: .relationships,
            blurb: "Family reunion attended — when, where, who, photo.",
            keywords: ["family reunion", "gathering", "extended family"],
            template: makeType(
                id: "FamilyReunion", name: "Reunion", plural: "Family Reunions",
                image: "person.3.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Hosting branch / family", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Attendees", kind: .link),
                    FieldDef.make(name: "Highlights", kind: .richText),
                    FieldDef.make(name: "Group photo", kind: .attachment),
                ],
                primary: "hosting_branch_family", calendar: "date", gallery: "group_photo"
            )
        ),

        Entry(
            id: "lib.family_movie_night",
            category: .relationships,
            blurb: "Family movie nights — movie, who watched, vote.",
            keywords: ["family", "movie night", "fun"],
            template: makeType(
                id: "FamilyMovieNight", name: "Night", plural: "Family Movie Nights",
                image: "tv.and.mediabox", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Movie", kind: .text, required: true),
                    FieldDef.make(name: "Who watched", kind: .link),
                    FieldDef.make(name: "Family vote (1-10)", kind: .number),
                    FieldDef.make(name: "Snacks", kind: .text),
                    FieldDef.make(name: "Notes / quotes", kind: .longText),
                ],
                primary: "movie", calendar: "date"
            )
        ),

        Entry(
            id: "lib.game_night",
            category: .relationships,
            blurb: "Game nights — game played, who, winner.",
            keywords: ["game night", "tabletop", "fun"],
            template: makeType(
                id: "GameNight", name: "Night", plural: "Game Nights",
                image: "die.face.3", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Game played", kind: .link),
                    FieldDef.make(name: "Players", kind: .link),
                    FieldDef.make(name: "Winner", kind: .link),
                    FieldDef.make(name: "Final score / outcome", kind: .text),
                    FieldDef.make(name: "Highlight moment", kind: .longText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.dinner_party_hosted",
            category: .relationships,
            blurb: "Dinner parties you hosted — date, guests, menu.",
            keywords: ["dinner party", "host", "entertaining"],
            template: makeType(
                id: "DinnerPartyHosted", name: "Party", plural: "Dinner Parties Hosted",
                image: "fork.knife.circle.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Occasion / theme", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Guests", kind: .link),
                    FieldDef.make(name: "Menu", kind: .richText),
                    FieldDef.make(name: "What worked", kind: .longText),
                    FieldDef.make(name: "What I'd change", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "occasion_theme", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.dinner_party_attended",
            category: .relationships,
            blurb: "Dinner parties you attended — host, occasion, host gift.",
            keywords: ["dinner party", "attend", "guest"],
            template: makeType(
                id: "DinnerPartyAttended", name: "Party", plural: "Dinner Parties Attended",
                image: "fork.knife.circle", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Host", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Occasion", kind: .text),
                    FieldDef.make(name: "Host gift brought", kind: .text),
                    FieldDef.make(name: "Memorable dish", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "host", calendar: "date"
            )
        ),

        Entry(
            id: "lib.cocktail_party",
            category: .relationships,
            blurb: "Cocktail parties — host, vibe, who introduced you to whom.",
            keywords: ["cocktail party", "mingling", "social"],
            template: makeType(
                id: "CocktailParty", name: "Party", plural: "Cocktail Parties",
                image: "wineglass", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Host", kind: .link),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Theme / vibe", kind: .text),
                    FieldDef.make(name: "New people met", kind: .longText),
                    FieldDef.make(name: "Memorable conversation", kind: .richText),
                ],
                primary: "host", calendar: "date"
            )
        ),

        Entry(
            id: "lib.brunch_outing",
            category: .relationships,
            blurb: "Brunch outings — where, who, dish, plan again.",
            keywords: ["brunch", "weekend", "social"],
            template: makeType(
                id: "BrunchOuting", name: "Brunch", plural: "Brunches",
                image: "sun.haze", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Restaurant", kind: .link),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "With whom", kind: .link),
                    FieldDef.make(name: "What I ordered", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "restaurant", calendar: "date"
            )
        ),

        Entry(
            id: "lib.coffee_chat",
            category: .relationships,
            blurb: "Coffee chats — person, topic, follow-up.",
            keywords: ["coffee chat", "catch up", "informal"],
            template: makeType(
                id: "CoffeeChat", name: "Chat", plural: "Coffee Chats",
                image: "cup.and.saucer", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Topics", kind: .longText),
                    FieldDef.make(name: "Follow-up", kind: .text),
                    FieldDef.make(name: "Energy after (1–5)", kind: .rating),
                ],
                primary: "person", calendar: "date"
            )
        ),

        Entry(
            id: "lib.walk_and_talk",
            category: .relationships,
            blurb: "Walk-and-talks — person, route, what we discussed.",
            keywords: ["walk and talk", "stroll", "conversation"],
            template: makeType(
                id: "WalkAndTalk", name: "Walk", plural: "Walk-and-Talks",
                image: "figure.walk.motion", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Route", kind: .text),
                    FieldDef.make(name: "Distance (mi)", kind: .number),
                    FieldDef.make(name: "Topics discussed", kind: .richText),
                ],
                primary: "person", calendar: "date"
            )
        ),

        Entry(
            id: "lib.reference_given",
            category: .relationships,
            blurb: "References you gave — person, role, what you said.",
            keywords: ["reference", "recommendation", "vouched"],
            template: makeType(
                id: "ReferenceGiven", name: "Reference", plural: "References Given",
                image: "hand.thumbsup.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "For role / opportunity", kind: .text),
                    FieldDef.make(name: "Asked by", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Format", kind: .text, description: "Phone, email, written"),
                    FieldDef.make(name: "Talking points", kind: .longText),
                    selectField("Outcome", [
                        ("They got it", "#3FB950"), ("Didn't get it", "#D14B5C"),
                        ("Still pending", "#E8A93B"), ("Unknown", "#666666"),
                    ]),
                ],
                primary: "person", kanban: "outcome", calendar: "date"
            )
        ),

        Entry(
            id: "lib.borrowed_item",
            category: .relationships,
            blurb: "Items I've borrowed — from whom, return by.",
            keywords: ["borrowed", "owe", "return"],
            template: makeType(
                id: "BorrowedItem", name: "Borrowed", plural: "Items I've Borrowed",
                image: "arrow.down.right.square", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "From whom", kind: .link),
                    FieldDef.make(name: "Borrowed on", kind: .date),
                    FieldDef.make(name: "Return by", kind: .date),
                    selectField("Status", [
                        ("Still have", "#E8A93B"), ("Returned", "#3FB950"),
                        ("Lost", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "status", calendar: "return_by"
            )
        ),

        Entry(
            id: "lib.lent_item",
            category: .relationships,
            blurb: "Items I've lent out — to whom, return by.",
            keywords: ["lent", "loaned", "owed back"],
            template: makeType(
                id: "LentItem", name: "Lent", plural: "Items I've Lent",
                image: "arrow.up.right.square", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "To whom", kind: .link),
                    FieldDef.make(name: "Lent on", kind: .date),
                    FieldDef.make(name: "Expected back", kind: .date),
                    selectField("Status", [
                        ("Out", "#E8A93B"), ("Returned", "#3FB950"),
                        ("Lost / unreturned", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "item", kanban: "status", calendar: "expected_back"
            )
        ),

        Entry(
            id: "lib.forgiveness_offered",
            category: .relationships,
            blurb: "Forgiveness offered — whom, what, date.",
            keywords: ["forgive", "forgave", "let go"],
            template: makeType(
                id: "ForgivenessOffered", name: "Act", plural: "Forgiveness Offered",
                image: "heart.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "For what", kind: .text),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "How I told them (if at all)", kind: .text),
                    FieldDef.make(name: "What it freed up", kind: .longText),
                ],
                primary: "person", calendar: "date"
            )
        ),

        Entry(
            id: "lib.forgiveness_asked",
            category: .relationships,
            blurb: "Forgiveness asked — whom, what, response.",
            keywords: ["sorry", "apologized", "asked forgiveness"],
            template: makeType(
                id: "ForgivenessAsked", name: "Ask", plural: "Forgiveness Asked",
                image: "heart.circle.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "For what", kind: .text, required: true),
                    FieldDef.make(name: "Date asked", kind: .date),
                    selectField("Response", [
                        ("Accepted", "#3FB950"), ("Need time", "#E8A93B"),
                        ("Refused", "#D14B5C"), ("Unclear", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "person", kanban: "response", calendar: "date_asked"
            )
        ),

        Entry(
            id: "lib.promise_made",
            category: .relationships,
            blurb: "Promises made — whom, what, deadline.",
            keywords: ["promise", "commitment", "kept"],
            template: makeType(
                id: "PromiseMade", name: "Promise", plural: "Promises Made",
                image: "hands.clap.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Promise", kind: .text, required: true),
                    FieldDef.make(name: "To whom", kind: .link),
                    FieldDef.make(name: "Made on", kind: .date),
                    FieldDef.make(name: "Deadline", kind: .date),
                    selectField("Status", [
                        ("Active", "#3FA9F5"), ("Kept", "#3FB950"),
                        ("Broken", "#D14B5C"), ("Renegotiated", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "promise", kanban: "status", calendar: "deadline"
            )
        ),

        Entry(
            id: "lib.boundary_set",
            category: .relationships,
            blurb: "Boundaries set — with whom, what, response.",
            keywords: ["boundary", "limit", "say no"],
            template: makeType(
                id: "BoundarySet", name: "Boundary", plural: "Boundaries",
                image: "hand.raised.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Boundary", kind: .text, required: true),
                    FieldDef.make(name: "With whom", kind: .link),
                    FieldDef.make(name: "Set on", kind: .date),
                    FieldDef.make(name: "Why", kind: .longText),
                    selectField("Response", [
                        ("Respected", "#3FB950"), ("Pushed back", "#E8A93B"),
                        ("Violated", "#D14B5C"), ("Unknown", "#666666"),
                    ]),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "boundary", kanban: "response", calendar: "set_on"
            )
        ),

        Entry(
            id: "lib.person_passed",
            category: .relationships,
            blurb: "Person who passed away — name, relation, date.",
            keywords: ["death", "passed", "memorial"],
            template: makeType(
                id: "PersonPassed", name: "Memorial", plural: "In Memoriam",
                image: "leaf.fill", color: "#666666",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Relation to me", kind: .text),
                    FieldDef.make(name: "Date passed", kind: .date, required: true),
                    FieldDef.make(name: "Cause", kind: .text),
                    FieldDef.make(name: "Where they rest", kind: .text),
                    FieldDef.make(name: "What I miss most", kind: .richText),
                    FieldDef.make(name: "Memorial photo", kind: .attachment),
                ],
                primary: "person", calendar: "date_passed", gallery: "memorial_photo"
            )
        ),

        Entry(
            id: "lib.memorial_attended",
            category: .relationships,
            blurb: "Memorial / funeral attended — date, location, eulogy notes.",
            keywords: ["funeral", "memorial", "wake"],
            template: makeType(
                id: "MemorialAttended", name: "Memorial", plural: "Memorials Attended",
                image: "person.crop.square.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "For (person)", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Eulogy notes", kind: .richText),
                    FieldDef.make(name: "Who else attended", kind: .link),
                    FieldDef.make(name: "What I want to remember", kind: .richText),
                ],
                primary: "for_person", calendar: "date"
            )
        ),

        Entry(
            id: "lib.eulogy_delivered",
            category: .relationships,
            blurb: "Eulogies delivered — whom, date, text.",
            keywords: ["eulogy", "spoke at funeral", "tribute"],
            template: makeType(
                id: "EulogyDelivered", name: "Eulogy", plural: "Eulogies Delivered",
                image: "mic", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "For (person)", kind: .link, required: true),
                    FieldDef.make(name: "Delivered on", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Text", kind: .richText),
                    FieldDef.make(name: "Audio / video", kind: .attachment),
                ],
                primary: "for_person", calendar: "delivered_on"
            )
        ),

        Entry(
            id: "lib.death_anniversary",
            category: .relationships,
            blurb: "Death anniversaries — recurring date, who, traditions.",
            keywords: ["death anniversary", "remembrance"],
            template: makeType(
                id: "DeathAnniversary", name: "Anniversary", plural: "Death Anniversaries",
                image: "calendar.badge.exclamationmark", color: "#666666",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Date passed", kind: .date, required: true),
                    FieldDef.make(name: "How I observe it", kind: .richText),
                    FieldDef.make(name: "Traditions", kind: .longText),
                ],
                primary: "person", calendar: "date_passed"
            )
        ),

        Entry(
            id: "lib.grief_milestone",
            category: .relationships,
            blurb: "Grief milestones — months out, what's shifted.",
            keywords: ["grief", "milestone", "healing"],
            template: makeType(
                id: "GriefMilestone", name: "Milestone", plural: "Grief Milestones",
                image: "heart.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Person mourning", kind: .link, required: true),
                    FieldDef.make(name: "Milestone", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "What's shifted", kind: .richText),
                    FieldDef.make(name: "What's still hard", kind: .longText),
                ],
                primary: "milestone", calendar: "date"
            )
        ),

        Entry(
            id: "lib.outfit_for",
            category: .relationships,
            blurb: "Outfits you wore for events — event, outfit, photo.",
            keywords: ["outfit", "event", "wore", "fit"],
            template: makeType(
                id: "OutfitFor", name: "Outfit", plural: "Outfits",
                image: "tshirt.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Event", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Outfit description", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    selectField("Verdict", [
                        ("Nailed it", "#3FB950"), ("Good", "#3FA9F5"),
                        ("OK", "#E8A93B"), ("Wrong call", "#D14B5C"),
                    ]),
                ],
                primary: "event", kanban: "verdict", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.coffee_order_friend",
            category: .relationships,
            blurb: "Coffee orders for friends — person, drink.",
            keywords: ["coffee order", "drink", "preferences"],
            template: makeType(
                id: "CoffeeOrderForFriend", name: "Order", plural: "Friend Coffee Orders",
                image: "cup.and.saucer.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Their order", kind: .text, required: true),
                    FieldDef.make(name: "Spot they like", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "person"
            )
        ),

        Entry(
            id: "lib.drink_order_friend",
            category: .relationships,
            blurb: "Drink orders for friends — whisky neat, hopped seltzer, etc.",
            keywords: ["drink order", "bar", "cocktail preferences"],
            template: makeType(
                id: "DrinkOrderForFriend", name: "Order", plural: "Friend Drink Orders",
                image: "wineglass.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Standard order", kind: .text, required: true),
                    FieldDef.make(name: "Won't drink", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "person"
            )
        ),

        Entry(
            id: "lib.dish_pref_friend",
            category: .relationships,
            blurb: "Food preferences / allergies for friends and family.",
            keywords: ["food preferences", "allergies", "dietary"],
            template: makeType(
                id: "DishPrefForFriend", name: "Preference", plural: "Friend Dietary Prefs",
                image: "fork.knife.circle", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    selectField("Diet", [
                        ("Anything", "#3FB950"), ("Vegetarian", "#E8A93B"),
                        ("Vegan", "#9D4DCC"), ("Pescatarian", "#3FA9F5"),
                        ("Kosher", "#666666"), ("Halal", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "Allergies", kind: .text),
                    FieldDef.make(name: "Dislikes", kind: .text),
                    FieldDef.make(name: "Favorite cuisines", kind: .text),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "person", kanban: "diet"
            )
        ),

        Entry(
            id: "lib.gift_list_for",
            category: .relationships,
            blurb: "Birthday / holiday gift ideas per person — recurring brainstorm.",
            keywords: ["gift list", "per person", "ideas"],
            template: makeType(
                id: "GiftListFor", name: "Idea", plural: "Gift Ideas Per Person",
                image: "gift.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "For", kind: .link, required: true),
                    FieldDef.make(name: "Gift idea", kind: .text, required: true),
                    selectField("Occasion", [
                        ("Birthday", "#9D4DCC"), ("Christmas / Holiday", "#3FB950"),
                        ("Anniversary", "#D14B5C"), ("Just because", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Estimated cost", kind: .number),
                    FieldDef.make(name: "Where to find", kind: .url),
                    selectField("Status", [
                        ("Idea", "#888888"), ("Saved up", "#3FA9F5"),
                        ("Bought", "#3FB950"), ("Given", "#9D4DCC"),
                        ("Skipped", "#666666"),
                    ]),
                ],
                primary: "gift_idea", kanban: "status"
            )
        ),

        Entry(
            id: "lib.name_forgotten",
            category: .relationships,
            blurb: "People whose names you've blanked on — description, where met.",
            keywords: ["name forgotten", "who is that", "blank"],
            template: makeType(
                id: "NameForgotten", name: "Person", plural: "Names I've Forgotten",
                image: "person.crop.square.fill", color: "#888888",
                fields: [
                    FieldDef.make(name: "Description / appearance", kind: .text, required: true),
                    FieldDef.make(name: "Where I last saw them", kind: .text),
                    FieldDef.make(name: "Last seen", kind: .date),
                    FieldDef.make(name: "Context", kind: .longText),
                    FieldDef.make(name: "Memorable detail", kind: .text),
                    selectField("Status", [
                        ("Still don't know", "#D14B5C"), ("Half-remembered", "#E8A93B"),
                        ("Confirmed", "#3FB950"),
                    ]),
                ],
                primary: "description_appearance", kanban: "status", calendar: "last_seen"
            )
        ),

        // MARK: - Unusual & Truly Weird

        Entry(
            id: "lib.sleep_talking",
            category: .unusual,
            blurb: "Sleep talking episodes — what you said, who heard.",
            keywords: ["sleep talk", "somniloquy", "weird"],
            template: makeType(
                id: "SleepTalking", name: "Episode", plural: "Sleep Talking",
                image: "bubble.middle.bottom", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "What I (allegedly) said", kind: .longText),
                    FieldDef.make(name: "Who heard", kind: .link),
                    selectField("Intensity", [
                        ("Mutter", "#888888"), ("Clear sentence", "#3FA9F5"),
                        ("Conversation", "#9D4DCC"), ("Yelled", "#D14B5C"),
                    ]),
                ],
                primary: "date", kanban: "intensity", calendar: "date"
            )
        ),

        Entry(
            id: "lib.sleepwalk",
            category: .unusual,
            blurb: "Sleepwalking episodes — date, where you went.",
            keywords: ["sleepwalk", "somnambulism", "weird"],
            template: makeType(
                id: "Sleepwalk", name: "Episode", plural: "Sleepwalking",
                image: "moon.dust.fill", color: "#666666",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Where I went", kind: .text),
                    FieldDef.make(name: "Witness", kind: .link),
                    FieldDef.make(name: "Duration (min)", kind: .number),
                    FieldDef.make(name: "Outcome", kind: .longText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.obe",
            category: .unusual,
            blurb: "Out-of-body experiences — date, vividness, details.",
            keywords: ["obe", "out of body", "astral"],
            template: makeType(
                id: "OBE", name: "Experience", plural: "Out-of-Body Experiences",
                image: "person.fill.viewfinder", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Vividness", [
                        ("Faint", "#888888"), ("Clear", "#3FA9F5"),
                        ("Vivid", "#9D4DCC"), ("Hyper-real", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "What I experienced", kind: .richText),
                    FieldDef.make(name: "Triggered by", kind: .text),
                ],
                primary: "date", kanban: "vividness", calendar: "date"
            )
        ),

        Entry(
            id: "lib.nde",
            category: .unusual,
            blurb: "Near-death experience accounts.",
            keywords: ["nde", "near death"],
            template: makeType(
                id: "NDE", name: "Experience", plural: "NDE",
                image: "heart.slash.circle", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Circumstance", kind: .text),
                    FieldDef.make(name: "What I remember", kind: .richText),
                    FieldDef.make(name: "Lasting effect", kind: .longText),
                ],
                primary: "circumstance", calendar: "date"
            )
        ),

        Entry(
            id: "lib.doppelganger",
            category: .unusual,
            blurb: "Doppelgänger sightings — where, who, photo.",
            keywords: ["doppelganger", "lookalike", "twin"],
            template: makeType(
                id: "Doppelganger", name: "Sighting", plural: "Doppelgängers",
                image: "person.2", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Who they looked like", kind: .text),
                    FieldDef.make(name: "How similar (1–10)", kind: .number),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "who_they_looked_like", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.mistaken_identity",
            category: .unusual,
            blurb: "Times you were mistaken for someone else.",
            keywords: ["mistaken identity", "thought I was"],
            template: makeType(
                id: "MistakenIdentity", name: "Mistake", plural: "Mistaken Identity",
                image: "person.crop.circle.badge.questionmark", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "By whom", kind: .text),
                    FieldDef.make(name: "Confused for", kind: .text),
                    FieldDef.make(name: "Story", kind: .richText),
                ],
                primary: "confused_for", calendar: "date"
            )
        ),

        Entry(
            id: "lib.wedding_crashed",
            category: .unusual,
            blurb: "Weddings (or other events) you crashed — couple, outcome.",
            keywords: ["crashed", "wedding crasher", "uninvited"],
            template: makeType(
                id: "WeddingCrashed", name: "Crash", plural: "Weddings Crashed",
                image: "party.popper.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Event", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Couple / hosts", kind: .text),
                    selectField("Outcome", [
                        ("Stayed all night", "#3FB950"), ("Caught but welcomed", "#3FA9F5"),
                        ("Politely shown out", "#E8A93B"), ("Ejected", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Story", kind: .richText),
                ],
                primary: "event", kanban: "outcome", calendar: "date"
            )
        ),

        Entry(
            id: "lib.hitchhiker",
            category: .unusual,
            blurb: "Hitchhikers you picked up — where, where they were going.",
            keywords: ["hitchhiker", "stranger", "ride"],
            template: makeType(
                id: "HitchhikerPickedUp", name: "Pickup", plural: "Hitchhikers",
                image: "hand.thumbsup", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Picked up at", kind: .text),
                    FieldDef.make(name: "Dropped off at", kind: .text),
                    FieldDef.make(name: "Miles together", kind: .number),
                    FieldDef.make(name: "Their story", kind: .richText),
                ],
                primary: "picked_up_at", calendar: "date"
            )
        ),

        Entry(
            id: "lib.stranger_convo",
            category: .unusual,
            blurb: "Memorable stranger conversations — where, gist.",
            keywords: ["stranger", "conversation", "memorable"],
            template: makeType(
                id: "StrangerConvo", name: "Convo", plural: "Stranger Conversations",
                image: "bubble.left.and.bubble.right.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Their description (no name)", kind: .text),
                    FieldDef.make(name: "Topic / gist", kind: .richText),
                    FieldDef.make(name: "What stuck with me", kind: .longText),
                ],
                primary: "topic_gist", calendar: "date"
            )
        ),

        Entry(
            id: "lib.wrong_number",
            category: .unusual,
            blurb: "Wrong-number calls / texts — conversation, outcome.",
            keywords: ["wrong number", "phone call", "weird"],
            template: makeType(
                id: "WrongNumber", name: "Call", plural: "Wrong-Number Calls",
                image: "phone.bubble.left", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Number that called", kind: .text),
                    selectField("Medium", [
                        ("Voice", "#3FA9F5"), ("Text", "#9D4DCC"),
                        ("Video", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Conversation", kind: .richText),
                    selectField("Outcome", [
                        ("Quick correction", "#3FB950"), ("Long conversation", "#9D4DCC"),
                        ("Became friend?!", "#F08C2E"), ("Hung up", "#666666"),
                    ]),
                ],
                primary: "number_that_called", kanban: "outcome", calendar: "date"
            )
        ),

        Entry(
            id: "lib.mystery_package",
            category: .unusual,
            blurb: "Mysterious packages received — sender, contents, mystery.",
            keywords: ["mystery", "package", "unexpected"],
            template: makeType(
                id: "MysteryPackage", name: "Package", plural: "Mystery Packages",
                image: "shippingbox.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Received on", kind: .date, required: true),
                    FieldDef.make(name: "Sender (if any)", kind: .text),
                    FieldDef.make(name: "Contents", kind: .longText),
                    selectField("Mystery level", [
                        ("Solved quickly", "#3FB950"), ("Eventually solved", "#3FA9F5"),
                        ("Still unsolved", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Story", kind: .richText),
                ],
                primary: "contents", kanban: "mystery_level", calendar: "received_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.letter_to_future_self",
            category: .unusual,
            blurb: "Letters sealed for your future self — open date, content.",
            keywords: ["letter to future self", "time capsule"],
            template: makeType(
                id: "LetterToFutureSelf", name: "Letter", plural: "Letters to Future Self",
                image: "envelope.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Written on", kind: .date, required: true),
                    FieldDef.make(name: "Open on", kind: .date, required: true),
                    FieldDef.make(name: "Sealed in", kind: .text, description: "Envelope, .future folder, etc."),
                    FieldDef.make(name: "Letter text (sealed)", kind: .richText),
                    selectField("Status", [
                        ("Sealed", "#9D4DCC"), ("Opened", "#3FB950"),
                        ("Lost", "#D14B5C"),
                    ]),
                ],
                primary: "title", kanban: "status", calendar: "open_on"
            )
        ),

        Entry(
            id: "lib.letter_from_past_self",
            category: .unusual,
            blurb: "Letters from your past self — found, written, response.",
            keywords: ["letter from past self", "discovered"],
            template: makeType(
                id: "LetterFromPastSelf", name: "Letter", plural: "Letters from Past Self",
                image: "envelope.open.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Written on", kind: .date),
                    FieldDef.make(name: "Found on", kind: .date, required: true),
                    FieldDef.make(name: "Letter text", kind: .richText),
                    FieldDef.make(name: "My response to it now", kind: .richText),
                ],
                primary: "title", calendar: "found_on"
            )
        ),

        Entry(
            id: "lib.time_capsule",
            category: .unusual,
            blurb: "Time capsule contents — what's inside, open date.",
            keywords: ["time capsule", "buried"],
            template: makeType(
                id: "TimeCapsule", name: "Capsule", plural: "Time Capsules",
                image: "cylinder", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Capsule name", kind: .text, required: true),
                    FieldDef.make(name: "Sealed on", kind: .date, required: true),
                    FieldDef.make(name: "Open on", kind: .date, required: true),
                    FieldDef.make(name: "Stored where", kind: .text),
                    FieldDef.make(name: "Contents list", kind: .richText),
                    selectField("Status", [
                        ("Sealed", "#9D4DCC"), ("Opened", "#3FB950"),
                        ("Lost / missing", "#D14B5C"),
                    ]),
                ],
                primary: "capsule_name", kanban: "status", calendar: "open_on"
            )
        ),

        Entry(
            id: "lib.pocket_treasure",
            category: .unusual,
            blurb: "Objects carried in your pocket — where from, why kept.",
            keywords: ["pocket", "pebble", "talisman"],
            template: makeType(
                id: "PocketTreasure", name: "Treasure", plural: "Pocket Treasures",
                image: "circle.hexagonpath.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Object", kind: .text, required: true),
                    FieldDef.make(name: "Where from", kind: .text),
                    FieldDef.make(name: "Carried since", kind: .date),
                    FieldDef.make(name: "Meaning", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "object", calendar: "carried_since", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.mandela_effect",
            category: .unusual,
            blurb: "Mandela effect notes — what you remembered, vs reality.",
            keywords: ["mandela effect", "misremembered"],
            template: makeType(
                id: "MandelaEffect", name: "Memory", plural: "Mandela Effects",
                image: "memorychip", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "What I remembered", kind: .richText),
                    FieldDef.make(name: "What's actually true", kind: .richText),
                    FieldDef.make(name: "Discovered on", kind: .date),
                    selectField("How sure was I", [
                        ("Vaguely", "#3FA9F5"), ("Pretty sure", "#9D4DCC"),
                        ("Dead certain", "#D14B5C"),
                    ]),
                ],
                primary: "subject", kanban: "how_sure_was_i", calendar: "discovered_on"
            )
        ),

        Entry(
            id: "lib.misheard_lyric",
            category: .unusual,
            blurb: "Misheard lyrics — wrong version, song, your version.",
            keywords: ["mondegreen", "misheard", "lyric"],
            template: makeType(
                id: "MisheardLyric", name: "Mondegreen", plural: "Misheard Lyrics",
                image: "music.note", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Song", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Actual lyric", kind: .text),
                    FieldDef.make(name: "My version", kind: .longText),
                    FieldDef.make(name: "Date discovered", kind: .date),
                ],
                primary: "song", calendar: "date_discovered"
            )
        ),

        Entry(
            id: "lib.spoonerism",
            category: .unusual,
            blurb: "Spoonerisms observed — original, accidental form.",
            keywords: ["spoonerism", "slip of tongue"],
            template: makeType(
                id: "Spoonerism", name: "Slip", plural: "Spoonerisms",
                image: "text.bubble", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "What was meant", kind: .text, required: true),
                    FieldDef.make(name: "What came out", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Who said it", kind: .link),
                    FieldDef.make(name: "Context", kind: .longText),
                ],
                primary: "what_came_out", calendar: "date"
            )
        ),

        Entry(
            id: "lib.embarrassing_memory",
            category: .unusual,
            blurb: "Embarrassing memories — date, severity, recovery.",
            keywords: ["embarrassing", "cringe", "memory"],
            template: makeType(
                id: "EmbarrassingMemory", name: "Memory", plural: "Embarrassing Memories",
                image: "face.dashed.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "When (era / date)", kind: .text),
                    selectField("Severity", [
                        ("Mild cringe", "#E8A93B"), ("Solid cringe", "#F08C2E"),
                        ("Want to disappear", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "How I made peace", kind: .longText),
                ],
                primary: "title", kanban: "severity"
            )
        ),

        Entry(
            id: "lib.cringe_message",
            category: .unusual,
            blurb: "Cringe messages I rediscovered — old text, what I cringe at.",
            keywords: ["cringe", "old text", "embarrassing"],
            template: makeType(
                id: "CringeMessage", name: "Message", plural: "Cringe Messages",
                image: "message.badge.filled.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "What I sent", kind: .richText, required: true),
                    FieldDef.make(name: "Sent in (era)", kind: .text),
                    FieldDef.make(name: "Rediscovered on", kind: .date),
                    FieldDef.make(name: "Why it's cringe now", kind: .longText),
                    FieldDef.make(name: "Screenshot", kind: .attachment),
                ],
                primary: "what_i_sent", calendar: "rediscovered_on", gallery: "screenshot"
            )
        ),

        Entry(
            id: "lib.voicemail_saved",
            category: .unusual,
            blurb: "Voicemails you saved — sender, date, why saved.",
            keywords: ["voicemail", "saved", "voice"],
            template: makeType(
                id: "VoicemailSaved", name: "Voicemail", plural: "Saved Voicemails",
                image: "phone.fill.arrow.down.left", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "From", kind: .link, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Length (sec)", kind: .number),
                    FieldDef.make(name: "Why I saved it", kind: .longText),
                    FieldDef.make(name: "Audio file", kind: .attachment),
                ],
                primary: "from", calendar: "date"
            )
        ),

        Entry(
            id: "lib.photo_rediscovered",
            category: .unusual,
            blurb: "Photos you rediscovered — era, who's in it, where stored.",
            keywords: ["photo", "rediscovered", "old"],
            template: makeType(
                id: "PhotoRediscovered", name: "Photo", plural: "Rediscovered Photos",
                image: "photo.on.rectangle.angled", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Title / what's in it", kind: .text, required: true),
                    FieldDef.make(name: "Era / approximate date", kind: .text),
                    FieldDef.make(name: "Found on", kind: .date, required: true),
                    FieldDef.make(name: "Where it was stored", kind: .text),
                    FieldDef.make(name: "Memory it triggered", kind: .richText),
                    FieldDef.make(name: "Image", kind: .attachment),
                ],
                primary: "title_what_s_in_it", calendar: "found_on", gallery: "image"
            )
        ),

        Entry(
            id: "lib.unsent_email",
            category: .unusual,
            blurb: "Emails you wrote but never sent — draft, intended recipient.",
            keywords: ["unsent", "email", "draft", "vent"],
            template: makeType(
                id: "UnsentEmail", name: "Draft", plural: "Unsent Emails",
                image: "envelope.badge", color: "#666666",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "Intended recipient", kind: .link),
                    FieldDef.make(name: "Written on", kind: .date, required: true),
                    FieldDef.make(name: "Draft", kind: .richText),
                    FieldDef.make(name: "Why I didn't send", kind: .longText),
                ],
                primary: "subject", calendar: "written_on"
            )
        ),

        Entry(
            id: "lib.unmailed_letter",
            category: .unusual,
            blurb: "Letters you wrote but never mailed — recipient, sentiment.",
            keywords: ["unmailed letter", "draft"],
            template: makeType(
                id: "UnmailedLetter", name: "Letter", plural: "Unmailed Letters",
                image: "envelope.arrow.triangle.branch", color: "#666666",
                fields: [
                    FieldDef.make(name: "Recipient", kind: .link, required: true),
                    FieldDef.make(name: "Written on", kind: .date, required: true),
                    FieldDef.make(name: "Letter text", kind: .richText),
                    FieldDef.make(name: "Why I didn't mail it", kind: .longText),
                ],
                primary: "recipient", calendar: "written_on"
            )
        ),

        Entry(
            id: "lib.confession",
            category: .unusual,
            blurb: "Confessions — anonymous, private, dated.",
            keywords: ["confession", "secret", "private"],
            template: makeType(
                id: "Confession", name: "Confession", plural: "Confessions",
                image: "lock.doc.fill", color: "#666666",
                fields: [
                    FieldDef.make(name: "Title (general)", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Severity", [
                        ("Light", "#3FA9F5"), ("Real", "#E8A93B"),
                        ("Heavy", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Confession", kind: .richText),
                    FieldDef.make(name: "Will I ever share it?", kind: .text),
                ],
                primary: "title_general", kanban: "severity", calendar: "date"
            )
        ),

        Entry(
            id: "lib.regret",
            category: .unusual,
            blurb: "Regrets — date, decision, what I'd do.",
            keywords: ["regret", "wish", "redo"],
            template: makeType(
                id: "Regret", name: "Regret", plural: "Regrets",
                image: "arrow.uturn.backward.circle", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .text),
                    selectField("Domain", [
                        ("Career", "#3FA9F5"), ("Relationships", "#D14B5C"),
                        ("Money", "#E8A93B"), ("Health", "#3FB950"),
                        ("Words said / unsaid", "#9D4DCC"), ("Other", "#666666"),
                    ]),
                    FieldDef.make(name: "What happened", kind: .richText),
                    FieldDef.make(name: "What I'd do differently", kind: .richText),
                    FieldDef.make(name: "Have I made peace with it?", kind: .text),
                ],
                primary: "title", kanban: "domain"
            )
        ),

        Entry(
            id: "lib.compliment_given",
            category: .unusual,
            blurb: "Compliments you gave — who, when, what.",
            keywords: ["compliment", "gave", "kind word"],
            template: makeType(
                id: "ComplimentGiven", name: "Compliment", plural: "Compliments Given",
                image: "heart.text.square", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Person", kind: .link, required: true),
                    FieldDef.make(name: "Compliment", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Context", [
                        ("In person", "#3FB950"), ("Text / chat", "#3FA9F5"),
                        ("Email / letter", "#9D4DCC"), ("Public / posted", "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Their reaction", kind: .text),
                ],
                primary: "compliment", kanban: "context", calendar: "date"
            )
        ),

        Entry(
            id: "lib.apology_made",
            category: .unusual,
            blurb: "Apologies you made — recipient, when, accepted?",
            keywords: ["apology", "sorry", "amends"],
            template: makeType(
                id: "ApologyMade", name: "Apology", plural: "Apologies Made",
                image: "hand.raised.fingers.spread", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Recipient", kind: .link, required: true),
                    FieldDef.make(name: "For what", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    selectField("Response", [
                        ("Accepted", "#3FB950"), ("Cautious", "#3FA9F5"),
                        ("Still needs time", "#E8A93B"), ("Refused", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "How I delivered it", kind: .text),
                ],
                primary: "recipient", kanban: "response", calendar: "date"
            )
        ),

        Entry(
            id: "lib.stranger_kindness",
            category: .unusual,
            blurb: "Random kindness from strangers — where, what, when.",
            keywords: ["kindness", "stranger", "good deed"],
            template: makeType(
                id: "StrangerKindness", name: "Act", plural: "Stranger Kindness",
                image: "sparkles", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "What happened", kind: .text, required: true),
                    FieldDef.make(name: "When", kind: .date, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Stranger description", kind: .text),
                    FieldDef.make(name: "What it meant", kind: .richText),
                ],
                primary: "what_happened", calendar: "when"
            )
        ),

        Entry(
            id: "lib.stranger_quote",
            category: .unusual,
            blurb: "Stranger quotes that stuck — quote, where, when.",
            keywords: ["stranger", "quote", "overheard"],
            template: makeType(
                id: "StrangerQuote", name: "Quote", plural: "Stranger Quotes",
                image: "quote.bubble", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Quote", kind: .text, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "When", kind: .date),
                    FieldDef.make(name: "Stranger description", kind: .text),
                    FieldDef.make(name: "Why it stuck", kind: .longText),
                ],
                primary: "quote", calendar: "when"
            )
        ),

        Entry(
            id: "lib.penny_found",
            category: .unusual,
            blurb: "Pennies you've found — where, year on penny.",
            keywords: ["penny", "found money", "coin"],
            template: makeType(
                id: "PennyFound", name: "Penny", plural: "Pennies Found",
                image: "centsign.circle.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Found on", kind: .date, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Year on penny", kind: .number),
                    FieldDef.make(name: "Heads or tails up?", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "where", calendar: "found_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.bumper_sticker",
            category: .unusual,
            blurb: "Bumper sticker quotes worth remembering.",
            keywords: ["bumper sticker", "quote", "car"],
            template: makeType(
                id: "BumperSticker", name: "Sticker", plural: "Bumper Stickers",
                image: "car.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Quote", kind: .text, required: true),
                    FieldDef.make(name: "Spotted on", kind: .date),
                    FieldDef.make(name: "City / road", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    selectField("Vibe", [
                        ("Funny", "#3FB950"), ("Political", "#D14B5C"),
                        ("Sweet", "#9D4DCC"), ("Bizarre", "#E8A93B"),
                        ("Quote", "#3FA9F5"),
                    ]),
                ],
                primary: "quote", kanban: "vibe", calendar: "spotted_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.strange_sign",
            category: .unusual,
            blurb: "Strange signs spotted — where, photo.",
            keywords: ["sign", "strange", "weird", "engrish"],
            template: makeType(
                id: "StrangeSign", name: "Sign", plural: "Strange Signs",
                image: "signpost.right", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Sign text", kind: .text, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Date spotted", kind: .date),
                    FieldDef.make(name: "Why it's weird", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "sign_text", calendar: "date_spotted", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.found_typo",
            category: .unusual,
            blurb: "Typos found in published material — where, what, fix sent?",
            keywords: ["typo", "error", "proofread"],
            template: makeType(
                id: "FoundTypo", name: "Typo", plural: "Found Typos",
                image: "text.badge.xmark", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Where", kind: .text, required: true),
                    FieldDef.make(name: "Typo text", kind: .text),
                    FieldDef.make(name: "Date found", kind: .date),
                    FieldDef.make(name: "Sent fix to publisher?", kind: .boolean),
                    FieldDef.make(name: "Photo / screenshot", kind: .attachment),
                ],
                primary: "where", calendar: "date_found", gallery: "photo_screenshot"
            )
        ),

        Entry(
            id: "lib.funny_error",
            category: .unusual,
            blurb: "Funny error messages from apps — app, message, screenshot.",
            keywords: ["error message", "funny", "bug"],
            template: makeType(
                id: "FunnyError", name: "Error", plural: "Funny Errors",
                image: "exclamationmark.bubble.circle", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "App / system", kind: .text, required: true),
                    FieldDef.make(name: "Error text", kind: .text),
                    FieldDef.make(name: "Date encountered", kind: .date),
                    FieldDef.make(name: "What caused it", kind: .longText),
                    FieldDef.make(name: "Screenshot", kind: .attachment),
                ],
                primary: "app_system", calendar: "date_encountered", gallery: "screenshot"
            )
        ),

        Entry(
            id: "lib.imaginary_friend",
            category: .unusual,
            blurb: "Childhood imaginary friends — name, era, fate.",
            keywords: ["imaginary friend", "childhood"],
            template: makeType(
                id: "ImaginaryFriend", name: "Friend", plural: "Imaginary Friends",
                image: "person.crop.artframe", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Active years", kind: .text),
                    FieldDef.make(name: "Description", kind: .longText),
                    FieldDef.make(name: "What we did together", kind: .richText),
                    FieldDef.make(name: "How they faded out", kind: .longText),
                ],
                primary: "name"
            )
        ),

        Entry(
            id: "lib.stuffed_animal",
            category: .unusual,
            blurb: "Stuffed animals — name, era, current location.",
            keywords: ["stuffed animal", "plush", "lovey"],
            template: makeType(
                id: "StuffedAnimal", name: "Friend", plural: "Stuffed Animals",
                image: "teddybear.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Type / species", kind: .text),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Current location", kind: .text),
                    FieldDef.make(name: "Story", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", calendar: "acquired", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.childhood_obsession",
            category: .unusual,
            blurb: "Childhood obsessions — topic, age range.",
            keywords: ["obsession", "phase", "childhood"],
            template: makeType(
                id: "ChildhoodObsession", name: "Phase", plural: "Childhood Obsessions",
                image: "star.bubble.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Topic", kind: .text, required: true),
                    FieldDef.make(name: "Age started", kind: .number),
                    FieldDef.make(name: "Age ended", kind: .number),
                    FieldDef.make(name: "What I did", kind: .richText),
                    FieldDef.make(name: "How it shaped me", kind: .longText),
                ],
                primary: "topic"
            )
        ),

        Entry(
            id: "lib.recurring_dream",
            category: .unusual,
            blurb: "Recurring dream themes — frequency, what happens.",
            keywords: ["recurring dream", "theme", "dream"],
            template: makeType(
                id: "RecurringDream", name: "Theme", plural: "Recurring Dreams",
                image: "moon.zzz.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Theme", kind: .text, required: true),
                    selectField("Frequency", [
                        ("Yearly or less", "#3FA9F5"), ("Few times a year", "#9D4DCC"),
                        ("Monthly", "#E8A93B"), ("Weekly+", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "First noticed", kind: .date),
                    FieldDef.make(name: "Common elements", kind: .richText),
                    FieldDef.make(name: "What I think it means", kind: .longText),
                ],
                primary: "theme", kanban: "frequency", calendar: "first_noticed"
            )
        ),

        Entry(
            id: "lib.phobia",
            category: .unusual,
            blurb: "Phobias — trigger, severity, exposure progress.",
            keywords: ["phobia", "fear", "exposure"],
            template: makeType(
                id: "Phobia", name: "Phobia", plural: "Phobias",
                image: "exclamationmark.triangle.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Phobia name", kind: .text, required: true),
                    FieldDef.make(name: "Trigger", kind: .text),
                    selectField("Severity", [
                        ("Mild", "#3FB950"), ("Moderate", "#E8A93B"),
                        ("Severe", "#F08C2E"), ("Debilitating", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Suspected origin", kind: .longText),
                    FieldDef.make(name: "Exposure progress notes", kind: .noteLog),
                ],
                primary: "phobia_name", kanban: "severity"
            )
        ),

        Entry(
            id: "lib.quirk",
            category: .unusual,
            blurb: "Personal quirks you've noticed about yourself.",
            keywords: ["quirk", "self", "weird"],
            template: makeType(
                id: "PersonalQuirk", name: "Quirk", plural: "Quirks",
                image: "questionmark.bubble.fill", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Quirk", kind: .text, required: true),
                    FieldDef.make(name: "Noticed on", kind: .date),
                    FieldDef.make(name: "Description", kind: .richText),
                    FieldDef.make(name: "Origin theory", kind: .longText),
                ],
                primary: "quirk", calendar: "noticed_on"
            )
        ),

        Entry(
            id: "lib.verbal_tic",
            category: .unusual,
            blurb: "Verbal tics — words/phrases you overuse.",
            keywords: ["verbal tic", "filler", "overuse"],
            template: makeType(
                id: "VerbalTic", name: "Tic", plural: "Verbal Tics",
                image: "text.bubble.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Word / phrase", kind: .text, required: true),
                    FieldDef.make(name: "When I use it", kind: .text),
                    FieldDef.make(name: "First noticed", kind: .date),
                    selectField("Severity", [
                        ("Background hum", "#3FA9F5"), ("Noticeable", "#E8A93B"),
                        ("Constant", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Trying to stop?", kind: .boolean),
                ],
                primary: "word_phrase", kanban: "severity", calendar: "first_noticed"
            )
        ),

        Entry(
            id: "lib.pet_peeve",
            category: .unusual,
            blurb: "Pet peeves — trigger, intensity, root.",
            keywords: ["pet peeve", "annoyance"],
            template: makeType(
                id: "PetPeeve", name: "Peeve", plural: "Pet Peeves",
                image: "exclamationmark.bubble.circle.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Peeve", kind: .text, required: true),
                    selectField("Intensity", [
                        ("Mild", "#3FA9F5"), ("Strong", "#E8A93B"),
                        ("Fury", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Trigger context", kind: .text),
                    FieldDef.make(name: "Root / story", kind: .longText),
                ],
                primary: "peeve", kanban: "intensity"
            )
        ),

        Entry(
            id: "lib.comfort_thing",
            category: .unusual,
            blurb: "Comfort objects / rituals / foods.",
            keywords: ["comfort", "ritual", "soothe"],
            template: makeType(
                id: "ComfortThing", name: "Comfort", plural: "Comforts",
                image: "heart.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Comfort", kind: .text, required: true),
                    selectField("Type", [
                        ("Object", "#9D4DCC"), ("Food", "#E8A93B"),
                        ("Place", "#3FB950"), ("Ritual", "#3FA9F5"),
                        ("Song", "#F08C2E"), ("Smell", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Why it works", kind: .richText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "comfort", kanban: "type", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.lullaby",
            category: .unusual,
            blurb: "Lullabies that calm — song, who sang it, era.",
            keywords: ["lullaby", "calming", "nostalgic"],
            template: makeType(
                id: "Lullaby", name: "Lullaby", plural: "Lullabies",
                image: "moon.stars", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Who sang it to me", kind: .text),
                    FieldDef.make(name: "Era / age", kind: .text),
                    FieldDef.make(name: "Why it works", kind: .longText),
                ],
                primary: "title"
            )
        ),

        Entry(
            id: "lib.smell_memory",
            category: .unusual,
            blurb: "Smells that transport you to a memory.",
            keywords: ["smell", "memory", "proustian"],
            template: makeType(
                id: "SmellMemory", name: "Memory", plural: "Smell Memories",
                image: "wind", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Smell", kind: .text, required: true),
                    FieldDef.make(name: "Memory", kind: .richText),
                    FieldDef.make(name: "Era", kind: .text),
                    selectField("Emotional charge", [
                        ("Warm", "#E8A93B"), ("Bittersweet", "#9D4DCC"),
                        ("Sad", "#3FA9F5"), ("Joyful", "#3FB950"),
                    ]),
                ],
                primary: "smell", kanban: "emotional_charge"
            )
        ),

        Entry(
            id: "lib.song_that_haunts",
            category: .unusual,
            blurb: "Songs that haunt you — song, why it gets you.",
            keywords: ["song", "haunts", "earworm"],
            template: makeType(
                id: "SongThatHaunts", name: "Song", plural: "Songs That Haunt Me",
                image: "music.note.house", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Era discovered", kind: .text),
                    FieldDef.make(name: "Why it gets me", kind: .richText),
                ],
                primary: "title"
            )
        ),

        Entry(
            id: "lib.cool_cloud",
            category: .unusual,
            blurb: "Memorable clouds spotted — type, photo.",
            keywords: ["cloud", "lenticular", "mammatus", "sky"],
            template: makeType(
                id: "CoolCloud", name: "Cloud", plural: "Cool Clouds",
                image: "cloud.fill", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Date spotted", kind: .date, required: true),
                    FieldDef.make(name: "Type / name", kind: .text),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "type_name", calendar: "date_spotted", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.stick_collected",
            category: .unusual,
            blurb: "Sticks you collected — why you kept it.",
            keywords: ["stick", "branch", "walking stick"],
            template: makeType(
                id: "StickCollected", name: "Stick", plural: "Sticks",
                image: "tree.fill", color: "#7B4F2F",
                fields: [
                    FieldDef.make(name: "Nickname", kind: .text, required: true),
                    FieldDef.make(name: "Found on", kind: .date),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Length (in)", kind: .number),
                    FieldDef.make(name: "Why I kept it", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "nickname", calendar: "found_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.trash_treasure",
            category: .unusual,
            blurb: "Curb finds and dumpster treasures — what, where, condition.",
            keywords: ["curb find", "dumpster", "free", "stooping"],
            template: makeType(
                id: "TrashTreasure", name: "Find", plural: "Trash Treasures",
                image: "trash.slash.circle.fill", color: "#3FB950",
                fields: [
                    FieldDef.make(name: "Item", kind: .text, required: true),
                    FieldDef.make(name: "Found on", kind: .date, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    selectField("Condition", [
                        ("Like new", "#3FB950"), ("Good", "#3FA9F5"),
                        ("Needs work", "#E8A93B"), ("Project piece", "#F08C2E"),
                    ]),
                    FieldDef.make(name: "What I did with it", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "item", kanban: "condition", calendar: "found_on", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.bizarre_statue",
            category: .unusual,
            blurb: "Bizarre statues spotted — where, subject.",
            keywords: ["statue", "weird", "roadside"],
            template: makeType(
                id: "BizarreStatue", name: "Statue", plural: "Bizarre Statues",
                image: "figure.stand", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Subject", kind: .text, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Date spotted", kind: .date),
                    FieldDef.make(name: "Why it's bizarre", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "subject", calendar: "date_spotted", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.mural_seen",
            category: .unusual,
            blurb: "Murals seen — where, artist, theme.",
            keywords: ["mural", "street art", "wall"],
            template: makeType(
                id: "MuralSeen", name: "Mural", plural: "Murals",
                image: "paintbrush.pointed", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Title / subject", kind: .text, required: true),
                    FieldDef.make(name: "Artist", kind: .text),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Date seen", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "title_subject", calendar: "date_seen", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.graffiti_tag",
            category: .unusual,
            blurb: "Graffiti tags noticed — where, tag, photo.",
            keywords: ["graffiti", "tag", "street"],
            template: makeType(
                id: "GraffitiTag", name: "Tag", plural: "Graffiti Tags",
                image: "scribble.variable", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Tag", kind: .text, required: true),
                    FieldDef.make(name: "Where", kind: .text),
                    FieldDef.make(name: "Date spotted", kind: .date),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "tag", calendar: "date_spotted", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sunset_ranked",
            category: .unusual,
            blurb: "Memorable sunsets — date, location, color palette, rating.",
            keywords: ["sunset", "sky", "evening"],
            template: makeType(
                id: "SunsetRanked", name: "Sunset", plural: "Sunsets",
                image: "sunset.fill", color: "#F08C2E",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Color palette", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "location", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.sunrise_ranked",
            category: .unusual,
            blurb: "Memorable sunrises — date, location, palette, rating.",
            keywords: ["sunrise", "dawn", "morning"],
            template: makeType(
                id: "SunriseRanked", name: "Sunrise", plural: "Sunrises",
                image: "sunrise.fill", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(name: "Color palette", kind: .text),
                    FieldDef.make(name: "Rating", kind: .rating),
                    FieldDef.make(name: "Who I watched it with", kind: .link),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "location", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.party_story",
            category: .unusual,
            blurb: "Stories I tell at parties — inventory of go-to anecdotes.",
            keywords: ["story", "anecdote", "party", "go-to"],
            template: makeType(
                id: "PartyStory", name: "Story", plural: "Party Stories",
                image: "text.book.closed", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "One-liner setup", kind: .text),
                    FieldDef.make(name: "Story body", kind: .richText),
                    selectField("Length", [
                        ("Quick (< 1 min)", "#3FB950"), ("Short (1–3 min)", "#3FA9F5"),
                        ("Medium (3–10 min)", "#E8A93B"), ("Long (10+ min)", "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Best audience", kind: .text),
                    FieldDef.make(name: "Times told", kind: .number),
                ],
                primary: "title", kanban: "length"
            )
        ),

        Entry(
            id: "lib.memorable_phrase",
            category: .unusual,
            blurb: "Phrases worth remembering — without attribution.",
            keywords: ["phrase", "saying", "memorable"],
            template: makeType(
                id: "MemorablePhrase", name: "Phrase", plural: "Memorable Phrases",
                image: "quote.opening", color: "#3FA9F5",
                fields: [
                    FieldDef.make(name: "Phrase", kind: .text, required: true),
                    FieldDef.make(name: "When / where I heard it", kind: .text),
                    FieldDef.make(name: "Date saved", kind: .date),
                    FieldDef.make(name: "Why I like it", kind: .longText),
                ],
                primary: "phrase", calendar: "date_saved"
            )
        ),

    ]
}
