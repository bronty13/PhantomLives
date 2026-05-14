import Foundation
import Combine

/// Outcome of a single preflight probe. Equatable so SwiftUI rebuilds the
/// step rows only when the underlying status actually changes.
enum PreflightStatus: Equatable {
    /// Probe hasn't been run yet this session.
    case pending
    /// Probe is in flight (spawning a subprocess, awaiting reply).
    case checking
    /// Probe succeeded. `detail` is an optional terse note for the row
    /// caption ("Python 3.14.5 at /opt/homebrew/bin/python3").
    case ok(detail: String?)
    /// Probe failed. `reason` is the user-facing one-liner. `fix` is an
    /// optional suggested resolution displayed under the row.
    case failed(reason: String, fix: String?)
}

/// One step in the launch-time preflight. The IDs are stable so the UI
/// can key off them for icons / retry actions.
enum PreflightStepID: String, CaseIterable, Identifiable {
    case transcribeScript        // ~/Documents/GitHub/PhantomLives/transcribe/transcribe.py present
    case pythonVersion           // Python 3.10+ on the augmented PATH
    case ffmpegOnPath            // `ffmpeg` resolvable on the augmented PATH
    case venvBootstrap           // .venv/ exists and is post-3.10
    case mlxWhisperImport        // `import mlx_whisper` works inside the venv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcribeScript: return "transcribe.py is reachable"
        case .pythonVersion:    return "Python 3.10+ is installed"
        case .ffmpegOnPath:     return "ffmpeg is on PATH"
        case .venvBootstrap:    return "Transcribe venv exists"
        case .mlxWhisperImport: return "Transcription packages import cleanly"
        }
    }

    var explainer: String {
        switch self {
        case .transcribeScript:
            return "The CLI delegates transcription to PhantomLives/transcribe/transcribe.py. The GUI checks the same default path and the TRANSCRIBE_SCRIPT override."
        case .pythonVersion:
            return "transcribe.py uses PEP 604 syntax and the mlx wheels — both require Python 3.10 or later. The CommandLineTools Python (3.9) won't work."
        case .ffmpegOnPath:
            return "mlx-whisper shells out to ffmpeg to extract audio from .m4a / .mov / .mp4 attachments. /opt/homebrew/bin is auto-added to the child PATH, so installing ffmpeg via Homebrew is enough."
        case .venvBootstrap:
            return "transcribe.py creates ~/Documents/GitHub/PhantomLives/transcribe/.venv on first run. A stale venv from a removed Python is rebuilt automatically — but only if every other check above already passed."
        case .mlxWhisperImport:
            return "Final verification that the venv has every Python package transcribe.py requires (mlx, mlx-whisper, mlx-lm, truststore). If this is the only red row, run `Set up transcription` to pip-install the missing ones."
        }
    }
}

/// One row's worth of state: what to probe, where it stands.
struct PreflightStep: Identifiable, Equatable {
    let id: PreflightStepID
    var status: PreflightStatus

    var title: String { id.title }
    var explainer: String { id.explainer }
}

/// Plain-English step the setup workflow is currently executing. Drives
/// the warm progress UI so the user reads "Installing ffmpeg…" instead
/// of pip output. `none` means idle (no setup running); `finishedOK` and
/// `finishedFailed` are terminal so the wizard can swap to a success /
/// error panel without consulting `isInstalling` separately.
enum PreflightSetupPhase: Equatable {
    case none
    case checkingFfmpeg
    case installingFfmpeg
    case checkingVenv
    case rebuildingVenv
    case creatingVenv
    case refreshingPip
    case installingEngine
    case verifying
    case finishedOK
    /// Carries a user-facing reason the wizard surfaces in plain English.
    /// The technical detail still lives in `installLog` for the disclosure.
    case finishedFailed(reason: String)

