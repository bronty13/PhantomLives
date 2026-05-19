import SwiftUI
import UniformTypeIdentifiers

/// Reusable drag-drop affordance for Purple Import. Accepts any
/// file URL; the wizard's `pickSource` step uses one to let the user
/// drop a CSV / JSON / etc. directly onto the wizard window without
/// going through NSOpenPanel.
struct DropZone: View {
    var prompt: String = "Drop a file here, or click to choose"
    var systemImage: String = "tray.and.arrow.down"
    var onPick: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text(prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [6])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
        .onTapGesture { runOpenPanel() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async { onPick(url) }
                }
            }
            return true
        }
    }

    private func runOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}
