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

    /// True when the item's original is reachable as a real file on this Mac — either genuinely local
    /// (local mode) or the server's volume mounted here over SMB (e.g. airy's ROG_AIRY at the same
    /// `/Volumes/ROG_AIRY` path). When so, we play/read the ORIGINAL directly: a network filesystem
    /// streams video far more smoothly than HTTP, with no transcode/proxy needed.
    ///
    /// Answered from `LocalReachability`'s volume cache: this computed property runs during `body`,
    /// and the old direct `FileManager.fileExists` was a network stat per render — and an
    /// indefinite MAIN-THREAD HANG whenever the SMB mount had gone stale mid-session.
    private var localOriginalAvailable: Bool {
        LocalReachability.shared.isReachable(file.filePath)
    }
    /// Audio stream URL: the local original if reachable (incl. over SMB), else PeekServer's `/full`.
    private var streamURL: URL {
        if localOriginalAvailable { return file.fileURL }
        return appState.peekMediaProvider?.fullURL(id: file.id) ?? file.fileURL
    }
    /// Video stream URL: the local original over the (SMB) filesystem when reachable — smooth, no
    /// transcode. Otherwise the `/preview` HTTP proxy (fallback for clients that can't mount the
    /// volume, e.g. iPad).
    private var videoStreamURL: URL {
        if localOriginalAvailable { return file.fileURL }
        return appState.peekMediaProvider?.previewURL(id: file.id) ?? file.fileURL
    }
    private var streamHeaders: [String: String] {
        // Local file → no auth header; remote HTTP → the server's Basic-auth header.
        (localOriginalAvailable ? nil : appState.peekMediaProvider?.httpHeaders) ?? [:]
    }

    @ViewBuilder
    private var content: some View {
        switch file.mediaType {
        case .photo: photoView
        case .video: VideoPlayerView(url: videoStreamURL, headers: streamHeaders).id(file.id)
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
        var loaded: NSImage?
        if localOriginalAvailable {
            // The original is reachable on disk (local, or the server's volume mounted over SMB) —
            // read it directly, no HTTP round-trip.
            let url = file.fileURL
            loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        } else if let provider = appState.peekMediaProvider {
            // Remote: the screen-size /display JPEG (~20× fewer bytes than the original; falls
            // back to /full for pre-0.7 servers), deduped + disk-cached by ThumbnailService.
            loaded = await ThumbnailService.shared.displayImage(for: file, provider: provider)
        }
        // `.task(id:)` cancelled us because the user navigated on — the NEXT item's load owns
        // these @State slots now; writing would blank its spinner/image mid-load.
        guard !Task.isCancelled else { return }
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
