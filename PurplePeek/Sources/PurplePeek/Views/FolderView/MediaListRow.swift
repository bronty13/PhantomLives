import SwiftUI

/// A compact list-mode row: small thumbnail + filename + path-tail + decision/favorite
/// glyphs. Shares `ThumbnailService` with the grid.
struct MediaListRow: View {
    let file: MediaFile
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var image: NSImage?
    @State private var didLoad = false

    private let thumbSize = CGSize(width: 48, height: 48)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName).lineLimit(1)
                    Text(file.mediaType.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if file.isFavorite {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
                decisionGlyph
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isSelected ? theme.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: file.id) {
            guard !didLoad else { return }
            didLoad = true
            image = await ThumbnailService.shared.thumbnail(for: file.fileURL, size: thumbSize)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(theme.cellBackground)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: file.mediaType == .video ? "film" : (file.mediaType == .audio ? "waveform" : "photo"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var decisionGlyph: some View {
        switch file.keepDecision {
        case .some(true):  Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(false): Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .none:        Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}
