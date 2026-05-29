import SwiftUI
import UniformTypeIdentifiers

/// Empty-state landing pane. Big drag-and-drop target plus the shared
/// `ProcessingPanel` (preset bar + console knobs + toggles), so the
/// user can configure the run before queuing anything.
struct DropZoneView: View {
    @EnvironmentObject var queue: ProcessingQueue
    @EnvironmentObject var settings: SettingsStore
    @State private var isTargeted: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                dropTarget
                    .frame(maxWidth: 560, maxHeight: 240)
                ProcessingPanel()
                    .frame(maxWidth: 560)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var dropTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2,
                                                 dash: [8, 6]))
                .foregroundStyle(isTargeted
                                 ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text("Drop audio or video here")
                    .font(.title3)
                Text("m4a · mp3 · wav · mp4 · mov · aif · aac · caf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 220)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted
                      ? Color.accentColor.opacity(0.06)
                      : Color.secondary.opacity(0.04))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            queue.ingest(urls: collected, settings: settings)
        }
        return !providers.isEmpty
    }
}
