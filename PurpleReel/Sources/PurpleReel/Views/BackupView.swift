import SwiftUI
import AppKit

struct BackupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var source: URL?
    @State private var destinations: [URL] = []
    @State private var algorithm: HashAlgorithm = .sha1
    /// MHL output format. Defaults to legacy v1.1 because every DIT
    /// tool reads it; ASC-MHL v2.0 is the Netflix-spec option.
    @State private var mhlFormat: MHLFormat = .legacy
    @State private var runningJob: BackupJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    configurationSection
                    if let job = runningJob {
                        progressSection(job: job)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Verified Backup")
                .font(.title2.bold())
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Source
            VStack(alignment: .leading, spacing: 4) {
                Text("Source folder").font(.headline)
                HStack {
                    Text(source?.path ?? "Choose a source folder…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(source == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") { pickSource() }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Destinations
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Destinations").font(.headline)
                    Text("(up to 4)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        pickDestination()
                    } label: {
                        Label("Add Destination", systemImage: "plus")
                    }
                    .disabled(destinations.count >= 4)
                }
                if destinations.isEmpty {
                    Text("Choose at least one destination folder.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(8)
                } else {
                    ForEach(Array(destinations.enumerated()), id: \.offset) { idx, dst in
                        HStack {
                            Image(systemName: "\(idx + 1).circle.fill")
                                .foregroundStyle(.tint)
                            Text(dst.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                destinations.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08),
                                     in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Algorithm
            VStack(alignment: .leading, spacing: 4) {
                Text("Hash algorithm").font(.headline)
                Picker("", selection: $algorithm) {
                    ForEach(HashAlgorithm.allCases) { algo in
                        Text(algo.rawValue).tag(algo)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: algorithm) { _, new in
                    // C4 requires the ASC-MHL writer; legacy MHL
                    // v1.1 doesn't know the c4 element. Switch the
                    // format implicitly so the user can't ship a
                    // manifest with `<c4>` inside a v1.1 hashlist.
                    if !new.legacyMHLCompatible {
                        mhlFormat = .ascMHL
                    }
                }
                Text(algorithmHelpText)
                    .font(.caption).foregroundStyle(.secondary)
            }

            // MHL output format
            VStack(alignment: .leading, spacing: 4) {
                Text("MHL format").font(.headline)
                Picker("", selection: $mhlFormat) {
                    ForEach(MHLFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!algorithm.legacyMHLCompatible)
                Text(mhlFormatHelpText)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var algorithmHelpText: String {
        switch algorithm {
        case .sha1:   return "SHA-1 — the MHL v1.1 default; ubiquitous DIT-tool compatibility."
        case .md5:    return "MD5 — fastest, but cryptographically weakest. Use only for self-audit."
        case .sha256: return "SHA-256 — modern, widely supported."
        case .c4:     return "C4 ID — SHA-512 base58-encoded; required for Netflix Originals delivery alongside ASC-MHL."
        }
    }
    private var mhlFormatHelpText: String {
        switch mhlFormat {
        case .legacy: return "ASC Media Hash List v1.1 (.mhl) — the long-standing DIT format."
        case .ascMHL: return "ASC-MHL v2.0 (.ascmhl) — the Netflix Originals-mandated successor."
        }
    }

    private func progressSection(job: BackupJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("Progress").font(.headline)
                Spacer()
                if job.isRunning {
                    ProgressView().controlSize(.small)
                }
                Text(progressSummary(job: job))
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(job.items) { item in
                BackupFileRow(item: item)
            }

            if !job.summary.isEmpty {
                Text(job.summary)
                    .font(.callout)
                    .padding(.top, 8)
            }
            if !job.mhlPaths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wrote MHL manifests:").font(.caption)
                    ForEach(job.mhlPaths, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(url.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Start Backup") { startBackup() }
                .keyboardShortcut(.defaultAction)
                .disabled(source == nil || destinations.isEmpty || runningJob?.isRunning == true)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func pickSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { source = panel.url }
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !destinations.contains(url) { destinations.append(url) }
        }
    }

    private func startBackup() {
        guard let source else { return }
        let job = BackupJob(source: source, destinations: destinations,
                             algorithm: algorithm,
                             mhlFormat: mhlFormat)
        runningJob = job
        Task {
            await VerifiedBackupService.run(job: job, toolVersion: AppVersion.marketing)
        }
    }

    private func progressSummary(job: BackupJob) -> String {
        let total = job.items.count
        let done = job.items.filter {
            if case .done = $0.state { return true }
            return false
        }.count
        let failed = job.items.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
        return "\(done)/\(total) verified" + (failed > 0 ? " · \(failed) failed" : "")
    }
}

private struct BackupFileRow: View {
    @ObservedObject var item: BackupFileItem

    var body: some View {
        HStack(spacing: 8) {
            stateIcon
            Text(item.relativePath)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(stateLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .queued:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .hashing:
            Image(systemName: "number.square").foregroundStyle(.tint)
        case .copying:
            Image(systemName: "arrow.right.doc.on.clipboard").foregroundStyle(.tint)
        case .verifying:
            Image(systemName: "checkmark.shield").foregroundStyle(.tint)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            // C37 — distinct from .failed so the row renders as
            // "user-stopped" rather than "broken at verify".
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .queued: return "queued"
        case .hashing(let bytes):
            return "hashing \(format(bytes))"
        case .copying: return "copying"
        case .verifying(let dst): return "verifying → \(dst.lastPathComponent)"
        case .done: return "done"
        case .failed(let msg): return msg
        case .cancelled: return "cancelled"
        }
    }

    private func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
