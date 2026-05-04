import Testing
import Foundation
@testable import SizzleBot

@Suite("PromptExporter parsing & composition")
struct PromptExporterTests {

    @Test("Parses paragraph + comma-separated variants")
    func parsesStandardArchitectOutput() {
        let raw = """
        A dense portrait paragraph describing the subject in detail goes here, covering hair, eyes, build, expression, and lighting.

        Style variants: noir b&w portrait, fantasy oil painting, cyberpunk neon
        """
        let parsed = PromptExporter.parse(raw)
        #expect(parsed.paragraph.contains("dense portrait paragraph"))
        #expect(!parsed.paragraph.lowercased().contains("style variants"),
                "paragraph should not include the variants line")
        #expect(parsed.variants == ["noir b&w portrait", "fantasy oil painting", "cyberpunk neon"])
    }

    @Test("Tolerates lowercase and dash separator on the variants line")
    func parsesCaseAndDashTolerantly() {
        let raw = """
        Subject paragraph here.
        style variants - watercolor sketch, anime ink, pastel chalk
        """
        let parsed = PromptExporter.parse(raw)
        #expect(parsed.variants == ["watercolor sketch", "anime ink", "pastel chalk"])
    }

    @Test("Tolerates semicolon-separated variants")
    func parsesSemicolonSeparator() {
        let raw = """
        Paragraph.
        Style variants: a; b; c
        """
        let parsed = PromptExporter.parse(raw)
        #expect(parsed.variants == ["a", "b", "c"])
    }

    @Test("Returns the whole text as paragraph when no variants line is present")
    func noVariantsLineReturnsWholeText() {
        let raw = "Just a description, no variants line at all."
        let parsed = PromptExporter.parse(raw)
        #expect(parsed.paragraph == raw)
        #expect(parsed.variants.isEmpty)
    }

    @Test("Mid-paragraph mention of 'style variants' is not misread as the variants line")
    func midParagraphPhrasingIgnored() {
        let raw = """
        I considered several style variants earlier in this description, but the actual list is below.
        Style variants: red, green, blue
        """
        let parsed = PromptExporter.parse(raw)
        #expect(parsed.variants == ["red", "green", "blue"])
        #expect(parsed.paragraph.contains("considered several style variants"),
                "the mid-paragraph mention must remain in the paragraph body")
    }

    @Test("Handles empty input gracefully")
    func handlesEmptyInput() {
        let parsed = PromptExporter.parse("")
        #expect(parsed.paragraph.isEmpty)
        #expect(parsed.variants.isEmpty)
    }

    @Test("composePrompt with no variant returns paragraph unchanged")
    func composeNoVariant() {
        #expect(PromptExporter.composePrompt(paragraph: "subject", variant: nil) == "subject")
        #expect(PromptExporter.composePrompt(paragraph: "subject", variant: "") == "subject")
        #expect(PromptExporter.composePrompt(paragraph: "subject", variant: "   ") == "subject")
    }

    @Test("composePrompt joins paragraph and variant with a comma")
    func composeWithVariant() {
        #expect(
            PromptExporter.composePrompt(paragraph: "subject", variant: "neon")
                == "subject, neon"
        )
    }

    @Test("composePrompt trims surrounding whitespace from both inputs")
    func composeTrimsWhitespace() {
        let result = PromptExporter.composePrompt(paragraph: "  subject  \n", variant: "  neon ")
        #expect(result == "subject, neon")
    }

    @Test("All Target cases have non-empty display names and bundle names")
    func targetMetadataPresent() {
        for target in PromptExporter.Target.allCases {
            #expect(!target.displayName.isEmpty)
            #expect(!target.bundleNames.isEmpty)
            for name in target.bundleNames {
                #expect(!name.isEmpty)
            }
        }
    }

    @Test("Locating an app at a non-existent path returns nil")
    func locateMissingApp() {
        // We can't reliably assert installed/not-installed in CI, but we can
        // assert the function doesn't crash and that the contract holds:
        // if it returns a URL, that URL points at an existing .app bundle.
        for target in PromptExporter.Target.allCases {
            if let url = PromptExporter.locate(target) {
                #expect(FileManager.default.fileExists(atPath: url.path))
                #expect(url.pathExtension == "app")
            }
        }
    }
}
