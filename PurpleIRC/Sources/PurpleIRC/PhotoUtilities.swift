import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

/// Photo helpers used by the address-book profile photo feature.
/// Images are downscaled and JPEG-encoded on import so the inline
/// storage in `settings.json` stays compact (typically 8–20 KB per
/// photo even when the user picks a 4K JPEG).
enum PhotoUtilities {

    /// Maximum dimension (width or height) any imported photo is
    /// scaled down to. 256 px gives a crisp 128 pt avatar on Retina
    /// without ballooning the per-entry storage. Bigger profile-card
    /// renderings (Phase 8 / contact-card sheets) re-upsample with
    /// SwiftUI interpolation; lossless detail past 256 px isn't worth
    /// the file weight.
    static let maxDimension: CGFloat = 256

    /// JPEG quality used when re-encoding scaled-down images. 0.85
    /// balances visual fidelity with file size — under 0.7 visible
    /// chroma subsampling artifacts start to appear on faces.
    static let jpegQuality: NSNumber = 0.85

    /// Read a file URL and produce a downscaled JPEG-encoded `Data`
    /// blob suitable for `AddressEntry.photoData`. Returns nil on
    /// I/O failure or when the data isn't a recognisable image.
    static func loadDownscaled(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return nil }
        return downscaleAndEncode(image)
    }

    /// Downscale `image` to at most `maxDimension` px on its longest
    /// side, then re-encode as JPEG. Single-step pipeline — accepts
    /// any NSImage, returns base64-friendly Data. Pure function;
    /// safe to call off-main.
    static func downscaleAndEncode(_ image: NSImage) -> Data? {
        let scaled = downscale(image, to: maxDimension)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: jpegQuality]
        )
    }

    /// Render `image` into a new NSImage no bigger than `maxDim` on
    /// its longer side, preserving aspect ratio. No-op when the source
    /// already fits. Uses `NSImage.draw(in:from:operation:fraction:)`
    /// so the OS picks an appropriate interpolation for the size delta.
    static func downscale(_ image: NSImage, to maxDim: CGFloat) -> NSImage {
        let originalSize = image.size
        let longest = max(originalSize.width, originalSize.height)
        guard longest > maxDim, longest > 0 else { return image }
        let scale = maxDim / longest
        let target = NSSize(width: round(originalSize.width * scale),
                            height: round(originalSize.height * scale))
        let result = NSImage(size: target)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// Initials fallback for a nick. Picks the first alphanumeric
    /// character (uppercased), or "?" when the nick has none.
    static func initials(for nick: String) -> String {
        let trimmed = nick.trimmingCharacters(in: .whitespaces)
        for ch in trimmed where ch.isLetter || ch.isNumber {
            return String(ch).uppercased()
        }
        return "?"
    }

    /// Deterministic accent colour from a nick — used as the circle
    /// background for the initials fallback so avatars are visually
    /// distinct even when no photo is attached. Picks from a small
    /// curated palette via `SHA256(nick).first byte mod count` so
    /// the same nick always lands on the same swatch.
    static func avatarTint(for nick: String) -> Color {
        let palette: [Color] = [
            .purple, .blue, .indigo, .teal, .mint,
            .green, .yellow, .orange, .red, .pink, .brown
        ]
        let key = nick.lowercased()
        let digest = SHA256.hash(data: Data(key.utf8))
        // SHA256Digest is iterable but its `.first` returns the curried
        // `first(where:)` method, not the leading byte; reify to an
        // Array so the simple subscript is unambiguous.
        let bytes = Array(digest)
        let byte = bytes.first ?? 0
        return palette[Int(byte) % palette.count]
    }
}

/// Round avatar suitable for the sidebar contacts row, the address-book
/// editor, and the contact-card hover preview. Renders the entry's
/// `photoData` when present, otherwise a deterministic-tinted circle
/// with the nick's first letter.
///
/// One control: the `size` (the diameter in points). Everything else —
/// crop, font weight inside the initials placeholder — scales relative
/// to that, so the same view works at 18 pt (sidebar) and 96 pt
/// (contact card sheet) without per-call configuration.
struct ContactAvatar: View {
    let entry: AddressEntry
    /// Diameter in points. Initials font scales at ~50% of this.
    let size: CGFloat

    var body: some View {
        Group {
            if let data = entry.photoData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            Circle().fill(PhotoUtilities.avatarTint(for: entry.nick).gradient)
            Text(PhotoUtilities.initials(for: entry.nick))
                .font(.system(size: max(8, size * 0.46), weight: .semibold,
                              design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// Convenience helper that shares an avatar-by-nick lookup against the
/// settings store, so views that have a nick (but no AddressEntry)
/// can still get the right avatar (or the placeholder fallback).
struct ContactAvatarByNick: View {
    @ObservedObject var settings: SettingsStore
    let nick: String
    let size: CGFloat

    var body: some View {
        let lower = nick.lowercased()
        if let entry = settings.settings.addressBook
            .first(where: { $0.nick.lowercased() == lower }) {
            ContactAvatar(entry: entry, size: size)
        } else {
            // Synthesise an empty entry so the placeholder still
            // gets the deterministic tint + initial. Keeps the same
            // visual identity for nicks that aren't in the address
            // book yet.
            ContactAvatar(
                entry: AddressEntry(nick: nick, watch: false),
                size: size
            )
        }
    }
}
