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

    // MARK: Speed regimes
    /// The synthesizer's native ceiling: `AVSpeechUtteranceMaximumSpeechRate`
    /// produces ~4× normal speech. At or below this we use the native engine
    /// (perfect highlight, no render latency); above it we render once and
    /// time-stretch the audio.
    static let nativeMaxSpeed: Double = 4.0

    // MARK: Fast (time-stretched) playback path, for speeds > nativeMaxSpeed.
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    /// Word start times in the rendered buffer: (document range, frame offset).
    private var fastTimeline: [(range: NSRange, frame: AVAudioFramePosition)] = []
    private var fastTimer: Timer?
    private var fastActive = false
    /// Bumped on every speak()/stop() so a slow async render that finishes
    /// after the user moved on can detect it's stale and not start playing.
    private var playGeneration = 0

    override init() {
        super.init()
        synth.delegate = self
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        // Connected with concrete formats in setupAndPlayFast once the rendered
        // buffer's format is known.
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

        isSpeaking = true
        isPaused = false
        playGeneration += 1

        if rateMultiplier <= Self.nativeMaxSpeed {
            speakNative(tail)
        } else {
            // >4×: render in chunks and stream them, so playback starts after the
            // first (small) chunk instead of waiting for the whole document.
            startFastStreaming(tail: tail, baseOffset: offset, speed: rateMultiplier)
        }
    }

    /// Change speed while playing. For the fast path this is seamless (just
    /// retune `AVAudioUnitTimePitch`). For the native path the synthesizer can't
    /// re-rate a live utterance, so the caller commits the change (restart from
    /// the current word) when the slider drag ends — see `commitRate`.
    func setRateLive(_ multiplier: Double) {
        rateMultiplier = multiplier
        if fastActive, multiplier > Self.nativeMaxSpeed {
            timePitch.rate = Float(min(8.0, max(0.5, multiplier / Self.nativeMaxSpeed)))
        }
    }

    /// Apply a committed speed change to in-progress playback: restart from the
    /// current word at the new rate. No-op when idle, paused, or when a fast→fast
    /// change was already applied live by `setRateLive`.
    func commitRate() {
        guard isSpeaking, !isPaused else { return }
        if fastActive && rateMultiplier > Self.nativeMaxSpeed { return } // handled live
        let pos = spokenWordRange?.location ?? baseOffset
        speak(fullText, from: pos)
    }

    /// Native AVSpeechSynthesizer playback (≤ nativeMaxSpeed). Perfect word
    /// highlighting via the delegate; zero render latency.
    private func speakNative(_ tail: String) {
        let utterance = AVSpeechUtterance(string: tail)
        if let vid = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: vid) {
            utterance.voice = voice
        }
        utterance.rate = Self.mappedRate(rateMultiplier)
        utterance.pitchMultiplier = Float(max(0.5, min(2.0, pitch)))
        synth.speak(utterance)
    }

    func pause() {
        if fastActive {
            playerNode.pause()
            isPaused = true
            return
        }
        guard synth.isSpeaking, !synth.isPaused else { return }
        synth.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        if fastActive {
            playerNode.play()
            isPaused = false
            return
        }
        guard synth.isPaused else { return }
        synth.continueSpeaking()
        isPaused = false
    }

    func stop() {
        // Call unconditionally. AVSpeechSynthesizer.isSpeaking can read false
        // while audio is still playing out (just after speak(), or near an
        // utterance boundary), so guarding on it would skip a needed stop and
        // leave the voice running. stopSpeaking is a no-op when idle.
        synth.stopSpeaking(at: .immediate)
        stopFast()
        isSpeaking = false
        isPaused = false
        spokenWordRange = nil
        spokenSentenceRange = nil
    }

    /// Map a user speed multiplier (× normal) onto AVSpeech's rate parameter.
    /// Calibrated so the label tracks perceived speed: the engine's max rate
    /// (`AVSpeechUtteranceMaximumSpeechRate`) is ~4× normal, so we interpolate
    /// between default (1×) and max (4×) instead of the old base×multiplier
    /// curve that saturated at ~2 on the slider. Above 4× the fast path takes
    /// over, but this still clamps sanely if called with a higher value.
    static func mappedRate(_ multiplier: Double) -> Float {
        let m = max(0.25, multiplier)
        let normal = Double(AVSpeechUtteranceDefaultSpeechRate)   // 0.5 → 1× speech
        let maxRate = Double(AVSpeechUtteranceMaximumSpeechRate)  // 1.0 → ~4× speech
        let r: Double
        if m <= 1.0 {
            r = normal * m                                        // linear for slow
        } else {
            // Interpolate in "perceived speed" space (max rate ≈ nativeMaxSpeed×).
            let frac = (1.0 - 1.0 / min(m, nativeMaxSpeed)) / (1.0 - 1.0 / nativeMaxSpeed)
            r = normal + (maxRate - normal) * frac
        }
        return Float(min(maxRate, max(Double(AVSpeechUtteranceMinimumSpeechRate), r)))
    }

    // MARK: - Fast (time-stretched) playback for speeds > nativeMaxSpeed

    private struct RenderResult {
        let buffer: AVAudioPCMBuffer
        let timeline: [(range: NSRange, frame: AVAudioFramePosition)]
    }

    /// Render `tail` to a single PCM buffer at the engine's max rate (~4×),
    /// capturing each word's start frame from `willSpeakRange` (which fires
    /// during offline render). Runs on the main actor; `await` frees the thread
    /// so the synthesizer's main-thread callbacks can be delivered.
    private func renderFast(tail: String, baseOffset: Int) async -> RenderResult? {
        let renderSynth = AVSpeechSynthesizer()
        let capture = FastRenderCapture(baseOffset: baseOffset)
        renderSynth.delegate = capture

        let u = AVSpeechUtterance(string: tail)
        if let vid = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: vid) { u.voice = v }
        u.rate = AVSpeechUtteranceMaximumSpeechRate
        u.pitchMultiplier = Float(max(0.5, min(2.0, pitch)))

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            renderSynth.write(u) { buf in
                guard let pcm = buf as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !resumed { resumed = true; cont.resume() }
                    return
                }
                if let copy = Self.copyBuffer(pcm) {
                    capture.buffers.append(copy)
                    capture.currentFrame += AVAudioFramePosition(pcm.frameLength)
                }
            }
        }
        guard let combined = Self.combineBuffers(capture.buffers) else { return nil }
        return RenderResult(buffer: combined, timeline: capture.timeline)
    }

    /// Render the tail in chunks and stream them onto the player as each is
    /// ready, so playback starts after the first (small) chunk rather than
    /// waiting for the whole document. Frame offsets accumulate across chunks so
    /// the single growing `fastTimeline` indexes by the player's cumulative
    /// sample position.
    private func startFastStreaming(tail: String, baseOffset: Int, speed: Double) {
        fastActive = true
        fastTimeline = []
        let gen = playGeneration
        let chunks = Self.chunkForStreaming(tail)

        Task { @MainActor in
            var cumulativeFrames: AVAudioFramePosition = 0
            var engineStarted = false
            for (i, chunk) in chunks.enumerated() {
                guard self.playGeneration == gen else { return }   // stopped/superseded
                guard let r = await self.renderFast(tail: chunk.text,
                                                    baseOffset: baseOffset + chunk.offset) else {
                    continue   // skip a chunk that failed to render; keep streaming
                }
                guard self.playGeneration == gen else { return }

                // Shift this chunk's word timings into whole-playback coordinates.
                for entry in r.timeline {
                    self.fastTimeline.append((entry.range, entry.frame + cumulativeFrames))
                }
                if !engineStarted {
                    guard self.beginFastEngine(format: r.buffer.format, speed: speed) else {
                        // Engine wouldn't start — fall back to native, once.
                        self.fastActive = false
                        self.speakNative(String((self.fullText as NSString).substring(from: baseOffset)))
                        return
                    }
                    engineStarted = true
                }
                self.scheduleFastBuffer(r.buffer, isLast: i == chunks.count - 1, gen: gen)
                cumulativeFrames += AVAudioFramePosition(r.buffer.frameLength)
            }
        }
    }

    private func beginFastEngine(format: AVAudioFormat, speed: Double) -> Bool {
        audioEngine.stop()
        audioEngine.connect(playerNode, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: format)
        timePitch.rate = Float(min(8.0, max(0.5, speed / Self.nativeMaxSpeed)))
        do {
            try audioEngine.start()
        } catch {
            NSLog("PurpleSpeak: fast playback engine failed (\(error)); using native.")
            return false
        }
        playerNode.play()
        startFastTimer()
        return true
    }

    private func scheduleFastBuffer(_ buffer: AVAudioPCMBuffer, isLast: Bool, gen: Int) {
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard isLast else { return }
            Task { @MainActor in
                guard let self, self.playGeneration == gen else { return }
                self.finishFast()
            }
        }
    }

    /// Split text into sentence-aligned chunks of roughly `maxChars`, each with
    /// its character offset within `text`, so streaming renders start fast.
    static func chunkForStreaming(_ text: String, maxChars: Int = 320) -> [(text: String, offset: Int)] {
        let ns = text as NSString
        var chunks: [(String, Int)] = []
        var accStart = -1
        var accEnd = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .bySentences) { _, r, _, _ in
            if accStart < 0 { accStart = r.location }
            accEnd = r.location + r.length
            if accEnd - accStart >= maxChars {
                chunks.append((ns.substring(with: NSRange(location: accStart, length: accEnd - accStart)), accStart))
                accStart = -1
            }
        }
        if accStart >= 0, accEnd > accStart {
            chunks.append((ns.substring(with: NSRange(location: accStart, length: accEnd - accStart)), accStart))
        }
        return chunks.isEmpty ? [(text, 0)] : chunks
    }

    private func startFastTimer() {
        fastTimer?.invalidate()
        // Poll playback position to drive the synced highlight. 25 fps is plenty.
        fastTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFastHighlight() }
        }
    }

    private func updateFastHighlight() {
        guard fastActive, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let pt = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        // playerTime.sampleTime is the position in the rendered buffer (the
        // player feeds frames into timePitch at the buffer rate), so it indexes
        // the timeline directly regardless of the stretch factor.
        let pos = pt.sampleTime
        var current: NSRange?
        for entry in fastTimeline {
            if entry.frame <= pos { current = entry.range } else { break }
        }
        if let r = current, r != spokenWordRange {
            spokenWordRange = r
            spokenSentenceRange = highlightSentence
                ? Self.sentenceRange(containing: r, in: fullText) : nil
        }
    }

    private func finishFast() {
        stopFast()
        isSpeaking = false
        isPaused = false
        spokenWordRange = nil
        spokenSentenceRange = nil
    }

    private func stopFast() {
        fastTimer?.invalidate()
        fastTimer = nil
        if fastActive {
            playerNode.stop()
            audioEngine.stop()
            fastActive = false
        }
        playGeneration += 1   // invalidate any in-flight render
        fastTimeline = []
    }

    /// Deep-copy a transient render buffer (the write callback may reuse it).
    static func copyBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameLength) else { return nil }
        dst.frameLength = src.frameLength
        let frames = Int(src.frameLength)
        let channels = Int(src.format.channelCount)
        if let s = src.floatChannelData, let d = dst.floatChannelData {
            for ch in 0..<channels { memcpy(d[ch], s[ch], frames * MemoryLayout<Float>.size) }
        } else if let s = src.int16ChannelData, let d = dst.int16ChannelData {
            for ch in 0..<channels { memcpy(d[ch], s[ch], frames * MemoryLayout<Int16>.size) }
        } else if let s = src.int32ChannelData, let d = dst.int32ChannelData {
            for ch in 0..<channels { memcpy(d[ch], s[ch], frames * MemoryLayout<Int32>.size) }
        } else {
            return nil
        }
        return dst
    }

    /// Concatenate same-format PCM buffers into one.
    static func combineBuffers(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let first = buffers.first else { return nil }
        let format = first.format
        let total = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        let channels = Int(format.channelCount)
        for b in buffers {
            let n = Int(b.frameLength)
            let off = Int(out.frameLength)
            if let s = b.floatChannelData, let d = out.floatChannelData {
                for ch in 0..<channels { memcpy(d[ch] + off, s[ch], n * MemoryLayout<Float>.size) }
            } else if let s = b.int16ChannelData, let d = out.int16ChannelData {
                for ch in 0..<channels { memcpy(d[ch] + off, s[ch], n * MemoryLayout<Int16>.size) }
            } else if let s = b.int32ChannelData, let d = out.int32ChannelData {
                for ch in 0..<channels { memcpy(d[ch] + off, s[ch], n * MemoryLayout<Int32>.size) }
            } else {
                return nil
            }
            out.frameLength += b.frameLength
        }
        return out
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
            // Ignore if a fast (time-stretched) playback has taken over.
            guard !self.fastActive else { return }
            self.isSpeaking = false
            self.isPaused = false
            self.spokenWordRange = nil
            self.spokenSentenceRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        // Intentionally does NOT reset isSpeaking. A cancel only happens because
        // stop() or a restart called stopSpeaking — stop() already resets state,
        // and a restart sets isSpeaking=true right after; letting this stale
        // callback flip isSpeaking=false would disable Stop / desync the UI
        // while the new utterance plays.
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

/// Delegate used only during offline render (`renderFast`) to capture each
/// word's start frame in the rendered buffer. Lives on the main thread for the
/// duration of one render.
private final class FastRenderCapture: NSObject, AVSpeechSynthesizerDelegate {
    let baseOffset: Int
    var buffers: [AVAudioPCMBuffer] = []
    var currentFrame: AVAudioFramePosition = 0
    var timeline: [(range: NSRange, frame: AVAudioFramePosition)] = []

    init(baseOffset: Int) { self.baseOffset = baseOffset }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // `currentFrame` is the frames rendered so far ≈ where this word begins.
        let absolute = NSRange(location: characterRange.location + baseOffset,
                               length: characterRange.length)
        timeline.append((absolute, currentFrame))
    }
}
