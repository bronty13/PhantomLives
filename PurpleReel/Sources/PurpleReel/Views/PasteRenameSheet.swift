import SwiftUI
import AppKit

/// "Paste with rename" — Kyno 1.6 parity (row 18). Picks file
/// URLs off the system pasteboard (copied from Finder or another
/// PurpleReel window), applies a token-based naming template, and
/// copies them into a chosen destination folder.
///
/// Token engine reuses `BatchRenameService.expandForPaste` so the
/// rename pipeline is shared with the existing batch-rename flow.
/// Catalog-derived tokens (`{codec}`, `{fps}`, `{w}`, etc.) stay
/// literal because the pasted files aren't catalogued yet — the
/// user sees them in the preview and knows to use URL-only tokens
/// like `{date}` / `{counter}` / `{orig}`.
struct PasteRenameSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pastedURLs: [URL] = []
    @State private var dest: URL?
    @State private var template: String = "{date}_{orig}{ext}"
    @State private var startCounter: Int = 1
    @State private var status: String = ""
    @State private var working: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            sourceRow
            destRow
            templateRow
            Divider()
            previewSection
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .onAppear(perform: refreshPasteboard)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Paste & Rename")
                .font(.title3.weight(.semibold))
            Text("Copy files from the pasteboard into a destination folder, applying a naming template. Source URLs are read from the clipboard at sheet open.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourceRow: some View {
        HStack(spacing: 8) {
            Text("From clipboard:")
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(pastedURLs.isEmpty
                  ? "No file URLs on the clipboard."
                  : "\(pastedURLs.count) file(s)")
                .foregroundStyle(pastedURLs.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Re-read") { refreshPasteboard() }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var destRow: some View {
        HStack(spacing: 8) {
            Text("To:")
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(dest?.path ?? "—")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(dest == nil ? .secondary : .primary)
            Spacer()
            Button("Choose…") { pickDestination() }
        }
    }

    @ViewBuilder
    private var templateRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Template:")
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                TextField("", text: $template)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Text("Counter from:")
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                Stepper(value: $startCounter, in: 1...9999) {
                    Text("\(startCounter)")
                }
                Spacer()
                Text("Tokens: {orig} {ext} {date} {date:yyyyMMdd} {counter} {counter:04}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if pastedURLs.isEmpty {
            Text("Copy media files in Finder (⌘C), then return to this sheet — the URLs will show up under \"From clipboard\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(pastedURLs.enumerated()), id: \.element) { idx, url in
                            let renamed = BatchRenameService.expandForPaste(
                                template: template, url: url,
                                counter: startCounter + idx
                            )
                            HStack(spacing: 8) {
                                Text(url.lastPathComponent)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(renamed)
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        if !status.isEmpty {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Paste") { runPaste() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(pastedURLs.isEmpty || dest == nil || working)
        }
    }

    // MARK: - Actions

    /// Pull file URLs off `NSPasteboard.general`. Both NSURLs and
    /// raw `.fileURL` strings are accepted so Finder's clipboard
    /// format works as well as a SwiftUI cell that wrote `[URL]`.
    private func refreshPasteboard() {
        let pb = NSPasteboard.general
        var urls: [URL] = []
        if let nsURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls.append(contentsOf: nsURLs)
        }
        // Filter to file URLs that actually exist — discards
        // http(s) URLs, file URLs whose target was moved, etc.
        let fm = FileManager.default
        pastedURLs = urls.filter { $0.isFileURL && fm.fileExists(atPath: $0.path) }
        status = ""
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            dest = url
        }
    }

    private func runPaste() {
        guard let dst = dest else { return }
        working = true
        Task {
            let fm = FileManager.default
            var copied = 0
            var skipped = 0
            for (idx, src) in pastedURLs.enumerated() {
                let renamed = BatchRenameService.expandForPaste(
                    template: template, url: src,
                    counter: startCounter + idx
                )
                let target = dst.appendingPathComponent(renamed)
                if fm.fileExists(atPath: target.path) {
                    skipped += 1
                    continue
                }
                do {
                    try fm.copyItem(at: src, to: target)
                    copied += 1
                } catch {
                    NSLog("[PurpleReel] paste-rename copy failed for \(src.path): \(error)")
                    skipped += 1
                }
            }
            await MainActor.run {
                status = "Copied \(copied) file(s); skipped \(skipped)."
                working = false
                if copied > 0 {
                    // Kick a workspace rescan so the new files show
                    // up in the catalogue right away.
                    Task { await appState.rescan() }
                    dismiss()
                }
            }
        }
    }
}
