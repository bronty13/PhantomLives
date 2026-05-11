import Foundation
import AVFoundation

/// Synthesized cue bank. All audio is generated procedurally — sine + noise
/// envelopes — so the app ships no audio assets and the cues are unmistakably
/// our own. If the user drops a replacement WAV/CAF/AIFF into
/// `~/Documents/ElectronicDetective Assets/audio/` (matching the cue name),
/// that file is preferred at play time.
@MainActor
final class SoundBank: ObservableObject {
    static let shared = SoundBank()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sampleRate: Double = 44_100
    private var players: [AssetResolver.AudioCue: AVAudioPlayerNode] = [:]
    private var defaultBuffers: [AssetResolver.AudioCue: AVAudioPCMBuffer] = [:]
    private var userBufferCache: [URL: AVAudioPCMBuffer] = [:]

    /// When false, calls to `play(_:)` no-op. Toggled via `AppSettings`.
    var audioEnabled: Bool = true
    /// When false, the key-click cue is suppressed even if `audioEnabled` is on.
    /// Other cues are unaffected.
    var keyClickEnabled: Bool = true

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let mixer = engine.mainMixerNode
        for cue in AssetResolver.AudioCue.allCases {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            players[cue] = player
            defaultBuffers[cue] = synthesize(cue)
        }
        do {
            try engine.start()
        } catch {
            NSLog("ElectronicDetective: AVAudioEngine failed to start — \(error)")
        }
    }

    // MARK: - Public

    func play(_ cue: AssetResolver.AudioCue) {
        guard audioEnabled else { return }
        if cue == .key, !keyClickEnabled { return }
        guard let player = players[cue], let buffer = bufferToPlay(for: cue) else { return }
        // Re-scheduling on a busy node truncates the previous play. That's
        // the right behavior for short cues — a second keypress shouldn't
        // queue up behind the previous click.
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !engine.isRunning { try? engine.start() }
        player.play()
    }

    // MARK: - User-asset preference

    private func bufferToPlay(for cue: AssetResolver.AudioCue) -> AVAudioPCMBuffer? {
        if let url = AssetResolver.shared.audioURL(cue) {
            if let cached = userBufferCache[url] { return cached }
            if let loaded = loadBuffer(from: url) {
                userBufferCache[url] = loaded
                return loaded
            }
        }
        return defaultBuffers[cue]
    }

    private func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let cap = AVAudioFrameCount(file.length)
        guard cap > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: cap)
        else { return nil }
        do {
            try file.read(into: buf)
            return buf
        } catch {
            return nil
        }
    }

    // MARK: - Synthesis

    private func synthesize(_ cue: AssetResolver.AudioCue) -> AVAudioPCMBuffer {
        switch cue {
        case .bong:    return Synth.bong(format: format, sampleRate: sampleRate)
        case .key:     return Synth.keyClick(format: format, sampleRate: sampleRate)
        case .gunshot: return Synth.gunshot(format: format, sampleRate: sampleRate)
        case .siren:   return Synth.siren(format: format, sampleRate: sampleRate)
        case .dirge:   return Synth.dirge(format: format, sampleRate: sampleRate)
        }
    }
}

/// Pure-function synthesis primitives. Each cue is short (< 2.5s) and
/// generated once at app launch into a single mono float32 buffer.
enum Synth {

