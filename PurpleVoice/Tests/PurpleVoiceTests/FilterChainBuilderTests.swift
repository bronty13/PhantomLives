import Foundation
import Testing
@testable import PurpleVoice

@Suite("FilterChainBuilder")
struct FilterChainBuilderTests {

    @Test("Light profile skips heavy denoise + compression")
    func lightProfileSkipsHeavyDenoiseAndCompression() {
        let chain = FilterChainBuilder.chain(profile: .light,
                                             enhancementEnabled: true)
        #expect(chain.contains("highpass=f=80"))
        #expect(chain.contains("afftdn=nr=8"))
        #expect(!chain.contains("anlmdn"))
        #expect(!chain.contains("acompressor"))
        #expect(!chain.contains("lowpass"))
        #expect(chain.contains("alimiter"))
    }

    @Test("Medium profile includes full chain")
    func mediumProfileIncludesFullChain() {
        let chain = FilterChainBuilder.chain(profile: .medium,
                                             enhancementEnabled: true)
        for stage in ["highpass=f=80", "afftdn=nr=12", "anlmdn=",
                      "lowpass=f=12000", "dynaudnorm=",
                      "acompressor=", "alimiter=limit=0.97"] {
            #expect(chain.contains(stage), "missing stage `\(stage)`; got: \(chain)")
        }
    }

    @Test("Aggressive profile uses strongest denoise")
    func aggressiveProfileHasStrongestDenoise() {
        let chain = FilterChainBuilder.chain(profile: .aggressive,
                                             enhancementEnabled: true)
        #expect(chain.contains("afftdn=nr=20"))
        #expect(chain.contains("tn=1"))
        #expect(chain.contains("anlmdn=s=10"))
    }

    @Test("Enhancement disabled strips dynamics stages")
    func enhancementDisabledStripsDynamicsStages() {
        let chain = FilterChainBuilder.chain(profile: .medium,
                                             enhancementEnabled: false)
        #expect(!chain.contains("dynaudnorm"))
        #expect(!chain.contains("acompressor"))
        #expect(!chain.contains("alimiter"))
        #expect(chain.contains("afftdn"))
        #expect(chain.contains("anlmdn"))
    }

    @Test("Chain is comma-separated with no stray whitespace")
    func chainIsCommaSeparatedWithNoStrayWhitespace() {
        let chain = FilterChainBuilder.chain(profile: .aggressive,
                                             enhancementEnabled: true)
        #expect(!chain.contains(", "))
        #expect(!chain.hasPrefix(","))
        #expect(!chain.hasSuffix(","))
    }

    // MARK: - v0.2 additions

    @Test("Loudness target appends the loudnorm filter")
    func loudnessTargetAppendsLoudnorm() {
        let podcast = FilterChainBuilder.chain(options: .init(
            profile: .medium, loudnessTarget: .podcast
        ))
        #expect(podcast.contains("loudnorm=I=-16.0:TP=-1.5:LRA=11"))

        let streaming = FilterChainBuilder.chain(options: .init(
            profile: .medium, loudnessTarget: .streaming
        ))
        #expect(streaming.contains("loudnorm=I=-14.0:TP=-1.5:LRA=11"))

        let broadcast = FilterChainBuilder.chain(options: .init(
            profile: .medium, loudnessTarget: .broadcast
        ))
        #expect(broadcast.contains("loudnorm=I=-23.0:TP=-1.5:LRA=11"))

        let none = FilterChainBuilder.chain(options: .init(
            profile: .medium, loudnessTarget: .none
        ))
        #expect(!none.contains("loudnorm"))
    }

    @Test("Loudnorm is last so it measures the final mix")
    func loudnormIsLastStage() {
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .medium, loudnessTarget: .podcast
        ))
        let stages = chain.split(separator: ",").map(String.init)
        #expect(stages.last?.hasPrefix("loudnorm") == true,
                "loudnorm must run after the dynamics chain so it sees the final levels; got order: \(stages)")
    }

    @Test("De-esser only appears when enabled")
    func deEsserToggle() {
        let off = FilterChainBuilder.chain(options: .init(
            profile: .medium, deEsserEnabled: false
        ))
        #expect(!off.contains("deesser"))

        let on = FilterChainBuilder.chain(options: .init(
            profile: .medium, deEsserEnabled: true
        ))
        #expect(on.contains("deesser="))
    }

    @Test("De-clicker only appears when enabled, before de-esser")
    func deClickerToggleAndOrder() {
        let off = FilterChainBuilder.chain(options: .init(
            profile: .medium, deClickerEnabled: false
        ))
        #expect(!off.contains("adeclick"))

        let on = FilterChainBuilder.chain(options: .init(
            profile: .medium,
            deEsserEnabled: true,
            deClickerEnabled: true
        ))
        guard let clickIdx = on.range(of: "adeclick")?.lowerBound,
              let essIdx   = on.range(of: "deesser")?.lowerBound else {
            Issue.record("missing adeclick / deesser stage in chain: \(on)")
            return
        }
        #expect(clickIdx < essIdx,
                "de-clicker must run before de-esser to clean transients first; got: \(on)")
    }

    @Test("skipDenoise omits afftdn + anlmdn but keeps the rest")
    func skipDenoiseOmitsDenoiseStages() {
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .medium,
            enhancementEnabled: true,
            skipDenoise: true,
            loudnessTarget: .podcast
        ))
        #expect(!chain.contains("afftdn"))
        #expect(!chain.contains("anlmdn"))
        #expect(!chain.contains("lowpass"),
                "lowpass is part of the denoise-cleanup band-limiting; skip when DFN did the denoise")
        #expect(chain.contains("highpass=f=80"))
        #expect(chain.contains("dynaudnorm"))
        #expect(chain.contains("alimiter"))
        #expect(chain.contains("loudnorm"))
    }
}

@Suite("LoudnessTarget")
struct LoudnessTargetTests {

    @Test("Filter strings are nil for off, populated otherwise")
    func filterStrings() {
        #expect(LoudnessTarget.none.filterString == nil)
        #expect(LoudnessTarget.podcast.filterString?.hasPrefix("loudnorm=I=-16") == true)
        #expect(LoudnessTarget.streaming.filterString?.contains("I=-14") == true)
        #expect(LoudnessTarget.broadcast.filterString?.contains("I=-23") == true)
    }

    @Test("Integrated LUFS values match the broadcast / streaming specs")
    func integratedLUFS() {
        #expect(LoudnessTarget.none.integratedLUFS == nil)
        #expect(LoudnessTarget.podcast.integratedLUFS == -16)
        #expect(LoudnessTarget.streaming.integratedLUFS == -14)
        #expect(LoudnessTarget.broadcast.integratedLUFS == -23)
    }
}
