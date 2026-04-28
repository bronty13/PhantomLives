import Foundation

/// A saved search/replace criteria set. Funduc calls these "Favorites".
struct Favorite: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var pattern: String
    var replacement: String
    var isRegex: Bool
    var caseInsensitive: Bool
    var wholeWord: Bool
    var multiline: Bool
    var includeGlobs: String
    var excludeGlobs: String
    var honorGitignore: Bool
    var rootPaths: [String]
}

enum FavoriteStore {

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacSearchReplace/Favorites", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func list() -> [Favorite] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Favorite.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func save(_ fav: Favorite) throws {
        let url = folder.appendingPathComponent("\(fav.name).json")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(fav).write(to: url, options: .atomic)
    }

    static func delete(_ fav: Favorite) {
        try? FileManager.default.removeItem(
            at: folder.appendingPathComponent("\(fav.name).json")
        )
    }
}
