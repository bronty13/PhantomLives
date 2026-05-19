import SwiftUI
import AppKit

/// 80×45 cell that loads its asset's thumbnail strip lazily, shows
/// the middle frame by default, and cycles frames based on cursor X
/// when the mouse hovers over it. Same UX shape Kyno's browser uses.
struct ThumbnailCell: View {
    let asset: Asset
    /// Drives the offline-fade + cloud-slash overlay (Kyno-parity
    /// row 57). Parent decides — SwiftUI Table column closures
    /// don't reliably propagate `@EnvironmentObject` on macOS, so
    /// passing it in explicitly avoids a crash when the row body
    /// renders without AppState in its environment chain.
    var isOnline: Bool = true

    @State private var urls: [URL] = []
    @State private var loadedImage: NSImage?
    @State private var hoverFraction: Double? = nil   // 0…1 within the cell
    @State private var hovering = false
    /// Most-recently-loaded frame index (0..<urls.count). Used by the
    /// tick-row highlight and by the SMPTE tooltip so they don't have
    /// to round-trip through `tiffRepresentation` comparisons.
    @State private var activeIdx: Int = 0
    /// Cached poster-frame image when the asset has a user-set
    /// poster override (P key). Used as the at-rest cell frame and
    /// when hover ends, so the cell snaps back to the user's pick.
    @State private var posterImage: NSImage?

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
            if !isOnline {
                // Offline overlay — semi-opaque tint + corner badge.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.35))
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.white.opacity(0.9))
                    .font(.system(size: 14))
            }
            if hovering, urls.count > 1 {
                // Tiny tick row showing the cursor's mapped frame index.
                GeometryReader { geo in
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
                if let tc = hoverTimecode {
                    Text(tc)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.65),
                                     in: RoundedRectangle(cornerRadius: 2))
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .top)
                }
            }
        }
        .frame(width: 80, height: 45)
        .clipped()
        .onAppear(perform: loadIfNeeded)
        .onChange(of: asset.posterFrameSeconds) { _, _ in reloadPoster() }
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
                // Reset on hover exit: prefer the user's poster
                // pick (P key) over the auto-mid frame, so the
                // table reads the cell as the user's chosen frame
                // at rest.
                if let poster = posterImage {
                    loadedImage = poster
                } else if !urls.isEmpty {
                    loadFrame(at: urls.count / 2)
                }
            }
        }
    }

    private func loadIfNeeded() {
        Task {
            let urls = await ThumbnailService.thumbnails(for: asset)
            // Resolve the user's poster-frame override (P key) in
            // parallel — falls back to mid-strip when nil.
            var poster: NSImage? = nil
            if let secs = asset.posterFrameSeconds,
               let pURL = await ThumbnailService.posterFrame(for: asset, seconds: secs) {
                poster = NSImage(contentsOf: pURL)
            }
            await MainActor.run {
                self.urls = urls
                self.posterImage = poster
                if let poster {
                    self.loadedImage = poster
                } else if !urls.isEmpty {
                    loadFrame(at: urls.count / 2)
                }
            }
        }
    }

    /// Re-resolve the poster frame after the user has changed it
    /// (P / ⇧P). Doesn't touch the hover-scrub strip.
    private func reloadPoster() {
        Task {
            var poster: NSImage? = nil
            if let secs = asset.posterFrameSeconds,
               let pURL = await ThumbnailService.posterFrame(for: asset, seconds: secs) {
                poster = NSImage(contentsOf: pURL)
            }
            await MainActor.run {
                self.posterImage = poster
                if !hovering {
                    if let poster {
                        loadedImage = poster
                    } else if !urls.isEmpty {
                        loadFrame(at: urls.count / 2)
                    }
                }
            }
        }
    }

    private func loadFrame(at index: Int) {
        guard index >= 0 && index < urls.count else { return }
        activeIdx = index
        if let img = NSImage(contentsOf: urls[index]) {
            loadedImage = img
        }
    }

    private func applyHover(x: CGFloat) {
        guard !urls.isEmpty else { return }
        let cellWidth: CGFloat = 80
        let clampedX = min(max(0, x), cellWidth)
        let frac = clampedX / cellWidth
        hoverFraction = Double(frac)
        let idx = min(urls.count - 1,
                       Int(frac * CGFloat(urls.count)))
        loadFrame(at: idx)
    }

    /// SMPTE-formatted clip-time at the hovered fraction, e.g.
    /// "00:01:23:15". nil when we don't have duration or fps yet
    /// (image assets, or strip not yet loaded).
    private var hoverTimecode: String? {
        guard let frac = hoverFraction,
              let dur = asset.durationSeconds, dur > 0 else { return nil }
        let fps = asset.frameRate ?? 30.0
        return Timecode.format(seconds: dur * frac, fps: fps)
    }
}
