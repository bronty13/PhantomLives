import Foundation
import AVFoundation
import Accelerate
import CryptoKit

/// Downsampled audio waveform: one peak amplitude per bucket, in [0, 1].
struct WaveformSamples: Codable {
    let peaks: [Float]
    let sourcePath: String
    let bucketCount: Int
}

/// Pre-renders a downsampled peak-amplitude array for a video/audio
/// file so the player scrubber can paint a waveform under itself.
///
/// We read the first audio track via AVAssetReader as 16-bit signed
/// little-endian PCM, accumulate `|sample|` into N buckets, and
/// normalize to [0, 1]. One pass through the file at full speed —
/// typical 5-min HEVC clip processes in ~1-2s on Apple Silicon.
enum WaveformService {

    /// Generate a waveform of `bucketCount` peaks for `url`. Returns
    /// nil if the file has no audio track or reading fails.
    static func generate(url: URL, bucketCount: Int = 800) async -> WaveformSamples? {
        await Task.detached(priority: .utility) {
            generateSync(url: url, bucketCount: bucketCount)
        }.value
    }

    /// Disk-cached variant for the list-view "Waveform" column
    /// (Kyno-parity row 68). The peaks file is keyed by
    /// `(path, modtime, bucketCount)` so touching the source
    /// invalidates without nuking the whole cache. Generation cost
    /// is a one-time 1-2s per clip; subsequent loads are a JSON
    /// read off SSD.
    static func cachedOrGenerate(url: URL, bucketCount: Int = 160) async -> WaveformSamples? {
        let cacheFile: URL
        do {
            cacheFile = try cacheFileURL(for: url, bucketCount: bucketCount)
        } catch {
            return await generate(url: url, bucketCount: bucketCount)
        }
        if let data = try? Data(contentsOf: cacheFile),
           let samples = try? JSONDecoder().decode(WaveformSamples.self, from: data) {
            return samples
        }
        let samples = await generate(url: url, bucketCount: bucketCount)
        if let samples,
           let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: cacheFile)
        }
        return samples
    }

    private static func cacheFileURL(for url: URL, bucketCount: Int) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("PurpleReel/waveforms", isDirectory: true)
        try FileManager.default.createDirectory(at: support,
                                                  withIntermediateDirectories: true)
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let mod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(mod)|\(bucketCount)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return support.appendingPathComponent("\(String(hex.prefix(32))).json")
    }

    static func generateSync(url: URL, bucketCount: Int) -> WaveformSamples? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            // No audio track (or AVFoundation couldn't read one); not
            // an error — the scrubber simply renders without a
            // waveform layer underneath.
            return nil
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return nil
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        // Estimate total sample frames so we can size buckets up front.
        let totalSeconds = CMTimeGetSeconds(asset.duration)
        let sampleRate = readSampleRate(track: track) ?? 48000
        let channels = readChannelCount(track: track) ?? 2
        let totalFrames = max(1, Int(totalSeconds * sampleRate))
        let framesPerBucket = max(1, totalFrames / bucketCount)

        var buckets = [Float](repeating: 0, count: bucketCount)
        var frameIndex = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                         totalLengthOut: &length, dataPointerOut: &dataPointer)
            guard let ptr = dataPointer else { continue }
            ptr.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                let frameCount = length / (2 * channels)
                for f in 0..<frameCount {
                    let bucket = min(bucketCount - 1, frameIndex / framesPerBucket)
                    // Channel 0 only — mono-summing the channels is
                    // slightly more accurate but doubles work for ~0
                    // visual gain.
                    let sample = abs(Float(samples[f * channels])) / 32768.0
                    if sample > buckets[bucket] { buckets[bucket] = sample }
                    frameIndex += 1
                }
            }
        }

        // Light log-curve so quiet dialog isn't invisible against
        // loud transients.
        var output_buckets = [Float](repeating: 0, count: bucketCount)
        for i in 0..<bucketCount {
            let v = buckets[i]
            output_buckets[i] = v > 0 ? sqrtf(v) : 0
        }

        return WaveformSamples(
            peaks: output_buckets,
            sourcePath: url.path,
            bucketCount: bucketCount
        )
    }

    // MARK: - Track introspection

    private static func readSampleRate(track: AVAssetTrack) -> Double? {
        guard let desc = track.formatDescriptions.first else { return nil }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
            desc as! CMFormatDescription
        )
        return asbd?.pointee.mSampleRate
    }

    private static func readChannelCount(track: AVAssetTrack) -> Int? {
        guard let desc = track.formatDescriptions.first else { return nil }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
            desc as! CMFormatDescription
        )
        return asbd.map { Int($0.pointee.mChannelsPerFrame) }
    }
}
