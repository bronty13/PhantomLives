import Foundation
import Testing
@testable import Ircle

/// Chat logging: filename sanitization, per-conversation paths, gated writes,
/// and the persisted toggle.
@MainActor
@Suite("Chat logging")
struct LoggingTests {

    private func tempService() -> LogService {
        let svc = LogService()
        svc.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-logs-\(UUID().uuidString)", isDirectory: true)
        return svc
    }

    @Test func safeSanitizesPathSeparatorsAndDots() {
        #expect(LogService.safe("#chan") == "#chan")
        #expect(LogService.safe("irc.libera.chat") == "irc.libera.chat")
        #expect(LogService.safe("a/b\\c:d") == "a_b_c_d")
        #expect(LogService.safe("..") == "_")
        #expect(LogService.safe("   ") == "_")
    }

    @Test func fileURLNestsNetworkThenTarget() {
        let svc = tempService()
        let url = svc.fileURL(network: "Libera", target: "#swift")
        #expect(url.lastPathComponent == "#swift.log")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Libera")
    }

    @Test func writeThenReadRoundTrips() {
        let svc = tempService()
        svc.enabled = true
        svc.log(network: "Libera", target: "#swift", line: "<bob> hi")
        svc.log(network: "Libera", target: "#swift", line: "<sue> yo")
        let text = LogFile.read(svc.fileURL(network: "Libera", target: "#swift"))
        #expect(text.contains("<bob> hi"))
        #expect(text.contains("<sue> yo"))
        #expect(text.contains("] <bob> hi"))   // timestamp prefix present
    }

    @Test func disabledLogIsANoOp() {
        let svc = tempService()
        svc.enabled = false
        svc.log(network: "Libera", target: "#swift", line: "should not write")
        #expect(!FileManager.default.fileExists(atPath: svc.fileURL(network: "Libera", target: "#swift").path))
    }

    @Test func scanFindsWrittenLogs() {
        let svc = tempService()
        svc.enabled = true
        svc.log(network: "Libera", target: "#swift", line: "a")
        svc.log(network: "OFTC", target: "#debian", line: "b")
        let found = LogFile.scan(svc.directory)
        #expect(found.count == 2)
        #expect(found.contains { $0.network == "Libera" && $0.target == "#swift" })
        #expect(found.contains { $0.network == "OFTC" && $0.target == "#debian" })
    }

    @Test func loggingDefaultsOffAndRoundTrips() throws {
        #expect(AppSettings().loggingEnabled == false)
        var s = AppSettings()
        s.loggingEnabled = true
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).loggingEnabled)
    }
}
