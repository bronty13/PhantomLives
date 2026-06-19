import Foundation
import Testing
import IRCKit
@testable import Ircle

/// The app-side DCC orchestration that's pure enough to unit-test: the
/// non-clobbering save-path logic and the offer/decline state. The actual
/// socket download (DCCDownload) is exercised by a manual two-client smoke test,
/// not here (sockets don't belong in unit tests).
@MainActor
@Suite("DCC transfer orchestration")
struct DCCTransferTests {

    private let dir = URL(fileURLWithPath: "/tmp/ircle-dcc-test")

    @Test func uniqueDestinationUsesBaseNameWhenFree() {
        let url = IrcleDCC.uniqueDestination(for: "photo.jpg", in: dir) { _ in false }
        #expect(url.lastPathComponent == "photo.jpg")
    }

    @Test func uniqueDestinationIncrementsWhenTaken() {
        // "photo.jpg" and "photo (1).jpg" exist; expect "photo (2).jpg".
        let taken: Set<String> = ["photo.jpg", "photo (1).jpg"]
        let url = IrcleDCC.uniqueDestination(for: "photo.jpg", in: dir) {
            taken.contains($0.lastPathComponent)
        }
        #expect(url.lastPathComponent == "photo (2).jpg")
    }

    @Test func uniqueDestinationHandlesNoExtension() {
        let taken: Set<String> = ["README"]
        let url = IrcleDCC.uniqueDestination(for: "README", in: dir) {
            taken.contains($0.lastPathComponent)
        }
        #expect(url.lastPathComponent == "README (1)")
    }

    @Test func uniqueDestinationReSanitizesName() {
        // Defense in depth: a traversal name can't escape `dir`.
        let url = IrcleDCC.uniqueDestination(for: "../../etc/passwd", in: dir) { _ in false }
        #expect(!url.lastPathComponent.contains(".."))
        #expect(!url.lastPathComponent.contains("/"))
        #expect(url.deletingLastPathComponent().path == dir.path)
    }

    @Test func addOfferRoutesSendToFilesAndChatToChats() {
        let dcc = IrcleDCC()
        dcc.addOffer(DCC.Offer(kind: .send, filename: "a.bin", host: "1.2.3.4", port: 5000, size: 100), from: "bob")
        dcc.addOffer(DCC.Offer(kind: .chat, filename: nil, host: "1.2.3.4", port: 5001, size: nil), from: "sue")
        #expect(dcc.items.count == 1)
        #expect(dcc.items.first?.filename == "a.bin")
        #expect(dcc.items.first?.peer == "bob")
        #expect(dcc.items.first?.state == .offered)
        #expect(dcc.chats.count == 1)
        #expect(dcc.chats.first?.peer == "sue")
        #expect(dcc.chats.first?.state == .offered)
    }

    @Test func declineChatAndClearRemovesIt() {
        let dcc = IrcleDCC()
        dcc.addOffer(DCC.Offer(kind: .chat, filename: nil, host: "1.2.3.4", port: 5001, size: nil), from: "sue")
        let chat = dcc.chats[0]
        dcc.declineChat(chat)
        #expect(chat.state == .declined)
        #expect(chat.state.isTerminal)
        dcc.clearFinished()
        #expect(dcc.chats.isEmpty)
    }

    @Test func sendChatBeforeConnectedIsIgnored() {
        let dcc = IrcleDCC()
        dcc.addOffer(DCC.Offer(kind: .chat, filename: nil, host: "1.2.3.4", port: 5001, size: nil), from: "sue")
        let chat = dcc.chats[0]
        dcc.sendChat(chat, "hello")          // still .offered → no local echo, no send
        #expect(chat.lines.isEmpty)
    }

    @Test func declineMovesOfferToTerminal() {
        let dcc = IrcleDCC()
        dcc.addOffer(DCC.Offer(kind: .send, filename: "a.bin", host: "1.2.3.4", port: 5000, size: 100), from: "bob")
        let item = dcc.items[0]
        dcc.decline(item)
        #expect(item.state == .declined)
        #expect(item.state.isTerminal)
        dcc.clearFinished()
        #expect(dcc.items.isEmpty)
    }
}
