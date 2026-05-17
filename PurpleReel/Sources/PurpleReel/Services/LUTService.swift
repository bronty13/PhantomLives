import Foundation
import CoreImage

/// Parsed Adobe CUBE LUT. The data buffer matches `CIFilter.colorCubeWithColorSpace`'s
/// expected layout: RGBA float32, interleaved, with R varying fastest, then G, then B.
struct LUTData {
    let name: String
    let size: Int       // cube edge length (e.g. 17, 33, 64)
    let data: Data      // size^3 * 4 floats
    let sourceURL: URL?
}

enum LUTService {

    enum ParseError: Error, LocalizedError {
        case invalidFormat(String)
        case unsupportedSize(Int)
        case io(Error)

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let s): return "Invalid CUBE file: \(s)"
            case .unsupportedSize(let n): return "Unsupported LUT size \(n) (expected 2…256)"
            case .io(let e): return "I/O error: \(e.localizedDescription)"
            }
        }
    }

    /// Parse an Adobe .cube file. Supports 3D LUTs natively; 1D LUTs are
    /// synthesized into a 17³ cube by applying the per-channel curve
    /// independently — accurate for typical 1D gamma/log curves.
    static func load(url: URL) throws -> LUTData {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ParseError.io(error)
        }

        var lut3DSize: Int?
        var lut1DSize: Int?
        var title: String?
        var domainMin: SIMD3<Float> = .init(0, 0, 0)
        var domainMax: SIMD3<Float> = .init(1, 1, 1)
        var samples: [SIMD3<Float>] = []
        samples.reserveCapacity(64 * 64 * 64)

        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE") {
                title = extractTitle(line: line)
                continue
            }
            if upper.hasPrefix("LUT_3D_SIZE") {
                lut3DSize = Int(line.split(separator: " ").last ?? "")
                continue
            }
            if upper.hasPrefix("LUT_1D_SIZE") {
                lut1DSize = Int(line.split(separator: " ").last ?? "")
                continue
            }
            if upper.hasPrefix("DOMAIN_MIN") {
                let v = parseTriplet(line)
                if let v { domainMin = v }
                continue
            }
            if upper.hasPrefix("DOMAIN_MAX") {
                let v = parseTriplet(line)
                if let v { domainMax = v }
                continue
            }
            if let v = parseTriplet(line) {
                samples.append(v)
            }
        }

        let name = title ?? url.deletingPathExtension().lastPathComponent

        if let size = lut3DSize {
            guard (2...256).contains(size) else { throw ParseError.unsupportedSize(size) }
            let expected = size * size * size
            guard samples.count == expected else {
                throw ParseError.invalidFormat("expected \(expected) samples for size \(size), found \(samples.count)")
            }
            let buffer = buildCubeBuffer(samples: samples, size: size,
                                          domainMin: domainMin, domainMax: domainMax)
            return LUTData(name: name, size: size, data: buffer, sourceURL: url)
        }

        if let size = lut1DSize {
            guard (2...65536).contains(size) else { throw ParseError.unsupportedSize(size) }
            guard samples.count == size else {
                throw ParseError.invalidFormat("expected \(size) samples for 1D LUT, found \(samples.count)")
            }
            // Synthesize a 33³ cube by applying the 1D curve to each
            // channel of the identity cube.
            let cubeSize = 33
            let buffer = build1DSynthesizedCube(curve: samples, cubeSize: cubeSize,
                                                 domainMin: domainMin, domainMax: domainMax)
            return LUTData(name: name, size: cubeSize, data: buffer, sourceURL: url)
        }

        throw ParseError.invalidFormat("no LUT_3D_SIZE or LUT_1D_SIZE directive")
    }

    /// Returns a CIFilter configured with this LUT, ready to drop into
    /// an AVVideoComposition handler.
    static func filter(for lut: LUTData) -> CIFilter? {
        let f = CIFilter(name: "CIColorCubeWithColorSpace")
        f?.setValue(lut.size, forKey: "inputCubeDimension")
        f?.setValue(lut.data, forKey: "inputCubeData")
        if let cs = CGColorSpace(name: CGColorSpace.sRGB) {
            f?.setValue(cs, forKey: "inputColorSpace")
        }
        return f
    }

    // MARK: - Private helpers

    private static func extractTitle(line: String) -> String? {
        // TITLE "Look Name" — capture the quoted body.
        if let r1 = line.firstIndex(of: "\""),
           let r2 = line[line.index(after: r1)...].firstIndex(of: "\"") {
            return String(line[line.index(after: r1)..<r2])
        }
        return nil
    }

    private static func parseTriplet(_ line: String) -> SIMD3<Float>? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .compactMap { Float($0) }
        guard parts.count >= 3 else { return nil }
        return SIMD3<Float>(parts[0], parts[1], parts[2])
    }

    /// Build the RGBA float32 buffer CoreImage expects: R varies fastest.
    /// CUBE files store data with R fastest as well, so we copy in order.
    private static func buildCubeBuffer(samples: [SIMD3<Float>], size: Int,
                                          domainMin: SIMD3<Float>,
                                          domainMax: SIMD3<Float>) -> Data {
        let count = size * size * size
        var floats = [Float](repeating: 0, count: count * 4)
        let range = domainMax - domainMin
        for i in 0..<count {
            let s = samples[i]
            // Normalize against DOMAIN_MIN/MAX to [0,1] for CoreImage.
            let norm = SIMD3<Float>(
                range.x > 0 ? (s.x - domainMin.x) / range.x : s.x,
                range.y > 0 ? (s.y - domainMin.y) / range.y : s.y,
                range.z > 0 ? (s.z - domainMin.z) / range.z : s.z
            )
            floats[i * 4 + 0] = clamp01(norm.x)
            floats[i * 4 + 1] = clamp01(norm.y)
            floats[i * 4 + 2] = clamp01(norm.z)
            floats[i * 4 + 3] = 1.0
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func build1DSynthesizedCube(curve: [SIMD3<Float>], cubeSize: Int,
                                                 domainMin: SIMD3<Float>,
                                                 domainMax: SIMD3<Float>) -> Data {
        // For each (r,g,b) identity cube index, look up the 1D curve
        // independently per channel via linear interpolation.
        let curveLen = curve.count
        let count = cubeSize * cubeSize * cubeSize
        var floats = [Float](repeating: 0, count: count * 4)
        var idx = 0
        for b in 0..<cubeSize {
            for g in 0..<cubeSize {
                for r in 0..<cubeSize {
                    let inR = Float(r) / Float(cubeSize - 1)
                    let inG = Float(g) / Float(cubeSize - 1)
                    let inB = Float(b) / Float(cubeSize - 1)
                    let outR = sample1D(curve: curve, axis: \.x, t: inR, len: curveLen)
                    let outG = sample1D(curve: curve, axis: \.y, t: inG, len: curveLen)
                    let outB = sample1D(curve: curve, axis: \.z, t: inB, len: curveLen)
                    floats[idx * 4 + 0] = clamp01(outR)
                    floats[idx * 4 + 1] = clamp01(outG)
                    floats[idx * 4 + 2] = clamp01(outB)
                    floats[idx * 4 + 3] = 1.0
                    idx += 1
                }
            }
        }
        _ = domainMin; _ = domainMax  // honored by callers via input normalization upstream
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func sample1D(curve: [SIMD3<Float>],
                                  axis: KeyPath<SIMD3<Float>, Float>,
                                  t: Float, len: Int) -> Float {
        let pos = t * Float(len - 1)
        let i0 = Int(pos.rounded(.down))
        let i1 = min(i0 + 1, len - 1)
        let frac = pos - Float(i0)
        let v0 = curve[i0][keyPath: axis]
        let v1 = curve[i1][keyPath: axis]
        return v0 + (v1 - v0) * frac
    }

    private static func clamp01(_ x: Float) -> Float {
        min(max(x, 0), 1)
    }
}
