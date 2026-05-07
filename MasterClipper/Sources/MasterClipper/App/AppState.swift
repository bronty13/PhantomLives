import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var personas: [Persona] = []
    @Published var sites: [Site] = []
    @Published var categories: [Category] = []
    @Published var calendarRules: [CalendarRule] = []
    @Published var exclusionReasons: [ExclusionReason] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedSection: Section = .dashboard
    /// Set by the dashboard / search to pre-select a specific clip when the
    /// user navigates to the Clips section. The list view reads + clears this.
    @Published var focusedClipId: String? = nil
    /// Set by the dashboard's stat cards to pre-apply a posting-completeness
    /// filter (Fully posted / Partial / Not posted / No scope). The Clips
    /// list reads + clears this on appear.
    @Published var pendingPostingFilter: PostingFilter? = nil

    enum Section: String, Hashable, CaseIterable {
        case dashboard, editingQueue, postingQueue, clips, calendar, postingBatch, reports, c4sHistorical, importView

        var title: String {
            switch self {
            case .dashboard:     return "Dashboard"
            case .editingQueue:  return "Editing Queue"
            case .postingQueue:  return "Posting Queue"
            case .clips:         return "Clips"
            case .calendar:      return "Calendar"
            case .postingBatch:  return "Posting Batch"
            case .reports:       return "Reports"
            case .c4sHistorical: return "C4S Historical"
            case .importView:    return "Import"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard:     return "rectangle.3.group.fill"
            case .editingQueue:  return "wand.and.stars"
            case .postingQueue:  return "tray.full"
            case .clips:         return "film.stack.fill"
            case .calendar:      return "calendar"
            case .postingBatch:  return "paperplane.fill"
            case .reports:       return "chart.bar.doc.horizontal"
            case .c4sHistorical: return "chart.line.uptrend.xyaxis"
            case .importView:    return "square.and.arrow.down"
            }
        }
    }

    let settingsStore = SettingsStore()

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue; settingsStore.save() }
    }

    var currentTheme: Theme {
        Theme.named(settings.themeName)
    }

    var effectiveAccentColor: Color {
        Color(hex: settings.accentColorHex) ?? currentTheme.accentColor
    }

    /// Maps the saved color-scheme preference to a SwiftUI `ColorScheme?`.
    /// `nil` means "follow system".
    var preferredColorScheme: ColorScheme? {
        switch settings.colorScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// Persona color (falling back to a deterministic per-code default if the
    /// configured hex doesn't parse). Used widely by views that "light up" rows
    /// for visual identity.
    func color(forPersona code: String) -> Color {
        if let p = persona(forCode: code), let c = Color(hex: p.colorHex) {
            return c
        }
        return .accentColor
    }

    var effectiveFont: Font {
        if settings.fontName.isEmpty {
            return .system(size: settings.fontSize)
        }
        return .custom(settings.fontName, size: settings.fontSize)
    }

    init() {
        // Auto-upgrade legacy refine prompts to the current default. We only
        // touch the value if it exactly matches a known shipped default, so a
        // user who customized the template never has their work overwritten.
        if AppSettings.legacyRefinePromptDefaults.contains(settingsStore.settings.refinePromptTemplate) {
            var s = settingsStore.settings
            s.refinePromptTemplate = AppSettings.defaultRefinePromptTemplate
            settingsStore.settings = s
            settingsStore.save()
        }

        // Same auto-upgrade idea for the production-folder pattern. Final
        // layout is `<base>/<contentDate> <Title>/<Title>.<ext>` — folder
        // includes the title for human scannability, file inside is just
        // `<Title>.<ext>`. Default pattern therefore = `{date} {title}`.
        // Anyone still on a known-legacy default gets bumped so the pill,
        // the wand button, and the backfill all produce the same shape.
        if AppSettings.legacyProductionPatternDefaults.contains(settingsStore.settings.defaultProductionPattern) {
            var s = settingsStore.settings
            s.defaultProductionPattern = "{date} {title}"
            settingsStore.settings = s
            settingsStore.save()
        }

        reloadAll()

        // One-time backfill: any production clips without production_folder /
        // fcp_project_folder get them populated from the configured defaults.
        // Marker prevents re-running on every launch; the user can also force
        // it from Settings → File Locations.
        if !settingsStore.settings.pathBackfillV1Done {
            _ = PathDefaultsService.backfill(appState: self)
            var s = settingsStore.settings
            s.pathBackfillV1Done = true
            settingsStore.settings = s
            settingsStore.save()
        }

        BackupService.runIfEnabled(settingsStore: settingsStore)
        Task { @MainActor in
            await OllamaSetup.shared.run(settings: settings)
            await OllamaService.shared.checkConnection(settings: settings)
            // If the configured model isn't installed but something else is, switch.
            if let fallback = OllamaService.shared.suggestedFallbackModel(currentModel: settings.ollamaModel) {
                var s = settings
                s.ollamaModel = fallback
                settings = s
            }
        }
    }

    func reloadAll() {
        isLoading = true
        do {
            clips            = try DatabaseService.shared.fetchAllClips()
            personas         = try DatabaseService.shared.fetchPersonas()
            sites            = try DatabaseService.shared.fetchSites()
            categories       = try DatabaseService.shared.fetchCategories()
            calendarRules    = try DatabaseService.shared.fetchRules()
            exclusionReasons = try DatabaseService.shared.fetchExclusionReasons()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func reloadClips() {
        do {
            clips = try DatabaseService.shared.fetchAllClips()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadPersonas() {
        do {
            personas = try DatabaseService.shared.fetchPersonas()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadSites() {
        do {
            sites = try DatabaseService.shared.fetchSites()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadCategories() {
        do {
            categories = try DatabaseService.shared.fetchCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadCalendarRules() {
        do {
            calendarRules = try DatabaseService.shared.fetchRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadExclusionReasons() {
        do {
            exclusionReasons = try DatabaseService.shared.fetchExclusionReasons()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persona(forCode code: String) -> Persona? {
        personas.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    func site(forCode code: String) -> Site? {
        sites.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    // MARK: - Clip mutations

    /// Create a new clip with a fresh `YYYYMMDD####` id keyed off `contentDate`
    /// (or today if nil). Returns the persisted clip.
    func createClip(
        personaCode: String,
        title: String = "",
        contentDate: Date? = nil
    ) throws -> Clip {
        let id = try IDGeneratorService.next(forContentDate: contentDate)
        let now = DatabaseService.isoNow()
        let dateStr = contentDate.map { DatabaseService.isoDate($0) }

        let clip = Clip(
            id: id,
            externalClipId: nil,
            trackingTag: nil,
            personaCode: personaCode,
            title: title,
            descriptionRaw: "",
            descriptionRefined: "",
            keywords: "",
            performers: "",
            clipFilename: nil,
            thumbnailFilename: nil,
            previewFilename: nil,
            lengthSeconds: nil,
            priceCents: nil,
            salesCount: 0,
            incomeCents: 0,
            contentDate: dateStr,
            goLiveDate: nil,
            status: ClipStatus.production.rawValue,
            archived: false,
            notes: "",
            transcript: "",
            mp4Md5: "", mp4Sha1: "", mp4Sha256: "", mp4SizeBytes: nil,
            reducedMd5: "", reducedSha1: "", reducedSha256: "", reducedSizeBytes: nil,
            hashesComputedAt: "",
            postingExcluded: false,
            exclusionReason: "",
            exclusionNotes: "",
            createdAt: now,
            updatedAt: now
        )
        try DatabaseService.shared.insertClip(clip)
        reloadClips()
        return clip
    }

    func updateClip(_ clip: Clip) throws {
        try DatabaseService.shared.updateClip(clip)
        reloadClips()
    }

    func deleteClip(id: String) throws {
        try DatabaseService.shared.deleteClip(id: id)
        reloadClips()
    }

    // MARK: - Settings table mutations (CRUD on personas / sites / categories)

    func savePersona(_ p: Persona) throws {
        var mutable = p
        try DatabaseService.shared.savePersona(&mutable)
        reloadPersonas()
    }

    func deletePersona(id: Int64) throws {
        try DatabaseService.shared.deletePersona(id: id)
        reloadPersonas()
    }

    func saveSite(_ s: Site) throws {
        var mutable = s
        try DatabaseService.shared.saveSite(&mutable)
        reloadSites()
    }

    func deleteSite(id: Int64) throws {
        try DatabaseService.shared.deleteSite(id: id)
        reloadSites()
    }

    func saveCategory(_ c: Category) throws {
        var mutable = c
        try DatabaseService.shared.saveCategory(&mutable)
        reloadCategories()
    }

    func deleteCategory(id: Int64) throws {
        try DatabaseService.shared.deleteCategory(id: id)
        reloadCategories()
    }
}
