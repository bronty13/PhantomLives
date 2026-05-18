import Foundation

/// Silverstack-style workflow chain (Kyno-parity row 66).
///
/// A `WorkflowChain` is an ordered sequence of `Step`s — each step
/// wraps an existing service (VerifiedBackup, Transcode, Report).
/// Running a chain pipes the user's input folder through every
/// enabled step in order, with a single progress UI driving the
/// whole pipeline.
///
/// Persistence: every defined chain serialises to JSON inside the
/// `purplereel.workflowChains` UserDefaults key (a small array).
/// Two-mac DITs can cross-import via paste-the-JSON; a richer
/// import/export flow is a follow-up.
struct WorkflowChain: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// Free-form description shown in the management sheet.
    var notes: String
    var steps: [Step]
    /// When true, `VolumeWatcher.handleMounted` offers to run this
    /// chain on any newly-mounted volume that looks like camera
    /// media (DCIM / AVCHD / PRIVATE / BPAV / XDROOT at the root).
    /// Off by default — auto-trigger is an opt-in.
    var runOnCameraMediaMount: Bool

    init(id: UUID = UUID(),
         name: String,
         notes: String = "",
         steps: [Step] = [],
         runOnCameraMediaMount: Bool = false) {
        self.id = id
        self.name = name
        self.notes = notes
        self.steps = steps
        self.runOnCameraMediaMount = runOnCameraMediaMount
    }

    /// One step in a chain. The associated values are the parameters
    /// the step needs to run; everything else (source folder, etc.)
    /// is supplied by the runner at execution time.
    enum Step: Codable, Equatable, Identifiable, Hashable {
        case verifiedBackup(VerifiedBackupParams)
        case transcode(TranscodeParams)
        case exportReport(ReportParams)

        var id: String {
            switch self {
            case .verifiedBackup: return "verifiedBackup"
            case .transcode:      return "transcode"
            case .exportReport:   return "exportReport"
            }
        }

        var displayName: String {
            switch self {
            case .verifiedBackup: return "Verified Backup"
            case .transcode:      return "Transcode"
            case .exportReport:   return "Export Report"
            }
        }

        var icon: String {
            switch self {
            case .verifiedBackup: return "externaldrive.badge.checkmark"
            case .transcode:      return "wand.and.stars"
            case .exportReport:   return "doc.text"
            }
        }
    }

    struct VerifiedBackupParams: Codable, Equatable, Hashable {
        /// Destination roots. Resolved at run time as absolute paths.
        var destinationPaths: [String]
        var hashAlgorithm: String   // matches HashAlgorithm.rawValue
        var mhlFormat: String       // matches MHLFormat.rawValue

        static let defaults = VerifiedBackupParams(
            destinationPaths: [],
            hashAlgorithm: "SHA-1",
            mhlFormat: "MHL v1.1"
        )
    }

    struct TranscodeParams: Codable, Equatable, Hashable {
        /// `TranscodePreset.id` of the preset to use.
        var presetID: String
        /// Where transcoded files land. Empty = sibling
        /// `<source>/Proxies/` directory.
        var outputPath: String

        static let defaults = TranscodeParams(
            presetID: "prores-422-proxy",
            outputPath: ""
        )
    }

    struct ReportParams: Codable, Equatable, Hashable {
        /// "csv" or "html".
        var format: String
        /// Where the report file lands. Empty = `~/Downloads/PurpleReel/<chain>-<timestamp>.<ext>`.
        var outputPath: String

        static let defaults = ReportParams(format: "html", outputPath: "")
    }
}

/// UserDefaults-backed store for the user's chain definitions.
/// Read on app launch, written whenever the management sheet
/// commits a change. Plain JSON encoded as `Data` under the
/// `purplereel.workflowChains` key.
enum WorkflowChainsStore {
    static let defaultsKey = "purplereel.workflowChains"

    static func load() -> [WorkflowChain] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey)
        else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([WorkflowChain].self, from: data)) ?? []
    }

    static func save(_ chains: [WorkflowChain]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(chains) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