    /// One-line label the wizard shows above the progress bar.
    var caption: String {
        switch self {
        case .none:                return ""
        case .checkingFfmpeg:      return "Checking for ffmpeg…"
        case .installingFfmpeg:    return "Installing ffmpeg (this can take a minute)…"
        case .checkingVenv:        return "Checking the Python environment…"
        case .rebuildingVenv:      return "Rebuilding the Python environment from scratch…"
        case .creatingVenv:        return "Setting up the Python environment…"
        case .refreshingPip:       return "Updating the package installer…"
        case .installingEngine:    return "Downloading the transcription engine (~200 MB)…"
        case .verifying:           return "Verifying the install…"
        case .finishedOK:          return "Transcription is ready."
        case .finishedFailed(let why): return why
        }
    }

    /// Position on a 0…1 progress bar. Approximate — pip output lengths
    /// are too variable to do anything more precise, but the user sees
    /// motion as we move through the phases.
    var progress: Double {
        switch self {
        case .none:                return 0
        case .checkingFfmpeg:      return 0.05
        case .installingFfmpeg:    return 0.15
        case .checkingVenv:        return 0.25
        case .rebuildingVenv:      return 0.30
        case .creatingVenv:        return 0.35
        case .refreshingPip:       return 0.45
        case .installingEngine:    return 0.75
        case .verifying:           return 0.92
        case .finishedOK:          return 1.0
        case .finishedFailed:      return 1.0
        }
    }

    var isTerminal: Bool {
        if case .finishedOK = self { return true }
        if case .finishedFailed = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .finishedFailed = self { return true }
        return false
    }
}

/// Probes the transcription pipeline's external dependencies at launch (and
/// on demand from Settings → Transcription). Designed as a thin shell over
/// `Process` so each step can be retried independently and the UI gets
/// granular feedback. The whole subsystem is no-op'd when the master kill
/// switch in Settings is off (`SettingsKeys.transcribeMasterOn` = false).
///
/// **Why a service**: the previous behaviour was to ship every transcription
/// failure straight into the CLI log pane as a Python traceback — useful
/// for debugging, useless for users. This consolidates the "is anything in
/// the pipeline actually broken?" question into a single sheet with named
/// steps, suggested fixes, and a one-button setup workflow.
@MainActor
final class TranscriptionPreflightService: ObservableObject {

    /// All probe rows. Initialised in stable order so the UI doesn't shuffle
    /// when one step's status changes.
    @Published private(set) var steps: [PreflightStep] = PreflightStepID
        .allCases.map { PreflightStep(id: $0, status: .pending) }
    /// True while any step is `.checking`. Lets the wizard show a spinner /
    /// disable buttons without each call site polling individual rows.
    @Published private(set) var isProbing: Bool = false
    /// True while the "Set up transcription" workflow is running pip
    /// installs / brew installs in the background.
    @Published private(set) var isInstalling: Bool = false
    /// User-facing phase of the in-flight setup workflow. Drives the
    /// warm progress UI (plain-English caption + progress bar); the
    /// technical pip log lives in `installLog` and is hidden behind a
    /// disclosure by default.
    @Published private(set) var setupPhase: PreflightSetupPhase = .none
    /// Newest-last list of lines the install workflow has emitted. Surfaced
    /// in the wizard's "Show technical details" disclosure for users who
    /// want to copy a bug report; never the primary view.
    @Published private(set) var installLog: [String] = []

    /// Computed: are all rows green?
    var allOK: Bool {
        steps.allSatisfy { if case .ok = $0.status { return true } else { return false } }
    }

    /// Computed: is any row red?
    var hasFailures: Bool {
        steps.contains { if case .failed = $0.status { return true } else { return false } }
    }

    // MARK: - Probing

    /// Run every probe in sequence. Sequential rather than parallel because
    /// later steps (venv, mlx import) read state populated by the earlier
    /// ones (which Python is in scope, which PATH applies).
    func probeAll() async {
        isProbing = true
        defer { isProbing = false }
        for id in PreflightStepID.allCases {
            await probe(id)
        }
    }

