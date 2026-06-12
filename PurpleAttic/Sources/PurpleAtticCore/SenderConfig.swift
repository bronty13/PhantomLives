import Foundation

/// Configuration for **sender mode** — a one-way "capture this Mac's Photos and ship them to a
/// remote PurpleAttic host" agent, for a *second* Mac (a different iCloud account) whose photos
/// you want preserved centrally. It is deliberately a **separate type from `ArchiveProfile`** so
/// the sender can never touch the core archive/mirror/verify/cloud/**purge** machinery: a sender
/// only ever *reads* Photos and *writes* to a local staging area + a remote folder. It never
/// deletes from Photos and has no purge surface at all.
///
/// Designed for a **small-disk source Mac** (e.g. a 256 GB drive that's always full): the export
/// lands on an **external SSD** (`stagingRoot`), keeping the internal disk untouched, and is then
/// rsync'd over SSH to the remote (`remote`). The staging SSD doubles as a complete local copy.
public struct SenderConfig: Codable, Sendable, Equatable {
    /// Human label for logs/reports (e.g. "Sallie-MacBook").
    public var name: String

    /// Photos library to read. nil → the system library (the normal case).
    public var photosLibraryPath: String?

    /// Staging archive base — an **external SSD** with room for the full export. The archive is
    /// nested under `archiveSubfolder` here, exactly like `ArchiveProfile.primaryDestination`.
    public var stagingRoot: String

    /// Subfolder under the staging base / remote path holding the archive (keeps multiple
    /// senders' archives separate on the receiver, e.g. "Photos Archive - Sallie").
    public var archiveSubfolder: String

    /// Dated folder template (same engine as the core archive).
    public var directoryTemplate: String

    public var keepHEIC: Bool
    public var keepJPEG: Bool

    /// Pull originals from iCloud when the source Mac is on *Optimize Mac Storage*. If the
    /// library lives on the SSD set to "Download Originals" (recommended for a full-disk Mac),
    /// leave this **off** — every original is already local and no iCloud fetch is needed.
    public var downloadMissingFromICloud: Bool
    public var usePhotoKitForDownload: Bool
    public var excludeSharedAndSyndicated: Bool

    /// Where the staged archive is shipped after each export.
    public var remote: Remote

    /// Push transport target on the receiver (Vortex).
    public struct Remote: Codable, Sendable, Equatable {
        /// Send to the remote after exporting. When false the agent only exports to the SSD
        /// (useful for a first offline full pass, or to verify staging before wiring the link).
        public var enabled: Bool
        public var host: String          // hostname / IP / Tailscale name of the receiver
        public var user: String          // ssh login on the receiver
        public var port: Int             // ssh port (22)
        public var identityFile: String? // ssh private key path; nil → ssh default keys
        /// Destination folder ON the receiver. The staging archive root is rsync'd *into* here
        /// (so the receiver ends with `<remotePath>/<archiveSubfolder>/originals`, …).
        public var remotePath: String

        public init(enabled: Bool = false, host: String = "", user: String = "",
                    port: Int = 22, identityFile: String? = nil, remotePath: String = "") {
            self.enabled = enabled; self.host = host; self.user = user
            self.port = port; self.identityFile = identityFile; self.remotePath = remotePath
        }
    }

    public init(
        name: String = "Photo Sender",
        photosLibraryPath: String? = nil,
        stagingRoot: String = "",
        archiveSubfolder: String = "Photos Archive",
        directoryTemplate: String = "{created.year}/{created.year}-{created.mm}",
        keepHEIC: Bool = true,
        keepJPEG: Bool = true,
        downloadMissingFromICloud: Bool = false,
        usePhotoKitForDownload: Bool = true,
        excludeSharedAndSyndicated: Bool = true,
        remote: Remote = Remote()
    ) {
        self.name = name
        self.photosLibraryPath = photosLibraryPath
        self.stagingRoot = stagingRoot
        self.archiveSubfolder = archiveSubfolder
        self.directoryTemplate = directoryTemplate
        self.keepHEIC = keepHEIC
        self.keepJPEG = keepJPEG
        self.downloadMissingFromICloud = downloadMissingFromICloud
        self.usePhotoKitForDownload = usePhotoKitForDownload
        self.excludeSharedAndSyndicated = excludeSharedAndSyndicated
        self.remote = remote
    }

