import Testing
@testable import SnRCore

@Test func versionIsExposed() {
    #expect(!SnR.version.isEmpty)
}
