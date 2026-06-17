import SwiftUI

/// A single grid cell: thumbnail + filename, overlaid with type / decision / favorite
/// badges. Loads its thumbnail lazily via `.task(id:)` so scrolling cancels off-screen
/// loads automatically.
struct MediaThumbnailCell: View {
    let file: MediaFile
    let isSelected: Bool
    var duplicateCount: Int = 1
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var image: NSImage?
    @State private var didLoad = false

    private let thumbSize = CGSize(width: 160, height: 160)

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(badges, alignment: .topLeading)
                    .overlay(favoriteBadge, alignment: .topTrailing)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? theme.accentColor : Color.clear, lineWidth: 3)
                    )

                Text(file.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 160)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.fileName)
        .task(id: file.id) {
            guard !didLoad else { return }
            didLoad = true
            image = await ThumbnailService.shared.thumbnail(for: file.fileURL, size: thumbSize)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cellBackground)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placeholderSymbol: String {
        switch file.mediaType {
        case .photo: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }

    // MARK: - Badges

    private var badges: some View {
        HStack(spacing: 4) {
            typeBadge
            decisionBadge
            if file.isMissing { missingBadge }
            if duplicateCount > 1 { duplicateBadge }
        }
        .padding(6)
    }

    /// Shown on the one representative of a set of exact duplicates (×N copies).
    private var duplicateBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "doc.on.doc.fill")
            Text("\(duplicateCount)")
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.blue.opacity(0.85), in: Capsule())
        .foregroundStyle(.white)
        .help("\(duplicateCount) identical copies — one decision applies to all")
    }

    /// Shown when a re-scan found the file gone from disk (it may still reappear).
    private var missingBadge: some View {
        Image(systemName: "questionmark.folder")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            .help("This file is missing from disk")
    }

    private var typeBadge: some View {
        Image(systemName: placeholderSymbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var decisionBadge: some View {
        switch file.keepDecision {
        case .some(true):
            badgePill(systemImage: "checkmark", color: .green)
        case .some(false):
            badgePill(systemImage: "xmark", color: .red)
        case .none:
            EmptyView()
        }
    }

    private func badgePill(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var favoriteBadge: some View {
        HStack(spacing: 4) {
            if file.isHidden {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2)
                    .padding(5)
                    .background(.black.opacity(0.45), in: Circle())
                    .foregroundStyle(.white)
            }
            if file.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .padding(5)
                    .background(.black.opacity(0.45), in: Circle())
                    .foregroundStyle(.pink)
            }
        }
        .padding(6)
    }
}
