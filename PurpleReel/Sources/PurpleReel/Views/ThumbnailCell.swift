import SwiftUI
import AppKit

/// 80×45 cell that loads its asset's thumbnail strip lazily, shows
/// the middle frame by default, and cycles frames based on cursor X
/// when the mouse hovers over it. Same UX shape Kyno's browser uses.
struct ThumbnailCell: View {
    let asset: Asset

    @State private var urls: [URL] = []
    @State private var loadedImage: NSImage?
    @State private var hoverFraction: Double? = nil   // 0…1 within the cell
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.18))
            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            if hovering, urls.count > 1 {
                // Tiny tick row showing the cursor's mapped frame index.
                GeometryReader { geo in
                    let activeIdx = currentFrameIndex(width: geo.size.width)
                    HStack(spacing: 1) {
                        ForEach(0..<urls.count, id: \.self) { i in
                            Rectangle()
                                .fill(i == activeIdx
                                      ? Color.accentColor
                                      : Color.white.opacity(0.35))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 2)
                    .position(x: geo.size.width / 2, y: geo.size.height - 4)
                }
            }
        }
        .frame(width: 80, height: 45)
        .clipped()
        .onAppear(perform: loadIfNeeded)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovering = true
                hoverFraction = nil   // recomputed via GeometryReader below
                Task { @MainActor in
                    applyHover(x: location.x)
                }
            case .ended:
                hovering = false
                hoverFraction = nil
                // Reset to middle frame on hover exit so the table
                // doesn't keep the last scrubbed frame as the cell's
                // identity.
                if !urls.isEmpty {
                    loadFrame(at: urls.count / 2)
                }
            }
        }
    }

    private func loadIfNeeded() {
        Task {
            let urls = await ThumbnailService.thumbnails(for: asset)
            await MainActor.run {
                self.urls = urls
                if !urls.isEmpty {
                    loadFrame(at: urls.count / 2)
                }
            }
        }
    }

    private func loadFrame(at index: Int) {
        guard index >= 0 && index < urls.count else { return }
        if let img = NSImage(contentsOf: urls[index]) {
            loadedImage = img
        }
    }

    private func applyHover(x: CGFloat) {
        guard !urls.isEmpty else { return }
        let cellWidth: CGFloat = 80
        let clampedX = min(max(0, x), cellWidth)
        let idx = min(urls.count - 1,
                       Int((clampedX / cellWidth) * CGFloat(urls.count)))
        loadFrame(at: idx)
    }

    private func currentFrameIndex(width: CGFloat) -> Int {
        // Used only by the tick overlay; we don't have direct access
        // to the cursor here, so we approximate from the most recent
        // loaded image index. Acceptable since the highlight is a
        // small UX nicety, not load-bearing.
        guard let img = loadedImage,
              let url = urls.first(where: { NSImage(contentsOf: $0)?.tiffRepresentation == img.tiffRepresentation }) else {
            return urls.count / 2
        }
        return Int(url.deletingPathExtension().lastPathComponent) ?? urls.count / 2
    }
}
