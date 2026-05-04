import SwiftUI
import AppKit

/// Visual frame-picker rendered under the "Thumbnail frames" audit row.
/// Renders every captured `<Title>_frame_NN.png` as a small preview tile
/// in a wrapping grid; clicking a tile picks that frame, the selected
/// tile shows a coloured border, and the action row underneath has
/// "Reveal" (open the picked frame in Finder) and "Use as thumbnail"
/// (parent persists the pick — typically by promoting it to
/// `<Title>.png`).
///
/// Picked-frame state is OWNED BY THE PARENT via a `Binding<Int>`. We
/// found that the previous `@State` approach was getting reset across
/// re-audits (SwiftUI sometimes recreates the picker, sometimes reuses
/// it; either way the state behaviour wasn't reliable). Letting the
/// parent own the @State means the value survives every kind of
/// re-render.
struct ThumbnailFramePicker: View {
    let title: String
    let productionFolder: String?
    let foundFrameNumbers: [Int]
    /// Currently-stored thumbnailFilename on the clip (just for display).
    let currentSelection: String?
    @Binding var picked: Int

    /// Called with the new `<Title>_frame_NN.png` when the user clicks
    /// "Use as thumbnail." The parent persists it.
    var onPick: (String) -> Void

    private let tileWidth: CGFloat  = 120
    private let tileHeight: CGFloat = 68

    var body: some View {
        if foundFrameNumbers.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.grid.3x2")
                        .font(.caption).foregroundStyle(.purple)
                    Text("Pick thumbnail frame")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    Text("Frame \(String(format: "%02d", picked)) selected")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth + 20),
                                       spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(foundFrameNumbers, id: \.self) { n in
                        tile(for: n)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if let cur = currentSelection, !cur.isEmpty {
                        Text("Current thumbnail file: \(cur)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        revealPicked()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(pickedPath ?? "")

                    Button {
                        onPick(pickedFilename)
                    } label: {
                        Label("Use as thumbnail", systemImage: "checkmark.seal")
                    }
                    .controlSize(.small)
                    .help("Promote frame \(String(format: "%02d", picked)) to be the canonical `<Title>.png` thumbnail.")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.purple.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - Tile

    private func tile(for n: Int) -> some View {
        let path = framePath(for: n)
        let image = path.flatMap { NSImage(contentsOfFile: $0) }
        let isPicked = (n == picked)
        return VStack(spacing: 2) {
            ZStack {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: tileWidth, height: tileHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.gray.opacity(0.20))
                        .frame(width: tileWidth, height: tileHeight)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .frame(width: tileWidth, height: tileHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isPicked ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isPicked ? 3 : 1)
                    .allowsHitTesting(false)
            )
            Text(String(format: "%02d", n))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isPicked ? Color.accentColor : .secondary)
        }
        .frame(width: tileWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            picked = n
        }
        .help("Click to select frame \(String(format: "%02d", n)).")
    }

    // MARK: - Internals

    private var pickedFilename: String {
        String(format: "%@_frame_%02d.png", title, picked)
    }

    private var pickedPath: String? { framePath(for: picked) }

    private func framePath(for n: Int) -> String? {
        guard let dir = productionFolder, !dir.isEmpty else { return nil }
        let expanded = (dir as NSString).expandingTildeInPath
        let name = String(format: "%@_frame_%02d.png", title, n)
        return (expanded as NSString).appendingPathComponent(name)
    }

    private func revealPicked() {
        guard let p = pickedPath else { return }
        let url = URL(fileURLWithPath: p)
        if FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let dir = productionFolder, !dir.isEmpty {
            let dirURL = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            NSWorkspace.shared.activateFileViewerSelecting([dirURL])
        }
    }

    /// Helper exposed for the parent so seed logic stays consistent
    /// across the sheet and the workflow. Returns the parsed frame
    /// number (1-based) when the filename matches `<title>_frame_NN.png`,
    /// otherwise nil — caller falls back to the lowest found frame.
    static func parseFrameNumber(from filename: String, title: String) -> Int? {
        let prefix = (title + "_frame_").lowercased()
        let lower  = filename.lowercased()
        guard lower.hasPrefix(prefix), lower.hasSuffix(".png") else { return nil }
        let middle = lower.dropFirst(prefix.count).dropLast(".png".count)
        return Int(middle)
    }
}
