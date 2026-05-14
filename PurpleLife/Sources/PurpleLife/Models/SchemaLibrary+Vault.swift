import Foundation

/// Vault library entries — sexual health, intimate, and kink schemas
/// users may want behind a Touch ID / device-password gate. Importing
/// goes through the same `materialize()` path as every other library
/// entry; the only difference is `category == .vault` triggers
/// `ObjectType.isVault = true` on the resulting type, which keeps it
/// out of the regular sidebar / search / Today / library gallery
/// unless the user has unveiled the Vault for the current session
/// (`AppState.vaultRevealed`, gated by `VaultAuthService`).
///
/// 20 entries grouped as:
///   - Sexual health (6): Cycle · Intimate Health Visit · STI Test ·
///     Contraception · Libido & Desire · Intimate Symptoms
///   - Encounter / relational (4): Encounter Journal · Partner Profile ·
///     Date Night · Aftercare Notes
///   - Kink (6): Kink Inventory · Scene Log · Toy & Gear ·
///     Hard Limits · Safewords · Scene Plan
///   - Body & intimate (4): Body Diary · Fantasy Journal ·
///     Intimacy Goal · Boundaries & Negotiation
extension SchemaLibrary {

    static let vaultEntries: [Entry] = [

        // MARK: Sexual health

        Entry(
            id: "lib.vault.cycle",
            category: .vault,
            blurb: "Daily menstrual / hormonal cycle log with flow, symptoms, and mood.",
            keywords: ["cycle", "period", "menstrual", "menses", "flow", "PMS", "hormone"],
            template: makeType(
                id: "VaultCycle", name: "Cycle entry", plural: "Cycle entries",
                image: "moon.stars", color: "#B65BAB",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Day of cycle", kind: .number, description: "Day 1 = first day of flow."),
                    selectField("Flow", [
                        ("None", "#888888"), ("Spotting", "#D2A4C5"),
                        ("Light", "#C25A99"), ("Medium", "#9D4DCC"),
                        ("Heavy", "#6B3B7E"),
                    ]),
                    FieldDef.make(
                        name: "Symptoms", kind: .multiSelect,
                        options: [
                            FieldOption.make("Cramps",            colorHex: "#D14B5C"),
                            FieldOption.make("Headache",          colorHex: "#E8A93B"),
                            FieldOption.make("Breast tenderness", colorHex: "#C25A99"),
                            FieldOption.make("Bloating",          colorHex: "#9D4DCC"),
                            FieldOption.make("Mood shift",        colorHex: "#B65BAB"),
                            FieldOption.make("Acne",              colorHex: "#6B3B7E"),
                            FieldOption.make("Back pain",         colorHex: "#7C3F66"),
                            FieldOption.make("Nausea",            colorHex: "#888888"),
                            FieldOption.make("Fatigue",           colorHex: "#5A2D5C"),
                        ]
                    ),
                    FieldDef.make(name: "Mood", kind: .rating),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", kanban: "flow", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.intimate_health_visit",
            category: .vault,
            blurb: "Visits to gynecologist, urologist, sexual-health clinic, or family planning.",
            keywords: ["doctor", "gynecologist", "urologist", "ob-gyn", "clinic", "appointment", "health"],
            template: makeType(
                id: "VaultIntimateHealthVisit", name: "Intimate health visit", plural: "Intimate health visits",
                image: "stethoscope", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true,
                                  description: "e.g. \"Annual checkup — Dr. Smith\""),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Provider", kind: .text),
                    selectField("Visit type", [
                        ("Annual checkup",        "#3FB950"),
                        ("STI screen",            "#3FA9F5"),
                        ("Contraception consult", "#9D4DCC"),
                        ("Symptom follow-up",     "#E8A93B"),
                        ("Procedure",             "#D14B5C"),
                        ("Other",                 "#888888"),
                    ]),
                    FieldDef.make(
                        name: "Tests ordered", kind: .multiSelect,
                        options: [
                            FieldOption.make("HIV",            colorHex: "#D14B5C"),
                            FieldOption.make("Syphilis",       colorHex: "#E8A93B"),
                            FieldOption.make("Gonorrhea",      colorHex: "#3FA9F5"),
                            FieldOption.make("Chlamydia",      colorHex: "#9D4DCC"),
                            FieldOption.make("HPV",            colorHex: "#B65BAB"),
                            FieldOption.make("Herpes",         colorHex: "#7C3F66"),
                            FieldOption.make("Trichomoniasis", colorHex: "#C25A99"),
                            FieldOption.make("Hepatitis B",    colorHex: "#6B3B7E"),
                            FieldOption.make("Hepatitis C",    colorHex: "#5A2D5C"),
                            FieldOption.make("Pap smear",      colorHex: "#3FB950"),
                            FieldOption.make("Pelvic exam",    colorHex: "#A24E8B"),
                            FieldOption.make("Blood work",     colorHex: "#888888"),
                        ]
                    ),
                    FieldDef.make(name: "Outcome", kind: .richText),
                    FieldDef.make(name: "Next visit", kind: .date),
                ],
                primary: "title", kanban: "visit_type", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.sti_test",
            category: .vault,
            blurb: "Per-test record of STI screens — panel, result, site, follow-up.",
            keywords: ["sti", "std", "test", "screen", "hiv", "syphilis", "chlamydia", "gonorrhea"],
            template: makeType(
                id: "VaultSTITest", name: "STI test", plural: "STI tests",
                image: "cross.case", color: "#8E3A8C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true,
                                  description: "e.g. \"Quarterly screen — March\""),
                    FieldDef.make(name: "Test date", kind: .date, required: true),
                    FieldDef.make(
                        name: "Panel", kind: .multiSelect,
                        options: [
                            FieldOption.make("HIV",            colorHex: "#D14B5C"),
                            FieldOption.make("Syphilis",       colorHex: "#E8A93B"),
                            FieldOption.make("Gonorrhea",      colorHex: "#3FA9F5"),
                            FieldOption.make("Chlamydia",      colorHex: "#9D4DCC"),
                            FieldOption.make("HPV",            colorHex: "#B65BAB"),
                            FieldOption.make("HSV-1",          colorHex: "#7C3F66"),
                            FieldOption.make("HSV-2",          colorHex: "#5A2D5C"),
                            FieldOption.make("Hepatitis B",    colorHex: "#A24E8B"),
                            FieldOption.make("Hepatitis C",    colorHex: "#6B3B7E"),
                            FieldOption.make("Trichomoniasis", colorHex: "#C25A99"),
                        ]
                    ),
                    selectField("Result", [
                        ("Pending",      "#888888"),
                        ("Negative",     "#3FB950"),
                        ("Positive",     "#D14B5C"),
                        ("Inconclusive", "#E8A93B"),
                        ("Treated",      "#9D4DCC"),
                    ]),
                    selectField("Site", [
                        ("Clinic",          "#3FA9F5"),
                        ("Doctor's office", "#9D4DCC"),
                        ("Mail-in kit",     "#E8A93B"),
                        ("At-home rapid",   "#B65BAB"),
                        ("Hospital",        "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Provider or lab", kind: .text),
                    FieldDef.make(name: "Follow-up notes", kind: .longText),
                ],
                primary: "title", kanban: "result", calendar: "test_date"
            )
        ),

        Entry(
            id: "lib.vault.contraception",
            category: .vault,
            blurb: "Daily contraception log — method, adherence, side effects.",
            keywords: ["contraception", "birth control", "pill", "iud", "condom", "patch", "ring"],
            template: makeType(
                id: "VaultContraception", name: "Contraception entry", plural: "Contraception log",
                image: "pill", color: "#C25A99",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    selectField("Method", [
                        ("Pill",         "#9D4DCC"),
                        ("IUD",          "#B65BAB"),
                        ("Implant",      "#6B3B7E"),
                        ("Patch",        "#A24E8B"),
                        ("Ring",         "#C25A99"),
                        ("Condom",       "#3FA9F5"),
                        ("Diaphragm",    "#7C3F66"),
                        ("Injection",    "#E8A93B"),
                        ("Withdrawal",   "#888888"),
                        ("Fertility tracking", "#3FB950"),
                        ("None",         "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Taken / used as planned", kind: .boolean),
                    FieldDef.make(name: "Time of day", kind: .text,
                                  description: "Optional — e.g. \"8:00 AM\". Useful for pill consistency."),
                    FieldDef.make(name: "Missed-dose / fallback notes", kind: .longText),
                    FieldDef.make(
                        name: "Side effects", kind: .multiSelect,
                        options: [
                            FieldOption.make("Nausea",       colorHex: "#888888"),
                            FieldOption.make("Headache",     colorHex: "#E8A93B"),
                            FieldOption.make("Mood change",  colorHex: "#B65BAB"),
                            FieldOption.make("Spotting",     colorHex: "#C25A99"),
                            FieldOption.make("Libido shift", colorHex: "#9D4DCC"),
                            FieldOption.make("Weight change",colorHex: "#6B3B7E"),
                            FieldOption.make("Skin change",  colorHex: "#7C3F66"),
                            FieldOption.make("None",         colorHex: "#3FB950"),
                        ]
                    ),
                ],
                primary: "date", kanban: "method", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.libido",
            category: .vault,
            blurb: "Daily libido, desire, mood, and energy ratings with cycle correlation.",
            keywords: ["libido", "desire", "arousal", "mood", "energy", "hormone"],
            template: makeType(
                id: "VaultLibido", name: "Libido entry", plural: "Libido & desire",
                image: "flame", color: "#A24E8B",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Libido", kind: .rating),
                    FieldDef.make(name: "Desire (partnered)", kind: .rating),
                    FieldDef.make(name: "Desire (solo)", kind: .rating),
                    FieldDef.make(name: "Mood", kind: .rating),
                    FieldDef.make(name: "Energy", kind: .rating),
                    FieldDef.make(
                        name: "Influences", kind: .multiSelect,
                        options: [
                            FieldOption.make("Stress",       colorHex: "#D14B5C"),
                            FieldOption.make("Sleep",        colorHex: "#3FA9F5"),
                            FieldOption.make("Cycle phase",  colorHex: "#B65BAB"),
                            FieldOption.make("New medication", colorHex: "#E8A93B"),
                            FieldOption.make("Travel",       colorHex: "#9D4DCC"),
                            FieldOption.make("Connection",   colorHex: "#3FB950"),
                            FieldOption.make("Argument",     colorHex: "#7C3F66"),
                            FieldOption.make("Alcohol",      colorHex: "#6B3B7E"),
                        ]
                    ),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "date", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.intimate_symptoms",
            category: .vault,
            blurb: "Track pelvic, urinary, or genital symptoms with triggers and resolutions.",
            keywords: ["symptoms", "pelvic", "uti", "yeast", "infection", "discomfort", "pain"],
            template: makeType(
                id: "VaultIntimateSymptoms", name: "Intimate symptom", plural: "Intimate symptoms",
                image: "waveform.path.ecg", color: "#7C3F66",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true,
                                  description: "Short label — e.g. \"UTI flare\" or \"Pelvic pain\""),
                    FieldDef.make(name: "Onset", kind: .dateTime, required: true),
                    selectField("Severity", [
                        ("Mild",     "#3FB950"),
                        ("Moderate", "#E8A93B"),
                        ("Severe",   "#D14B5C"),
                    ]),
                    selectField("Status", [
                        ("Active",      "#D14B5C"),
                        ("Improving",   "#E8A93B"),
                        ("Resolved",    "#3FB950"),
                        ("Recurring",   "#9D4DCC"),
                    ]),
                    FieldDef.make(
                        name: "Symptom type", kind: .multiSelect,
                        options: [
                            FieldOption.make("Pain",       colorHex: "#D14B5C"),
                            FieldOption.make("Itching",    colorHex: "#E8A93B"),
                            FieldOption.make("Burning",    colorHex: "#F08C2E"),
                            FieldOption.make("Discharge",  colorHex: "#9D4DCC"),
                            FieldOption.make("Bleeding",   colorHex: "#C25A99"),
                            FieldOption.make("Odor",       colorHex: "#7C3F66"),
                            FieldOption.make("Urinary",    colorHex: "#3FA9F5"),
                            FieldOption.make("Swelling",   colorHex: "#B65BAB"),
                        ]
                    ),
                    FieldDef.make(name: "Suspected trigger", kind: .text),
                    FieldDef.make(name: "Action taken", kind: .longText),
                    FieldDef.make(name: "Resolved", kind: .date),
                ],
                primary: "title", kanban: "status", calendar: "onset"
            )
        ),

        // MARK: Encounter / relational

        Entry(
            id: "lib.vault.encounter",
            category: .vault,
            blurb: "Journal sexual encounters — partner, mood, safer-sex practices, reflections.",
            keywords: ["encounter", "sex", "journal", "intimacy", "log"],
            template: makeType(
                id: "VaultEncounter", name: "Encounter", plural: "Encounter journal",
                image: "heart.text.square", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true,
                                  description: "A short, memorable label."),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Partner", kind: .link,
                                  description: "Link to a Person or Partner Profile."),
                    FieldDef.make(name: "Location", kind: .text),
                    FieldDef.make(
                        name: "Activities", kind: .multiSelect,
                        options: [
                            FieldOption.make("Cuddling",   colorHex: "#3FB950"),
                            FieldOption.make("Kissing",    colorHex: "#C25A99"),
                            FieldOption.make("Oral",       colorHex: "#9D4DCC"),
                            FieldOption.make("Manual",     colorHex: "#B65BAB"),
                            FieldOption.make("Penetrative",colorHex: "#7C3F66"),
                            FieldOption.make("Mutual",     colorHex: "#A24E8B"),
                            FieldOption.make("Toys",       colorHex: "#6B3B7E"),
                            FieldOption.make("Roleplay",   colorHex: "#E8A93B"),
                        ]
                    ),
                    FieldDef.make(
                        name: "Safer-sex practices", kind: .multiSelect,
                        options: [
                            FieldOption.make("Condom",        colorHex: "#3FA9F5"),
                            FieldOption.make("Dental dam",    colorHex: "#9D4DCC"),
                            FieldOption.make("Internal condom", colorHex: "#B65BAB"),
                            FieldOption.make("PrEP",          colorHex: "#3FB950"),
                            FieldOption.make("Recent tests",  colorHex: "#E8A93B"),
                            FieldOption.make("Fluid-bonded",  colorHex: "#7C3F66"),
                            FieldOption.make("None",          colorHex: "#D14B5C"),
                        ]
                    ),
                    FieldDef.make(name: "Enjoyment", kind: .rating),
                    FieldDef.make(name: "Reflections", kind: .richText),
                ],
                primary: "title", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.partner_profile",
            category: .vault,
            blurb: "Partner card — pronouns, kinks, hard limits, communication notes.",
            keywords: ["partner", "lover", "profile", "boundaries", "preferences", "polyamory"],
            template: makeType(
                id: "VaultPartnerProfile", name: "Partner profile", plural: "Partner profiles",
                image: "person.crop.circle.badge.questionmark", color: "#B65BAB",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    FieldDef.make(name: "Pronouns", kind: .text),
                    selectField("Relationship", [
                        ("Primary",     "#9D4DCC"),
                        ("Secondary",   "#B65BAB"),
                        ("Casual",      "#C25A99"),
                        ("Play partner","#7C3F66"),
                        ("Past",        "#888888"),
                        ("Crush",       "#E8A93B"),
                    ]),
                    FieldDef.make(name: "Met on", kind: .date),
                    FieldDef.make(name: "Anniversary", kind: .date),
                    FieldDef.make(name: "Communication style", kind: .longText),
                    FieldDef.make(name: "Loves / yes-list", kind: .longText),
                    FieldDef.make(name: "Hard limits", kind: .longText),
                    FieldDef.make(name: "Aftercare preferences", kind: .longText),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "name", kanban: "relationship"
            )
        ),