    /// Run a single probe. Public so the UI can wire "Retry" buttons per
    /// row without re-running the entire chain.
    func probe(_ id: PreflightStepID) async {
        setStatus(id, .checking)
        let result: PreflightStatus
        switch id {
        case .transcribeScript: result = await probeTranscribeScript()
        case .pythonVersion:    result = await probePythonVersion()
        case .ffmpegOnPath:     result = await probeFfmpegOnPath()
        case .venvBootstrap:    result = await probeVenvBootstrap()
        case .mlxWhisperImport: result = await probeMLXWhisperImport()
        }
        setStatus(id, result)
    }

    // MARK: - Individual probes

    /// Look for transcribe.py at the default location, then at the
    /// TRANSCRIBE_SCRIPT override. Mirrors the CLI's discovery order so
    /// the green-light here means the CLI will also find it.
    private func probeTranscribeScript() async -> PreflightStatus {
        for path in Self.transcribeScriptCandidates() {
            if FileManager.default.isReadableFile(atPath: path) {
                return .ok(detail: path)
            }
        }
        return .failed(
            reason: "transcribe.py not found.",
            fix: "Clone PhantomLives next to this app, or set the TRANSCRIBE_SCRIPT env var to your transcribe.py path."
        )
    }

    /// Locate Python 3.10+ on the augmented PATH. Tries the same lookup
    /// the CLI's `find_python_for_transcribe()` does so a passing row
    /// guarantees a passing transcription.
    private func probePythonVersion() async -> PreflightStatus {
        // Prefer homebrew's symlink — that's what the augmented PATH puts
        // first, and it's the most stable identifier for "the python the
        // CLI will pick." Fall back to plain `python3` so a manual install
        // outside homebrew still passes.
        for binary in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "python3"] {
            if let (out, code) = await Self.runCapturing(
                executable: binary,
                arguments: ["-c",
                    "import sys; print(sys.version.split()[0])"]),
               code == 0 {
                let version = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.versionMeets(version, minMajor: 3, minMinor: 10) {
                    return .ok(detail: "\(version) at \(binary)")
                } else {
                    return .failed(
                        reason: "\(binary) is Python \(version) — transcribe.py needs 3.10+.",
                        fix: "Install a newer Python: `brew install python@3.12`. The .app's PATH already includes /opt/homebrew/bin."
                    )
                }
            }
        }
        return .failed(
            reason: "Couldn't find a working python3 on the augmented PATH.",
            fix: "Run `brew install python@3.12` and re-run the preflight."
        )
    }

    /// Resolve `ffmpeg` exactly the way transcribe.py's `shutil.which()`
    /// will. We use `/usr/bin/env ffmpeg -version` rather than `which`
    /// because `env`'s PATH lookup is the same Python's subprocess uses,
    /// so a green row here truly means transcribe.py will succeed.
    private func probeFfmpegOnPath() async -> PreflightStatus {
        if let (out, code) = await Self.runCapturing(
            executable: "/usr/bin/env",
            arguments: ["ffmpeg", "-version"]),
           code == 0 {
            let first = out.split(separator: "\n").first.map(String.init) ?? "ffmpeg"
            return .ok(detail: first)
        }
        return .failed(
            reason: "`ffmpeg` not found on the augmented PATH.",
            fix: "Install via Homebrew: `brew install ffmpeg`. (The .app prepends /opt/homebrew/bin to PATH automatically.)"
        )
    }

    /// Confirm a usable venv already exists. transcribe.py rebuilds the
    /// venv on first run, but if Python disappeared (homebrew major-version
    /// upgrade) it can be left in a half-broken state.
    private func probeVenvBootstrap() async -> PreflightStatus {
        guard let venvPython = Self.venvPython(),
              FileManager.default.isExecutableFile(atPath: venvPython) else {
            return .failed(
                reason: "transcribe/.venv/bin/python missing.",
                fix: "Click `Set up transcription` to bootstrap it, or run `python3 ~/Documents/GitHub/PhantomLives/transcribe/transcribe.py --help` once from Terminal."
            )
        }
        if let (out, code) = await Self.runCapturing(
            executable: venvPython,
            arguments: ["-c", "import sys; print(sys.version.split()[0])"]),
           code == 0 {
            let version = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.versionMeets(version, minMajor: 3, minMinor: 10) {
                return .ok(detail: "venv Python \(version)")
            } else {
                return .failed(
                    reason: "venv Python is \(version) — needs 3.10+.",
                    fix: "Delete ~/Documents/GitHub/PhantomLives/transcribe/.venv and click `Set up transcription`."
                )
            }
        }
        return .failed(
            reason: "venv Python wouldn't start.",
            fix: "Delete ~/Documents/GitHub/PhantomLives/transcribe/.venv and click `Set up transcription`."
        )
    }

    /// The final acceptance test: can the venv actually `import mlx_whisper`?
    /// This is the single most common breakage after a Python or wheel
    /// update — the venv survives but the C extension goes stale.
    /// Per-row probe for the technical-details checklist. Checks every
    /// module in `requiredImports`, not just mlx_whisper — that was an
    /// alignment bug with transcribe.py's REQUIRED_PACKAGES list. When
    /// only mlx_whisper was checked, transcribe.py's bootstrap kept
    /// hitting the missing mlx-lm import and re-running its own
    /// `pip install` (which then intermittently fails on PyPI flakiness
    /// across a long export). Probing all of them keeps the GUI's idea
    /// of "is transcription ready?" honest.
    private func probeMLXWhisperImport() async -> PreflightStatus {
        guard let venvPython = Self.venvPython(),
              FileManager.default.isExecutableFile(atPath: venvPython) else {
            return .failed(
                reason: "venv Python missing — fix the venv bootstrap row first.",
                fix: nil
            )
        }
        // Check each module individually so the failure detail can
        // mention which one(s) are missing — useful for bug reports.
        var missing: [String] = []
        for module in Self.requiredImports {
            if let (_, code) = await Self.runCapturing(
                executable: venvPython,
                arguments: ["-c", "import \(module)"]),
               code == 0 {
                continue
            }
            missing.append(module)
        }
        if missing.isEmpty {
            return .ok(detail: "all required modules import cleanly (\(Self.requiredImports.joined(separator: ", ")))")
        }
        return .failed(
            reason: "Missing in the venv: \(missing.joined(separator: ", ")).",
            fix: "Click `Set up transcription` — that runs `pip install` for all required packages."
        )
    }

    // MARK: - One-shot setup workflow

    /// Single source of truth for "what does transcribe.py need installed
    /// inside its venv?" Kept in sync with transcribe.py's
    /// REQUIRED_PACKAGES (and the corresponding top-level import names)
    /// — if these drift, transcribe.py's bootstrap will hit a missing
    /// module on subsequent invocations and fall back to `pip install`,
    /// which is the exact bug the new bootstrap is supposed to skip.
    ///
    /// Pip-name vs import-name: pip uses dashes ("mlx-whisper"), Python
    /// uses underscores ("mlx_whisper") for the corresponding module.
    /// We carry both so we can drive pip install AND the import-based
    /// verification probe off the same list.
    static let requiredPipPackages: [String] = [
        "mlx>=0.16.0",
        "mlx-whisper>=0.4.0",
        "mlx-lm>=0.19.0",
        "truststore>=0.10.0",
    ]
    static let requiredImports: [String] = [
        "mlx",
        "mlx_whisper",
        "mlx_lm",
        "truststore",
    ]

    /// One-button "fix transcription" workflow. Does the right thing
    /// every time — no user choice required:
    ///
    ///   1. Make sure ffmpeg is installed (best effort via Homebrew).
    ///   2. Make sure the .venv exists and its bundled pip works.
    ///      Corrupt pip (the canonical `_log` ImportError after a Python
    ///      upgrade) is detected and triggers an automatic rebuild.
    ///   3. Refresh pip via ensurepip --upgrade --default-pip.
    ///   4. pip install mlx-whisper + truststore.
    ///   5. **Verify by importing mlx_whisper.** This is the source of
    ///      truth, not any individual subprocess exit code — pip can
    ///      print "Successfully installed" and still return non-zero in
    ///      edge cases, and our streamProcess can drop the exit value
    ///      after a torrent of output. If the import works, transcription
    ///      works; declare success.
    ///
    /// Both `runSetup` and the manual `rebuildVenv` action funnel through
    /// here. The only difference: `rebuildVenv` always nukes the venv
    /// first, where `runSetup` only rebuilds when pip is broken.
    ///
    /// Returns true iff the final verification probe confirms transcription
    /// is live. Updates `setupPhase` continuously so the warm UI can show
    /// plain-English progress without scraping pip's output.
    func runSetup() async -> Bool {
        await runSetupInternal(forceVenvRebuild: false)
    }

    /// Manual escape hatch the wizard exposes when the user wants a
    /// clean rebuild regardless of whether pip looks broken. Same
    /// workflow as `runSetup` except the venv is always nuked first.
    func rebuildVenv() async -> Bool {
        await runSetupInternal(forceVenvRebuild: true)
    }

    private func runSetupInternal(forceVenvRebuild: Bool) async -> Bool {
        guard !isInstalling else { return false }
        isInstalling = true
        installLog = []
        setupPhase = .none
        defer { isInstalling = false }

        // Step 1: ffmpeg. Probe with the augmented PATH first; if missing,
        // install via Homebrew. brew install is a no-op on existing
        // installs, but it's slow, so skip when we know it's already there.
        setupPhase = .checkingFfmpeg
        let ffmpegOK = await ffmpegIsOnPath()
        if !ffmpegOK {
            setupPhase = .installingFfmpeg
            installLog.append("[setup] Installing ffmpeg via Homebrew…")
            let ok = await streamProcess(
                executable: "/usr/bin/env",
                arguments: ["brew", "install", "ffmpeg"])
            if !ok {
                let reason = brewIsAvailable()
                    ? "Couldn't install ffmpeg. Check your internet connection and try again."
                    : "Transcription needs Homebrew to install ffmpeg. Install Homebrew from https://brew.sh, then click Fix transcription again."
                setupPhase = .finishedFailed(reason: reason)
                return false
            }
        }

        // Step 2: healthy venv. Three cases — missing, corrupt, healthy.
        // The manual "Rebuild venv" path forces the corrupt branch.
        setupPhase = .checkingVenv
        let venvMissing = Self.venvPython() == nil
        var venvCorrupt = false
        if !venvMissing {
            venvCorrupt = !(await venvPipIsHealthy())
        }
        if venvMissing || venvCorrupt || forceVenvRebuild {
            if venvMissing {
                setupPhase = .creatingVenv
                installLog.append("[setup] Creating .venv at \(Self.venvDir())…")
            } else {
                setupPhase = .rebuildingVenv
                installLog.append(
                    forceVenvRebuild
                    ? "[setup] Rebuilding .venv from scratch (user-initiated)…"
                    : "[setup] Existing .venv's pip is broken — rebuilding from scratch…"
                )
                if !nukeVenv() {
                    setupPhase = .finishedFailed(reason:
                        "Couldn't delete the old Python environment. Check disk permissions and try again.")
                    return false
                }
            }
            if !(await createVenv()) {
                setupPhase = .finishedFailed(reason:
                    "Couldn't create the Python environment. Make sure Python 3.10+ is installed (e.g. `brew install python@3.12`) and try again.")
                return false
            }
        }
        guard let venvPython = Self.venvPython() else {
            setupPhase = .finishedFailed(reason:
                "The Python environment is missing after setup — please try Rebuild venv from the menu.")
            return false
        }

        // Step 3: refresh pip. ensurepip overwrites the venv's site-packages
        // pip with the host Python's bundled wheel. Non-zero exit isn't fatal
        // (a freshly-rebuilt venv may already have a healthy pip).
        setupPhase = .refreshingPip
        installLog.append("[setup] Refreshing pip (ensurepip --upgrade)…")
        _ = await streamProcess(
            executable: venvPython,
            arguments: ["-m", "ensurepip", "--upgrade", "--default-pip"])

        // Step 4: install. Match transcribe.py's REQUIRED_PACKAGES list
        // exactly so its bootstrap import-check passes on every subsequent
        // invocation — installing only a subset would mean transcribe.py
        // still falls back to its own `pip install` (and intermittently
        // fails on PyPI flakiness) for the missing entries.
        //
        // --force-reinstall is the bulletproof option here. The user's
        // venv repeatedly got into states where pip thought a package
        // was installed but key files were missing (the "torch requires
        // networkx, which is not installed" message from a half-broken
        // mlx-whisper install is the canonical symptom). Forcing
        // reinstall makes the workflow idempotent — clicking the button
        // a second time after corruption fixes it instead of compounding it.
        setupPhase = .installingEngine
        installLog.append("[setup] Installing transcription engine packages: \(Self.requiredPipPackages.joined(separator: ", "))…")
        _ = await streamProcess(
            executable: venvPython,
            arguments: ["-m", "pip", "install", "--progress-bar", "off",
                        "--upgrade", "--force-reinstall"]
                       + Self.requiredPipPackages)

        // Step 5: VERIFY. Single source of truth — does `python -c
        // "import mlx, mlx_whisper, mlx_lm, truststore"` succeed?
        // We deliberately don't read pip's exit code: pip's own
        // "dependency conflicts" warning produces a non-zero exit in
        // some pip versions even when the install physically worked,
        // and our streamProcess can lose the tail bytes in others.
        // The import probe is both stricter (catches missing-file
        // half-installs) AND more forgiving (catches working installs
        // pip mis-reported).
        setupPhase = .verifying
        installLog.append("[setup] Verifying installation (\(Self.requiredImports.joined(separator: ", ")))…")
        let importOK = await requiredImportsAllResolve(python: venvPython)
        if importOK {
            setupPhase = .finishedOK
            installLog.append("[setup] ✓ Done — all required modules import cleanly.")
            return true
        }

        setupPhase = .finishedFailed(reason: classifyInstallFailure())
        installLog.append("[setup] ✗ Final verification (`import \(Self.requiredImports.joined(separator: ", "))`) failed.")
        return false
    }

    /// True iff `ffmpeg -version` exits 0 on the augmented PATH.
    private func ffmpegIsOnPath() async -> Bool {
        guard let (_, code) = await Self.runCapturing(
            executable: "/usr/bin/env",
            arguments: ["ffmpeg", "-version"]) else { return false }
        return code == 0
    }

    /// True iff `brew --version` exits 0 — used to give a more helpful
    /// failure message ("install Homebrew") vs ("check your network").
    private func brewIsAvailable() -> Bool {
        // Synchronous shell-out via Process. No need to async — this is
        // only invoked on the failure path where we can afford a blocking
        // ~50ms probe.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["brew", "--version"]
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExportRunner.augmentedPATH(existing: env["PATH"])
        p.environment = env
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Quick liveness probe on the venv's pip. Any non-zero exit (or
    /// missing binary) is treated as "broken" — corrupt-pip cases vary
    /// (the `_log` ImportError is one of many) and rebuilding is cheap.
    private func venvPipIsHealthy() async -> Bool {
        guard let py = Self.venvPython() else { return false }
        guard let (_, code) = await Self.runCapturing(
            executable: py,
            arguments: ["-m", "pip", "--version"]) else { return false }
        return code == 0
    }

    /// Final acceptance test: can the venv import every module in
    /// `requiredImports`? This is what determines success — not pip's
    /// exit code, not any individual subprocess return.
    private func requiredImportsAllResolve(python: String) async -> Bool {
        guard let (_, code) = await Self.runCapturing(
            executable: python,
            arguments: ["-c", "import " + Self.requiredImports.joined(separator: ", ")])
        else { return false }
        return code == 0
    }

    /// Best-effort plain-English explanation when verification fails.
    /// Scans the technical log for the patterns we know about (pip wheel
    /// mismatch, ImportError, network timeout) and falls back to a
    /// generic message that nudges the user toward the technical details
    /// disclosure.
    private func classifyInstallFailure() -> String {
        let log = installLog.joined(separator: "\n")
        if log.contains("Could not find a version") || log.contains("No matching distribution") {
            return "Some packages don't have a build for this Python version yet. Try installing python@3.12 with Homebrew and click Fix transcription again."
        }
        if log.contains("Connection") || log.contains("network") || log.contains("Could not connect") {
            return "Couldn't reach PyPI. Check your internet connection and try again."
        }
        if log.contains("ImportError") {
            return "The Python environment is in an unusable state. Try `Rebuild venv` from the menu for a clean install."
        }
        return "Setup didn't complete. Open Show technical details below to see what went wrong, or click Rebuild venv for a fresh start."
    }

    /// `rm -rf` the .venv directory. Tolerant of "already gone" so it's
    /// safe to call as a precondition to createVenv even on first run.
    private func nukeVenv() -> Bool {
        let dir = Self.venvDir()
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir) else { return true }
        do {
            try fm.removeItem(atPath: dir)
            installLog.append("[setup] Removed \(dir).")
            return true
        } catch {
            installLog.append("[setup] Failed to remove \(dir): \(error.localizedDescription)")
            return false
        }
    }

    /// Spawn `python -m venv <dir>`. Picks the same Python the preflight
    /// row blessed so the bootstrap inherits a 3.10+ interpreter.
    private func createVenv() async -> Bool {
        let pyForBootstrap = Self.preferredSystemPython()
        installLog.append("[setup] Running \(pyForBootstrap) -m venv \(Self.venvDir())…")
        let ok = await streamProcess(
            executable: pyForBootstrap,
            arguments: ["-m", "venv", Self.venvDir()])
        if !ok {
            installLog.append("[setup] venv creation failed.")
            return false
        }
        return true
    }

    // MARK: - Helpers

    /// Search order for the transcribe.py script, in the same precedence
    /// `find_transcribe_script()` uses in export_messages.py.
    nonisolated static func transcribeScriptCandidates() -> [String] {
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["TRANSCRIBE_SCRIPT"],
           !env.isEmpty {
            candidates.append(env)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append("\(home)/Documents/GitHub/PhantomLives/transcribe/transcribe.py")
        return candidates
    }

    nonisolated static func venvDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Documents/GitHub/PhantomLives/transcribe/.venv"
    }

    nonisolated static func venvPython() -> String? {
        let path = "\(venvDir())/bin/python"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// First existing Python 3.10+ binary we can find. Used when the venv
    /// is missing entirely and we have to bootstrap one from scratch.
    nonisolated static func preferredSystemPython() -> String {
        // The augmented PATH includes /opt/homebrew/bin so a plain `python3`
        // resolves there; absolute paths fall through for completeness.
        for candidate in [
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/env"   // last resort: rely on PATH lookup
        ] {
            if candidate.hasSuffix("env") { return candidate }
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/env"
    }

    /// Update a single row's status. @MainActor on the service makes this
    /// safe to call from any await chain without an explicit hop.
    private func setStatus(_ id: PreflightStepID, _ status: PreflightStatus) {
        guard let idx = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[idx].status = status
    }

    private func statusFor(_ id: PreflightStepID) -> PreflightStatus {
        steps.first(where: { $0.id == id })?.status ?? .pending
    }

    /// Spawn a process and capture combined stdout+stderr until exit.
    /// Returns nil if the process couldn't be launched at all (binary
    /// missing); otherwise the captured text and exit code.
    nonisolated static func runCapturing(executable: String,
                                         arguments: [String]) async -> (String, Int32)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        // Inherit the same augmented PATH the export runner uses — the whole
        // point of preflight is to predict what the export will see.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExportRunner.augmentedPATH(existing: env["PATH"])
        p.environment = env
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
    }

    /// Like `runCapturing` but streams output into `installLog` as it
    /// arrives. Used by the setup workflow so the wizard's technical log
    /// stays live during long pip downloads.
    ///
    /// Implementation notes:
    /// - Uses a `Data`-backed line buffer (the same shape ExportRunner
    ///   uses) so we never split a UTF-8 line across chunk boundaries.
    ///   The naive prior implementation appended partial-line tails as
    ///   if they were full lines and never drained the residual data
    ///   after process exit — which is why pip's tail output ("[setup]
    ///   Done.", "Successfully installed …") sometimes vanished and the
    ///   wizard reported a successful install as a failure.
    /// - Always drains the pipe after the process terminates so the
    ///   `terminationStatus` accompanies the FULL captured output.
    @MainActor
    private func streamProcess(executable: String, arguments: [String]) async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExportRunner.augmentedPATH(existing: env["PATH"])
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env

        do { try p.run() } catch {
            installLog.append("[setup] failed to launch \(executable): \(error.localizedDescription)")
            return false
        }

        let buffer = PipeLineBuffer()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            let lines = buffer.append(chunk)
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                for line in lines {
                    self?.installLog.append(line)
                }
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        handle.readabilityHandler = nil

        // Post-exit drain. The pipe may still hold buffered bytes the
        // readabilityHandler hasn't seen — without this, the last few
        // lines of pip output (including "Successfully installed …") get
        // silently dropped. availableData is non-blocking now that the
        // process is dead.
        let residual = handle.availableData
        if !residual.isEmpty {
            for line in buffer.append(residual) { installLog.append(line) }
        }
        // Final tail: any bytes still in the buffer without a trailing
        // newline. pip's last line of output frequently lacks one when
        // streamed through a pipe rather than a TTY.
        if let trailing = buffer.drainTrailing() {
            installLog.append(trailing)
        }

        return p.terminationStatus == 0
    }

    /// "3.14.5" >= "3.10" → true, etc. Tolerant of dev tags ("3.13.0rc1")
    /// because brew sometimes serves them; we only compare the leading
    /// dotted-integer prefix.
    nonisolated static func versionMeets(_ s: String,
                                         minMajor: Int, minMinor: Int) -> Bool {
        let parts = s.split(separator: ".").prefix(2)
        guard parts.count == 2 else { return false }
        // The minor component can be "5rc1" or similar; pull leading digits.
        let minorDigits = parts[1].prefix(while: { $0.isNumber })
        guard let major = Int(parts[0]),
              let minor = Int(minorDigits) else { return false }
        if major != minMajor { return major > minMajor }
        return minor >= minMinor
    }
}

