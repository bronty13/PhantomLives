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
    /// C33 (E2) — when true, a step that fails is recorded and the
    /// chain continues running subsequent steps rather than
    /// terminating the whole run. Default false preserves the
    /// pre-C33 abort-on-first-failure behavior. Recommended on for
    /// "best-effort" pipelines (e.g. Transcode failures of one
    /// codec-quirky file shouldn't block the catalog Report).
    var continueOnFailure: Bool

    init(id: UUID = UUID(),
         name: String,
         notes: String = "",
         steps: [Step] = [],
         runOnCameraMediaMount: Bool = false,
         continueOnFailure: Bool = false) {
        self.id = id
        self.name = name
        self.notes = notes
        self.steps = steps
        self.runOnCameraMediaMount = runOnCameraMediaMount
        self.continueOnFailure = continueOnFailure
    }

    /// C33 — custom decoder so chain JSON saved before the
    /// `continueOnFailure` field existed still loads. Maps any
    /// missing field to false (pre-C33 behavior). Without this,
    /// users upgrading would silently lose their saved chains
    /// when the synthesized Codable failed on the missing key.
    enum CodingKeys: String, CodingKey {
        case id, name, notes, steps, runOnCameraMediaMount, continueOnFailure
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
        self.runOnCameraMediaMount =
            try c.decodeIfPresent(Bool.self, forKey: .runOnCameraMediaMount) ?? false
        self.continueOnFailure =
            try c.decodeIfPresent(Bool.self, forKey: .continueOnFailure) ?? false
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

/// C33 (E4) — built-in chain templates surfaced in the
/// `WorkflowChainsSheet` editor as a "Start from template…" menu.
/// Each template is just a `WorkflowChain` factory; instantiation
/// gives the user a fully-formed chain they can rename + tweak
/// before saving. Beats starting from a blank "Add step…" form.
enum WorkflowChainTemplates {

    struct Template: Identifiable {
        let id: String
        let name: String
        let description: String
        let icon: String
        /// Factory — fresh UUID per instantiation so each user
        /// import is its own chain rather than aliasing a shared id.
        let build: () -> WorkflowChain
    }

    /// Catalogue surfaced in the editor menu. Order matters — the
    /// menu shows them top-down.
    static let catalogue: [Template] = [
        Template(
            id: "card-offload",
            name: "Camera Card Offload",
            description: "Verified-Backup-only chain for the DIT's daily card-ingest pass. No transcode, no report. Auto-trigger on camera-media mount is on by default — useful for set workflows.",
            icon: "externaldrive.badge.checkmark",
            build: {
                WorkflowChain(
                    name: "Camera Card Offload",
                    notes: "Verifies and writes MHL for each newly-mounted camera card.",
                    steps: [.verifiedBackup(.defaults)],
                    runOnCameraMediaMount: true,
                    continueOnFailure: false
                )
            }
        ),
        Template(
            id: "daily-delivery",
            name: "Daily Delivery (Backup + H.264 + CSV)",
            description: "End-of-day pipeline: verified backup, H.264 1080p transcodes for review, CSV report. continueOnFailure ON — one codec-quirky source shouldn't block the report.",
            icon: "tray.and.arrow.down",
            build: {
                var tx = WorkflowChain.TranscodeParams.defaults
                tx.presetID = "h264-1080p"
                var rp = WorkflowChain.ReportParams.defaults
                rp.format = "csv"
                return WorkflowChain(
                    name: "Daily Delivery",
                    notes: "Verified backup → H.264 1080p transcodes → CSV report.",
                    steps: [
                        .verifiedBackup(.defaults),
                        .transcode(tx),
                        .exportReport(rp),
                    ],
                    runOnCameraMediaMount: false,
                    continueOnFailure: true
                )
            }
        ),
        Template(
            id: "proxy-only",
            name: "Proxy Generation Only",
            description: "Skip backup; just transcode the source folder to ProRes Proxy for editorial. Useful when the original backup lives elsewhere.",
            icon: "wand.and.stars",
            build: {
                WorkflowChain(
                    name: "Proxy Only",
                    notes: "ProRes Proxy transcodes only — no backup, no report.",
                    steps: [.transcode(WorkflowChain.TranscodeParams(
                        presetID: "prores-422-proxy", outputPath: ""
                    ))],
                    runOnCameraMediaMount: false,
                    continueOnFailure: false
                )
            }
        ),
        Template(
            id: "report-only",
            name: "Catalogue Report Only",
            description: "Just emit an HTML report of the current catalogue scope. Skips backup + transcode. Useful for sharing a clip list with the producer/director without re-rendering anything.",
            icon: "doc.text",
            build: {
                WorkflowChain(
                    name: "Catalogue Report",
                    notes: "HTML report of the current catalogue scope.",
                    steps: [.exportReport(.defaults)],
                    runOnCameraMediaMount: false,
                    continueOnFailure: false
                )
            }
        ),
    ]
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