        Entry(
            id: "lib.vault.date_night",
            category: .vault,
            blurb: "Plan and remember date nights — activity, vibe, post-date reflection.",
            keywords: ["date", "night", "romance", "plan", "intimacy"],
            template: makeType(
                id: "VaultDateNight", name: "Date night", plural: "Date nights",
                image: "wineglass", color: "#C25A99",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Partner", kind: .link),
                    FieldDef.make(name: "Activity", kind: .text),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Vibe", [
                        ("Romantic",   "#C25A99"),
                        ("Adventurous","#E8A93B"),
                        ("Cozy",       "#9D4DCC"),
                        ("Sexy",       "#7C3F66"),
                        ("Playful",    "#3FB950"),
                        ("Quiet",      "#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Reflection", kind: .richText),
                ],
                primary: "title", kanban: "vibe", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.aftercare",
            category: .vault,
            blurb: "Capture what aftercare worked — for yourself and for your partner.",
            keywords: ["aftercare", "recovery", "scene", "drop", "comfort"],
            template: makeType(
                id: "VaultAftercare", name: "Aftercare note", plural: "Aftercare notes",
                image: "heart.circle", color: "#6B3B7E",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Partner", kind: .link),
                    FieldDef.make(name: "What helped me", kind: .longText),
                    FieldDef.make(name: "What helped them", kind: .longText),
                    FieldDef.make(name: "What didn't land", kind: .longText),
                    FieldDef.make(
                        name: "Tools used", kind: .multiSelect,
                        options: [
                            FieldOption.make("Cuddling",     colorHex: "#C25A99"),
                            FieldOption.make("Blanket",      colorHex: "#9D4DCC"),
                            FieldOption.make("Snack / drink",colorHex: "#E8A93B"),
                            FieldOption.make("Quiet talk",   colorHex: "#3FA9F5"),
                            FieldOption.make("Shower / bath",colorHex: "#B65BAB"),
                            FieldOption.make("Solo time",    colorHex: "#888888"),
                            FieldOption.make("Music",        colorHex: "#3FB950"),
                            FieldOption.make("Check-in later",colorHex: "#7C3F66"),
                        ]
                    ),
                    FieldDef.make(name: "Drop intensity", kind: .rating,
                                  description: "How rough the post-scene drop felt, 0–5."),
                    FieldDef.make(name: "Next-time notes", kind: .richText),
                ],
                primary: "title", calendar: "date"
            )
        ),

        // MARK: Kink

        Entry(
            id: "lib.vault.kink_inventory",
            category: .vault,
            blurb: "Personal kink list — interest level, experience, and giving / receiving preferences.",
            keywords: ["kink", "fetish", "yes", "no", "maybe", "list", "inventory"],
            template: makeType(
                id: "VaultKink", name: "Kink", plural: "Kink inventory",
                image: "checkmark.seal", color: "#7C3F66",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Category", [
                        ("Sensation",   "#C25A99"),
                        ("Restraint",   "#9D4DCC"),
                        ("Role / power","#B65BAB"),
                        ("Impact",      "#D14B5C"),
                        ("Voyeurism",   "#3FA9F5"),
                        ("Exhibition",  "#E8A93B"),
                        ("Edge play",   "#7C3F66"),
                        ("Service",     "#3FB950"),
                        ("Other",       "#888888"),
                    ]),
                    selectField("Interest", [
                        ("Hard no",   "#D14B5C"),
                        ("Soft no",   "#E8A93B"),
                        ("Curious",   "#9D4DCC"),
                        ("Like",      "#B65BAB"),
                        ("Love",      "#3FB950"),
                    ]),
                    selectField("Experience", [
                        ("None",      "#888888"),
                        ("Researched","#3FA9F5"),
                        ("Tried once","#E8A93B"),
                        ("Occasional","#9D4DCC"),
                        ("Regular",   "#3FB950"),
                    ]),
                    FieldDef.make(
                        name: "Role", kind: .multiSelect,
                        options: [
                            FieldOption.make("Giving",   colorHex: "#9D4DCC"),
                            FieldOption.make("Receiving",colorHex: "#B65BAB"),
                            FieldOption.make("Switch",   colorHex: "#C25A99"),
                            FieldOption.make("Observer", colorHex: "#3FA9F5"),
                        ]
                    ),
                    FieldDef.make(name: "Notes", kind: .richText),
                ],
                primary: "name", kanban: "interest"
            )
        ),

        Entry(
            id: "lib.vault.scene_log",
            category: .vault,
            blurb: "Per-scene log — participants, role, intensity, debrief, aftercare.",
            keywords: ["scene", "play", "session", "log", "kink", "bdsm"],
            template: makeType(
                id: "VaultSceneLog", name: "Scene", plural: "Scene log",
                image: "theatermasks", color: "#5A2D5C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "Location", kind: .text),
                    selectField("Role", [
                        ("Top",     "#9D4DCC"),
                        ("Bottom",  "#B65BAB"),
                        ("Switch",  "#C25A99"),
                        ("Observer","#3FA9F5"),
                    ]),
                    FieldDef.make(name: "Participants", kind: .longText,
                                  description: "Free-text list — link individual Partner Profiles in the notes if helpful."),
                    FieldDef.make(name: "Gear used", kind: .longText),
                    FieldDef.make(name: "Intensity", kind: .rating),
                    FieldDef.make(name: "Safewords called", kind: .text),
                    FieldDef.make(name: "Aftercare given", kind: .longText),
                    FieldDef.make(name: "Aftercare received", kind: .longText),
                    FieldDef.make(name: "Debrief", kind: .richText),
                ],
                primary: "title", kanban: "role", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.toy_inventory",
            category: .vault,
            blurb: "Inventory of toys, gear, and equipment — material, status, care.",
            keywords: ["toy", "gear", "equipment", "inventory", "kink"],
            template: makeType(
                id: "VaultToyInventory", name: "Toy / gear", plural: "Toy & gear inventory",
                image: "shippingbox", color: "#A24E8B",
                fields: [
                    FieldDef.make(name: "Name", kind: .text, required: true),
                    selectField("Type", [
                        ("Vibrator",     "#9D4DCC"),
                        ("Dildo",        "#B65BAB"),
                        ("Plug",         "#7C3F66"),
                        ("Restraint",    "#6B3B7E"),
                        ("Impact",       "#D14B5C"),
                        ("Rope",         "#E8A93B"),
                        ("Lingerie",     "#C25A99"),
                        ("Costume",      "#A24E8B"),
                        ("Cleaning supply","#3FA9F5"),
                        ("Other",        "#888888"),
                    ]),
                    FieldDef.make(name: "Material", kind: .text,
                                  description: "Silicone, glass, leather, etc. Important for cleaning compatibility."),
                    selectField("Status", [
                        ("Clean",          "#3FB950"),
                        ("Needs cleaning", "#E8A93B"),
                        ("Needs batteries","#3FA9F5"),
                        ("Needs repair",   "#D14B5C"),
                        ("Retired",        "#888888"),
                    ]),
                    FieldDef.make(name: "Acquired", kind: .date),
                    FieldDef.make(name: "Last used", kind: .date),
                    FieldDef.make(name: "Care instructions", kind: .longText),
                    FieldDef.make(name: "Photo", kind: .attachment),
                ],
                primary: "name", kanban: "status", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.vault.hard_limits",
            category: .vault,
            blurb: "Personal hard limits — what you won't do, with context for why.",
            keywords: ["hard limit", "no", "boundaries", "kink", "negotiation"],
            template: makeType(
                id: "VaultHardLimits", name: "Hard limit", plural: "Hard limits",
                image: "hand.raised.fill", color: "#D14B5C",
                fields: [
                    FieldDef.make(name: "Limit", kind: .text, required: true),
                    selectField("Category", [
                        ("Physical",  "#D14B5C"),
                        ("Emotional", "#B65BAB"),
                        ("Verbal",    "#9D4DCC"),
                        ("Roleplay",  "#7C3F66"),
                        ("Health",    "#3FA9F5"),
                        ("Privacy",   "#6B3B7E"),
                        ("Other",     "#888888"),
                    ]),
                    selectField("Firmness", [
                        ("Hard no",   "#D14B5C"),
                        ("Soft no",   "#E8A93B"),
                        ("Conditional","#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Conditions / exceptions", kind: .longText),
                    FieldDef.make(name: "Why this matters", kind: .longText),
                    FieldDef.make(name: "Last reviewed", kind: .date),
                ],
                primary: "limit", kanban: "firmness"
            )
        ),

        Entry(
            id: "lib.vault.safewords",
            category: .vault,
            blurb: "Safewords and non-verbal signals — what they mean and with whom.",
            keywords: ["safeword", "signal", "stop", "yellow", "red", "negotiation"],
            template: makeType(
                id: "VaultSafewords", name: "Safeword", plural: "Safewords & signals",
                image: "exclamationmark.shield", color: "#E8A93B",
                fields: [
                    FieldDef.make(name: "Word or signal", kind: .text, required: true),
                    selectField("Color / level", [
                        ("Green",  "#3FB950"),
                        ("Yellow", "#E8A93B"),
                        ("Red",    "#D14B5C"),
                        ("Custom", "#9D4DCC"),
                    ]),
                    FieldDef.make(name: "Meaning", kind: .longText, required: true),
                    selectField("Channel", [
                        ("Verbal",        "#3FA9F5"),
                        ("Hand signal",   "#9D4DCC"),
                        ("Drop object",   "#E8A93B"),
                        ("Squeeze",       "#B65BAB"),
                        ("Tap out",       "#C25A99"),
                        ("Other",         "#888888"),
                    ]),
                    FieldDef.make(name: "Used with", kind: .link),
                    FieldDef.make(name: "Notes", kind: .longText),
                ],
                primary: "word_or_signal", kanban: "color_level"
            )
        ),

        Entry(
            id: "lib.vault.scene_plan",
            category: .vault,
            blurb: "Plan an upcoming scene — gear list, negotiation, safety check, aftercare.",
            keywords: ["scene", "plan", "negotiation", "session", "preparation"],
            template: makeType(
                id: "VaultScenePlan", name: "Scene plan", plural: "Scene plans",
                image: "list.bullet.rectangle.portrait", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    selectField("Status", [
                        ("Drafting",   "#888888"),
                        ("Negotiated", "#3FA9F5"),
                        ("Confirmed",  "#9D4DCC"),
                        ("Done",       "#3FB950"),
                        ("Cancelled",  "#D14B5C"),
                    ]),
                    FieldDef.make(name: "Participants", kind: .longText),
                    FieldDef.make(name: "Goals / intent", kind: .richText),
                    FieldDef.make(name: "Gear needed", kind: .longText),
                    FieldDef.make(name: "Safety check", kind: .longText,
                                  description: "Allergies, medications, recent injuries, mental-state notes."),
                    FieldDef.make(name: "Safewords agreed", kind: .text),
                    FieldDef.make(name: "Hard limits reviewed", kind: .boolean),
                    FieldDef.make(name: "Aftercare plan", kind: .longText),
                ],
                primary: "title", kanban: "status", calendar: "date"
            )
        ),

        // MARK: Body & intimate

        Entry(
            id: "lib.vault.body_diary",
            category: .vault,
            blurb: "Private body journal — photos, measurements, self-image notes.",
            keywords: ["body", "diary", "photo", "self-image", "measurement"],
            template: makeType(
                id: "VaultBodyDiary", name: "Body entry", plural: "Body diary",
                image: "figure.stand", color: "#B65BAB",
                fields: [
                    FieldDef.make(name: "Date", kind: .date, required: true),
                    FieldDef.make(name: "Photo", kind: .attachment),
                    FieldDef.make(name: "Body image", kind: .rating,
                                  description: "How you feel in your body today, 0–5."),
                    FieldDef.make(name: "Energy", kind: .rating),
                    FieldDef.make(name: "Observations", kind: .richText),
                    FieldDef.make(
                        name: "Tags", kind: .multiSelect,
                        options: [
                            FieldOption.make("Strong",   colorHex: "#3FB950"),
                            FieldOption.make("Tired",    colorHex: "#888888"),
                            FieldOption.make("Pretty",   colorHex: "#C25A99"),
                            FieldOption.make("Sore",     colorHex: "#E8A93B"),
                            FieldOption.make("Confident",colorHex: "#9D4DCC"),
                            FieldOption.make("Dysphoric",colorHex: "#7C3F66"),
                            FieldOption.make("Hungry",   colorHex: "#F08C2E"),
                            FieldOption.make("Sated",    colorHex: "#3FA9F5"),
                        ]
                    ),
                ],
                primary: "date", calendar: "date", gallery: "photo"
            )
        ),

        Entry(
            id: "lib.vault.fantasy_journal",
            category: .vault,
            blurb: "Capture fantasies, daydreams, and want-to-try ideas with a flag.",
            keywords: ["fantasy", "daydream", "journal", "idea", "want", "wishlist"],
            template: makeType(
                id: "VaultFantasy", name: "Fantasy", plural: "Fantasy journal",
                image: "sparkles.tv", color: "#8E3A8C",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .date),
                    FieldDef.make(name: "Body", kind: .richText),
                    FieldDef.make(name: "Want to try", kind: .boolean),
                    selectField("Status", [
                        ("Idea only",  "#888888"),
                        ("Curious",    "#9D4DCC"),
                        ("Negotiated", "#3FA9F5"),
                        ("Tried",      "#3FB950"),
                        ("Retired",    "#D14B5C"),
                    ]),
                    FieldDef.make(
                        name: "Themes", kind: .multiSelect,
                        options: [
                            FieldOption.make("Romance",  colorHex: "#C25A99"),
                            FieldOption.make("Power",    colorHex: "#9D4DCC"),
                            FieldOption.make("Voyeurism",colorHex: "#3FA9F5"),
                            FieldOption.make("Praise",   colorHex: "#3FB950"),
                            FieldOption.make("Restraint",colorHex: "#7C3F66"),
                            FieldOption.make("Adventure",colorHex: "#E8A93B"),
                            FieldOption.make("Tender",   colorHex: "#B65BAB"),
                        ]
                    ),
                    FieldDef.make(name: "Notes", kind: .noteLog),
                ],
                primary: "title", kanban: "status", calendar: "date"
            )
        ),

        Entry(
            id: "lib.vault.intimacy_goal",
            category: .vault,
            blurb: "Goals around communication, exploration, and intimate health.",
            keywords: ["goal", "intimacy", "communication", "exploration"],
            template: makeType(
                id: "VaultIntimacyGoal", name: "Intimacy goal", plural: "Intimacy goals",
                image: "target", color: "#9D4DCC",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    selectField("Area", [
                        ("Communication",  "#3FA9F5"),
                        ("Exploration",    "#9D4DCC"),
                        ("Health",         "#3FB950"),
                        ("Boundaries",     "#D14B5C"),
                        ("Self-knowledge", "#B65BAB"),
                        ("Connection",     "#C25A99"),
                    ]),
                    selectField("Status", [
                        ("Idea",     "#888888"),
                        ("Active",   "#3FA9F5"),
                        ("Paused",   "#E8A93B"),
                        ("Achieved", "#3FB950"),
                        ("Released", "#888888"),
                    ]),
                    FieldDef.make(name: "Target date", kind: .date),
                    FieldDef.make(name: "Why this matters", kind: .longText),
                    FieldDef.make(name: "First step", kind: .longText),
                    FieldDef.make(name: "Progress notes", kind: .noteLog),
                ],
                primary: "title", kanban: "status", calendar: "target_date"
            )
        ),

        Entry(
            id: "lib.vault.boundaries",
            category: .vault,
            blurb: "Negotiation notes — what was discussed, what was agreed, with whom.",
            keywords: ["boundaries", "negotiation", "consent", "agreement", "partner"],
            template: makeType(
                id: "VaultBoundaries", name: "Negotiation", plural: "Boundaries & negotiation",
                image: "doc.text.below.ecg", color: "#6B3B7E",
                fields: [
                    FieldDef.make(name: "Title", kind: .text, required: true),
                    FieldDef.make(name: "Date", kind: .dateTime, required: true),
                    FieldDef.make(name: "With", kind: .link),
                    selectField("Type", [
                        ("Scene-specific","#9D4DCC"),
                        ("Ongoing",       "#B65BAB"),
                        ("Relationship",  "#C25A99"),
                        ("One-off",       "#E8A93B"),
                    ]),
                    FieldDef.make(name: "What we agreed", kind: .richText),
                    FieldDef.make(name: "What is off-limits", kind: .longText),
                    FieldDef.make(name: "Safer-sex agreements", kind: .longText),
                    FieldDef.make(name: "Re-check on", kind: .date,
                                  description: "Set a date to revisit this conversation."),
                    FieldDef.make(name: "Updates", kind: .noteLog),
                ],
                primary: "title", kanban: "type", calendar: "date"
            )
        ),
    ]
}
