import SwiftUI
import UniformTypeIdentifiers

/// Reusable drag-drop affordance for Purple Import. Accepts any
/// single file URL — Purple Import infers the source format from the
/// extension after the pick, so it would be hostile to filter at the
/// drop / NSOpenPanel layer (the user can pick the wrong format up
/// top and still drag a "right" file in). Multi-file drops and
/// directories are still rejected with a friendly inline message.
struct DropZone: View {
    var prompt: String = "Drop a file here, or click to choose"
    var systemImage: String = "tray.and.arrow.down"

    var onPick: (URL) -> Void

    @State private var isTargeted = false
    @State private var rejectionMessage: String?
    @State private var rejectionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text(prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Click to browse")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let msg = rejectionMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(borderFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .foregroundStyle(borderStroke)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { runOpenPanel() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if providers.count > 1 {
            showRejection("Drop only one file at a time.")
            return false
        }
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                if isDirectory(url) {
                    showRejection("Drop a file, not a folder.")
                    return
                }
                rejectionMessage = nil
                rejectionTask?.cancel()
                onPick(url)
            }
        }
        return true
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func showRejection(_ message: String) {
        rejectionTask?.cancel()
        rejectionMessage = message
        rejectionTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled {
                await MainActor.run { rejectionMessage = nil }
            }
        }
    }

    // MARK: - Click-to-open fallback

    private func runOpenPanel() {
        // Deliberately unfiltered. macOS doesn't ship a UTType
        // registration for every extension Purple Import understands
        // (`UTType(filenameExtension: "xlsx")` notoriously returns
        // nil on some installs, which then filters .xlsx files out
        // of the open panel entirely — the symptom that motivated
        // removing this gate). Format inference happens after the
        // pick.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    // MARK: - Color helpers

    private var borderFill: Color {
        if rejectionMessage != nil { return Color.orange.opacity(0.06) }
        return isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04)
    }

    private var borderStroke: Color {
        if rejectionMessage != nil { return Color.orange }
        return isTargeted ? Color.accentColor : Color.secondary.opacity(0.4)
    }
}
