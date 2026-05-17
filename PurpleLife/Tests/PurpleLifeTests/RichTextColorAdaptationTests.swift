import AppKit
import XCTest
@testable import PurpleLife

/// Locks the contract that `NSAttributedString.fromRTFData` adapts
/// AppKit's RTF-encoder-baked pure-black foregroundColor to a dynamic
/// `NSColor.labelColor`, while preserving intentional user-picked
/// colors. The symptom this guards against: black-on-dark invisible
/// text in the Notes editor when content arrives via an RTF round
/// trip from a plain string.
final class RichTextColorAdaptationTests: XCTestCase {

    /// `NSAttributedString(string: "...")` → encode to RTF → decode.
    /// AppKit's encoder produces an RTF blob whose decoded form has no
    /// foregroundColor attribute (proven empirically). Our adaptation
    /// adds `NSColor.labelColor` to every range that lacks one so the
    /// text renders dynamically in NSTextView. (NSTextView's own
    /// `textColor` default is supposed to handle this case but proves
    /// unreliable inside our SwiftUI host.)
    func testPlainStringRoundTripGainsLabelColor() throws {
        let source = NSAttributedString(string: "Hello dark world")
        let rtf = try XCTUnwrap(source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ))
        let decoded = NSAttributedString.fromRTFData(rtf)
        XCTAssertEqual(decoded.string, "Hello dark world")
        let color = decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor,
                       "Every range without an explicit foregroundColor must gain NSColor.labelColor on decode for dark-mode adaptation")
    }

    /// Explicit pure-black foreground also gets rewritten to labelColor —
    /// covers the case where AppKit's encoder DOES bake an explicit
    /// black (e.g. source had `NSColor.black` directly).
    func testExplicitBlackIsRewrittenToLabelColor() throws {
        let source = NSAttributedString(string: "Hello explicit black",
                                        attributes: [.foregroundColor: NSColor.black])
        let rtf = try XCTUnwrap(source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ))
        let decoded = NSAttributedString.fromRTFData(rtf)
        let color = decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor,
                       "Pure-black explicit foregroundColor must be rewritten to dynamic labelColor")
    }

    /// A string with explicit user-chosen non-black colors must NOT be
    /// rewritten — the "all-black" check fails the moment any non-black
    /// run exists.
    func testStringWithUserColorIsLeftAlone() {
        let userRed = NSColor.systemRed
        let mutable = NSMutableAttributedString(string: "Hello red world",
                                                 attributes: [.foregroundColor: userRed])
        let rtf = try? mutable.data(
            from: NSRange(location: 0, length: mutable.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let decoded = NSAttributedString.fromRTFData(rtf)
        let color = decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.labelColor,
                          "User-chosen non-black color must survive the round-trip")
        // Be tolerant on exact red — RTF color table quantization can
        // shift components by ±1/255. The important property is
        // "not labelColor and approximately red."
        let rgb = color?.usingColorSpace(.sRGB)
        XCTAssertGreaterThan(rgb?.redComponent ?? 0, 0.6)
        XCTAssertLessThan(rgb?.greenComponent ?? 1, 0.4)
    }

    /// Mixed content (black + red): the black ranges get rewritten to
    /// labelColor (they're the AppKit-baked default), the red survives.
    /// Locks that intentional non-black user colors aren't clobbered.
    func testMixedContentPreservesNonBlackColors() throws {
        let mutable = NSMutableAttributedString()
        mutable.append(NSAttributedString(string: "Default text",
                                          attributes: [.foregroundColor: NSColor.black]))
        mutable.append(NSAttributedString(string: " red bit",
                                          attributes: [.foregroundColor: NSColor.systemRed]))
        let rtf = try XCTUnwrap(mutable.data(
            from: NSRange(location: 0, length: mutable.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ))
        let decoded = NSAttributedString.fromRTFData(rtf)
        // First range: black → labelColor.
        let firstColor = decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(firstColor, NSColor.labelColor)
        // Locate the red range — search the second half for any pixel
        // that's red-dominant. Don't assume an exact byte offset; RTF
        // attachment overhead can shift positions.
        var foundRed = false
        decoded.enumerateAttribute(.foregroundColor,
                                    in: NSRange(location: 0, length: decoded.length),
                                    options: []) { value, _, _ in
            if let c = (value as? NSColor)?.usingColorSpace(.sRGB),
               c.redComponent > 0.6, c.greenComponent < 0.4 {
                foundRed = true
            }
        }
        XCTAssertTrue(foundRed, "Red user-color must survive the RTF round-trip + adaptation")
    }

    /// Empty / nil data returns an empty attributed string — same as before.
    func testEmptyInput() {
        XCTAssertEqual(NSAttributedString.fromRTFData(nil).length, 0)
        XCTAssertEqual(NSAttributedString.fromRTFData(Data()).length, 0)
    }

    /// **Light-mode safety.** Simulates the legacy data shape: a string
    /// where the foreground color is a *resolved* near-white RGB
    /// (what `labelColor` would freeze to if encoded in dark mode).
    /// After adaptation, the runs must be rewritten to labelColor so
    /// switching to light mode renders them readable instead of
    /// invisible.
    func testNearWhiteGrayscaleRunIsRewrittenToLabelColor() throws {
        let frozenWhite = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        let source = NSAttributedString(string: "Dark-mode-saved text",
                                        attributes: [.foregroundColor: frozenWhite])
        let rtf = try XCTUnwrap(source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ))
        let decoded = NSAttributedString.fromRTFData(rtf)
        let color = decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor,
                       "Frozen near-white grayscale must be rewritten to labelColor — symmetric with the pure-black rewrite")
    }

    /// Encoding `toRTFData` on a string that carries `NSColor.labelColor`
    /// (catalog / dynamic) must NOT freeze the color into the RTF.
    /// Otherwise saving in one appearance bakes a static color that
    /// breaks in the other appearance — the bug this whole work was
    /// motivated by.
    func testToRTFDataStripsCatalogColorBeforeEncoding() throws {
        let source = NSAttributedString(string: "Dynamic text",
                                        attributes: [.foregroundColor: NSColor.labelColor])
        // Pre-condition: the catalog color is actually present.
        let preColor = source.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(preColor?.type, .catalog)

        guard let rtf = source.toRTFData() else {
            return XCTFail("toRTFData returned nil")
        }
        let decoded = NSAttributedString.fromRTFData(rtf)
        // After save + load: should be labelColor again (added by the
        // adapter on decode), NOT a frozen static white/black RGB.
        let post = decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(post, NSColor.labelColor)
        XCTAssertEqual(post?.type, .catalog,
                       "Round-tripped color must end up dynamic again; encoding must not have frozen a static RGB")
    }

    /// User-picked non-grayscale colors survive the save round-trip
    /// untouched — the stripping is scoped to catalog colors only.
    func testUserComponentColorSurvivesSaveRoundTrip() throws {
        // sRGB-explicit so the color is component-based, not catalog.
        let userRed = NSColor(srgbRed: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        XCTAssertEqual(userRed.type, .componentBased,
                       "Pre-condition: user-picked colors should be component-based")
        let source = NSAttributedString(string: "Hello red",
                                        attributes: [.foregroundColor: userRed])
        guard let rtf = source.toRTFData() else { return XCTFail("nil rtf") }
        let decoded = NSAttributedString.fromRTFData(rtf)
        let post = (decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.sRGB)
        XCTAssertNotNil(post)
        XCTAssertGreaterThan(post?.redComponent ?? 0, 0.6)
        XCTAssertLessThan(post?.greenComponent ?? 1, 0.4)
    }

    /// Pure-mid-gray that a user might intentionally pick (not catalog,
    /// not near-extreme) must survive — symmetric guard against
    /// over-aggressive rewriting.
    func testIntentionalMidGrayIsLeftAlone() {
        let userGray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let source = NSAttributedString(string: "Hello mid gray",
                                        attributes: [.foregroundColor: userGray])
        let adapted = source.adaptingDefaultBlackToLabelColor()
        let post = (adapted.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.sRGB)
        XCTAssertEqual(post?.redComponent ?? 0, 0.5, accuracy: 0.05,
                       "Mid-gray is between the black and white thresholds — must not be touched")
    }

    /// The `adaptingDefaultBlackToLabelColor` extension is idempotent —
    /// re-running on already-adapted content leaves it unchanged.
    func testAdaptationIsIdempotent() {
        let source = NSAttributedString(string: "Hello",
                                        attributes: [.foregroundColor: NSColor.labelColor])
        let adapted = source.adaptingDefaultBlackToLabelColor()
        XCTAssertEqual(adapted.string, "Hello")
        let color = adapted.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor)
    }
}
