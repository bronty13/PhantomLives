import Testing
import Foundation
@testable import SizzleBot

@Suite("OllamaService roleplay framing")
struct OllamaServiceTests {

    @Test("roleplay preamble is non-empty")
    func preambleIsNonEmpty() {
        #expect(!OllamaService.roleplayPreamble.isEmpty)
    }

    @Test("preamble forbids breaking character with safety nags")
    func preambleForbidsNags() {
        let p = OllamaService.roleplayPreamble.lowercased()
        #expect(p.contains("character"), "preamble should reference staying in character")
        #expect(p.contains("safety warning") || p.contains("safety warnings"),
                "preamble should explicitly forbid safety warnings")
        #expect(p.contains("disclaimer") || p.contains("disclaimers"),
                "preamble should forbid disclaimers")
        #expect(p.contains("refusal") || p.contains("refusals"),
                "preamble should forbid refusals")
    }

    @Test("preamble forbids common AI-disclosure phrasing")
    func preambleForbidsAIDisclosure() {
        let p = OllamaService.roleplayPreamble.lowercased()
        #expect(p.contains("as an ai"), "should forbid 'As an AI' phrasing")
        #expect(p.contains("i'm sorry") || p.contains("i am sorry"),
                "should forbid 'I'm sorry, but' hedging")
    }

    @Test("fullSystemPrompt prepends preamble to the character prompt")
    func fullSystemPromptComposition() {
        let character = Character(
            name: "Test Bot",
            avatar: "🧪",
            tagline: "test",
            systemPrompt: "UNIQUE_CHARACTER_BODY_MARKER",
            greeting: "hi"
        )
        let combined = OllamaService.fullSystemPrompt(for: character)
        #expect(combined.hasPrefix(OllamaService.roleplayPreamble),
                "combined prompt must start with the preamble")
        #expect(combined.contains("UNIQUE_CHARACTER_BODY_MARKER"),
                "combined prompt must contain the character's own systemPrompt body")
        #expect(combined.count == OllamaService.roleplayPreamble.count + character.systemPrompt.count,
                "combined prompt should be exactly preamble + body, no truncation")
    }

    @Test("fullSystemPrompt is pure — same input yields same output")
    func fullSystemPromptIsPure() {
        let c = Character(name: "A", avatar: "X", tagline: "t", systemPrompt: "body", greeting: "g")
        #expect(OllamaService.fullSystemPrompt(for: c) == OllamaService.fullSystemPrompt(for: c))
    }

    @Test("utility preamble keeps anti-refusal guidance, drops 'fictional roleplay' framing")
    func utilityPreambleShape() {
        let p = OllamaService.utilityPreamble.lowercased()
        // Must keep the anti-refusal protections.
        #expect(p.contains("do not refuse") || p.contains("not refuse"))
        #expect(p.contains("as an ai"), "should still suppress 'As an AI' phrasing")
        #expect(p.contains("safety warning") || p.contains("safety warnings"))
        // Must NOT carry the fiction framing — the user wants precise real-world description.
        #expect(!p.contains("fictional roleplay"),
                "utility preamble must not call the task fictional roleplay")
        #expect(!p.contains("immersive fictional"))
    }

    @Test("Vision-enabled characters get the utility preamble; others get roleplay")
    func preambleRoutedByVisionFlag() {
        let roleplayChar = Character(
            name: "Roleplay", avatar: "X", tagline: "t",
            systemPrompt: "BODY_MARKER", greeting: "g"
        )
        let visionChar = Character(
            name: "Vision", avatar: "Y", tagline: "t",
            systemPrompt: "BODY_MARKER", greeting: "g",
            acceptsImages: true
        )

        let roleplayFull = OllamaService.fullSystemPrompt(for: roleplayChar)
        let visionFull = OllamaService.fullSystemPrompt(for: visionChar)

        #expect(roleplayFull.hasPrefix(OllamaService.roleplayPreamble))
        #expect(visionFull.hasPrefix(OllamaService.utilityPreamble))
        #expect(!visionFull.hasPrefix(OllamaService.roleplayPreamble),
                "vision character must not be prefixed with the roleplay preamble")
        #expect(roleplayFull.contains("BODY_MARKER"))
        #expect(visionFull.contains("BODY_MARKER"))
    }

    @Test("recommended model list leads with uncensored / roleplay-friendly options")
    func recommendedListLeadsWithUncensored() {
        // The first four entries should be the roleplay-friendly tier.
        // We don't pin exact identifiers — we assert the *property* the ordering encodes.
        let topFour = OllamaModel.recommended.prefix(4).map { $0.description.lowercased() }
        for desc in topFour {
            let isRoleplayFriendly =
                desc.contains("uncensored") ||
                desc.contains("roleplay") ||
                desc.contains("expressive") ||
                desc.contains("character")
            #expect(isRoleplayFriendly,
                    "top-of-list model description should advertise uncensored / roleplay-friendly traits, got: \(desc)")
        }
    }

    @Test("dolphin-mistral remains the first recommended model (the app default)")
    func dolphinMistralStaysDefault() {
        #expect(OllamaModel.recommended.first?.id == "dolphin-mistral")
    }

    @Test("wizard-vicuna-uncensored is present in the recommended list")
    func wizardVicunaPresent() {
        #expect(OllamaModel.recommended.contains { $0.id == "wizard-vicuna-uncensored" })
    }

    @Test("vision-capable models are present in the recommended list")
    func visionModelsPresent() {
        let visionIds = OllamaModel.recommended.filter { $0.kind == .vision }.map(\.id)
        #expect(visionIds.contains("llama3.2-vision"))
        #expect(visionIds.contains("llava"))
        #expect(visionIds.contains("moondream"))
    }
}

