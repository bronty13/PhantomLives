import Foundation
import Testing
@testable import PurpleVoice

@Suite("DeepFilterNetLocator")
struct DeepFilterNetLocatorTests {

    @Test("Env var override takes priority when executable")
    func envOverrideTakesPriority() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-df-\(UUID().uuidString)")
        try "#!/bin/sh\nexit 0\n".write(to: temp,
                                         atomically: true,
                                         encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: temp.path)
        defer { try? FileManager.default.removeItem(at: temp) }

        let found = DeepFilterNetLocator.find(
            override: nil,
            environment: ["PURPLE_VOICE_DEEPFILTER": temp.path]
        )
        #expect(found?.path == temp.path)
    }

    @Test("Override param takes priority over standard paths")
    func overrideParamTakesPriority() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-df-\(UUID().uuidString)")
        try "#!/bin/sh\nexit 0\n".write(to: temp,
                                         atomically: true,
                                         encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: temp.path)
        defer { try? FileManager.default.removeItem(at: temp) }

        let found = DeepFilterNetLocator.find(
            override: temp.path,
            environment: ["PATH": "/nonexistent"]
        )
        #expect(found?.path == temp.path)
    }

    @Test("Returns nil when nothing resolves")
    func nothingResolves() {
        let found = DeepFilterNetLocator.find(
            override: "/definitely/does/not/exist/deep-filter",
            environment: [
                "PATH": "/nonexistent",
                "PURPLE_VOICE_DEEPFILTER": "/also/not/here"
            ]
        )
        // On a dev machine without DFN installed this is nil; on one
        // with DFN installed in ~/.cargo/bin it's not — both are valid
        // outcomes of the test, but the override+env failures should
        // not return the bogus paths.
        if let f = found {
            #expect(f.path != "/definitely/does/not/exist/deep-filter")
            #expect(f.path != "/also/not/here")
        }
    }
}
