import Testing
import Foundation
@testable import SnRReplace

@Suite("Replacer")
struct ReplacerTests {

    func makeTmp() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snr-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test func literalReplaceUTF8() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.txt")
        try "the quick brown fox".write(to: url, atomically: true, encoding: .utf8)
        try await Replacer().apply(
            spec: ReplaceSpec(pattern: "brown", replacement: "red"),
            fileURL: url
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "the quick red fox")
    }

    @Test func regexReplaceWithBackref() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("b.txt")
        try "name=Alice; name=Bob".write(to: url, atomically: true, encoding: .utf8)
        try await Replacer().apply(
            spec: ReplaceSpec(pattern: "name=(\\w+)", replacement: "user($1)", mode: .regex),
            fileURL: url
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "user(Alice); user(Bob)")
    }

    @Test func counterToken() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("c.txt")
        try "ID=X\nID=X\nID=X".write(to: url, atomically: true, encoding: .utf8)
        try await Replacer().apply(
            spec: ReplaceSpec(
                pattern: "ID=X",
                replacement: "ID=#{1000,1,%04d}",
                counterEnabled: true
            ),
            fileURL: url
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "ID=1000\nID=1001\nID=1002")
    }

    @Test func pathInterpolation() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("d.txt")
        try "header here".write(to: url, atomically: true, encoding: .utf8)
        try await Replacer().apply(
            spec: ReplaceSpec(
                pattern: "header",
                replacement: "%FILE%:header",
                interpolatePathTokens: true
            ),
            fileURL: url
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "d.txt:header here")
    }

    @Test func binaryReplaceLengthPreserving() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("e.bin")
        try Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x01]).write(to: url)
        try await Replacer().apply(
            spec: ReplaceSpec(pattern: "CAFEBABE", replacement: "DEADBEEF", mode: .binary),
            fileURL: url
        )
        #expect(try Data(contentsOf: url) == Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]))
    }

    @Test func binaryReplaceLengthChangingDisallowedByDefault() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("f.bin")
        try Data([0xCA, 0xFE]).write(to: url)
        await #expect(throws: ReplaceError.self) {
            try await Replacer().apply(
                spec: ReplaceSpec(pattern: "CAFE", replacement: "DEADBEEF", mode: .binary),
                fileURL: url
            )
        }
    }

    @Test func binaryReplaceLengthChangingWithOptIn() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("g.bin")
        try Data([0xCA, 0xFE]).write(to: url)
        try await Replacer().apply(
            spec: ReplaceSpec(
                pattern: "CAFE", replacement: "DEADBEEF",
                mode: .binary,
                allowLengthChangingBinary: true
            ),
            fileURL: url
        )
        #expect(try Data(contentsOf: url) == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test func backupAndRestore() async throws {
        let dir = try makeTmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("h.txt")
        try "before".write(to: url, atomically: true, encoding: .utf8)
        let backups = try BackupManager(parentRoot: dir.appendingPathComponent("bk"))
        try await Replacer().apply(
            spec: ReplaceSpec(pattern: "before", replacement: "after"),
            fileURL: url,
            acceptedHits: nil,
            backups: backups
        )
        try await backups.writeManifest()
        // Allow the detached backup snapshot Task to run.
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(try String(contentsOf: url, encoding: .utf8) == "after")
        try await backups.restoreAll()
        #expect(try String(contentsOf: url, encoding: .utf8) == "before")
    }

    @Test func hexBytesRoundTrip() throws {
        #expect(try HexBytes.parse("CAFE BABE") == Data([0xCA, 0xFE, 0xBA, 0xBE]))
        #expect(try HexBytes.parse("0xDEADBEEF") == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(HexBytes.render(Data([0x01, 0x02])) == "01 02")
    }

    @Test func counterParsing() {
        let t = CounterToken.parse(template: "ID=#{100,5,%03d}-end")
        #expect(t?.start == 100)
        #expect(t?.step == 5)
        #expect(t?.format == "%03d")
        #expect(t?.render(value: 105, template: "ID=#{100,5,%03d}-end") == "ID=105-end")
    }
}
