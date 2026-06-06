import SwiftUI
import PurpleMarkRenderCore

/// A user-created theme.
struct CustomTheme: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colors: ThemeColors

    init(id: UUID = UUID(), name: String, colors: ThemeColors) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}

/// Owns the four built-in themes plus the user's custom themes, persists the
/// custom ones, and resolves a selection id (stored in `AppSettings.themeRaw`)
/// to `ThemeColors`. A selection id is either a built-in `RenderTheme` raw value
/// ("default"/"nord"/…) or `"custom:<uuid>"`.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var customThemes: [CustomTheme] = []

    private var storeURL: URL {
        BackupService.supportDirectory.appendingPathComponent("themes.json")
    }

    init() { load() }

    // MARK: Options for pickers

    struct Option: Identifiable, Hashable {
        let id: String       // selection id
        let name: String
        let isCustom: Bool
    }

    var builtinOptions: [Option] {
        RenderTheme.allCases.map { Option(id: $0.rawValue, name: $0.displayName, isCustom: false) }
    }
    var customOptions: [Option] {
        customThemes.map { Option(id: "custom:\($0.id.uuidString)", name: $0.name, isCustom: true) }
    }
    var allOptions: [Option] { builtinOptions + customOptions }

    // MARK: Resolve

    static func customID(_ id: UUID) -> String { "custom:\(id.uuidString)" }

    func customTheme(forID id: String) -> CustomTheme? {
        guard id.hasPrefix("custom:"),
              let uuid = UUID(uuidString: String(id.dropFirst("custom:".count))) else { return nil }
        return customThemes.first { $0.id == uuid }
    }

    func colors(forID id: String) -> ThemeColors {
        if let custom = customTheme(forID: id) { return custom.colors }
        if let builtin = RenderTheme(rawValue: id) { return .builtin(builtin) }
        return .builtin(.default)
    }

    func name(forID id: String) -> String {
        allOptions.first { $0.id == id }?.name ?? "Default"
    }

    // MARK: CRUD

    /// Creates a new custom theme seeded from `colors`, returns its selection id.
    @discardableResult
    func addCustom(name: String, colors: ThemeColors) -> String {
        let theme = CustomTheme(name: name, colors: colors)
        customThemes.append(theme)
        save()
        return ThemeStore.customID(theme.id)
    }

    func updateCustom(_ id: UUID, name: String? = nil, colors: ThemeColors? = nil) {
        guard let index = customThemes.firstIndex(where: { $0.id == id }) else { return }
        if let name { customThemes[index].name = name }
        if let colors { customThemes[index].colors = colors }
        save()
    }

    func deleteCustom(_ id: UUID) {
        customThemes.removeAll { $0.id == id }
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([CustomTheme].self, from: data) else { return }
        customThemes = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: BackupService.supportDirectory,
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(customThemes)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("PurpleMark: failed to save custom themes — \(error.localizedDescription)")
        }
    }
}
