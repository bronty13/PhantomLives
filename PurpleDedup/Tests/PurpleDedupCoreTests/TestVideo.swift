import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

/// Generates short test videos on disk using AVAssetWriter. Tests get reproducible,
/// no-binary-blobs fixtures: the Swift code below is the entire video.
enum TestVideo {

    enum BuildError: Error, LocalizedError {
        case writerFailed(String)
        case noPixelBufferPool
        case bufferAllocFailed
        case bufferLockFailed
        case ctxFailed

        var errorDescription: String? {
            switch self {
            case .writerFailed(let s): return "AVAssetWriter: \(s)"
            case .noPixelBufferPool:   return "AVAssetWriter never produced a pixel buffer pool"
            case .bufferAllocFailed:   return "Could not allocate pixel buffer"
            case .bufferLockFailed:    return "Could not lock pixel buffer"
            case .ctxFailed:           return "Could not create CGContext over pixel buffer"
            }
        }
    }

    /// Build a .mov at `url` from the supplied CGImages. Each frame is one second long;
    /// a sequence of N images produces an N-second video. Codec: H.264 (the most common
    /// choice; AVAssetImageGenerator decodes it without surprises).
    @discardableResult
    static func build(
        frames: [CGImage],
        size: CGSize,
        url: URL,
        framesPerSecond: Int32 = 1
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw BuildError.writerFailed(error.localizedDescription)
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs
        )
        guard writer.canAdd(input) else {
            throw BuildError.writerFailed("cannot add input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw BuildError.writerFailed("startWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        // Wait for the pool to become available — it appears asynchronously after
        // startWriting on some platforms.
        var attempts = 0
        while adaptor.pixelBufferPool == nil && attempts < 50 {
            try await Task.sleep(nanoseconds: 10_000_000)
            attempts += 1
        }
        guard let pool = adaptor.pixelBufferPool else {
            throw BuildError.noPixelBufferPool
        }

        for (i, image) in frames.enumerated() {
            // Backpressure: spin until the input is ready. Real test videos are short
            // enough that this loop iterates at most a handful of times.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            var pb: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard status == kCVReturnSuccess, let buffer = pb else {
                throw BuildError.bufferAllocFailed
            }
            try draw(image: image, into: buffer, size: size)

            let time = CMTime(value: Int64(i), timescale: framesPerSecond)
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw BuildError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        return url
    }

    private static func draw(image: CGImage, into buffer: CVPixelBuffer, size: CGSize) throws {
        let lockResult = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockResult == kCVReturnSuccess else { throw BuildError.bufferLockFailed }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw BuildError.ctxFailed }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    // MARK: - frame patterns

    /// A solid-coloured frame at the requested size. Useful for "two completely
    /// different videos" tests.
    static func solidFrame(rgb: (UInt8, UInt8, UInt8), size: CGSize) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 4 * Int(size.width),
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return ctx.makeImage()!
    }

    /// Diagonal gradient with a phase offset. Two videos sharing the same offset
    /// sequence are perceptually identical; sequences with a steady phase shift are
    /// related but not perfectly aligned (good for the alignment-window test).
    static func gradientFrame(seed: Int, size: CGSize) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let w = Int(size.width)
        let h = Int(size.height)
        let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 4 * w,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            for x in 0..<w {
                let v = ((x + y + seed * 8) * 255 / (w + h)) & 0xFF
                let i = (y * w + x) * 4
                // BGRA in memory due to byteOrder32Little + premultipliedFirst
                buf[i + 0] = UInt8(v)
                buf[i + 1] = UInt8(v)
                buf[i + 2] = UInt8(v)
                buf[i + 3] = 255
            }
        }
        return ctx.makeImage()!
    }
}