/// Byte buffer that accumulates pipe chunks and emits complete lines.
/// Pipe.readabilityHandler delivers data in arbitrary-sized chunks that
/// don't necessarily align with line boundaries or even UTF-8 codepoint
/// boundaries; a naive `String(data:).split("\n")` per chunk loses
/// trailing partial lines and can mangle multi-byte characters that
/// straddle a chunk boundary. This buffer:
///
///   - Holds raw bytes until we see a `\n`.
///   - Returns full lines on each append.
///   - Lets the caller `drainTrailing()` for whatever remains after the
///     process exits (the last line of pip output often has no
///     trailing newline when piped instead of TTY'd).
///
/// Lock'd because the readabilityHandler closure is Sendable but reads/
/// writes the same `Data` instance the post-exit drain code touches.
/// Mirrors the pattern in ExportRunner's private LineBuffer; kept here
/// (rather than reused) so the service stays free-standing.
final class PipeLineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    /// Append a chunk and return any newly-completed lines. A "line" is
    /// the bytes up to (but not including) the next `\n` or `\r\n`. Empty
    /// lines are preserved as empty strings — pip's `--progress-bar off`
    /// output emits them and tests want to see the spacing.
    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var out: [String] = []
        while let idx = data.firstIndex(of: 0x0A) {
            // Include the byte right before the \n unless it's a \r (CRLF).
            let trimEnd = (idx > data.startIndex && data[data.index(before: idx)] == 0x0D)
                ? data.index(before: idx)
                : idx
            let lineBytes = data[data.startIndex..<trimEnd]
            let line = String(data: lineBytes, encoding: .utf8) ?? ""
            out.append(line)
            data.removeSubrange(data.startIndex...idx)
        }
        return out
    }

    /// Pop whatever's left in the buffer (no trailing newline). nil when
    /// the buffer is empty — the caller can `if let` to decide whether
    /// to bother appending an empty string.
    func drainTrailing() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return nil }
        let line = String(data: data, encoding: .utf8) ?? ""
        data.removeAll()
        return line.isEmpty ? nil : line
    }
}