    static func bong(format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer {
        let durEach = 0.55
        let gap = 0.06
        let bongFreqs = [220.0, 165.0, 110.0]
        let total = Double(bongFreqs.count) * (durEach + gap)
        let buf = makeBuffer(sampleRate: sampleRate, seconds: total, format: format)
        for (i, freq) in bongFreqs.enumerated() {
            let start = Int(Double(i) * (durEach + gap) * sampleRate)
            writeBellTone(into: buf, startSample: start, seconds: durEach,
                          freq: freq, amplitude: 0.55, sampleRate: sampleRate)
        }
        return buf
    }

    static func keyClick(format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer {
        let total = 0.06
        let buf = makeBuffer(sampleRate: sampleRate, seconds: total, format: format)
        let data = buf.floatChannelData![0]
        let count = Int(buf.frameLength)
        for s in 0..<count {
            let t = Double(s) / sampleRate
            let envNoise = exp(-t * 220)
            let envTick  = exp(-t * 60)
            let n = (Double.random(in: -1...1)) * envNoise
            let tick = 0.5 * sin(2 * .pi * 60 * t) * envTick
            data[s] = Float(0.35 * (n + tick))
        }
        return buf
    }

    static func gunshot(format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer {
        let total = 0.45
        let buf = makeBuffer(sampleRate: sampleRate, seconds: total, format: format)
        let data = buf.floatChannelData![0]
        let count = Int(buf.frameLength)
        // Single seed for repeatable "voice"; high-frequency noise gated by a
        // very fast attack + slower decay; layered low rumble.
        for s in 0..<count {
            let t = Double(s) / sampleRate
            let attack = 1 - exp(-t * 800)
            let decay  = exp(-t * 8)
            let noise  = Double.random(in: -1...1)
            let rumble = sin(2 * .pi * 55 * t) * exp(-t * 5)
            data[s] = Float(0.8 * attack * decay * (0.85 * noise + 0.45 * rumble))
        }
        return buf
    }

    static func siren(format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer {
        let total = 1.8
        let buf = makeBuffer(sampleRate: sampleRate, seconds: total, format: format)
        let data = buf.floatChannelData![0]
        let count = Int(buf.frameLength)
        for s in 0..<count {
            let t = Double(s) / sampleRate
            // Two-tone wail: alternate between 880 and 660 Hz on ~0.45s phases,
            // gently overall-enveloped so it fades in and out.
            let phase = Int((t / 0.45).truncatingRemainder(dividingBy: 2.0))
            let freq: Double = phase == 0 ? 880 : 660
            let env = sin(.pi * t / total)   // 0 → 1 → 0 over the buffer
            data[s] = Float(0.45 * env * sin(2 * .pi * freq * t))
        }
        return buf
    }

    static func dirge(format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer {
        // Descending four-note motif on a minor triad, each note rung as a
        // bell tone (sine + slow decay). Not a copy of any specific piece.
        let notes: [Double] = [220.0, 174.61, 146.83, 110.0]  // A3, F3, D3, A2
        let durEach = 0.5
        let total = Double(notes.count) * durEach
        let buf = makeBuffer(sampleRate: sampleRate, seconds: total, format: format)
        for (i, freq) in notes.enumerated() {
            let start = Int(Double(i) * durEach * sampleRate)
            writeBellTone(into: buf, startSample: start, seconds: durEach,
                          freq: freq, amplitude: 0.45, sampleRate: sampleRate)
        }
        return buf
    }

    // MARK: - Helpers

    private static func makeBuffer(sampleRate: Double, seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(sampleRate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buf.frameLength = count
        // Zero-fill is required because frameCapacity allocation does not
        // guarantee silence — leftover memory can manifest as clicks.
        let data = buf.floatChannelData![0]
        for i in 0..<Int(count) { data[i] = 0 }
        return buf
    }

    /// Adds a single sine tone with a soft attack + exponential decay into
    /// the buffer at `startSample`. Idempotent across calls (additive), so
    /// multiple notes can layer if desired.
    private static func writeBellTone(into buf: AVAudioPCMBuffer,
                                      startSample: Int, seconds: Double,
                                      freq: Double, amplitude: Double,
                                      sampleRate: Double) {
        let data = buf.floatChannelData![0]
        let totalSamples = Int(buf.frameLength)
        let noteSamples = Int(sampleRate * seconds)
        let end = min(totalSamples, startSample + noteSamples)
        guard startSample >= 0, startSample < totalSamples else { return }
        for s in startSample..<end {
            let t = Double(s - startSample) / sampleRate
            let attack = 1 - exp(-t * 80)
            let decay  = exp(-t * 4.5)
            let env = attack * decay
            data[s] += Float(amplitude * env * sin(2 * .pi * freq * t))
        }
    }
}