@Suite("OllamaService effective-model fallback")
@MainActor
struct OllamaServiceFallbackTests {

    private func makeService(installed installedNames: [String], selected: String) -> OllamaService {
        let svc = OllamaService()
        svc.availableModels = installedNames.map {
            OllamaModel(name: $0, size: nil, modifiedAt: nil)
        }
        svc.setModel(selected)
        return svc
    }

    private func character(preferring preferred: String?) -> Character {
        Character(
            name: "T", avatar: "X", tagline: "",
            systemPrompt: "p", greeting: "g",
            preferredModel: preferred
        )
    }

    @Test("preferred model installed → uses preferred, no fallback")
    func preferredInstalled() {
        let svc = makeService(
            installed: ["dolphin-mistral:latest", "wizard-vicuna-uncensored:latest"],
            selected: "dolphin-mistral"
        )
        let result = svc.effectiveModel(for: character(preferring: "wizard-vicuna-uncensored"))
        #expect(result.model == "wizard-vicuna-uncensored")
        #expect(result.fellBack == false)
    }

    @Test("preferred model NOT installed → falls back to global default")
    func preferredMissingFallsBack() {
        let svc = makeService(
            installed: ["dolphin-mistral:latest"],
            selected: "dolphin-mistral"
        )
        let result = svc.effectiveModel(for: character(preferring: "wizard-vicuna-uncensored"))
        #expect(result.model == "dolphin-mistral")
        #expect(result.fellBack == true, "should report a fallback occurred")
    }

    @Test("no preferred model → uses global default, no fallback flag")
    func noPreferredUsesDefault() {
        let svc = makeService(
            installed: ["dolphin-mistral:latest"],
            selected: "dolphin-mistral"
        )
        let result = svc.effectiveModel(for: character(preferring: nil))
        #expect(result.model == "dolphin-mistral")
        #expect(result.fellBack == false)
    }

    @Test("isInstalled tolerates the :latest tag suffix")
    func isInstalledTolerantToTag() {
        let svc = makeService(
            installed: ["dolphin-mistral:latest"],
            selected: "dolphin-mistral"
        )
        #expect(svc.isInstalled("dolphin-mistral"))
        #expect(svc.isInstalled("dolphin-mistral:latest"))
        #expect(!svc.isInstalled("does-not-exist"))
    }
}
