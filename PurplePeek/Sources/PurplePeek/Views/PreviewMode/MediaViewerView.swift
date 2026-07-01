import SwiftUI
import AVKit

/// The large viewer in Preview mode. Switches on media type: a fit-to-frame image for
/// photos, an inline `AVPlayerView` for video, and a waveform backdrop + audio transport
/// for audio.
struct MediaViewerView: View {
    let file: MediaFile
    @EnvironmentObject private var appState: AppState
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

    /// Video/audio stream URL + headers: PeekServer's `/full/<id>` (Range-aware, auth header) in
    /// remote mode, else the local file URL.
    private var streamURL: URL {
        appState.peekMediaProvider?.fullURL(id: file.id) ?? file.fileURL
    }
    private var streamHeaders: [String: String] {
        appState.peekMediaProvider?.httpHeaders ?? [:]
    }

    @ViewBuilder
    private var content: some View {
        switch file.mediaType {
        case .photo: photoView
        case .video: VideoPlayerView(url: streamURL, headers: streamHeaders).id(file.id)
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
        if let provider = appState.peekMediaProvider {
            // Remote: fetch the original bytes over HTTP (the file isn't on this Mac).
            var req = URLRequest(url: provider.fullURL(id: file.id))
            for (k, v) in provider.httpHeaders { req.setValue(v, forHTTPHeaderField: k) }
            let data = try? await URLSession.shared.data(for: req).0
            image = data.flatMap(NSImage.init(data:))
        } else {
            let url = file.fileURL
            image = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        }
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
            VideoPlayerView(url: streamURL, headers: streamHeaders)
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
    var headers: [String: String] = [:]

    /// Build a player whose asset carries HTTP headers (so PeekServer's Basic-auth `/full` stream
    /// authenticates). AVFoundation streams it with Range requests for scrubbing.
    private func makePlayer() -> AVPlayer {
        if headers.isEmpty { return AVPlayer(url: url) }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        return AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = makePlayer()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentURL != url {
            nsView.player?.pause()
            nsView.player = makePlayer()
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
    }
}
