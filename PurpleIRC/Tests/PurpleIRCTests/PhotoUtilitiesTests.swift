import Foundation
import AppKit
import SwiftUI
import Testing
@testable import PurpleIRC

@Suite("PhotoUtilities — downscale, initials, tint")
struct PhotoUtilitiesTests {

    // MARK: - initials(for:)

    @Test func initialsPicksFirstLetter() {
        #expect(PhotoUtilities.initials(for: "alice") == "A")
        #expect(PhotoUtilities.initials(for: "Alice") == "A")
    }

    @Test func initialsSkipsLeadingNonAlphanumerics() {
        #expect(PhotoUtilities.initials(for: "_alice") == "A")
        #expect(PhotoUtilities.initials(for: "@!#bob") == "B")
        #expect(PhotoUtilities.initials(for: "  carol") == "C")
    }

    @Test func initialsAcceptsLeadingDigit() {
        #expect(PhotoUtilities.initials(for: "1337") == "1")
    }

    @Test func initialsFallsBackToQuestionMark() {
        #expect(PhotoUtilities.initials(for: "") == "?")
        #expect(PhotoUtilities.initials(for: "@@@") == "?")
        #expect(PhotoUtilities.initials(for: "   ") == "?")
    }

    // MARK: - avatarTint(for:)

    /// Reduce a SwiftUI Color to a stable `(r, g, b)` triplet via the
    /// sRGB color space. SwiftUI Color's own `==` returns identity for
    /// catalog-wrapped colors (each call mints a fresh wrapper even
    /// for the same underlying values), so component comparison is
    /// the only reliable equality test.
    private func components(_ color: Color) -> [Int] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return [
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255)),
        ]
    }

    @Test func avatarTintIsDeterministic() {
        let a1 = PhotoUtilities.avatarTint(for: "alice")
        let a2 = PhotoUtilities.avatarTint(for: "alice")
        // Same nick → same tint, every time.
        #expect(components(a1) == components(a2))
    }

    @Test func avatarTintIsCaseInsensitive() {
        let lower = PhotoUtilities.avatarTint(for: "alice")
        let upper = PhotoUtilities.avatarTint(for: "ALICE")
        #expect(components(lower) == components(upper))
    }

    @Test func avatarTintDiffersAcrossNicks() {
        // Rather than hand-pick non-colliding nicks (brittle), assert
        // "at least 3 distinct colors across 10 arbitrary nicks" —
        // far weaker than the spec but enough to catch a degenerate
        // "always returns purple" regression.
        let nicks = ["alice", "bob", "carol", "dave", "eve",
                     "frank", "grace", "heidi", "ivan", "judy"]
        let colorSets = Set(nicks.map { components(PhotoUtilities.avatarTint(for: $0)) })
        #expect(colorSets.count >= 3)
    }

    // MARK: - downscale(_:to:)

    @Test func downscaleNoOpForSmallImage() {
        let img = NSImage(size: NSSize(width: 100, height: 100))
        let out = PhotoUtilities.downscale(img, to: 256)
        #expect(out.size.width == 100)
        #expect(out.size.height == 100)
    }

    @Test func downscaleShrinksLargeImagePreservingAspect() {
        // Synthesise a 2000×1000 image and downscale to 256.
        let img = NSImage(size: NSSize(width: 2000, height: 1000))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()

        let out = PhotoUtilities.downscale(img, to: 256)
        #expect(out.size.width == 256)
        #expect(out.size.height == 128)   // aspect ratio 2:1 preserved
    }

    @Test func downscaleHandlesPortraitOrientation() {
        let img = NSImage(size: NSSize(width: 1000, height: 2000))
        img.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()

        let out = PhotoUtilities.downscale(img, to: 256)
        #expect(out.size.width == 128)
        #expect(out.size.height == 256)
    }

    @Test func downscaleSafeForZeroSizedImage() {
        let img = NSImage(size: .zero)
        let out = PhotoUtilities.downscale(img, to: 256)
        // No crash; returns the (zero-sized) image as-is.
        #expect(out.size == .zero)
    }

    // MARK: - downscaleAndEncode

    @Test func downscaleAndEncodeProducesDecodableJPEG() {
        let img = NSImage(size: NSSize(width: 800, height: 600))
        img.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()

        guard let data = PhotoUtilities.downscaleAndEncode(img) else {
            Issue.record("downscaleAndEncode returned nil"); return
        }
        // The encoded payload is a real JPEG that decodes back into
        // an NSImage with the downscaled dimensions.
        let roundTrip = NSImage(data: data)
        #expect(roundTrip != nil)
        #expect((roundTrip?.size.width ?? 0) <= PhotoUtilities.maxDimension)
        #expect((roundTrip?.size.height ?? 0) <= PhotoUtilities.maxDimension)
    }

    @Test func downscaledPhotoIsCompactForReasonablePhoto() {
        // A typical 1024×768 photo should compress under 50 KB
        // after the downscale + JPEG re-encode pass — keeps
        // settings.json from bloating with hundreds of contacts.
        let img = NSImage(size: NSSize(width: 1024, height: 768))
        img.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()

        guard let data = PhotoUtilities.downscaleAndEncode(img) else {
            Issue.record("downscaleAndEncode returned nil"); return
        }
        #expect(data.count < 50_000, "encoded \(data.count) bytes")
    }

    // MARK: - loadDownscaled(from:)

    @Test func loadDownscaledReturnsNilForMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).jpg")
        let data = PhotoUtilities.loadDownscaled(from: url)
        #expect(data == nil)
    }

    @Test func loadDownscaledReturnsNilForNonImageFile() throws {
        // Write a tiny text file and try to load it as an image.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-image-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = PhotoUtilities.loadDownscaled(from: url)
        #expect(data == nil)
    }
}
