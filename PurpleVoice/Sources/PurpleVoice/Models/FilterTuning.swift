import Foundation

/// Per-filter tunables that override the profile-baked defaults when
/// "custom tuning" is enabled. Designed as a flat struct of Optional
/// values: `nil` means "use the profile's default for this knob",
/// non-nil means "use this value." This lets a user override just
/// one parameter (say, compressor ratio) and inherit the rest from
/// their chosen profile.
///
/// Persistence is hand-rolled JSON via `SettingsStore` rather than
/// per-field `@AppStorage` keys — keeps the UserDefaults surface
/// small and lets us add fields without migration churn.
struct FilterTuning: Codable, Equatable {

    /// Highpass cutoff in Hz. Profile default: 80.
    /// Sensible range: 20...200.
    var highpassHz: Double?

    /// `afftdn` noise-reduction strength in dB. Profile default:
    /// 8 (light), 12 (medium), 20 (aggressive).
    /// Sensible range: 0...30. 0 effectively disables denoise.
    var afftdnNR: Double?

    /// `deesser` intensity, 0–1. Profile default: 0.4 (when enabled).
    /// Only applied when the de-esser is on.
    var deEsserIntensity: Double?

    /// `acompressor` threshold in dB. Profile default: -22.
    /// Sensible range: -60...0.
    var compressorThresholdDB: Double?

    /// `acompressor` ratio (N:1). Profile default: 3.
    /// Sensible range: 1...20. 1 = no compression.
    var compressorRatio: Double?

    /// `alimiter` ceiling, 0–1 linear. Profile default: 0.97.
    /// Sensible range: 0.5...1.0. Below ~0.7 makes things very quiet.
    var limiterCeiling: Double?

    /// Empty tuning — every knob inherits from the profile.
    static let inherited = FilterTuning()

    /// True if at least one knob is overriding the profile default.
    var hasAnyOverride: Bool {
        highpassHz != nil
            || afftdnNR != nil
            || deEsserIntensity != nil
            || compressorThresholdDB != nil
            || compressorRatio != nil
            || limiterCeiling != nil
    }

    // MARK: - Bounds (single source of truth for sliders + clamp logic)

    enum Bounds {
        static let highpassHz: ClosedRange<Double>         = 20...200
        static let afftdnNR: ClosedRange<Double>           = 0...30
        static let deEsserIntensity: ClosedRange<Double>   = 0...1
        static let compressorThresholdDB: ClosedRange<Double> = -60...0
        static let compressorRatio: ClosedRange<Double>    = 1...20
        static let limiterCeiling: ClosedRange<Double>     = 0.5...1
    }
}
