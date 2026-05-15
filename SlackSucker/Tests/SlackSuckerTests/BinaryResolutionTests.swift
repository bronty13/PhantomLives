import Foundation
import Testing
@testable import SlackSucker

@Suite("SlackdumpBinary")
struct BinaryResolutionTests {

    @Test("ensureExecutable sets the +x bit when missing")
    func ensureExecutableSetsBit() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss-chmod-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("slackdump")
        try Data("hi".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)

        SlackdumpBinary.ensureExecutable(at: target.path)
        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        #expect((perms & 0o111) != 0,
                "ensureExecutable must leave the +x bit set")
    }

    @Test("resolveFromBundle returns nil for a non-bundle URL")
    func resolveFromBundleNilForNonBundle() {
        // Bundle.main has no `slackdump` resource in the test runner; we
        // assert the function tolerates that without crashing.
        // (When the .app is the runtime host, the resource is present
        //  and a smoke test on the live app exercises that branch.)
        #expect(SlackdumpBinary.resolveFromBundle(Bundle.main) == nil)
    }
}
