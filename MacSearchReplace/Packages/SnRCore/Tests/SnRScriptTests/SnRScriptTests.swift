import Testing
import Foundation
@testable import SnRScript

@Suite("SnRScript")
struct SnRScriptTests {

    @Test func roundTrip() throws {
        let script = SnRScript(
            name: "demo",
            roots: ["/tmp/x"],
            include: ["*.swift"],
            exclude: ["Pods/**"],
            steps: [
                .init(type: "literal", search: "foo", replace: "bar"),
                .init(type: "regex",   search: #"\bx\b"#, replace: "y", caseInsensitive: true)
            ]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("script-\(UUID().uuidString).snrscript")
        try script.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try SnRScript.load(from: url)
        #expect(loaded == script)
    }

    @Test func producesSpecs() {
        let script = SnRScript(
            name: "x",
            roots: ["/tmp"],
            steps: [.init(type: "regex", search: "a", replace: "b", caseInsensitive: true)]
        )
        let s = script.searchSpec(forStep: script.steps[0])
        #expect(s.kind == .regex)
        #expect(s.caseInsensitive)
        let r = script.replaceSpec(forStep: script.steps[0])
        #expect(r?.mode == .regex)
        #expect(r?.replacement == "b")
    }
}
