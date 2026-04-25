import SwiftUI

/// On-disk chat log browser. Files under `supportDir/logs/<networkSlug>/
/// <bufferSlug>.log` are AES-GCM-sealed when the keystore is unlocked, so
/// you can't open them in TextEdit. This sheet enumerates whatever buffers
/// are visible in the live connection list, asks the LogStore actor to
/// decrypt the file, and shows the decoded text with search.
///
/// Design notes:
/// - Filenames are SHA-256 slugs so the directory is opaque to disk
///   browsers; we can only resolve a slug back to a friendly name when the
///   buffer (or connection) is currently in memory. Closed channels show
///   only if they're already open in another connection or in the saved
///   buffer list. That's acceptable for the "find an old conversation"
///   use case; recovering names for long-gone buffers is out of scope.
/// - Reading goes through `LogStore.read(network:buffer:)` which handles
///   format detection — encrypted records are decoded on the fly when a
///   key is available, plaintext logs pass through.
struct ChatLogViewerView: View {
    @EnvironmentObject var model: ChatModel
    @Environment(\.dismiss) private var dismiss

    /// One row in the picker — a (network, buffer-name) pair. Identifiable
    /// so SwiftUI can diff the list cleanly. `isLive` distinguishes a buffer
    /// currently in memory (chat is happening) from a historic / offline
    /// entry resolved through the LogStore index.
    struct LogTarget: Identifiable, Hashable {
        let id: String          // "<network>::<buffer>" — unique
        let networkName: String
        let bufferName: String
        let kindLabel: String   // "channel" / "query" / "server" / "archive"
        let isLive: Bool
    }

