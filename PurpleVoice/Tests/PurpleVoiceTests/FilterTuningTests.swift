import Foundation
import Testing
@testable import PurpleVoice

@Suite("FilterTuning + chain overrides")
struct FilterTuningTests {

    @Test("Inherited tuning produces same chain as profile defaults")
    func inheritedMatchesProfileDefaults() {
        let inherited = FilterChainBuilder.chain(options: .init(
            profile: .medium,
            enhancementEnabled: true,
            tuning: .inherited
        ))
        let plain = FilterChainBuilder.chain(profile: .medium,
                                              enhancementEnabled: true)
        #expect(inherited == plain,
                "inherited tuning must round-trip to the unmodified profile chain")
    }

    @Test("Highpass override replaces the default 80 Hz")
    func highpassOverride() {
        var t = FilterTuning.inherited
        t.highpassHz = 50
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .medium, tuning: t
        ))
        #expect(chain.contains("highpass=f=50"))
        #expect(!chain.contains("highpass=f=80"))
    }

    @Test("Denoise dB override replaces afftdn nr")
    func afftdnOverride() {
        var t = FilterTuning.inherited
        t.afftdnNR = 18
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .medium, tuning: t
        ))
        #expect(chain.contains("afftdn=nr=18"))
        #expect(!chain.contains("afftdn=nr=12"))
    }

    @Test("De-esser intensity only takes effect when de-esser is on")
    func deEsserIntensityOverrideRequiresEnabled() {
        var t = FilterTuning.inherited
        t.deEsserIntensity = 0.8

        let off = FilterChainBuilder.chain(options: .init(
            profile: .medium, deEsserEnabled: false, tuning: t
        ))
        #expect(!off.contains("deesser"),
                "de-esser must remain off when the toggle is off, even with intensity override")

        let on = FilterChainBuilder.chain(options: .init(
            profile: .medium, deEsserEnabled: true, tuning: t
        ))
        #expect(on.contains("deesser=i=0.8"))
    }

    @Test("Compressor threshold + ratio overrides apply together")
    func compressorOverridesApply() {
        var t = FilterTuning.inherited
        t.compressorThresholdDB = -12
        t.compressorRatio = 6
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .medium, tuning: t
        ))
        #expect(chain.contains("acompressor=threshold=-12dB:ratio=6"))
    }

    @Test("Limiter ceiling override changes the alimiter limit value")
    func limiterCeilingOverride() {
        var t = FilterTuning.inherited
        t.limiterCeiling = 0.85
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .medium, tuning: t
        ))
        #expect(chain.contains("alimiter=limit=0.85"))
        #expect(!chain.contains("alimiter=limit=0.97"))
    }

    @Test("Empty override (hasAnyOverride == false) leaves chain identical")
    func emptyOverrideIsNoOp() {
        let blank = FilterTuning()
        #expect(!blank.hasAnyOverride)
        let chain = FilterChainBuilder.chain(options: .init(
            profile: .aggressive, tuning: blank
        ))
        let plain = FilterChainBuilder.chain(profile: .aggressive,
                                              enhancementEnabled: true)
        #expect(chain == plain)
    }

    @Test("hasAnyOverride flips when any single field is set")
    func hasAnyOverrideFlipsCorrectly() {
        var t = FilterTuning()
        #expect(!t.hasAnyOverride)
        t.afftdnNR = 10
        #expect(t.hasAnyOverride)
        t.afftdnNR = nil
        #expect(!t.hasAnyOverride)
    }

    @Test("FilterTuning round-trips through JSON for persistence")
    func jsonRoundTrip() throws {
        var t = FilterTuning.inherited
        t.highpassHz = 60
        t.compressorRatio = 4.5
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(FilterTuning.self, from: data)
        #expect(decoded == t)
    }
}

@Suite("CLI tuning flags")
struct CLITuningFlagTests {

    @Test("parseDouble validates the documented sensible range")
    func parseDoubleValidatesRange() {
        // In-range is fine.
        #expect(CLI.parseDouble("0.5",
                                flag: "--de-esser-intensity",
                                range: FilterTuning.Bounds.deEsserIntensity) == 0.5)
        // Boundary inclusive.
        #expect(CLI.parseDouble("1",
                                flag: "--de-esser-intensity",
                                range: FilterTuning.Bounds.deEsserIntensity) == 1)
        // Out-of-range and non-numeric exit via bail(), which calls
        // `exit(2)` — not testable here without subprocess
        // isolation, so we settle for the happy-path round-trip.
    }
}
