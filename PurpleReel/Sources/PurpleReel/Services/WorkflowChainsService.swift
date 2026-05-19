import Foundation
import AppKit

/// Active run of one `WorkflowChain` (Kyno-parity row 66). Tracks
/// step-level state so the run sheet can show a progress checklist
/// instead of one opaque spinner. Lives on the main actor so its
/// `@Published` fields drive SwiftUI updates directly.
@MainActor
final class WorkflowChainRun: ObservableObject, Identifiable {
    enum State: Equatable {
        case queued, running
        case finished
        case failed(String)
        case cancelled
        var isTerminal: Bool {
            switch self {
            case .finished, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    /// Per-step state in the run. Mirrors the chain's `Step` order.
    @MainActor
    final class StepState: ObservableObject, Identifiable {
        let id = UUID()
        let step: WorkflowChain.Step
        @Published var status: State = .queued
        @Published var detail: String = ""
        @Published var progress: Double = 0
        init(_ step: WorkflowChain.Step) {
            self.step = step
        }
    }

    let id = UUID()
    let chain: WorkflowChain
    let source: URL
    @Published private(set) var steps: [StepState] = []
    @Published private(set) var state: State = .queued
    /// Index of the currently-executing step. -1 before the run
    /// starts, `steps.count` after every step terminates.
    @Published private(set) var currentStep: Int = -1
    /// Artifacts emitted by completed steps — surfaced in the run
    /// sheet so the user can reveal them in Finder.
    @Published private(set) var artifacts: [URL] = []
    /// In-flight backup job (so the user can cancel). Cleared
    /// between steps.
    private weak var activeBackup: BackupJob?
    /// C32 (E1) — in-flight transcode jobs for the current step,
    /// so `cancel()` can propagate to every queued sub-job. Cleared
    /// between steps.
    private var activeTranscodes: [TranscodeJob] = []

    init(chain: WorkflowChain, source: URL) {
        self.chain = chain
        self.source = source
        self.steps = chain.steps.map { StepState($0) }
    }

    func cancel() {
        // C32 (E1) — propagate cancel to every step kind we can
        // reach right now. Transcode sub-jobs each respond to
        // `cancel()` (TranscodeJob has its own AVAssetExportSession
        // / Process termination). Report export checks the run's
        // `state` at await boundaries. VerifiedBackupService doesn't
        // currently expose mid-flight cancellation — the backup
        // step still respects step-boundary cancel (state check at
        // top of loop) but won't interrupt an in-flight verify of
        // a large file. Documented as a known gap pending a
        // BackupJob.cancel API.
        state = .cancelled
        for j in activeTranscodes { j.cancel() }
    }

    func run(toolVersion: String, transcodeQueue: TranscodeQueue,
             appState: AppState) async {
        state = .running
        for (idx, stepState) in steps.enumerated() {
            if state == .cancelled {
                stepState.status = .cancelled
                continue
            }
            currentStep = idx
            stepState.status = .running
            switch stepState.step {
            case .verifiedBackup(let params):
                await runBackup(stepState: stepState,
                                params: params,
                                toolVersion: toolVersion)
            case .transcode(let params):
                await runTranscode(stepState: stepState,
                                    params: params,
                                    queue: transcodeQueue)
            case .exportReport(let params):
                await runReport(stepState: stepState,
                                params: params,
                                appState: appState)
            }
            if case .failed = stepState.status {
                state = .failed("Step \(idx + 1): \(stepState.detail)")
                return
            }
        }
        if state != .cancelled {
            state = .finished
        }
        currentStep = steps.count
    }

    // MARK: - Step runners

    private func runBackup(stepState: StepState,
                            params: WorkflowChain.VerifiedBackupParams,
                            toolVersion: String) async {
        guard !params.destinationPaths.isEmpty else {
            stepState.status = .failed("No destinations configured")
            stepState.detail = "Configure at least one destination."
            return
        }
        let algo = HashAlgorithm(rawValue: params.hashAlgorithm) ?? .sha1
        let fmt  = MHLFormat(rawValue: params.mhlFormat) ?? .legacy
        let dests = params.destinationPaths.map { URL(fileURLWithPath: $0) }
        let job = BackupJob(source: source, destinations: dests,
                             algorithm: algo, mhlFormat: fmt)
        activeBackup = job
        // Surface a coarse progress signal while the backup runs:
        // count items as they complete vs total discovered.
        let observer = Task { @MainActor [weak job, weak stepState] in
            while let j = job, let s = stepState, !s.status.isTerminal {
                if !j.items.isEmpty {
                    let done = j.items.filter {
                        if case .done = $0.state { return true }; return false
                    }.count
                    s.progress = Double(done) / Double(j.items.count)
                    s.detail = "\(done) / \(j.items.count) files verified"
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await VerifiedBackupService.run(job: job, toolVersion: toolVersion)
        observer.cancel()
        activeBackup = nil
        let failures = job.items.filter {
            if case .failed = $0.state { return true }; return false
        }
        if failures.isEmpty {
            stepState.status = .finished
            stepState.detail = "Verified \(job.items.count) file(s); "
                + "\(job.mhlPaths.count) MHL(s) written"
            artifacts.append(contentsOf: job.mhlPaths)
        } else {
            stepState.status = .failed("\(failures.count) file(s) failed verification")
            if let first = failures.first,
               case .failed(let msg) = first.state {
                stepState.detail = msg
            }
        }
    }

    private func runTranscode(stepState: StepState,
                               params: WorkflowChain.TranscodeParams,
                               queue: TranscodeQueue) async {
        // Resolve the preset by id; fall back to a sensible default
        // rather than failing — the chain ran for a reason.
        let preset = TranscodePreset.all.first { $0.id == params.presetID }
                  ?? TranscodePreset.all.first(where: { $0.id == "prores-422-proxy" })
                  ?? TranscodePreset.all[0]
        // Discover source media via the same extensions the scanner
        // uses. Cheap because we only enumerate one level.
        let media = WorkflowChainRun.discoverMedia(under: source)
        if media.isEmpty {
            stepState.status = .finished
            stepState.detail = "No media files found under source"
            return
        }
        // Output dir defaults to `<source>/Proxies` when blank.
        let outDir: URL
        if params.outputPath.isEmpty {
            outDir = source.appendingPathComponent("Proxies",
                                                    isDirectory: true)
        } else {
            outDir = URL(fileURLWithPath: params.outputPath)
        }
        try? FileManager.default.createDirectory(at: outDir,
                                                   withIntermediateDirectories: true)
        // Enqueue every media file as its own job. The queue's
        // `maxParallel` setting controls concurrency.
        var jobs: [TranscodeJob] = []
        for src in media {
            let base = src.deletingPathExtension().lastPathComponent
            let outName = "\(base)\(preset.suffix).\(preset.fileExtension)"
            let dst = outDir.appendingPathComponent(outName)
            let job = TranscodeJob(source: src, preset: preset, outputURL: dst)
            jobs.append(job)
            queue.enqueue(job)
        }
        // C32 (E1) — publish the in-flight jobs so `cancel()` can
        // reach them. Cleared in `defer` below regardless of how
        // we exit this scope.
        activeTranscodes = jobs
        defer { activeTranscodes = [] }
        // Wait for every job we enqueued to terminate. We poll the
        // job's `state` rather than touching the queue's internals,
        // so a user-triggered cancellation from the queue sheet
        // surfaces as `.cancelled` for that job.
        while jobs.contains(where: { !$0.state.isTerminal }) {
            // C32 (E1) — break out promptly when the run is
            // cancelled; the sub-jobs already had `.cancel()`
            // called from the outer `cancel()`, but we don't want
            // to block here waiting for AVAssetExportSession to
            // notice (it can take a beat).
            if state == .cancelled {
                stepState.status = .cancelled
                stepState.detail = "Cancelled mid-transcode"
                return
            }
            let done = jobs.filter { $0.state.isTerminal }.count
            stepState.progress = Double(done) / Double(jobs.count)
            stepState.detail = "\(done) / \(jobs.count) transcoded"
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let failures = jobs.filter {
            if case .failed = $0.state { return true }; return false
        }
        if failures.isEmpty {
            stepState.status = .finished
            stepState.detail = "Transcoded \(jobs.count) file(s) → \(outDir.lastPathComponent)/"
            artifacts.append(outDir)
        } else {
            stepState.status = .failed("\(failures.count) of \(jobs.count) transcodes failed")
            if let first = failures.first,
               case .failed(let msg) = first.state {
                stepState.detail = msg
            }
        }
    }

    private func runReport(stepState: StepState,
                            params: WorkflowChain.ReportParams,
                            appState: AppState) async {
        // Filter the live catalogue to assets under `source`.
        let prefix = (source.path.hasSuffix("/")
                      ? source.path : source.path + "/")
        let inScope = appState.assets.filter {
            $0.path.hasPrefix(prefix) || $0.path == source.path
        }
        if inScope.isEmpty {
            stepState.status = .finished
            stepState.detail = "No catalogued assets under source — run a workspace scan first"
            return
        }
        let ext = params.format == "csv" ? "csv" : "html"
        let outURL: URL
        if params.outputPath.isEmpty {
            let stamp = Self.timestampForFilename(Date())
            let downloads = FileManager.default.urls(
                for: .downloadsDirectory, in: .userDomainMask
            ).first ?? source
            let dir = downloads.appendingPathComponent("PurpleReel",
                                                        isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            outURL = dir.appendingPathComponent(
                "\(chain.name)-\(stamp).\(ext)"
            )
        } else {
            outURL = URL(fileURLWithPath: params.outputPath)
        }
        // C32 (E1) — cancel guard before kicking off the export.
        // The HTML writer is async and can take seconds on a large
        // workspace; CSV is sync but cheap. Either way, a user
        // hitting Cancel before the write starts shouldn't pay for
        // a doomed report.
        if state == .cancelled {
            stepState.status = .cancelled
            stepState.detail = "Cancelled before report started"
            return
        }
        do {
            let written: Int
            if params.format == "csv" {
                try ReportExporter.writeCSV(
                    assets: inScope, to: outURL, appState: appState
                )
                written = inScope.count
            } else {
                let summary = try await ReportExporter.writeHTML(
                    assets: inScope, to: outURL, appState: appState
                )
                written = summary.written
            }
            // Post-export cancel check — the user might have hit
            // cancel during the HTML write. If so, throw away the
            // (potentially partial) output.
            if state == .cancelled {
                try? FileManager.default.removeItem(at: outURL)
                stepState.status = .cancelled
                stepState.detail = "Cancelled — partial output removed"
                return
            }
            stepState.status = .finished
            stepState.detail = "Wrote \(written) row(s) → \(outURL.lastPathComponent)"
            artifacts.append(outURL)
        } catch {
            stepState.status = .failed(error.localizedDescription)
            stepState.detail = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private static func timestampForFilename(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: date)
    }

    /// Recursive media discovery — same extension set MediaScanner
    /// uses. Kept lean (no AVAsset probing) since the transcode
    /// step doesn't need the catalogue.
    private static func discoverMedia(under root: URL) -> [URL] {
        let fm = FileManager.default
        let exts: Set<String> = [
            "mov", "mp4", "m4v", "qt", "mxf", "avi", "mkv",
            "wav", "aif", "aiff", "mp3", "m4a", "flac", "caf"
        ]
        var out: [URL] = []
        guard let walker = fm.enumerator(at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        for case let url as URL in walker {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if v?.isDirectory == true { continue }
            let ext = url.pathExtension.lowercased()
            if exts.contains(ext) { out.append(url) }
        }
        return out
    }
}

/// Helpers shared across the chain UI.
enum WorkflowChainsService {
    /// Validate that a chain can run. Returns nil on success or a
    /// human-readable error string identifying the first problem.
    static func validate(_ chain: WorkflowChain) -> String? {
        if chain.steps.isEmpty { return "Chain has no steps." }
        for (i, step) in chain.steps.enumerated() {
            if case .verifiedBackup(let p) = step,
               p.destinationPaths.isEmpty {
                return "Step \(i + 1) (Verified Backup): no destinations."
            }
        }
        return nil
    }
}
