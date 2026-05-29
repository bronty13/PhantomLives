import Foundation
import AVFoundation

/// Reads an audio (or video-with-audio) file via AVFoundation and
/// downsamples it to a fixed number of normalized [0, 1] peak values.
/// Output shape is two arrays of the same length — `min` (the most
/// negative sample magnitude in each bucket, expressed as a positive
/// number) and `max` (the most positive). Drawing code renders these
/// as the upper and lower halves of the waveform.
///
/// One downsampled waveform is ~12 KB for 1500 peaks — cheap to cache,
/// cheap to redraw. Reading the full source is what's expensive, so
/// the WaveformCache stores results between launches.
enum WaveformGenerator {

    struct Result: Sendable, Codable, Equatable {
        var minPeaks: [Float]
        var maxPeaks: [Float]
        var sampleRate: Double
        var totalSamples: Int64
        var duration: Double { Double(totalSamples) / max(sampleRate, 1) }
    }

    enum GenerationError: Error {
        case noAudioTrack
        case readerSetupFailed(String)
        case readFailed(String)
    }

    /// Generate a `targetPeaks`-bucket waveform from the file at
    /// `url`. Mixed down to mono before bucketing — visual only;
    /// playback path stays untouched.
    static func generate(url: URL,
                         targetPeaks: Int = 1500) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw GenerationError.noAudioTrack
        }
        let formatDescriptions = try await track.load(.formatDescriptions)
        let sampleRate: Double = {
            guard let fd = formatDescriptions.first else { return 44100 }
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd) {
                return asbd.pointee.mSampleRate
            }
            return 44100
        }()

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw GenerationError.readerSetupFailed(error.localizedDescription)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1  // mix down to mono for the waveform
        ]
        let output = AVAssetReaderTrackOutput(track: track,
                                              outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw GenerationError.readerSetupFailed("reader rejected the audio output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw GenerationError.readerSetupFailed(
                reader.error?.localizedDescription ?? "unknown reader start failure"
            )
        }

        // First pass: stream samples into a bucket accumulator. We
        // don't know the exact sample count up front, so size buckets
        // dynamically by partitioning each incoming chunk
        // proportionally. To keep the math simple, accumulate all
        // samples into a single `[Float]` first (a 5-minute mono 48k
        // clip is 14.4M floats = 57 MB — fine for the kinds of
        // "short clip" PurpleVoice targets) then bucket at the end.
        // For longer files we could swap to a true streaming bucketer.
        var samples: [Float] = []
        samples.reserveCapacity(1024 * 1024)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                CMSampleBufferInvalidate(sampleBuffer)
                continue
            }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block,
                                         atOffset: 0,
                                         lengthAtOffsetOut: nil,
                                         totalLengthOut: &length,
                                         dataPointerOut: &dataPointer)
            if let ptr = dataPointer, length > 0 {
                let floatCount = length / MemoryLayout<Float>.size
                ptr.withMemoryRebound(to: Float.self, capacity: floatCount) { fptr in
                    samples.append(contentsOf: UnsafeBufferPointer(start: fptr,
                                                                    count: floatCount))
                }
            }
            CMSampleBufferInvalidate(sampleBuffer)
        }

        if reader.status == .failed {
            throw GenerationError.readFailed(
                reader.error?.localizedDescription ?? "unknown read failure"
            )
        }

        let totalSamples = Int64(samples.count)
        let buckets = max(1, min(targetPeaks, samples.count))
        var minPeaks = [Float](repeating: 0, count: buckets)
        var maxPeaks = [Float](repeating: 0, count: buckets)

        if samples.isEmpty {
            return Result(minPeaks: minPeaks,
                          maxPeaks: maxPeaks,
                          sampleRate: sampleRate,
                          totalSamples: 0)
        }

        let bucketSize = Double(samples.count) / Double(buckets)
        for i in 0..<buckets {
            let start = Int(Double(i) * bucketSize)
            let end   = min(Int(Double(i + 1) * bucketSize), samples.count)
            guard start < end else { continue }
            var lo: Float = 0
            var hi: Float = 0
            for s in samples[start..<end] {
                if s < lo { lo = s }
                if s > hi { hi = s }
            }
            // Express the negative bound as a positive magnitude so
            // drawing code can extrude both halves from a common
            // baseline without worrying about signs.
            minPeaks[i] = -lo
            maxPeaks[i] = hi
        }

        // Normalize to [0, 1] against the global peak. Otherwise a
        // quiet clip renders as a thin line and a loud one fills the
        // whole pane — both unreadable.
        let peak = max(minPeaks.max() ?? 0, maxPeaks.max() ?? 0, 0.0001)
        for i in 0..<buckets {
            minPeaks[i] = minPeaks[i] / peak
            maxPeaks[i] = maxPeaks[i] / peak
        }

        return Result(minPeaks: minPeaks,
                      maxPeaks: maxPeaks,
                      sampleRate: sampleRate,
                      totalSamples: totalSamples)
    }
}