    /// Resilient decoding (same convention as `ArchiveProfile`): every key `decodeIfPresent`
    /// with the memberwise default, so adding a field never breaks an older `sender.json`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Photo Sender"
        photosLibraryPath = try c.decodeIfPresent(String.self, forKey: .photosLibraryPath)
        stagingRoot = try c.decodeIfPresent(String.self, forKey: .stagingRoot) ?? ""
        archiveSubfolder = try c.decodeIfPresent(String.self, forKey: .archiveSubfolder) ?? "Photos Archive"
        directoryTemplate = try c.decodeIfPresent(String.self, forKey: .directoryTemplate)
            ?? "{created.year}/{created.year}-{created.mm}"
        keepHEIC = try c.decodeIfPresent(Bool.self, forKey: .keepHEIC) ?? true
        keepJPEG = try c.decodeIfPresent(Bool.self, forKey: .keepJPEG) ?? true
        downloadMissingFromICloud = try c.decodeIfPresent(Bool.self, forKey: .downloadMissingFromICloud) ?? false
        usePhotoKitForDownload = try c.decodeIfPresent(Bool.self, forKey: .usePhotoKitForDownload) ?? true
        excludeSharedAndSyndicated = try c.decodeIfPresent(Bool.self, forKey: .excludeSharedAndSyndicated) ?? true
        remote = try c.decodeIfPresent(Remote.self, forKey: .remote) ?? Remote()
    }

    // MARK: - Derived

    /// The staging archive root (SSD base + subfolder), where osxphotos writes.
    public var stagingArchiveRoot: String {
        let sub = archiveSubfolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sub.isEmpty else { return stagingRoot }
        return (stagingRoot as NSString).appendingPathComponent(sub)
    }

    /// Map to an **export-only** `ArchiveProfile`: SSD as primary, **no mirror, no vault, purge
    /// OFF, review OFF**. Feeding this to `ExportEngine.run` runs *only* the osxphotos export
    /// (it skips mirror when `mirrorDestinations` is empty and cloud when `cloudVaultPath` is
    /// nil) — so the sender reuses the exact, tested export path with zero core changes.
    public func exportProfile() -> ArchiveProfile {
        ArchiveProfile(
            name: name,
            photosLibraryPath: photosLibraryPath,
            primaryDestination: stagingRoot,
            mirrorDestinations: [],
            cloudVaultPath: nil,
            keepHEIC: keepHEIC,
            keepJPEG: keepJPEG,
            directoryTemplate: directoryTemplate,
            downloadMissingFromICloud: downloadMissingFromICloud,
            usePhotoKitForDownload: usePhotoKitForDownload,
            excludeSharedAndSyndicated: excludeSharedAndSyndicated,
            purgeEnabled: false,           // a sender can NEVER purge
            archiveSubfolder: archiveSubfolder,
            reviewNewItems: false          // no local "review" copies on a small-disk source
        )
    }

    // MARK: - Validation

    /// Blocking problems for a sender run.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        let staging = stagingRoot.trimmingCharacters(in: .whitespaces)
        if staging.isEmpty {
            issues.append("Staging SSD path is not set.")
        } else {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: staging, isDirectory: &isDir) || !isDir.boolValue {
                issues.append("Staging SSD isn’t mounted/available: \(staging)")
            }
        }
        if !keepHEIC && !keepJPEG {
            issues.append("No export format selected — enable HEIC originals and/or JPEG.")
        }
        if remote.enabled {
            if remote.host.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Remote host is not set.") }
            if remote.user.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Remote user is not set.") }
            if remote.remotePath.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Remote path is not set.") }
        }
        return issues
    }

    // MARK: - Persistence

    /// `~/Library/Application Support/PurpleAttic/sender.json` (separate from `profile.json`,
    /// so the sender config never collides with the core archive profile).
    public static func defaultURL() -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PurpleAttic", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sender.json")
    }

    public static func load(from url: URL = defaultURL()) -> SenderConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SenderConfig.self, from: data)
    }

    public func save(to url: URL = defaultURL()) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
