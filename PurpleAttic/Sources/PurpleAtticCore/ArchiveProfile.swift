import Foundation

/// A self-contained description of one archive job: which Photos library to read, where
/// the plain-file copies go, which formats to keep, and the retention rule. Profiles are
/// the reuse mechanism — the maintainer's second Mac (different iCloud account) is just a
/// second profile with `purgeEnabled = false`, so the same engine serves both with no
/// special-casing. Codable so it round-trips to a JSON file the CLI and GUI share.
public struct ArchiveProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Display name, e.g. "Vortex — main library".
    public var name: String

    /// Path to a specific `.photoslibrary`, or nil to use the System Photo Library.
    public var photosLibraryPath: String?

    /// Root of the primary archive (e.g. "/Volumes/Vortex4TB/PhotoArchive"). osxphotos
    /// writes originals under `<primary>/originals` and the JPEG set under `<primary>/jpeg`.
    public var primaryDestination: String

    /// Additional on-disk copies kept in lockstep with the primary (rsync, no --delete).
    /// At least one mirror is required before any purge is permitted.
    public var mirrorDestinations: [String]

    /// Mounted Cryptomator vault directory for the encrypted offsite copy, or nil to skip.
    public var cloudVaultPath: String?

    /// Export the untouched originals (HEIC/RAW/etc.). The fidelity copy.
    public var keepHEIC: Bool
    /// Also export a universally-openable JPEG derivative set (osxphotos --convert-to-jpeg).
    public var keepJPEG: Bool

    /// osxphotos `--directory` template controlling the dated folder tree.
    public var directoryTemplate: String

    /// Ask osxphotos to pull missing originals from iCloud during export. Leave false on a
    /// machine set to "Download Originals" (Vortex) where everything is already local;
    /// set true only on an Optimize-Storage host.
    public var downloadMissingFromICloud: Bool

    /// The keep/purge rule.
    public var retention: RetentionPolicy

    /// Master delete switch. **Defaults to false and must be turned on deliberately.** Even
    /// when true, every purge run still previews (dry-run) and is gated on the verify check.
    public var purgeEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Main Photo Archive",
        photosLibraryPath: String? = nil,
        primaryDestination: String = "",
        mirrorDestinations: [String] = [],
        cloudVaultPath: String? = nil,
        keepHEIC: Bool = true,
        keepJPEG: Bool = true,
        directoryTemplate: String = "{created.year}/{created.year}-{created.mm}",
        downloadMissingFromICloud: Bool = false,
        retention: RetentionPolicy = RetentionPolicy(),
        purgeEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.photosLibraryPath = photosLibraryPath
        self.primaryDestination = primaryDestination
        self.mirrorDestinations = mirrorDestinations
        self.cloudVaultPath = cloudVaultPath
        self.keepHEIC = keepHEIC
        self.keepJPEG = keepJPEG
        self.directoryTemplate = directoryTemplate
        self.downloadMissingFromICloud = downloadMissingFromICloud
        self.retention = retention
        self.purgeEnabled = purgeEnabled
    }

    // MARK: - Derived paths

    /// Subdirectory under the primary archive for a given export pass.
    public func subdirectory(for pass: ExportPass) -> String {
        switch pass {
        case .originals: return "originals"
        case .jpeg: return "jpeg"
        }
    }

    /// Which export passes this profile runs, in order.
    public var enabledPasses: [ExportPass] {
        var passes: [ExportPass] = []
        if keepHEIC { passes.append(.originals) }
        if keepJPEG { passes.append(.jpeg) }
        return passes
    }

    // MARK: - Validation

    /// Non-fatal configuration problems to surface before a run. Empty means good to go for
    /// archival (purge has additional, stricter gates checked at purge time).
    public func validationIssues() -> [String] {
        var issues: [String] = []
        if primaryDestination.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Primary destination is not set.")
        }
        if !keepHEIC && !keepJPEG {
            issues.append("No export format selected — enable HEIC originals and/or JPEG.")
        }
        if directoryTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Directory template is empty.")
        }
        if purgeEnabled && mirrorDestinations.isEmpty {
            issues.append("Purge is enabled but no mirror is configured — a second on-disk copy is required before deletion.")
        }
        return issues
    }
}

/// The two osxphotos export passes PurpleAttic runs to keep both formats.
public enum ExportPass: String, Sendable, CaseIterable {
    case originals
    case jpeg

    public var label: String {
        switch self {
        case .originals: return "HEIC originals"
        case .jpeg: return "JPEG derivatives"
        }
    }
}
