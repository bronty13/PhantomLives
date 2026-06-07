import Foundation
import AVFoundation

/// A text-to-speech backend. v1 ships only `AVSpeechTTSEngine` (on-device,
/// free, offline); the protocol is the seam where cloud voices (ElevenLabs /
/// OpenAI) drop in later without the UI knowing the difference.
@MainActor
protocol TTSEngine: AnyObject {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    /// The character range of the word currently being spoken, in the
    /// coordinate space of the full document text that was handed to `speak`.
    var spokenWordRange: NSRange? { get }
    /// The enclosing sentence range, for sentence-level highlight.
    var spokenSentenceRange: NSRange? { get }

    func availableVoices() -> [VoiceInfo]
    func speak(_ text: String, from offset: Int)
    func pause()
    func resume()
    func stop()
}

/// A selectable voice, flattened from `AVSpeechSynthesisVoice` for the UI.
struct VoiceInfo: Identifiable, Hashable {
    let id: String          // AVSpeechSynthesisVoice.identifier
    let name: String
    let language: String
    let quality: String     // "Default" | "Enhanced" | "Premium"
}

/// Voices grouped under one language, for a sectioned picker.
struct VoiceGroup: Identifiable, Hashable {
    let id: String          // BCP-47 language code, e.g. "en-US"
    let displayName: String // localized, e.g. "English (United States)"
    let voices: [VoiceInfo]
}

/// On-device TTS over `AVSpeechSynthesizer`.
///
/// The synced-highlight primitive — the single most-copied feature in every
/// Speechify-class reader — comes free from AppKit: the synthesizer's
/// `willSpeakRangeOfSpeechString` delegate callback hands us the character
/// range of each word *as it is spoken*. We speak the document (or a tail of
/// it, for click-to-start) as one utterance and add `baseOffset` so the
/// published range is always in whole-document coordinates.
@MainActor
final class AVSpeechTTSEngine: NSObject, ObservableObject, TTSEngine, AVSpeechSynthesizerDelegate {

    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var spokenWordRange: NSRange?
    @Published private(set) var spokenSentenceRange: NSRange?

    /// User-facing knobs, set by AppState from settings before `speak`.
    var voiceIdentifier: String?
    var rateMultiplier: Double = 1.0
    var pitch: Double = 1.0
    var highlightSentence: Bool = true

    private let synth = AVSpeechSynthesizer()
    /// Offset added to delegate ranges so they map to the full document.
    private var baseOffset: Int = 0
    /// The full document text — used to compute the enclosing sentence.
    private var fullText: String = ""

    override init() {
        super.init()
        synth.delegate = self
    }

    func availableVoices() -> [VoiceInfo] {
        let preferredCode = Self.preferredLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices().map { v in
            VoiceInfo(
                id: v.identifier,
                name: v.name,
                language: v.language,
                quality: Self.qualityLabel(v.quality)
            )
        }
        // The user's own language first, then by language, highest quality, name.
        .sorted {
            let lhsPreferred = $0.language.hasPrefix(preferredCode)
            let rhsPreferred = $1.language.hasPrefix(preferredCode)
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            if $0.language != $1.language { return $0.language < $1.language }
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.name < $1.name
        }
    }

