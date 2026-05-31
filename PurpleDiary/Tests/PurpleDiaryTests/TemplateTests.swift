import XCTest
@testable import PurpleDiary

/// Phase-5 templates: the pure token renderer and the data-layer CRUD/seed.
@MainActor
final class TemplateTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private var sundayMay31: Date {
        DateComponents(calendar: cal, timeZone: TimeZone(identifier: "UTC"),
                       year: 2026, month: 5, day: 31, hour: 16, minute: 5).date!
    }

    func testRenderSubstitutesDateTokens() {
        let body = "## {{weekday}}, {{date}}\nYear: {{year}}"
        let out = TemplateService.render(body, date: sundayMay31,
                                         locale: Locale(identifier: "en_US"))
        XCTAssertTrue(out.contains("Sunday"), out)
        XCTAssertTrue(out.contains("2026"), out)
        XCTAssertFalse(out.contains("{{"), "all tokens should be replaced")
    }

    func testRenderIsCaseInsensitiveAndToleratesSpaces() {
        let out = TemplateService.render("{{ WEEKDAY }}", date: sundayMay31,
                                         locale: Locale(identifier: "en_US"))
        XCTAssertEqual(out, "Sunday")
    }

    func testRenderLeavesUnknownTokensAlone() {
        XCTAssertEqual(TemplateService.render("{{nope}}", date: sundayMay31), "{{nope}}")
    }

    func testTemplateCRUD() throws {
        let t = Template.newDraft(name: "Test", body: "hello {{year}}")
        try DatabaseService.shared.insertTemplate(t)
        defer { try? DatabaseService.shared.deleteTemplate(id: t.id) }

        XCTAssertTrue(try DatabaseService.shared.fetchAllTemplates().contains { $0.id == t.id })

        var edited = t; edited.name = "Renamed"
        try DatabaseService.shared.updateTemplate(edited)
        XCTAssertEqual(try DatabaseService.shared.fetchAllTemplates().first { $0.id == t.id }?.name, "Renamed")

        try DatabaseService.shared.deleteTemplate(id: t.id)
        XCTAssertFalse(try DatabaseService.shared.fetchAllTemplates().contains { $0.id == t.id })
    }

    func testSeedDefaultsOnlyWhenEmpty() throws {
        // Seeding is a no-op once any template exists; assert it doesn't throw
        // and the table is non-empty afterward.
        try DatabaseService.shared.seedDefaultTemplatesIfEmpty()
        XCTAssertFalse(try DatabaseService.shared.fetchAllTemplates().isEmpty)
    }

    func testTemplateCodableRoundTrip() throws {
        let t = Template.newDraft(name: "Daily", body: "## {{date}}")
        XCTAssertEqual(try JSONDecoder().decode(Template.self, from: JSONEncoder().encode(t)), t)
    }
}
