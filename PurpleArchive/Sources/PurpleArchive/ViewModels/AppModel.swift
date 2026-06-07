import Foundation
import SwiftUI
import ArchiveKit

/// The GUI's central state: the currently open archive, its entry tree, and the
/// async operations (open, extract, compress) with progress. Engine calls run
/// off the main actor; results land back on it.
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    private let service = ArchiveService()
    let vault: PasswordVault = KeychainVault()

    // Open archive
    @Published var openedURL: URL?
    @Published var entries: [ArchiveEntry] = []
    /// Hierarchical (multi-level) view of `entries` for the outline browser —
    /// the top-level nodes; folders expand to reveal their contents n levels
    /// deep. Rebuilt whenever the listing or filename encoding changes.
    @Published var entryNodes: [ArchiveEntryNode] = []
    @Published var info: ArchiveInfo?
    @Published var isEncrypted = false

    // Filename-encoding fix (live picker). `rawEntries` keeps libarchive's
    // listing; `entries` is `rawEntries` re-decoded with `selectedEncoding`.
    private var rawEntries: [ArchiveEntry] = []
    @Published var selectedEncoding: DetectedEncoding = EncodingDetector.candidates[0] {
        didSet { applyEncoding() }
    }
    let availableEncodings = EncodingDetector.candidates

    // Transient UI state
    @Published var status: String = "Drop an archive to browse it, or files to compress."
    @Published var busy = false
    @Published var progress: Double?
    @Published var errorMessage: String?

    @Published var sidebarSelection: SidebarItem = .browse

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Open / browse

    func open(_ url: URL) {
        runJob("Reading \(url.lastPathComponent)…") { [service] in
            let info = try service.info(url)
            let entries = try service.list(url)
            return (info, entries)
        } onSuccess: { [weak self] (info: ArchiveInfo, entries: [ArchiveEntry]) in
            guard let self else { return }
            self.openedURL = url
            self.info = info
            self.rawEntries = entries
            self.isEncrypted = info.isEncrypted
            // Auto-detect the filename encoding; the user can override live.
            let detected = EncodingDetector.detect(rawNames: entries.map(\.rawNameBytes))
            self.selectedEncoding = detected   // triggers applyEncoding()
            self.applyEncoding()
            self.status = "\(info.fileCount) files · \(ByteFormat.string(info.totalUncompressedSize)) unpacked"
                + (detected.encoding != .utf8 ? " · names: \(detected.label)" : "")
        }
    }

    /// Re-decode the open archive's entry names with `selectedEncoding`. Instant
    /// — operates on the cached raw bytes, no re-read.
    private func applyEncoding() {
        if selectedEncoding.encoding == .utf8 {
            entries = rawEntries
        } else {
            entries = rawEntries.map { $0.reDecoded(using: selectedEncoding.encoding) }
        }
        entryNodes = ArchiveEntryTree.build(from: entries).children
    }

    /// Password remembered in the Keychain for the open archive, if any.
    var vaultPassword: String? { openedURL.flatMap { vault.password(for: $0) } }

    /// Session-sticky extract destination. When the user picks a folder it's
    /// stored here and every later extract goes there — until the app relaunches
    /// (this is in-memory only), when it falls back to the Settings default.
    @Published var sessionExtractRoot: URL?

    /// Where extracts go right now: the session override if set, else the
    /// persistent Settings default (`~/Downloads/PurpleArchive` out of the box).
    var extractDestinationRoot: URL { sessionExtractRoot ?? settings.resolvedExtractRoot }

    /// `~`-abbreviated path of the current destination, for menus/help text.
    var extractDestinationLabel: String {
        extractDestinationRoot.path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    func extractOpened(password: String? = nil, remember: Bool = false) {
        guard let url = openedURL else { return }
        // Fall back to a Keychain-remembered password when none was supplied.
        let effective = password ?? vault.password(for: url)
        if remember, let pw = password, !pw.isEmpty { vault.setPassword(pw, for: url) }
        let dest = extractDestinationRoot
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
        let opts = ExtractOptions(destination: dest, password: effective)
        runJob("Extracting…") { [service] in
            try service.extract(url, options: opts)
            return dest
        } onSuccess: { [weak self] (dest: URL) in
            self?.status = "Extracted → \(dest.path)"
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }

    /// Extract a subset of entries (selected in the browser) to the same
    /// destination folder as a full extract, preserving their paths within the
    /// archive. Directories should already be expanded to their files by the
    /// caller; any directory entries are skipped here.
    func extractEntries(_ entries: [ArchiveEntry], password: String? = nil, remember: Bool = false) {
        guard let url = openedURL else { return }
        let items = entries.filter { !$0.isDirectory }.map(\.displayPath)
        guard !items.isEmpty else { return }
        let effective = password ?? vault.password(for: url)
        if remember, let pw = password, !pw.isEmpty { vault.setPassword(pw, for: url) }
        let destRoot = extractDestinationRoot
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
        runJob("Extracting \(items.count) item(s)…") { [service] in
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            var extracted = 0
            for path in items {
                let dest = destRoot.appendingPathComponent(path)
                if try service.extractEntry(url, entryPath: path, to: dest, password: effective) {
                    extracted += 1
                }
            }
            return (destRoot, extracted)
        } onSuccess: { [weak self] (result: (URL, Int)) in
            self?.status = "Extracted \(result.1) item(s) → \(result.0.path)"
            NSWorkspace.shared.activateFileViewerSelecting([result.0])
        }
    }

    // MARK: - Test / verify

    /// Integrity-test the open archive — reads every entry through the engine,
    /// verifying CRCs / decompression, writing nothing to disk.
    func testOpened(password: String? = nil) {
        guard let url = openedURL else { return }
        let effective = password ?? vault.password(for: url)
        runJob("Testing \(url.lastPathComponent)…") { [service] in
            try service.test(url, password: effective)
        } onSuccess: { [weak self] (ok: Bool) in
            self?.status = ok
                ? "✓ Archive is intact — every entry verified."
                : "⚠︎ Archive failed verification."
        }
    }

    // MARK: - Quick Look

    /// A file extracted to a temp location for inline Quick Look preview.
    /// Identifiable so it can drive a `.sheet(item:)`.
    struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
    }

    /// Non-nil while a Quick Look preview sheet should be shown.
    @Published var preview: PreviewItem?

    /// Extract one entry to a temp file and surface it for Quick Look. Reuses
    /// the same single-entry streaming extractor as drag-out, so even huge
    /// archives only unpack the one file being previewed.
    func quickLook(_ entry: ArchiveEntry) {
        guard let url = openedURL, !entry.isDirectory else { return }
        let pw = vault.password(for: url)
        runJob("Preparing preview of \(entry.name)…") { [service] in
            try service.extractEntryToTemp(url, entry: entry, password: pw)
        } onSuccess: { [weak self] (temp: URL) in
            self?.preview = PreviewItem(url: temp, name: entry.name)
            self?.status = "Previewing \(entry.name)"
        }
    }

    // MARK: - In-place edit

    /// Whether the open archive is a writable, editable container.
    var canEdit: Bool {
        guard let url = openedURL, let fmt = ArchiveFormat.forFilename(url.lastPathComponent)
        else { return false }
        return fmt.canCreate && fmt.isMultiFileContainer
    }

    func deleteEntries(_ paths: [String]) { applyEdits(paths.map { .delete(path: $0) }) }
    func addFiles(_ urls: [URL]) { applyEdits(urls.map { .add(fileURL: $0, at: $0.lastPathComponent) }) }
    func rename(_ from: String, to: String) {
        guard !to.isEmpty, to != from else { return }
        applyEdits([.rename(from: from, to: to)])
    }

    private func applyEdits(_ ops: [EditOperation]) {
        guard let url = openedURL, !ops.isEmpty else { return }
        runJob("Editing \(url.lastPathComponent)…") { [service] in
            try service.edit(url, operations: ops)
            let info = try service.info(url)
            let entries = try service.list(url)
            return (info, entries)
        } onSuccess: { [weak self] (info: ArchiveInfo, entries: [ArchiveEntry]) in
            self?.info = info
            self?.rawEntries = entries
            self?.applyEncoding()
            self?.status = "Edited · \(info.fileCount) files"
        }
    }

    // MARK: - Compress

    /// Default output URL for `inputs` in the current format and destination —
    /// the pre-filled suggestion in the Create-Archive save panel.
    func suggestedOutputURL(for inputs: [URL]) -> URL {
        let format = settings.defaultFormat
        let firstName = inputs.count == 1
            ? inputs[0].deletingPathExtension().lastPathComponent
            : "Archive"
        return settings.resolvedExtractRoot
            .appendingPathComponent("\(firstName).\(format.preferredExtension)")
    }

    func compress(_ inputs: [URL], windowsSafe: Bool = false) {
        guard !inputs.isEmpty else { return }
        createArchive(inputs, output: suggestedOutputURL(for: inputs),
                      password: nil, windowsSafe: windowsSafe)
    }

    func compressEncrypted(_ inputs: [URL], password: String, windowsSafe: Bool = false) {
        guard !inputs.isEmpty else { return }
        createArchive(inputs, output: suggestedOutputURL(for: inputs),
                      password: password, windowsSafe: windowsSafe)
    }

    /// Create an archive at an explicit output URL (the path + name the user
    /// confirmed in the save panel). The format is the current Settings default,
    /// regardless of the typed extension.
    func createArchive(_ inputs: [URL], output: URL, password: String?, windowsSafe: Bool) {
        guard !inputs.isEmpty else { return }
        let format = settings.defaultFormat
        let opts = CompressionOptions(level: settings.settings.defaultLevel,
                                      password: password,
                                      threads: 0,
                                      stripMacMetadata: settings.settings.stripMacMetadata,
                                      windowsSafeNames: windowsSafe)
        runJob("Compressing \(inputs.count) item(s) → \(format.displayName)…") { [service] in
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try service.create(output, inputs: inputs, format: format, options: opts)
            return output
        } onSuccess: { [weak self] (out: URL) in
            self?.status = "Created \(out.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
            NSWorkspace.shared.activateFileViewerSelecting([out])
        }
    }

    // MARK: - Job runner

    private func runJob<T: Sendable>(_ label: String,
                                     _ work: @escaping @Sendable () throws -> T,
                                     onSuccess: @escaping (T) -> Void) {
        busy = true; progress = nil; errorMessage = nil; status = label
        Task.detached(priority: .userInitiated) {
            do {
                let result = try work()
                await MainActor.run { onSuccess(result); self.busy = false }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    self.status = "Failed."
                    self.busy = false
                }
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case browse = "Browse"
    case compress = "Compress"
    case queue = "Queue"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .browse: return "doc.zipper"
        case .compress: return "plus.rectangle.on.folder"
        case .queue: return "square.stack.3d.up"
        }
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes); var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(bytes) B" : String(format: "%.1f %@", v, units[i])
    }
}
