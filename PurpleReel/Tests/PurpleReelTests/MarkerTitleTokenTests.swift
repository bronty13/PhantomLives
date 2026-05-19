import XCTest
@testable import PurpleReel

/// Coverage for the C22 `${markerTitle}` token resolver. The token
/// was declared in C10 but stubbed to "" pending a DB-aware lookup;
/// C22 wires the view layer's closure-injected resolver and a
/// filename-safe sanitizer. These tests pin both the closure-routed
/// path and the sanitization rules.
final class MarkerTitleTokenTests: XCTestCase {

    private func makeAsset(filename: String = "clip.mov") -> Asset {
        Asset(
            rowId: 42,
            path: "/tmp/\(filename)",
            filename: filename,
            sizeBytes: 1_000_000,
            modifiedAt: Date(),
            codec: "avc1",
            widthPx: 1920,
            heightPx: 1080,
            durationSeconds: 10,
            frameRate: 30,
            sha1: nil,
            addedAt: Date(),
            audioCodec: "aac ",
            recordedAt: nil,
            createdAt: nil,
            isVFR: false
        )
    }

    // MARK: - End-to-end resolver behavior

    func testMarkerTitleResolvesFromInjectedClosure() {
        let plan = BatchRenameService.plan(
            template: "${originalName}_${markerTitle}${extension}",
            items: [makeAsset()],
            markerTitleLookup: { _ in "best take" }
        )
        XCTAssertEqual(plan.first?.proposedName, "clip_best take.mov")
    }

    func testMissingClosureFallsBackToEmpty() {
        // No lookup closure: token resolves to "" (not literal
        // "{markertitle}" — that'd leak braces into the filename).
        let plan = BatchRenameService.plan(
            template: "${originalName}_${markerTitle}${extension}",
            items: [makeAsset()]
        )
        XCTAssertEqual(plan.first?.proposedName, "clip_.mov")
    }

    func testClosureReturningNilCollapsesToEmpty() {
        let plan = BatchRenameService.plan(
            template: "${originalName}_${markerTitle}${extension}",
            items: [makeAsset()],
            markerTitleLookup: { _ in nil }
        )
        XCTAssertEqual(plan.first?.proposedName, "clip_.mov")
    }

    func testClosureReturningEmptyStringCollapsesToEmpty() {
        let plan = BatchRenameService.plan(
            template: "${originalName}_${markerTitle}${extension}",
            items: [makeAsset()],
            markerTitleLookup: { _ in "" }
        )
        XCTAssertEqual(plan.first?.proposedName, "clip_.mov")
    }

    // MARK: - Sanitization rules

    func testSanitizerStripsFilesystemHostileChars() {
        let dirty = "best:answer/2*3?\"who<is>this|that\\thing"
        let clean = BatchRenameService.sanitizeForFilename(dirty)
        // All nine of `/ \ : * ? " < > |` must be replaced.
        for forbidden in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] {
            XCTAssertFalse(clean.contains(forbidden),
                            "Sanitized output still contains \(forbidden): \(clean)")
        }
    }

    func testSanitizerCollapsesNewlinesAndTabs() {
        let multi = "line one\nline two\twith tab"
        let clean = BatchRenameService.sanitizeForFilename(multi)
        // Newlines and tabs fold to space; runs of whitespace
        // collapse to a single space.
        XCTAssertEqual(clean, "line one line two with tab")
    }

    func testSanitizerTrimsSurroundingWhitespace() {
        let padded = "   surrounded   "
        XCTAssertEqual(BatchRenameService.sanitizeForFilename(padded),
                        "surrounded")
    }

    func testSanitizerLeavesSafeCharsAlone() {
        let safe = "interview-take_03 (good)"
        // Hyphens, underscores, parens, spaces, digits all survive.
        XCTAssertEqual(BatchRenameService.sanitizeForFilename(safe),
                        safe)
    }

    /// Marker notes can carry emoji — make sure those don't get
    /// mangled (they're valid filename chars on APFS).
    func testSanitizerPreservesEmoji() {
        let withEmoji = "great take 🎬"
        XCTAssertEqual(BatchRenameService.sanitizeForFilename(withEmoji),
                        "great take 🎬")
    }
}
