import Foundation
import Testing
@testable import IRCKit

/// DCC peer-host validation (SSRF guard), filename sanitization (path-traversal
/// guard), and offer parsing. Ported from PurpleIRC's DCCSecurityTests so the
/// one shared, audited copy carries the same anti-abuse coverage.
@Suite("DCC engine")
struct DCCTests {

    // MARK: - Peer-host validation

    @Test func acceptsRoutableIPv4FromIntegerAndDotted() {
        #expect(DCC.validatedPeerHost("3232235521") == "192.168.0.1")  // RFC1918 (LAN DCC)
        #expect(DCC.validatedPeerHost("16909060") == "1.2.3.4")        // public
        #expect(DCC.validatedPeerHost("8.8.8.8") == "8.8.8.8")
        #expect(DCC.validatedPeerHost("10.0.0.5") == "10.0.0.5")
    }

    @Test func rejectsLoopbackUnspecifiedAndLinkLocal() {
        #expect(DCC.validatedPeerHost("2130706433") == nil)   // 127.0.0.1
        #expect(DCC.validatedPeerHost("127.0.0.1") == nil)
        #expect(DCC.validatedPeerHost("0") == nil)            // 0.0.0.0
        #expect(DCC.validatedPeerHost("0.0.0.0") == nil)
        #expect(DCC.validatedPeerHost("2851995649") == nil)   // 169.254.0.1
        #expect(DCC.validatedPeerHost("169.254.10.10") == nil)
    }

    @Test func rejectsHostnamesAndGarbage() {
        #expect(DCC.validatedPeerHost("evil.example.com") == nil)
        #expect(DCC.validatedPeerHost("localhost") == nil)
        #expect(DCC.validatedPeerHost("not an ip") == nil)
        #expect(DCC.validatedPeerHost("") == nil)
        #expect(DCC.validatedPeerHost("999.1.1.1") == nil)
    }

    @Test func ipv4StringToIntValidatesOctets() {
        #expect(DCC.ipv4StringToInt("192.168.0.1") == 3_232_235_521)
        #expect(DCC.ipv4StringToInt("1.2.3.4") == 16_909_060)
        #expect(DCC.ipv4StringToInt("999.1.1.1") == 0)
        #expect(DCC.ipv4StringToInt("1.2.3") == 0)
        #expect(DCC.ipv4StringToInt("not.an.ip.addr") == 0)
    }

    @Test func ipv6LiteralsRoutableAcceptedLocalRejected() {
        #expect(DCC.validatedPeerHost("2001:db8::1") == "2001:db8::1")
        #expect(DCC.validatedPeerHost("::1") == nil)
        #expect(DCC.validatedPeerHost("::") == nil)
        #expect(DCC.validatedPeerHost("fe80::1") == nil)
    }

    // MARK: - Filename sanitization (path-traversal guard)

    @Test func sanitizeStripsTraversalAndSeparators() {
        // Plain names pass through unchanged.
        #expect(DCC.sanitizeFilename("photo.jpg") == "photo.jpg")
        // The security property: no separators or `..` can survive (so a name
        // can never escape the downloads dir), whatever the exact result is.
        for hostile in ["../../etc/passwd", "/abs/path/x.txt", "a/b\\c:d.bin", "..\\..\\win.ini"] {
            let safe = DCC.sanitizeFilename(hostile)
            #expect(!safe.contains(".."))
            #expect(!safe.contains("/"))
            #expect(!safe.contains("\\"))
            #expect(!safe.contains(":"))
        }
    }

    @Test func sanitizeRejectsEmptyDotAndControlChars() {
        #expect(DCC.sanitizeFilename("") == "dcc-file")
        #expect(DCC.sanitizeFilename("...") == "dcc-file")
        #expect(DCC.sanitizeFilename(".hidden") == "hidden")   // leading dots stripped
        let withControl = DCC.sanitizeFilename("a\u{0}b\u{7}c")
        #expect(!withControl.unicodeScalars.contains { $0.value < 0x20 })
    }

    // MARK: - Offer parsing

    @Test func parsesChatOffer() {
        guard case let .offer(o) = DCC.parseOffer("CHAT chat 16909060 5000") else {
            Issue.record("expected a chat offer"); return
        }
        #expect(o.kind == .chat)
        #expect(o.host == "1.2.3.4")
        #expect(o.port == 5000)
        #expect(o.filename == nil)
    }

    @Test func parsesSendOfferWithSizeAndSanitizedName() {
        guard case let .offer(o) = DCC.parseOffer("SEND ../secret.txt 16909060 5000 1024") else {
            Issue.record("expected a send offer"); return
        }
        #expect(o.kind == .send)
        #expect(o.filename?.hasSuffix("secret.txt") == true)        // name preserved
        #expect(o.filename?.contains("..") == false)                // traversal stripped
        #expect(o.host == "1.2.3.4")
        #expect(o.port == 5000)
        #expect(o.size == 1024)
    }

    @Test func quotedFilenameWithSpacesStaysOneToken() {
        guard case let .offer(o) = DCC.parseOffer("SEND \"my file.txt\" 16909060 5000 10") else {
            Issue.record("expected a send offer"); return
        }
        #expect(o.filename == "my file.txt")
    }

    @Test func unsafeAddressIsRejectedNotParsed() {
        #expect(DCC.parseOffer("CHAT chat 2130706433 5000") == .rejectedUnsafeAddress("2130706433")) // 127.0.0.1
        #expect(DCC.parseOffer("SEND x 0 5000 10") == .rejectedUnsafeAddress("0"))                    // 0.0.0.0
    }

    @Test func malformedOrUnknownIsUnsupported() {
        #expect(DCC.parseOffer("CHAT chat 16909060") == .unsupported)   // missing port
        #expect(DCC.parseOffer("RESUME x 5000 0") == .unsupported)      // not handled here
        #expect(DCC.parseOffer("") == .unsupported)
        #expect(DCC.parseOffer("SEND x 16909060 notaport 10") == .unsupported)
    }
}
