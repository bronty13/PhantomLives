import Foundation

/// Builds the ffmpeg `-af` filter chain for a given profile + the
/// various v0.2 toggles + optional v0.3 per-filter tuning overrides.
/// Split out so we can unit-test composition without spawning a
/// subprocess.
///
/// Order of stages (left to right is the audio's processing order):
///
/// - `highpass`       — kill rumble below speech fundamentals.
/// - `afftdn`         — frequency-domain noise reduction (stationary
///                      noise like AC hum / hiss / fan). Skipped when
///                      a neural engine has already done denoise.
/// - `anlmdn`         — non-local-means residual denoise. Off in light.
/// - `lowpass`        — band-limit highs introduced by denoising.
/// - `adeclick`       — transient click / pop removal. Opt-in.
/// - `deesser`        — sibilance suppression. Opt-in.
/// - `dynaudnorm`     — even out level swings.
/// - `acompressor`    — gentle compression for quiet syllables.
/// - `alimiter`       — peak limiter (file can't clip).
/// - `loudnorm`       — final integrated-loudness target.
enum FilterChainBuilder {

    struct Options {
        var profile: ProcessingProfile = .medium
        var enhancementEnabled: Bool = true
        /// When true, the denoise stages (`afftdn` + `anlmdn`) are
        /// skipped because an upstream engine (DeepFilterNet) already
        /// denoised the temp WAV that gets handed to ffmpeg.
        var skipDenoise: Bool = false
        var loudnessTarget: LoudnessTarget = .none
        var deEsserEnabled: Bool = false
        var deClickerEnabled: Bool = false
        /// Per-filter overrides. Any nil field inherits from the
        /// profile defaults baked in below.
        var tuning: FilterTuning = .inherited
    }

    static func chain(options: Options) -> String {
        var stages: [String] = []

        // 1. Highpass — defaults to 80 Hz; override via tuning.
        let hp = options.tuning.highpassHz ?? 80
        stages.append("highpass=f=\(fmt(hp))")

        // 2. Denoise. Skipped entirely when an upstream engine
        //    already produced a clean WAV.
        if !options.skipDenoise {
            // Per-profile default for afftdn nr; tuning override
            // replaces whichever profile said.
            let defaultNR: Double
            let extra: String
            switch options.profile {
            case .light:      defaultNR = 8;  extra = ":nf=-25"
            case .medium:     defaultNR = 12; extra = ":nf=-25"
            case .aggressive: defaultNR = 20; extra = ":nf=-25:tn=1"
            }
            let nr = options.tuning.afftdnNR ?? defaultNR
            stages.append("afftdn=nr=\(fmt(nr))\(extra)")

            // anlmdn — only on medium / aggressive; non-tunable for
            // now (its three params are too obscure for the sheet).
            switch options.profile {
            case .light: break
            case .medium:
                stages.append("anlmdn=s=7:p=0.002:r=0.006")
            case .aggressive:
                stages.append("anlmdn=s=10:p=0.003:r=0.008")
            }
        }

        // 3. Lowpass — band-limit cleanup. Skip in light and when
        //    denoise was upstreamed.
        if options.profile != .light && !options.skipDenoise {
            stages.append("lowpass=f=12000")
        }

        // 4. Optional click / pop removal (no tunable parameters
        //    worth exposing — `adeclick` is basically off/on).
        if options.deClickerEnabled {
            stages.append("adeclick")
        }

        // 5. Optional de-esser. Intensity is tunable; the other
        //    params (max attenuation, frequency) stay fixed.
        if options.deEsserEnabled {
            let i = options.tuning.deEsserIntensity ?? 0.4
            stages.append("deesser=i=\(fmt(i)):m=0.5:f=0.5")
        }

        // 6. Enhancement chain.
        if options.enhancementEnabled {
            stages.append("dynaudnorm=g=5:f=200")
            if options.profile != .light {
                let threshold = options.tuning.compressorThresholdDB ?? -22
                let ratio = options.tuning.compressorRatio ?? 3
                stages.append("acompressor=threshold=\(fmt(threshold))dB:ratio=\(fmt(ratio)):attack=5:release=80")
            }
            let ceiling = options.tuning.limiterCeiling ?? 0.97
            stages.append("alimiter=limit=\(fmt(ceiling))")
        }

        // 7. Loudness normalization — last so we measure / target the
        //    fully-processed signal, not the raw denoised one.
        if let loudnorm = options.loudnessTarget.filterString {
            stages.append(loudnorm)
        }

        return stages.joined(separator: ",")
    }

    /// Trim trailing zeros so the emitted chain reads cleanly
    /// ("80" not "80.0", "0.4" not "0.40000000003"). Uses %g which
    /// switches between fixed and scientific based on magnitude;
    /// for our value ranges it stays fixed.
    private static func fmt(_ v: Double) -> String {
        // Round to 4 decimals to avoid Double-precision crud.
        let rounded = (v * 10_000).rounded() / 10_000
        return String(format: "%g", rounded)
    }

    // Back-compat shim — keep the old call-site so existing tests
    // and the CLI's default path continue to compile. New code uses
    // the Options form directly.
    static func chain(profile: ProcessingProfile,
                      enhancementEnabled: Bool) -> String {
        chain(options: Options(profile: profile,
                               enhancementEnabled: enhancementEnabled))
    }
}
