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

    /// The chosen **base** for the primary archive — normally a drive/volume root
    /// (e.g. "/Volumes/Vortex4TB"). The actual archive lives in `archiveSubfolder` *under*
    /// this base, so picking a drive root doesn't litter it: originals land at
    /// `<base>/<archiveSubfolder>/originals` and the JPEG set at `<base>/<archiveSubfolder>/jpeg`.
    public var primaryDestination: String

    /// Additional on-disk copy bases kept in lockstep with the primary (rsync, no --delete).
    /// The same `archiveSubfolder` is nested under each. At least one mirror is required
    /// before any purge is permitted.
    public var mirrorDestinations: [String]

    /// Mounted Cryptomator vault directory for the encrypted offsite copy, or nil to skip.
    /// The vault is **exempt** from `archiveSubfolder` — the archive is written at the vault
    /// root (a Cryptomator vault is already a dedicated container).
    public var cloudVaultPath: String?

    /// Folder nested under each physical destination *base* (primary + mirrors) to hold the
    /// archive, so a drive root stays tidy and other content on the drive isn't intermixed.
    /// Default "Photos Archive". Empty string opts out (archive written at the base itself).
    /// Does NOT apply to the Cryptomator vault.
    public var archiveSubfolder: String

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

    /// When pulling missing originals (`downloadMissingFromICloud`), use osxphotos'
    /// **PhotoKit** download path (`--use-photokit`) instead of the default AppleScript one.
    /// PhotoKit requests originals from iCloud directly; the AppleScript path drives Photos
    /// and, on a slow/indeterminate iCloud asset, **times out and kills Photos** in a retry
    /// loop that can wedge both Photos and the export. On by default — only meaningful when
    /// `downloadMissingFromICloud` is true. (Incident 2026-06-10: the AppleScript path hung
    /// on 44 `incloud=None` stragglers, repeatedly terminating Photos; PhotoKit is the fix.)
    public var usePhotoKitForDownload: Bool

    /// Exclude **"Shared with You" (syndicated)** and **shared-album** items from the export
    /// (osxphotos `--not-syndicated --not-shared`). These are not your own originals — they're
    /// references to content others shared (via Messages or a shared album), so they have **no
    /// downloadable master** and otherwise show up forever as bogus "missing" originals, sending
    /// you chasing a ghost. On by default. Does NOT exclude your own iCloud **Shared Library**
    /// photos (those are `--shared-library`, which you do own). (Incident 2026-06-11: the last
    /// 3 "missing stragglers" were all shared/syndicated — a texted pasta photo, a shared video.)
    public var excludeSharedAndSyndicated: Bool

    /// The keep/purge rule.
    public var retention: RetentionPolicy

    /// Master delete switch. **Defaults to false and must be turned on deliberately.** Even
    /// when true, every purge run still previews (dry-run) and is gated on the verify check.
    public var purgeEnabled: Bool

    /// On each **incremental** run, also copy the newly-added items into a dated batch under
    /// `reviewFolderPath` ("NEW PHOTOS TO REVIEW") so they can be handed off or deleted after
    /// review. On by default. Never runs on the baseline population (everything is "new" then).
    public var reviewNewItems: Bool

    /// Where the "NEW PHOTOS TO REVIEW" batches go. nil → `defaultReviewRoot()`
    /// (`~/Downloads/PurpleAttic/NEW PHOTOS TO REVIEW`).
    public var reviewFolderPath: String?

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
        usePhotoKitForDownload: Bool = true,
        excludeSharedAndSyndicated: Bool = true,
        retention: RetentionPolicy = RetentionPolicy(),
        purgeEnabled: Bool = false,
        archiveSubfolder: String = "Photos Archive",
        reviewNewItems: Bool = true,
        reviewFolderPath: String? = nil
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
        self.usePhotoKitForDownload = usePhotoKitForDownload
        self.excludeSharedAndSyndicated = excludeSharedAndSyndicated
        self.retention = retention
        self.purgeEnabled = purgeEnabled
        self.archiveSubfolder = archiveSubfolder
        self.reviewNewItems = reviewNewItems
        self.reviewFolderPath = reviewFolderPath
    }

    /// Resilient decoding: every key is `decodeIfPresent` with the same default as the
    /// memberwise init, so adding a field never breaks an older `profile.json` (the lesson
    /// baked into `AppSettings`). In particular a pre-0.6 profile with no `archiveSubfolder`
    /// decodes to the "Photos Archive" default rather than throwing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Main Photo Archive"
        photosLibraryPath = try c.decodeIfPresent(String.self, forKey: .photosLibraryPath)
        primaryDestination = try c.decodeIfPresent(String.self, forKey: .primaryDestination) ?? ""
        mirrorDestinations = try c.decodeIfPresent([String].self, forKey: .mirrorDestinations) ?? []
        cloudVaultPath = try c.decodeIfPresent(String.self, forKey: .cloudVaultPath)
        keepHEIC = try c.decodeIfPresent(Bool.self, forKey: .keepHEIC) ?? true
        keepJPEG = try c.decodeIfPresent(Bool.self, forKey: .keepJPEG) ?? true
        directoryTemplate = try c.decodeIfPresent(String.self, forKey: .directoryTemplate)
            ?? "{created.year}/{created.year}-{created.mm}"
        downloadMissingFromICloud = try c.decodeIfPresent(Bool.self, forKey: .downloadMissingFromICloud) ?? false
        usePhotoKitForDownload = try c.decodeIfPresent(Bool.self, forKey: .usePhotoKitForDownload) ?? true
        excludeSharedAndSyndicated = try c.decodeIfPresent(Bool.self, forKey: .excludeSharedAndSyndicated) ?? true
        retention = try c.decodeIfPresent(RetentionPolicy.self, forKey: .retention) ?? RetentionPolicy()
        purgeEnabled = try c.decodeIfPresent(Bool.self, forKey: .purgeEnabled) ?? false
        archiveSubfolder = try c.decodeIfPresent(String.self, forKey: .archiveSubfolder) ?? "Photos Archive"
        reviewNewItems = try c.decodeIfPresent(Bool.self, forKey: .reviewNewItems) ?? true
        reviewFolderPath = try c.decodeIfPresent(String.self, forKey: .reviewFolderPath)
    }

    /// Default location for "NEW PHOTOS TO REVIEW" batches (PhantomLives output convention).
    public static func defaultReviewRoot() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/PurpleAttic/NEW PHOTOS TO REVIEW").path
    }

    /// The effective review root (explicit path, or the default).
    public var effectiveReviewRoot: String {
        let p = (reviewFolderPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? Self.defaultReviewRoot() : p
    }

    // MARK: - Derived paths

    /// Compose the archive root for a physical destination *base* by nesting `archiveSubfolder`.
    /// An empty/whitespace subfolder yields the base unchanged (opt-out / pre-0.6 behavior).
    public func archiveRoot(forBase base: String) -> String {
        let sub = archiveSubfolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sub.isEmpty else { return base }
        return (base as NSString).appendingPathComponent(sub)
    }

    /// The primary archive root (primary base + archive subfolder).
    public var primaryArchiveRoot: String { archiveRoot(forBase: primaryDestination) }

    /// Each mirror's archive root (mirror base + archive subfolder).
    public var mirrorArchiveRoots: [String] { mirrorDestinations.map { archiveRoot(forBase: $0) } }

    /// Subdirectory under an archive root for a given export pass.
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
        let primary = primaryDestination.trimmingCharacters(in: .whitespaces)
        if primary.isEmpty {
            issues.append("Primary destination is not set.")
        } else if primary.contains("CHANGE_ME") {
            issues.append("Primary destination is still the placeholder — set it to your archive drive in Settings.")
        } else {
            // The archive subfolder is created on demand, but the chosen base (the
            // drive/volume) must already exist. Catches "/Volumes/NotMounted" before
            // osxphotos sees a bad path.
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: primary, isDirectory: &isDir) || !isDir.boolValue {
                issues.append("Primary destination isn’t available (is the drive mounted?): \(primary)")
            }
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
