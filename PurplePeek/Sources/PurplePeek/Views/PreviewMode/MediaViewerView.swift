import SwiftUI
import AVKit

/// The large viewer in Preview mode. Switches on media type: a fit-to-frame image for
/// photos, an inline `AVPlayerView` for video, and a waveform backdrop + audio transport
/// for audio.
struct MediaViewerView: View {
    let file: MediaFile
    @Environment(\.appTheme) private var theme
    @State private var image: NSImage?
    @State private var loading = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        switch file.mediaType {
        case .photo: photoView
        case .video: VideoPlayerView(url: file.fileURL).id(file.id)
        case .audio: audioView
        }
    }

    // MARK: - Photo

    private var photoView: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: "photo").font(.system(size: 60, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .task(id: file.id) { await loadImage() }
    }

    private func loadImage() async {
        loading = true
        image = nil
        let url = file.fileURL
        let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        image = loaded
        loading = false
    }

    // MARK: - Audio

    private var audioView: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.system(size: 90, weight: .thin))
                .foregroundStyle(theme.accentColor)
                .symbolEffect(.pulse, options: .repeating)
            Text(file.fileName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            VideoPlayerView(url: file.fileURL)
                .id(file.id)
                .frame(height: 44)
                .frame(maxWidth: 420)
        }
        .padding(40)
    }
}

/// `AVPlayerView` wrapped for SwiftUI. Rebuilds the player only when the URL actually
/// changes (compared by asset URL) so re-renders don't reset playback.
struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentURL != url {
            nsView.player?.pause()
            nsView.player = AVPlayer(url: url)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
    }
}
