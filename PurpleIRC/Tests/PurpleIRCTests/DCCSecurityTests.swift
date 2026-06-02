import Foundation
import Testing
@testable import PurpleIRC

/// Validation of DCC-offered peer addresses. A DCC SEND/CHAT offer carries
/// the peer's IP, which the client dials when the user accepts — so an
/// unvalidated host is an SSRF primitive (make the client connect to an
/// attacker-chosen address). `validatedPeerHost` accepts only real IP
/// literals and rejects hostnames and non-routable abuse targets, while
/// still allowing RFC1918 ranges so on-LAN DCC keeps working.
@MainActor
@Suite("DCC peer-host validation")
struct DCCSecurityTests {

    private func service() -> DCCService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DCCSecurityTests-\(UUID().uuidString)", isDirectory: true)
        return DCCService(downloadsDir: dir)
    }

    @Test func acceptsRoutableIPv4FromIntegerAndDotted() {
        let svc = service()
        // 3232235521 == 192.168.0.1 (RFC1918 — the common LAN DCC case).
        #expect(svc.validatedPeerHost("3232235521") == "192.168.0.1")
        // 1.2.3.4 == 16909060 (public).
        #expect(svc.validatedPeerHost("16909060") == "1.2.3.4")
        // Dotted-quad literal accepted as-is.
        #expect(svc.validatedPeerHost("8.8.8.8") == "8.8.8.8")
        #expect(svc.validatedPeerHost("10.0.0.5") == "10.0.0.5")
    }

    @Test func rejectsLoopbackUnspecifiedAndLinkLocal() {
        let svc = service()
        #expect(svc.validatedPeerHost("2130706433") == nil)   // 127.0.0.1
        #expect(svc.validatedPeerHost("127.0.0.1") == nil)
        #expect(svc.validatedPeerHost("0") == nil)            // 0.0.0.0
        #expect(svc.validatedPeerHost("0.0.0.0") == nil)
        #expect(svc.validatedPeerHost("2851995649") == nil)   // 169.254.0.1 link-local
        #expect(svc.validatedPeerHost("169.254.10.10") == nil)
    }

    @Test func rejectsHostnamesAndGarbage() {
        let svc = service()
        // A bare hostname is the SSRF vector — must be refused outright.
        #expect(svc.validatedPeerHost("evil.example.com") == nil)
        #expect(svc.validatedPeerHost("localhost") == nil)
        #expect(svc.validatedPeerHost("not an ip") == nil)
        #expect(svc.validatedPeerHost("") == nil)
        // Out-of-range dotted octet.
        #expect(svc.validatedPeerHost("999.1.1.1") == nil)
    }

    @Test func ipv6LiteralsRoutableAcceptedLocalRejected() {
        let svc = service()
        #expect(svc.validatedPeerHost("2001:db8::1") == "2001:db8::1")
        #expect(svc.validatedPeerHost("::1") == nil)          // loopback
        #expect(svc.validatedPeerHost("::") == nil)           // unspecified
        #expect(svc.validatedPeerHost("fe80::1") == nil)      // link-local
    }
}