    /// Installed voices grouped by language for a sectioned picker. Groups are
    /// ordered with the user's locale first, then alphabetically by the
    /// localized language name; voices within a group are highest-quality first.
    func voicesByLanguage() -> [VoiceGroup] {
        // Rank exact-locale (e.g. en-US) first, then same-language variants
        // (other English), then everything else — so the user's own voice isn't
        // buried under alphabetically-earlier variants like Australia/India.
        let exact = Locale.preferredLanguages.first ?? "en-US"   // "en-US"
        let prefix = String(exact.prefix(2))                     // "en"
        func rank(_ id: String) -> Int {
            if id.caseInsensitiveCompare(exact) == .orderedSame { return 0 }
            if id.hasPrefix(prefix) { return 1 }
            return 2
        }
        let grouped = Dictionary(grouping: availableVoices(), by: { $0.language })
        return grouped.map { (language, voices) in
            VoiceGroup(
                id: language,
                displayName: Self.languageDisplayName(language),
                voices: voices.sorted {
                    if $0.quality != $1.quality { return $0.quality > $1.quality }
                    return $0.name < $1.name
                }
            )
        }
        .sorted { a, b in
            let ra = rank(a.id), rb = rank(b.id)
            if ra != rb { return ra < rb }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// "en-US" → "English (United States)". Falls back to the raw code.
    static func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// Two-letter code of the user's preferred language (e.g. "en").
    static func preferredLanguageCode() -> String {
        let full = Locale.preferredLanguages.first ?? "en-US"
        return String(full.prefix(2))
    }

    /// A sensible default voice identifier: the user's locale, else en-US,
    /// else the first installed voice. Keeps the picker and the actual speech
    /// in agreement instead of defaulting to whatever sorts first.
    static func systemDefaultVoiceID() -> String? {
        let pref = Locale.preferredLanguages.first ?? "en-US"
        if let v = AVSpeechSynthesisVoice(language: pref) { return v.identifier }
        if let v = AVSpeechSynthesisVoice(language: "en-US") { return v.identifier }
        return AVSpeechSynthesisVoice.speechVoices().first?.identifier
    }

    private static func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .enhanced: return "Enhanced"
        case .premium:  return "Premium"
        default:        return "Default"
        }
    }

    func speak(_ text: String, from offset: Int) {
        stop()
        guard offset >= 0, offset <= text.count else { return }
        fullText = text
        baseOffset = offset

        // Substring from the requested character offset to the end.
        let start = text.index(text.startIndex, offsetBy: offset)
        let tail = String(text[start...])
        guard !tail.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: tail)
        if let vid = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: vid) {
            utterance.voice = voice
        }
        utterance.rate = Self.mappedRate(rateMultiplier)
        utterance.pitchMultiplier = Float(max(0.5, min(2.0, pitch)))

        isSpeaking = true
        isPaused = false
        synth.speak(utterance)
    }

    func pause() {
        guard synth.isSpeaking, !synth.isPaused else { return }
        synth.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard synth.isPaused else { return }
        synth.continueSpeaking()
        isPaused = false
    }

    func stop() {
        if synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isPaused = false
        spokenWordRange = nil
        spokenSentenceRange = nil
    }

    /// Map a 0.5…4.0 user multiplier onto AVSpeech's clamped rate range.
    /// The engine caps at `AVSpeechUtteranceMaximumSpeechRate`, so multipliers
    /// beyond ~2× saturate — documented in USER_MANUAL.md.
    static func mappedRate(_ multiplier: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let target = base * max(0.25, multiplier)
        return Float(min(Double(AVSpeechUtteranceMaximumSpeechRate),
                         max(Double(AVSpeechUtteranceMinimumSpeechRate), target)))
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        // The callback range is relative to the utterance string; shift it
        // back into whole-document coordinates on the main actor (where
        // `baseOffset` / `fullText` live).
        Task { @MainActor in
            let absolute = NSRange(location: characterRange.location + self.baseOffset,
                                   length: characterRange.length)
            self.spokenWordRange = absolute
            self.spokenSentenceRange = self.highlightSentence
                ? Self.sentenceRange(containing: absolute, in: self.fullText)
                : nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.spokenWordRange = nil
            self.spokenSentenceRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }

    /// Compute the sentence enclosing `wordRange` by walking the string's
    /// sentence boundaries. Pure + static so it's unit-testable without a
    /// synthesizer (see PurpleSpeakTests).
    static func sentenceRange(containing wordRange: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        guard wordRange.location >= 0, wordRange.location < ns.length else { return nil }
        var result: NSRange?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .bySentences) { _, sentenceRange, _, stop in
            if NSLocationInRange(wordRange.location, sentenceRange) {
                result = sentenceRange
                stop.pointee = true
            }
        }
        return result
    }
}
