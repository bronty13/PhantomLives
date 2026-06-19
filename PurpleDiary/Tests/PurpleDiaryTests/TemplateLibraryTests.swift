import XCTest
@testable import PurpleDiary

/// The curated built-in template library: structural invariants + that every
/// scaffold renders cleanly through `TemplateService` (no leftover tokens, since
/// the library only uses known ones).
final class TemplateLibraryTests: XCTestCase {

    func testLibraryIsReasonablySized() {
        XCTAssertGreaterThanOrEqual(TemplateLibrary.all.count, 15,
                                    "the point of this feature is a generous library")
    }

    func testNamesAreUnique() {
        let names = TemplateLibrary.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "library template names must be unique (they're the id)")
    }

    func testEveryTemplateHasNameBlurbAndBody() {
        for t in TemplateLibrary.all {
            XCTAssertFalse(t.name.trimmingCharacters(in: .whitespaces).isEmpty, "empty name")
            XCTAssertFalse(t.blurb.trimmingCharacters(in: .whitespaces).isEmpty, "\(t.name): empty blurb")
            XCTAssertFalse(t.body.trimmingCharacters(in: .whitespaces).isEmpty, "\(t.name): empty body")
        }
    }

    func testSeedDefaultsAreANonEmptySubset() {
        let defaults = TemplateLibrary.seedDefaults
        XCTAssertFalse(defaults.isEmpty, "a fresh install needs a starter set")
        XCTAssertLessThan(defaults.count, TemplateLibrary.all.count, "not everything should be seeded")
        for d in defaults { XCTAssertTrue(d.seedByDefault) }
        let allNames = Set(TemplateLibrary.all.map(\.name))
        for d in defaults { XCTAssertTrue(allNames.contains(d.name)) }
    }

    func testSeedDefaultsKeepTheOriginalStarters() {
        // Daily Check-in + Gratitude were the original two seeds; keep them in the
        // starter set for continuity.
        let names = Set(TemplateLibrary.seedDefaults.map(\.name))
        XCTAssertTrue(names.contains("Daily Check-in"))
        XCTAssertTrue(names.contains("Gratitude"))
    }

    func testEveryBodyRendersWithNoLeftoverTokens() {
        // The library only uses known tokens, so a rendered body should contain
        // no `{{` — a guard against a typo'd token name slipping into a scaffold.
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        for t in TemplateLibrary.all {
            let rendered = TemplateService.render(t.body, date: date, locale: Locale(identifier: "en_US"))
            XCTAssertFalse(rendered.contains("{{"),
                           "\(t.name) has an unrecognized token: \(rendered)")
        }
    }
}