    @State private var targets: [LogTarget] = []
    @State private var selection: LogTarget.ID?
    @State private var content: String = ""
    @State private var search: String = ""
    @State private var loading: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                targetList
                    .frame(width: 240)
                Divider()
                detailPane
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { rebuildTargetList() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(.secondary)
            Text("Chat logs")
                .font(.headline)
            Spacer()
            Text(model.keyStore.isUnlocked
                 ? "Keystore unlocked — encrypted logs decode on the fly."
                 : "Keystore locked — only plaintext logs will decode.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
    }

    private var targetList: some View {
        List(selection: $selection) {
            if targets.isEmpty {
                Text("No active buffers.\nConnect to a network and join channels to see logs here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(grouped, id: \.network) { group in
                    Section(group.network) {
                        ForEach(group.targets) { t in
                            HStack(spacing: 6) {
                                Image(systemName: iconFor(t.kindLabel))
                                    .foregroundStyle(t.isLive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                                Text(t.bufferName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(t.isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                if !t.isLive {
                                    Text("(archived)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tag(t.id as LogTarget.ID?)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, _ in loadSelected() }
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter lines (case-insensitive)", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(8)
            Divider()
            if loading {
                ProgressView("Decoding…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView(
                    "Couldn't read log",
                    systemImage: "lock.trianglebadge.exclamationmark",
                    description: Text(error)
                )
            } else if content.isEmpty, selection != nil {
                ContentUnavailableView(
                    "No log on disk yet",
                    systemImage: "tray",
                    description: Text("This buffer hasn't recorded any lines. Persistent logging may be off in Setup → Behavior.")
                )
            } else if selection == nil {
                ContentUnavailableView(
                    "Pick a network/buffer on the left",
                    systemImage: "arrow.left",
                    description: Text("Logs decrypt on the fly.")
                )
            } else {
                ScrollView {
                    Text(filteredContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if !content.isEmpty {
                let lineCount = filteredContent.split(separator: "\n",
                                                      omittingEmptySubsequences: false).count
                let totalLines = content.split(separator: "\n",
                                               omittingEmptySubsequences: false).count
                if search.isEmpty {
                    Text("\(totalLines) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(lineCount) of \(totalLines) lines match")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Copy") { copyContent() }
                .disabled(filteredContent.isEmpty)
            Button("Export…") { exportContent() }
                .disabled(filteredContent.isEmpty)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    // MARK: - Helpers

    /// Walk live connections + the LogStore's persistent index. Live entries
    /// keep their buffer kind; entries pulled from the index without a
    /// matching live buffer are tagged "archive" and rendered with a
    /// dimmed icon so the user can tell they're historic.
    private func rebuildTargetList() {
        var liveIDs = Set<String>()
        var out: [LogTarget] = []
        // 1) live connections — most recent state, includes buffer kind.
        for conn in model.connections {
            for buf in conn.buffers {
                let kind: String
                switch buf.kind {
                case .channel: kind = "channel"
                case .query:   kind = "query"
                case .server:  kind = "server"
                }
                let id = "\(conn.displayName)::\(buf.name)"
                liveIDs.insert(id)
                out.append(LogTarget(
                    id: id,
                    networkName: conn.displayName,
                    bufferName: buf.name,
                    kindLabel: kind,
                    isLive: true))
            }
        }
        // 2) historic entries from the LogStore's index. Run async on the
        // actor; reload the table when results arrive. Live IDs already
        // captured above so the indexed pass can skip duplicates.
        let live = liveIDs
        Task { @MainActor in
            let entries = await model.logStore.enumerateIndex()
            var combined = out
            for e in entries {
                let id = "\(e.network)::\(e.buffer)"
                if live.contains(id) { continue }
                combined.append(LogTarget(
                    id: id,
                    networkName: e.network,
                    bufferName: e.buffer,
                    kindLabel: "archive",
                    isLive: false))
            }
            combined.sort { lhs, rhs in
                if lhs.networkName != rhs.networkName {
                    return lhs.networkName.localizedCaseInsensitiveCompare(rhs.networkName) == .orderedAscending
                }
                if lhs.kindLabel != rhs.kindLabel {
                    return Self.kindOrder(lhs.kindLabel) < Self.kindOrder(rhs.kindLabel)
                }
                return lhs.bufferName.localizedCaseInsensitiveCompare(rhs.bufferName) == .orderedAscending
            }
            self.targets = combined
        }
    }

    private static func kindOrder(_ kind: String) -> Int {
        switch kind {
        case "channel": return 0
        case "query":   return 1
        case "server":  return 2
        case "archive": return 3
        default:        return 4
        }
    }

    /// Group targets by network for the sectioned sidebar.
    private struct Group {
        let network: String
        let targets: [LogTarget]
    }
    private var grouped: [Group] {
        var byNetwork: [String: [LogTarget]] = [:]
        for t in targets { byNetwork[t.networkName, default: []].append(t) }
        return byNetwork
            .map { Group(network: $0.key, targets: $0.value) }
            .sorted { $0.network.localizedCaseInsensitiveCompare($1.network) == .orderedAscending }
    }

    private func iconFor(_ kind: String) -> String {
        switch kind {
        case "channel": return "number"
        case "query":   return "person.fill"
        case "server":  return "server.rack"
        case "archive": return "archivebox"
        default:        return "doc.text"
        }
    }

    private var filteredContent: String {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return content }
        let needle = q.lowercased()
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.lowercased().contains(needle) }
            .joined(separator: "\n")
    }

    /// Resolve the selection back to its target and read the log via the
    /// LogStore actor. Errors get surfaced inline rather than thrown.
    private func loadSelected() {
        guard let selection,
              let target = targets.first(where: { $0.id == selection })
        else { return }
        loading = true
        error = nil
        content = ""
        let store = model.logStore
        let network = target.networkName
        let buffer = target.bufferName
        Task { @MainActor in
            let text = await store.read(network: network, buffer: buffer)
            loading = false
            if let text {
                content = text
            } else {
                error = "No log file found for \(network) / \(buffer). Either persistent logging was off when this buffer was active, or the file was rotated/purged."
            }
        }
    }

    private func copyContent() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filteredContent, forType: .string)
        #endif
    }

    /// Save the currently-displayed text to a user-chosen location. Always
    /// plaintext — the whole point of "Export" is to hand-share.
    private func exportContent() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = suggestedFilename()
        panel.title = "Export chat log"
        if panel.runModal() == .OK, let url = panel.url {
            try? filteredContent.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }

    private func suggestedFilename() -> String {
        guard let selection,
              let target = targets.first(where: { $0.id == selection })
        else { return "chatlog.txt" }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let safeNet = target.networkName.replacingOccurrences(of: "/", with: "_")
        let safeBuf = target.bufferName.replacingOccurrences(of: "/", with: "_")
        return "\(safeNet)-\(safeBuf)-\(stamp).txt"
    }
}
