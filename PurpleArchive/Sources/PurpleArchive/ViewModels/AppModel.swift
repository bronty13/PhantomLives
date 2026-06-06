import Foundation
import SwiftUI

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
    }

    /// Password remembered in the Keychain for the open archive, if any.
    var vaultPassword: String? { openedURL.flatMap { vault.password(for: $0) } }

    func extractOpened(password: String? = nil, remember: Bool = false) {
        guard let url = openedURL else { return }
        // Fall back to a Keychain-remembered password when none was supplied.
        let effective = password ?? vault.password(for: url)
        if remember, let pw = password, !pw.isEmpty { vault.setPassword(pw, for: url) }
        let dest = settings.resolvedExtractRoot
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

    // MARK: - Compress

    func compress(_ inputs: [URL], windowsSafe: Bool = false) {
        compress(inputs, password: nil, windowsSafe: windowsSafe)
    }

    func compressEncrypted(_ inputs: [URL], password: String, windowsSafe: Bool = false) {
        compress(inputs, password: password, windowsSafe: windowsSafe)
    }

    private func compress(_ inputs: [URL], password: String?, windowsSafe: Bool) {
        guard !inputs.isEmpty else { return }
        let format = settings.defaultFormat
        let firstName = inputs.count == 1
            ? inputs[0].deletingPathExtension().lastPathComponent
            : "Archive"
        let out = settings.resolvedExtractRoot
            .appendingPathComponent("\(firstName).\(format.preferredExtension)")
        let opts = CompressionOptions(level: settings.settings.defaultLevel,
                                      password: password,
                                      threads: 0,
                                      stripMacMetadata: settings.settings.stripMacMetadata,
                                      windowsSafeNames: windowsSafe)
        runJob("Compressing \(inputs.count) item(s) → \(format.displayName)…") { [service] in
            try FileManager.default.createDirectory(
                at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try service.create(out, inputs: inputs, format: format, options: opts)
            return out
        } onSuccess: { [weak self] (out: URL) in
            self?.status = "Created \(out.lastPathComponent)"
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
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .browse: return "doc.zipper"
        case .compress: return "plus.rectangle.on.folder"
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
