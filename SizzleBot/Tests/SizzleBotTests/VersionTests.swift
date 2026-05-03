import Testing
@testable import SizzleBot

@Suite("AppVersion")
struct VersionTests {

    @Test("marketing version is non-empty and semver shaped")
    func marketingVersion() {
        let v = AppVersion.marketing
        #expect(!v.isEmpty)
        let parts = v.split(separator: ".")
        #expect(parts.count == 3, "Expected MAJOR.MINOR.PATCH, got \(v)")
        for part in parts {
            #expect(Int(part) != nil, "Non-numeric part '\(part)' in version \(v)")
        }
    }

    @Test("build number is a non-empty numeric string")
    func buildNumber() {
        let b = AppVersion.build
        #expect(!b.isEmpty)
        #expect(Int(b) != nil, "Build '\(b)' is not numeric")
    }

    @Test("display includes both marketing version and build")
    func displayContainsBoth() {
        #expect(AppVersion.display.contains(AppVersion.marketing))
        #expect(AppVersion.display.contains(AppVersion.build))
    }
}
