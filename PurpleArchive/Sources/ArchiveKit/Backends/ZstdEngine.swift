import Foundation
import CZstd

/// Direct libzstd backend. In Phase 1 this owns the multithreaded `.zst` /
/// `.tar.zst` *creation* path (`ZSTD_c_nbWorkers = 0` → all cores), the
/// headline Apple-Silicon performance feature. Phase 0 only needs it to prove
/// the vendored, statically-linked libzstd actually links and runs.
public struct ZstdEngine: Sendable {
    public init() {}

    /// The linked libzstd version string, e.g. `"1.5.6"`.
    public static var version: String {
        guard let c = ZSTD_versionString() else { return "unknown" }
        return String(cString: c)
    }

    /// One-shot compress of `data` at the given level. Used by tests/the CLI to
    /// confirm a real round-trip through the vendored library.
    public func compress(_ data: Data, level: Int32 = 3) -> Data {
        let bound = ZSTD_compressBound(data.count)
        var dst = Data(count: bound)
        let written = dst.withUnsafeMutableBytes { dstPtr in
            data.withUnsafeBytes { srcPtr in
                ZSTD_compress(dstPtr.baseAddress, bound,
                              srcPtr.baseAddress, data.count, level)
            }
        }
        if ZSTD_isError(written) != 0 { return Data() }
        dst.removeSubrange(written..<dst.count)
        return dst
    }

    /// One-shot decompress. `expectedSize` bounds the output buffer.
    public func decompress(_ data: Data, expectedSize: Int) -> Data {
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { dstPtr in
            data.withUnsafeBytes { srcPtr in
                ZSTD_decompress(dstPtr.baseAddress, expectedSize,
                                srcPtr.baseAddress, data.count)
            }
        }
        if ZSTD_isError(written) != 0 { return Data() }
        dst.removeSubrange(written..<dst.count)
        return dst
    }
}

/// Versions of the vendored/linked compression libraries, for `parc version`
/// and the app's About box.
public enum ArchiveKitVersions {
    public static var libarchive: String { LibArchiveVersion.string }
    public static var zstd: String { ZstdEngine.version }
}
