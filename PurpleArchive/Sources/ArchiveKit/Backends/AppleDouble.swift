import Foundation

/// Minimal AppleDouble (`._name`) encoder for resource forks + Finder info,
/// byte-compatible with peeler's CLI output (and the macOS convention for
/// preserving classic-Mac resource forks on a POSIX filesystem). Layout
/// (resource-fork present): header(26) + 2 descriptors(24) + FinderInfo(32) +
/// resource data.
enum AppleDouble {
    private static let magic: UInt32 = 0x0005_1607
    private static let version: UInt32 = 0x0002_0000
    private static let headerSize = 26
    private static let entrySize = 12
    private static let finderLen = 32
    private static let entryFinderInfo: UInt32 = 9
    private static let entryRsrcFork: UInt32 = 2

    static func encode(resourceFork rsrc: Data, macType: UInt32,
                       macCreator: UInt32, finderFlags: UInt16) -> Data {
        let hasRsrc = !rsrc.isEmpty
        let numEntries = hasRsrc ? 2 : 1
        let finderOffset = headerSize + numEntries * entrySize
        let rsrcOffset = finderOffset + finderLen
        let total = hasRsrc ? rsrcOffset + rsrc.count : finderOffset + finderLen

        var buf = Data(count: total)
        buf.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!
            var o = 0
            func be32(_ v: UInt32, at off: Int) {
                p[off] = UInt8((v >> 24) & 0xFF); p[off+1] = UInt8((v >> 16) & 0xFF)
                p[off+2] = UInt8((v >> 8) & 0xFF); p[off+3] = UInt8(v & 0xFF)
            }
            func be16(_ v: UInt16, at off: Int) {
                p[off] = UInt8((v >> 8) & 0xFF); p[off+1] = UInt8(v & 0xFF)
            }
            be32(magic, at: 0); be32(version, at: 4)   // + 16 bytes filler (zero)
            be16(UInt16(numEntries), at: 24)
            o = headerSize
            // Descriptor 1: Finder Info.
            be32(entryFinderInfo, at: o); be32(UInt32(finderOffset), at: o+4); be32(UInt32(finderLen), at: o+8)
            o += entrySize
            // Descriptor 2: Resource Fork (if present).
            if hasRsrc {
                be32(entryRsrcFork, at: o); be32(UInt32(rsrcOffset), at: o+4); be32(UInt32(rsrc.count), at: o+8)
            }
            // Finder Info payload: type(4) + creator(4) + flags(2) + 22 zero.
            be32(macType, at: finderOffset); be32(macCreator, at: finderOffset+4)
            be16(finderFlags, at: finderOffset+8)
        }
        if hasRsrc { buf.replaceSubrange(rsrcOffset..<total, with: rsrc) }
        return buf
    }
}
