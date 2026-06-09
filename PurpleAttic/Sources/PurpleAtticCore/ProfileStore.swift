import Foundation

/// Loads and saves `ArchiveProfile`s as JSON. The CLI and the future GUI share the same
/// on-disk format and default location so a profile authored in one is usable in the other.
public enum ProfileStore {

    /// Default config directory: ~/Library/Application Support/PurpleAttic/.
    public static func defaultDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/PurpleAttic", isDirectory: true)
    }

    /// Default single-profile path used when `--profile` is omitted.
    public static func defaultProfileURL() -> URL {
        defaultDirectory().appendingPathComponent("profile.json")
    }

    public static func load(from url: URL) throws -> ArchiveProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ArchiveProfile.self, from: data)
    }

    @discardableResult
    public static func save(_ profile: ArchiveProfile, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: url)
        return url
    }

    /// A starter profile pointed at the System Photo Library with placeholder destinations,
    /// purge OFF. Written by `pattic init`.
    public static func sample() -> ArchiveProfile {
        ArchiveProfile(
            name: "Main Photo Archive",
            photosLibraryPath: nil,
            primaryDestination: "/Volumes/CHANGE_ME/PhotoArchive",
            mirrorDestinations: ["/Volumes/CHANGE_ME_MIRROR/PhotoArchive"],
            cloudVaultPath: nil,
            keepHEIC: true,
            keepJPEG: true,
            downloadMissingFromICloud: false,
            retention: RetentionPolicy(),
            purgeEnabled: false
        )
    }
}
