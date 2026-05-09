import Foundation
import CoreGraphics
import ImageIO
import Accelerate

/// Perceptual fingerprints for a single image. Both hashes are 64-bit; compare two images
/// by Hamming distance on `phash`. `dhash` is computed alongside as a cross-check —
/// pHash and dHash catch slightly different transformations, so storing both lets future
/// phases tighten matching criteria without re-decoding images.
public struct PerceptualHash: Sendable, Hashable, Codable {
    public let phash: UInt64
    public let dhash: UInt64
    public let width: Int
    public let height: Int

    public init(phash: UInt64, dhash: UInt64, width: Int, height: Int) {
        self.phash = phash
        self.dhash = dhash
        self.width = width
        self.height = height
    }

    /// Hamming distance between two 64-bit hashes — the count of bit positions that
    /// differ. The integer popcount is one cycle on Apple Silicon (CNT instruction); BK-
    /// tree queries call this in tight loops, so we keep it inlinable.
    @inlinable
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

public enum PerceptualHasherError: Error, LocalizedError {
    case decodeFailed(URL)
    case rasterizeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed(let u):    return "Could not decode image at \(u.path)"
        case .rasterizeFailed(let u): return "Could not rasterize image at \(u.path)"
        }
    }
}

/// Computes pHash + dHash for an image on disk. Decoding is delegated to ImageIO so we
/// support every format macOS knows (HEIC, JPEG, PNG, RAW, …) without third-party deps.
/// EXIF orientation is honored — a photo rotated in metadata produces the same hash as
/// the same photo "physically" rotated.
///
/// Algorithm summary (per the requirements doc § 5.5):
///
///   pHash:
///     1. Decode → CGImage with EXIF transform applied
///     2. Draw into a 32×32 single-channel (grayscale) buffer with anti-aliased resampling
///     3. 2D DCT (1D-along-rows then 1D-along-columns via vDSP)
///     4. Top-left 8×8 of DCT coefficients = low-frequency components
///     5. Hash = 64 bits, bit i = (coef_i > median ? 1 : 0)
///
///   dHash:
///     1. Same decode/orientation logic, draw into a 9×8 grayscale buffer
///     2. For each row, compare adjacent pixels: bit = (right > left ? 1 : 0)
///     3. Concatenate 8 rows × 8 bits = 64-bit hash
public struct PerceptualHasher: Sendable {

    /// Side length of the pHash workspace. 32 is the canonical choice — large enough that
    /// the 8×8 DCT block captures meaningful low-frequency content, small enough that the
    /// DCT itself takes microseconds.
    public static let phashSide = 32

    /// dHash uses a 9-wide × 8-tall buffer so each row produces 8 gradient bits (9 - 1).
    public static let dhashWidth = 9
    public static let dhashHeight = 8

    public init() {}

    /// Hash a file. Throws if the image cannot be decoded; returns nil only for the
    /// degenerate case where rasterization succeeded but produced an all-zero buffer
    /// (treat as "we don't have a fingerprint for this") — never silently returns wrong
    /// data.
    public func hash(imageAt url: URL) throws -> PerceptualHash {
        // CRITICAL PERFORMANCE NOTE — embedded thumbnails:
        //
        // We pass `CreateThumbnailFromImageIfAbsent` (NOT `…Always`). On every iPhone
        // JPEG/HEIC, this returns the embedded EXIF thumbnail (~150-500 px) which
        // ImageIO can decode in ~1 ms, vs ~50 ms for a full 24-MP decode + downsample.
        // For perceptual hashing the further downsample to 32×32 produces equivalent
        // pHash bits either way — embedded thumbnails are higher resolution than our
        // DCT input.
        //
        // For files without an embedded thumbnail (rare for camera output, more common
        // for screenshots / synthetic test images), ImageIO falls back to a full
        // decode automatically.
        //
        // The previous `…Always` flag was the dominant cost on multi-thousand-file
        // libraries — Gemini's "scans in moments" speed comes from this same trick.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source, 0,
                  [
                      kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: max(Self.phashSide * 8, 256),
                      kCGImageSourceShouldCacheImmediately: false,
                  ] as CFDictionary
              ) else {
            throw PerceptualHasherError.decodeFailed(url)
        }

