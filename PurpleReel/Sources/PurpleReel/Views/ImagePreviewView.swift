import SwiftUI
import AppKit

/// Minimal still-image viewer used in the browser detail pane (and in
/// `ClipDetailSheet`'s preview) when the selected asset is an image.
/// Loads the file on appear / path change, scales to fit a black
/// frame, and exposes nothing beyond display — markers / subclips /
/// LUT all live in the video player path.
struct ImagePreviewView: View {
    let asset: Asset

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Loading image…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onChange(of: asset.path) { _, _ in load() }
    }

    private func load() {
        image = nil
        Task.detached(priority: .userInitiated) {
            let img = NSImage(contentsOf: URL(fileURLWithPath: asset.path))
            await MainActor.run { self.image = img }
        }
    }
}

/// Helper: is this asset an image we should preview as a still
/// rather than feeding to AVPlayer?
enum MediaKind {
    case video, image, audio, unknown

    static func of(asset: Asset) -> MediaKind {
        let ext = (asset.filename as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "tif", "tiff", "gif", "bmp", "webp"]
            .contains(ext) { return .image }
        if ["mov", "mp4", "m4v", "qt", "mxf", "avi", "mkv", "webm"]
            .contains(ext) { return .video }
        if ["wav", "aif", "aiff", "mp3", "m4a", "flac", "caf", "ogg"]
            .contains(ext) { return .audio }
        return .unknown
    }
}
