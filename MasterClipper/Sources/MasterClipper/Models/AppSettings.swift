import Foundation

struct AppSettings: Codable {
    // Appearance
    var themeName: String = "Default"
    var fontName: String = ""
    var fontSize: Double = 13
    var accentColorHex: String = "#7A4FFF"
    var colorScheme: String = "auto"           // "auto" | "light" | "dark"

    // Defaults
    var operatorName: String = "Me"
    var defaultPersonaCode: String = "CoC"

    // Backup
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""
    var backupRetentionDays: Int = 30
    var lastBackupAt: String = ""

    // Exports
    var defaultExportDirectory: String = ""

    // Ollama
    var ollamaEnabled: Bool = true
    var ollamaModel: String = "dolphin-mistral"
    var ollamaBaseURL: String = "http://localhost:11434"
    var ollamaAutoStart: Bool = true
    var refinePromptTemplate: String = AppSettings.defaultRefinePromptTemplate

    /// Strict word-for-word proofreading prompt. The LLM must echo every word
    /// of the input back unless there is a concrete spelling, punctuation, or
    /// grammar error. Few-shot examples train the model to leave already-clean
    /// text untouched and to make only the specific fix needed (no rewriting,
    /// no synonym swaps, no clause reordering).
    static let defaultRefinePromptTemplate: String = """
    You are a STRICT proofreader. Your only job is to copy the creator's
    description back word-for-word with three classes of fixes:

      1. Spelling errors (misspelled words → correct spelling)
      2. Punctuation errors (missing commas / periods, runaway capitals,
         missing question marks, extra spaces)
      3. Grammar errors that are objectively wrong (subject-verb agreement,
         tense slips, broken plurals)

    Hard rules — violating any of these is a failure:

    - Echo the input word-for-word. Every word the creator wrote must appear
      in your output unless that exact word is misspelled.
    - DO NOT swap any synonyms. "big" → "large" is forbidden. "house" →
      "home" is forbidden. The creator's word choices stay.
    - DO NOT rephrase sentences. If the creator wrote "I'm gonna show you
      something", you output "I'm gonna show you something" — not "I will
      show you something".
    - DO NOT reorder clauses or sentences.
    - DO NOT add information that wasn't there.
    - DO NOT remove information that was there.
    - DO NOT add commentary, headings, lists, or markdown.
    - DO NOT wrap your output in quotes.
    - Preserve all informal/explicit language verbatim — slang, kink terms,
      body parts, brand names, profanity, the creator's deliberate
      phrasing.
    - Preserve line breaks and paragraph breaks exactly.
    - If a sentence is already perfect, output it unchanged.

    Examples of correct behavior:

    INPUT:
    i love rubbing my hands on my hairy pussy. getting it all wet and slippery and creamy
    OUTPUT:
    I love rubbing my hands on my hairy pussy, getting it all wet and slippery and creamy.

    INPUT:
    Watch me pull my dark purple panties to teh side and get them all white and creamy just for you.
    OUTPUT:
    Watch me pull my dark purple panties to the side and get them all white and creamy just for you.

    INPUT:
    I love showing off how turned on I am.
    OUTPUT:
    I love showing off how turned on I am.

    INPUT:
    have you ever watched apart in a movie and just whish you could be there
    OUTPUT:
    Have you ever watched a part in a movie and just wish you could be there?

    INPUT:
    she put it on the table and walks away
    OUTPUT:
    She put it on the table and walked away.

    Now proofread the description below using the same rules. Output ONLY the
    proofread description — no preamble, no markdown, no explanation, no
    quotes. If the input is already clean, output it unchanged.

    INPUT:
    {{description}}
    OUTPUT:
    """

    /// Earlier defaults that get auto-migrated to the current one on launch.
    /// Any user who never edited the template is silently upgraded; users
    /// who customized the prompt are left alone.
    static let legacyRefinePromptDefaults: [String] = [
        // v1 — original aggressive "rewrite for clarity" prompt
        """
        You are an editor for a video clip storefront description.
        Rewrite the description below for clarity, fix spelling/grammar,
        keep the original voice, and remove any words banned by major
        clip platforms. Preserve specifics (length, costume, kink details) verbatim.
        Return ONLY the revised description text — no preamble, no markdown.

        Description:
        {{description}}
        """,
        // v2 — "minimal changes" copy edit (still let some rewriting through)
        """
        You are a copy editor cleaning up a creator's video description before it
        is pasted into a storefront listing for consumers to see.

        Make MINIMAL changes — preserve the creator's voice, phrasing, sentence
        structure, and word choice as much as possible. The result should read
        like the creator wrote it themselves.

        Rules:
        - Fix spelling mistakes.
        - Fix capitalization (proper nouns, sentence starts, the pronoun "I",
          brand and platform names).
        - Fix obvious typos and missing or extra punctuation / spacing.
        - Preserve every specific detail verbatim — length, costume, outfit,
          names, kink terms, body parts, slang, any explicit vocabulary.
        - Do NOT rewrite, paraphrase, "improve", or simplify any sentence.
        - Do NOT change vocabulary, swap synonyms, or restructure clauses.
        - Do NOT add or remove information.
        - Do NOT change the order of sentences.
        - Keep line breaks and paragraph structure intact.
        - If the input is already clean, return it unchanged.

        Return ONLY the cleaned description — no preamble, no notes, no markdown,
        no explanation, no quotes around the output.

        Description:
        {{description}}
        """,
    ]

    // Posting
    var postingBatchAutoAdvance: Bool = true

    // Import
    var importDuplicateStrategy: String = "skip"
    var importDateLocale: String = "en_US_POSIX"

    // Calendar
    var calendarFirstWeekday: Int = 1
    var calendarDefaultView: String = "month"

    // Search
    var includeNotesInGlobalSearch: Bool = true

    var debugLogging: Bool = false
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("MasterClipper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        settings = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var resolvedBackupPath: URL {
        if settings.backupPath.isEmpty {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return downloads.appendingPathComponent("MasterClipper backup", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.backupPath)
    }

    var resolvedExportDirectory: URL {
        if settings.defaultExportDirectory.isEmpty {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return downloads.appendingPathComponent("MasterClipper", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.defaultExportDirectory)
    }
}