        // The thumbnail is capped at our requested max size — its `cgImage.width` is
        // therefore the *thumbnail* dimension, not the file's original. Pull the real
        // dimensions from CGImageSource properties (which read the file header without
        // decoding pixels). Fall back to the thumbnail size if properties are missing —
        // some exotic formats don't expose dimensions in metadata.
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let originalWidth = (props?[kCGImagePropertyPixelWidth] as? Int) ?? cgImage.width
        let originalHeight = (props?[kCGImagePropertyPixelHeight] as? Int) ?? cgImage.height

        return try hash(cgImage: cgImage, originalWidth: originalWidth, originalHeight: originalHeight, errorContext: url)
    }

    /// Hash a CGImage that's already been decoded — used by `VideoFingerprinter` when it
    /// pulls frames out of `AVAssetImageGenerator` (no on-disk URL per frame). The
    /// `errorContext` URL is purely for log/error messages; pass the source-asset URL.
    public func hash(
        cgImage: CGImage,
        originalWidth: Int,
        originalHeight: Int,
        errorContext: URL
    ) throws -> PerceptualHash {
        let phashGray = try rasterizeGrayscale(
            image: cgImage, width: Self.phashSide, height: Self.phashSide, url: errorContext
        )
        let dhashGray = try rasterizeGrayscale(
            image: cgImage, width: Self.dhashWidth, height: Self.dhashHeight, url: errorContext
        )
        let phash = computePHash(grayscale: phashGray, side: Self.phashSide)
        let dhash = computeDHash(grayscale: dhashGray, width: Self.dhashWidth, height: Self.dhashHeight)
        return PerceptualHash(phash: phash, dhash: dhash, width: originalWidth, height: originalHeight)
    }

    /// All four rotation hashes for an image, in `[0°, 90°, 180°, 270°]` order.
    /// Used by `RotatedClusterer` (FR-2.7) — two photos are rotation-duplicates
    /// if any rotation of one is within Hamming threshold of any rotation of
    /// the other. Cost: one HEIC/JPEG decode + four DCTs (the DCT is fast,
    /// the decode dominates), so this is ~the same wall time as a single
    /// hash on real photo workloads.
    public func hashWithRotations(imageAt url: URL) throws -> [UInt64] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source, 0,
                  [
                      kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: max(Self.phashSide * 8, 256),
                      kCGImageSourceShouldCacheImmediately: false,
                  ] as CFDictionary
              ) else {
            throw PerceptualHasherError.decodeFailed(url)
        }
        let g0 = try rasterizeGrayscale(
            image: cgImage, width: Self.phashSide, height: Self.phashSide, url: url
        )
        let g90 = Self.rotate90Clockwise(g0, side: Self.phashSide)
        let g180 = Self.rotate180(g0, side: Self.phashSide)
        let g270 = Self.rotate90Clockwise(g180, side: Self.phashSide)
        return [
            computePHash(grayscale: g0, side: Self.phashSide),
            computePHash(grayscale: g90, side: Self.phashSide),
            computePHash(grayscale: g180, side: Self.phashSide),
            computePHash(grayscale: g270, side: Self.phashSide),
        ]
    }

    /// Rotate a square row-major byte buffer 90° clockwise. (x, y) → (side-1-y, x).
    static func rotate90Clockwise(_ src: [UInt8], side: Int) -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: src.count)
        for y in 0..<side {
            for x in 0..<side {
                let srcIdx = y * side + x
                let dstIdx = x * side + (side - 1 - y)
                dst[dstIdx] = src[srcIdx]
            }
        }
        return dst
    }

    /// Rotate a square row-major byte buffer 180°. Trivially the same as
    /// reversing the flat buffer because (x, y) → (side-1-x, side-1-y) is
    /// the same index permutation as `i → N-1-i`.
    static func rotate180(_ src: [UInt8], side: Int) -> [UInt8] {
        Array(src.reversed())
    }

    // MARK: - rasterize

    /// Render a CGImage into a tightly-packed 8-bit grayscale buffer of the requested size.
    /// We use Core Graphics' built-in resampling — sufficient for perceptual hashing and
    /// far simpler than going through vImage's scaler. Input is converted to grayscale by
    /// the gray colorspace; alpha is composited against opaque black implicitly.
    private func rasterizeGrayscale(
        image: CGImage, width: Int, height: Int, url: URL
    ) throws -> [UInt8] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var buffer = [UInt8](repeating: 0, count: width * height)

        let success = buffer.withUnsafeMutableBufferPointer { bp -> Bool in
            guard let context = CGContext(
                data: bp.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !success { throw PerceptualHasherError.rasterizeFailed(url) }
        return buffer
    }

    // MARK: - pHash

    /// Compute the 64-bit pHash from a side×side grayscale buffer. Uses Accelerate's vDSP
    /// 1D DCT applied row-wise then column-wise to compute the 2D DCT — a standard
    /// separable formulation that's significantly faster than a hand-rolled 2D pass and
    /// preserves the same coefficients.
    private func computePHash(grayscale: [UInt8], side: Int) -> UInt64 {
        // Convert UInt8 → Float for vDSP. Pixels in [0,255]; the DCT doesn't care about
        // absolute scale, only relative magnitudes.
        var pixels = [Float](repeating: 0, count: side * side)
        for i in 0..<grayscale.count {
            pixels[i] = Float(grayscale[i])
        }

        // Build a single DCT setup for length `side` and reuse it for rows AND columns —
        // vDSP setups are length-bound, not direction-bound.
        guard let setup = vDSP_DCT_CreateSetup(nil, vDSP_Length(side), .II) else {
            // 32 is a supported size, so this should never happen in practice. Fall back
            // to an all-zero hash so a single weird platform doesn't take down a scan.
            Log.hash.error("vDSP_DCT_CreateSetup returned nil for side=\(side)")
            return 0
        }
        // DCT setups share a destructor with DFT — Accelerate implements DCT on top of
        // DFT, and the docs explicitly say to use vDSP_DFT_DestroySetup for both.
        defer { vDSP_DFT_DestroySetup(setup) }

        // Row-wise 1D DCT.
        var rowDCT = [Float](repeating: 0, count: side * side)
        for r in 0..<side {
            let inSlice = Array(pixels[(r * side)..<((r + 1) * side)])
            var outSlice = [Float](repeating: 0, count: side)
            inSlice.withUnsafeBufferPointer { ip in
                outSlice.withUnsafeMutableBufferPointer { op in
                    vDSP_DCT_Execute(setup, ip.baseAddress!, op.baseAddress!)
                }
            }
            for c in 0..<side {
                rowDCT[r * side + c] = outSlice[c]
            }
        }

        // Column-wise 1D DCT on the row-DCT result. Transpose-via-stride to avoid
        // building an explicit transpose array.
        var twoDDCT = [Float](repeating: 0, count: side * side)
        for c in 0..<side {
            var col = [Float](repeating: 0, count: side)
            for r in 0..<side {
                col[r] = rowDCT[r * side + c]
            }
            var outCol = [Float](repeating: 0, count: side)
            col.withUnsafeBufferPointer { ip in
                outCol.withUnsafeMutableBufferPointer { op in
                    vDSP_DCT_Execute(setup, ip.baseAddress!, op.baseAddress!)
                }
            }
            for r in 0..<side {
                twoDDCT[r * side + c] = outCol[r]
            }
        }

        // Top-left 8×8 block of DCT coefficients = low-frequency content.
        var lowFreq = [Float]()
        lowFreq.reserveCapacity(64)
        for r in 0..<8 {
            for c in 0..<8 {
                lowFreq.append(twoDDCT[r * side + c])
            }
        }

        // Median over the 64 values. The DC term [0,0] is included — it carries average
        // brightness and the resulting bit is almost always 1, but excluding it changes
        // the median slightly so we'd need separate code paths to compare. Including it
        // matches the most common pHash convention (Zauner '10).
        let sorted = lowFreq.sorted()
        let median = (sorted[31] + sorted[32]) / 2

        var hash: UInt64 = 0
        for i in 0..<64 {
            if lowFreq[i] > median {
                hash |= (UInt64(1) << UInt64(i))
            }
        }
        return hash
    }

    // MARK: - dHash

    /// 9×8 grayscale → 64 bits, where bit (r * 8 + c) = (pixel[r,c+1] > pixel[r,c] ? 1 : 0).
    /// Catches a different class of similarity than pHash: dHash is sensitive to local
    /// gradient direction, pHash to overall frequency profile.
    private func computeDHash(grayscale: [UInt8], width: Int, height: Int) -> UInt64 {
        var hash: UInt64 = 0
        var bitIndex = 0
        for r in 0..<height {
            for c in 0..<(width - 1) {
                let left = grayscale[r * width + c]
                let right = grayscale[r * width + c + 1]
                if right > left {
                    hash |= (UInt64(1) << UInt64(bitIndex))
                }
                bitIndex += 1
            }
        }
        return hash
    }
}
